---
status: draft
tags:
  - reading
---

# Reading

The "Packages and archives" section of CTools `docs/bootstrap/Reading.md`, copied as it is, plus the SHA-256 standard. Every link was checked when this note was written.

## Packages and archives

- **Start here.** [APPNOTE.TXT: .ZIP File Format Specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT), PKWARE. `P2.5` The zip specification. Sections 4.3 (local file header, central directory, end of central directory record) and 4.4 (the fields, including CRC-32 and the flag bits) are all a store-only reader and writer need.
- **Start here.** [Minimal Version Selection](https://research.swtch.com/vgo-mvs), Russ Cox. `P2.5` The algorithm behind Go modules: a requirement is a minimum, and the build uses the highest minimum. It also argues why SAT-style solvers are the wrong default.
- [The Manifest Format](https://doc.rust-lang.org/cargo/reference/manifest.html), the Cargo book. `P2.5` A mature manifest: package metadata, targets, and dependencies. Compare each field with `jog.mod` v2.
- [Cargo.toml vs Cargo.lock](https://doc.rust-lang.org/cargo/guide/cargo-toml-vs-cargo-lock.html), the Cargo book. `P2.5` Why a manifest and a lock file are two files, and when to check the lock file in.
- [Go Modules Reference](https://go.dev/ref/mod). `P2.5` `go.mod`, minimal version selection, the module cache, module zip files, and `go.sum` hashes, in one long page. Skim the table of contents and read those sections.
- [Semantic Versioning 2.0.0](https://semver.org/). `P2.5` The version syntax `jog.mod` uses, and the precedence rules for prereleases.
- [SemVer Compatibility](https://doc.rust-lang.org/cargo/reference/semver.html), the Cargo book. `P2.5` Which changes to a library break its users, for a language with structs, generics and traits; most of it applies to Jog unchanged.

## SHA-256

- **Start here.** [FIPS 180-4, Secure Hash Standard](https://csrc.nist.gov/pubs/fips/180-4/upd1/final), NIST. The definition of SHA-256: the functions (4.1.2), the constants (4.2.2), padding (5.1.1), the initial hash value (5.3.3), and the computation (6.2). The page links the PDF.
- [SHA-256 example](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA256.pdf), NIST. Every intermediate value for `abc` and the two-block message, round by round; the fastest way to find which step of a wrong digest went wrong.

## See also

- [[Plan]]
- [[study/Packaging]]
