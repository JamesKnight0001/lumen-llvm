# Build record

A verified from-source build of the Lumen-tuned LLVM, recorded so the patches in
`patches/` are demonstrably real, not theoretical. See [`patches.md`](patches.md)
for what each patch does.

## Built on

- Host: Windows, 12 cores, clang/lld 21.1.6 (MSYS2) as the host compiler.
- Source: `llvm/llvm-project` @ `llvmorg-21.1.6` (pinned in `LLVM_VERSION`) +
  `patches/0001-lumen-gc-strategy.patch` + `patches/0002-lumen-triple-vendor.patch`.
- Config: Release, `LLVM_TARGETS_TO_BUILD=X86`, projects `clang;lld`, tests off.
- Build dir: kept off OneDrive (local disk) to avoid per-file sync overhead.

## Result

```
bin/llc.exe      58 MB   (built first - validates BuiltinGCs.cpp + Triple.cpp)
bin/clang.exe   105 MB
bin/ld.lld.exe   65 MB
```
All linked with `CLANG_LLD_EXIT: 0`.

## Verification (the patches actually work)

### gc "lumen" + lumen triple lower through the forked llc

`build/bin/llc tests/lumen_gc_triple.ll -o -` exits 0 and emits valid x86-64
asm. The rooted value is spilled to a stack slot **before** the call into the
collector:

```asm
rooted:
    subq    $40, %rsp
    movq    %rcx, 32(%rsp)      # root stored to frame slot ...
    callq   lumen_collect       # ... before the collector runs (stays scannable)
```

Before the fix the strategy aborted with "no GCMetadataPrinter registered for
GC: lumen"; the final strategy is statepoint-free + metadata-free, so it lowers
cleanly with no printer. The `x86_64-lumen-windows-gnu` triple (lumen vendor) is
parsed and accepted.

### Full Lumen toolchain compiles real programs

Pointing Lumen's `lumen build --backend llvm` at the forked clang
(`LUMEN_CLANG=build/bin/clang.exe`) and running the 3-way conformance suite:

```
==== 3-way conformance: PASS=21 FAIL=0 SKIP=6 ====
```

21/21 examples byte-identical (interpreter == asm backend == forked-LLVM build).
A standalone program using both `gc "lumen"` and `target triple
x86_64-lumen-windows-gnu` compiles through the forked clang into a runnable exe.

## Reproduce

```sh
bash scripts/fetch.sh     # clone pinned upstream + apply patches/
bash scripts/build.sh     # cmake + ninja llc clang lld, then smoke-test the patches
```
