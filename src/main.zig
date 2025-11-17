// Bankal - Event-sourced Kanban Board
// Single-user personal kanban with CQRS/ES architecture
// Embeds static assets, event-sourced persistence via WAL
// Designed for localhost or behind reverse proxy (no built-in auth)

const std = @import("std");
const http_common = @import("http_common");
const db = @import("db.zig");
const event = @import("event.zig");
const dto = @import("dto.zig");
const model = @import("model.zig");

const Response = @import("http_common").Router.Response;

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
    card_storage: *db.Storage(model.Card),
    board_storage: *db.Storage(model.Board),
    user_storage: *db.Storage(model.User),
};

const MAX_REQUEST_BODY_SIZE = 8192;

const routes = [_]http_common.Router.Route(Context){
    .{ .method = .GET, .path = "/", .handler = handleStaticFile },
    .{ .method = .GET, .path = "/health", .handler = handleHealthCheck },
    .{ .method = .GET, .path = "/static", .handler = handleStaticFile, .match = .prefix },

    .{ .method = .PATCH, .path = "/api/cards/:id", .handler = handleUpdateCard, .match = .pattern },
    .{ .method = .PATCH, .path = "/api/cards/:id/column", .handler = handleUpdateCardColumn, .match = .pattern },
    .{ .method = .PATCH, .path = "/api/cards/:id/board", .handler = handleUpdateCardBoard, .match = .pattern },
    .{ .method = .GET, .path = "/api/cards", .handler = handleGetAllCards },
    .{ .method = .POST, .path = "/api/cards", .handler = handleCreateCard },

    .{ .method = .GET, .path = "/api/boards", .handler = handleGetAllBoards },
    .{ .method = .GET, .path = "/api/boards/:id/cards", .handler = handleGetAllBoardCards, .match = .pattern },
    .{ .method = .POST, .path = "/api/boards", .handler = handleCreateBoard },

    .{ .method = .GET, .path = "/api/user", .handler = handleGetUser },
};

const app_router = http_common.Router.Router(Context, &routes);

pub fn main() !void {
    std.log.info("Starting server", .{});
    const start_time = std.time.nanoTimestamp();

    const main_allocator = std.heap.c_allocator;

    var card_storage = db.Storage(model.Card).init(main_allocator);
    var board_storage = db.Storage(model.Board).init(main_allocator);
    var user_storage = db.Storage(model.User).init(main_allocator);

    var database = try db.Database.init("kanban.wal");
    defer database.deinit();

    try database.loadAllEvents(main_allocator, &card_storage, &board_storage, &user_storage);
    if (board_storage.entities.get(0)) |_| {} else {
        const create_main_board: event.Event = .{
            .timestamp = std.time.timestamp(),
            .data = .{
                .board_created = .{
                    .code = "MAIN",
                    .description = "Main board",
                    .name = "Main",
                },
            },
        };

        try database.appendEvent(
            main_allocator,
            main_allocator,
            create_main_board,
            &card_storage,
            &board_storage,
            &user_storage,
        );
    }

    // After loading events
    if (user_storage.entities.get(0)) |_| {} else {
        const create_default_user: event.Event = .{
            .timestamp = std.time.timestamp(),
            .data = .{
                .user_created = .{
                    .id = 0,
                    .name = "Default User",
                },
            },
        };
        try database.appendEvent(
            main_allocator,
            main_allocator,
            create_default_user,
            &card_storage,
            &board_storage,
            &user_storage,
        );
    }

    var context: Context = .{
        .card_storage = &card_storage,
        .board_storage = &board_storage,
        .user_storage = &user_storage,
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
    _: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    return Response{
        .body = "",
        .status = .ok,
    };
}

fn handleStaticFile(
    _: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    _: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    const path = req.head.target;

    const content = if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/index.html"))
        index_html
    else if (std.mem.eql(u8, path, "/static/style.css"))
        style_css
    else if (std.mem.eql(u8, path, "/static/dist/bundle.min.js"))
        bundle_js
    else {
        return Response{
            .body = "Not found",
            .status = .not_found,
        };
    };

    const content_type = if (std.mem.endsWith(u8, path, ".html") or std.mem.eql(u8, path, "/"))
        "text/html; charset=utf-8"
    else if (std.mem.endsWith(u8, path, ".css"))
        "text/css; charset=utf-8"
    else if (std.mem.endsWith(u8, path, ".js"))
        "application/javascript"
    else
        "application/octet-stream";

    const headers_on_stack = &[_]std.http.Header{
        .{ .name = "content-type", .value = content_type },
    };

    return Response{
        .body = content,
        .status = .ok,
        .extra_headers = try arena_allocator.dupe(std.http.Header, headers_on_stack),
    };
}

pub fn handleGetAllCards(
    _: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    _: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    var allocating_writer: std.io.Writer.Allocating = .init(arena_allocator);
    defer allocating_writer.deinit();

    var json_writer: std.json.Stringify = .{
        .writer = &allocating_writer.writer,
        .options = .{ .emit_strings_as_arrays = false, .whitespace = .minified },
    };

    var list: std.ArrayList(dto.Card) = .empty;
    ctx.card_storage.mutex.lock();
    defer ctx.card_storage.mutex.unlock();
    var iter = ctx.card_storage.entities.valueIterator();
    while (iter.next()) |entity| {
        try list.append(arena_allocator, try dto.Card.toDTO(arena_allocator, entity.*));
    }

    try json_writer.write(list.items);
    try json_writer.writer.flush();

    const json_bytes = allocating_writer.written();
    return Response.json(try arena_allocator.dupe(u8, json_bytes));
}

pub fn handleUpdateCardColumn(
    main_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    path_params: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    const id = try parseCardId(path_params);

    const card = ctx.card_storage.entities.get(id) orelse {
        return Response{
            .body = "Card not found",
            .status = .not_found,
        };
    };

    const body = try readBody(arena_allocator, req);
    const parsed = try std.json.parseFromSlice(dto.CardUpdateColumn, arena_allocator, body, .{});
    defer parsed.deinit();

    // Idempotency check
    if (card.column == parsed.value.column) {
        return Response{
            .body = "",
            .status = .no_content,
        };
    }

    const evt = event.Event{
        .timestamp = std.time.timestamp(),
        .data = .{
            .card_moved_column = .{
                .id = id,
                .column = parsed.value.column,
            },
        },
    };

    try ctx.db.appendEvent(main_allocator, arena_allocator, evt, ctx.card_storage, ctx.board_storage, ctx.user_storage);
    return Response{
        .body = "",
        .status = .no_content,
    };
}

pub fn handleUpdateCardBoard(
    main_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    path_params: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    const id = try parseCardId(path_params);

    const card = ctx.card_storage.entities.get(id) orelse {
        return Response{
            .body = "Card not found",
            .status = .not_found,
        };
    };

    const body = try readBody(arena_allocator, req);
    const parsed = try std.json.parseFromSlice(dto.CardUpdateBoard, arena_allocator, body, .{});
    defer parsed.deinit();

    // Check target board exists
    _ = ctx.board_storage.entities.get(parsed.value.board_id) orelse {
        return Response{
            .body = "Board not found",
            .status = .not_found,
        };
    };

    // Idempotency check
    if (card.board_id == parsed.value.board_id) {
        return Response{
            .body = "",
            .status = .no_content,
        };
    }

    const evt = event.Event{
        .timestamp = std.time.timestamp(),
        .data = .{
            .card_moved_board = .{
                .card_id = id,
                .board_id = parsed.value.board_id,
            },
        },
    };

    try ctx.db.appendEvent(main_allocator, arena_allocator, evt, ctx.card_storage, ctx.board_storage, ctx.user_storage);
    return Response{
        .body = "",
        .status = .no_content,
    };
}

pub fn handleGetAllBoards(
    _: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    _: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    var allocating_writer: std.io.Writer.Allocating = .init(arena_allocator);

    var json_writer: std.json.Stringify = .{
        .writer = &allocating_writer.writer,
        .options = .{ .emit_strings_as_arrays = false, .whitespace = .minified },
    };

    var list: std.ArrayList(dto.Board) = .empty;
    ctx.board_storage.mutex.lock();
    defer ctx.board_storage.mutex.unlock();
    var iter = ctx.board_storage.entities.valueIterator();
    while (iter.next()) |entity| {
        try list.append(arena_allocator, try dto.Board.toDTO(arena_allocator, entity.*));
    }

    try json_writer.write(list.items);

    // Get the bytes
    const json_bytes = allocating_writer.written();

    return Response.json(try arena_allocator.dupe(u8, json_bytes));
}

pub fn handleGetAllBoardCards(
    _: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    _: *std.http.Server.Request,
    path_params: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    var allocating_writer: std.io.Writer.Allocating = .init(arena_allocator);
    defer allocating_writer.deinit();

    var json_writer: std.json.Stringify = .{
        .writer = &allocating_writer.writer,
        .options = .{ .emit_strings_as_arrays = false, .whitespace = .minified },
    };

    const id_str = path_params.get("id") orelse {
        return Response{
            .body = "Missing id path param",
            .status = .bad_request,
        };
    };

    const id = std.fmt.parseInt(u64, id_str, 10) catch |err| {
        std.log.debug("Error parsing id: {}", .{err});
        return Response{
            .body = "Invalid id format",
            .status = .bad_request,
        };
    };

    var list: std.ArrayList(dto.Card) = .empty;
    ctx.card_storage.mutex.lock();
    defer ctx.card_storage.mutex.unlock();
    var iter = ctx.card_storage.entities.valueIterator();
    while (iter.next()) |entity| {
        if (entity.board_id == id) {
            try list.append(arena_allocator, try dto.Card.toDTO(arena_allocator, entity.*));
        }
    }

    try json_writer.write(list.items);

    // Get the bytes
    const json_bytes = allocating_writer.written();

    return Response.json(try arena_allocator.dupe(u8, json_bytes));
}

pub fn handleCreateBoard(
    main_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    const body = try readBody(arena_allocator, req);

    const parsed = try std.json.parseFromSlice(dto.BoardCreate, arena_allocator, body, .{});
    defer parsed.deinit();

    // Create event
    const evt = event.Event{
        .timestamp = std.time.timestamp(),
        .data = .{
            .board_created = .{
                .name = parsed.value.name,
                .code = parsed.value.code,
                .description = parsed.value.description,
            },
        },
    };

    try ctx.db.appendEvent(main_allocator, arena_allocator, evt, ctx.card_storage, ctx.board_storage, ctx.user_storage);
    return Response{
        .body = "Created",
        .status = .created,
    };
}

pub fn handleCreateCard(
    main_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    const body = try readBody(arena_allocator, req);

    const parsed = try std.json.parseFromSlice(dto.CardCreate, arena_allocator, body, .{});
    defer parsed.deinit();

    var uuid_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&uuid_bytes);
    uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x40;
    uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80;
    const card_id = std.mem.readInt(u64, uuid_bytes[0..8], .little);

    const evt = event.Event{
        .timestamp = std.time.timestamp(),
        .data = .{
            .card_created = .{
                .id = card_id,
                .board_id = parsed.value.board_id,
                .column = parsed.value.column,
                .title = parsed.value.title,
                .description = parsed.value.description,
            },
        },
    };

    ctx.db.appendEvent(main_allocator, arena_allocator, evt, ctx.card_storage, ctx.board_storage, ctx.user_storage) catch |err| {
        if (err == error.BoardNotFound) {
            return Response{
                .body = "Board not found",
                .status = .not_found,
            };
        }
        std.log.err("Unexpected error: {}", .{err});
        return Response{
            .body = "Internal server error",
            .status = .internal_server_error,
        };
    };
    return Response{
        .body = "Created",
        .status = .created,
    };
}

pub fn handleUpdateCard(
    main_allocator: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    path_params: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    const id = try parseCardId(path_params);

    _ = ctx.card_storage.entities.get(id) orelse {
        return Response{
            .body = "Card not found",
            .status = .not_found,
        };
    };

    const body = try readBody(arena_allocator, req);
    const parsed = try std.json.parseFromSlice(dto.CardUpdate, arena_allocator, body, .{});
    defer parsed.deinit();

    const evt = event.Event{
        .timestamp = std.time.timestamp(),
        .data = .{
            .card_updated = .{
                .id = id,
                .title = parsed.value.title,
                .description = parsed.value.description,
            },
        },
    };

    try ctx.db.appendEvent(main_allocator, arena_allocator, evt, ctx.card_storage, ctx.board_storage, ctx.user_storage);
    return Response{
        .body = "",
        .status = .no_content,
    };
}

fn handleGetUser(
    _: std.mem.Allocator,
    arena_allocator: std.mem.Allocator,
    ctx: *Context,
    req: *std.http.Server.Request,
    _: std.StringHashMap([]const u8),
    _: std.StringHashMap([]const u8),
) !Response {
    var allocating_writer: std.io.Writer.Allocating = .init(arena_allocator);
    defer allocating_writer.deinit();

    var json_writer: std.json.Stringify = .{
        .writer = &allocating_writer.writer,
        .options = .{ .emit_strings_as_arrays = false, .whitespace = .minified },
    };

    const id = try parseUserId(req);

    const user = ctx.user_storage.entities.get(id) orelse {
        return Response{
            .body = "User not found",
            .status = .not_found,
        };
    };

    const user_dto = try dto.User.toDTO(arena_allocator, user);

    try json_writer.write(user_dto);

    const json_bytes = allocating_writer.written();

    return Response.json(try arena_allocator.dupe(u8, json_bytes));
}

//Helper functions
fn readBody(allocator: std.mem.Allocator, request: *std.http.Server.Request) ![]u8 {
    var body_buffer: [1024]u8 = undefined;
    const body_reader = try request.readerExpectContinue(&body_buffer);
    return try body_reader.allocRemaining(allocator, .limited(MAX_REQUEST_BODY_SIZE));
}

fn parseCardId(path_params: std.StringHashMap([]const u8)) !u64 {
    const id_str = path_params.get("id") orelse return error.MissingId;
    return std.fmt.parseInt(u64, id_str, 10) catch return error.InvalidId;
}

fn parseUserId(_: *std.http.Server.Request) !u64 {
    // Single-user app, hardcoded to user 0
    // TODO add proper auth and multi user
    return 0;
}
