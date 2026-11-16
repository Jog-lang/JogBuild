const std = @import("std");
const manifest = @import("manifest.zig");
const resolve = @import("resolve.zig");
const pack = @import("pack.zig");

const version_string = "jog-build 0.3.0-v2 (zig; resolve/pack/cache + JogCompiler v2)";

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
        var path: []const u8 = ".";
        var flags = false;
        var include_test = false;
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "--flags")) {
                flags = true;
            } else if (std.mem.eql(u8, a, "--test")) {
                include_test = true;
            } else if (std.mem.startsWith(u8, a, "-")) {
                continue;
            } else {
                path = a;
            }
        }
        const source = try resolveBuildPath(allocator, path);
        defer allocator.free(source);
        var graph = resolve.resolveGraph(allocator, source, include_test) catch |err| {
            try stderr.print("jog-build deps: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer graph.deinit();
        if (flags) {
            try resolve.emitModuleFlags(stdout, &graph);
        } else {
            for (graph.nodes.items) |n| {
                try stdout.print("{s} {s} {s} {s}\n", .{ n.name, n.version, @tagName(n.kind), n.dir });
            }
        }
        return;
    }
    if (std.mem.eql(u8, cmd, "pack")) {
        var path: []const u8 = ".";
        var out_path: ?[]const u8 = null;
        while (args.next()) |a| {
            if (std.mem.eql(u8, a, "-o")) {
                out_path = args.next() orelse {
                    try stderr.writeAll("missing -o path\n");
                    std.process.exit(2);
                };
            } else if (std.mem.startsWith(u8, a, "-")) {
                try stderr.print("unknown flag {s}\n", .{a});
                std.process.exit(2);
            } else {
                path = a;
            }
        }
        const source = try resolveBuildPath(allocator, path);
        defer allocator.free(source);
        var graph = resolve.resolveGraph(allocator, source, false) catch |err| {
            try stderr.print("jog-build pack: resolve {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer graph.deinit();

        // jog check with module flags
        const jog = try findJog(allocator);
        defer allocator.free(jog);
        {
            var argv: std.ArrayListUnmanaged([]const u8) = .{};
            defer {
                // module flags owned
                for (argv.items) |x| {
                    if (std.mem.startsWith(u8, x, "--module=")) allocator.free(x);
                }
                argv.deinit(allocator);
            }
            try argv.append(allocator, "check");
            try resolve.appendModuleArgs(allocator, &argv, &graph);
            try argv.append(allocator, source);
            const code = try runJog(allocator, jog, argv.items, stdout, stderr);
            if (code != 0) std.process.exit(code);
        }

        var result = pack.packModule(allocator, source, out_path, &graph) catch |err| {
            try stderr.print("jog-build pack: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        defer result.deinit();
        try stdout.print("{s}\n{s}\n", .{ result.path, result.hash });
        return;
    }
    if (std.mem.eql(u8, cmd, "check") or std.mem.eql(u8, cmd, "build") or std.mem.eql(u8, cmd, "run")) {
        const jog = try findJog(allocator);
        defer allocator.free(jog);

        var path: []const u8 = ".";
        var out_path: ?[]const u8 = null;
        var extras: std.ArrayListUnmanaged([]const u8) = .{};
        defer extras.deinit(allocator);
        var run_args: std.ArrayListUnmanaged([]const u8) = .{};
        defer run_args.deinit(allocator);
        var saw_ddash = false;
        var emscripten = false;
        var skip_resolve = false;

        while (args.next()) |a| {
            if (saw_ddash) {
                try run_args.append(allocator, a);
                continue;
            }
            if (std.mem.eql(u8, a, "--")) {
                saw_ddash = true;
                continue;
            }
            if (std.mem.eql(u8, a, "-o")) {
                out_path = args.next() orelse {
                    try stderr.writeAll("missing -o path\n");
                    std.process.exit(2);
                };
            } else if (std.mem.eql(u8, a, "--target")) {
                const t = args.next() orelse {
                    try stderr.writeAll("missing --target value (wasm32-emscripten)\n");
                    std.process.exit(2);
                };
                if (!std.mem.eql(u8, t, "wasm32-emscripten")) {
                    try stderr.print("unsupported --target {s} (v2: wasm32-emscripten)\n", .{t});
                    std.process.exit(2);
                }
                emscripten = true;
                try extras.append(allocator, "--target");
                try extras.append(allocator, t);
            } else if (std.mem.startsWith(u8, a, "--target=")) {
                const t = a["--target=".len..];
                if (!std.mem.eql(u8, t, "wasm32-emscripten")) {
                    try stderr.print("unsupported --target {s} (v2: wasm32-emscripten)\n", .{t});
                    std.process.exit(2);
                }
                emscripten = true;
                try extras.append(allocator, "--target");
                try extras.append(allocator, t);
            } else if (std.mem.eql(u8, a, "--libdir") or std.mem.eql(u8, a, "-L")) {
                const dir = args.next() orelse {
                    try stderr.writeAll("missing --libdir path\n");
                    std.process.exit(2);
                };
                try extras.append(allocator, "--libdir");
                try extras.append(allocator, dir);
            } else if (std.mem.startsWith(u8, a, "--libdir=")) {
                try extras.append(allocator, "--libdir");
                try extras.append(allocator, a["--libdir=".len..]);
            } else if (std.mem.startsWith(u8, a, "-L") and a.len > 2) {
                try extras.append(allocator, "--libdir");
                try extras.append(allocator, a[2..]);
            } else if (std.mem.eql(u8, a, "--keep-asm") or std.mem.eql(u8, a, "--keep-c") or std.mem.eql(u8, a, "--diag=json") or std.mem.eql(u8, a, "--test")) {
                try extras.append(allocator, a);
            } else if (std.mem.eql(u8, a, "--module")) {
                skip_resolve = true;
                const v = args.next() orelse {
                    try stderr.writeAll("missing --module name=dir\n");
                    std.process.exit(2);
                };
                try extras.append(allocator, "--module");
                try extras.append(allocator, v);
            } else if (std.mem.startsWith(u8, a, "--module=")) {
                skip_resolve = true;
                try extras.append(allocator, a);
            } else if (std.mem.startsWith(u8, a, "-")) {
                try stderr.print("unknown flag {s}\n", .{a});
                std.process.exit(2);
            } else {
                path = a;
            }
        }

        const source = try resolveBuildPath(allocator, path);
        defer allocator.free(source);

        var owned_flags: std.ArrayListUnmanaged([]u8) = .{};
        defer {
            for (owned_flags.items) |f| allocator.free(f);
            owned_flags.deinit(allocator);
        }

        if (!skip_resolve) {
            // Resolve when jog.mod exists; plain files skip.
            const mod_file = try std.fs.path.join(allocator, &.{ source, "jog.mod" });
            defer allocator.free(mod_file);
            if (fileExists(mod_file) or std.mem.eql(u8, std.fs.path.basename(path), "jog.mod") or isDir(source)) {
                if (fileExists(mod_file)) {
                    var graph = resolve.resolveGraph(allocator, source, false) catch |err| {
                        try stderr.print("jog-build: resolve {s}\n", .{@errorName(err)});
                        std.process.exit(1);
                    };
                    defer graph.deinit();
                    for (graph.nodes.items) |n| {
                        const abs = std.fs.cwd().realpathAlloc(allocator, n.dir) catch try allocator.dupe(u8, n.dir);
                        const flag = try std.fmt.allocPrint(allocator, "--module={s}={s}", .{ n.name, abs });
                        allocator.free(abs);
                        try owned_flags.append(allocator, flag);
                    }
                }
            }
        }

        if (std.mem.eql(u8, cmd, "check")) {
            var argv: std.ArrayListUnmanaged([]const u8) = .{};
            defer argv.deinit(allocator);
            try argv.append(allocator, "check");
            for (extras.items) |e| try argv.append(allocator, e);
            for (owned_flags.items) |f| try argv.append(allocator, f);
            try argv.append(allocator, source);
            // Libraries: check is correct; executables too.
            const code = try runJog(allocator, jog, argv.items, stdout, stderr);
            std.process.exit(code);
        }

        // Library build → check
        var is_lib = false;
        {
            const mf = try std.fs.path.join(allocator, &.{ source, "jog.mod" });
            defer allocator.free(mf);
            if (fileExists(mf)) {
                if (manifest.load(allocator, source)) |man_val| {
                    var man = man_val;
                    defer man.deinit();
                    is_lib = man.kind == .library;
                } else |_| {}
            }
        }
        if (is_lib and std.mem.eql(u8, cmd, "build")) {
            var argv: std.ArrayListUnmanaged([]const u8) = .{};
            defer argv.deinit(allocator);
            try argv.append(allocator, "check");
            for (extras.items) |e| try argv.append(allocator, e);
            for (owned_flags.items) |f| try argv.append(allocator, f);
            try argv.append(allocator, source);
            const code = try runJog(allocator, jog, argv.items, stdout, stderr);
            std.process.exit(code);
        }

        const default_out: []const u8 = if (emscripten) "a.out.html" else "a.out";
        const out = out_path orelse default_out;
        {
            var argv: std.ArrayListUnmanaged([]const u8) = .{};
            defer argv.deinit(allocator);
            try argv.append(allocator, "build");
            try argv.append(allocator, source);
            try argv.append(allocator, "-o");
            try argv.append(allocator, out);
            for (extras.items) |e| try argv.append(allocator, e);
            for (owned_flags.items) |f| try argv.append(allocator, f);
            const code = try runJog(allocator, jog, argv.items, stdout, stderr);
            if (code != 0) std.process.exit(code);
        }

        if (std.mem.eql(u8, cmd, "run")) {
            var argv: std.ArrayListUnmanaged([]const u8) = .{};
            defer argv.deinit(allocator);
            try argv.append(allocator, out);
            for (run_args.items) |a| try argv.append(allocator, a);
            var child = std.process.Child.init(argv.items, allocator);
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
        \\v2 Zig build tool for JogCompiler v2: resolve path/.jogz, pack, cache.
        \\
        \\commands:
        \\  version
        \\  check [path] [--diag=json]
        \\  build [path] -o OUT [--keep-asm] [--libdir DIR]...
        \\  run   [path] -o OUT [-- prog-args...]
        \\  deps [--flags] [--test] [path]
        \\  pack [path] [-o OUT.jogz]
        \\  help
        \\
    );
}

fn findJog(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("JOG")) |j| {
        if (j.len > 0) return try allocator.dupe(u8, j);
    }
    const home = std.posix.getenv("HOME") orelse "";
    if (home.len > 0) {
        const local = try std.fs.path.join(allocator, &.{ home, ".local/bin/jog-v2" });
        defer allocator.free(local);
        if (fileExists(local)) return try allocator.dupe(u8, local);
    }
    if (try siblingCompilerJog(allocator)) |p| return p;
    if (try which(allocator, "jog-v2")) |p| return p;
    std.debug.print("jog-build: JogCompiler v2 not found. Set JOG.\n", .{});
    std.process.exit(1);
}

fn siblingCompilerJog(allocator: std.mem.Allocator) !?[]const u8 {
    const candidates = [_][]const u8{
        "../JogCompiler-wt-shareable-jogz/zig-out/bin/jog",
        "../JogCompiler-v2/zig-out/bin/jog",
        "../JogCompiler/zig-out/bin/jog",
    };
    for (candidates) |rel| {
        if (fileExists(rel)) {
            if (try isV2Jog(allocator, rel)) return try allocator.dupe(u8, rel);
        }
    }
    return null;
}

fn isV2Jog(allocator: std.mem.Allocator, path: []const u8) !bool {
    var child = std.process.Child.init(&.{ path, "version" }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    try child.spawn();
    const out = try child.stdout.?.readToEndAlloc(allocator, 4096);
    defer allocator.free(out);
    _ = try child.wait();
    return std.mem.indexOf(u8, out, "-v2") != null or std.mem.indexOf(u8, out, "v2") != null;
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

fn isDir(path: []const u8) bool {
    const st = std.fs.cwd().statFile(path) catch return false;
    return st.kind == .directory;
}

fn resolveBuildPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const st = std.fs.cwd().statFile(path) catch {
        return try allocator.dupe(u8, path);
    };
    if (st.kind == .directory) {
        const mod_path = try std.fs.path.join(allocator, &.{ path, "jog.mod" });
        defer allocator.free(mod_path);
        if (fileExists(mod_path)) return try allocator.dupe(u8, path);
        return try std.fs.path.join(allocator, &.{ path, "main.jog" });
    }
    if (std.mem.eql(u8, std.fs.path.basename(path), "jog.mod")) {
        if (std.fs.path.dirname(path)) |dir| return try allocator.dupe(u8, dir);
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
