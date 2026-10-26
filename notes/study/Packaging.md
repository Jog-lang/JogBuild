---
status: draft
tags:
  - bootstrap
  - study
  - packages
  - tooling
---

# Packaging

Packaging answers three questions for a build: which modules make up this program, where their source is on disk, and how one module is shipped to someone else. It is phase P2.5 of [[bootstrap/Roadmap]]: `jog-build`, the build tool, written in Jog. The formats it implements are specified in [[design/Packages]]; this note is the background for writing it.

## Key ideas

### Manifests

A **manifest** states what a module *wants*: its name, its version, and the modules it depends on, each with a version requirement or a path. It is written by people and checked into the repository. `jog.mod` is Jog's manifest, `Cargo.toml` is Rust's, `go.mod` is Go's.

A manifest is intent, not fact. "Requires `json` 1.4.0" does not say which `json` ends up in the build, because other modules may require it too. Turning every manifest in the graph into one concrete set of modules is **resolution**.

### Semantic versions

[Semantic Versioning](https://semver.org/) gives a version three numbers, `MAJOR.MINOR.PATCH`. A patch release fixes bugs, a minor release adds things without breaking callers, and a major release may break them. Before 1.0.0 anything may change. A prerelease, such as `1.0.0-beta.2`, sorts before its release.

The numbers are a promise made by people, not something a tool can verify. The Cargo book's [SemVer Compatibility](https://doc.rust-lang.org/cargo/reference/semver.html) chapter lists which changes break callers in a language like Jog: removing a public item, adding a field to a struct that callers construct, changing a function signature.

### Resolution: SAT-style versus MVS

Most package managers (Cargo, npm, pip, Bundler) let a requirement be a **range**, such as `^1.4` (at least 1.4, below 2.0), and pick the **newest** version that satisfies every range in the graph. With ranges, choosing a version for one module changes which versions of its dependencies are allowed, so the solver searches with backtracking. In general this problem is NP-complete; it can encode boolean satisfiability, hence "SAT-style". It also means that the result of a build depends on what was published yesterday, which is why these tools need a lock file to make builds repeatable.

Go's **minimal version selection** (MVS) makes a requirement a **minimum** and picks, for each module, the **highest of the minimums** that appear anywhere in the graph. There are no upper bounds, so there is nothing to search: one walk over the graph gives the answer, and the answer only changes when a manifest changes. A newer release of a dependency is never picked up by accident. The cost is that an incompatible major version must be a different module; Go spells it with a `/v2` suffix on the module path.

Jog V1 has only local dependencies, so it needs neither: a module may appear once, and two different sources for it are an error. The design leaves MVS as the recommended rule for later; see "Decided" at the end of [[design/Packages]].

### Lock files

A **lock file** records the result of resolution: the exact version of every module in the graph, where it came from, and a hash of its content. It is written by the tool, not edited by people, and it is checked in for applications. With SAT-style resolution it is what makes a build repeatable. With MVS it is mostly about integrity: the versions already follow from the manifests, and the hashes catch a module whose content changed under the same version. Go splits this differently: `go.mod` already lists the selected versions, and `go.sum` holds the hashes.

A lock file must be **deterministic**: sorted, no timestamps, no absolute paths. Otherwise every build on another machine changes it, and the diff stops meaning anything.

### Content hashes

A hash of an archive's bytes changes when the archive is rewritten by a different tool, even if every file in it is the same. A **content hash** hashes the files instead. Go's `h1:` hash, for example, lists every file in sorted order as one line of "SHA-256 of the file, name", and hashes that list. Sorting matters: directory listing order differs between file systems, and the hash must not.

A cryptographic hash (SHA-256) is needed once archives come from a network, because an attacker can make a different file with the same CRC-32 in microseconds. CRC-32 is for detecting accidents, SHA-256 for detecting substitution.

### Archive formats

An archive packs a tree of files into one file. The two common families:

- **tar** is a sequence of 512-byte headers, each followed by the file's data. There is no index, so finding one file means reading everything before it. It has no compression of its own; `.tar.gz` runs the whole stream through gzip, so random access is lost entirely.
- **zip** compresses (or stores) each entry separately and ends with a **central directory**: an index of every entry and its offset. A reader can jump to any entry. Each entry carries a CRC-32 of its uncompressed bytes.

That index is why Java's `.jar`, Python's wheels, NuGet's `.nupkg`, VS Code's `.vsix`, Go's module zips, and Jog's `.jogz` are all zip files.

### The zip layout

A zip file is read from the **end**. Every number is little-endian.

```
[local file header 1][data 1]
[local file header 2][data 2]
...
[central directory header 1]
[central directory header 2]
...
[end of central directory record]
```

- The **local file header** is 30 bytes followed by the name and an extra field: signature `0x04034b50`, version needed, flags, compression method, DOS time, DOS date, CRC-32, compressed size, uncompressed size, name length, extra length. The file's data follows directly.
- The **central directory header** is 46 bytes followed by the name, an extra field, and a comment. It repeats the local header's fields and adds "version made by", a comment length, a disk number, internal and external attributes, and the **offset of the local header** from the start of the file. The signature is `0x02014b50`.
- The **end of central directory record** (EOCD) is 22 bytes plus an optional comment: signature `0x06054b50`, two disk numbers, the entry count on this disk and in total, the size of the central directory, its offset, and the comment length.

To read a zip:

1. Find the EOCD. It is the last 22 bytes when there is no comment. A comment can be up to 65 535 bytes, so scan backwards from `len - 22` for the signature, at most that far.
2. Read the central directory's offset and the entry count from the EOCD.
3. Walk the central directory headers. Each is `46 + name + extra + comment` bytes long.
4. For an entry's data, go to its local header offset, check the signature, and skip `30 + local name length + local extra length`. The local extra field may differ from the central one, so read its length from the local header, not the central one.
5. With method 0 (stored), the compressed and uncompressed sizes are equal and the data is the file itself.

The central directory is authoritative. A reader that walks local headers from the start instead breaks on archives with data descriptors (flag bit 3, sizes written after the data) and on archives that contain deleted or prepended data. A self-extracting `.exe` is a program with a zip appended, and it still works because offsets are found from the end.

Two zip details matter for reproducible archives. Times are MS-DOS times, with 2-second precision and years counted from 1980; writing a fixed 1980-01-01 00:00 keeps packing deterministic. And flag bit 11 says names are UTF-8; without it, a reader may assume an old code page.

### CRC-32

The zip CRC-32 is the reflected form of polynomial `0x04C11DB7`, which is `0xEDB88320` in the bit order the table uses. The register starts at `0xFFFFFFFF`, each byte updates it through a 256-entry table, and the result is the register's complement. The check value is `0xCBF43926` for the nine bytes `123456789`; test with that first.

`tests/jog/crc.jog` already builds exactly this table at compile time with `@comptime(makeCrcTable())`, and checks `CrcTable[1] == 0x77073096` and `CrcTable[255] == 0x2D02EF8D`.

### Caches

A **cache** holds unpacked dependencies so that a build does not unpack them again. Three properties make one trustworthy:

- **Keyed by identity.** One folder per module and version. Two builds that need the same version share it.
- **Immutable.** Nothing edits a folder once it is complete. A build that wants different files is a different version.
- **Atomic installs.** Unpack into a temporary folder, verify, and rename into place. A rename within one volume is atomic, so a crash leaves junk in `tmp/`, never a half-written module that looks complete.

And one rule keeps it safe: before writing any file, reject entry names with `..`, a leading `/`, a drive letter, or a backslash. Otherwise a crafted archive writes outside the cache ("zip slip").

## How the C V1 does it

There are no dependencies in V1 yet, but every piece the tool will drive exists:

- **Finding the module: `compiler/src/loader.c`.** `jog_load` calls `locate_roots`, which finds std and the runtime under `JOG_ROOT` or next to the executable (`exe_path`, `parent_dir`). `open_module` then calls `find_manifest`, which walks parent folders until it finds `jog.mod`, and reports a folder named `std` in the module root as shadowing the standard library.
- **Reading `jog.mod`: `parse_manifest`.** A line-based reader: `next_tok` splits a line into words and stops at `#`, `is_ident_token` checks the module name, and `manifest_pos` gives each error a line and column. It knows `module` and `link`; anything else is `unknown declaration`. The `link` names land in `JogProgram.link_libs`, declared in `compiler/src/program.h`.
- **Import paths to folders: `package_dir` and `collect_imports`.** A first segment of `std` means `program->std_root`; anything else is a folder under `program->module_root`. This is the function the module mapping changes: a third case, "a module this one requires", goes between the two. `load_package` and `load_files` then read the folder, and the `PkgState` colors detect import cycles, which is also the shape of the tool's module cycle check.
- **Command-line flags: `compiler/src/cmd_build.c`.** `parse_args` is where `--module` will be parsed, next to `--target` and `--comptime-steps`. `compile_pipeline` runs `jog_load`, `jog_check`, `jog_lower`, `jog_emit_c`, and `link_program`. `cmd_test.c` (`jog_cmd_test`) forwards to `jog_drive_test` in `cmd_build.c`.
- **Linking: `link_program` and `compiler/src/cc.c`.** `link_program` copies `program->link_libs` into a `JogCcRequest`, and `jog_cc_build` turns each one into `-l<name>` with `link_flag`. For wasm32, `jog_cc_build_wasm` rejects `link` lines.
- **Package paths in C names: `pkg_source`** in `lower.c`, `lower_package.c`, and `lower_generic.c` uses `JogPackage.path`, or the module name for the root package, as the prefix of every generated name. That is why a dependency's packages need a canonical path that includes its module name.
- **`@embed` stays inside the module: `jog_embed_resolve`** in `check_comptime.c` normalizes the path (`norm_path`) and checks `path_inside` against `program->module_root`.
- **CRC-32 and SHA-256** do not exist in the C code at all. The only CRC is the Jog test `tests/jog/crc.jog`. Both are new Jog code in `jog-build`.

## Questions to answer in your own words

1. Why can a C library ship as an `.a` file and headers, while a Jog library has to ship source? Name the three language features that force it.
2. What is the difference between a manifest and a lock file? Which one does a person edit, and which one should change when you edit a dependency's source in place?
3. MVS picks the highest of the minimums. Construct a three-module example where a SAT-style resolver with ranges picks a different version than MVS, and say which build you would rather debug.
4. Why does a zip reader start from the end of the file? What breaks if it walks the local headers from the front?
5. Why hash the files of a module rather than the bytes of its `.jogz`? Why sort the file list first?
6. Why does `jog-build` unpack into `tmp/` and rename, instead of unpacking straight into `mod/<module>/<version>/`?
7. Why is a folder named `sdl` in your module an error when your module requires `sdl`, and how is that the same rule as the existing one for `std`?
8. The compiler gets only `--module name=dir` flags. What does it still have to check itself, and why not trust the tool for those checks?

## Jog exercise

Write `ziplist`, which prints the size and name of every entry in a zip file. It uses `std.fs` to read the file, `std.os` for the argument, and `std.strbuilder` to format each line. Build it with `jog build` in its own folder, with a `jog.mod` that says `module ziplist`.

```
// ziplist: list the entries of a store-only zip file.
// usage: ziplist <file.zip>

import std.fs
import std.io
import std.mem
import std.os
import std.strbuilder

// Little-endian reads. The caller checks that the bytes are there:
// data.ptr is a raw pointer, so these reads are not bounds-checked.
fn u16_at(data: bytes, at: usize): u32 {
    return (data.ptr[at] as u32) | ((data.ptr[at + 1] as u32) << 8)
}

fn u32_at(data: bytes, at: usize): u32 {
    return u16_at(data, at) | (u16_at(data, at + 2) << 16)
}

// n bytes of data from at, as a str. No copy.
fn view(data: bytes, at: usize, n: usize): str {
    var out = bytes()
    out.ptr = data.ptr + at
    out.len = n
    return out
}

// The end of central directory record is 22 bytes plus a comment of at
// most 65535 bytes, so it starts in the last 65557 bytes of the file.
fn find_eocd(data: bytes): (usize, bool) {
    if data.len < 22 {
        return 0, false
    }
    var at = data.len - 22
    var left: usize = 65536
    for left > 0 {
        if u32_at(data, at) == 0x06054b50 {
            return at, true
        }
        if at == 0 {
            break
        }
        at = at - 1
        left = left - 1
    }
    return 0, false
}

fn free_bytes(data: bytes) with (a: mem.Allocator) {
    a.free(data)
}

fn fail(msg: str) {
    if !io.eprintln(msg) {
        return
    }
}

fn main() {
    if os.argc() != 2 {
        fail("usage: ziplist <file.zip>")
        return
    }
    val (data, ok) = fs.read_all(os.argv(1))
    if !ok {
        fail("cannot read the file")
        return
    }
    defer free_bytes(data)
    val (eocd, found) = find_eocd(data)
    if !found {
        fail("no end of central directory record")
        return
    }
    val count = u16_at(data, eocd + 10) as usize
    val cd_size = u32_at(data, eocd + 12) as usize
    var at = u32_at(data, eocd + 16) as usize
    if at > eocd || cd_size > eocd - at {
        fail("central directory is outside the file")
        return
    }
    var sb = strbuilder.empty()
    defer sb.free()
    for _ in 0 as usize..count {
        if eocd - at < 46 || u32_at(data, at) != 0x02014b50 {
            fail("bad central directory header")
            return
        }
        val method = u16_at(data, at + 10)
        val size = u32_at(data, at + 24)
        val name_len = u16_at(data, at + 28) as usize
        val extra_len = u16_at(data, at + 30) as usize
        val comment_len = u16_at(data, at + 32) as usize
        val total = 46 + name_len + extra_len + comment_len
        if eocd - at < total {
            fail("bad central directory header")
            return
        }
        sb.clear()
        sb.append_int(size as i64, 10)
        sb.append(" ")
        if method != 0 {
            sb.append("(compressed) ")
        }
        sb.append(view(data, at + 46, name_len))
        if !io.println(sb.str()) {
            return
        }
        at = at + total
    }
}
```

Make a test archive with `Compress-Archive -Path a.txt, b.txt -DestinationPath t.zip -CompressionLevel NoCompression`, then run `out\ziplist.exe t.zip`. The program above builds with the C `jog` today.

Then extend it:

- Follow each entry's local header offset, check the `0x04034b50` signature, and skip `30 + name + extra` using the **local** lengths. Print the first bytes of each stored file.
- Write `crc32(data: bytes): u32` with the table from `tests/jog/crc.jog`, test it on `123456789` (`0xCBF43926`), and verify every stored entry's CRC against the central directory.
- Reject what a `.jogz` reader must reject: a method other than 0, flag bit 3, a name with `..`, a leading `/`, a backslash or a drive letter, and a name that appears twice. Each rejection is a test with a hand-made archive in a `bytes` literal.
- Write the other direction, a store-only writer: given a sorted list of names and contents, produce local headers, data, a central directory and an EOCD, with the fixed DOS date `0x0021`. Check that `Expand-Archive` accepts the result and that writing twice gives identical bytes.
- Move the reader and writer into a `zip` package of `jog-build`. That package and the `jog.mod` parser are the first two pieces of P2.5.

## Reading

From [[bootstrap/Reading]]:

- The PKWARE APPNOTE, sections 4.3 (the layout) and 4.4 (the fields): the zip specification itself.
- Russ Cox, "Minimal Version Selection": the algorithm, and the argument against SAT-style solvers.
- The Cargo book, "The Manifest Format" and "Cargo.toml vs Cargo.lock": a mature manifest and a lock file, with the reasons for each.
- The Go Modules Reference, the sections on `go.mod`, minimal version selection, the module cache, and `go.sum`.

## See also

- [[bootstrap/Roadmap]]
- [[bootstrap/Checks]]
- [[bootstrap/Friction]]
- [[bootstrap/study/NameResolution]]
- [[design/Packages]]
- [[design/Modules]]
