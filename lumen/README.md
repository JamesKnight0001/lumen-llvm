# Lumen tooling (in the fork)

This directory holds the Lumen-specific tooling for the **lumen-llvm** fork of
`llvm/llvm-project`. The LLVM source here is the real thing and the two Lumen
patches are already applied in place as commits on the `lumen` branch:

- `gc "lumen"` strategy &mdash; `llvm/lib/IR/BuiltinGCs.cpp`
- the `lumen` triple vendor &mdash; `llvm/lib/TargetParser/Triple.cpp`,
  `llvm/include/llvm/TargetParser/Triple.h`

So there is no `fetch.sh` step (the source is the repo). Just build and bundle:

```sh
bash lumen/scripts/build.sh    # cmake + ninja: clang lld llc (X86, Release)
bash lumen/scripts/bundle.sh   # zip the slim, self-contained installer bundle
```

`lumen/scripts/build.sh` configures `cmake -S llvm -B build` at the repo root and
builds `llc clang lld`, then smoke-tests the patches via `lumen/tests/lumen_gc_triple.ll`.

`lumen/scripts/bundle.sh` packages a **complete, self-contained** toolchain
(patched clang + lld + clang's resource dir + libgcc + a mingw sysroot: C/Win32
headers, CRT objects, and the curated runtime/Win32 import libs) laid out so
clang finds its sysroot relative to `clang.exe` with no flags. The Lumen
installer drops it into `%LOCALAPPDATA%/Lumen/llvm`, where `lumenc` auto-detects
it &mdash; `lumen build` then works with no MSYS2 / winget / scoop prerequisite.
It runs a clean-PATH compile+link self-test before zipping.

`lumen/patches/` keeps the patches for record / regeneration; `lumen/docs/patches.md`
explains each. `lumen/LLVM_VERSION` records the upstream tag this branch is based
on (`llvmorg-21.1.6`).
