#!/usr/bin/env bash
# Zip a COMPLETE, self-contained clang+lld toolchain the Lumen installer drops
# into %LOCALAPPDATA%/Lumen/llvm. `lumenc` (compiler/src/llvm.rs) auto-detects
# that path, so once extracted `lumen build` works with no MSYS2 / winget /
# scoop and no PATH or --sysroot setup.
#
# IMPORTANT: a windows-gnu clang cannot compile the Lumen C runtime or link a
# PE/COFF exe on its own - lumen_rt.c includes <stdio.h>, <windows.h>,
# <winsock2.h>, <dirent.h>, <unistd.h>, and the link pulls -lkernel32 -lws2_32
# etc. So this bundle ships the patched clang/lld/llc PLUS a mingw sysroot
# (C/Win32 headers + CRT objects + import libs) + clang's resource dir + libgcc,
# laid out the way clang's MinGW driver probes so the sysroot is found relative
# to clang.exe with zero flags.
#
#   bash scripts/fetch.sh && bash scripts/build.sh && bash scripts/bundle.sh
#
# The patched clang comes from the from-source build (default: ./build, or
# $LUMEN_LLVM_BUILD, e.g. C:/llvm-build when the build lives off OneDrive). The
# mingw sysroot is harvested from an MSYS2 install (the build's host toolchain);
# only the libc/Win32 runtime is copied, never MSYS2's unrelated dev packages.
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="x86_64-w64-mingw32"
VER="$(tr -d '[:space:]' < LLVM_VERSION)"
OUT="dist/lumen-llvm-${VER}-x86_64-windows-gnu"

log() { printf '  %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

# --- locate the patched build ------------------------------------------------
# Prefer an explicit override, then the in-repo build/, then C:/llvm-build (the
# build-record.md convention: build dir kept off OneDrive on local disk).
BUILD=""
for d in "${LUMEN_LLVM_BUILD:-}" build /c/llvm-build; do
  [ -n "$d" ] && [ -f "$d/bin/clang.exe" ] && { BUILD="$d"; break; }
done
[ -n "$BUILD" ] || die "no patched clang found (run scripts/build.sh, or set LUMEN_LLVM_BUILD). Looked in: build/, C:/llvm-build"
log "patched build:   $BUILD"

# --- locate an MSYS2 mingw sysroot (headers + CRT + import libs) --------------
# The from-source build uses an MSYS2 clang/lld host toolchain (see
# build-record.md), so MSYS2 is present on a build host. Harvest its sysroot.
SYSROOT_SRC=""
for root in /c/msys64/mingw64 /c/msys64/ucrt64 "${LUMEN_MINGW:-}"; do
  [ -n "$root" ] && [ -f "$root/include/stdio.h" ] && { SYSROOT_SRC="$root"; break; }
done
[ -n "$SYSROOT_SRC" ] || die "no mingw sysroot (stdio.h) found. Install MSYS2 mingw-w64-x86_64-gcc, or set LUMEN_MINGW=<mingw prefix>."
log "mingw sysroot:   $SYSROOT_SRC"

# clang's versioned resource dir (builtin headers: stddef.h, immintrin.h, ...).
RES_SRC="$(ls -d "$BUILD"/lib/clang/* 2>/dev/null | sort -V | tail -1 || true)"
[ -n "$RES_SRC" ] || die "no clang resource dir at $BUILD/lib/clang/<ver>"
RES_VER="$(basename "$RES_SRC")"
log "clang resource:  $RES_SRC (v$RES_VER)"

# gcc lib dir (libgcc.a + crt startup objects clang links for unwinding/intrinsics).
GCC_SRC="$(ls -d "$SYSROOT_SRC"/lib/gcc/$TARGET/* 2>/dev/null | sort -V | tail -1 || true)"
GCC_VER="$([ -n "$GCC_SRC" ] && basename "$GCC_SRC" || echo '')"

# --- assemble the tree -------------------------------------------------------
rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/lib/clang" "$OUT/$TARGET/lib"
log "assembling -> $OUT"

# 1) the patched binaries. clang drives .ll+.c -> .o; ld.lld links; llc/clang++
#    are handy extras (llc also carries the gc/triple patches).
for b in clang clang++ ld.lld lld llc llvm-ar; do
  for ext in "" ".exe"; do
    [ -f "$BUILD/bin/$b$ext" ] && cp -p "$BUILD/bin/$b$ext" "$OUT/bin/"
  done
done
[ -f "$OUT/bin/clang.exe" ]  || die "clang.exe not copied from $BUILD/bin"
[ -f "$OUT/bin/ld.lld.exe" ] || die "ld.lld.exe not copied from $BUILD/bin"
log "bin/ (patched clang + lld + llc)"

# 2) runtime DLLs the patched clang.exe imports. A from-source Release build
#    links against the MSYS2 host C++ runtime DLLs, which live in the mingw bin.
#    Copy them so the bundle runs on a machine with no MSYS2 at all. (A fully
#    static clang has none of these; the loop just no-ops then.)
DLL_SRC=""
for root in "$BUILD/bin" "$SYSROOT_SRC/bin" /c/msys64/mingw64/bin; do
  [ -f "$root/libwinpthread-1.dll" ] && { DLL_SRC="$root"; break; }
done
if [ -n "$DLL_SRC" ]; then
  for dll in libstdc++-6.dll libgcc_s_seh-1.dll libwinpthread-1.dll libc++.dll libunwind.dll; do
    [ -f "$DLL_SRC/$dll" ] && cp -p "$DLL_SRC/$dll" "$OUT/bin/"
  done
  for dll in "$BUILD"/bin/libLLVM*.dll "$BUILD"/bin/libclang-cpp*.dll; do
    [ -f "$dll" ] && cp -p "$dll" "$OUT/bin/" && log "bin/$(basename "$dll") (shared clang)"
  done
  log "bin/ runtime DLLs from $DLL_SRC"
fi

# 3) clang resource dir (builtin headers + compiler-rt). Drop the C++ builtin
#    headers - Lumen compiles only C.
cp -r "$RES_SRC" "$OUT/lib/clang/$RES_VER"
rm -rf "$OUT/lib/clang/$RES_VER/include/c++" 2>/dev/null || true
log "lib/clang/$RES_VER"

# 4) gcc libs (libgcc + crt startup objects). Skip the heavy C++/lto archives.
if [ -n "$GCC_VER" ]; then
  mkdir -p "$OUT/lib/gcc/$TARGET/$GCC_VER"
  for a in libgcc.a libgcc_eh.a libgcc_s.a; do
    [ -f "$GCC_SRC/$a" ] && cp -p "$GCC_SRC/$a" "$OUT/lib/gcc/$TARGET/$GCC_VER/"
  done
  cp -p "$GCC_SRC"/crt*.o "$OUT/lib/gcc/$TARGET/$GCC_VER/" 2>/dev/null || true
  log "lib/gcc/$TARGET/$GCC_VER (libgcc + crt)"
fi

# 5) the sysroot headers, where clang's MinGW driver probes
#    (<bundle>/x86_64-w64-mingw32/include). MSYS2 keeps them flat in
#    mingw64/include, so copy into the probed location. Drop the C++ stdlib and
#    unrelated dev-package headers (gtk/Qt/python/...) - Lumen links none.
cp -r "$SYSROOT_SRC/include" "$OUT/$TARGET/include"
for d in c++ clang gtk-3.0 gtk-4.0 glib-2.0 gstreamer-1.0 SDL2 SDL3 python3.* \
         OpenEXR Imath nss3 epoxy harfbuzz cairo pango-1.0 gdk-pixbuf-2.0 \
         librsvg-2.0 graphene-1.0 atk-1.0 webp libxml2 freetype2 fontconfig \
         hwy isl gmp ffmpeg libavcodec qt5 qt6 boost; do
  rm -rf "$OUT/$TARGET/include/"$d 2>/dev/null || true
done
log "$TARGET/include (C + Win32 headers; C++/dev headers dropped)"

# 6) CRT startup objects + a curated allowlist of the mingw C runtime + Win32
#    API import libs. MSYS2's mingw64/lib also holds ~1 GB of unrelated static
#    dev archives (librsvg, clang, Qt, ...) that no Lumen program links, and the
#    essential libmsvcrt/libkernel32 are themselves 1.5-2 MB, so a size cap
#    can't separate them - hence an explicit allowlist (~25 MB).
LIB_SRC=""
for d in "$SYSROOT_SRC/lib" "$SYSROOT_SRC/$TARGET/lib"; do
  [ -f "$d/libmsvcrt.a" ] && { LIB_SRC="$d"; break; }
done
[ -n "$LIB_SRC" ] || die "cannot find mingw import libs (libmsvcrt.a) under $SYSROOT_SRC"

RUNTIME_LIBS="libmingw32 libmingwex libmsvcrt libmoldname libpthread libwinpthread \
  libssp libssp_nonshared libgcc libgcc_eh libgcc_s libmcfgthread libgmon libm \
  libdmoldname libucrtbase libmsvcr120 libmsvcr110 libmsvcr100 libquadmath"
WIN32_LIBS="libkernel32 libuser32 libgdi32 libwinmm libws2_32 libadvapi32 libshell32 \
  libole32 liboleaut32 libuuid libcomdlg32 libcomctl32 libversion libsetupapi \
  libiphlpapi libpsapi libdbghelp libbcrypt libcrypt32 libsecur32 libwininet \
  libwinhttp libnetapi32 libuserenv libwtsapi32 libpowrprof libdwmapi libimm32 \
  libshlwapi librpcrt4 libntdll libmswsock libmpr libdnsapi libpdh libnormaliz \
  libwsock32 libwldap32 libsynchronization libwinspool libavrt libcfgmgr32"

shopt -s nullglob
n_o=0; n_a=0
for f in "$LIB_SRC"/*.o; do cp -p "$f" "$OUT/$TARGET/lib/"; n_o=$((n_o+1)); done
for l in $RUNTIME_LIBS $WIN32_LIBS; do
  [ -f "$LIB_SRC/$l.a" ] && { cp -p "$LIB_SRC/$l.a" "$OUT/$TARGET/lib/"; n_a=$((n_a+1)); }
done
shopt -u nullglob
log "$TARGET/lib ($n_o CRT objects + $n_a runtime/Win32 import libs)"

# 7) manifest the installer can read (version + provenance).
cat > "$OUT/lumen-llvm.json" <<JSON
{
  "name": "lumen-llvm-${VER}-x86_64-windows-gnu",
  "llvm_version": "$VER",
  "target": "$TARGET",
  "clang_resource": "$RES_VER",
  "gcc_libs": "${GCC_VER:-none}",
  "patched": true,
  "built": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "entry": "bin/clang.exe"
}
JSON

# 8) self-test the assembled bundle BEFORE zipping: compile + link a tiny C
#    program with a fully clean PATH, proving it's standalone. Catches a missing
#    header/lib here instead of on a user's machine.
log "self-test (clean-PATH compile + link)\u2026"
TMP="$(mktemp -d)"
printf '#include <stdio.h>\n#include <winsock2.h>\nint main(void){ printf("ok\\n"); return 0; }\n' > "$TMP/t.c"
if PATH="$(cd "$OUT/bin" && pwd):/c/Windows/System32:/c/Windows" \
     "$OUT/bin/clang.exe" -fuse-ld=lld -o "$TMP/t.exe" "$TMP/t.c" -lws2_32 2>"$TMP/err"; then
  log "self-test: build OK"
else
  cat "$TMP/err" >&2
  rm -rf "$TMP"
  die "self-test FAILED: the bundle cannot compile+link a standalone C program (missing sysroot piece?)"
fi
rm -rf "$TMP"

SIZE="$(du -sh "$OUT" | cut -f1)"
( cd dist && \
  if command -v 7z >/dev/null 2>&1; then 7z a -tzip -mx=9 "$(basename "$OUT").zip" "$(basename "$OUT")" >/dev/null;
  elif command -v zip >/dev/null 2>&1; then zip -qr9 "$(basename "$OUT").zip" "$(basename "$OUT")";
  else powershell -NoProfile -Command "Compress-Archive -Path '$(basename "$OUT")' -DestinationPath '$(basename "$OUT").zip' -Force"; fi )
ZSIZE="$(du -sh "$OUT.zip" | cut -f1)"

printf '\nbundle: %s.zip\n  tree: %s   zip: %s\n  upload as a release asset on this repo; the Lumen installer fetches it.\n' \
  "$OUT" "$SIZE" "$ZSIZE"
