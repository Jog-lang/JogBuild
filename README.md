# JogBuild (v2)

Zig front-end for **JogCompiler v2**. It finds the Zig-hosted `jog` (`JOG`, then `jog-v2`, then the local `JogCompiler-v2` build) and forwards `check` / `build` / `run`.

The v1 Jog-written tool (module graph, `.jogz`, `--module`, libdir) lives on `main` / older branches and targets the C/`jogc` compilers. It is not used with v2.

## Build

```
zig build
./zig-out/bin/jog-build version
export JOG=/path/to/JogCompiler-v2/zig-out/bin/jog
./zig-out/bin/jog-build build examples/hello.jog -o out/hello
./zig-out/bin/jog-build run examples/hello.jog -o out/hello
```

## Commands

| Command | Behavior |
|---|---|
| `version` | Print jog-build + jog versions |
| `check [path]` | `jog check` (path or `dir/main.jog`) |
| `build [path] -o OUT` | `jog build … -o OUT` |
| `run [path] -o OUT` | build then execute |
| `deps` | no-op (module flags deferred) |

Design: JogDocs `design/v2/`.
