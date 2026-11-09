#!/usr/bin/env python3
"""Peerbloom app icon concepts: luminous glass that reads as a torrent client.

Beauty first: vivid gradients, coloured glass that overlaps and refracts, light and glow.
The idea underneath: pieces forming a whole.

Shapes are drawn as SVG; Apple's Icon Composer (ictool) renders the Liquid Glass material,
lighting, shadows and the dark version.

Run: python3 scripts/icon-concepts.py
Writes Support/Icons/<name>.icon and Support/IconVariants/<name>-light.png / -dark.png
"""
import json
import math
import os
import shutil
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICONS = os.path.join(ROOT, "Support", "Icons")
RENDERS = os.path.join(ROOT, "Support", "IconVariants")
ICTOOL = "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"


def srgb(hex_color, a=1.0):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return f"srgb:{r:.5f},{g:.5f},{b:.5f},{a:.5f}"


def mix(a, b, t):
    a, b = a.lstrip("#"), b.lstrip("#")
    ca = [int(a[i:i + 2], 16) for i in (0, 2, 4)]
    cb = [int(b[i:i + 2], 16) for i in (0, 2, 4)]
    return "#" + "".join(f"{round(x + (y - x) * t):02X}" for x, y in zip(ca, cb))


def ramp(colours, t):
    """Colour at position t (0...1) along a list of hex colours."""
    t = max(0.0, min(1.0, t))
    seg = t * (len(colours) - 1)
    i = min(int(seg), len(colours) - 2)
    return mix(colours[i], colours[i + 1], seg - i)


def lin(gid, stops, x1=0, y1=0, x2=0, y2=1, user=False):
    units = ' gradientUnits="userSpaceOnUse"' if user else ""
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<linearGradient id="{gid}" x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"{units}>{s}</linearGradient>'


def rad(gid, stops, cx=0.5, cy=0.5, r=0.5):
    s = "".join(f'<stop offset="{o}" stop-color="{c}" stop-opacity="{a}"/>' for o, c, a in stops)
    return f'<radialGradient id="{gid}" cx="{cx}" cy="{cy}" r="{r}">{s}</radialGradient>'


class Art:
    def __init__(self):
        self.defs, self.body, self.n = "", "", 0

    def gid(self, p):
        self.n += 1
        return f"{p}{self.n}"

    def svg(self):
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
                f"<defs>{self.defs}</defs>{self.body}</svg>")

    def rect(self, x, y, w, h, r, top, bottom, rotate=0.0, opacity=1.0):
        g = self.gid("r")
        self.defs += lin(g, [(0, top, 1), (1, bottom, 1)], 0, 0, 1, 1)
        cx, cy = x + w / 2, y + h / 2
        self.body += (f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{r:.1f}" fill="url(#{g})" '
                      f'fill-opacity="{opacity}" transform="rotate({rotate:.1f} {cx:.1f} {cy:.1f})"/>')

    def glow(self, cx, cy, r, colour, strength=0.6):
        g = self.gid("g")
        self.defs += rad(g, [(0, colour, strength), (0.45, colour, strength * 0.35), (1, colour, 0)])
        self.body += f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="{r:.1f}" fill="url(#{g})"/>'


def write_icon(name, bg, groups):
    """groups front to back: (layer_name, Art, glass, translucency, shadow)."""
    path = os.path.join(ICONS, name + ".icon")
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(os.path.join(path, "Assets"))
    out = []
    for layer_name, art, glass, translucency, shadow in groups:
        with open(os.path.join(path, "Assets", layer_name + ".svg"), "w") as f:
            f.write(art.svg())
        out.append({"layers": [{"image-name": layer_name + ".svg", "name": layer_name, "glass": glass}],
                    "shadow": {"kind": "neutral", "opacity": shadow},
                    "translucency": {"enabled": translucency > 0, "value": translucency}})
    doc = {"fill": {"linear-gradient": [srgb(bg[0]), srgb(bg[1])]}, "groups": out,
           "supported-platforms": {"squares": "shared"}}
    with open(os.path.join(path, "icon.json"), "w") as f:
        json.dump(doc, f, indent=2)
    for rendition, suffix in (("Default", "light"), ("Dark", "dark")):
        subprocess.run([ICTOOL, path, "--export-image", "--output-file", os.path.join(RENDERS, f"{name}-{suffix}.png"),
                        "--platform", "macOS", "--rendition", rendition, "--width", "512", "--height", "512",
                        "--scale", "2"], check=True, capture_output=True)


# MARK: - Shape helpers

def rounded(points, radius):
    """SVG path for a polygon with rounded corners."""
    n = len(points)
    d = []
    for i in range(n):
        p0, p1, p2 = points[i - 1], points[i], points[(i + 1) % n]
        v1 = (p0[0] - p1[0], p0[1] - p1[1])
        v2 = (p2[0] - p1[0], p2[1] - p1[1])
        l1, l2 = math.hypot(*v1), math.hypot(*v2)
        rr = min(radius, l1 / 2.2, l2 / 2.2)
        a = (p1[0] + v1[0] / l1 * rr, p1[1] + v1[1] / l1 * rr)
        b = (p1[0] + v2[0] / l2 * rr, p1[1] + v2[1] / l2 * rr)
        d.append(("M" if i == 0 else "L") + f"{a[0]:.1f} {a[1]:.1f}")
        d.append(f"Q{p1[0]:.1f} {p1[1]:.1f} {b[0]:.1f} {b[1]:.1f}")
    return "".join(d) + "Z"


def shape(art, points, top, bottom, radius=30, opacity=1.0, rotate=0.0, pivot=(512, 512)):
    g = art.gid("s")
    art.defs += lin(g, [(0, top, 1), (1, bottom, 1)], 0, 0, 0, 1)
    art.body += (f'<path d="{rounded(points, radius)}" fill="url(#{g})" fill-opacity="{opacity}" '
                 f'transform="rotate({rotate:.1f} {pivot[0]:.1f} {pivot[1]:.1f})"/>')


def arrow_points(cx, top, tip, shaft, head_w, head_h, up=False):
    """Block arrow pointing down (or up when up=True)."""
    s, hw = shaft / 2, head_w / 2
    if not up:
        neck = tip - head_h
        return [(cx - s, top), (cx + s, top), (cx + s, neck), (cx + hw, neck), (cx, tip), (cx - hw, neck), (cx - s, neck)]
    neck = tip + head_h
    return [(cx - s, top), (cx - s, neck), (cx - hw, neck), (cx, tip), (cx + hw, neck), (cx + s, neck), (cx + s, top)]


# MARK: - 1. Pieced arrow: a download arrow assembled from glass pieces, the last one arriving

def pieced_arrow(name, bg, colours, glow):
    back = Art()
    back.glow(512, 620, 460, glow, 0.5)
    cx, shaft, gap = 512, 236, 24
    head = Art()
    shape(head, [(cx - 250, 600), (cx + 250, 600), (cx, 880)], ramp(colours, 0.7), ramp(colours, 1.0), radius=50)
    mid = Art()
    shape(mid, [(cx - shaft / 2, 400), (cx + shaft / 2, 400), (cx + shaft / 2, 600 - gap), (cx - shaft / 2, 600 - gap)],
          ramp(colours, 0.4), ramp(colours, 0.6), radius=36)
    top = Art()
    # The arriving piece: lifted and slightly turned.
    shape(top, [(cx - shaft / 2, 150), (cx + shaft / 2, 150), (cx + shaft / 2, 400 - gap - 30), (cx - shaft / 2, 400 - gap - 30)],
          mix(ramp(colours, 0.0), "#FFFFFF", 0.2), ramp(colours, 0.3), radius=36, rotate=-9, pivot=(cx, 250))
    write_icon(name, bg, [("top", top, True, 0.3, 0.45), ("mid", mid, True, 0.3, 0.45), ("head", head, True, 0.3, 0.5),
                          ("glow", back, False, 0, 0)])


# MARK: - 2. Stack + arrow: the fanned glass stack with a download arrow on the front tile

def stack_arrow(name, bg, colours, arrow_colour="#FFFFFF"):
    layers = []
    offsets = [(-110, 110, -14), (0, 0, 0), (110, -110, 12)]
    for i, ((dx, dy, rot), col) in enumerate(zip(offsets, colours)):
        art = Art()
        art.rect(512 - 230 + dx, 512 - 230 + dy, 460, 460, 104, mix(col, "#FFFFFF", 0.3), col, rotate=rot)
        layers.append((f"tile{i}", art, True, 0.45, 0.45))
    a = Art()
    cx, cy = 512 + 110, 512 - 110
    shape(a, arrow_points(cx, cy - 150, cy + 160, 86, 250, 130), arrow_colour, mix(arrow_colour, "#DDE3FF", 0.4),
          radius=24, rotate=12, pivot=(cx, cy))
    write_icon(name, bg, [("arrow", a, True, 0.1, 0.4)] + list(reversed(layers)))


# MARK: - 3. Peers to you: glowing peers beaming into one download arrow

def peers(name, bg, colours, glow):
    back = Art()
    back.glow(512, 700, 420, glow, 0.5)
    beams = Art()
    nodes = [(250, 250, colours[0]), (512, 190, colours[1]), (774, 250, colours[2])]
    target = (512, 640)
    for x, y, col in nodes:
        g = beams.gid("b")
        beams.defs += lin(g, [(0, col, 0.85), (1, col, 0.05)], x, y, target[0], target[1], user=True)
        dx, dy = target[0] - x, target[1] - y
        l = math.hypot(dx, dy)
        nx, ny = -dy / l, dx / l
        beams.body += (f'<path d="M{x + nx * 40:.1f} {y + ny * 40:.1f} L{target[0] + nx * 8:.1f} {target[1] + ny * 8:.1f} '
                       f'L{target[0] - nx * 8:.1f} {target[1] - ny * 8:.1f} L{x - nx * 40:.1f} {y - ny * 40:.1f}Z" fill="url(#{g})"/>')
        back.glow(x, y, 150, col, 0.55)
    orbs = Art()
    for x, y, col in nodes:
        g = orbs.gid("o")
        orbs.defs += rad(g, [(0, "#FFFFFF", 1), (0.35, mix(col, "#FFFFFF", 0.4), 1), (1, col, 1)], 0.4, 0.35, 0.7)
        orbs.body += f'<circle cx="{x}" cy="{y}" r="74" fill="url(#{g})"/>'
    arrow = Art()
    shape(arrow, arrow_points(512, 470, 880, 170, 420, 210), "#FFFFFF", mix(colours[1], "#FFFFFF", 0.45), radius=36)
    write_icon(name, bg, [("arrow", arrow, True, 0.15, 0.5), ("peers", orbs, True, 0.2, 0.4),
                          ("beams", beams, False, 0, 0), ("glow", back, False, 0, 0)])


# MARK: - 4. Magnet: a glass magnet pulling glowing pieces in (magnet links)

def magnet(name, bg, colours, glow):
    back = Art()
    back.glow(512, 760, 360, glow, 0.55)
    u = Art()
    g = u.gid("m")
    u.defs += lin(g, [(i / (len(colours) - 1), c, 1) for i, c in enumerate(colours)], 0, 0, 1, 0)
    u.body += (f'<path d="M322 590 L322 440 A190 190 0 0 1 702 440 L702 590" stroke="url(#{g})" stroke-width="170" '
               f'fill="none"/>')
    tips = Art()
    tips.rect(237, 560, 170, 130, 30, "#FFFFFF", "#E4E6F0")
    tips.rect(617, 560, 170, 130, 30, "#FFFFFF", "#E4E6F0")
    pieces = Art()
    for x, y, s, rot, col in [(512, 790, 96, 12, colours[-1]), (390, 870, 64, -16, colours[0]), (640, 880, 58, 20, colours[1])]:
        back.glow(x, y, s * 1.6, col, 0.6)
        pieces.rect(x - s / 2, y - s / 2, s, s, s * 0.24, mix(col, "#FFFFFF", 0.35), col, rotate=rot)
    write_icon(name, bg, [("pieces", pieces, True, 0.2, 0.4), ("tips", tips, True, 0.15, 0.4), ("magnet", u, True, 0.25, 0.5),
                          ("glow", back, False, 0, 0)])


# MARK: - 5. Down and up: overlapping glass arrows for downloading and seeding

def twin(name, bg, down, up):
    d = Art()
    shape(d, arrow_points(400, 170, 810, 170, 400, 220), mix(down[0], "#FFFFFF", 0.15), down[1], radius=40)
    u = Art()
    shape(u, arrow_points(624, 860, 220, 170, 400, 220, up=True), mix(up[0], "#FFFFFF", 0.15), up[1], radius=40)
    write_icon(name, bg, [("up", u, True, 0.45, 0.45), ("down", d, True, 0.45, 0.45)])


SUNSET = ["#7B5CFF", "#C04BFF", "#FF5CA8", "#FF8A5C", "#FFC24A"]
NIGHT_BG = ("#2A1F5C", "#0A0818")
PEACH_BG = ("#FFF4EC", "#FFD6C2")
MINT_BG = ("#F2FFF9", "#CFF3E4")

CONCEPTS = [
    ("stack-arrow-peach", lambda n: stack_arrow(n, PEACH_BG, ["#7B5CFF", "#FF5CA8", "#FFB547"])),
    ("stack-arrow-night", lambda n: stack_arrow(n, ("#23233A", "#0B0B14"), ["#26B8F0", "#8A5CFF", "#FF5CA8"])),
    ("pieced-arrow-night", lambda n: pieced_arrow(n, NIGHT_BG, SUNSET, "#FF5CA8")),
    ("pieced-arrow-peach", lambda n: pieced_arrow(n, PEACH_BG, SUNSET, "#FFB547")),
    ("peers-night", lambda n: peers(n, NIGHT_BG, ["#26B8F0", "#FF5CA8", "#FFC24A"], "#8A5CFF")),
    ("magnet-night", lambda n: magnet(n, NIGHT_BG, SUNSET, "#FF8A5C")),
    ("twin-mint", lambda n: twin(n, MINT_BG, ("#26B8F0", "#4F5BFF"), ("#2DE1C2", "#9BD82E"))),
    ("twin-night", lambda n: twin(n, NIGHT_BG, ("#8A5CFF", "#4F5BFF"), ("#FF8A5C", "#FF4F8B"))),
]

if __name__ == "__main__":
    shutil.rmtree(RENDERS, ignore_errors=True)
    shutil.rmtree(ICONS, ignore_errors=True)
    os.makedirs(RENDERS)
    os.makedirs(ICONS)
    for i, (name, make) in enumerate(CONCEPTS, start=1):
        label = f"{i:02d}-{name}"
        make(label)
        print("rendered", label)
