const std = @import("std");
const manifest = @import("manifest.zig");
const ziputil = @import("ziputil.zig");
const resolve = @import("resolve.zig");

pub const PackResult = struct {
    path: []u8,
    hash: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *PackResult) void {
        self.allocator.free(self.path);
        self.allocator.free(self.hash);
    }
};

const FileEntry = struct {
    name: []u8,
    data: []u8,
};

/// Pack a library module into `out/<name>-<version>.jogz` (or `-o` path).
pub fn packModule(
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    out_path_opt: ?[]const u8,
    graph: *const resolve.Graph,
) !PackResult {
    var man = try manifest.load(allocator, root_dir);
    defer man.deinit();
    if (man.kind != .library) return error.NotALibrary;
    if (std.mem.eql(u8, man.version, "0.0.0")) {
        // Require an explicit version line for pack (spec).
        // Heuristic: if text has no "version " line, fail.
        if (std.mem.indexOf(u8, man.text, "version ") == null) return error.MissingVersion;
    }

    var files: std.ArrayListUnmanaged(FileEntry) = .{};
    defer {
        for (files.items) |f| {
            allocator.free(f.name);
            allocator.free(f.data);
        }
        files.deinit(allocator);
    }

    // Rewritten jog.mod first under src/
    const rewritten = try rewriteJogMod(allocator, &man, graph);
    defer allocator.free(rewritten);
    try files.append(allocator, .{
        .name = try allocator.dupe(u8, "src/jog.mod"),
        .data = try allocator.dupe(u8, rewritten),
    });

    // Pack only `source` / `root` trees from jog.mod — never vendor/, prefix/,
    // examples/, or other checkout noise (those hit FileTooBig on pch/objects).
    if (man.sources.len == 0) {
        try collectTree(allocator, &files, root_dir, "");
    } else {
        for (man.sources) |src| {
            const abs = try std.fs.path.join(allocator, &.{ root_dir, src });
            defer allocator.free(abs);
            const st = std.fs.cwd().statFile(abs) catch |err| {
                if (err == error.FileNotFound) return error.MissingSource;
                return err;
            };
            if (st.kind == .directory) {
                try collectTree(allocator, &files, abs, src);
            } else if (st.kind == .file) {
                const data = try std.fs.cwd().readFileAlloc(allocator, abs, 16 * 1024 * 1024);
                errdefer allocator.free(data);
                const zip_name = try std.fmt.allocPrint(allocator, "src/{s}", .{src});
                try files.append(allocator, .{ .name = zip_name, .data = data });
            }
        }
    }

    // Sort by name (byte order); manifest entry is separate and first in zip.
    std.mem.sort(FileEntry, files.items, {}, struct {
        fn less(_: void, a: FileEntry, b: FileEntry) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.less);

    const hash = try contentHash(allocator, files.items);
    errdefer allocator.free(hash);

    const arch_manifest = try std.fmt.allocPrint(allocator,
        \\archive 1
        \\module {s}
        \\version {s}
        \\kind library
        \\hash {s}
        \\
    , .{ man.name, man.version, hash });
    defer allocator.free(arch_manifest);

    var entries: std.ArrayListUnmanaged(ziputil.Entry) = .{};
    defer entries.deinit(allocator);
    try entries.append(allocator, .{ .name = "manifest", .data = arch_manifest });
    for (files.items) |f| {
        try entries.append(allocator, .{ .name = f.name, .data = f.data });
    }

    const default_name = try std.fmt.allocPrint(allocator, "out/{s}-{s}.jogz", .{ man.name, man.version });
    defer allocator.free(default_name);
    const out_path = out_path_opt orelse default_name;

    if (std.fs.path.dirname(out_path)) |parent| {
        try std.fs.cwd().makePath(parent);
    }
    try ziputil.writeStoreZip(allocator, out_path, entries.items);

    return .{
        .path = try allocator.dupe(u8, out_path),
        .hash = hash,
        .allocator = allocator,
    };
}

fn rewriteJogMod(allocator: std.mem.Allocator, man: *const manifest.Manifest, graph: *const resolve.Graph) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .{};
    errdefer out.deinit(allocator);
    var line_it = std.mem.splitScalar(u8, man.text, '\n');
    while (line_it.next()) |raw| {
        const trimmed = std.mem.trim(u8, raw, " \t\r");
        const line = if (std.mem.indexOfScalar(u8, trimmed, '#')) |i|
            std.mem.trim(u8, trimmed[0..i], " \t")
        else
            trimmed;
        if (std.mem.startsWith(u8, line, "require.test")) continue;
        if (std.mem.startsWith(u8, line, "require ")) {
            var tok = std.mem.tokenizeAny(u8, line, " \t");
            _ = tok.next();
            const rname = tok.next() orelse {
                try out.appendSlice(allocator, raw);
                try out.append(allocator, '\n');
                continue;
            };
            const rspec = tok.next() orelse "";
            if (manifest.isPathSpec(rspec)) {
                // Replace with dependency's version from graph.
                var ver: []const u8 = "0.0.0";
                for (graph.nodes.items) |n| {
                    if (std.mem.eql(u8, n.name, rname)) {
                        ver = n.version;
                        break;
                    }
                }
                try out.appendSlice(allocator, "require ");
                try out.appendSlice(allocator, rname);
                try out.append(allocator, ' ');
                try out.appendSlice(allocator, ver);
                try out.append(allocator, '\n');
                continue;
            }
        }
        try out.appendSlice(allocator, raw);
        try out.append(allocator, '\n');
    }
    return try out.toOwnedSlice(allocator);
}

fn collectTree(
    allocator: std.mem.Allocator,
    files: *std.ArrayListUnmanaged(FileEntry),
    abs_dir: []const u8,
    rel_prefix: []const u8,
) !void {
    var dir = try std.fs.cwd().openDir(abs_dir, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.name.len == 0 or entry.name[0] == '.') continue;
        if (std.mem.eql(u8, entry.name, "out")) continue;
        if (std.mem.eql(u8, entry.name, "jog.lock")) continue;
        // Safety net when packing a whole checkout (no `source` lines).
        if (std.mem.eql(u8, entry.name, "vendor")) continue;
        if (std.mem.eql(u8, entry.name, "prefix")) continue;
        if (std.mem.eql(u8, entry.name, "prefix-emscripten")) continue;
        if (std.mem.eql(u8, entry.name, "examples")) continue;
        const child_abs = try std.fs.path.join(allocator, &.{ abs_dir, entry.name });
        defer allocator.free(child_abs);
        const child_rel = if (rel_prefix.len == 0)
            try allocator.dupe(u8, entry.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ rel_prefix, entry.name });
        defer allocator.free(child_rel);

        switch (entry.kind) {
            .directory => {
                const nested = try std.fs.path.join(allocator, &.{ child_abs, "jog.mod" });
                defer allocator.free(nested);
                if (fileExists(nested)) continue; // nested module — skip
                try collectTree(allocator, files, child_abs, child_rel);
            },
            .file => {
                if (std.mem.eql(u8, entry.name, "jog.mod") and rel_prefix.len == 0) continue; // rewritten
                if (std.mem.endsWith(u8, entry.name, ".test.jog")) continue;
                const data = try std.fs.cwd().readFileAlloc(allocator, child_abs, 16 * 1024 * 1024);
                errdefer allocator.free(data);
                const zip_name = try std.fmt.allocPrint(allocator, "src/{s}", .{child_rel});
                try files.append(allocator, .{ .name = zip_name, .data = data });
            },
            else => {},
        }
    }
}

fn contentHash(allocator: std.mem.Allocator, files: []const FileEntry) ![]u8 {
    // lines: "<hex> <name-relative-to-src>\n" sorted by name under src/
    var lines: std.ArrayListUnmanaged(u8) = .{};
    defer lines.deinit(allocator);
    for (files) |f| {
        // name is "src/..."
        const rel = if (std.mem.startsWith(u8, f.name, "src/")) f.name["src/".len..] else f.name;
        var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(f.data, &digest, .{});
        var hex: [64]u8 = undefined;
        _ = std.fmt.bufPrint(&hex, "{s}", .{std.fmt.fmtSliceHexLower(&digest)}) catch unreachable;
        try lines.appendSlice(allocator, &hex);
        try lines.append(allocator, ' ');
        try lines.appendSlice(allocator, rel);
        try lines.append(allocator, '\n');
    }
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(lines.items, &digest, .{});
    var hex: [64]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{s}", .{std.fmt.fmtSliceHexLower(&digest)}) catch unreachable;
    return try std.fmt.allocPrint(allocator, "sha256:{s}", .{hex});
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}
