const std = @import("std");

pub const Kind = enum { executable, library };

pub const Require = struct {
    name: []const u8,
    spec: []const u8,
    test_only: bool,
};

pub const Manifest = struct {
    name: []const u8,
    version: []const u8,
    kind: Kind,
    sources: []const []const u8,
    exports: []const []const u8,
    requires: []const Require,
    /// Original file text (arena-owned) for pack rewrite.
    text: []const u8,
    dir: []const u8,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *Manifest) void {
        self.arena.deinit();
    }
};

pub fn isPathSpec(spec: []const u8) bool {
    if (spec.len == 0) return false;
    if (spec[0] == '.' or spec[0] == '/' or spec[0] == '\\') return true;
    if (spec.len >= 2 and spec[1] == ':') return true;
    return false;
}

pub fn load(parent: std.mem.Allocator, dir: []const u8) !Manifest {
    const mod_path = try std.fs.path.join(parent, &.{ dir, "jog.mod" });
    defer parent.free(mod_path);
    const text = try std.fs.cwd().readFileAlloc(parent, mod_path, 1024 * 1024);
    defer parent.free(text);
    return parse(parent, text, dir);
}

pub fn parse(parent: std.mem.Allocator, text: []const u8, dir: []const u8) !Manifest {
    var arena = std.heap.ArenaAllocator.init(parent);
    errdefer arena.deinit();
    const a = arena.allocator();

    var name: ?[]const u8 = null;
    var version: ?[]const u8 = null;
    var kind: Kind = .executable;
    var sources: std.ArrayListUnmanaged([]const u8) = .{};
    var exports_list: std.ArrayListUnmanaged([]const u8) = .{};
    var requires: std.ArrayListUnmanaged(Require) = .{};

    var line_it = std.mem.splitScalar(u8, text, '\n');
    while (line_it.next()) |raw| {
        const line = trimComment(std.mem.trim(u8, raw, " \t\r"));
        if (line.len == 0) continue;
        var tok = std.mem.tokenizeAny(u8, line, " \t");
        const key = tok.next() orelse continue;
        const value = std.mem.trim(u8, line[key.len..], " \t");
        if (value.len == 0) continue;

        if (std.mem.eql(u8, key, "module")) {
            name = try a.dupe(u8, firstWord(value));
        } else if (std.mem.eql(u8, key, "version")) {
            version = try a.dupe(u8, firstWord(value));
        } else if (std.mem.eql(u8, key, "kind")) {
            const k = firstWord(value);
            if (std.mem.eql(u8, k, "library")) kind = .library;
        } else if (std.mem.eql(u8, key, "source") or std.mem.eql(u8, key, "root")) {
            try sources.append(a, try a.dupe(u8, firstWord(value)));
        } else if (std.mem.eql(u8, key, "export")) {
            try exports_list.append(a, try a.dupe(u8, firstWord(value)));
        } else if (std.mem.eql(u8, key, "require") or std.mem.eql(u8, key, "require.test")) {
            var vit = std.mem.tokenizeAny(u8, value, " \t");
            const rname = vit.next() orelse continue;
            const rspec = vit.next() orelse continue;
            try requires.append(a, .{
                .name = try a.dupe(u8, rname),
                .spec = try a.dupe(u8, rspec),
                .test_only = std.mem.eql(u8, key, "require.test"),
            });
        }
        // link / libdir / jog / targets: ignored here (compiler reads them).
    }

    return .{
        .name = name orelse return error.MissingModule,
        .version = version orelse try a.dupe(u8, "0.0.0"),
        .kind = kind,
        .sources = try sources.toOwnedSlice(a),
        .exports = try exports_list.toOwnedSlice(a),
        .requires = try requires.toOwnedSlice(a),
        .text = try a.dupe(u8, text),
        .dir = try a.dupe(u8, dir),
        .arena = arena,
    };
}

fn firstWord(s: []const u8) []const u8 {
    var it = std.mem.tokenizeAny(u8, s, " \t");
    return it.next() orelse s;
}

fn trimComment(line: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, line, '#')) |i| {
        return std.mem.trim(u8, line[0..i], " \t");
    }
    return line;
}
