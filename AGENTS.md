# Agents (JogBuild v2)

## Jog knowledge

- Jog language notes, plans, checklists and the friction log live in JogDocs:
  Fedora `~/Documents/Projects/Jog/JogDocs` (or `/home/plague_doc/Documents/Projects/Jog/JogDocs`);
  Windows `D:/Projects/Jog/JogDocs`
  (https://github.com/Jog-lang/JogDocs).
- Read JogDocs `AGENTS.md` first, then `guide/JogQuickRef.md` before writing or reviewing Jog.
- Agent skills canon: JogDocs `.agents/skills/` (pointer: `.agents/skills/README.md` here). See `guide/UsingJogDocs.md`.
- Log rough edges in JogDocs `bootstrap/Friction.md`. Project note: `projects/JogBuild.md`.

## This repo

- Branch `v2` is the Zig tool for JogCompiler v2 (post-concurrency). Do not merge the Jog v1 tree into it.
- Compiler discovery: `JOG`, `~/.local/bin/jog-v2`, sibling `../JogCompiler-v2/zig-out/bin/jog`, then PATH.
- Gate: `zig build` and `jog-build check|build|run|deps` against a v2 `jog` ≥ 0.2.3-v2.
- Concurrency (`go`/`yield`, `with (Dispatcher)`, `dispatcher_io`, Chase-Lev): no JogBuild-side flags; compiler links coro runtime.
- `deps` / directory builds use minimal `jog.mod` (`module`/`version`/`root`/`source`). Cross-module `require` / `--module` still deferred.
- Ivan writes Jog by hand. Do not implement the tool's Jog logic unasked.
- Do not start JogSDL / Emscripten work from this tree.
