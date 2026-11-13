# Agents (JogBuild v2)

- Branch `v2` is the Zig tool for JogCompiler v2 (post-concurrency). Do not merge the Jog v1 tree into it.
- Compiler discovery: `JOG`, `~/.local/bin/jog-v2`, sibling `../JogCompiler-v2/zig-out/bin/jog`, then PATH.
- Gate: `zig build` and `jog-build check|build|run|deps` against a v2 `jog` ≥ 0.2.3-v2.
- Concurrency (`go`/`yield`, `with (Dispatcher)`, `dispatcher_io`, Chase-Lev): no JogBuild-side flags; compiler links coro runtime.
- `deps` / directory builds use minimal `jog.mod` (`module`/`version`/`root`/`source`). Cross-module `require` / `--module` still deferred.
- Do not start JogSDL / Emscripten work from this tree.
