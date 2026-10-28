#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Direct3D 12 for "graphics dxmt" bottles: VKD3D-Proton (+ DXVK's dxgi/d3d11/d3d10core) on VKD3D-Proton-MacOS's
# MoltenVK, ~9x faster than wined3d's vkd3d here (3DMark Steel Nomad 23.3 vs 2.54 fps, native Metal 29.9).
# Builds d3d12.dll/d3d12core.dll from VKD3D-Proton-MacOS v4.5's pinned sources plus patches/vkd3d-proton/*.patch;
# DXVK's DLLs and their MoltenVK + Apple's libmetalirconverter come from their v4.5 release (SHA-256 checked),
# since MoltenVK cannot be built without Xcode. Output: dist/lib/vkd3d-proton (run build-wine.sh first).
# Needs: llvm-mingw 20260616 (ucrt, macos-universal) in src/vkd3d-proton-macos/toolchain, meson, ninja, glslang.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src/vkd3d-proton-macos"
OUT="$ROOT/dist/lib/vkd3d-proton"
WINEBUILD="$ROOT/build/wine/tools/winebuild/winebuild"
TAG=v4.5
REV=153e9fb7765051781cf83fe9129ff40274ef5db5
REL=https://github.com/metalsharp/VKD3D-Proton-MacOS/releases/download/$TAG

[ -x "$WINEBUILD" ] || { echo "build wine first (no $WINEBUILD)"; exit 1; }
if [ ! -d "$SRC/.git" ]; then
  git clone -q https://github.com/metalsharp/VKD3D-Proton-MacOS.git "$SRC"
  git -C "$SRC" checkout -q "$REV"
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$REV" ] || { echo "$SRC is not at $TAG ($REV)"; exit 1; }
[ -d "$SRC/toolchain/llvm-mingw-20260616-ucrt-macos-universal" ] ||
  { echo "put llvm-mingw-20260616-ucrt-macos-universal (github.com/mstorsjo/llvm-mingw) in $SRC/toolchain"; exit 1; }

# their pinned vkd3d-proton + their patches, then ours (skipped when already applied)
[ -d "$SRC/sources/vkd3d-proton/.git" ] || bash "$SRC/scripts/fetch-sources.sh" vkd3d-proton
for p in "$ROOT"/patches/vkd3d-proton/*.patch; do
  if git -C "$SRC/sources/vkd3d-proton" apply --check "$p" 2>/dev/null; then
    git -C "$SRC/sources/vkd3d-proton" apply "$p"
  else
    git -C "$SRC/sources/vkd3d-proton" apply -R --check "$p" || { echo "patch no longer applies: $p"; exit 1; }
  fi
done
bash "$SRC/scripts/build-vkd3d-proton.sh"

# their release packages: DXVK's DLLs, MoltenVK + Apple's shader converter
fetch() { # file sha256
  local f="$ROOT/src/$1"
  [ -f "$f" ] || { curl -fL --retry 3 -o "$f.part" "$REL/$1"; mv "$f.part" "$f"; }
  echo "$2  $f" | shasum -a 256 -c - >/dev/null || { echo "checksum mismatch: $f (delete it and retry)"; exit 1; }
}
fetch vkd3d-proton-$TAG-x86_64.tar.zst a09c53914d4896048c5d4b877b585c649cf521a71e5c75c77cf0c901dcec5480
fetch moltenvk-$TAG-universal.tar.zst 379674c20aab61856f7e50a22181bd1c2c2439ff52d25cf430bf1c8cbd7e1d64
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for f in vkd3d-proton-$TAG-x86_64 moltenvk-$TAG-universal; do zstd -dc "$ROOT/src/$f.tar.zst" | tar -xf - -C "$TMP"; done

rm -rf "$OUT"; mkdir -p "$OUT/x86_64-windows" "$OUT/moltenvk"
cp "$SRC"/artifacts/build/vkd3d-proton/x86_64-windows/{d3d12,d3d12core}.dll "$OUT/x86_64-windows/"
cp "$TMP"/vkd3d-proton-$TAG-x86_64/x86_64-windows/{dxgi,d3d11,d3d10core}.dll "$OUT/x86_64-windows/"
# wine only loads builtin-marked DLLs from its DLL path (WINEDLLPATH_PREPEND_D3D12, see dll-path-prepend.patch)
for dll in "$OUT"/x86_64-windows/*.dll; do "$WINEBUILD" --builtin "$dll"; done
cp "$TMP"/moltenvk-$TAG-universal/{libMoltenVK.dylib,libmetalirconverter.dylib,LICENSE.MoltenVK,LICENSE.metal-shaderconverter.rtf,ACKNOWLEDGEMENTS.metal-shaderconverter.rtf} "$OUT/moltenvk/"
cp "$TMP"/vkd3d-proton-$TAG-x86_64/LICENSE* "$OUT/"
cat > "$OUT/PROVENANCE.txt" <<EOF
VKD3D-Proton-MacOS $TAG ($REV), https://github.com/metalsharp/VKD3D-Proton-MacOS
x86_64-windows/d3d12.dll, d3d12core.dll: built here from its pinned vkd3d-proton (LGPL-2.1) + patches/vkd3d-proton.
x86_64-windows/dxgi.dll, d3d11.dll, d3d10core.dll: DXVK v2.7.1 (zlib), from its vkd3d-proton-$TAG-x86_64 release.
moltenvk/libMoltenVK.dylib: its MoltenVK 1.4.3 build (Apache-2.0), from moltenvk-$TAG-universal (needs Xcode to build).
moltenvk/libmetalirconverter.dylib: Apple's Metal Shader Converter runtime, unmodified, Apple's license (section 2B).
All DLLs marked "Wine builtin" by winebuild --builtin. Personal use; keep the licenses next to the files.
EOF
echo "VKD3D-Proton ready in $OUT"
