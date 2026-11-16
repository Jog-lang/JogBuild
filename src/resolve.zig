const std = @import("std");
const manifest = @import("manifest.zig");
const ziputil = @import("ziputil.zig");

pub const SourceKind = enum { path, archive, cache };

pub const Node = struct {
    name: []const u8,
    version: []const u8,
    /// Directory the compiler should see (`--module name=dir`).
    dir: []const u8,
    kind: SourceKind,
    location: []const u8,
};

pub const Graph = struct {
    nodes: std.ArrayListUnmanaged(Node) = .{},
    arena: std.heap.ArenaAllocator,
    root_dir: []const u8 = "",
    root_name: []const u8 = "",
    parent: std.mem.Allocator,

    pub fn deinit(self: *Graph) void {
        self.nodes.deinit(self.parent);
        self.arena.deinit();
    }
};

pub fn cacheRoot(allocator: std.mem.Allocator) ![]u8 {
    if (std.posix.getenv("JOG_CACHE")) |c| {
        if (c.len > 0) return try allocator.dupe(u8, c);
    }
    if (std.posix.getenv("XDG_CACHE_HOME")) |x| {
        if (x.len > 0) return try std.fs.path.join(allocator, &.{ x, "jog" });
    }
    const home = std.posix.getenv("HOME") orelse return try allocator.dupe(u8, "/tmp/jog-cache");
    return try std.fs.path.join(allocator, &.{ home, ".cache/jog" });
}

/// Resolve the production module graph for `root_dir`.
pub fn resolveGraph(parent: std.mem.Allocator, root_dir: []const u8, include_test: bool) !Graph {
    var graph: Graph = .{
        .arena = std.heap.ArenaAllocator.init(parent),
        .parent = parent,
    };
    errdefer graph.deinit();
    const a = graph.arena.allocator();

    var root_man = try manifest.load(parent, root_dir);
    defer root_man.deinit();

    graph.root_dir = try a.dupe(u8, root_dir);
    graph.root_name = try a.dupe(u8, root_man.name);

    var seen: std.StringHashMapUnmanaged(void) = .{};
    defer {
        var it = seen.keyIterator();
        while (it.next()) |k| parent.free(k.*);
        seen.deinit(parent);
    }

    try walkRequires(parent, a, &graph, &seen, &root_man, include_test);
    return graph;
}

fn walkRequires(
    parent: std.mem.Allocator,
    a: std.mem.Allocator,
    graph: *Graph,
    seen: *std.StringHashMapUnmanaged(void),
    man: *const manifest.Manifest,
    include_test: bool,
) !void {
    for (man.requires) |req| {
        if (req.test_only and !include_test) continue;
        if (seen.contains(req.name)) continue;

        const resolved = try resolveOne(parent, a, man, req);
        var dep_man = try manifest.load(parent, resolved.dir);
        defer dep_man.deinit();
        if (!std.mem.eql(u8, dep_man.name, req.name)) {
            std.debug.print("jog-build: module '{s}' has name '{s}' in jog.mod\n", .{ req.name, dep_man.name });
            return error.ModuleNameMismatch;
        }
        if (dep_man.kind != .library) {
            std.debug.print("jog-build: module '{s}' is not kind library\n", .{req.name});
            return error.NotALibrary;
        }
        try seen.put(parent, try parent.dupe(u8, req.name), {});
        try walkRequires(parent, a, graph, seen, &dep_man, include_test);

        try graph.nodes.append(parent, .{
            .name = try a.dupe(u8, req.name),
            .version = try a.dupe(u8, dep_man.version),
            .dir = try a.dupe(u8, resolved.dir),
            .kind = resolved.kind,
            .location = try a.dupe(u8, resolved.location),
        });
    }
}

const Resolved = struct {
    dir: []const u8,
    kind: SourceKind,
    location: []const u8,
};

fn resolveOne(parent: std.mem.Allocator, a: std.mem.Allocator, man: *const manifest.Manifest, req: manifest.Require) !Resolved {
    if (manifest.isPathSpec(req.spec)) {
        const joined = if (std.fs.path.isAbsolute(req.spec))
            try parent.dupe(u8, req.spec)
        else
            try std.fs.path.join(parent, &.{ man.dir, req.spec });
        defer parent.free(joined);
        const abs = std.fs.cwd().realpathAlloc(parent, joined) catch try parent.dupe(u8, joined);
        defer parent.free(abs);

        if (std.mem.endsWith(u8, abs, ".jogz")) {
            const src = try installArchive(parent, a, abs);
            return .{ .dir = src, .kind = .archive, .location = try a.dupe(u8, req.spec) };
        }
        return .{
            .dir = try a.dupe(u8, abs),
            .kind = .path,
            .location = try a.dupe(u8, req.spec),
        };
    }

    const cache = try cacheRoot(parent);
    defer parent.free(cache);
    const src = try std.fs.path.join(a, &.{ cache, "mod", req.name, req.spec, "src" });
    std.fs.cwd().access(src, .{}) catch {
        std.debug.print("jog-build: module '{s}' {s} is not in the cache; require its .jogz path\n", .{ req.name, req.spec });
        return error.NotInCache;
    };
    return .{ .dir = src, .kind = .cache, .location = try a.dupe(u8, "-") };
}

fn installArchive(parent: std.mem.Allocator, a: std.mem.Allocator, jogz_path: []const u8) ![]const u8 {
    const cache = try cacheRoot(parent);
    defer parent.free(cache);
    const tmp_root = try std.fs.path.join(parent, &.{ cache, "tmp" });
    defer parent.free(tmp_root);
    try std.fs.cwd().makePath(tmp_root);

    var seed: [8]u8 = undefined;
    std.crypto.random.bytes(&seed);
    var hex: [16]u8 = undefined;
    _ = std.fmt.bufPrint(&hex, "{s}", .{std.fmt.fmtSliceHexLower(&seed)}) catch unreachable;
    const unpack_dir = try std.fs.path.join(parent, &.{ tmp_root, &hex });
    defer parent.free(unpack_dir);

    try ziputil.extractStoreZip(parent, jogz_path, unpack_dir);

    const man_path = try std.fs.path.join(parent, &.{ unpack_dir, "manifest" });
    defer parent.free(man_path);
    const man_text = try std.fs.cwd().readFileAlloc(parent, man_path, 64 * 1024);
    defer parent.free(man_text);

    var mod_name: ?[]const u8 = null;
    var mod_ver: ?[]const u8 = null;
    var line_it = std.mem.splitScalar(u8, man_text, '\n');
    while (line_it.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.startsWith(u8, line, "module ")) mod_name = std.mem.trim(u8, line["module ".len..], " \t");
        if (std.mem.startsWith(u8, line, "version ")) mod_ver = std.mem.trim(u8, line["version ".len..], " \t");
    }
    const name = mod_name orelse return error.BadArchiveManifest;
    const ver = mod_ver orelse return error.BadArchiveManifest;

    const final_dir = try std.fs.path.join(parent, &.{ cache, "mod", name, ver });
    defer parent.free(final_dir);
    const final_src = try std.fs.path.join(a, &.{ cache, "mod", name, ver, "src" });

    if (fileExists(final_src)) {
        std.fs.cwd().deleteTree(unpack_dir) catch {};
        return final_src;
    }

    const parent_mod = try std.fs.path.join(parent, &.{ cache, "mod", name });
    defer parent.free(parent_mod);
    try std.fs.cwd().makePath(parent_mod);

    std.fs.cwd().rename(unpack_dir, final_dir) catch {
        try std.fs.cwd().makePath(final_dir);
        try copyDir(parent, unpack_dir, final_dir);
        std.fs.cwd().deleteTree(unpack_dir) catch {};
    };

    if (!fileExists(final_src)) return error.ArchiveMissingSrc;
    return final_src;
}

fn copyDir(allocator: std.mem.Allocator, src: []const u8, dest: []const u8) !void {
    var dir = try std.fs.cwd().openDir(src, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const s = try std.fs.path.join(allocator, &.{ src, entry.name });
        defer allocator.free(s);
        const d = try std.fs.path.join(allocator, &.{ dest, entry.name });
        defer allocator.free(d);
        switch (entry.kind) {
            .directory => {
                try std.fs.cwd().makePath(d);
                try copyDir(allocator, s, d);
            },
            .file => try std.fs.cwd().copyFile(s, std.fs.cwd(), d, .{}),
            else => {},
        }
    }
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn emitModuleFlags(w: anytype, graph: *const Graph) !void {
    for (graph.nodes.items) |n| {
        const abs = std.fs.cwd().realpathAlloc(std.heap.page_allocator, n.dir) catch try std.heap.page_allocator.dupe(u8, n.dir);
        defer std.heap.page_allocator.free(abs);
        try w.print("--module={s}={s}\n", .{ n.name, abs });
    }
}

/// Append `--module` argv pairs for invoking jog.
pub fn appendModuleArgs(allocator: std.mem.Allocator, argv: *std.ArrayListUnmanaged([]const u8), graph: *const Graph) !void {
    for (graph.nodes.items) |n| {
        const abs = std.fs.cwd().realpathAlloc(allocator, n.dir) catch try allocator.dupe(u8, n.dir);
        const flag = try std.fmt.allocPrint(allocator, "--module={s}={s}", .{ n.name, abs });
        allocator.free(abs);
        try argv.append(allocator, flag);
    }
}
