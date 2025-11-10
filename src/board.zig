const std = @import("std");

pub const Board = extern struct {
    id: u64,
    next_card_number: u64,
    name_len: u8,
    name: [64]u8,
    code_len: u8,
    code: [8]u8,
    description_len: u8,
    description: [128]u8,
};
