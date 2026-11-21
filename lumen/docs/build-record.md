# Build Record (`lumen-llvm` @ `llvmorg-21.1.6`)

A verified build and self-contained bundle of the Lumen-tuned LLVM 21.1.6 toolchain (`patches/0001-lumen-gc-strategy.patch` + `patches/0002-lumen-triple-vendor.patch`). See [`patches.md`](patches.md) for patch details.

## Built & Bundled Artifacts

Installed to `%LOCALAPPDATA%\Lumen\llvm` and `C:\llvm-build`, and packaged in `dist/lumen-llvm-llvmorg-21.1.6-x86_64-windows-gnu.zip`:

| Binary | Size | Purpose |
|---|---:|---|
| `bin/clang.exe` | 104.8 MB | Patched LLVM 21.1.6 C / LLVM-IR driver (`gc "lumen"`, `lumen` vendor triple, `fastcc i48`) |
| `bin/ld.lld.exe` | 65.4 MB | ELF + MinGW PE/COFF linker (hosted `.exe`/`.dll` + bare-metal `i686-unknown-none` `.elf` kernels) |
| `bin/lld-link.exe` | 65.4 MB | MSVC COFF linker for native Windows `.sys` kernel drivers (`/DRIVER /SUBSYSTEM:NATIVE /NODEFAULTLIB`) |
| `bin/llvm-ar.exe` (`ar.exe`) | 1.3 MB | Static library archiver for `--kind staticlib` C-ABI builds (`.a` / `.lib`) |

## Verification

1. **`tests/lumen_gc_triple.ll`**: Lowers `target triple = "x86_64-lumen-windows-gnu"` and `gc "lumen"` cleanly through the patched backend, spilling stack roots before `@lumen_collect`.
2. **`tests/lumen_systems_driver.ll`**: Lowers `internal fastcc i48` tail-recursive workers, `load/store volatile i32` MMIO accesses, and inline assembly x86 port I/O (`outb %al, %dx`, `pause`) under `gc "lumen"`.
3. **4-Target Standalone Clean-`PATH` Build**:
   - Hosted `.exe` (`tests/regressions/systems_memory.lm`)
   - Hosted C-ABI v2 `.dll` & `.a` (`tests/abi/run_abi_test.py`)
   - Bare-metal x86 Multiboot `.elf` kernel (`tests/freestanding/driver_serial.lm`, `5,480` bytes, verified in QEMU)
   - Native Windows PE32+ `.sys` kernel driver (`tests/kernel/driver.lm`, `2,048` bytes, linked via `lld-link.exe`)
