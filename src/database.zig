const std = @import("std");

const HEADER_SIZE = 5; // 4 bytes magic + 4 bytes version

pub fn Database(
    comptime T: type,
    magic_number: [4]u8,
    version_number: u8,
) type {
    return struct {
        const Self = @This();
        const MAGIC = magic_number;
        const VERSION = version_number;

        path: []const u8,
        mutex: std.Thread.Mutex = .{},

        pub fn writeAll(self: *@This(), cards: []const T) !void {
            const dir = std.fs.cwd();

            var temp_name_buf: [256]u8 = undefined;
            const temp_path = try std.fmt.bufPrint(
                &temp_name_buf,
                "{s}.tmp",
                .{self.path},
            );

            self.mutex.lock();
            const file = try dir.createFile(temp_path, .{});
            defer file.close();

            errdefer dir.deleteFile(temp_path) catch {};

            var writerBuffer: [4096]u8 = undefined;
            var writer = file.writer(&writerBuffer);
            try writer.interface.writeAll(&MAGIC);
            try writer.interface.writeInt(u32, VERSION, .little);
            for (cards) |card| {
                try writer.interface.writeStruct(card, .little);
            }
            try writer.interface.flush();

            try dir.rename(temp_path, self.path);
            self.mutex.unlock();
        }

        pub fn readAll(self: *@This(), allocator: std.mem.Allocator) !std.ArrayList(T) {
            const dir = std.fs.cwd();

            self.mutex.lock();
            const file = try dir.openFile(self.path, .{});

            var magic_buf: [4]u8 = undefined;
            var readerBuffer: [4096]u8 = undefined;
            var reader = file.reader(&readerBuffer);
            try reader.interface.readSliceAll(&magic_buf);
            if (!std.mem.eql(u8, &magic_buf, &MAGIC)) {
                return error.InvalidMagicBytes;
            }

            const version = try reader.interface.takeInt(u32, .little);
            if (version != VERSION) {
                return error.UnsupportedVersion;
            }

            var cardsList: std.ArrayList(T) = .empty;

            while (reader.interface.takeStruct(T, .little)) |card| {
                try cardsList.append(allocator, card);
            } else |err| switch (err) {
                error.EndOfStream => {
                    std.log.debug("Finished reading cards from file: {s}", .{self.path});
                },
                else => {
                    std.log.err("Error while reading file {s}: {}", .{ self.path, err });
                    return err;
                },
            }
            self.mutex.unlock();

            return cardsList;
        }

        pub fn initFile(self: *Self) !void {
            const dir = std.fs.cwd();
            self.mutex.lock();

            const file = try dir.createFile(self.path, .{});
            defer file.close();

            var writerBuffer: [4096]u8 = undefined;
            var writer = file.writer(&writerBuffer);
            try writer.interface.writeAll(&MAGIC);
            try writer.interface.writeInt(u32, VERSION, .little);
            try writer.interface.flush();

            self.mutex.unlock();
        }

        /// Check if database file exists and is valid
        pub fn exists(self: *Self) bool {
            const dir = std.fs.cwd();
            self.mutex.lock();
            defer self.mutex.unlock();

            const file = dir.openFile(self.path, .{}) catch return false;
            defer file.close();

            var magic_buf: [4]u8 = undefined;
            _ = file.readAll(&magic_buf) catch return false;

            return std.mem.eql(u8, &magic_buf, &MAGIC);
        }
    };
}
