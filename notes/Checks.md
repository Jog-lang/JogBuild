---
status: draft
tags:
  - plan
  - checklist
---

# Checks

One checklist per milestone of [[Plan]]. A milestone is done when every box in it is ticked. Commands are PowerShell, run from the repo root unless they `cd` somewhere, with these two names:

```
$jog = "D:\Projects\CTools\build\jog.exe"
$jb  = "D:\Projects\Jog\Jog-build\out\jog-build.exe"
```

Build the tool with `& $jog build -o out/jog-build.exe`, and run the unit tests with `& $jog test`. `jog test` writes `out/jog_build.exe` as its runner, so `out/jog-build.exe` is not overwritten.

When a check fails because of Jog itself rather than your code, log it in CTools `docs/bootstrap/Friction.md` before working around it.

## Skeleton

- [x] `& $jog check` exits 0.
- [x] `& $jog build -o out/jog-build.exe` exits 0, and `& $jb help` prints the command list and exits 0.
- [x] `& $jb` and `& $jb frob` print the usage on stderr and exit 2.
- [x] `& $jb deps --flags` says it is not implemented and exits 1.
- [ ] `& $jog test` exits 0. Not yet: with no `@test` function anywhere, `jog test` runs `main` with no arguments, which prints the usage and exits 2 ("error: test exited with status 2"). The first test file, in milestone 1, fixes it. That behaviour is a Friction.md entry.

## Milestone 1: arguments and dispatch

- [ ] `src/text/text.jog` exists, with `copy_str`, `free_str`, `starts_with`, and `view_range`.
- [ ] `& $jog test` passes `src/cli/cli.test.jog`: every command's flags, every bad-usage case in [[Plan]].
- [ ] `& $jb build --bogus; $LASTEXITCODE` is 2. `& $jb build --release --release-fast; $LASTEXITCODE` is 2.
- [ ] `& $jb run -- --release` reaches `cmd_run` with `--release` as a program argument.

## Milestone 2: the jog.mod parser

- [ ] Every file in `testdata/manifest/valid/` parses, and its fields match the spot checks in [[Plan]].
- [ ] Round trip: for every valid file, `parse(format(parse(text)))` equals `parse(text)`, and `format` of that is the same text.
- [ ] For every folder in `testdata/manifest/invalid/`, the first error's line and column equal `expect.txt`. To see what `jog` says for a new case: `cd testdata/manifest/invalid/<case>; & $jog check`.
- [ ] The semver precedence chain from [[Plan]] sorts correctly, and `99999999999999999999.0.0` parses.
- [ ] Optional: every `jog.mod` under CTools `examples/` and `tests/jog/pkg/modules/` parses.

## Milestone 3: compiler command line; build, run, test with path dependencies

- [ ] `src/compiler/compiler.test.jog` passes: exact argument lists for `build`, `run`, `test`, and library `build` becoming `check`.
- [ ] Path normalization tests pass, including `testdata/graph/diamond/b`'s `../b/../c`.
- [ ] `cd testdata/modules/app; & $jb run` prints `app util`, `lib util`, `shapes`, `embed ok`, and exits 0.
- [ ] `cd testdata/modules/app; & $jb test` prints `app util` and `lib util` and exits 0. (`lib/lib.test.jog` does not type-check, so this also shows it was not loaded.)
- [ ] `cd testdata/modules/app; & $jb build; Test-Path out/app.exe` is True.
- [ ] `$env:JOG = "$jog"` is used when set; with `JOG` removed and CTools `build` not on `PATH`, `& $jb build` says the compiler was not found and exits 1.
- [ ] A compile error in `app/main.jog` (make one in a copy) makes `& $jb build` exit with `jog`'s code, 1.
- [ ] Tool box from CTools: "A two-module example, an application plus a local library required by path, builds and runs through `jog-build build` and `jog-build run`, and `jog-build test` runs only the application's tests."

## Milestone 4: deps and deps --flags

- [ ] `cd testdata/modules/app; & $jb deps` prints one line: `lib 0.2.0 path <absolute folder>`.
- [ ] `cd testdata/modules/app; & $jb deps --flags` prints `--module=lib=<absolute folder>`.
- [ ] `cd testdata/modules/app; & $jog check (& $jb deps --flags); $LASTEXITCODE` is 0.
- [ ] `cd testdata/graph/diamond/app; & $jb deps` lists `c` before `a` and `b`.

## Milestone 5: resolution

- [ ] `src/resolve/resolve.test.jog` has one test per folder in `testdata/graph/`, and they pass.
- [ ] `cd testdata/graph/diamond/app; & $jb run` prints `c` twice.
- [ ] `cd testdata/graph/conflict/app; & $jb build` prints one error that names `app -> dep 1.0.0 (path ../dep1)` and `app -> mid -> dep 1.1.0 (path ../dep2)`, ends with `a build has one version of each module`, exits 1, and does not run `jog` (no `out/` folder appears).
- [ ] `cd testdata/graph/cycle/app; & $jb build` reports `a -> b -> a`.
- [ ] `wrongname`, `notlib`, `newjog`, `caseclash`, `missing`, and `badchild` each print one error and exit 1. `badchild` points at `child/jog.mod:3:9`.
- [ ] Tool box from CTools: "A version conflict (one module required from two different sources) is one clear error that names both requirement chains, and the compiler is not run."

## Milestone 6: CRC-32 and zip

- [ ] `crc32` of `123456789` is `0xCBF43926`; of empty, 0; `crc32_update` over a split input equals one call.
- [ ] Write then read two entries: same names, same bytes. Two writes of the same entries are byte-identical.
- [ ] `Expand-Archive out/test/two.zip out/test/two -Force` succeeds and the files match; `tar -tf out/test/two.zip` lists both names.
- [ ] The reader accepts `Compress-Archive -Path a.txt, b.txt -DestinationPath out/test/ps.zip -CompressionLevel NoCompression` (method 0, flags 0, no extras with PowerShell 7.6).
- [ ] `tar -a -cf out/test/tar.zip --options zip:compression=store a.txt b.txt` (flag bit 3, extra fields) is rejected or accepted, as decided in [[Plan]], with a test either way.
- [ ] Rejections, each a test: method 8, a wrong CRC, `../x`, `/x`, `C:x`, `a\b`, `a//b`, a duplicate name, a directory offset past the end, a truncated file. None crashes.
- [ ] Tool box from CTools, first half: "CRC-32 gives `0xCBF43926` for `123456789`".

## Milestone 7: SHA-256 and the content hash

- [ ] Every vector in the table in [[Plan]], milestone 7, matches, in one `update` and in several of sizes 1, 63, and 65.
- [ ] The content hash of `testdata/modules/lib` (without `lib.test.jog`) gives the lines in `testdata/hash/lib.lines` and the value in `testdata/hash/lib.hash`.
- [ ] Tool box from CTools, second half: "SHA-256 matches the standard test vectors for the empty string, `abc`, and a 1 MiB input."

The reference values were computed with .NET's SHA-256. To recompute the content hash of a folder by the rule in "Content hash" (no exclusions or rewriting; for `lib`, delete `lib.test.jog` from a copy first):

```
$root = (Resolve-Path <folder>).Path
$sha = [Security.Cryptography.SHA256]::Create()
function Get-Hex([byte[]]$b) { ($sha.ComputeHash($b) | ForEach-Object { $_.ToString('x2') }) -join '' }
$names = [string[]](Get-ChildItem -Recurse -File $root | ForEach-Object { $_.FullName.Substring($root.Length + 1).Replace('\', '/') })
[Array]::Sort($names, [StringComparer]::Ordinal)
$lines = ($names | ForEach-Object { (Get-Hex ([IO.File]::ReadAllBytes("$root/$_"))) + " " + $_ + "`n" }) -join ''
"sha256:" + (Get-Hex ([Text.Encoding]::UTF8.GetBytes($lines)))
```

## Milestone 8: pack

- [ ] `cd testdata/pack/top; & $jb pack` writes `out/top-1.0.0.jogz` and prints its path and hash.
- [ ] Its entries, in order, are `testdata/pack/top.files`. Check with `tar -tf out/top-1.0.0.jogz` and with `zip.read`.
- [ ] Its `src/jog.mod` equals `testdata/pack/top.src.jog.mod`, and its hash equals `testdata/pack/top.hash`.
- [ ] `cd testdata/modules/lib; & $jb pack` gives the hash in `testdata/hash/lib.hash`.
- [ ] `cd testdata/pack/nover; & $jb pack` and `cd testdata/pack/exe; & $jb pack` each print one error and exit 1.
- [ ] Packing twice gives the same bytes: `(Get-FileHash a.jogz).Hash -eq (Get-FileHash b.jogz).Hash`.
- [ ] `Expand-Archive out/top-1.0.0.jogz out/x -Force` succeeds.
- [ ] Tool box from CTools: "`jog-build pack` produces a `.jogz` that `Expand-Archive` (or `tar -tf`, or `unzip -l`) accepts, with every CRC correct. Packing the same tree twice gives byte-identical files."

## Milestone 9: cache and unpacking

- [ ] `src/cache/cache.test.jog` installs `lib-0.2.0.jogz` under `out/test-cache`; `mod/lib/0.2.0/manifest` and `mod/lib/0.2.0/src/` exist; a second install is a no-op; the extracted content hash matches `testdata/hash/lib.hash`.
- [ ] End to end, in a copy at `out/e2e/app` requiring `lib ../lib-0.2.0.jogz`, with `$env:JOG_CACHE = "$PWD\out\e2e\cache"`: `& $jb run` prints the four lines of milestone 3. A second run unpacks nothing.
- [ ] After that, `require lib 0.2.0` builds from the cache.
- [ ] An archive with one changed data byte is rejected by its CRC, and nothing appears under `mod/`.
- [ ] A different archive claiming `lib 0.2.0` is rejected as a different hash.
- [ ] Archives with names `../x`, `/x`, `a\b`, `C:x` are rejected before any file is written.
- [ ] `cd testdata/graph/notcached/app; & $jb build` prints `module 'json' 1.4.0 is not in the cache; fetching is not available yet; require it by the path of its .jogz`.
- [ ] Tool box from CTools: "With `require <module> <path>.jogz`, the tool unpacks the archive into the cache, verifies the content hash, and builds against `<cache>/mod/<module>/<version>/src`. A second build does not unpack it again. An archive with a changed byte is rejected, and so are entry names with `..`, a leading `/`, a backslash or a drive letter."

## Milestone 10: jog.lock

- [ ] `cd testdata/modules/app; & $jb build; Compare-Object (Get-Content jog.lock) (Get-Content ../../lock/app.lock)` prints nothing, and `fc.exe /b jog.lock ..\..\lock\app.lock` agrees byte for byte.
- [ ] A second `& $jb build` leaves `(Get-Item jog.lock).LastWriteTime` unchanged.
- [ ] A copy of `testdata/graph/diamond/app` with its two `require` lines swapped writes a byte-identical `jog.lock`.
- [ ] `build`, `run`, `test`, `pack`, and `deps` all write it.
- [ ] Delete the generated `jog.lock` files under `testdata/` afterwards, or add them to `.gitignore`; only `testdata/pack/top/jog.lock` is a fixture.
- [ ] Tool box from CTools: "`jog.lock` is written deterministically: two runs give byte-identical files, and the result does not depend on the order of `require` lines or on directory listing order."

## Milestone 11: init

- [ ] `mkdir out/e2e/hello; cd out/e2e/hello; & $jb init; & $jb build` works, and `jog.mod` has `module hello`, `version 0.1.0`, `kind executable`, and `jog 0.0.1`.
- [ ] `mkdir out/e2e/shapes; cd out/e2e/shapes; & $jb init --lib; & $jb build` runs `jog check` and exits 0.
- [ ] A second `& $jb init` in the same folder fails and changes nothing.
- [ ] `& $jb init 1bad` fails with a message.

## Throughout

- [ ] Tool box from CTools: "JogBuild has a skeleton: `jog.mod`, `src/`, `tests/`, and a README that says how to build `jog-build` with `jog`." The skeleton has `jog.mod`, `src/`, and the README; unit tests are `*.test.jog` beside the code, and `testdata/` holds the fixtures. Add `tests/` for end-to-end scripts if you want the box literally.
- [ ] Tool box from CTools: "Every rough edge found while writing `jog-build` is in [[bootstrap/Friction]]."

## See also

- [[Plan]]
- [[Packages]]
- [[study/Packaging]]
