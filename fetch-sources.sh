#!/bin/bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Download and unpack the sources Cuvee builds from, checking their SHA-256:
#   CodeWeavers' public CrossOver 26.3 source release (Wine 11.0 + deps) and GNU nettle 3.10.
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

[ -d src/sources/wine ] || tar -xzf src/crossover-sources-26.3.0.tar.gz -C src
[ -d src/nettle-3.10 ] || tar -xzf src/nettle-3.10.tar.gz -C src
echo "sources ready in src/"
