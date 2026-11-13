# JogBuild (v2)

Zig front-end for **JogCompiler v2** (post-concurrency: Gates 1–4 + Chase-Lev). It finds the Zig-hosted `jog` and forwards `check` / `build` / `run` / `deps`.

Discovery order: `JOG`, `~/.local/bin/jog-v2`, sibling `../JogCompiler-v2/zig-out/bin/jog`, then PATH (`jog-v2` / v2 `jog`).

The v1 Jog-written tool (full package graph, `.jogz`, `--module`, libdir) lives on `main` and targets C/`jogc`. It is not used with v2.

## Build

```
zig build
./zig-out/bin/jog-build version
export JOG=/path/to/JogCompiler-v2/zig-out/bin/jog   # optional if sibling/jog-v2 found
./zig-out/bin/jog-build build examples/hello.jog -o out/hello
./zig-out/bin/jog-build run examples/hello.jog -o out/hello
```

Concurrency examples need **no extra flags** — `jog build` always links `runtime/linux_x64_coro.s` (go/yield, `with (Dispatcher)`, `dispatcher_io`, Chase-Lev pools).

```
./zig-out/bin/jog-build run examples/coro_yield.jog -o out/coro_yield
./zig-out/bin/jog-build deps examples/coro_mod
./zig-out/bin/jog-build run examples/coro_mod -o out/coro_mod
```

## Commands

| Command | Behavior |
|---|---|
| `version` | Print jog-build + jog versions |
| `check [path]` | `jog check` (`--diag=json` forwarded) |
| `build [path] -o OUT` | `jog build … -o OUT` (`--keep-asm` / `--keep-c` / `--libdir` forwarded) |
| `build … --target wasm32-emscripten` | Forwards to jog (JOG-90); default OUT `a.out.html` |
| `run [path] -o OUT [-- args]` | build then execute OUT (optional program args after `--`) |
| `deps [path]` | `jog deps` — one source path per line from `jog.mod` |

`path` may be a `.jog` file, a directory with `jog.mod`, or `jog.mod` itself. Directories without `jog.mod` fall back to `main.jog`.

Cross-module `require` / `--module` still deferred. Design: JogDocs `design/v2/`. Browser+SDL: JogSDL `v2/examples/*-emscripten` + emsdk.
