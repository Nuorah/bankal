const std = @import("std");

pub const Card = extern struct {
    // Metadata block (16 bytes)
    id: u64,
    created_at: i64,

    // Frequently accessed stuff (16 bytes)
    updated_at: i64,
    column: u8,
    archived: bool,
    title_len: u8,
    _padding1: [5]u8 = undefined, // Align next field to 8 bytes

    // Variable content (640 bytes)
    title: [128]u8,
    description_len: u16,
    _padding2: [6]u8 = undefined,
    description: [512]u8,

    // Reserved for future (352 bytes)
    _reserved: [352]u8 = undefined,
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
    archived: bool,
    title: []const u8,
    description: []const u8,
};

pub fn toDTO(card: Card, allocator: std.mem.Allocator) !CardResponseDTO {
    return CardResponseDTO{
        .id = try std.fmt.allocPrint(allocator, "{d}", .{card.id}),
        .created_at = card.created_at,
        .updated_at = card.updated_at,
        .column = card.column,
        .archived = card.archived,
        .title = try allocator.dupe(u8, card.title[0..card.title_len]),
        .description = try allocator.dupe(u8, card.description[0..card.description_len]),
    };
}

pub fn fromDTO(dto: CardCreateDTO) !Card {
    if (dto.title.len > 128) return error.TitleTooLong;
    if (dto.description.len > 512) return error.DescriptionTooLong;

    // Generate UUID v4
    var uuid_bytes: [16]u8 = undefined;
    std.crypto.random.bytes(&uuid_bytes);

    // Set version (4) and variant bits for RFC 4122 compliance
    uuid_bytes[6] = (uuid_bytes[6] & 0x0f) | 0x40; // Version 4
    uuid_bytes[8] = (uuid_bytes[8] & 0x3f) | 0x80; // Variant 10

    // Convert first 8 bytes to u64 for the ID
    const id = std.mem.readInt(u64, uuid_bytes[0..8], .little);

    const now = std.time.timestamp();

    var card: Card = .{
        .id = id,
        .created_at = now,
        .updated_at = now,
        .column = dto.column,
        .archived = false,
        .title_len = @intCast(dto.title.len),
        .description_len = @intCast(dto.description.len),
        .title = undefined,
        .description = undefined,
        ._padding1 = undefined,
        ._padding2 = undefined,
        ._reserved = undefined,
    };

    @memcpy(card.title[0..dto.title.len], dto.title);
    @memcpy(card.description[0..dto.description.len], dto.description);

    return card;
}

pub fn updateCardFromDTO(card: *Card, dto: CardUpdateDTO) !void {
    var updated = false;
    if (dto.description) |description| {
        if (description.len > 512) return error.DescriptionTooLong;
    }
    if (dto.title) |title| {
        if (title.len > 128) return error.TitleTooLong;
    }

    if (dto.description) |description| {
        @memcpy(card.description[0..description.len], description);
        card.description_len = @intCast(description.len);
        updated = true;
    }
    if (dto.title) |title| {
        @memcpy(card.title[0..title.len], title);
        card.title_len = @intCast(title.len);
        updated = true;
    }
    if (dto.column) |column| {
        card.column = column;
        updated = true;
    }

    if (updated) {
        card.updated_at = std.time.timestamp();
    }
}
