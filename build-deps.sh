#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Build x86_64 deps (gmp, nettle, gnutls, freetype) from the CrossOver 26.3 source tree.
# Run natively (arm64): cross-compiles to x86_64 (macOS 27 CLT has no x86_64 slice).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
case "$ROOT" in *" "*) echo "path has spaces: run from a symlink without spaces (ln -s \"$ROOT\" ~/.cuvee)"; exit 1;; esac
SRC="$ROOT/src/sources"
DEPS="$ROOT/deps"          # install prefix for x86_64 libs
WORK="$ROOT/build/deps"
JOBS=$(sysctl -n hw.ncpu)

export PATH="/opt/homebrew/opt/bison/bin:/opt/homebrew/opt/flex/bin:/opt/homebrew/bin:$PATH"
export CC="clang -arch x86_64" CXX="clang++ -arch x86_64"
export CFLAGS="-O2 -mmacosx-version-min=11.0" CXXFLAGS="-O2 -mmacosx-version-min=11.0"
export LDFLAGS="-L$DEPS/lib -mmacosx-version-min=11.0" CPPFLAGS="-I$DEPS/include"
export PKG_CONFIG_PATH="$DEPS/lib/pkgconfig" PKG_CONFIG_LIBDIR="$DEPS/lib/pkgconfig"
HOST=x86_64-apple-darwin


build() { # name srcdir configure-args...
  local name=$1 dir=$2; shift 2
  [ -f "$WORK/$name.done" ] && { echo "== $name: already built"; return; }
  echo "== $name"
  rm -rf "$WORK/$name"; mkdir -p "$WORK/$name"; cp -Rp "$dir/." "$WORK/$name/"
  cd "$WORK/$name"
  [ -x configure ] || autoreconf -fi
  [ -f autogen.sh ] && [ ! -f builds/unix/configure ] && sh autogen.sh   # freetype git tree
  [ -d subprojects/dlg ] && [ ! -e src/dlg/dlg.c ] && mkdir -p include/dlg && touch src/dlg/dlg.c include/dlg/dlg.h include/dlg/output.h  # debug-only submodule, absent from tarball
  ./configure --build=aarch64-apple-darwin --host=$HOST --prefix="$DEPS" --disable-static "$@"
  make -j"$JOBS"
  make install
  touch "$WORK/$name.done"
}

mkdir -p "$WORK" "$DEPS"
build gmp      "$SRC/gnutls/gmp"    --enable-shared
build nettle   "$ROOT/src/nettle-3.10" --disable-documentation --disable-openssl
build gnutls   "$SRC/gnutls/gnutls" --with-included-libtasn1 --with-included-unistring \
               --without-p11-kit --without-idn --disable-gost \
               NETTLE_CFLAGS="-I$DEPS/include" NETTLE_LIBS=-lnettle HOGWEED_CFLAGS="-I$DEPS/include" HOGWEED_LIBS=-lhogweed --without-brotli --without-zstd --without-tpm --without-tpm2 \
               --disable-doc --disable-tests --disable-tools --disable-cxx --disable-guile --disable-nls
build freetype "$SRC/freetype"      --without-harfbuzz --without-png --without-brotli --without-bzip2 --with-zlib=no

echo "DEPS OK"
file "$DEPS"/lib/libgnutls*.dylib "$DEPS"/lib/libfreetype*.dylib | grep -c x86_64
