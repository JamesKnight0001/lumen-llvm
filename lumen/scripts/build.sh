#!/usr/bin/env bash
# Configure + build only what Lumen needs: clang + lld, X86 target, Release.
# Slim on purpose - we do not build the full LLVM tool/test surface.
set -euo pipefail
cd "$(dirname "$0")/.."

cmake -S llvm -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DLLVM_ENABLE_PROJECTS="clang;lld" \
  -DLLVM_TARGETS_TO_BUILD="X86" \
  -DLLVM_ENABLE_ASSERTIONS=OFF \
  -DLLVM_INCLUDE_TESTS=OFF \
  -DLLVM_INCLUDE_BENCHMARKS=OFF

# build the binaries Lumen drives. llc also exercises the Lumen GC strategy +
# triple patches, so it doubles as the patch-validation target.
ninja -C build llc clang lld
echo "built: build/bin/{llc,clang,lld}"

# smoke-test the Lumen-specific patches lowered cleanly
if [ -f tests/lumen_gc_triple.ll ]; then
  echo "verifying gc \"lumen\" + lumen triple..."
  build/bin/llc tests/lumen_gc_triple.ll -o - | head -5
fi
