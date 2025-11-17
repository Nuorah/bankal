const std = @import("std");

pub const Event = struct {
    data: Data,
    timestamp: i64,
};

pub const Data = union(enum) {
    card_created: CardCreatedEvent,
    card_updated: CardUpdatedEvent,
    card_moved_column: CardMovedColumnEvent,
    card_moved_board: CardMovedBoardEvent,

    board_created: BoardCreatedEvent,

    user_created: UserCreatedEvent,
};

//Card event structs
pub const CardCreatedEvent = struct {
    id: u64,
    column: u8 = 0,
    title: []const u8,
    description: []const u8,
    board_id: u8 = 0,
};

pub const CardUpdatedEvent = struct {
    id: u64,
    title: []const u8,
    description: []const u8,
};

pub const CardMovedColumnEvent = struct {
    id: u64,
    column: u8,
};

pub const CardMovedBoardEvent = struct {
    card_id: u64,
    board_id: u8,
};

//Board event structs
pub const BoardCreatedEvent = struct {
    name: []const u8,
    code: []const u8,
    description: []const u8,
};

//User event structs
pub const UserCreatedEvent = struct {
    id: u64,
    name: []const u8,
};
