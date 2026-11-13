const std = @import("std");

const version_string = "jog-build 0.2.5-v2 (zig; forwards to JogCompiler v2; deps --flags)";

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
        // Forward `--flags` / `--test` to jog (JOG-92 LSP module mappings).
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
        const jog = try findJog(allocator);
        defer allocator.free(jog);
        const source = try resolveBuildPath(allocator, path);
        defer allocator.free(source);
        var jog_args: std.ArrayListUnmanaged([]const u8) = .{};
        defer jog_args.deinit(allocator);
        try jog_args.append(allocator, "deps");
        if (flags) try jog_args.append(allocator, "--flags");
        if (include_test) try jog_args.append(allocator, "--test");
        try jog_args.append(allocator, source);
        const code = try runJog(allocator, jog, jog_args.items, stdout, stderr);
        std.process.exit(code);
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
                const v = args.next() orelse {
                    try stderr.writeAll("missing --module name=dir\n");
                    std.process.exit(2);
                };
                try extras.append(allocator, "--module");
                try extras.append(allocator, v);
            } else if (std.mem.startsWith(u8, a, "--module=")) {
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

        if (std.mem.eql(u8, cmd, "check")) {
            var argv: std.ArrayListUnmanaged([]const u8) = .{};
            defer argv.deinit(allocator);
            try argv.append(allocator, "check");
            for (extras.items) |e| try argv.append(allocator, e);
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
        \\v2 Zig front-end for JogCompiler v2 (Gates 1–4 + Chase-Lev).
        \\Finds JOG / jog-v2 / sibling JogCompiler-v2 / PATH jog.
        \\Concurrency (go/yield, with (Dispatcher), dispatcher_io) needs no
        \\extra flags — the compiler always links runtime/linux_x64_coro.s.
        \\
        \\commands:
        \\  version
        \\  check [path] [--diag=json]
        \\  build [path] -o OUT [--keep-asm] [--keep-c]
        \\        [--target wasm32-emscripten] [--libdir DIR | -L DIR]...
        \\  run   [path] -o OUT [--keep-asm] [-- prog-args...]
        \\  deps [--flags] [--test] [path]
        \\        source paths, or --module=name=dir for LSP (via jog deps)
        \\  help
        \\
        \\path may be a .jog file, a directory with jog.mod, or jog.mod itself.
        \\Directories without jog.mod still fall back to main.jog.
        \\wasm32-emscripten: forwards to jog; output defaults to a.out.html.
        \\check/build also forward --module name=dir when given.
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
        const local_jog = try std.fs.path.join(allocator, &.{ home, ".local/bin/jog" });
        defer allocator.free(local_jog);
        if (fileExists(local_jog)) {
            if (try isV2Jog(allocator, local_jog)) return try allocator.dupe(u8, local_jog);
        }
    }
    if (try siblingCompilerJog(allocator)) |p| return p;

    const candidates = [_][]const u8{ "jog-v2", "jog" };
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

/// Prefer a checkout next to JogBuild: ../JogCompiler-v2/zig-out/bin/jog
/// (also tried relative to this binary's directory).
fn siblingCompilerJog(allocator: std.mem.Allocator) !?[]const u8 {
    const rel = "JogCompiler-v2/zig-out/bin/jog";
    const cwd_cand = try std.fs.path.join(allocator, &.{ "..", rel });
    defer allocator.free(cwd_cand);
    if (fileExists(cwd_cand)) {
        if (try isV2Jog(allocator, cwd_cand)) return try allocator.dupe(u8, cwd_cand);
    }

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe = std.fs.selfExePath(&buf) catch return null;
    const exe_dir = std.fs.path.dirname(exe) orelse return null;
    // zig-out/bin → ../../.. → Jog tree root sibling
    const from_bin = try std.fs.path.join(allocator, &.{ exe_dir, "../../..", rel });
    defer allocator.free(from_bin);
    if (fileExists(from_bin)) {
        if (try isV2Jog(allocator, from_bin)) return try allocator.dupe(u8, from_bin);
    }
    // source-tree layout: JogBuild/zig-out/bin → JogBuild → sibling
    const from_build = try std.fs.path.join(allocator, &.{ exe_dir, "../..", rel });
    defer allocator.free(from_build);
    if (fileExists(from_build)) {
        if (try isV2Jog(allocator, from_build)) return try allocator.dupe(u8, from_build);
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
    // Match 0.2.x-v2 and any "v2" marker from JogCompiler v2.
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

/// Prefer a module directory (pass through to jog) when jog.mod exists;
/// otherwise keep the old main.jog fallback for plain directories.
fn resolveBuildPath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const st = std.fs.cwd().statFile(path) catch {
        return try allocator.dupe(u8, path);
    };
    if (st.kind == .directory) {
        const mod_path = try std.fs.path.join(allocator, &.{ path, "jog.mod" });
        defer allocator.free(mod_path);
        if (fileExists(mod_path)) {
            return try allocator.dupe(u8, path);
        }
        return try std.fs.path.join(allocator, &.{ path, "main.jog" });
    }
    // Bare jog.mod file → use its directory so deps/build see the module root.
    if (std.mem.eql(u8, std.fs.path.basename(path), "jog.mod")) {
        if (std.fs.path.dirname(path)) |dir| {
            return try allocator.dupe(u8, dir);
        }
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
