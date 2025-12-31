// Event-sourced storage layer
// All state changes are persisted as events in append-only WAL
// Current state is rebuilt by replaying all events on startup

const std = @import("std");
const model = @import("model.zig");
const event = @import("event.zig");
const event_wal = @import("event_wal");

pub fn Storage(comptime T: type) type {
    return event_wal.Storage(u64, T);
}

const Wal = event_wal.Wal(event.Event);

pub const Database = struct {
    const Self = @This();

    wal: Wal,

    pub fn init(wal_path: []const u8) !Database {
        return .{
            .wal = try Wal.init(wal_path),
        };
    }

    pub fn deinit(self: *Database) void {
        self.wal.deinit();
    }

    // Not thread safe, to use at launch or lock storage mutex around it
    pub fn loadEvent(
        allocator: std.mem.Allocator,
        event_to_load: event.Event,
        card_storage: *Storage(model.Card),
        board_storage: *Storage(model.Board),
        user_storage: *Storage(model.User),
    ) !void {
        switch (event_to_load.data) {
            .user_created => |payload| {
                const user = model.User{
                    .id = 0,
                    .name = try allocator.dupe(u8, payload.name),
                    .board_order = null,
                    .created_at = event_to_load.timestamp,
                    .updated_at = event_to_load.timestamp,
                };

                try user_storage.entities.put(user.id, user);
            },
            .card_created => |payload| {
                const board_to_update = board_storage.entities.getPtr(payload.board_id) orelse return error.BoardNotFound;
                const code = try std.fmt.allocPrint(allocator, "{s}-{d}", .{ board_to_update.code, board_to_update.next_card_number });
                errdefer allocator.free(code);

                const card = model.Card{
                    .id = payload.id,
                    .code = code,
                    .title = try allocator.dupe(u8, payload.title),
                    .description = try allocator.dupe(u8, payload.description),
                    .created_at = event_to_load.timestamp,
                    .updated_at = event_to_load.timestamp,
                    .board_id = payload.board_id,
                    .column = payload.column,
                };

                board_to_update.next_card_number = board_to_update.next_card_number + 1;
                board_to_update.updated_at = event_to_load.timestamp;

                try card_storage.entities.put(card.id, card);
            },
            .card_updated => |payload| {
                const card_to_update = card_storage.entities.getPtr(payload.id) orelse return error.CardNotFound;

                const new_desc = try allocator.dupe(u8, payload.description);
                errdefer allocator.free(new_desc);

                const new_title = try allocator.dupe(u8, payload.title);
                errdefer allocator.free(new_title);

                allocator.free(card_to_update.description);
                allocator.free(card_to_update.title);

                card_to_update.description = new_desc;
                card_to_update.title = new_title;
                card_to_update.updated_at = event_to_load.timestamp;
            },
            .card_moved_column => |payload| {
                const card_to_update = card_storage.entities.getPtr(payload.id) orelse return error.CardNotFound;

                card_to_update.column = payload.column;
                card_to_update.updated_at = event_to_load.timestamp;
            },
            .card_moved_board => |payload| {
                const card_to_update = card_storage.entities.getPtr(payload.card_id) orelse return error.CardNotFound;
                const board_to_update = board_storage.entities.getPtr(payload.board_id) orelse return error.BoardNotFound;

                const new_code = try std.fmt.allocPrint(allocator, "{s}-{d}", .{ board_to_update.code, board_to_update.next_card_number });
                errdefer allocator.free(new_code);

                allocator.free(card_to_update.code);

                card_to_update.column = 0;
                card_to_update.board_id = payload.board_id;
                card_to_update.code = new_code;
                card_to_update.updated_at = event_to_load.timestamp;
                board_to_update.next_card_number = board_to_update.next_card_number + 1;
                board_to_update.updated_at = event_to_load.timestamp;
            },
            .board_created => |payload| {

                // Find a free id
                var id: u8 = 0;
                while (board_storage.entities.get(id)) |_| {
                    id += 1;
                }

                const board = model.Board{
                    .id = id,
                    .created_at = event_to_load.timestamp,
                    .updated_at = event_to_load.timestamp,
                    .code = try allocator.dupe(u8, payload.code),
                    .name = try allocator.dupe(u8, payload.name),
                    .description = try allocator.dupe(u8, payload.description),
                    .columns = try model.Board.initDefaultColumns(allocator),
                    .next_card_number = 1,
                };

                try board_storage.entities.put(board.id, board);
            },
        }
    }

    pub fn loadAllEvents(
        self: *Self,
        allocator: std.mem.Allocator,
        card_storage: *Storage(model.Card),
        board_storage: *Storage(model.Board),
        user_storage: *Storage(model.User),
    ) !void {
        var reader_buffer: [4096]u8 = undefined;
        var reader = self.wal.reader(&reader_buffer);

        while (try reader.interface.takeDelimiter('\n')) |line| {
            if (line.len == 0) continue;

            const event_to_load = std.json.parseFromSlice(event.Event, allocator, line, .{ .ignore_unknown_fields = true }) catch |err| {
                std.log.err("Failed to parse event, invalid data, aborting: {}", .{err});
                return err;
            };

            defer event_to_load.deinit();

            try loadEvent(allocator, event_to_load.value, card_storage, board_storage, user_storage);
        }
    }

    pub fn appendEvent(
        self: *Self,
        main_allocator: std.mem.Allocator,
        arena_allocator: std.mem.Allocator,
        event_to_append: event.Event,
        card_storage: *Storage(model.Card),
        board_storage: *Storage(model.Board),
        user_storage: *Storage(model.User),
    ) !void {
        board_storage.mutex.lock();
        defer board_storage.mutex.unlock();
        card_storage.mutex.lock();
        defer card_storage.mutex.unlock();

        try self.wal.append(arena_allocator, event_to_append);

        try loadEvent(main_allocator, event_to_append, card_storage, board_storage, user_storage);
    }
};
