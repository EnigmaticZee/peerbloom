#!/bin/bash
# Builds Peerbloom in release mode and wraps it in Peerbloom.app so macOS treats it as a real app
# (Dock icon, notifications, magnet link and .torrent file handling).
# Homebrew libraries (libtorrent, OpenSSL) are copied into the app so it runs on Macs without Homebrew.
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="/opt/homebrew/bin:$PATH"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Peerbloom"

APP="build/Peerbloom.app"
FRAMEWORKS="$APP/Contents/Frameworks"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$FRAMEWORKS"
cp "$BIN" "$APP/Contents/MacOS/Peerbloom"
cp Support/Info.plist "$APP/Contents/Info.plist"
# App icon: compile the Icon Composer document. This produces Assets.car (Liquid Glass, with
# dark and tinted versions on macOS 26+) and AppIcon.icns for older macOS versions.
xcrun actool Support/AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist build/icon-partial.plist >/dev/null
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$APP/Contents/Info.plist"
rm -f build/icon-partial.plist

# The prompt behind Settings › Appearance › Copy Theme Maker.
cp Themes/ThemeMaker.md "$APP/Contents/Resources/ThemeMaker.md"

# Licence notices for the libraries bundled below. The About window shows Credits.html.
LIBTORRENT_LICENSE="$(brew --prefix libtorrent-rasterbar)/LICENSE"
OPENSSL_LICENSE="$(brew --prefix openssl)/LICENSE.txt"
escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' "$1"; }
{
    echo '<html><body style="font: 11px -apple-system, sans-serif; text-align: center">'
    echo '<p>Free and open source. No ads, no accounts, no tracking.</p>'
    echo '<p>Peerbloom is free software under the <a href="https://www.gnu.org/licenses/gpl-3.0.html">GNU General Public License v3</a>.</p>'
    echo '<p>Built on <a href="https://libtorrent.org">libtorrent</a> and <a href="https://www.openssl.org">OpenSSL</a>. Their licences follow.</p>'
    echo '<pre style="font: 10px ui-monospace, monospace; text-align: left; white-space: pre-wrap">'
    echo "libtorrent"; echo; escape "$LIBTORRENT_LICENSE"
    echo; echo "------------------------------------------------------------------------------"; echo
    echo "OpenSSL"; echo; escape "$OPENSSL_LICENSE"
    echo '</pre></body></html>'
} > "$APP/Contents/Resources/Credits.html"

# Lists the Homebrew libraries a binary links against.
homebrew_deps() {
    otool -L "$1" | tail -n +2 | awk '{print $1}' | grep '^/opt/homebrew/' || true
}

# Copies every Homebrew library the app needs into Contents/Frameworks (recursively)
# and points all references at @rpath so nothing loads from /opt/homebrew.
embed() {
    local file="$1"
    local dep name
    for dep in $(homebrew_deps "$file"); do
        name="$(basename "$dep")"
        if [ ! -f "$FRAMEWORKS/$name" ]; then
            cp "$(realpath "$dep")" "$FRAMEWORKS/$name"
            chmod u+w "$FRAMEWORKS/$name"
            install_name_tool -id "@rpath/$name" "$FRAMEWORKS/$name" 2>/dev/null
            embed "$FRAMEWORKS/$name"
        fi
        install_name_tool -change "$dep" "@rpath/$name" "$file" 2>/dev/null
    done
}

embed "$APP/Contents/MacOS/Peerbloom"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Peerbloom" 2>/dev/null || true

if otool -L "$APP/Contents/MacOS/Peerbloom" "$FRAMEWORKS"/*.dylib | grep -q '/opt/homebrew/'; then
    echo "error: the app still references /opt/homebrew" >&2
    exit 1
fi

# Ad-hoc signature so it runs on this Mac. Sharing it widely needs a Developer ID and notarization.
codesign --force --sign - "$FRAMEWORKS"/*.dylib
codesign --force --sign - "$APP"

# Tell Launch Services about the magnet: and .torrent handlers.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" || true

echo "Built $APP"
