#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Build CrossOver 26.3's Wine (11.0) for macOS, x86_64 unix side + WoW64 PE (i386, x86_64).
# Run natively (arm64) from a path without spaces (e.g. a ~/.cuvee link). Compiles x86_64 with the arm64 toolchain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
case "$ROOT" in *" "*) echo "path has spaces: run from a symlink without spaces (ln -s \"$ROOT\" ~/.cuvee)"; exit 1;; esac
SRC="$ROOT/src/sources/wine"
DEPS="$ROOT/deps"
WORK="$ROOT/build/wine"
DIST="$ROOT/dist"           # final install: dist/bin/wine, dist/lib/wine/...
JOBS=$(sysctl -n hw.ncpu)


export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64"
export CFLAGS="-O2 -mmacosx-version-min=11.0 -Wno-error=incompatible-function-pointer-types -Wno-error=int-conversion"
export CPPFLAGS="-I$DEPS/include"
export LDFLAGS="-L$DEPS/lib -Wl,-rpath,@loader_path/../../ -Wl,-rpath,$DEPS/lib -mmacosx-version-min=11.0"
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig" PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
export x86_64_CC=x86_64-w64-mingw32-gcc i386_CC=i686-w64-mingw32-gcc

# our own patches (patches/*.patch, -p1 relative to the wine tree); skip if already applied, abort if it no longer applies
for p in "$ROOT"/patches/*.patch; do
  patch -d "$SRC" -p1 -R -s -f --dry-run < "$p" >/dev/null 2>&1 && continue
  patch -d "$SRC" -p1 -N -s < "$p" || { echo "PATCH FAILED: $p"; exit 1; }
done

# x86_64 wine. build=host=x86_64: wine tools are x86_64 and run under Rosetta; clang itself stays arm64.
mkdir -p "$WORK"
cd "$WORK"
if [ ! -f Makefile ]; then
  "$SRC/configure" --prefix="$DIST" --build=x86_64-apple-darwin --host=x86_64-apple-darwin \
    --enable-archs=i386,x86_64 --disable-tests \
    --without-x --without-wayland --without-fontconfig --without-dbus --without-alsa --without-oss \
    --without-pulse --without-udev --without-v4l2 --without-sane --without-gphoto --without-capi \
    --without-krb5 --without-gssapi --without-netapi --without-inotify --without-usb --without-pcap \
    --without-gstreamer --without-sdl --without-vulkan \
    --with-freetype --with-gnutls --with-mingw
fi
make -j"$JOBS"
make install

# bundle the x86_64 deps next to wine so dist/ is self-contained
mkdir -p "$DIST/lib"
cp -a "$DEPS"/lib/*.dylib "$DIST/lib/"

# MoltenVK (Vulkan->Metal, needed by wined3d's Vulkan renderer for D3D10/11): CodeWeavers' fork, Apache-2.0.
# Not shipped with Cuvee: taken from your own CrossOver install, or put your own build in dist/lib (see README).
MVK_TESTED_SHA=9343e68e5183c22e   # CrossOver 26.3's build, the one Cuvee was tested with
CX_MVK="$HOME/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/libMoltenVK.dylib"
[ -f "$CX_MVK" ] || CX_MVK="/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/libMoltenVK.dylib"
if [ ! -f "$DIST/lib/libMoltenVK.dylib" ] && [ -f "$CX_MVK" ]; then
  cp "$CX_MVK" "$DIST/lib/"
  cp "$SRC/../moltenvk/LICENSE" "$DIST/lib/MoltenVK-LICENSE.txt"
fi
if [ ! -f "$DIST/lib/libMoltenVK.dylib" ]; then
  echo "warning: no libMoltenVK.dylib in $DIST/lib: D3D10/11 games will fall back to OpenGL (see README)"
elif ! shasum -a 256 "$DIST/lib/libMoltenVK.dylib" | grep -q "^$MVK_TESTED_SHA"; then
  echo "warning: libMoltenVK.dylib differs from the tested build (CrossOver 26.3)"
fi
echo "WINE OK"
arch -x86_64 "$DIST/bin/wine" --version
