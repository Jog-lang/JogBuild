# Jog-build

A build tool for Jog. It reads a module's `jog.mod`, resolves its dependencies (local folders and `.jogz` archives), unpacks archives into a per-user cache, writes `jog.lock`, packs libraries, and runs the compiler with one `--module <name>=<dir>` flag per dependency. It is written in Jog. The format it follows is `design/Packages.md` in JogDocs.

The notes for this repo live in JogDocs, at `D:/Projects/Jog/JogDocs` ([github.com/Jog-lang/JogDocs](https://github.com/Jog-lang/JogDocs)), not here. `notes/README.md` only points there.

The compiler command is `jog`. On this machine the binary is `D:\Projects\Jog\JogCompiler\build\jog.exe`. When `JOG` is set, that path is the compiler. From the repo root:

```
jog build -o out/jog-build.exe
out\jog-build.exe help
jog test
```

The commands are `init`, `build`, `run`, `test`, `pack`, `deps`, and `help`. The eleven milestones in JogDocs `projects/JogBuild/Checks.md` are done. The two Throughout boxes there are still open.

- `AGENTS.md`: how this repo is worked on.
- JogDocs `projects/JogBuild/Plan.md`: the milestones and how each one was tested.
- JogDocs `projects/JogBuild/Checks.md`: the checklists.
- JogDocs `design/Packages.md` (the spec) and `bootstrap/study/Packaging.md` (the background).
- `testdata/`: the inputs the plan refers to.

Plan.md and Checks.md are Ivan's working checklists. He edits them in JogDocs, in `D:/Projects/Jog/JogDocs/projects/JogBuild/`.
