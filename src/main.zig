const std = @import("std");
const http_common = @import("http_common");
const Database = @import("database.zig").Database;
const db = @import("db.zig");
const card_module = @import("card.zig");
const Card = @import("card.zig").Card;
const CardCreateDTO = @import("card.zig").CreationDTO;
const CardUpdateDTO = @import("card.zig").CardUpdateDTO;
const board = @import("board.zig");

const index_html = @embedFile("static/index.html");
const style_css = @embedFile("static/style.css");
const bundle_js = @embedFile("static/dist/bundle.min.js");

pub const std_options: std.Options = .{
    .log_level = .info,
};

const config: http_common.Server.ServerConfiguration = .{
    .port = 8080,
};

const Context = struct {
    db: db.Database,
    card_storage: *db.Storage(Card),
    board_storage: *db.Storage(board.Board),
};

const MAX_REQUEST_BODY_SIZE = 8192;

const routes = [_]http_common.Router.Route(Context){
    .{ .method = .GET, .path = "/", .handler = handleStaticFile },
    .{ .method = .GET, .path = "/health", .handler = handleHealthCheck },
    .{ .method = .GET, .path = "/static", .handler = handleStaticFile, .match = .prefix },

    .{ .method = .PATCH, .path = "/api/cards/:id", .handler = handleUpdateCard, .match = .pattern },
    .{ .method = .GET, .path = "/api/cards", .handler = handleGetAllCards },
    .{ .method = .POST, .path = "/api/cards", .handler = handleCreateCard },

    .{ .method = .GET, .path = "/api/boards", .handler = handleGetAllBoards },
    .{ .method = .GET, .path = "/api/boards/:id/cards", .handler = handleGetAllBoardCards, .match = .pattern },
    .{ .method = .POST, .path = "/api/boards", .handler = handleCreateBoard },
};

const app_router = http_common.Router.Router(Context, &routes);

pub fn main() !void {
    const start_time = std.time.nanoTimestamp();

    var gpa = std.heap.GeneralPurposeAllocator(.{ .thread_safe = true }){}; // /!\ Thread safe allocator is very recommended
    defer _ = gpa.deinit();
    const main_allocator = gpa.allocator();

    var card_storage = db.Storage(Card).init(main_allocator);
    var board_storage = db.Storage(board.Board).init(main_allocator);

    var database = db.Database{ .wal_path = "kanban.wal" };

    try database.load(main_allocator, .{ &card_storage, &board_storage });
    if (board_storage.entities.get(0)) |_| {} else {
        try database.append(board.Board, board.Board{
            .code = "MAIN",
            .description = "Main, default board",
            .id = 0,
            .name = "Main",
            .next_card_number = 1,
        }, main_allocator, &board_storage);
    }
    var context: Context = .{
        .card_storage = &card_storage,
        .board_storage = &board_storage,
        .db = database,
    };

    var shutdown = std.atomic.Value(bool).init(false); // For safe shutdown

    const elapsed_ms = @as(f64, @floatFromInt(std.time.nanoTimestamp() - start_time)) / 1_000_000.0;
    std.log.info("Server loaded in {d:.2}ms, starting listener on port {}", .{ elapsed_ms, config.port });

    try http_common.Server.runServer(Context, main_allocator, config, &context, app_router.route, &shutdown);
}

fn handleHealthCheck(
    _: std.mem.Allocator,
    _: std.mem.Allocator,
    _: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !void {
    try req.respond("", .{});
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
    else if (std.mem.eql(u8, path, "/static/dist/bundle.min.js"))
        bundle_js
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
    var allocating_writer: std.io.Writer.Allocating = .init(arena_allocator);
    defer allocating_writer.deinit();

    var json_writer: std.json.Stringify = .{
        .writer = &allocating_writer.writer,
        .options = .{ .emit_strings_as_arrays = false, .whitespace = .minified },
    };

    var list: std.ArrayList(card_module.CardResponseDTO) = .empty;
    ctx.card_storage.mutex.lock();
    defer ctx.card_storage.mutex.unlock();
    var iter = ctx.card_storage.entities.valueIterator();
    while (iter.next()) |entity| {
        try list.append(arena_allocator, try card_module.toResponseDTO(arena_allocator, entity.*));
    }

    try json_writer.write(list.items);

    // Get the bytes
    const json_bytes = allocating_writer.written();

    try req.respond(json_bytes, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

pub fn handleGetAllBoards(
    _: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !void {
    var allocating_writer: std.io.Writer.Allocating = .init(arena_allocator);
    defer allocating_writer.deinit();

    var json_writer: std.json.Stringify = .{
        .writer = &allocating_writer.writer,
        .options = .{ .emit_strings_as_arrays = false, .whitespace = .minified },
    };

    var list: std.ArrayList(board.BoardResponseDTO) = .empty;
    ctx.board_storage.mutex.lock();
    defer ctx.board_storage.mutex.unlock();
    var iter = ctx.board_storage.entities.valueIterator();
    while (iter.next()) |entity| {
        try list.append(arena_allocator, try board.toResponseDTO(arena_allocator, entity.*));
    }

    try json_writer.write(list.items);

    // Get the bytes
    const json_bytes = allocating_writer.written();

    try req.respond(json_bytes, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

pub fn handleGetAllBoardCards(
    _: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    path_params: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !void {
    var allocating_writer: std.io.Writer.Allocating = .init(arena_allocator);
    defer allocating_writer.deinit();

    var json_writer: std.json.Stringify = .{
        .writer = &allocating_writer.writer,
        .options = .{ .emit_strings_as_arrays = false, .whitespace = .minified },
    };

    const id_str = path_params.get("id") orelse {
        try req.respond("Missing id path param", .{ .status = .bad_request });
        return;
    };

    const id = std.fmt.parseInt(u64, id_str, 10) catch |err| {
        std.log.debug("Error parsing id: {}", .{err});
        try req.respond("Invalid id format", .{ .status = .bad_request });
        return;
    };

    var list: std.ArrayList(card_module.CardResponseDTO) = .empty;
    ctx.card_storage.mutex.lock();
    defer ctx.card_storage.mutex.unlock();
    var iter = ctx.card_storage.entities.valueIterator();
    while (iter.next()) |entity| {
        if (entity.board_id == id) {
            try list.append(arena_allocator, try card_module.toResponseDTO(arena_allocator, entity.*));
        }
    }

    try json_writer.write(list.items);

    // Get the bytes
    const json_bytes = allocating_writer.written();

    try req.respond(json_bytes, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = "application/json" },
        },
    });
}

pub fn handleCreateBoard(
    main_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !void {
    const body = try readBody(arena_allocator, req);

    const parsed = try std.json.parseFromSlice(board.BoardCreateDTO, arena_allocator, body, .{});
    defer parsed.deinit();

    var iter = ctx.board_storage.entities.valueIterator();
    var id: u8 = 0;

    while (iter.next()) |board_entity| {
        if (board_entity.id > id) id = board_entity.id;
    }

    id = id + 1;

    const board_entity = try board.fromCreateDTO(main_allocator, parsed.value, id);

    try ctx.db.append(board.Board, board_entity, main_allocator, ctx.board_storage);

    try req.respond("Created", .{
        .status = .created,
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

    var board_entity = ctx.board_storage.entities.get(parsed.value.board_id) orelse return error.InvalidBoard;
    const card = try card_module.fromDTO(main_allocator, parsed.value, board_entity);
    board_entity.next_card_number += 1;
    try ctx.db.append(board.Board, board_entity, main_allocator, ctx.board_storage);

    try ctx.db.append(Card, card, main_allocator, ctx.card_storage);

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
        std.log.debug("Error parsing id: {}", .{err});
        try req.respond("Invalid id format", .{ .status = .bad_request });
        return;
    };

    const body = try readBody(arena_allocator, req);

    const parsed = try std.json.parseFromSlice(CardUpdateDTO, arena_allocator, body, .{ .ignore_unknown_fields = true });

    var board_entity: ?board.Board = null;

    if (parsed.value.board_id) |board_id| {
        board_entity = ctx.board_storage.entities.get(board_id) orelse return error.InvalidBoard;
        board_entity.?.next_card_number += 1;
        try ctx.db.append(board.Board, board_entity.?, main_allocator, ctx.board_storage);
    }

    ctx.card_storage.mutex.lock();
    errdefer ctx.card_storage.mutex.unlock();
    var card = ctx.card_storage.entities.get(id) orelse {
        try req.respond("Not found in storage", .{ .status = .not_found });
        return;
    };

    const updated_card = try card_module.updateCardFromDTO(main_allocator, &card, parsed.value, board_entity);

    try ctx.db.append(Card, updated_card.*, main_allocator, ctx.card_storage);
    ctx.card_storage.mutex.unlock();

    try req.respond("", .{ .status = .no_content });
}

fn readBody(allocator: std.mem.Allocator, request: *std.http.Server.Request) ![]u8 {
    var body_buffer: [1024]u8 = undefined;
    const body_reader = try request.readerExpectContinue(&body_buffer);
    return try body_reader.allocRemaining(allocator, .limited(MAX_REQUEST_BODY_SIZE));
}
