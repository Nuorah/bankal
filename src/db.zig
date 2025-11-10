const std = @import("std");

pub fn Storage(comptime T: type) type {
    return struct {
        const Self = @This();
        pub const EntityType = T;

        entities: std.AutoHashMap(u64, T),
        mutex: std.Thread.Mutex = .{},

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{
                .entities = std.AutoHashMap(u64, T).init(allocator),
            };
        }

        pub fn deinit(self: Self, allocator: std.mem.Allocator) void {
            const iter = self.entities.iterator();
            while (iter.next()) |entity| {
                entity.value_ptr.deinit(allocator);
            }
            self.entities.deinit();
        }
    };
}

pub const Database = struct {
    const Self = @This();

    wal_path: []const u8,

    pub fn load(
        self: *Self,
        allocator: std.mem.Allocator,
        storages: anytype,
    ) !void {
        const file = std.fs.cwd().openFile(self.wal_path, .{}) catch |err| {
            if (err == error.FileNotFound) {
                const new_file = try std.fs.cwd().createFile(self.wal_path, .{});
                new_file.close();
                return;
            }
            return err;
        };
        defer file.close();

        var readerBuffer: [4096]u8 = undefined;
        var reader = file.reader(&readerBuffer);

        while (try reader.interface.takeDelimiter('\n')) |line| {
            if (line.len == 0) continue;

            const TypeInfo = struct {
                type: []const u8,
            };

            const type_info = std.json.parseFromSlice(TypeInfo, allocator, line, .{ .ignore_unknown_fields = true }) catch |err| {
                std.log.err("Failed to parse type, invalid data: {}", .{err});
                return err;
            };
            defer type_info.deinit();
            const type_name = type_info.value.type;

            inline for (storages) |storage| {
                const StorageType = @TypeOf(storage.*);
                const T = StorageType.EntityType;

                if (std.mem.eql(u8, type_name, T.TYPE_NAME)) {
                    storage.mutex.lock();
                    defer storage.mutex.unlock();

                    const TypedEntity = struct {
                        type: []const u8,
                        data: T,
                    };
                    const parsed = try std.json.parseFromSlice(TypedEntity, allocator, line, .{ .ignore_unknown_fields = true });
                    defer parsed.deinit();
                    std.log.info("Replaying history zooooom {d}\n", .{parsed.value.data.id});
                    const entity = try parsed.value.data.clone(allocator);
                    try storage.entities.put(entity.id, entity);
                }
            }
        }
    }

    pub fn append(
        self: *Self,
        comptime T: type,
        entity: T,
        allocator: std.mem.Allocator,
        storage: *Storage(T),
    ) !void {
        const file = try std.fs.cwd().createFile(self.wal_path, .{
            .read = false,
            .truncate = false,
            .exclusive = false,
        });
        defer file.close();

        var writerBuffer: [4096]u8 = undefined;
        var writer = file.writer(&writerBuffer);
        try writer.seekTo(try writer.file.getEndPos());

        const TypedEntity = struct {
            type: []const u8,
            data: T,
        };

        const typed = TypedEntity{
            .type = T.TYPE_NAME,
            .data = entity,
        };

        var allocating_writer: std.io.Writer.Allocating = .init(allocator);
        defer allocating_writer.deinit();

        var json_writer: std.json.Stringify = .{
            .writer = &allocating_writer.writer,
            .options = .{ .whitespace = .minified },
        };

        try json_writer.write(typed);
        const json_bytes = allocating_writer.written();

        try writer.interface.writeAll(json_bytes);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();

        try storage.entities.put(entity.id, entity);
    }
};
