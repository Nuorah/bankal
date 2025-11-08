const std = @import("std");
const http_common = @import("http_common");
const Database = @import("database.zig").Database;
const card_module = @import("card.zig");
const Card = @import("card.zig").Card;
const CardCreateDTO = @import("card.zig").CardCreateDTO;
const CardUpdateDTO = @import("card.zig").CardUpdateDTO;

const index_html = @embedFile("static/index.html");
const style_css = @embedFile("static/style.css");
const script_js = @embedFile("static/script.js");
const alpine_js = @embedFile("static/alpine.min.js");

pub const std_options: std.Options = .{
    .log_level = .info,
};

const config: http_common.Server.ServerConfiguration = .{
    .port = 8080,
};

const Context = struct {
    db: Database,
    cards: std.ArrayList(Card),
    mutex: std.Thread.Mutex,
};

const MAX_REQUEST_BODY_SIZE = 8192;

const routes = [_]http_common.Router.Route(Context){
    .{ .method = .GET, .path = "/", .handler = handleStaticFile },
    .{ .method = .GET, .path = "/static", .handler = handleStaticFile, .match = .prefix },
    .{ .method = .PATCH, .path = "/api/cards/:id", .handler = handleUpdateCard, .match = .pattern },
    .{ .method = .GET, .path = "/api/cards", .handler = handleGetAllCards },
    .{ .method = .POST, .path = "/api/cards", .handler = handleCreateCard },
};

const app_router = http_common.Router.Router(Context, &routes);

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){}; // /!\ Thread safe allocator is very recommended
    defer _ = gpa.deinit();
    const main_allocator = gpa.allocator();

    var database: Database = .{
        .path = "kanban.db",
    };

    if (!database.exists()) {
        try database.initFile();
    }

    var context: Context = .{
        .db = database,
        .cards = try database.readAll(main_allocator),
        .mutex = .{},
    };
    defer context.cards.deinit(main_allocator);

    var shutdown = std.atomic.Value(bool).init(false); // For safe shutdown

    try http_common.Server.runServer(Context, main_allocator, config, &context, app_router.route, &shutdown);
}

fn handleStaticFile(
    _: std.mem.Allocator,
    _: std.mem.Allocator,
    _: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !void {
    const path = req.head.target;

    const content = if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html"))
        index_html
    else if (std.mem.eql(u8, path, "/static/style.css"))
        style_css
    else if (std.mem.eql(u8, path, "/static/script.js"))
        script_js
    else if (std.mem.eql(u8, path, "/static/alpine.min.js"))
        alpine_js
    else {
        try req.respond("Not found", .{ .status = .not_found });
        return;
    };

    const content_type = if (std.mem.endsWith(u8, path, ".html") or std.mem.eql(u8, path, "/"))
        "text/html; charset=utf-8"
    else if (std.mem.endsWith(u8, path, ".css"))
        "text/css; charset=utf-8"
    else if (std.mem.endsWith(u8, path, ".js"))
        "application/javascript"
    else
        "application/octet-stream";

    try req.respond(content, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = content_type },
        },
    });
}

pub fn handleGetAllCards(
    _: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !void {
    std.log.debug("GET /api/cards hit", .{});
    ctx.mutex.lock();
    // Convert cards to DTOs
    var dtos = try std.ArrayList(card_module.CardResponseDTO).initCapacity(arena_allocator, ctx.cards.items.len);
    for (ctx.cards.items) |card| {
        try dtos.append(arena_allocator, try card_module.toDTO(card, arena_allocator));
    }
    //We can free the lock now
    ctx.mutex.unlock();

    var allocating_writer: std.io.Writer.Allocating = .init(arena_allocator);
    defer allocating_writer.deinit();

    var json_writer: std.json.Stringify = .{
        .writer = &allocating_writer.writer,
        .options = .{ .whitespace = .minified },
    };

    try json_writer.write(dtos.items);

    // Get the bytes
    const json_bytes = allocating_writer.written();

    try req.respond(json_bytes, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

pub fn handleCreateCard(
    main_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !void {
    const body = try readBody(arena_allocator, req);

    const parsed = try std.json.parseFromSlice(CardCreateDTO, arena_allocator, body, .{});
    defer parsed.deinit();

    const card = try card_module.fromDTO(parsed.value);

    ctx.mutex.lock();
    defer ctx.mutex.unlock();

    // Write to file first
    var temp_list = try std.ArrayList(Card).initCapacity(arena_allocator, ctx.cards.items.len + 1);
    try temp_list.appendSlice(arena_allocator, ctx.cards.items);
    try temp_list.append(arena_allocator, card);
    try ctx.db.writeAll(temp_list.items);

    try ctx.cards.append(main_allocator, card);

    try req.respond("Created", .{
        .status = .created,
    });
}

pub fn handleUpdateCard(
    main_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    path_params: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !void {
    const id_str = path_params.get("id") orelse {
        try req.respond("Missing id path param", .{ .status = .bad_request });
        return;
    };

    const id = std.fmt.parseInt(u64, id_str, 10) catch |err| {
        std.log.debug("Wrong path param format: {}", .{err});
        try req.respond("Invalid id format", .{ .status = .bad_request });
        return;
    };

    const body = try readBody(arena_allocator, req);

    const parsed = try std.json.parseFromSlice(CardUpdateDTO, arena_allocator, body, .{});

    const card_update_dto: CardUpdateDTO = parsed.value;

    ctx.mutex.lock();

    defer ctx.mutex.unlock();

    var temp_cards = try ctx.cards.clone(arena_allocator);

    var card_to_update_index: ?usize = null;

    for (ctx.cards.items, 0..) |card, index| {
        if (id == card.id) {
            card_to_update_index = index;
            break;
        }
    }

    if (card_to_update_index == null) {
        try req.respond("Not Found", .{ .status = .not_found });
        return;
    }

    card_module.updateCardFromDTO(&temp_cards.items[card_to_update_index.?], card_update_dto) catch |err| switch (err) {
        error.TitleTooLong, error.DescriptionTooLong => {
            try req.respond("Bad request", .{ .status = .bad_request });
            return;
        },
    };

    //FIXME double clone
    try ctx.db.writeAll(temp_cards.items);

    ctx.cards.deinit(main_allocator);
    ctx.cards = try temp_cards.clone(main_allocator);

    try req.respond("", .{ .status = .no_content });
}

fn readBody(allocator: std.mem.Allocator, request: *std.http.Server.Request) ![]u8 {
    var body_buffer: [1024]u8 = undefined;
    const body_reader = try request.readerExpectContinue(&body_buffer);
    return try body_reader.allocRemaining(allocator, .limited(MAX_REQUEST_BODY_SIZE));
}
