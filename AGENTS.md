# Agents

This repo is `jog-build`, the build tool for Jog, written in Jog. It is phase P2.5 of the bootstrap: the plan is `notes/Plan.md`, the checklist `notes/Checks.md`.

Ivan writes the implementation himself, to learn and to test Jog. Do not implement the tool's logic unasked. Review, explain, point at the spec and at how CTools does it, and write test fixtures when asked.

The spec is `notes/Packages.md`. Its master copy is `D:/Projects/CTools/docs/design/Packages.md`; change that one, then copy it here. The rest of the language spec is in `D:/Projects/CTools/docs`.

The compiler is `D:/Projects/CTools/build/jog.exe` (`jog version` is 0.0.1), and std is found relative to it. The tool talks to it only through `--module <name>=<dir>` (or `--module=<name>=<dir>`), repeatable, on `check`, `build`, `run`, `test`, `emit-c` and `emit-ir`: one per module in the build, the whole graph, `<dir>` the module's source folder. See "The compiler contract" in the spec.

From the repo root:

```
D:\Projects\CTools\build\jog.exe check
D:\Projects\CTools\build\jog.exe build -o out/jog-build.exe
D:\Projects\CTools\build\jog.exe run -- help
D:\Projects\CTools\build\jog.exe test
```

The module is `jog_build` (a module name is an identifier), so without `-o` the program is `out/jog_build.exe`. Tests are `*.test.jog` next to the code; fixtures are in `testdata/`. With no `@test` anywhere, `jog test` runs `main` and fails with status 2; that is expected on the bare skeleton.

Log every rough edge in Jog in `D:/Projects/CTools/docs/bootstrap/Friction.md`.
