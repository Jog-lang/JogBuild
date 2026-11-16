const std = @import("std");

/// Minimal store-only zip writer (Packages.md V1): method 0, fixed DOS time/date, UTF-8 names.
pub const Entry = struct {
    name: []const u8,
    data: []const u8,
};

pub fn writeStoreZip(allocator: std.mem.Allocator, path: []const u8, entries: []const Entry) !void {
    _ = allocator;
    var file = try std.fs.cwd().createFile(path, .{});
    defer file.close();
    var out = file.writer();

    var offsets: std.ArrayListUnmanaged(u32) = .{};
    defer offsets.deinit(std.heap.page_allocator);
    try offsets.ensureTotalCapacity(std.heap.page_allocator, entries.len);

    // Local file headers + data
    for (entries) |e| {
        const local_off: u32 = @intCast(try file.getPos());
        try offsets.append(std.heap.page_allocator, local_off);
        const crc = std.hash.Crc32.hash(e.data);
        try writeLocalHeader(out, e.name, e.data.len, crc);
        try out.writeAll(e.data);
    }

    const cd_start: u32 = @intCast(try file.getPos());
    var i: usize = 0;
    while (i < entries.len) : (i += 1) {
        const e = entries[i];
        const crc = std.hash.Crc32.hash(e.data);
        try writeCentralHeader(out, e.name, e.data.len, crc, offsets.items[i]);
    }
    const cd_end: u32 = @intCast(try file.getPos());
    const cd_size = cd_end - cd_start;
    try writeEndRecord(out, @intCast(entries.len), cd_size, cd_start);
}

fn writeLocalHeader(w: anytype, name: []const u8, size: usize, crc: u32) !void {
    try w.writeInt(u32, 0x04034b50, .little); // local file header sig
    try w.writeInt(u16, 10, .little); // version needed
    try w.writeInt(u16, 1 << 11, .little); // UTF-8 flag
    try w.writeInt(u16, 0, .little); // method store
    try w.writeInt(u16, 0, .little); // time
    try w.writeInt(u16, 0x0021, .little); // date 1980-01-01
    try w.writeInt(u32, crc, .little);
    try w.writeInt(u32, @intCast(size), .little);
    try w.writeInt(u32, @intCast(size), .little);
    try w.writeInt(u16, @intCast(name.len), .little);
    try w.writeInt(u16, 0, .little); // extra
    try w.writeAll(name);
}

fn writeCentralHeader(w: anytype, name: []const u8, size: usize, crc: u32, local_off: u32) !void {
    try w.writeInt(u32, 0x02014b50, .little);
    try w.writeInt(u16, 10, .little); // version made by
    try w.writeInt(u16, 10, .little); // version needed
    try w.writeInt(u16, 1 << 11, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, 0x0021, .little);
    try w.writeInt(u32, crc, .little);
    try w.writeInt(u32, @intCast(size), .little);
    try w.writeInt(u32, @intCast(size), .little);
    try w.writeInt(u16, @intCast(name.len), .little);
    try w.writeInt(u16, 0, .little); // extra
    try w.writeInt(u16, 0, .little); // comment
    try w.writeInt(u16, 0, .little); // disk
    try w.writeInt(u16, 0, .little); // int attrs
    try w.writeInt(u32, 0, .little); // ext attrs
    try w.writeInt(u32, local_off, .little);
    try w.writeAll(name);
}

fn writeEndRecord(w: anytype, count: u16, cd_size: u32, cd_off: u32) !void {
    try w.writeInt(u32, 0x06054b50, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, 0, .little);
    try w.writeInt(u16, count, .little);
    try w.writeInt(u16, count, .little);
    try w.writeInt(u32, cd_size, .little);
    try w.writeInt(u32, cd_off, .little);
    try w.writeInt(u16, 0, .little); // comment
}

/// Extract a .jogz into `dest_dir` (creates dest_dir).
pub fn extractStoreZip(allocator: std.mem.Allocator, zip_path: []const u8, dest_dir: []const u8) !void {
    _ = allocator;
    try std.fs.cwd().makePath(dest_dir);
    var dest = try std.fs.cwd().openDir(dest_dir, .{});
    defer dest.close();
    var file = try std.fs.cwd().openFile(zip_path, .{});
    defer file.close();
    try std.zip.extract(dest, file.seekableStream(), .{});
}
