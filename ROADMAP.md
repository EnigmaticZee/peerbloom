# Peerbloom roadmap

## Version 1 (built)

### Sidebar
- [x] Status filters with live counts: All, Downloading, Seeding, Completed, Paused & Queued
- [x] Colour tags, each with an optional default save folder (Settings › Tags)
- [x] VPN status card: Protected / VPN disconnected / Not bound

### Toolbar
- [x] Add a .torrent file or magnet link (button, ⌘O, ⌘U, drag and drop, or opening magnet links and .torrent files from other apps)
- [x] Pause, resume, remove (keep files or delete them)
- [x] Search transfers by name
- [x] Total download and upload speed under the title

### Transfer list
- [x] Columns: name, size, progress, status, down, up, time left, ratio, queue position
- [x] Sort by any column
- [x] Queue reordering (right-click › Queue)
- [x] Select several rows (⌘-click, Shift-click)
- [x] Right-click menu: Show in Finder, Copy Magnet Link, Queue, Tag, Stream, Move Files, Verify, Ask Trackers for More Peers, Remove
- [x] Comfortable and compact row sizes (Settings › General)

### Detail panel
- [x] Piece map
- [x] Overview: live speed chart (last 5 minutes), peers, ratio, time left, availability, save location, info hash
- [x] Files: skip files and set priority (Low / Normal / High)
- [x] Peers: address, client, speeds, encryption
- [x] Trackers: status, seeds, messages, plus DHT

### Status bar
- [x] DHT nodes, listening port (and whether the router mapped it), free disk space, session ratio

### Other screens
- [x] Add sheet: choose files, save folder, tag, "Stream while downloading", "Start immediately"
- [x] Menu bar popover: speeds, active transfers, VPN status, slow mode, Pause All / Resume All
- [x] Settings › Network & Privacy: bind to a VPN connection, kill switch, encryption mode, anonymous mode, IP blocklist (updated daily), listening port, UPnP / NAT-PMP, DHT, local peer discovery

### Mac features
- [x] Notification when a download finishes
- [x] Speed limits, a "slow mode" with its own limits, and a weekly schedule for it
- [x] Light and dark mode, following the system setting
- [x] Keep the Mac awake while downloading
- [x] Pause downloads when free disk space is low
- [x] Progress is saved on quit and every 5 minutes, and restored on launch

### Privacy
- [x] Privacy mode: one switch for VPN or SOCKS5 proxy only, encryption required, anonymous mode, no local broadcasts or router port opening
- [x] Proxy support (SOCKS5 or HTTP, with login; the password is kept in the Keychain)
- [x] "Peers see you as": the public address peers and trackers report, learned without contacting any outside service
- [x] VPN detection, "Any active VPN" binding that follows reconnects, and an Open button for the installed VPN app

### Themes
- [x] Settings › Appearance with six built-in themes: Peerbloom, Ocean, Forest, Paper, Terminal, High Contrast
- [x] Import `.peerbloomtheme` files (double-click or Import Theme…); themes are data only and checked for readable contrast
- [x] Theme Maker: a prompt to paste into any AI assistant, which interviews you and writes a theme file

### Safety
- [x] Downloaded files are quarantined, so Gatekeeper checks apps and installers before they open
- [x] Warning for torrents that contain apps, installers, scripts or disguised files, with one click to skip them
- [x] Licence notices for libtorrent and OpenSSL in the About window

## Backlog

### Mac integration
- [ ] Shortcuts actions (add magnet, pause all, slow mode)
- [ ] AppleScript dictionary
- [ ] Quick Look previews of downloaded files
- [ ] Web remote to control Peerbloom from a phone
- [ ] Dock icon badge with active transfer count
- [ ] Spotlight indexing of the transfer list

### Automation
- [ ] RSS rules (auto-add new items from feeds)
- [ ] Watched folders (auto-add .torrent files dropped into a folder)

### Performance
- [ ] Benchmark against Transmission (memory, CPU, speed). Peerbloom so far: about 90 MB of memory and about 1% CPU while idle
- [ ] Lower idle CPU: the window refreshes every second even when nothing is transferring

### Insights
- [ ] Network & Stats view (design variant E): daily totals, top uploads, peers by client, storage bar
- [ ] Transfer history

### Release
- [x] App icon
- [x] libtorrent and OpenSSL bundled inside the app, so it runs on Macs without Homebrew
- [x] Drag-to-install DMG (`scripts/make-dmg.sh`)
- [ ] Sparkle auto-updates, Homebrew Cask
- [ ] Intel Mac build (currently Apple silicon only)
- [x] Product name (Peerbloom) and trademark check
- [x] License: GNU GPL v3

### Engine
- [ ] Create new torrents from local files
- [ ] Per-transfer speed limits and seeding goals (stop at ratio X)
- [ ] Move off deprecated libtorrent 2.1 calls (`torrent_info::files()`, `make_magnet_uri(handle)` and a few more; they still work)

### Deliberately left out
- Built-in torrent search (legal risk)
- Ads, accounts and tracking
- Apple Developer ID signing and notarization: the app is ad-hoc signed, so macOS asks to confirm the first launch (see README)
