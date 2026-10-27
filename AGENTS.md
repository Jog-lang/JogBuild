# Agents

This repo is `jog-build`, the build tool for Jog, written in Jog. It is phase P2.5 of the bootstrap: the plan is JogDocs `projects/JogBuild/Plan.md`, the checklist JogDocs `projects/JogBuild/Checks.md`.

The Jog notes live in [JogDocs](https://github.com/Jog-lang/JogDocs). Read its `AGENTS.md`, then `guide/JogQuickRef.md`, before writing or reviewing Jog. This project's note is `projects/JogBuild.md`. `notes/` here only points to JogDocs; a code comment citing `notes/<file>` means the JogDocs file listed in `notes/README.md`.

Ivan writes the implementation himself, to learn and to test Jog. Do not implement the tool's logic unasked. Review, explain, point at the spec and at how the C compiler in JogCompiler does it, and write test fixtures when asked.

The spec is JogDocs `design/Packages.md`, and the background is JogDocs `bootstrap/study/Packaging.md`. The rest of the language spec is in JogDocs `design/`.

The compiler command is `jog` (`jog version` is 0.0.1). `JOG` is that binary when it is set; otherwise `jog` comes from `PATH`. Std is found relative to the compiler. The tool talks to it only through `--module <name>=<dir>` (or `--module=<name>=<dir>`), repeatable, on `check`, `build`, `run`, `test`, `emit-c` and `emit-ir`: one per module in the build, the whole graph, `<dir>` the module's source folder. See "The compiler contract" in the spec.

From the repo root:

```
jog check
jog build -o out/jog-build.exe
jog run -- help
jog test
```

The module is `jog_build` (a module name is an identifier), so without `-o` the program is `out/jog_build.exe`. Tests are `*.test.jog` next to the code; fixtures are in `testdata/`. `jog test` runs those tests. The eleven milestones in JogDocs `projects/JogBuild/Checks.md` are done.

Log every rough edge in Jog in JogDocs `bootstrap/Friction.md`.
