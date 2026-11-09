#!/usr/bin/env python3
"""Mosaic Arrow: the chosen icon direction, with more depth and many colourways.

A download arrow built from glass tiles with real thickness and highlights. The last pieces
arrive as small 3D cubes tumbling in with motion trails: pieces being downloaded.

Reuses the helpers in icon-concepts.py. Writes Support/Icons/ma-*.icon and
Support/IconVariants/ma-*-light.png / -dark.png without touching other renders.

Run: python3 scripts/icon-mosaic-arrow.py
"""
import glob
import importlib.util
import math
import os

_spec = importlib.util.spec_from_file_location(
    "concepts", os.path.join(os.path.dirname(os.path.abspath(__file__)), "icon-concepts.py"))
C = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(C)
Art, mix, ramp, lin, write_icon = C.Art, C.mix, C.ramp, C.lin, C.write_icon

# name: background (top, bottom), tile colours top to tip, glow colour (None for light backgrounds)
PALETTES = {
    "sunset":      (("#2A1F5C", "#0A0818"), ["#7B5CFF", "#C04BFF", "#FF5CA8", "#FF8A5C", "#FFC24A"], "#FF5CA8"),
    "sunset-day":  (("#FFF4EC", "#FFD6C2"), ["#7B5CFF", "#C04BFF", "#FF5CA8", "#FF8A5C", "#FFC24A"], None),
    "ocean":       (("#0E2A4A", "#040B18"), ["#8A5CFF", "#4F7BFF", "#26B8F0", "#2DE1C2"], "#26B8F0"),
    "sky":         (("#F4FAFF", "#D4E8FF"), ["#4F7BFF", "#26B8F0", "#2DE1C2"], None),
    "aurora":      (("#0F2A2A", "#04100F"), ["#8A5CFF", "#26B8F0", "#2DE1C2", "#9BE36B"], "#2DE1C2"),
    "lava":        (("#2B2326", "#0E0A0B"), ["#FF3B5C", "#FF6A3D", "#FF9F2E", "#FFD24A"], "#FF6A3D"),
    "candy":       (("#FFFFFF", "#F1E8FF"), ["#FF6FB5", "#C38BFF", "#7FB8FF", "#7FE8E0"], None),
    "mint":        (("#F2FFF9", "#CFF3E4"), ["#26B8F0", "#2DE1C2", "#9BD82E"], None),
    "berry":       (("#F7EEFF", "#E2CCFF"), ["#5A35B0", "#A040E0", "#FF4FA0"], None),
    "citrus":      (("#FFF8E6", "#FFE0B0"), ["#FF4F6D", "#FF7A45", "#FFB547", "#FFE15C"], None),
    "gold":        (("#3A3C44", "#121317"), ["#FFF1C4", "#F5C35A", "#E19A2A", "#B8741A"], "#F5B547"),
    "neon":        (("#141018", "#050307"), ["#00E5FF", "#7C5CFF", "#FF2BD6"], "#7C5CFF"),
    "forest":      (("#123A2B", "#05140E"), ["#D9F57A", "#7EDB6A", "#2FBF7A", "#14936B"], "#2FBF7A"),
    "rose":        (("#FFF6F0", "#FBDCD2"), ["#E8577A", "#F07C7C", "#F7A58A", "#FBC9A4"], None),
    "white-glass": (("#8A5CFF", "#FF5CA8"), ["#FFFFFF", "#FFF4FA", "#FFE3F1"], None),
    "midnight":    (("#14204A", "#060A1C"), ["#E4EEFF", "#A9C4FF", "#6E8FFF", "#4B5BFF"], "#6E8FFF"),
}

CX = 512
SIZE, GAP = 58, 9
STEP = SIZE + GAP
TOP = 262
# Half-widths per row: a 3-tile shaft, then a head of 9, 7, 5, 3 and 1 tiles.
HALF = [1] * 5 + [4, 3, 2, 1, 0]
MISSING = [(0, 1), (0, 0)]


def glass_tile(art, x, y, s, colour, depth=9, radius=14):
    """A tile with thickness: a darker base below, a lit top face and a highlight along the top edge."""
    base = mix(colour, "#000000", 0.35)
    g = art.gid("t")
    art.defs += lin(g, [(0, mix(colour, "#FFFFFF", 0.42), 1), (0.55, colour, 1), (1, mix(colour, "#000000", 0.08), 1)])
    art.body += (f'<rect x="{x:.1f}" y="{y + depth:.1f}" width="{s:.1f}" height="{s:.1f}" rx="{radius}" fill="{base}"/>'
                 f'<rect x="{x:.1f}" y="{y:.1f}" width="{s:.1f}" height="{s:.1f}" rx="{radius}" fill="url(#{g})"/>'
                 f'<rect x="{x + 6:.1f}" y="{y + 4:.1f}" width="{s - 12:.1f}" height="{s * 0.28:.1f}" rx="{radius * 0.6:.1f}" '
                 f'fill="#FFFFFF" fill-opacity="0.32"/>')


def cube(art, cx, cy, s, colour, spin):
    """A small isometric cube, turned by `spin` degrees, with lit top and shaded sides."""
    def pt(dx, dy):
        a = math.radians(spin)
        return (cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a))
    h = s / 2
    k = s * 0.5
    top = [pt(0, -h - k * 0.5), pt(h * 1.0, -k * 0.5 - h * 0.45), pt(0, -h * 0.1), pt(-h * 1.0, -k * 0.5 - h * 0.45)]
    left = [pt(-h, -k * 0.5 - h * 0.45), pt(0, -h * 0.1), pt(0, h * 1.05), pt(-h, h * 0.55)]
    right = [pt(h, -k * 0.5 - h * 0.45), pt(0, -h * 0.1), pt(0, h * 1.05), pt(h, h * 0.55)]
    def path(pts):
        return "M" + " L".join(f"{x:.1f} {y:.1f}" for x, y in pts) + "Z"
    g = art.gid("c")
    art.defs += lin(g, [(0, "#FFFFFF", 1), (1, mix(colour, "#FFFFFF", 0.35), 1)])
    art.body += (f'<path d="{path(left)}" fill="{mix(colour, "#000000", 0.12)}" stroke="{mix(colour, "#000000", 0.12)}" stroke-width="4" stroke-linejoin="round"/>'
                 f'<path d="{path(right)}" fill="{mix(colour, "#000000", 0.32)}" stroke="{mix(colour, "#000000", 0.32)}" stroke-width="4" stroke-linejoin="round"/>'
                 f'<path d="{path(top)}" fill="url(#{g})" stroke="{mix(colour, "#FFFFFF", 0.5)}" stroke-width="4" stroke-linejoin="round"/>')


def streak(art, x1, y1, x2, y2, colour, width):
    g = art.gid("s")
    art.defs += lin(g, [(0, colour, 0), (1, colour, 0.5)], x1, y1, x2, y2, user=True)
    dx, dy = x2 - x1, y2 - y1
    l = math.hypot(dx, dy)
    nx, ny = -dy / l, dx / l
    art.body += (f'<path d="M{x1:.1f} {y1:.1f} L{x2 + nx * width / 2:.1f} {y2 + ny * width / 2:.1f} '
                 f'L{x2 - nx * width / 2:.1f} {y2 - ny * width / 2:.1f}Z" fill="url(#{g})"/>')


def mosaic_arrow(name, palette):
    bg, colours, glow_colour = PALETTES[palette]
    glow = Art()
    if glow_colour:
        glow.glow(512, 600, 470, glow_colour, 0.5)
    shaft, head = Art(), Art()
    rows = len(HALF)
    for r in range(rows):
        for c in range(-HALF[r], HALF[r] + 1):
            if (r, c) in MISSING:
                continue
            x = CX - SIZE / 2 + c * STEP
            y = TOP + r * STEP
            glass_tile(shaft if r < 5 else head, x, y, SIZE, ramp(colours, r / (rows - 1)))
    # Cubes tumbling in from the top right, the largest closest to its slot.
    incoming = Art()
    first = ramp(colours, 0.0)
    for (tx, ty, s, spin, k) in [(CX + 30, TOP - 74, 96, 12, 1.0), (CX + 170, TOP - 140, 70, -16, 0.75),
                                 (CX + 262, TOP - 160, 48, 28, 0.55)]:
        streak(incoming, tx + 150, ty - 120, tx, ty, first, s * 1.05)
        cube(incoming, tx, ty, s, mix(first, "#FFFFFF", 0.1 * (1 - k)), spin)
    write_icon(name, bg, [("incoming", incoming, True, 0.15, 0.45), ("shaft", shaft, True, 0.2, 0.45),
                          ("head", head, True, 0.2, 0.5), ("glow", glow, False, 0, 0)])


if __name__ == "__main__":
    for f in glob.glob(os.path.join(C.RENDERS, "ma-*.png")):
        os.remove(f)
    for palette in PALETTES:
        name = f"ma-{palette}"
        mosaic_arrow(name, palette)
        print("rendered", name)
