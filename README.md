# Jog-build
a build tool for Jog. It is used alongside the Jog Compiler.

## Start here

`jog-build` reads a module's `jog.mod`, resolves its dependencies (local folders and `.jogz` archives), unpacks archives into a per-user cache, writes `jog.lock`, packs libraries, and runs the compiler with one `--module <name>=<dir>` flag per dependency. It is written in Jog. The format it follows is `notes/Packages.md`.

The compiler is `D:\Projects\CTools\build\jog.exe`. From the repo root:

```
D:\Projects\CTools\build\jog.exe build -o out/jog-build.exe
out\jog-build.exe help
D:\Projects\CTools\build\jog.exe test
```

Today only `help` works; every other command says it is not implemented yet. `jog test` fails until the first `@test` is written: with no tests it runs `main`, which exits 2 without arguments.

- `AGENTS.md`: how this repo is worked on.
- `notes/Plan.md`: what to implement, in order, and how to test each step.
- `notes/Checks.md`: the checklists.
- `testdata/`: the inputs the plan refers to.
