const std = @import("std");

pub const MAGIC: [4]u8 = .{ 'K', 'B', 'A', 'N' };
pub const VERSION: u8 = 1;

pub const Card = struct {
    const Self = @This();
    pub const TYPE_NAME = "card";
    // Metadata block (16 bytes)
    id: u64,
    created_at: i64,
    updated_at: i64,
    column: u8,
    title: []const u8,
    description: []const u8,

    pub fn clone(self: Card, allocator: std.mem.Allocator) !Self {
        return Card{
            .id = self.id,
            .created_at = self.created_at,
            .updated_at = self.updated_at,
            .column = self.column,
            .title = try allocator.dupe(u8, self.title),
            .description = try allocator.dupe(u8, self.description),
        };
    }
};

pub const CardCreateDTO = struct {
    column: u8,
    title: []const u8,
    description: []const u8,
};

pub const CardUpdateDTO = struct {
    column: ?u8 = null,
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

pub const CardResponseDTO = struct {
    id: []const u8,
    created_at: i64,
    updated_at: i64,
    column: u8,
    title: []const u8,
    description: []const u8,
};

pub fn toDTO(allocator: std.mem.Allocator, card: Card) !CardResponseDTO {
    return CardResponseDTO{
        .id = try std.fmt.allocPrint(allocator, "{d}", .{card.id}),
        .created_at = card.created_at,
        .updated_at = card.updated_at,
        .column = card.column,
        .title = try allocator.dupe(u8, card.title),
        .description = try allocator.dupe(u8, card.description),
    };
}

pub fn fromDTO(allocator: std.mem.Allocator, dto: CardCreateDTO) !Card {

    // Generate UUID v4
    var uuid_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&uuid_bytes);

    // Set version (4) and variant bits for RFC 4122 compliance
    uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x40; // Version 4
    uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80; // Variant 10

    // Convert first 8 bytes to u64 for the ID
    const id = std.mem.readInt(u64, uuid_bytes[0..8], .little);

    const now = std.time.timestamp();

    return Card{
        .id = id,
        .created_at = now,
        .updated_at = now,
        .column = dto.column,
        .title = try allocator.dupe(u8, dto.title),
        .description = try allocator.dupe(u8, dto.description),
    };
}

pub fn updateCardFromDTO(allocator: std.mem.Allocator, card: *Card, dto: CardUpdateDTO) !*Card {
    var updated = false;

    if (dto.description) |description| {
        card.description = try allocator.dupe(u8, description);
        updated = true;
    }
    if (dto.title) |title| {
        card.title = try allocator.dupe(u8, title);
        updated = true;
    }
    if (dto.column) |column| {
        card.column = column;
        updated = true;
    }

    if (updated) {
        card.updated_at = std.time.timestamp();
    }

    return card;
}
