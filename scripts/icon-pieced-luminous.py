#!/usr/bin/env python3
"""Pieced Arrow, luminous glass: the original flat glass pieces (no extra thickness) with a soft
motion trail behind the falling tile, in every palette used so far.

Reuses helpers from icon-concepts.py and palettes from icon-mosaic-arrow.py.
Writes Support/Icons/pl-*.icon and Support/IconVariants/pl-*-light.png / -dark.png.

Run: python3 scripts/icon-pieced-luminous.py
"""
import glob
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, file):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, file))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


C = load("concepts", "icon-concepts.py")
M = load("mosaic", "icon-mosaic-arrow.py")
Art, shape, mix, ramp, lin, write_icon = C.Art, C.shape, C.mix, C.ramp, C.lin, C.write_icon

CX = 512

# Every palette so far: (background top, bottom), colours from the falling tile to the arrow tip, glow.
PALETTES = dict(M.PALETTES)
PALETTES.update({
    # Mosaic materials: the falling tile carries the accent colour.
    "lapis":        (("#3D63E0", "#1A2C7A"), ["#F2B544", "#7C98F2", "#4A6FE6", "#2F55D4"], "#7C98F2"),
    "terracotta":   (("#FFF8EF", "#EEDFCA"), ["#2A9D8F", "#F2A47C", "#E07B4F", "#C95F35"], None),
    "zellige":      (("#13684F", "#06342A"), ["#F6F0E2", "#8FE0BF", "#47BC92", "#22936C"], "#47BC92"),
    "obsidian":     (("#2E2E33", "#0B0B0D"), ["#E8B84A", "#8A8A93", "#5B5B63", "#3E3E45"], "#E8B84A"),
    "coral-plum":   (("#FFF3EE", "#F8D8CC"), ["#3B2A6B", "#FFA593", "#FF7D66", "#E85B4A"], None),
    "turquoise":    (("#18405F", "#0A1B2E"), ["#F2B544", "#8AE8E4", "#43CBCB", "#1FA3B0"], "#43CBCB"),
    "amethyst":     (("#F6F1FF", "#E2D6FA"), ["#3FC496", "#C7ABF6", "#A07CEB", "#7E56D8"], None),
    "marble":       (("#F8F8F6", "#E2E2DD"), ["#17181C", "#C9C9C2", "#B4B4AC", "#9C9C94"], None),
    # Bold backgrounds from the tile scenes: white pieces, one accent.
    "emerald":      (("#2FD49A", "#0B7F5C"), ["#F2B544", "#FFFFFF", "#EAF8F1", "#CFEFDF"], None),
    "graphite":     (("#4A4D57", "#16171B"), ["#F2B544", "#F4F1EA", "#E7E2D8", "#D3CCBE"], "#F2B544"),
    "terracotta-bold": (("#FF9A62", "#D9532B"), ["#2A9D8F", "#FFF8F0", "#FBE7D6", "#F6D2B8"], None),
    "coral-bold":   (("#FF8A7A", "#E0435A"), ["#3B2A6B", "#FFFFFF", "#FFE9E4", "#FFD3CA"], None),
    # Glass Stack, night.
    # Final app icon: Ocean refined. Deep blue to aqua (no violet), with a softer glow.
    "ocean-final":  (("#0E2A4A", "#040B18"), ["#3C6BFF", "#2F8CF0", "#26B8F0", "#2DE1C2"], "#1E8FD6"),
    "stack-night":  (("#23233A", "#0B0B14"), ["#26B8F0", "#8A5CFF", "#C15CE0", "#FF5CA8"], "#8A5CFF"),
})


# Palettes whose falling tile is a separate accent colour rather than the start of the gradient.
ACCENTED = {"lapis", "terracotta", "zellige", "obsidian", "coral-plum", "turquoise", "amethyst", "marble",
            "emerald", "graphite", "terracotta-bold", "coral-bold"}


def pieced_luminous(name, palette):
    bg, colours, glow_colour = PALETTES[palette]
    back = Art()
    if glow_colour:
        back.glow(512, 620, 460, glow_colour, 0.25 if palette == "ocean-final" else 0.5)
    w, gap = 236, 24
    lead = ramp(colours, 0.0)
    # Soft motion behind the falling tile: a fading trail and two speed lines, all in the tile's colour.
    g = back.gid("drop")
    back.defs += lin(g, [(0, lead, 0), (1, lead, 0.45)], 0, 40, 0, 230, user=True)
    back.body += f'<path d="M{CX - 96} 40 L{CX + 96} 40 L{CX + w / 2 - 6} 230 L{CX - w / 2 + 6} 230Z" fill="url(#{g})"/>'
    for x, y0, y1 in [(CX - w / 2 - 34, 120, 210), (CX + w / 2 + 34, 96, 176)]:
        sid = back.gid("sp")
        back.defs += lin(sid, [(0, lead, 0), (1, lead, 0.7)], 0, y0, 0, y1, user=True)
        back.body += f'<path d="M{x} {y0} L{x} {y1}" stroke="url(#{sid})" stroke-width="10" stroke-linecap="round"/>'
    head, mid, top = Art(), Art(), Art()
    body_h = colours[1:] if palette in ACCENTED else colours
    shape(head, [(CX - 250, 600), (CX + 250, 600), (CX, 880)], ramp(body_h, 0.7 if body_h is colours else 0.5),
          ramp(body_h, 1.0), radius=50)
    body = colours[1:] if palette in ACCENTED else colours
    shape(mid, [(CX - w / 2, 400), (CX + w / 2, 400), (CX + w / 2, 600 - gap), (CX - w / 2, 600 - gap)],
          ramp(body, 0.4 if body is colours else 0.0), ramp(body, 0.6 if body is colours else 0.4), radius=36)
    top_end = mix(lead, "#000000", 0.12) if palette in ACCENTED else ramp(colours, 0.3)
    shape(top, [(CX - w / 2, 150), (CX + w / 2, 150), (CX + w / 2, 400 - gap - 30), (CX - w / 2, 400 - gap - 30)],
          mix(lead, "#FFFFFF", 0.2), top_end, radius=36, rotate=-9, pivot=(CX, 250))
    write_icon(name, bg, [("top", top, True, 0.3, 0.45), ("mid", mid, True, 0.3, 0.45), ("head", head, True, 0.3, 0.5),
                          ("back", back, False, 0, 0)])


if __name__ == "__main__":
    for f in glob.glob(os.path.join(C.RENDERS, "pl-*.png")):
        os.remove(f)
    for palette in PALETTES:
        name = f"pl-{palette}"
        pieced_luminous(name, palette)
        print("rendered", name)
