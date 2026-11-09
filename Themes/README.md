# Peerbloom themes

A theme is a small JSON file with the `.peerbloomtheme` extension. It holds colours, light or dark, and a
font style. Themes are only data: they can't run code, load anything from the internet, or change any
other setting, so trying a theme from anywhere is safe.

## Making one

- **With an AI assistant:** in Peerbloom, open Settings › Appearance › **Copy Theme Maker**, paste it into
  any AI assistant, and answer its questions. The same text is in [ThemeMaker.md](ThemeMaker.md).
- **By hand:** copy [Examples/night-swim.peerbloomtheme](Examples/night-swim.peerbloomtheme) and edit it.

To use a theme, double-click the file, or open Settings › Appearance › **Import Theme…**.
Imported themes are kept in `~/Library/Application Support/Peerbloom/Themes`.

## Format

| Field | Required | Values |
|---|---|---|
| `format` | yes | `1` |
| `name` | yes | 1 to 40 characters |
| `author` | no | Shown as "by …" |
| `appearance` | yes | `"system"`, `"light"` or `"dark"` |
| `font` | no | `"standard"` (default), `"rounded"`, `"serif"` or `"monospaced"` |
| `colors.accent` | yes | Buttons, switches and links |
| `colors.download` | yes | Downloading transfers and download speeds |
| `colors.seeding` | yes | Seeding transfers and upload speeds |
| `colors.protected` | yes | The "Protected" VPN status |
| `colors.warning` | yes | Warnings |
| `colors.background` | no | Window background; leave out for the standard Mac colour |
| `colors.sidebar` | no | Sidebar background |

Each colour is `"#RRGGBB"`, or `{"light": "#RRGGBB", "dark": "#RRGGBB"}` for a different value in light and
dark mode.

## Checks

Peerbloom rejects a theme that:

- is larger than 64 KB, isn't valid JSON, or uses a format other than `1`
- has a missing or too-long name
- has a colour that isn't `#RRGGBB`
- has a `download`, `seeding`, `protected` or `warning` colour with a contrast ratio below 3 against the
  background, in any mode the theme can show (without a `background`, white is used for light mode
  and #1E1E1E for dark mode)

## Sharing

Add your theme to this folder in a pull request, and include a screenshot.
