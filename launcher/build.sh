#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Builds Cuvee.app (quick-launch window) and installs it in /Applications.
# Signed with a local self-signed certificate so macOS keeps any grant across rebuilds (ad hoc = new identity each build).
set -euo pipefail
cd "$(dirname "$0")"
INSTALL=1
AD_HOC=0
APP="${TMPDIR:-/tmp}/cuvee-build/Cuvee.app"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --output) APP="$2"; shift 2 ;;
        --no-install) INSTALL=0; shift ;;
        --ad-hoc) AD_HOC=1; shift ;;
        *) echo "usage: $0 [--output /absolute/path/Cuvee.app] [--no-install] [--ad-hoc]" >&2; exit 2 ;;
    esac
done
case "$APP" in /*/Cuvee.app) ;; *) echo "output must be an absolute path ending in /Cuvee.app" >&2; exit 2 ;; esac
if [ "$AD_HOC" = 0 ]; then

KEYCHAIN="$HOME/Library/Application Support/Cuvee/signing.keychain-db"   # private file, never in the search list
IDENTITY="Cuvee Local Signing"
# keyed on the identity, not the file: an interrupted first run leaves an empty keychain behind
# throwaway self-signed cert made on this Mac; "cuvee" and the empty keychain password are not secrets
if ! security find-identity -p codesigning "$KEYCHAIN" 2>/dev/null | grep -q "$IDENTITY"; then
    rm -f "$KEYCHAIN"
    tmp=$(mktemp -d)
    openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" -days 36500 -nodes \
        -subj "/CN=$IDENTITY" -addext "keyUsage=critical,digitalSignature" -addext "extendedKeyUsage=critical,codeSigning"
    openssl pkcs12 -export -out "$tmp/id.p12" -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -passout pass:cuvee
    mkdir -p "$(dirname "$KEYCHAIN")"
    security create-keychain -p "" "$KEYCHAIN"
    security unlock-keychain -p "" "$KEYCHAIN"
    security import "$tmp/id.p12" -k "$KEYCHAIN" -P cuvee -T /usr/bin/codesign
    security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KEYCHAIN" >/dev/null
    rm -rf "$tmp"
fi
security unlock-keychain -p "" "$KEYCHAIN"
fi

# Assembled outside the Desktop: File Provider re-tags new files there and codesign then refuses the bundle.
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos14.0 -parse-as-library *.swift -o "$APP/Contents/MacOS/Cuvee"
cp Info.plist "$APP/Contents/"
cp ../branding/AppIcon.icns "$APP/Contents/Resources/"
xattr -cr "$APP"
if [ "$AD_HOC" = 1 ]; then
    codesign --force --sign - "$APP"
else
codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --identifier io.github.yesstonksman.cuvee "$APP"
req=$(codesign -d -r- "$APP" 2>&1)
grep -q 'certificate leaf' <<<"$req" || { echo "signature has no certificate" >&2; exit 1; }

fi
codesign --verify --strict "$APP"
if [ "$INSTALL" = 0 ]; then echo "→ $APP"; exit 0; fi
DEST=/Applications/Cuvee.app
rm -rf "$DEST"
cp -R "$APP" "$DEST"
# builds before 27-10-2026 went to ~/Applications: to the Trash, or Spotlight shows two Cuvee
OLD="$HOME/Applications/Cuvee.app"
if [ -d "$OLD" ]; then mv "$OLD" "$HOME/.Trash/Cuvee $(date +%Y%m%d-%H%M%S).app" || echo "move $OLD to the Trash by hand" >&2; fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
echo "→ $DEST"
