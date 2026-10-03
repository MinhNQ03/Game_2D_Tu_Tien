#!/usr/bin/env python3
"""Generate Aetheria UI pixel-art PNG assets (project-owned, self-made, CC0-equivalent).

BUILD-TIME TOOL ONLY. The game runtime never imports or depends on it; it exists so the
committed UI textures are reproducible and provably self-made — no external/licensed asset
enters the project (`.kiro/steering/06-art-assets.md`, provenance rule). This mirrors
`tools/gen_prototype_assets.py` (D-022): a pure-stdlib (zlib + struct) RGBA8 PNG writer, no
third-party image library, no download.

Context (Phase 04 UI hardening): the preferred external pack
(tiopalada "Tiny RPG - Mana Soul GUI", CC0, https://tiopalada.itch.io/tiny-rpg-mana-soul-gui)
could NOT be auto-downloaded in the build environment (itch.io returns HTTP 403 to automated
fetch; the download sits behind a JS button with no stable binary URL). Rather than fake a
download, screenshot it, or pull from an unverified mirror (all forbidden), we generate our
own prototype UI set here. These are PROTOTYPE assets — a real art pass (the itch.io pack or
original art) replaces them later and is recorded in `docs/ASSET_LICENSES.md`.

Design: an ink-and-jade xianxia palette (`src/presentation/ui/ui_palette.gd`). Every frame is
a 9-SLICE panel — a small texture with a documented, non-stretched border margin so corners
stay crisp when a NinePatchRect/StyleBoxTexture stretches the center. The 9-slice MARGIN for
each frame is noted next to its generator and consumed by `UITheme` as the patch margin.

Outputs (nearest filter, mipmaps off — set globally in project.godot + per-node):
  assets/ui/mana_soul/panels/panel.png            24x24  margin 8  (window/HUD panel)
  assets/ui/mana_soul/panels/panel_inset.png      24x24  margin 8  (darker inset/well)
  assets/ui/mana_soul/buttons/button_normal.png   24x24  margin 8
  assets/ui/mana_soul/buttons/button_hover.png    24x24  margin 8
  assets/ui/mana_soul/buttons/button_pressed.png  24x24  margin 8
  assets/ui/mana_soul/buttons/button_disabled.png 24x24  margin 8
  assets/ui/mana_soul/buttons/button_focus.png    24x24  margin 8  (accent outline only)
  assets/ui/mana_soul/frames/key_badge.png        16x16  margin 6  (keycap chip)
  assets/ui/mana_soul/frames/portrait_frame.png   24x24  margin 8  (identity portrait slot)
  assets/ui/mana_soul/frames/title_divider.png    48x8          (ornamental horizontal rule)

Run:  python tools/gen_ui_assets.py
"""
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
UI_DIR = os.path.join(ROOT, "assets/ui/mana_soul")

# --- Palette (RGBA), mirrors src/presentation/ui/ui_palette.gd (ink-and-jade) ---------
INK_0 = (18, 20, 26, 255)        # deepest outline / shadow
INK_1 = (28, 32, 40, 255)        # panel outer edge
SURFACE = (33, 38, 46, 255)      # panel fill
SURFACE_HI = (46, 54, 64, 255)   # top bevel highlight
SURFACE_LO = (24, 28, 35, 255)   # bottom bevel shade
INSET = (22, 26, 32, 255)        # inset/well fill
BTN = (40, 54, 58, 255)          # button normal fill (slight jade tint)
BTN_HI = (58, 76, 80, 255)
BTN_LO = (28, 40, 44, 255)
BTN_HOVER = (52, 72, 72, 255)
BTN_HOVER_HI = (74, 100, 96, 255)
BTN_PRESSED = (30, 42, 44, 255)
BTN_DISABLED = (30, 33, 38, 255)
JADE = (92, 199, 158, 255)       # accent (COLOR_ACCENT ~ .36,.78,.62)
JADE_DK = (54, 120, 96, 255)
GOLD = (198, 168, 92, 255)       # muted gold ornament
BADGE = (44, 51, 60, 255)
TRANSPARENT = (0, 0, 0, 0)


def _png(path, width, height, pixels):
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter 0 (none)
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))
    print("wrote %s (%dx%d)" % (os.path.relpath(path, ROOT), width, height))


def _blank(w, h, color=TRANSPARENT):
    return [[color for _ in range(w)] for _ in range(h)]


def _px(grid, x, y, color):
    if 0 <= y < len(grid) and 0 <= x < len(grid[0]):
        grid[y][x] = color


def _rect(grid, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            _px(grid, x, y, color)


def _border(grid, x0, y0, x1, y1, color):
    for x in range(x0, x1):
        _px(grid, x, y0, color)
        _px(grid, x, y1 - 1, color)
    for y in range(y0, y1):
        _px(grid, x0, y, color)
        _px(grid, x1 - 1, y, color)


def _bevel_panel(w, h, fill, hi, lo, outer, outline, accent_corners=False):
    """A beveled rounded-ish panel suitable for 9-slice (corners within the 8px margin)."""
    g = _blank(w, h)
    # Fill
    _rect(g, 1, 1, w - 1, h - 1, fill)
    # Outer 1px outline (dark)
    _border(g, 0, 0, w, h, outline)
    # Inner edge: top/left highlight, bottom/right shade (the 2px frame band)
    for x in range(1, w - 1):
        _px(g, x, 1, hi)
        _px(g, x, h - 2, lo)
    for y in range(1, h - 1):
        _px(g, 1, y, hi)
        _px(g, w - 2, y, lo)
    # A subtle 2nd band for depth
    _rect(g, 2, 2, w - 2, 3, outer)
    _rect(g, 2, h - 3, w - 2, h - 2, outer)
    _rect(g, 2, 2, 3, h - 2, outer)
    _rect(g, w - 3, 2, w - 2, h - 2, outer)
    # Rounded-ish corners: clear the 4 outermost corner pixels (reads as a soft corner)
    for (cx, cy) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        _px(g, cx, cy, TRANSPARENT)
    if accent_corners:
        for (cx, cy) in [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3)]:
            _px(g, cx, cy, JADE)
    return g


def gen_panel():
    g = _bevel_panel(24, 24, SURFACE, SURFACE_HI, SURFACE_LO, INK_1, INK_0,
                     accent_corners=True)
    _png(os.path.join(UI_DIR, "panels/panel.png"), 24, 24, g)


def gen_panel_inset():
    g = _bevel_panel(24, 24, INSET, SURFACE_LO, INK_0, INK_0, INK_0)
    _png(os.path.join(UI_DIR, "panels/panel_inset.png"), 24, 24, g)


def gen_button(name, fill, hi, lo, outline=INK_0, accent=False):
    g = _bevel_panel(24, 24, fill, hi, lo, INK_1, outline, accent_corners=accent)
    _png(os.path.join(UI_DIR, "buttons/%s.png" % name), 24, 24, g)


def gen_button_focus():
    # Transparent center, bright jade outline — overlaid on the normal button for focus.
    g = _blank(24, 24)
    _border(g, 0, 0, 24, 24, JADE)
    _border(g, 1, 1, 23, 23, JADE_DK)
    for (cx, cy) in [(0, 0), (23, 0), (0, 23), (23, 23)]:
        _px(g, cx, cy, TRANSPARENT)
    _png(os.path.join(UI_DIR, "buttons/button_focus.png"), 24, 24, g)


def gen_key_badge():
    # 16x16 keycap chip (9-slice margin 6): dark cap with a jade top-light and gold base.
    w = h = 16
    g = _blank(w, h)
    _rect(g, 1, 1, w - 1, h - 1, BADGE)
    _border(g, 0, 0, w, h, INK_0)
    for x in range(1, w - 1):          # top highlight
        _px(g, x, 1, SURFACE_HI)
    for x in range(1, w - 1):          # bottom base shade (keycap depth)
        _px(g, x, h - 2, INK_0)
        _px(g, x, h - 3, SURFACE_LO)
    for y in range(1, h - 1):
        _px(g, 1, y, SURFACE_HI)
        _px(g, w - 2, y, SURFACE_LO)
    for (cx, cy) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]:
        _px(g, cx, cy, TRANSPARENT)
    _png(os.path.join(UI_DIR, "frames/key_badge.png"), w, h, g)


def gen_portrait_frame():
    # 24x24 frame with a transparent center well for a portrait slot (9-slice margin 8).
    w = h = 24
    g = _bevel_panel(w, h, INSET, SURFACE_HI, SURFACE_LO, INK_1, INK_0)
    # Carve a transparent center so a portrait behind shows through; jade inner ring.
    _rect(g, 4, 4, w - 4, h - 4, TRANSPARENT)
    _border(g, 3, 3, w - 3, h - 3, JADE_DK)
    _png(os.path.join(UI_DIR, "frames/portrait_frame.png"), w, h, g)


def gen_title_divider():
    # 48x8 ornamental horizontal rule: a jade line with a gold center diamond.
    w, h = 48, 8
    g = _blank(w, h)
    _rect(g, 2, 3, w - 2, 5, JADE_DK)      # base rule
    _rect(g, 2, 3, w - 2, 4, JADE)         # bright top of rule
    # Center diamond ornament
    cx = w // 2
    _px(g, cx, 1, GOLD)
    _rect(g, cx - 1, 2, cx + 2, 6, GOLD)
    _px(g, cx - 2, 3, GOLD)
    _px(g, cx + 2, 3, GOLD)
    _px(g, cx - 2, 4, GOLD)
    _px(g, cx + 2, 4, GOLD)
    _px(g, cx, 6, GOLD)
    # End caps
    _px(g, 1, 3, JADE)
    _px(g, 1, 4, JADE)
    _px(g, w - 2, 3, JADE)
    _px(g, w - 2, 4, JADE)
    _png(os.path.join(UI_DIR, "frames/title_divider.png"), w, h, g)


if __name__ == "__main__":
    gen_panel()
    gen_panel_inset()
    gen_button("button_normal", BTN, BTN_HI, BTN_LO)
    gen_button("button_hover", BTN_HOVER, BTN_HOVER_HI, BTN_LO, accent=True)
    gen_button("button_pressed", BTN_PRESSED, BTN_LO, INK_0)
    gen_button("button_disabled", BTN_DISABLED, SURFACE_LO, INK_0)
    gen_button_focus()
    gen_key_badge()
    gen_portrait_frame()
    gen_title_divider()
    print("done")
