# dmgbuild settings for the Peerbloom installer window.
# Used by scripts/make-dmg.sh: dmgbuild -s scripts/dmg-settings.py -D app=... "Peerbloom" out.dmg
import os

app = defines.get("app", "build/Peerbloom.app")  # noqa: F821 (provided by dmgbuild)
support = defines.get("support", "Support")  # noqa: F821
app_name = os.path.basename(app)

volume_name = "Peerbloom"
format = "ULFO"            # LZFSE compressed, macOS 10.11+
filesystem = "APFS"
size = None

files = [app]
symlinks = {"Applications": "/Applications"}

icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")
badge_icon = None

# Window: 660 × 420 points, matching the background artwork.
background = os.path.join(support, "dmg-background.tiff")
window_rect = ((200, 120), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
sidebar_width = 0

icon_size = 112
text_size = 13
arrange_by = None
grid_spacing = 100
label_pos = "bottom"
show_icon_preview = False

icon_locations = {
    app_name: (180, 205),
    "Applications": (480, 205),
}

hide_extension = [app_name]
