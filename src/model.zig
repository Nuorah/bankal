const std = @import("std");

pub const Column = struct {
    const Self = @This();
    id: u8,
    name: []const u8,

    pub fn clone(self: Column, allocator: std.mem.Allocator) !Self {
        return Column{
            .id = self.id,
            .name = try allocator.dupe(u8, self.name),
        };
    }
};

pub const Card = struct {
    const Self = @This();

    id: u64,
    created_at: i64,
    updated_at: i64,
    column: u8,
    title: []const u8,
    description: []const u8,
    board_id: u8 = 0,
    code: []const u8,

    pub fn clone(self: Card, allocator: std.mem.Allocator) !Self {
        return Card{
            .id = self.id,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .column = self.column,
            .title = try allocator.dupe(u8, self.title),
            .description = try allocator.dupe(u8, self.description),
            .board_id = self.board_id,
            .code = try allocator.dupe(u8, self.code),
        };
    }
};

pub const Board = struct {
    const Self = @This();

    pub const default_columns: []const Column = &.{
        Column{ .id = 0, .name = "Backlog" },
        Column{ .id = 1, .name = "Design" },
        Column{ .id = 2, .name = "Ready" },
        Column{ .id = 3, .name = "Doing" },
        Column{ .id = 4, .name = "Review" },
        Column{ .id = 5, .name = "Done" },
    };

    id: u8,
    created_at: i64,
    updated_at: i64,
    next_card_number: u64,
    name: []const u8,
    code: []const u8,
    description: []const u8,
    columns: std.ArrayList(Column),

    pub fn initDefaultColumns(allocator: std.mem.Allocator) !std.ArrayList(Column) {
        var list: std.ArrayList(Column) = .empty;
        try list.appendSlice(allocator, default_columns);
        return list;
    }

    pub fn clone(self: Board, allocator: std.mem.Allocator) !Self {
        return Board{
            .id = self.id,
            .next_card_number = self.next_card_number,
            .name = try allocator.dupe(u8, self.name),
            .code = try allocator.dupe(u8, self.code),
            .description = try allocator.dupe(u8, self.description),
            .columns = try self.columns.clone(allocator),
        };
    }
};

pub const User = struct {
    const Self = @This();

    id: u64,
    created_at: i64,
    updated_at: i64,
    name: []const u8,
    board_order: ?std.ArrayList(u8),
};
