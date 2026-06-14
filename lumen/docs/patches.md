# Lumen LLVM patches

These patches modify upstream `llvm/llvm-project` (pinned in
[`../LLVM_VERSION`](../LLVM_VERSION)) to make LLVM aware of the Lumen language.
`scripts/fetch.sh` applies every `patches/NNNN-*.patch` in order after checking
out the pinned tag.

## 0001-lumen-gc-strategy.patch

Adds a built-in **`gc "lumen"`** strategy to `llvm/lib/IR/BuiltinGCs.cpp`,
registered alongside LLVM's stock `erlang` / `ocaml` / `shadow-stack` /
`statepoint-example` / `coreclr` strategies.

**Why.** Lumen's runtime GC is a non-moving, generational mark/sweep collector
that finds roots by scanning the native stack. At `-O2`+ a stock backend may
keep live heap pointers only in registers across a call, where that scan can't
see them - a use-after-free hazard. Giving Lumen a named, recognized GC strategy
lets the toolchain reason about this explicitly.

**What it does.** The strategy is deliberately minimal:

- `UseStatepoints = false` - Lumen's collector never moves objects, so
  statepoint relocation (whose whole purpose is updating moved pointers) would
  be wasted.
- `UsesMetadata = false` - no stackmap/metadata tables, so no `GCMetadataPrinter`
  is required (an earlier draft set this `true` and aborted at lowering with
  "no GCMetadataPrinter registered for GC: lumen").
- `NeededSafePoints = true` - calls are treated as safepoints so the backend
  keeps the frame in a scannable state.

Lumen's frontend already keeps every live value in an entry-block alloca and
reloads it across calls, so root finding is precise and register-independent
without LLVM's metadata machinery. The strategy lowers cleanly at any opt level.
A Lumen function opts in by emitting `define i64 @f(...) gc "lumen"`.

## 0002-lumen-triple-vendor.patch

Adds **`Lumen`** to `Triple::VendorType` (`Triple.h`) and wires the name<->enum
mapping in `Triple.cpp` (`getVendorTypeName` + `parseVendor`), so
`x86_64-lumen-windows-gnu` is a first-class, recognized target triple. This lets
the Lumen toolchain stamp its own vendor on emitted modules and lets tools
identify Lumen-produced objects.

## Applying by hand

`scripts/fetch.sh` applies these automatically. To do it manually:

```sh
cd llvm-project
git apply ../patches/0001-lumen-gc-strategy.patch
git apply ../patches/0002-lumen-triple-vendor.patch
```

## Regenerating after editing the source

If you edit the LLVM source in `llvm-project/`, regenerate the patches:

```sh
cd llvm-project
git diff llvm/lib/IR/BuiltinGCs.cpp \
    > ../patches/0001-lumen-gc-strategy.patch
git diff llvm/include/llvm/TargetParser/Triple.h \
         llvm/lib/TargetParser/Triple.cpp \
    > ../patches/0002-lumen-triple-vendor.patch
```

## Verifying

After building `llc` (`scripts/build.sh`), `tests/lumen_gc_triple.ll` exercises
both patches - a `gc "lumen"` function under an `x86_64-lumen-windows-gnu`
triple. It must lower to assembly without error:

```sh
build/bin/llc tests/lumen_gc_triple.ll -o -
```

See [`build-record.md`](build-record.md) for a full verified build + lowering
log.
