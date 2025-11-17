const std = @import("std");
const model = @import("model.zig");

pub const Card = struct {
    id: []const u8,
    created_at: i64,
    updated_at: i64,
    column: u8,
    title: []const u8,
    description: []const u8,
    board_id: u8,
    code: []const u8,

    pub fn toDTO(allocator: std.mem.Allocator, card: model.Card) !Card {
        return Card{
            .id = try std.fmt.allocPrint(allocator, "{d}", .{card.id}),
            .created_at = card.created_at,
            .updated_at = card.updated_at,
            .column = card.column,
            .title = try allocator.dupe(u8, card.title),
            .description = try allocator.dupe(u8, card.description),
            .board_id = card.board_id,
            .code = try allocator.dupe(u8, card.code),
        };
    }
};

pub const CardCreate = struct {
    board_id: u8,
    column: u8,
    title: []const u8,
    description: []const u8,
};

pub const CardUpdateColumn = struct {
    column: u8,
};

pub const CardUpdateBoard = struct {
    board_id: u8,
};

pub const CardUpdate = struct {
    title: []const u8,
    description: []const u8,
};

pub const Board = struct {
    pub const Self = @This();

    id: u8,
    name: []const u8,
    code: []const u8,
    description: []const u8,
    columns: []const model.Column,

    pub fn toDTO(allocator: std.mem.Allocator, board: model.Board) !Self {
        return Self{
            .id = board.id,
            .name = try allocator.dupe(u8, board.name),
            .code = try allocator.dupe(u8, board.code),
            .description = try allocator.dupe(u8, board.description),
            .columns = (try board.columns.clone(allocator)).items,
        };
    }

    pub fn fromDTO(self: Self, allocator: std.mem.Allocator) !Board {
        const columns: std.ArrayList(model.Column) = .empty;
        try columns.appendSlice(allocator, self.columns);
        return Board{
            .id = self.id,
            .name = self.name,
            .code = self.code,
            .description = self.description,
            .colums = columns,
        };
    }
};

pub const BoardCreate = struct {
    name: []const u8,
    code: []const u8,
    description: []const u8,
};

//User dtos
pub const User = struct {
    pub const Self = @This();

    id: []const u8,
    board_order: ?[]const u8,

    pub fn toDTO(allocator: std.mem.Allocator, user: model.User) !Self {
        var board_order: ?[]const u8 = null;
        if (user.board_order) |order| {
            board_order = try allocator.dupe(u8, order.items);
        }
        return Self{
            .id = try std.fmt.allocPrint(allocator, "{d}", .{user.id}),
            .board_order = board_order,
        };
    }
};
