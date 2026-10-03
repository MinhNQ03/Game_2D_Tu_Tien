#!/usr/bin/env python3
"""Generate Aetheria prototype pixel-art PNG assets (project-owned, self-made).

This is a BUILD-TIME TOOL only. The game runtime never imports or depends on it; it
exists so the committed prototype textures are reproducible and provably self-made
(no external/licensed asset enters the project — `.kiro/steering/06-art-assets.md`).

It writes true RGBA PNGs using only the Python standard library (zlib + struct), so no
third-party image library is required.

Outputs (16px base tile, nearest/no-mipmap pixel art — `06-art-assets.md`):
  assets/sprites/characters/player_proto.png   16x24 top-down character
  assets/tiles/prototype/prototype_tileset.png 48x16 strip of 3x 16x16 tiles
                                                (grass, path, wall/edge)

Run:  python tools/gen_prototype_assets.py
"""
import os
import struct
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

TILE = 16


def _png(path, width, height, pixels):
    """Write an RGBA8 PNG. `pixels` is a list of rows; each row is a list of (r,g,b,a)."""
    raw = bytearray()
    for row in pixels:
        raw.append(0)  # filter type 0 (none) per scanline
        for (r, g, b, a) in row:
            raw += bytes((r, g, b, a))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)  # 8-bit RGBA
    idat = zlib.compress(bytes(raw), 9)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))
    print("wrote %s (%dx%d)" % (os.path.relpath(path, ROOT), width, height))


def _blank(w, h, color=(0, 0, 0, 0)):
    return [[color for _ in range(w)] for _ in range(h)]


def _rect(px, x0, y0, x1, y1, color):
    for y in range(y0, y1):
        for x in range(x0, x1):
            if 0 <= y < len(px) and 0 <= x < len(px[0]):
                px[y][x] = color


# --- Player: 16x24 simple top-down figure (head, body, feet) ----------------
def gen_player():
    w, h = 16, 24
    px = _blank(w, h)
    skin = (235, 200, 165, 255)
    hair = (70, 50, 40, 255)
    tunic = (60, 130, 200, 255)
    tunic_dk = (40, 95, 150, 255)
    boots = (55, 45, 40, 255)
    outline = (20, 20, 28, 255)

    # Head
    _rect(px, 5, 2, 11, 8, skin)
    _rect(px, 5, 1, 11, 3, hair)          # hair cap
    _rect(px, 4, 2, 5, 7, hair)           # side hair
    _rect(px, 11, 2, 12, 7, hair)
    # Eyes
    px[5][6] = outline
    px[5][9] = outline
    # Body / tunic
    _rect(px, 4, 8, 12, 17, tunic)
    _rect(px, 4, 13, 12, 17, tunic_dk)    # lower tunic shade
    # Arms
    _rect(px, 2, 9, 4, 15, skin)
    _rect(px, 12, 9, 14, 15, skin)
    # Legs / boots
    _rect(px, 5, 17, 8, 23, boots)
    _rect(px, 9, 17, 12, 23, boots)
    # Simple outline on the silhouette edges (left/right of body)
    for y in range(8, 17):
        px[y][3] = outline
        px[y][12] = outline
    _png(os.path.join(ROOT, "assets/sprites/characters/player_proto.png"), w, h, px)


# --- Tileset: 48x16 = three 16x16 tiles -------------------------------------
def _tile_grass(px, ox):
    base = (74, 128, 66, 255)
    blade = (92, 156, 80, 255)
    blade2 = (60, 108, 54, 255)
    _rect(px, ox, 0, ox + TILE, TILE, base)
    for (x, y) in [(2, 3), (6, 2), (10, 5), (13, 9), (4, 11), (9, 13), (12, 6), (1, 8)]:
        px[y][ox + x] = blade
    for (x, y) in [(3, 6), (8, 9), (11, 12), (5, 14), (14, 3)]:
        px[y][ox + x] = blade2


def _tile_path(px, ox):
    base = (176, 150, 110, 255)
    grit = (156, 128, 92, 255)
    grit2 = (198, 174, 136, 255)
    _rect(px, ox, 0, ox + TILE, TILE, base)
    for (x, y) in [(3, 2), (7, 5), (11, 3), (13, 10), (5, 9), (9, 12), (2, 13)]:
        px[y][ox + x] = grit
    for (x, y) in [(4, 6), (10, 8), (12, 13), (6, 2)]:
        px[y][ox + x] = grit2


def _tile_wall(px, ox):
    base = (96, 100, 112, 255)
    dark = (66, 70, 82, 255)
    light = (128, 132, 144, 255)
    _rect(px, ox, 0, ox + TILE, TILE, base)
    # Brick seams
    for y in range(0, TILE, 4):
        _rect(px, ox, y, ox + TILE, y + 1, dark)
    for y in range(0, TILE):
        px[y][ox] = dark
        px[y][ox + TILE - 1] = dark
    _rect(px, ox + 1, 1, ox + TILE - 1, 2, light)  # top highlight


def gen_tileset():
    w, h = TILE * 3, TILE
    px = _blank(w, h, (0, 0, 0, 255))
    _tile_grass(px, 0)
    _tile_path(px, TILE)
    _tile_wall(px, TILE * 2)
    _png(os.path.join(ROOT, "assets/tiles/prototype/prototype_tileset.png"), w, h, px)


# --- Character directional idle sheets (Phase 05 art pipeline, D-026) --------
# A sheet is one row of 4 frames (DOWN, UP, LEFT, RIGHT) at 16x24 each (64x24 total), matching
# CharacterVisualProfileData. All archetypes share the same silhouette/anchor baseline (feet at
# the bottom row) and differ only by palette + a couple accent pixels, so the whole cast reads
# as one game (docs/CHARACTER_ART_BIBLE.md), not a mix of packs. Self-made/CC0.

FRAME_W, FRAME_H = 16, 24
OUTLINE = (20, 20, 28, 255)


def _draw_character_frame(px, ox, direction, pal):
    """Draw one 16x24 figure at x-offset `ox` facing `direction` (0=down,1=up,2=left,3=right).

    The silhouette is identical across directions (consistent footprint); only the
    face/accent details change with facing.
    """
    skin = pal["skin"]
    hair = pal["hair"]
    robe = pal["robe"]
    robe_dk = pal["robe_dk"]
    boots = pal["boots"]
    accent = pal["accent"]

    # Head
    _rect(px, ox + 5, 2, ox + 11, 8, skin)
    _rect(px, ox + 5, 1, ox + 11, 3, hair)       # hair cap (all directions)
    _rect(px, ox + 4, 2, ox + 5, 7, hair)
    _rect(px, ox + 11, 2, ox + 12, 7, hair)
    # Body / robe
    _rect(px, ox + 4, 8, ox + 12, 17, robe)
    _rect(px, ox + 4, 13, ox + 12, 17, robe_dk)
    _rect(px, ox + 7, 8, ox + 9, 17, accent)     # a center sash accent (archetype color)
    # Arms
    _rect(px, ox + 2, 9, ox + 4, 15, skin)
    _rect(px, ox + 12, 9, ox + 14, 15, skin)
    # Legs / boots
    _rect(px, ox + 5, 17, ox + 8, 23, boots)
    _rect(px, ox + 9, 17, ox + 12, 23, boots)
    # Silhouette outline (left/right of torso)
    for y in range(8, 17):
        px[y][ox + 3] = OUTLINE
        px[y][ox + 12] = OUTLINE

    # Facing-specific face details.
    if direction == 0:        # DOWN: eyes visible, facing the camera
        px[5][ox + 6] = OUTLINE
        px[5][ox + 9] = OUTLINE
    elif direction == 1:      # UP: back of head, no eyes, more hair
        _rect(px, ox + 5, 2, ox + 11, 5, hair)
    elif direction == 2:      # LEFT: one eye, shifted left
        px[5][ox + 6] = OUTLINE
        _rect(px, ox + 4, 2, ox + 6, 7, hair)
    elif direction == 3:      # RIGHT: one eye, shifted right
        px[5][ox + 9] = OUTLINE
        _rect(px, ox + 10, 2, ox + 12, 7, hair)


def _gen_character_sheet(name, pal):
    w, h = FRAME_W * 4, FRAME_H
    px = _blank(w, h)
    for direction in range(4):
        _draw_character_frame(px, direction * FRAME_W, direction, pal)
    _png(os.path.join(ROOT, "assets/sprites/characters/%s_idle.png" % name), w, h, px)


def gen_character_sheets():
    # Four initial archetypes, one consistent style, distinct palettes (06-art / art bible).
    archetypes = {
        # Player / young cultivator — jade-blue robe.
        "player_proto": {
            "skin": (235, 200, 165, 255), "hair": (70, 50, 40, 255),
            "robe": (60, 130, 200, 255), "robe_dk": (40, 95, 150, 255),
            "boots": (55, 45, 40, 255), "accent": (120, 210, 190, 255),
        },
        # Female cultivator — rose robe.
        "cultivator_f_proto": {
            "skin": (240, 208, 176, 255), "hair": (40, 30, 46, 255),
            "robe": (196, 92, 128, 255), "robe_dk": (150, 64, 96, 255),
            "boots": (70, 48, 60, 255), "accent": (236, 196, 150, 255),
        },
        # Elder — grey robe, white hair.
        "elder_proto": {
            "skin": (224, 196, 168, 255), "hair": (220, 220, 224, 255),
            "robe": (110, 112, 120, 255), "robe_dk": (78, 80, 88, 255),
            "boots": (50, 50, 56, 255), "accent": (170, 150, 90, 255),
        },
        # Wandering cultivator / merchant — earthy brown robe.
        "merchant_proto": {
            "skin": (232, 196, 160, 255), "hair": (56, 40, 30, 255),
            "robe": (150, 112, 68, 255), "robe_dk": (112, 82, 48, 255),
            "boots": (60, 46, 34, 255), "accent": (210, 180, 90, 255),
        },
    }
    for name in archetypes:
        _gen_character_sheet(name, archetypes[name])


if __name__ == "__main__":
    gen_player()
    gen_tileset()
    gen_character_sheets()
    print("done")
