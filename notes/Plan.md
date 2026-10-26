---
status: draft
tags:
  - plan
  - packages
  - tooling
---

# Plan

How to write `jog-build`, in eleven milestones. Each one ends with something that runs and a test that proves it. The spec is [[Packages]] (`notes/Packages.md`, a copy of CTools `docs/design/Packages.md`); section names below in quotes, such as "jog.lock", are its headings. The background is [[study/Packaging]]. The checkboxes are in [[Checks]].

Ivan writes the code. This note says what to build, where, with which std calls, and how to know it is done. It does not say how to write each function.

## Ground rules

- **Layout.** `main.jog` is the root package, `jog_build`. Each concern is one package under `src/`, one file each, imported as `src.<name>`. Inside the module every import is relative to the root, so `src/pack/pack.jog` writes `import src.zip`. Tests sit next to the code as `src/<name>/<name>.test.jog`, as in std and JogLSP; `jog test` loads them for every package the root reaches. The skeleton's `cli` imports every package so that `jog check` covers all of them.
- **Build.** From the repo root: `D:\Projects\CTools\build\jog.exe build -o out/jog-build.exe`. Without `-o` the file is `out/jog_build.exe`, after the module name. `jog test` writes `out/jog_build.exe` too, as the test runner. Until the first `@test` exists, `jog test` runs `main` instead, which exits 2 with no arguments; that is why `jog test` fails on the bare skeleton.
- **Memory.** `main` opens `with (mem.heap())`. Every function that allocates takes `with (a: mem.Allocator)`. A command that does a lot of small allocations (resolution, pack) can run inside an `arena.init(0)` arena and `release()` it at the end: `var ar = arena.init(0)`, then `with (&ar) { ... }`, then `ar.release()`.
- **Generic values.** Declare an empty list as `var xs: list.List<str>`, as `std.fs` does. `list.empty<i64>()` fails with "cannot infer type parameter 'T'" (checked); that is a Friction.md entry.
- **Strings.** std has no substring, prefix test, or owned copy (CTools Friction.md, "std has no `str` substring, starts-with, or owned copy"). Add a tenth package, `src/text/text.jog`, in milestone 1, with JogLSP's `copy_str`, `free_str`, `starts_with`, and `view_range` (`server/src/text.jog`), plus `ends_with`, `index_of`, and `split` on one byte as you need them.
- **Paths.** std uses the ANSI Win32 calls, so keep test paths ASCII (CTools Friction.md, "std's Win32 bindings are the ANSI forms"). The cache root comes from `%LOCALAPPDATA%`, which contains the user name; a non-ASCII user name fails until that entry is fixed.
- **Missing Win32 calls.** std binds `CreateDirectoryA`, `RemoveDirectoryA`, `DeleteFileA`, and `GetTempPathA` in `std.c`. It does not bind `MoveFileExA`, `GetFileAttributesA`, `GetFullPathNameA`, or `GetCurrentDirectoryA`. Declare the ones you need in a `private extern { ... }` block in the package that uses them, the way JogLSP's `serve.jog` declares `_setmode`, and log each one in Friction.md.
- **Exit.** std.os has no `exit`; `main` calls `c.jogrt_exit(code)`.
- **Testdata.** A test finds `testdata/` the way JogLSP's `json.test.jog` does: `os.argv(0)` is `<root>/out/jog_build.exe`, so its grandparent is the repo root. For one fixed file, `@embed("../../testdata/...")` from `src/<name>/` also works, since the file is inside the module root. `.gitattributes` keeps `testdata/` byte for byte, so hashes and columns do not change on checkout.
- **Friction.** Every time Jog gets in the way, add an entry to CTools `docs/bootstrap/Friction.md` before working around it.

## Milestone 1: arguments and dispatch

- **Goal.** Every command parses its own flags, and bad usage is exit 2 with the usage text on stderr. The commands still do nothing.
- **Where.** `src/cli/cli.jog`, and the new `src/text/text.jog`.
- **std.** `os.argc`, `os.argv`; `io.eprintln`; `list.List<str>`.
- **Detail.** The flags per command are the table in "The build tool > V1 commands". Copy all of `os.argv` into a `List<str>` once in `run`, and make `parse_flags` take a `[]str` (`slice_view()`), so a test can pass a hand-made argument list. Match `jog`'s forms: `--target wasm32` and `--target=wasm32`, `-o file`. For `run`, everything after `--` goes to the program untouched. A flag that is not the command's own, a missing value after `-o` or `--target`, a second positional, or a value other than `wasm32` for `--target` is bad usage.
- **Tests.** `src/cli/cli.test.jog`: one test per command with its full flag set; `build --release --release-fast` and `test --all extra` are bad usage; `run -- --release` puts `--release` in the program's arguments; `deps --flags` sets `flags_only`.
- **Done when.** `out/jog-build.exe build --bogus` exits 2, `out/jog-build.exe build --release` reaches the stub and exits 1, and the tests pass.

## Milestone 2: the jog.mod parser

- **Goal.** `manifest.parse` turns `jog.mod` text into a `Manifest`, or reports the first error at the same line and column as `jog check`.
- **Where.** `src/manifest/manifest.jog`. Its header has the type sketch.
- **std.** `fs.read_all` for test inputs; `list.List`; `strbuilder` for `format` and for error messages (`append`, `append_int`).
- **Detail.**
  - "jog.mod v2 > Lexical rules": split on `\n` and drop a trailing `\r`; cut each line at the first `#`; words are separated by spaces or tabs. The column of a word is its byte offset in the line plus one. Keep the position of every word, since errors point at words.
  - "Directives": the table gives each directive's count and meaning. `module` comes first and once. `export` only with `kind library`, whichever order the lines come in, so check it after the whole file is read. `require` names must be identifiers, not `std`, not the module itself, and appear once.
  - A `require` spec is a path when it starts with `./`, `../`, `/`, `\`, or a drive letter and a colon; anything else must parse as a version.
  - The reserved names (`libdir`, `source`, `replace`, `config`, `include`, `exclude`, `provides`, `needs`) get `'<name>' is reserved for a later version`. Any other unknown directive is `unknown declaration '<name>'`. In `link.<target>`, the target must be `windows`, `linux`, or `macos`.
  - Versions: `MAJOR.MINOR.PATCH` with an optional `-prerelease`, as in [Semantic Versioning 2.0.0](https://semver.org/): no leading zeros in a number or a numeric prerelease identifier, no empty identifier, no `v`, and `+build` is an error. `jog` accepts numbers of any length (`99999999999999999999.0.0` is valid), so store each number as its digit string and compare by length, then by bytes. `parse_i64` would overflow.
  - Precedence (semver section 11): numbers first; a version with a prerelease is lower than the same version without one; prerelease identifiers compare left to right, numeric ones as numbers, others by bytes, numeric lower than alphanumeric, and a shorter list is lower when all shared identifiers are equal.
  - The error text the compiler prints is the model. The 29 cases under `testdata/manifest/invalid/` each hold the `jog.mod`, a `main.jog` so `jog check` runs there, and `expect.txt` with the first line `jog check` printed, with the folder path cut down to `jog.mod`. Two rules worth noticing: an empty or comment-only file is `missing module name` at 1:1, and `link.debug` is `unknown target`, not reserved.
  - **Normal form**, for `format`. The spec does not define one; this is a proposal. One line per directive, single spaces, no comments, no blank lines, `\n` endings, in the order `module`, `version`, `kind`, `jog`, then `require`, `export`, `link`, and `link.<target>` lines in their file order. Write `version`, `kind`, and `jog` only when the file had them, so `has_version` survives the round trip (pack needs to know).
- **Tests.** `src/manifest/manifest.test.jog`:
  - `testdata/manifest/valid/*.mod` all parse: `v1-hello.mod` and `v1-links.mod` (V1 files from CTools), `game.mod` and `sdl.mod` (the two examples in "jog.mod v2 > Example", byte for byte), and `crlf-prerelease.mod` (CRLF, tabs, a trailing comment, a prerelease, a drive-letter path). Spot-check fields: `game` has 3 requires, the second `is_path`, the third version 1.4.0; `sdl` is a library with exports `video`, `events` and three `link.<target>` lines.
  - Round trip each valid file: `parse(format(parse(text)))` equals `parse(text)`, and `format` is a fixed point.
  - For each folder in `testdata/manifest/invalid/`, the first error's line and column equal those in `expect.txt`. Compare the message too, once the positions match.
  - Versions: `1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0`, the chain from semver section 11.
  - Optionally, every `jog.mod` under CTools `examples/` and `tests/jog/pkg/modules/` parses, and the ones under `tests/jog/loader/` give the same first error as `jog check` there.
- **Done when.** All of the above pass.

## Milestone 3: the compiler command line, and build, run, test for path dependencies

- **Goal.** In `testdata/modules/app`, `jog-build build`, `run`, and `test` work, with `lib` required as `../lib`.
- **Where.** `src/compiler/compiler.jog` (find `jog`, build the argument list, run it); the first part of `src/resolve/resolve.jog` (path dependencies only, no cycle or conflict checks yet); `cmd_build`, `cmd_run`, `cmd_test` in `src/cli/cli.jog`.
- **std.** `os.env("JOG")`, `os.env("PATH")`; `fs.join`; `proc.run`, `proc.free_output`; `io.print`, `io.eprint`.
- **Detail.**
  - "Two programs": the compiler is `JOG` when set and non-empty, otherwise `jog` on `PATH`. `proc.run` does not search `PATH` (its header: "args[0] is the module, so PATH is not searched"), so split `PATH` on `;` and test `<dir>\jog.exe` for each entry. To test that a file exists, declare `GetFileAttributesA` (it returns `0xFFFFFFFF` for a missing path), or try `fs.read_all`, which reads the whole executable.
  - Find the module root the way the compiler does: walk up from the current folder until a folder holds `jog.mod`. `proc.run` has no working-directory parameter, so pass the root folder as the `[package]` argument rather than `.`: `jog build D:\...\app --module lib=D:\...\lib` works from any folder (checked).
  - "The compiler contract > The flag": one `--module <name>=<dir>` per module in the build, the whole graph, in resolution order, with `<dir>` absolute. Two argv entries, `--module` and `name=dir`, or one, `--module=name=dir`; `jog` accepts both. A mapping of a module nothing requires is an error in `jog`, and so is a transitive dependency without a mapping (checked with `testdata/graph/diamond`).
  - Absolute paths: there is no std call. Either declare `GetFullPathNameA`, or `GetCurrentDirectoryA` plus `fs.join` plus your own normalizer that removes `.` and `x/..` segments and turns `\` into `/`. Write the normalizer either way; milestone 5 compares folders with it.
  - The command: `[jog, sub, <root>, --module..., extra...]`. `build` passes `--release`, `--release-fast`, `--keep-c`, `--target`, `-o` through. `run` passes `--target`, then `--`, then the program's arguments. `test` passes `--all`. For a library, `build` runs `jog check` instead ("V1 commands"), and drops the flags `check` does not take.
  - Output: `proc.run` waits, then hands back stdout and stderr as bytes. Print stdout with `io.print`, stderr with `io.eprint`, and return `Output.code`. `ok == false` means the program did not start: print a message and return 1. Consequence: `jog-build run` shows the program's output only after it exits, and stdout and stderr are not interleaved. Log that in Friction.md; a streaming `proc` is the std fix.
- **Tests.**
  - `src/compiler/compiler.test.jog`: given a hand-built list of `(name, dir)` pairs, the argument list is exactly `[jog, "build", root, "--module", "a=...", "--module", "b=...", "--release"]`. Same for `run` with `--` and `test --all`. Library `build` becomes `check`.
  - Path normalization: `D:/x/../y/./z` is `D:/y/z`, `..\lib` from `D:\a\app` is `D:/a/lib`, and `testdata/graph/diamond/b`'s `../b/../c` is the same folder as `a`'s `../c`.
  - By hand, from `testdata/modules/app`: `..\..\..\out\jog-build.exe run` prints `app util`, `lib util`, `shapes`, `embed ok`. `..\..\..\out\jog-build.exe test` prints `app util` and `lib util` and exits 0; `lib/lib.test.jog` does not type-check, so a pass also proves the dependency's tests were not loaded. `build` writes `out\app.exe`.
  - With `JOG` unset and `D:\Projects\CTools\build` not on `PATH`, `jog-build build` says the compiler was not found and exits 1.
- **Done when.** The three commands work on the app, and the exit code of a failing build or test is the compiler's.

## Milestone 4: deps and deps --flags

- **Goal.** Print what resolution chose, for people and for JogLSP.
- **Where.** `cmd_deps` in `src/cli/cli.jog`; `compiler.module_flags` from milestone 3.
- **std.** `strbuilder` (`append`, `str`); `io.println`.
- **Detail.** "V1 commands": `deps` prints one line per module with name, version, source, and folder; `--flags` prints only the `--module` arguments, so that JogLSP can add them to its `jog check --diag=json` call. The output format is not fixed by the spec. Proposal: `deps` prints `<name> <version> <source> <dir>` per module, root excluded, in resolution order (the order of the flags); `--flags` prints one argument per line, `--module=<name>=<dir>`, so a consumer splits on newlines and never has to undo quoting, even with spaces in a path. `deps` also writes `jog.lock` ("jog.lock"), but that file arrives in milestone 10; add it there.
- **Tests.** In `testdata/modules/app`: `jog-build deps` prints one line for `lib`, version `0.2.0`, source `path`, and the absolute folder. `jog-build deps --flags` prints `--module=lib=<that folder>`. In `testdata/graph/diamond/app`, `c` comes before `a` and `b`.
- **Done when.** `jog check (jog-build deps --flags)` in PowerShell, run in `testdata/modules/app`, checks the app.

## Milestone 5: resolution

- **Goal.** The full graph for path dependencies, with every rule in "Resolution in V1" and its errors. Archive and version specs give "not supported yet" until milestone 9.
- **Where.** `src/resolve/resolve.jog`.
- **std.** `map.Map<str, usize>` from name to node index, with `map.fnv1a(name)` as the hash; `list.List`; `fs.read_all`; `manifest.parse`; `compiler.version` (run `jog version` once, parse `jog 0.0.1`).
- **Detail.**
  - Steps 1 to 6 of "Resolution in V1". A depth-first walk with three states per module, the same scheme as the `PkgState` colors (`PKG_GRAY`, `PKG_DONE`) in CTools `compiler/src/loader.c`: reaching a gray module is a cycle; post-order gives the step 6 order, dependencies first.
  - Keep the chain of names from the root to the current module. The cycle error is the chain from the repeated module back to itself, `a -> b -> a`. The conflict error has the exact shape in step 4, both chains included.
  - Each dependency's `jog.mod`: its `module` line equals the required name, its `kind` is `library`, and its `jog` line accepts the compiler's version. A parse error in a dependency's `jog.mod` is reported at that file's path, line, and column.
  - "Same thing" for a path dependency means the same normalized absolute folder. Windows paths are case-insensitive; compare the drive letter case-insensitively at least.
  - "The cache": two modules whose names differ only in case are an error. `jog` itself accepts that (checked with `testdata/graph/caseclash`), so only the tool catches it.
  - "std": `require std` is already a manifest error; a folder named after a required module is the compiler's check, leave it to `jog`.
- **Tests.** `src/resolve/resolve.test.jog`, one per folder under `testdata/graph/`. Each has an `app/` to resolve from:
  - `diamond`: nodes `c`, then `a` and `b`; `c` appears once even though `b` spells its path `../b/../c`. `jog run` with the three flags prints `c` twice (checked by hand).
  - `conflict`: `dep` from `../dep1` (1.0.0) and from `../dep2` via `mid` (1.1.0); one error naming both chains, and the compiler does not run.
  - `cycle`: `a -> b -> a`.
  - `wrongname`: `require util ../helper`, whose `jog.mod` says `module helper`.
  - `notlib`: `tool` is `kind executable`.
  - `newjog`: `future` needs `jog 9.0.0`.
  - `caseclash`: `Json` and `json`.
  - `missing`: `../gone` does not exist.
  - `badchild`: `child/jog.mod` has `version 1.0` on line 3; the error points at `child/jog.mod:3:9`.
  - `notcached`: `require json 1.4.0` gives, once milestone 9 exists, `module 'json' 1.4.0 is not in the cache; fetching is not available yet; require it by the path of its .jogz`.
- **Done when.** Every case gives its one error, or its graph, and `jog-build build` runs the compiler only when resolution succeeded.

## Milestone 6: CRC-32, the zip writer, the zip reader

- **Goal.** `zip.write` produces archives that Windows opens; `zip.read` reads them back and rejects everything "Container: zip" forbids.
- **Where.** `src/zip/zip.jog`.
- **std.** `list.List<zip.Entry>`; `fs.read_all`, `fs.write_all`; `c.CreateDirectoryA` for a scratch folder under `out/`.
- **Detail.**
  - CRC-32 first. Table-driven: CTools `tests/jog/crc.jog` builds the table as `val CrcTable = makeCrcTable()` with `@comptime` and checks `CrcTable[1] == 0x77073096` and `CrcTable[255] == 0x2D02EF8D`. Register starts at `0xFFFFFFFF`, each byte is `table[(crc ^ b) & 0xFF] ^ (crc >> 8)`, the result is `crc ^ 0xFFFFFFFF`. The check value for `123456789` is `0xCBF43926`.
  - The writer emits, for each entry, a local header and the data, then every central directory header, then the end record. All numbers are little-endian; write them with `append_byte` on a `StrBuilder`, or into one block sized up front. Fixed fields for every entry ("Container: zip"): version needed 10, flags `0x0800`, method 0, time 0, date `0x0021`, external attributes 0, extra and comment lengths 0. Entry order: `manifest`, then the rest sorted by name in byte order.

    | Local file header | offset | size | value |
    |---|---|---|---|
    | signature | 0 | 4 | `0x04034b50` |
    | version needed | 4 | 2 | 10 |
    | flags | 6 | 2 | `0x0800` |
    | method | 8 | 2 | 0 |
    | time, date | 10, 12 | 2, 2 | 0, `0x0021` |
    | CRC-32 | 14 | 4 | |
    | compressed, uncompressed size | 18, 22 | 4, 4 | equal, the data length |
    | name length, extra length | 26, 28 | 2, 2 | n, 0 |
    | name | 30 | n | |

    | Central directory header | offset | size | value |
    |---|---|---|---|
    | signature | 0 | 4 | `0x02014b50` |
    | version made by | 4 | 2 | not fixed by the spec; 10 is consistent |
    | version needed, flags, method, time, date | 6 to 14 | 2 each | as in the local header |
    | CRC-32, sizes | 16, 20, 24 | 4 each | as in the local header |
    | name, extra, comment length | 28, 30, 32 | 2 each | n, 0, 0 |
    | disk start, internal attributes | 34, 36 | 2, 2 | 0, 0 |
    | external attributes | 38 | 4 | 0 |
    | local header offset | 42 | 4 | from the start of the file |
    | name | 46 | n | |

    | End of central directory | offset | size | value |
    |---|---|---|---|
    | signature | 0 | 4 | `0x06054b50` |
    | this disk, disk with the directory | 4, 6 | 2, 2 | 0, 0 |
    | entries on this disk, in total | 8, 10 | 2, 2 | count, count |
    | directory size, directory offset | 12, 16 | 4, 4 | |
    | comment length | 20 | 2 | 0 |

  - The reader is the `ziplist` exercise in [[study/Packaging]], "Jog exercise", grown up: find the end record from the end, walk the central directory, follow each local header offset, check its signature, and skip `30 + name + extra` using the local lengths. Verify each CRC. Reject, before returning any entry: method other than 0 (the exact message is in "Container: zip"), a name that is empty, starts with `/`, contains `\`, has a drive letter, or has an empty, `.` or `..` segment, and a name that appears twice. Also check that every offset and length stays inside the file; a bounds error must be a message, never a crash.
  - The spec forbids bit 3, extra fields, ZIP64, encryption, and directory entries for writers. For readers it only names the method, the CRC, and the names. Decide whether the reader also rejects the rest; rejecting is simpler and safer.
- **Tests.** `src/zip/zip.test.jog`:
  - `crc32` of empty is 0, of `123456789` is `0xCBF43926`; `crc32_update(crc32(x), y) == crc32(x ++ y)` for a split string.
  - Write two entries, read them back, same names and bytes. Write the same list twice, byte-identical.
  - Write to `out/test/two.zip`, then in PowerShell: `Expand-Archive out/test/two.zip out/test/two -Force` and compare the files; `tar -tf out/test/two.zip` lists the names.
  - Read an archive made by Windows: `Compress-Archive -Path a.txt, b.txt -DestinationPath t.zip -CompressionLevel NoCompression`. With PowerShell 7.6, that writes method 0, flags 0 (bit 11 clear), version needed 20, no extra fields (checked), so a reader that does not insist on bit 11 and version 10 reads it.
  - `tar -a -cf t2.zip --options zip:compression=store a.txt b.txt` writes flag bit 3 and a 32-byte extra field in each local header (checked). Use it as the "data descriptor" rejection case, or as a tolerance case if you decide to accept extras.
  - Rejection cases built in the test by writing a good archive and patching bytes: method 8, a wrong CRC, `../x`, `/x`, `C:x`, `a\b`, `a//b`, a duplicate name, a central directory offset past the end, a truncated file.
- **Done when.** All tests pass, and `Expand-Archive` opens what the writer writes.

## Milestone 7: SHA-256 and the content hash

- **Goal.** `hash.sha256_hex` matches the standard vectors; `hash.content_hash` matches "Content hash".
- **Where.** `src/hash/hash.jog`.
- **std.** `strbuilder.append_int(n, 16)` does not pad, so write the hex digits yourself, two per byte.
- **Detail.**
  - FIPS 180-4 ([[Reading]]): constants in section 4.2.2, initial hash in 5.3.3, padding in 5.1.1 (a `1` bit, zeros, then the bit length as 64 bits big-endian, to a multiple of 512 bits), the computation in 6.2.2. Big-endian words, unlike zip.
  - Integer addition panics on overflow and there is no wrapping add (CTools Friction.md, "no `wrappingMul`"). Add in `u64` and mask with `0xFFFFFFFF`, as `map.fnv1a` does. Write the rotations in `u64` too, masking after the left shift, until you know whether `u32 <<` panics, truncates, or is rejected; log what you find.
  - Streaming state (`update` and `finish`) keeps a 1 MiB input out of one temporary block, and lets the content hash feed lines as it builds them.
  - "Content hash": names relative to `src/`, `/`-separated, sorted by byte value (`fs.list` sorts each folder, but a recursive walk must sort the full relative names, since `a/b` and `a.b` interleave differently); one line `<hex> <name>\n` per file; the result is `sha256:` and the hex of all lines.
- **Tests.** `src/hash/hash.test.jog`, vectors checked with .NET's SHA-256 on this machine:

  | input | SHA-256 |
  |---|---|
  | empty | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
  | `abc` | `ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad` |
  | `abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq` | `248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1` |
  | `abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu` | `cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1` |
  | 55 times `a` (padding fits in one block) | `9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318` |
  | 56 times `a` (padding needs a second block) | `b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a` |
  | 64 times `a` (one full block) | `ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb` |
  | 1 000 000 times `a` (the FIPS long vector) | `cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0` |
  | 1 048 576 times `a` (1 MiB, for [[Checks]]) | `9bc1b2a288b26af7257a36277ae3816a7d4f16e89c1e7e77d0a5c48bad62b360` |

  The same digests in several `update` calls of odd sizes (1, 63, 65 bytes) match one call.

  Content hash: `testdata/modules/lib`, with `lib.test.jog` excluded and nothing else to rewrite, gives the lines in `testdata/hash/lib.lines` and the hash in `testdata/hash/lib.hash`, `sha256:ceaa8c79...`. Those were computed with PowerShell's SHA-256 over the same rule; [[Checks]] has the command, so they can be recomputed if the fixture changes.
- **Done when.** Every vector and both content-hash files match.

## Milestone 8: pack

- **Goal.** `jog-build pack` in a library writes `out/<name>-<version>.jogz` and prints its path and hash.
- **Where.** `src/pack/pack.jog`; `cmd_pack` in `src/cli/cli.jog`.
- **std.** `fs.list`, `fs.join`, `fs.read_all`, `fs.write_all`, `fs.free_names`; `zip.write`; `hash.content_hash`; `c.CreateDirectoryA` for `out/`.
- **Detail.**
  - Order from "V1 commands": library only, explicit `version` required, resolve, run `jog check` with the flags, collect, rewrite, hash, write.
  - "Layout": the `src/` rules. Skip `out/`, any name starting with `.`, `jog.lock`, `*.test.jog`, and any subfolder with its own `jog.mod`. `fs.list` returns names with no file or folder flag; `fs.list(child)` succeeds only for a folder, or declare `GetFileAttributesA` and test `FILE_ATTRIBUTE_DIRECTORY` (`0x10`).
  - `src/jog.mod` is `jog.mod` with every path `require` line replaced by `require <module> <version>`, the version taken from the dependency (its `jog.mod`, or its archive's `manifest`). Every other line is copied as written, comments and blank lines included. If the dependency has no explicit version, pack fails.
  - The `manifest` entry ("Layout"): `archive 1`, then `module`, `version`, `kind`, `jog`, each `require` as a version, each `export`, and `hash` last, in the order of the example. No `link` lines. `testdata/manifest/valid/archive-manifest.txt` is the spec's example, with its hash shortened to `41ab07...` as in the spec, so it is a shape reference, not a valid hash.
  - Print the path and the hash, one per line or on one line; not fixed by the spec.
- **Tests.** In `testdata/pack/`:
  - `top` requires `base` by path and has every kind of excluded file: `top.test.jog`, `.hidden/`, `.editorconfig`, `jog.lock`, and `nested/` with its own `jog.mod`. The entries are exactly `testdata/pack/top.files`, `src/jog.mod` is exactly `testdata/pack/top.src.jog.mod` (the require line rewritten to `require base 0.3.0`), and the hash is `testdata/pack/top.hash`.
  - `testdata/modules/lib` packs to `out/lib-0.2.0.jogz` with hash `testdata/hash/lib.hash`.
  - `nover` (no `version` line) and `exe` (`kind executable`) fail with one message and exit 1.
  - Pack `top` twice: `(Get-FileHash a.jogz).Hash -eq (Get-FileHash b.jogz).Hash`. `Expand-Archive` opens it.
  - The archive passes `zip.read` from milestone 6.
- **Done when.** All of the above.

## Milestone 9: the cache and unpacking

- **Goal.** `require lib ../lib-0.2.0.jogz` installs the archive into the cache once and builds against `<cache>/mod/lib/0.2.0/src`; `require lib 0.2.0` then finds it there.
- **Where.** `src/cache/cache.jog`; the archive and version cases in `src/resolve/resolve.jog`.
- **std.** `os.env("JOG_CACHE")`, `os.env("LOCALAPPDATA")`; `fs.join`, `fs.list`, `fs.read_all`, `fs.write_all`; `c.CreateDirectoryA`, `c.RemoveDirectoryA`, `c.DeleteFileA`; `zip.read`; `hash.content_hash`; `manifest.parse` reused for the `manifest` entry.
- **Detail.**
  - "The cache": the root is `JOG_CACHE` when set and non-empty, else `%LOCALAPPDATA%\jog\cache`. The layout is `mod/<module>/<version>/manifest` and `.../src/...`, plus `tmp/`.
  - Install: read the archive, check `archive 1` (reject other versions; ignore top-level entries other than `manifest` and `src/`), verify CRCs and names (milestone 6), unpack into a new folder under `tmp/`, recompute the content hash from the extracted files and compare it with the manifest's `hash`, then rename the folder to `mod/<module>/<version>`. Create every parent with `CreateDirectoryA`, one segment at a time.
  - The rename: declare `MoveFileExA(existing, new, flags): c.int` in a `private extern` block, with flags 0 so it fails when the target exists. When it fails because another install won, compare hashes, as when the folder already existed.
  - A unique `tmp/` name: std has no process id or clock. Try `tmp/<module>-<version>-<n>` for n = 0, 1, 2, ... until `CreateDirectoryA` succeeds.
  - Already installed: read `mod/<module>/<version>/manifest`; same hash is a no-op, a different hash is the error "two different archives claim to be `<module> <version>`".
  - Tests cannot set environment variables (std has no `setenv`), so every cache function takes the root as a parameter; only `cache.dir()` reads the environment. End-to-end runs set `$env:JOG_CACHE` in PowerShell.
  - Resolution step 2 now handles all three spec kinds; the version case uses the exact "not in the cache" message from step 2.
- **Tests.**
  - `src/cache/cache.test.jog`, with a root under `out/test-cache`: install the `lib` archive from milestone 8; the folder exists with `manifest` and `src/`; installing again is a no-op; the extracted content hash equals `testdata/hash/lib.hash`.
  - Copy `testdata/modules/app` to `out/e2e/app`, change its require to `require lib ../lib-0.2.0.jogz` with the archive beside it, and `jog-build run` with `$env:JOG_CACHE = "$PWD\out\e2e\cache"` prints the same four lines as in milestone 3. A second run does not unpack again (nothing new under `tmp/`, the folder's timestamps unchanged).
  - A changed byte inside a stored file: rejected by its CRC, nothing left in `mod/`. A second archive of `lib 0.2.0` packed from a changed tree: rejected as a different hash. Hand-patched names with `..`, a leading `/`, `\`, or a drive letter: rejected before anything is written.
  - `testdata/graph/notcached`: the exact message.
- **Done when.** All of the above, and a crash halfway through an install (stop the process in a debugger, or return early in a test build) leaves only a folder under `tmp/`.

## Milestone 10: jog.lock

- **Goal.** `build`, `run`, `test`, `pack`, and `deps` write `jog.lock`, and two runs give byte-identical files.
- **Where.** `src/lockfile/lockfile.jog`; one call in each command in `src/cli/cli.jog`, after resolution and before the compiler runs.
- **std.** `strbuilder`; `fs.read_all` and `fs.write_all`; your own byte-order sort (`fs.list` sorts with a private insertion sort, `sort_names`, that you can copy).
- **Detail.** "jog.lock": `lock 1` first, one `dep <name> <version> <source> <location> <hash>` per module except the root, sorted by name, single spaces, `\n` line ends. Location is the spec as written with `/` separators, or `-` for `cache`; hash is `-` for `path`, the content hash otherwise. No timestamps and no absolute paths. Write only when the bytes differ from the file on disk. The spec's example starts with a comment line, `# jog.lock: written by jog-build, do not edit`, before `lock 1`; `testdata/lock/app.lock` includes it.
- **Tests.**
  - `src/lockfile/lockfile.test.jog`: entries given in any order format to the same text; an entry for each source kind formats as in the spec's example.
  - In `testdata/modules/app`, `jog-build build` writes a `jog.lock` equal to `testdata/lock/app.lock`. Running it again does not touch the file (`(Get-Item jog.lock).LastWriteTime` unchanged).
  - In a copy of `testdata/graph/diamond/app` with the two `require` lines swapped, the lock is byte-identical to the original's.
- **Done when.** All of the above.

## Milestone 11: init

- **Goal.** `jog-build init [--lib] [name]` starts a module that `jog-build build` (or `check`, for a library) accepts.
- **Where.** `cmd_init` in `src/cli/cli.jog`; `manifest.format` writes the file.
- **std.** `fs.write_all`, `fs.read_all` (to refuse to overwrite); `compiler.version` for the `jog` line.
- **Detail.** "V1 commands": `jog.mod` with `module`, `version 0.1.0`, the `kind`, and `jog <the current compiler version>`; a `main.jog` with an empty `main` for an executable, or `<name>.jog` for a library; and an ignore file for `out/` (`.gitignore` with `out/`). The name defaults to the folder name. Refuse when `jog.mod` already exists. When the folder name is not an identifier (as in `Jog-build`), stop with a message that asks for a name, rather than inventing one.
- **Tests.** In a fresh folder under `out/e2e/`: `init` then `build` works; `init --lib shapes` then `jog-build build` runs `jog check` and succeeds; a second `init` fails; `init 1bad` fails.
- **Done when.** All of the above.

## Later

Not in P2.5. Each one fits the formats as they are ("The build tool > Later"):

- `jog-build get` and fetching into `<cache>/dl/`; the `remote` source kind in `jog.lock`, with the archive hash next to the content hash.
- Minimal version selection: each `require` version a minimum, the build takes the highest ("Decided", item 2). It replaces the "must agree" rule in milestone 5.
- `jog-build publish`.
- Build configurations: `config` and `<directive>.<config>` selectors.
- `replace`, `libdir`, `source`, `include`, `exclude`, `provides`, `needs`; quoted words.
- DEFLATE entries, `obj/<target>/` precompiled objects, and the `iface/` summary in archives.

## Open points in the spec

These came up while planning. The spec says there are no open questions; these are smaller, and each milestone above says what it assumes. Settle them in CTools `docs/design/Packages.md` (the master copy), then copy the file here again.

1. "Decided" item 1 reads "The tool is called `jog-build`, not `jog-build`." The rejected name is missing.
2. [[study/Packaging]] says "see the open questions in [[design/Packages]]", which now has none, and the P2.5 "Decisions" box in Checks is unticked.
3. The examples in "jog.mod v2 > Example" say `jog 0.1.0`; the compiler is 0.0.1, so `jog check` rejects them as written (checked). Fine for the parser, not for running.
4. The lock location is "the spec as written in the `jog.mod` that first required it". "First" depends on the walk order, and so on the order of `require` lines, while Checks wants a lock that does not. In `testdata/graph/diamond`, `c` is `../c` from `a` and `../b/../c` from `b`.
5. A `path` location and an `archive` location are relative to the `jog.mod` that required them, which may be a dependency's, not the folder of `jog.lock`.
6. Whether the comment line in the `jog.lock` example is part of the format.
7. The output formats of `deps`, `deps --flags`, and `pack` are not fixed, and JogLSP will parse `deps --flags`. Milestone 4 has a proposal.
8. `pack` "fails if the dependency has none": `version` defaults to `0.0.0`, so "none" must mean "no `version` line", and the parser has to remember that. The same for pack's own "version is required".
9. Whether a path dependency and an archive of the same module and version count as "the same thing" in resolution step 4.
10. Which of the writer's restrictions (bit 3, bit 11, extra fields, directory entries, version needed 10, the entry order) a reader must enforce. `Compress-Archive` output has bit 11 clear.
11. "Version made by" in the central directory is not fixed.
12. Whether pack's exclusions of `out/` and `jog.lock` apply only at the module root or at any depth.
13. `<directive>.<config>` selectors are reserved, but `link.debug` is also an unknown target; `jog` reports `unknown target 'debug'` (checked).
14. Path comparison on Windows: case, `\` against `/`, and `C:` drive-relative specs.
15. What `init` does when the folder name is not an identifier.
16. What `build` does with `--release`, `-o` and the other build flags on a library, where it runs `jog check`.
17. The cache root when `LOCALAPPDATA` is unset, and on hosts with a non-ASCII user name.
18. Checks asks for SHA-256 of "a 1 MiB input"; the FIPS long vector is 1 000 000 bytes. Both digests are in milestone 7.

## P2.5 in CTools

The P2.5 sections of CTools `docs/bootstrap/Roadmap.md` and `docs/bootstrap/Checks.md`, copied as they are. The **Tool** boxes are this repo's; milestone numbers for each are in [[Checks]].

### P2.5: Packages and the build tool

The formats are specified in [[design/Packages]]. Two programs change, in this order:

1. **The C compiler** (done for you, in CTools). `jog.mod` v2 is accepted, and `jog check`, `build`, `run`, `test`, `emit-c` and `emit-ir` take `--module <name>=<dir>`, repeatable, mapping a module name to a source folder. Each rule in "The compiler contract" in [[design/Packages]] gets a regression test. This comes first, because the tool is tested against it.
2. **`jog-build`, the build tool** (you write it, in a new repository). In order:
   - the `jog.mod` v2 parser, checked against the manifests already in CTools;
   - resolution of local path dependencies, `jog.lock`, and running `jog` through `proc` with the `--module` flags;
   - a two-module example, an application plus a local library;
   - CRC-32 and SHA-256, then the store-only zip reader and writer;
   - `pack`, then unpacking a `.jogz` into the cache and building against it.

The tool's name, `jog-build`, and the other questions about the formats were decided at the start of this phase and are recorded under "Decided" at the end of [[design/Packages]]. JogLSP keeps calling `jog check --diag=json`; for a module with dependencies it adds the flags printed by `jog-build deps --flags`.

Not in this phase: fetching modules from the network (`jog-build get`), publishing, build configurations, `libdir`, and precompiled objects in archives. They wait until after P5, and the formats already leave room for them.

Study first: [[bootstrap/study/Packaging]].

## P2.5: Packages and the build tool

The formats and the compiler contract are in [[design/Packages]]. Items marked **C compiler** are CTools work done by the agent, with tests under `tests/`. Items marked **Tool** are `jog-build`, written by Ivan in Jog.

Decisions:

- [ ] The open questions at the end of [[design/Packages]] are answered there, including the tool's name, before the parser is written.

C compiler:

- [x] **C compiler.** `jog.mod` v2 is accepted: every directive in [[design/Packages]], their defaults, `link.<target>` filtered by the host, and the reserved names rejected with the reserved message. Every existing V1 manifest (`examples/hello`, `std/`*, `tests/jog/loader/*`) still loads with the same result.
- [x] **C compiler.** `--module <name>=<dir>` works on `check`, `build`, `run`, `test`, `emit-c` and `emit-ir`, with regression tests on the fixtures under `tests/jog/pkg/modules`, in `tests/loader_test.c` and `tests/package_test.c`, for: a working mapping, a required module with no mapping, a mapping whose `jog.mod` names another module, an unused mapping, a folder that shadows a required module, an import of a package that is not exported, a dependency's `*.test.jog` not being loaded, `@embed` bounded by the dependency's root, and link lines merged in order.
- [x] **C compiler.** `jog check` on a `kind library` module checks its exported packages, and `jog build` on a library fails with the library message.
- [x] **C compiler.** The `program.h` change is recorded in the contract change log of [[plans/V1Parallel]], and `pwsh scripts/check.ps1` prints `check: OK`.

Tool:

- [ ] **Tool.** JogBuild has a skeleton: `jog.mod`, `src/`, `tests/`, and a README that says how to build `jog-build` with `jog`.
- [ ] **Tool.** The `jog.mod` v2 parser round-trips both examples in [[design/Packages]]: parse, print in normal form, parse again, and get the same value. Every V1 manifest in CTools parses. For a folder of invalid manifests, the first error has the same line and column as the one `jog check` reports.
- [ ] **Tool.** CRC-32 gives `0xCBF43926` for `123456789`, and SHA-256 matches the standard test vectors for the empty string, `abc`, and a 1 MiB input.
- [ ] **Tool.** A two-module example, an application plus a local library required by path, builds and runs through `jog-build build` and `jog-build run`, and `jog-build test` runs only the application's tests.
- [ ] **Tool.** `jog-build pack` produces a `.jogz` that `Expand-Archive` (or `tar -tf`, or `unzip -l`) accepts, with every CRC correct. Packing the same tree twice gives byte-identical files.
- [ ] **Tool.** With `require <module> <path>.jogz`, the tool unpacks the archive into the cache, verifies the content hash, and builds against `<cache>/mod/<module>/<version>/src`. A second build does not unpack it again. An archive with a changed byte is rejected, and so are entry names with `..`, a leading `/`, a backslash or a drive letter.
- [ ] **Tool.** A version conflict (one module required from two different sources) is one clear error that names both requirement chains, and the compiler is not run.
- [ ] **Tool.** `jog.lock` is written deterministically: two runs give byte-identical files, and the result does not depend on the order of `require` lines or on directory listing order.
- [ ] **Tool.** Every rough edge found while writing `jog-build` is in [[bootstrap/Friction]].

## See also

- [[Packages]]
- [[Checks]]
- [[Reading]]
- [[study/Packaging]]
