const std = @import("std");
const board = @import("board.zig");

pub const Card = struct {
    const Self = @This();
    pub const TYPE_NAME = "card";

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

pub const CreationDTO = struct {
    column: u8,
    title: []const u8,
    description: []const u8,
    board_id: u8,
};

pub const CardUpdateDTO = struct {
    column: ?u8 = null,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    board_id: ?u8 = null,
};

pub const CardResponseDTO = struct {
    id: []const u8,
    created_at: i64,
    updated_at: i64,
    column: u8,
    title: []const u8,
    description: []const u8,
    board_id: u8,
    code: []const u8,
};

pub fn toResponseDTO(allocator: std.mem.Allocator, card: Card) !CardResponseDTO {
    return CardResponseDTO{
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

pub fn fromDTO(allocator: std.mem.Allocator, dto: CreationDTO, board_entity: board.Board) !Card {
    // Generate UUID v4
    var uuid_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&uuid_bytes);

    // Set version (4) and variant bits for RFC 4122 compliance
    uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x40; // Version 4
    uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80; // Variant 10

    // Convert first 8 bytes to u64 for the ID
    const id = std.mem.readInt(u64, uuid_bytes[0..8], .little);

    const now = std.time.timestamp();

    const code = try std.fmt.allocPrint(allocator, "{s}-{d}", .{ board_entity.code, board_entity.next_card_number });

    return Card{
        .id = id,
        .created_at = now,
        .updated_at = now,
        .column = dto.column,
        .title = try allocator.dupe(u8, dto.title),
        .description = try allocator.dupe(u8, dto.description),
        .board_id = board_entity.id,
        .code = try allocator.dupe(u8, code),
    };
}

pub fn updateCardFromDTO(allocator: std.mem.Allocator, card: *Card, dto: CardUpdateDTO, board_entity: ?board.Board) !Card {
    var updated = false;
    var new_card = try card.clone(allocator);

    if (dto.description) |description| {
        new_card.description = try allocator.dupe(u8, description);
        updated = true;
    }
    if (dto.title) |title| {
        new_card.title = try allocator.dupe(u8, title);
        updated = true;
    }
    if (dto.column) |column| {
        new_card.column = column;
        updated = true;
    }

    if (dto.board_id) |board_id| {
        if (board_id != card.board_id) {
            if (board_entity) |board_entity_real| {
                new_card.column = 0;
                new_card.code = try std.fmt.allocPrint(allocator, "{s}-{d}", .{ board_entity_real.code, board_entity_real.next_card_number });
            }
        }
        new_card.board_id = board_id;
    }

    if (updated) {
        new_card.updated_at = std.time.timestamp();
    }

    return new_card;
}
