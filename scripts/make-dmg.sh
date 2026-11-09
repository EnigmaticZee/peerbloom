#!/bin/bash
# Builds Peerbloom.app, then packs it into a drag-to-install DMG in the project folder: Peerbloom-<version>.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# The DMG background is generated from code.
if [ ! -f Support/dmg-background.tiff ]; then
    swift scripts/make-art.swift Support
    tiffutil -cathidpicheck Support/dmg-background.png Support/dmg-background@2x.png -out Support/dmg-background.tiff
    rm -f Support/dmg-background.png Support/dmg-background@2x.png
fi

./scripts/bundle.sh

# dmgbuild writes the Finder window layout directly, without scripting Finder.
VENV="build/.dmg-venv"
if [ ! -x "$VENV/bin/dmgbuild" ]; then
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet "dmgbuild>=1.6"
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)"
OUT="Peerbloom-$VERSION.dmg"
rm -f "$OUT"
"$VENV/bin/dmgbuild" -s scripts/dmg-settings.py -D app=build/Peerbloom.app -D support=Support "Peerbloom" "$OUT"
codesign --force --sign - "$OUT"

echo "Built $OUT"
