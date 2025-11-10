const std = @import("std");

pub const Board = struct {
    const Self = @This();
    pub const TYPE_NAME = "board";

    id: u8,
    next_card_number: u64,
    name: []const u8,
    code: []const u8,
    description: []const u8,

    pub fn clone(self: Board, allocator: std.mem.Allocator) !Self {
        return Board{
            .id = self.id,
            .next_card_number = self.next_card_number,
            .name = try allocator.dupe(u8, self.name),
            .code = try allocator.dupe(u8, self.code),
            .description = try allocator.dupe(u8, self.description),
        };
    }
};

pub const BoardCreateDTO = struct {
    name: []const u8,
    code: []const u8,
    description: []const u8,
};

pub const BoardUpdateDTO = struct {
    name: ?[]const u8 = null,
    code: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

pub const BoardResponseDTO = struct {
    id: u8,
    name: []const u8,
    code: []const u8,
    description: []const u8,
};

pub fn toResponseDTO(allocator: std.mem.Allocator, board: Board) !BoardResponseDTO {
    return BoardResponseDTO{
        .id = board.id,
        .name = try allocator.dupe(u8, board.name),
        .code = try allocator.dupe(u8, board.code),
        .description = try allocator.dupe(u8, board.description),
    };
}

pub fn fromCreateDTO(allocator: std.mem.Allocator, dto: BoardCreateDTO, id: u8) !Board {
    return Board{
        .id = id,
        .code = try allocator.dupe(u8, dto.code),
        .description = try allocator.dupe(u8, dto.description),
        .name = try allocator.dupe(u8, dto.name),
        .next_card_number = 1,
    };
}
