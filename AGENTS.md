# Agents (JogBuild v2)

- Branch `v2` is the Zig tool for JogCompiler v2. Do not merge the Jog v1 tree into it.
- Compiler discovery: `JOG`, `~/.local/bin/jog-v2`, checkout `JogCompiler-v2/zig-out/bin/jog`, then PATH.
- Gate: `zig build` and `jog-build build` against a v2 `jog`.
- `deps` / directory builds use minimal `jog.mod` (`module`/`version`/`root`/`source`). Cross-module `require` / `--module` still deferred.
