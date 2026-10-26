---
status: draft
tags:
  - design
  - modules
  - packages
  - tooling
---

# Packages

This note specifies the package formats and the build tool: `jog.mod` v2, the `jog.lock` lock file, the `.jogz` library archive, the dependency cache, and the contract between the build tool and the compiler. [[design/Modules]] keeps the concepts (packages, modules, import paths, dependency injection as module metadata); this note is the format specification. It is a separate note because it is long, and because a second implementation, the build tool written in Jog, has to follow it exactly.

The plan in [[bootstrap/Roadmap]] (phase P2.5) is to fix these formats before the self-hosted compiler, so that its loader is written once, against the final format. V1 implements local path dependencies, local archives, and library builds. Remote install, publishing, and build configurations come after the bootstrap. The formats leave room for them; nothing in this note has to change when they arrive.

## Two programs

- **`jog`, the compiler**, keeps reading source folders. It never reads a `.jogz`, never looks at the cache, and never follows a path in a `require` line. It gains one flag, `--module <name>=<dir>`, that maps a module name to a source folder. See "The compiler contract" below.
- **`jog-build`, the build tool**, is a separate program that Ivan writes in Jog, the way cargo sits next to rustc. It parses `jog.mod`, resolves dependencies, packs and unpacks `.jogz` archives into a per-user cache, writes `jog.lock`, and invokes the compiler with the right `--module` flags.

The self-hosted compiler `jogc` implements the same contract as `jog`, so `jog-build` works with either. `jog-build` finds the compiler in the `JOG` environment variable when it is set, and as `jog` on `PATH` otherwise.

## jog.mod v2

### Lexical rules

`jog.mod` stays line-based, as in V1. A line-based file needs no parser library in either C or Jog, diffs cleanly, and is enough for a flat list of facts. TOML or JSON would add nesting that nothing here needs.

- The file is UTF-8. Lines end in `\n` or `\r\n`.
- `#` starts a comment that runs to the end of the line, anywhere on the line. Blank lines are ignored.
- A line is a directive followed by words, separated by spaces or tabs. A word cannot contain a space, a tab, or `#`.
- A word that starts with `"` is an error in v2. Quoted words are reserved for a later version, for paths that contain spaces.
- Every error has a line and a column, `jog.mod:<line>:<col>: error: ...`, the same shape as the V1 loader's errors.

### Directives

| Directive | Count | Meaning |
|---|---|---|
| `module <name>` | exactly once, first | The module name. It is an identifier, it is the first segment of the module's import paths in other modules, and it names the root package. `std` is not allowed. |
| `version <semver>` | at most once | The module's version. Default `0.0.0`. |
| `kind executable` or `kind library` | at most once | Default `executable`. A library has no entry point and can be required by other modules. |
| `jog <semver>` | at most once | The minimum compiler version, compared with `jog version`. Default: any. |
| `require <module> <spec>` | repeatable, one per module | A dependency. `<spec>` is a path or a version. |
| `export <package path>` | repeatable, library only | A package that other modules may import. See "Exports" below. |
| `link <lib>` | repeatable | A C library to link on every native target, passed as `-l<lib>`. Unchanged from V1. |
| `link.<target> <lib>` | repeatable | The same, only when building for `<target>`: `windows`, `linux`, or `macos`. |

Versions follow [Semantic Versioning 2.0.0](https://semver.org/): `MAJOR.MINOR.PATCH`, with an optional `-prerelease`. There is no leading `v`, and build metadata (`+...`) is rejected because it plays no part in selection.

A `require` spec is a **path** when it starts with `./`, `../`, `/`, `\`, or a drive letter and a colon. Paths are relative to the folder that holds the `jog.mod` they appear in, and `/` works on every host. A path names either a module folder (one that contains a `jog.mod`) or a `.jogz` file. Any other spec must be a **version**. In V1 a version is looked up in the cache only, so it works after a `.jogz` has been unpacked there; fetching it comes later.

These directive names are **reserved**. V1 rejects them with `jog.mod: '<name>' is reserved for a later version`, so they can be added later without changing the meaning of any existing file:

- `libdir`, `libdir.<target>`: C library search paths, from [[design/Modules]].
- `source`, `replace`: where to fetch a module from, and a local override for one (Go's `replace`).
- `config`, and selectors of the form `<directive>.<config>`: build configurations.
- `include`, `exclude`: which files `pack` ships.
- `provides`, `needs`: the interfaces of dependency injection, from [[design/Modules]].

Any other unknown directive, and any unknown `.<target>` selector, is an error, as it is in V1.

### Example

An application that uses a local library folder, a local archive, and an archive already in the cache:

```
# jog.mod: a small SDL game
module game
version 0.3.0
kind executable
jog 0.0.1

require sdl ../sdl                          # a module folder next to this one
require mathx ../vendor/mathx-1.2.0.jogz    # a local archive, unpacked into the cache
require json 1.4.0                          # a version, already in the cache

link m                                      # every native target
link.windows ws2_32
```

The library it uses:

```
# jog.mod for ../sdl
module sdl
version 0.2.1
kind library
jog 0.0.1

require mathx ../vendor/mathx-1.2.0.jogz

export video
export events

link.windows SDL3
link.linux SDL3
link.macos SDL3
```

### Migration from V1

V1 accepts `module <name>` followed by `link <lib>` lines. Every such file is already a valid v2 file: it means version `0.0.0`, kind `executable`, any compiler, no dependencies. Nothing is rewritten and there is no format marker. `examples/hello/jog.mod`, the `std/*/jog.mod` files, and the manifests under `tests/jog/loader` stay as they are.

What changes in the C loader is the set of directives `parse_manifest` knows. Today any directive other than `module` and `link` is `unknown declaration`; after P2.5 the v2 directives are accepted and validated, the reserved ones get the reserved message, and everything else is still `unknown declaration`.

### Exports

A library with no `export` lines exports every package. A library with `export` lines exports its root package and exactly the listed packages; importing any other package of it from another module is an error. A package path in `export` is dot-separated and relative to the module root, like an import path. An executable cannot have `export` lines.

## jog.lock

`jog.lock` sits next to `jog.mod`. `jog-build` writes it on every `build`, `run`, `test`, `pack`, and `deps`, and only rewrites the file when its content changed. It records what resolution chose, so that a later build, or another machine, can see whether anything moved.

```
# jog.lock: written by jog-build, do not edit
lock 1
dep json 1.4.0 cache - sha256:0c6f1e...
dep mathx 1.2.0 archive ../vendor/mathx-1.2.0.jogz sha256:9f2c44...
dep sdl 0.2.1 path ../sdl -
```

- `lock 1` is the format version and comes first.
- One `dep` line per module in the build, the root excluded: name, version, source kind, location, content hash.
- Source kinds in V1: `path` (a module folder), `archive` (a local `.jogz`), `cache` (a version found in the cache). The location is the spec as written in the `jog.mod` that first required it, with `/` separators, or `-` for `cache`.
- A `path` dependency has no hash (`-`). Its source changes with every edit, and hashing it would make the lock file change on every build.
- Lines are sorted by module name, fields are separated by one space, lines end in `\n`, and the file ends in a newline. There are no timestamps and no absolute paths. Two runs over the same inputs write byte-identical files.

When remote fetch exists, the source kind `remote` is added with the URL it came from, and the line gains the hash of the archive bytes next to the content hash, the two hashes Go keeps in `go.sum`. Under minimum version selection (see "Resolution and the cache") the chosen versions already follow from the manifests, so the lock file's main job then is integrity: a module that comes back with a different hash is an error. If a field is added or changes meaning, the first line becomes `lock 2`.

## The .jogz library archive

### Why not an .a file and headers

A C library can ship as compiled objects plus headers because a header holds only declarations: everything the caller needs to compile a call is a prototype. A Jog library cannot be only an object file, for three reasons:

- **Generics are monomorphized at the caller.** `List<T>` has no machine code until some module uses `List<Token>`; the instance is generated when the user's program is compiled. That needs the generic bodies. See [[design/language/Generics]].
- **Compile-time execution needs bodies.** `@comptime(f())` and a top-level `val` run `f` in the interpreter during the consumer's build, and a later annotation function runs on the consumer's declarations. The interpreter runs IR, so it needs the code, not an object file. See [[design/language/Comptime]].
- **Inlining and contexts.** Contexts become hidden trailing parameters, and a private function's contexts are inferred from its body. The whole-program C backend also inlines across packages because it sees every body. See [[design/language/Contexts]].

Other languages answer this differently. **Go** ships source: a module is a zip of source files, and compiled packages are only a local build cache. **Rust** ships source to crates.io as well; the compiled form, an `.rlib`, is an archive of object code plus metadata that includes the MIR of generic and inline functions, so a downstream crate can instantiate them, and it only works with the exact compiler that wrote it. **C++** puts templates in headers, which means every user recompiles them and header text is the de facto interface; modules are the late fix. Jog takes Go's route for V1, with room for Rust's later: the archive always carries the source, and may later carry precompiled objects for the parts that do not need it.

### Container: zip

A `.jogz` is a zip file, as specified by the PKWARE APPNOTE (see [[bootstrap/study/Packaging]]). Zip rather than tar because:

- zip has a **central directory**, an index at the end of the file, so a reader can find `manifest` without reading every entry. Tar is a sequence of headers with no index.
- Every zip entry has a **CRC-32**, so corruption is caught per file. Tar has a checksum for headers only.
- Windows opens zip files natively (`Expand-Archive`, Explorer, and its bundled `tar.exe`), and so does every other platform. Precedent: Java's `.jar`, Python's wheels, NuGet packages, and Go's module zips are all zip.
- Tar is only useful compressed, which means implementing gzip and DEFLATE before reading anything. A store-only zip needs neither.

V1 archives are restricted, so that a Jog reader and writer stay small:

- Compression method 0 (stored) only. A reader rejects any other method with `archive '<file>': entry '<name>' uses compression method <n>; only stored entries are supported`. DEFLATE (method 8) can be allowed later by raising the archive version.
- The CRC-32 of every entry is required, and a reader verifies it.
- General purpose flag bit 3 (data descriptor) is clear, so sizes and CRCs are in the local headers. Bit 11 is set: names are UTF-8.
- No ZIP64, no encryption, no extra fields, no comments, no directory entries (directories are implied by the names). V1 archives are under 4 GiB and 65 535 entries.
- Version needed to extract is 10 (1.0, the default for stored files). Every entry's time and date are fixed at 1980-01-01 00:00 (DOS time 0, date `0x0021`), and external attributes are 0, so packing the same tree twice gives the same bytes.
- Entry names use `/`, are relative, contain no `.` or `..` segment, no drive letter, no backslash, and appear once. A reader rejects any archive that breaks one of these, before extracting anything. That closes "zip slip", where a crafted name writes outside the target folder.
- Entries are written in byte order of their names, after `manifest`, which is always first.

### Layout

```
sdl-0.2.1.jogz
  manifest                  archive metadata, read without unpacking the rest
  src/jog.mod               the module's jog.mod, with path requires replaced by versions
  src/sdl.jog               the root package
  src/video/video.jog
  src/events/events.jog
  src/assets/font.bin       any other file in the tree, such as an @embed input
  obj/<target>/...          later: precompiled objects
  iface/...                 reserved: an interface summary
```

**`manifest`** uses the same lexical rules as `jog.mod`:

```
archive 1
module sdl
version 0.2.1
kind library
jog 0.0.1
require mathx 1.2.0
export video
export events
hash sha256:41ab07...
```

- `archive 1` is the archive format version and comes first.
- `module`, `version`, `kind`, `jog`, `require`, and `export` repeat the module's `jog.mod`. Every `require` here is a version, never a path: `pack` replaces each path dependency with the version declared in that dependency's own `jog.mod`, and fails if the dependency has none.
- `hash` is the content hash of `src/`, defined below.
- `target <target>` lines, one for each `obj/<target>/` folder present, come with precompiled objects. V1 archives have none.
- `link` lines are not repeated here: the compiler reads them from `src/jog.mod`.

**`src/`** is the module tree. `pack` takes every regular file under the module root except: the `out/` folder, any file or folder whose name starts with `.`, `jog.lock`, `*.test.jog` files, and any subfolder that has its own `jog.mod` (that is another module). Shipping every other file is what makes `@embed` work in a dependency without the tool having to parse the source. `src/jog.mod` is the module's `jog.mod` with each path `require` line rewritten to `require <module> <version>`; every other line is copied as written.

**`obj/<target>/`** is reserved for precompiled C objects or a static library of the module's non-generic, non-inline code, keyed by target, such as `obj/windows-x64/sdl.a`. It is an optimization: the consumer still compiles generic instances and compile-time code from `src/`. It needs separate compilation in the C backend, which V1 does not have, so it comes later.

**`iface/`** is reserved for an interface summary: the exported declarations and their types, without private bodies, so that a checker or the language server could read a dependency without parsing all of its source. It is also where runtime reflection's type information, described in [[design/Modules]], would go.

V1 readers ignore top-level entries they do not know, and reject an `archive` version they do not know. Adding `obj/` and `iface/` therefore keeps `archive 1`; changing what an existing entry means raises it.

### Content hash

The content hash identifies the source of a module independently of how the zip was written:

1. List every file under `src/`, with names relative to `src/`, using `/`, sorted by byte value.
2. For each file, write one line: the lowercase hex SHA-256 of its bytes, one space, the name, `\n`.
3. The hash is `sha256:` followed by the lowercase hex SHA-256 of all those lines together.

This is the same construction as Go's `h1:` directory hash, with one space instead of two and hex instead of base64. `pack` computes it from the files it writes, and unpacking recomputes it from the files it extracted. SHA-256 is written in Jog as part of the tool; the CRC-32 in the zip catches corruption, and the SHA-256 catches substitution once archives come from the network.

V1 consumers compile from the shipped source. There is no other mode yet.

## Resolution and the cache

### The cache

Unpacked dependencies live in one per-user cache:

| Host | Default |
|---|---|
| Windows | `%LOCALAPPDATA%\jog\cache` |
| Linux and other POSIX | `$XDG_CACHE_HOME/jog`, or `$HOME/.cache/jog` when `XDG_CACHE_HOME` is unset |
| macOS | `$HOME/Library/Caches/jog` |

`JOG_CACHE` replaces the default when it is set and non-empty. Inside the cache:

```
<cache>/mod/<module>/<version>/manifest
<cache>/mod/<module>/<version>/src/...
<cache>/tmp/                        unpacking in progress
```

- A module name is an identifier and a version is semver, so both are safe as folder names on every host without escaping. Two modules in one build whose names differ only in case are an error, because they would share a folder on Windows.
- `<cache>/mod/<module>/<version>/` is immutable once it exists. `jog-build` unpacks into a fresh folder under `<cache>/tmp/`, verifies every CRC and the content hash, and then renames it into place. A crash leaves only a folder under `tmp/`, never a half-written module.
- If the folder already exists, `jog-build` compares the `hash` in its `manifest` with the archive being installed. A different hash for the same module and version is an error: two different archives claim to be `sdl 0.2.1`.
- Path dependencies are never copied into the cache. They are compiled from their own folder.
- Later, `<cache>/dl/` holds downloaded archives, and a build cache for `obj/` output can sit beside `mod/`. Neither changes `mod/`.

### Resolution in V1

`jog-build` resolves the whole graph before it runs the compiler:

1. Read the root `jog.mod`.
2. For each `require`, turn the spec into a source folder:
   - a module folder: that folder, made absolute;
   - a `.jogz` file: read its `manifest`, install it into the cache if it is not there, and use `<cache>/mod/<module>/<version>/src`;
   - a version: `<cache>/mod/<module>/<version>/src`, which must already exist. Otherwise the error is `module 'json' 1.4.0 is not in the cache; fetching is not available yet; require it by the path of its .jogz`.
3. Read that folder's `jog.mod`. Its `module` line must equal the required name, its `kind` must be `library`, and its `jog` line must accept the compiler. Then resolve its own `require` lines the same way, with paths relative to that folder.
4. **One version per module.** If a module is reached a second time, the second resolution must give the same thing: the same folder for path dependencies, the same version otherwise. If not, that is an error that names both requirement chains:

   ```
   jog.mod: error: module 'mathx' is required twice, with different sources:
     game -> sdl -> mathx 1.2.0 (archive ../vendor/mathx-1.2.0.jogz)
     game -> mathx 1.3.0 (path ../mathx)
   a build has one version of each module
   ```

5. A cycle between modules is an error that names the chain, `sdl -> mathx -> sdl`, the same shape as an import cycle in `loader.c`.
6. Order the modules so that each comes before the modules it requires, write `jog.lock`, and invoke the compiler.

When remote fetch exists, step 2 gains a fetch for a version that is not in the cache, and step 4 changes from "must be equal" to minimum version selection: each `require` gives a minimum, and the build uses the highest minimum of each module. That still yields one version per module, so the compiler contract does not change. Two incompatible major versions are then two different module names. See "Decided" at the end.

### std

std stays built in. It ships with the compiler (`JOG_ROOT/std`, or `<exe>/../std`), it is never a dependency, and it has no version of its own: a module states the std it needs with its `jog` line. `require std ...` and `module std` are errors, and `std` is resolved before any dependency name, so a dependency cannot shadow it. A folder called `std` in a module root is an error, as it is today.

### Import paths

From another module, a dependency's packages are imported with its module name as the first segment:

```
import sdl              // the root package of module sdl
import sdl.video        // package video of module sdl
import sdl.video as v
import std.io
import ui.widgets       // package ui/widgets of this module
```

Inside a module, import paths stay relative to that module's own root, exactly as in V1. So `sdl`'s own files write `import video`, not `import sdl.video`, and the library builds the same way alone and as a dependency. The first segment of an import in module `M` means, in this order:

1. `std`: the standard library.
2. A module that `M`'s `jog.mod` requires: that module's root folder.
3. Anything else: a folder under `M`'s root.

A folder in `M`'s root with the same name as a module `M` requires is an error (`folder 'sdl' shadows module 'sdl'`), for the same reason a folder named `std` is. A module can only import modules its own `jog.mod` requires; it does not see its dependencies' dependencies.

## The compiler contract

### The flag

```
jog check   [package] --module <name>=<dir> ...
jog build   [package] --module <name>=<dir> ... [other flags]
jog run     [package] --module <name>=<dir> ... [-- args...]
jog test    [package | --all] --module <name>=<dir> ...
jog emit-c  [package] --module <name>=<dir> ...
jog emit-ir [package] --module <name>=<dir> ...
```

`--module <name>=<dir>` is repeatable, and `--module=<name>=<dir>` is the same, as with `--target`. `jog-build` passes one for every module in the build, the whole graph and not only the root's direct dependencies, in the order from step 6 of the resolution. `<dir>` is the module's source folder: the dependency's own folder for a path dependency, `<cache>/mod/<module>/<version>/src` for an archive. The flag is the whole interface; the compiler reads nothing else from the tool, and someone can run it by hand.

### What the compiler does with it

1. **Validates the mapping.** `<name>` is an identifier, not `std`, not the root module's name, and appears once. `<dir>` contains a `jog.mod` whose `module` line is `<name>` and whose `kind` is `library`. A mapped module that no loaded `jog.mod` requires is an error. A required module with no mapping is an error when a file imports it: `module 'sdl' is required by jog.mod but was not given with --module; build with jog-build, or pass --module sdl=<dir>`.
2. **Reads every v2 directive** in each loaded `jog.mod`, the root's and each mapped module's. It uses `module`, `kind`, `jog`, the names in `require` (not their specs), `export`, `link`, and `link.<target>`. It ignores `version` and the `require` specs, which are the tool's business.
3. **Resolves imports** by the three rules above, per module. Each package's import path inside the program becomes canonical: unchanged for the root module, `<name>` and `<name>.<rest>` for a mapped module. That canonical path is `JogPackage.path`, so diagnostics, deduplication, and the generated C names (`jog_<package path>__<name>`, from `pkg_source` in `lower.c` and its siblings) stay unique across modules. A C name turns `.` into `_`, so a root package `lib_util` and a dependency's `lib.util` would share a prefix; packages of two different modules with the same C prefix are an error that names both.
4. **Enforces exports**, and the shadowing and visibility rules above.
5. **Loads tests only for the root module.** `*.test.jog` files of a mapped module are never loaded, with or without `jog test`.
6. **Bounds `@embed` by the owning module.** `jog_embed_resolve` checks that the file stays inside the root of the module that owns the source file, instead of always `program->module_root`.
7. **Merges link lines.** The root's `link` lines come first, then each mapped module's in `--module` order, keeping only the lines for the current target. A name that appears twice keeps its last position, which is the order a static link needs. On `--target wasm32` no `link.<target>` line applies, since wasm32 is none of `windows`, `linux`, and `macos`.
8. **Checks the `jog` line** of every loaded module against its own version.

### Libraries

There is no `jog build --lib`. Packing is purely the tool's job; the compiler only proves that a library builds:

- `jog check` on a module with `kind library` loads the root package and every package named by an `export` line, with their imports. A library's root package may be empty when it has `export` lines. With no `export` lines, it checks the root package and what that imports, as for an executable; a package nothing reaches is not checked, which is one reason to list exports.
- `jog test` on a library runs the `@test` functions of those packages, as for an executable.
- `jog build` and `jog run` on a library are an error: `module 'sdl' is a library; use jog check or jog test`.

### The C changes, exactly

This is the whole compiler side of P2.5, done in CTools by the agent:

- `loader.c`: `parse_manifest` accepts v2 (the directives, their defaults, the reserved names); `package_dir` and `collect_imports` resolve the first segment through the module mapping; `jog_load` loads mapped modules' `jog.mod` files and, for a library, the exported packages.
- `cmd_build.c`: `parse_args` accepts `--module` for every pipeline command, and `link_program` passes the merged link list. `cmd_test.c` passes `--module` through to `jog_drive_test`.
- `check_comptime.c`: the `@embed` boundary per module.
- `program.h`, a contract change through the process in [[plans/V1Parallel]]: `JogProgram` gains the module mapping from the command line, and `JogPackage` gains its owning module's name and root, added at the end of each struct. `resolve_package.c` then binds an import by its canonical path rather than by the path as written.
- Fixtures under `tests/jog/pkg/modules` (an application, a library, and one module per broken rule), with checks in `tests/loader_test.c` and end-to-end runs in `tests/package_test.c`.

The compiler does not read `.jogz`, does not touch the cache, does not follow `require` paths, does not compare versions, and does not write `jog.lock`.

## The build tool

### Name

The build tool is **`jog-build`** (see "Decided" below). The name says what the program does. It is a separate program, not the `jog build` subcommand: `jog build` compiles one tree of source folders, and `jog-build` resolves the dependencies first and then runs `jog build` with the `--module` flags.

### V1 commands

| Command | Does |
|---|---|
| `jog-build init [--lib] [name]` | Writes `jog.mod` (v2, `version 0.1.0`, the `kind`, and a `jog` line with the current compiler version), a `main.jog` or a library root file, and an ignore file for `out/`. The name defaults to the folder name. |
| `jog-build build [--release \| --release-fast] [--keep-c] [--target wasm32] [-o file]` | Resolves, writes `jog.lock`, and runs `jog build . --module ...` with the remaining flags. For a library it runs `jog check` instead. |
| `jog-build run [--target wasm32] [-- args...]` | The same, through `jog run`. |
| `jog-build test [--all]` | The same, through `jog test`. Only the root module's tests run. |
| `jog-build pack [-o file]` | Library only, and `version` is required. Resolves, runs `jog check`, collects `src/`, rewrites path requires, computes the content hash, and writes `out/<name>-<version>.jogz`. Prints the path and the hash. |
| `jog-build deps [--flags]` | Resolves, writes `jog.lock`, and prints one line per module: name, version, source, and folder. `--flags` prints only the `--module` arguments, so another program, such as JogLSP's `jog check --diag=json` call, can reuse them. |

Exit codes follow `jog`: 0 on success, 1 on an error, 2 on bad usage, and the compiler's or the program's exit code when one ran.

### Later

These wait until after P5. Each one fits the formats above as they are:

- **`jog-build get <module> [<version>]`** fetches a module into the cache and adds a `require` line. The `require <module> <version>` form already exists, the cache layout already has a place for it, and `jog.lock` gains the `remote` source kind. Module names are flat identifiers rather than URLs, so fetching needs a source for each name: a registry index, or the reserved `source` directive.
- **`jog-build publish`** uploads a `.jogz`. The archive already has no path dependencies, and its `manifest` has what an index needs: name, version, requirements, and hash.
- **Build configurations**, in the style of Gradle's build types, use the reserved `config` directive and `<directive>.<config>` selectors, the same selector syntax as `link.windows`. Precompiled objects would then live under `obj/<target>-<config>/`.
- **`replace`** for a local override of a fetched module, **`libdir`** for C library search paths, **DEFLATE** entries in archives, and the `iface/` summary.

## Decided

Ivan decided these at the start of P2.5. There are no open questions left in this note.

1. **The tool is called `jog-build`**, not `jogb`.
2. **A `require` version is a minimum.** Once fetching exists, it is resolved with minimal version selection, as in Go: the build uses the highest minimum of each module, with no solver. Until then a version must already be in the cache, and two requirements of one module must agree.
3. **A library imports its own packages relative to its own root**, as every module does in V1: `sdl` writes `import video`. The compiler gives each package a canonical path, `sdl.video`, from outside.
4. **With no `export` lines, every package of a library is exported.**
5. **`pack` ships every file except the listed exclusions**, so `@embed` works in a dependency without the tool parsing source.

## See also

- [[design/Modules]]
- [[design/Compiler]]
- [[design/language/Generics]]
- [[design/language/Comptime]]
- [[design/language/CInterop]]
- [[plans/V1Compiler]]
- [[plans/V1Parallel]]
- [[bootstrap/Roadmap]]
- [[bootstrap/Checks]]
- [[bootstrap/study/Packaging]]
- [[Home]]
