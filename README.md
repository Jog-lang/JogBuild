# JogBuild

A build tool for Jog. It reads a module's `jog.mod`, resolves its dependencies (local folders and `.jogz` archives), unpacks archives into a per-user cache, writes `jog.lock`, packs libraries, and runs the compiler with one `--module <name>=<dir>` flag per dependency. It is written in Jog. The format it follows is `design/Packages.md` in JogDocs.

The notes for this repo live in [JogDocs](https://github.com/Jog-lang/JogDocs), not here. `notes/README.md` only points there.

The compiler command is `jog`. Set `JOG` to that binary, or put `jog` on `PATH`. From the repo root:

```
jog build -o out/jog-build
out/jog-build help
jog test
```

On Windows the compiler writes `out/jog-build.exe`. The tool itself builds for Windows, Linux, and macOS. `src/host` holds the `expect`/`actual` split: the compiler file name, the PATH separator, creating and deleting directories, and the default cache directory. `JOG_CACHE` wins when it is set. Otherwise the cache is `%LOCALAPPDATA%\jog\cache` on Windows, and `$XDG_CACHE_HOME/jog` or `$HOME/.cache/jog` on Linux and macOS.

The commands are `init`, `build`, `run`, `test`, `pack`, `deps`, and `help`. The eleven milestones in JogDocs `projects/JogBuild/Checks.md` are done. The two Throughout boxes there are still open.

String copies and slices go through `std.fs` and `std.text`. The current directory is `fs.cwd`. Looking up the compiler uses `fs.exists`. PATH is split in `src/compiler`, on `;` and `jog.exe` for Windows, and on `:` and `jog` for Linux and macOS.

`find`, `version`, `module_root`, `resolve`, `pack`, `install`, and `write_if_changed` return `error?`. A missing compiler or module root is `ErrNotFound`. A bad read or a failed process start is that error. When the tool has already printed the explanation, the result is `ErrReported` from `src.fail`, and the caller does not print it again. `manifest.parse` still returns a `ParseError` with a line and column, because `error?` has no position.

- `AGENTS.md`: how this repo is worked on.
- JogDocs `projects/JogBuild/Plan.md`: the milestones and how each one was tested.
- JogDocs `projects/JogBuild/Checks.md`: the checklists.
- JogDocs `design/Packages.md` (the spec) and `bootstrap/study/Packaging.md` (the background).
- `testdata/`: the inputs the plan refers to.

Plan.md and Checks.md are Ivan's working checklists. He edits them in JogDocs `projects/JogBuild/`.
