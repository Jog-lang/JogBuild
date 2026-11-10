const std = @import("std");

const version_string = "jog-build 0.2.0-v2 (zig; forwards to JogCompiler v2)";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.skip();

    const stdout = std.io.getStdOut().writer();
    const stderr = std.io.getStdErr().writer();

    const cmd = args.next() orelse {
        try usage(stderr);
        std.process.exit(2);
    };

    if (std.mem.eql(u8, cmd, "help") or std.mem.eql(u8, cmd, "-h") or std.mem.eql(u8, cmd, "--help")) {
        try usage(stdout);
        return;
    }
    if (std.mem.eql(u8, cmd, "version") or std.mem.eql(u8, cmd, "--version")) {
        try stdout.print("{s}\n", .{version_string});
        const jog = try findJog(allocator);
        defer allocator.free(jog);
        _ = try runJog(allocator, jog, &.{"version"}, stdout, stderr);
        return;
    }
    if (std.mem.eql(u8, cmd, "deps")) {
        // v2: no --module graph yet; empty flags keep LSP callers happy.
        while (args.next()) |_| {}
        return;
    }
    if (std.mem.eql(u8, cmd, "check") or std.mem.eql(u8, cmd, "build") or std.mem.eql(u8, cmd, "run")) {
        const jog = try findJog(allocator);
        defer allocator.free(jog);

        var path: []const u8 = ".";
        var out_path: ?[]const u8 = null;
        var extras: std.ArrayListUnmanaged([]const u8) = .{};
        defer extras.deinit(allocator);

        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "-o")) {
                out_path = args.next() orelse {
                    try stderr.writeAll("missing -o path\n");
                    std.process.exit(2);
                };
            } else if (std.mem.startsWith(u8, a, "-")) {
                try extras.append(allocator, a);
            } else {
                path = a;
            }
        }

        const source = try resolveSource(allocator, path);
        defer allocator.free(source);

        if (std.mem.eql(u8, cmd, "check")) {
            var argv: std.ArrayListUnmanaged([]const u8) = .{};
            defer argv.deinit(allocator);
            try argv.append(allocator, "check");
            for (extras.items) |e| try argv.append(allocator, e);
            try argv.append(allocator, source);
            const code = try runJog(allocator, jog, argv.items, stdout, stderr);
            std.process.exit(code);
        }

        const out = out_path orelse "a.out";
        {
            var argv: std.ArrayListUnmanaged([]const u8) = .{};
            defer argv.deinit(allocator);
            try argv.append(allocator, "build");
            try argv.append(allocator, source);
            try argv.append(allocator, "-o");
            try argv.append(allocator, out);
            for (extras.items) |e| try argv.append(allocator, e);
            const code = try runJog(allocator, jog, argv.items, stdout, stderr);
            if (code != 0) std.process.exit(code);
        }

        if (std.mem.eql(u8, cmd, "run")) {
            var child = std.process.Child.init(&.{out}, allocator);
            child.stdout_behavior = .Inherit;
            child.stderr_behavior = .Inherit;
            const term = try child.spawnAndWait();
            switch (term) {
                .Exited => |c| std.process.exit(c),
                else => std.process.exit(1),
            }
        }
        return;
    }

    try stderr.print("unknown command: {s}\n", .{cmd});
    try usage(stderr);
    std.process.exit(2);
}

fn usage(w: anytype) !void {
    try w.writeAll(
        \\usage: jog-build <command> [args]
        \\
        \\v2 Zig front-end for JogCompiler v2. Resolves JOG / jog-v2 / jog.
        \\
        \\commands:
        \\  version
        \\  check [path] [--diag=json]
        \\  build [path] -o OUT
        \\  run   [path] -o OUT     build then execute OUT
        \\  deps                    no-op (module graph deferred)
        \\  help
        \\
        \\path may be a .jog file or a directory containing main.jog.
        \\
    );
}

fn findJog(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("JOG")) |j| {
        if (j.len > 0) return try allocator.dupe(u8, j);
    }
    const home = std.posix.getenv("HOME") orelse "";
    const candidates = [_][]const u8{
        "jog-v2",
        "jog",
    };
    // Prefer ~/.local/bin/jog-v2 then PATH search via which-like
    if (home.len > 0) {
        const local = try std.fs.path.join(allocator, &.{ home, ".local/bin/jog-v2" });
        defer allocator.free(local);
        if (fileExists(local)) return try allocator.dupe(u8, local);
        const local_jog = try std.fs.path.join(allocator, &.{ home, ".local/bin/jog" });
        defer allocator.free(local_jog);
        // Only use ~/.local/bin/jog if it looks like v2
        if (fileExists(local_jog)) {
            if (try isV2Jog(allocator, local_jog)) return try allocator.dupe(u8, local_jog);
        }
    }
    for (candidates) |name| {
        if (try which(allocator, name)) |p| {
            if (try isV2Jog(allocator, p) or std.mem.eql(u8, name, "jog-v2")) {
                return p;
            }
            allocator.free(p);
        }
    }
    std.debug.print("jog-build: JogCompiler v2 not found. Set JOG to zig-out/bin/jog or install jog-v2.\n", .{});
    std.process.exit(1);
}

fn isV2Jog(allocator: std.mem.Allocator, path: []const u8) !bool {
    var child = std.process.Child.init(&.{ path, "version" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    const out = try child.stdout.?.readToEndAlloc(allocator, 4096);
    defer allocator.free(out);
    _ = try child.wait();
    return std.mem.indexOf(u8, out, "0.2.0-v2") != null or std.mem.indexOf(u8, out, "v2") != null;
}

fn which(allocator: std.mem.Allocator, name: []const u8) !?[]const u8 {
    const path_env = std.posix.getenv("PATH") orelse return null;
    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const cand = try std.fs.path.join(allocator, &.{ dir, name });
        if (fileExists(cand)) return cand;
        allocator.free(cand);
    }
    return null;
}

fn fileExists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

fn resolveSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const st = std.fs.cwd().statFile(path) catch {
        return try allocator.dupe(u8, path);
    };
    if (st.kind == .directory) {
        return try std.fs.path.join(allocator, &.{ path, "main.jog" });
    }
    return try allocator.dupe(u8, path);
}

fn runJog(allocator: std.mem.Allocator, jog: []const u8, jog_args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    var argv: std.ArrayListUnmanaged([]const u8) = .{};
    defer argv.deinit(allocator);
    try argv.append(allocator, jog);
    for (jog_args) |a| try argv.append(allocator, a);

    var child = std.process.Child.init(argv.items, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;
    try child.spawn();
    const out = try child.stdout.?.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(out);
    const err = try child.stderr.?.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(err);
    try stdout.writeAll(out);
    try stderr.writeAll(err);
    const term = try child.wait();
    return switch (term) {
        .Exited => |c| c,
        else => 1,
    };
}
