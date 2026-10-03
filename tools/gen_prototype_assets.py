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


if __name__ == "__main__":
    gen_player()
    gen_tileset()
    print("done")
