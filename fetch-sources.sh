#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Download and unpack the sources Cuvee builds from, checking their SHA-256:
#   CodeWeavers' public CrossOver 26.3 source release (Wine 11.0 + deps), GNU nettle 3.10, DXMT 0.80 and Wine Gecko 2.47.4.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p src

fetch() { # url sha256
  local file="src/${1##*/}"
  if [ ! -f "$file" ]; then
    curl -fL --retry 3 -o "$file.part" "$1"
    mv "$file.part" "$file"
  fi
  echo "$2  $file" | shasum -a 256 -c - || { echo "checksum mismatch: $file (delete it and retry)"; exit 1; }
}

fetch https://media.codeweavers.com/pub/crossover/source/crossover-sources-26.3.0.tar.gz \
      ac99c8ca4b3848f3e81784135f023df266b61c2345726ea55a50b3e030dd6872
fetch https://ftp.gnu.org/gnu/nettle/nettle-3.10.tar.gz \
      b4c518adb174e484cb4acea54118f02380c7133771e7e9beb98a0787194ee47c

# DXMT (Direct3D 10/11 on Metal, with MetalFX and DLSS->MetalFX), official release build: graphics option "dxmt"
fetch https://github.com/3Shain/dxmt/releases/download/v0.80/dxmt-v0.80-builtin.tar.gz \
      8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d

# Wine Gecko (the HTML engine behind mshtml, e.g. the EA app installer's window); SHA-256 as in dlls/appwiz.cpl/addons.c
fetch https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86.msi \
      26cecc47706b091908f7f814bddb074c61beb8063318e9efc5a7f789857793d6
fetch https://dl.winehq.org/wine/wine-gecko/2.47.4/wine-gecko-2.47.4-x86_64.msi \
      e590b7d988a32d6aa4cf1d8aa3aa3d33766fdd4cf4c89c2dcc2095ecb28d066f

[ -d src/sources/wine ] || tar -xzf src/crossover-sources-26.3.0.tar.gz -C src
[ -d src/nettle-3.10 ] || tar -xzf src/nettle-3.10.tar.gz -C src
echo "sources ready in src/"
