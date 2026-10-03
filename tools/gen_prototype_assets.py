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


def _shade(color, factor):
    """Return `color` lightened (factor>1) or darkened (factor<1), alpha kept, clamped 0..255."""
    r, g, b, a = color
    return (
        max(0, min(255, int(r * factor))),
        max(0, min(255, int(g * factor))),
        max(0, min(255, int(b * factor))),
        a,
    )


# --- Player: 16x24 top-down figure (production-foundation, D-029) -----------
# The player.tscn `Visual` Sprite2D uses this single 16x24 frame directly, so it must match
# the richer, shaded look of the 4-direction archetype sheets (`_draw_character_frame`). We
# reuse that exact drawing (DOWN facing, player jade-blue palette) instead of a second, flatter
# copy — one source of truth for the character silhouette/shading (04-coding-standards: no
# duplicated drawing logic). The companion idle sheet is produced by gen_character_sheets().
_PLAYER_PALETTE = {
    "skin": (235, 200, 165, 255), "hair": (70, 50, 40, 255),
    "robe": (60, 130, 200, 255), "robe_dk": (40, 95, 150, 255),
    "boots": (55, 45, 40, 255), "accent": (120, 210, 190, 255),
}


def gen_player():
    w, h = 16, 24
    px = _blank(w, h)
    _draw_character_frame(px, 0, 0, _PLAYER_PALETTE)   # DOWN-facing, same style as the sheets
    _png(os.path.join(ROOT, "assets/sprites/characters/player_proto.png"), w, h, px)


# --- Tileset: 48x16 = three 16x16 tiles -------------------------------------
# --- Tileset tiles (production-foundation top-down pixel art, D-029) ----------
# Richer than the first prototype: layered shading, a soft ordered-dither between tones and
# scattered detail so a tiled field does not read as one flat colour. Still 16px, nearest,
# wuxia garden-courtyard palette (mossy jade grass, warm flagstone path, blue-grey roof-tile
# wall). The three columns + atlas coords are UNCHANGED (0=grass,1=path,2=wall) so the TileSet
# resource, `prototype_ground.gd` and every map scene keep working with no edit.

# A 4x4 ordered-dither (Bayer) threshold matrix, values 0..15, for a soft two-tone speckle.
_BAYER4 = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def _dither(px, ox, lo, hi, density):
    """Speckle `hi` over the tile where the Bayer threshold is below `density` (0..16)."""
    for y in range(TILE):
        for x in range(TILE):
            if _BAYER4[y % 4][x % 4] < density:
                px[y][ox + x] = hi


def _tile_grass(px, ox):
    # Mossy jade turf: a base, a dithered lighter blend, a darker shadow mottle + grass tufts.
    base = (58, 110, 60, 255)
    light = (84, 146, 82, 255)
    dark = (44, 88, 50, 255)
    blade = (108, 170, 98, 255)
    _rect(px, ox, 0, ox + TILE, TILE, base)
    _dither(px, ox, base, light, 7)                       # soft lit speckle
    for (x, y) in [(2, 11), (10, 4), (13, 13), (6, 14), (3, 5)]:
        px[y][ox + x] = dark                               # shadow mottle
        if y + 1 < TILE:
            px[y + 1][ox + x] = dark
    # A few upright grass blades (two-pixel) for texture, not a lawn.
    for (x, y) in [(4, 9), (8, 6), (12, 10), (6, 12), (10, 13)]:
        px[y][ox + x] = blade
        if y - 1 >= 0:
            px[y - 1][ox + x] = blade


def _tile_path(px, ox):
    # Warm flagstone: paler sandy base, a dither of grit, and a subtle 2x2 cobble seam grid so
    # it reads as laid stone rather than bare dirt.
    base = (182, 158, 118, 255)
    light = (206, 184, 146, 255)
    seam = (150, 126, 92, 255)
    grit = (168, 142, 104, 255)
    _rect(px, ox, 0, ox + TILE, TILE, base)
    _dither(px, ox, base, light, 6)
    # Cobble seams every 8px (a 2x2 flagstone grid within the tile).
    for y in range(TILE):
        for x in range(TILE):
            if x % 8 == 0 or y % 8 == 0:
                px[y][ox + x] = seam
    for (x, y) in [(3, 3), (11, 5), (5, 11), (13, 12), (6, 6)]:
        px[y][ox + x] = grit


def _tile_wall(px, ox):
    # Chinese roof-tile / stone wall edge: blue-grey courses with a warm capstone highlight and
    # a dark base shadow, so a border reads as a tiled courtyard wall seen from above.
    base = (92, 104, 120, 255)
    course = (72, 84, 100, 255)
    cap = (150, 150, 142, 255)
    cap_dk = (116, 116, 110, 255)
    shade = (52, 60, 74, 255)
    _rect(px, ox, 0, ox + TILE, TILE, base)
    # Horizontal roof-tile courses (every 5px) with a slight overlap shadow under each.
    for y in range(0, TILE, 5):
        _rect(px, ox, y, ox + TILE, y + 2, course)
        if y + 2 < TILE:
            _rect(px, ox, y + 2, ox + TILE, y + 3, shade)
    # Warm stone capstone along the top (the lit ridge of a wall from above).
    _rect(px, ox, 0, ox + TILE, 2, cap)
    _rect(px, ox, 2, ox + TILE, 3, cap_dk)
    # Side + bottom shadow so adjacent wall tiles still read as separate blocks.
    for y in range(TILE):
        px[y][ox] = shade
        px[y][ox + TILE - 1] = shade
    _rect(px, ox, TILE - 1, ox + TILE, TILE, shade)


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
    skin_sh = _shade(skin, 0.82)
    hair = pal["hair"]
    hair_hi = _shade(hair, 1.35)
    robe = pal["robe"]
    robe_dk = pal["robe_dk"]
    robe_hi = _shade(robe, 1.22)
    boots = pal["boots"]
    accent = pal["accent"]

    # Full-body dark outline first (silhouette read), then fill inside it.
    _rect(px, ox + 4, 1, ox + 12, 24, OUTLINE)      # torso/head column outline block
    _rect(px, ox + 2, 9, ox + 14, 16, OUTLINE)      # arms span outline

    # Head (inside the outline): skin face + a shaded jaw, hair cap over the top.
    _rect(px, ox + 5, 2, ox + 11, 8, skin)
    _rect(px, ox + 5, 7, ox + 11, 8, skin_sh)        # jaw shadow
    _rect(px, ox + 5, 1, ox + 11, 3, hair)           # hair cap
    _rect(px, ox + 5, 1, ox + 11, 2, hair_hi)        # hair sheen (top-lit)
    _rect(px, ox + 4, 2, ox + 5, 7, hair)            # side hair
    _rect(px, ox + 11, 2, ox + 12, 7, hair)

    # Body / robe: lit upper, shaded lower hem, a center sash accent, a highlight shoulder.
    _rect(px, ox + 5, 8, ox + 12, 17, robe)
    _rect(px, ox + 5, 8, ox + 12, 10, robe_hi)       # top-lit shoulders
    _rect(px, ox + 5, 14, ox + 12, 17, robe_dk)      # lower hem shadow
    _rect(px, ox + 7, 8, ox + 10, 17, accent)        # center sash (archetype colour)
    _rect(px, ox + 8, 8, ox + 9, 17, _shade(accent, 1.2))  # sash highlight line

    # Arms (skin), with a shaded underside.
    _rect(px, ox + 3, 9, ox + 5, 15, skin)
    _rect(px, ox + 11, 9, ox + 13, 15, skin)
    _rect(px, ox + 3, 13, ox + 5, 15, skin_sh)
    _rect(px, ox + 11, 13, ox + 13, 15, skin_sh)

    # Legs / boots (feet on the bottom row = anchor line).
    _rect(px, ox + 5, 17, ox + 8, 23, boots)
    _rect(px, ox + 9, 17, ox + 12, 23, boots)
    _rect(px, ox + 5, 22, ox + 12, 23, _shade(boots, 0.7))  # foot contact shadow

    # Facing-specific face details (eyes drawn as dark pixels on the lit face).
    if direction == 0:        # DOWN: both eyes, facing camera
        px[5][ox + 6] = OUTLINE
        px[5][ox + 9] = OUTLINE
    elif direction == 1:      # UP: back of head — hair covers the face, no eyes
        _rect(px, ox + 5, 2, ox + 11, 6, hair)
        _rect(px, ox + 5, 2, ox + 11, 3, hair_hi)
    elif direction == 2:      # LEFT: profile — one eye left, hair swept left
        px[5][ox + 6] = OUTLINE
        _rect(px, ox + 4, 2, ox + 6, 7, hair)
    elif direction == 3:      # RIGHT: profile — one eye right, hair swept right
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


# --- Decorative props (top-down, production-foundation, D-029) ----------------
# A few Chinese garden-courtyard props placed as presentation-only Sprite2D decorations in the
# hub/field (no collision/gameplay change). Each is its own PNG, feet/base at the bottom row so
# a sprite's origin can anchor at its base like the character. Self-made/CC0, nearest filter.

def _oval(px, cx, cy, rx, ry, color):
    for y in range(len(px)):
        for x in range(len(px[0])):
            dx = (x - cx) / float(rx)
            dy = (y - cy) / float(ry)
            if dx * dx + dy * dy <= 1.0:
                px[y][x] = color


def gen_prop_lantern():
    # A hanging red palace lantern, 12x20 on a 16x24 canvas (base at bottom).
    w, h = 16, 24
    px = _blank(w, h)
    red = (176, 48, 48, 255)
    red_hi = _shade(red, 1.3)
    red_dk = _shade(red, 0.7)
    gold = (210, 180, 90, 255)
    tassel = (196, 60, 60, 255)
    _rect(px, 7, 0, 9, 3, (60, 50, 40, 255))     # cord
    _rect(px, 6, 3, 10, 4, gold)                  # top cap
    _oval(px, 8, 10, 5, 6, red)                   # body
    _oval(px, 6, 9, 2, 3, red_hi)                 # highlight
    _rect(px, 4, 10, 12, 11, red_dk)              # mid rib
    _rect(px, 6, 16, 10, 17, gold)                # bottom cap
    _rect(px, 7, 17, 9, 22, tassel)               # tassel
    _png(os.path.join(ROOT, "assets/sprites/props/prop_lantern.png"), w, h, px)


def gen_prop_tree():
    # A rounded pine/wutong canopy over a short trunk, 32x32, base at bottom center.
    w, h = 32, 32
    px = _blank(w, h)
    trunk = (92, 66, 44, 255)
    trunk_dk = _shade(trunk, 0.7)
    leaf = (46, 104, 56, 255)
    leaf_hi = (76, 142, 78, 255)
    leaf_dk = (34, 78, 44, 255)
    _rect(px, 14, 24, 18, 31, trunk)
    _rect(px, 16, 24, 18, 31, trunk_dk)
    _oval(px, 16, 14, 13, 12, leaf)
    _oval(px, 12, 11, 7, 6, leaf_hi)              # top-left highlight
    _oval(px, 20, 18, 7, 6, leaf_dk)              # bottom-right shadow
    for (x, y) in [(8, 16), (23, 10), (14, 6), (25, 18), (10, 9)]:
        px[y][x] = leaf_hi
    _png(os.path.join(ROOT, "assets/sprites/props/prop_tree.png"), w, h, px)


def gen_prop_rock():
    # A mossy garden rock (taihu-style), 16x12 on a 16x16 canvas, base at bottom.
    w, h = 16, 16
    px = _blank(w, h)
    stone = (120, 122, 130, 255)
    stone_hi = _shade(stone, 1.25)
    stone_dk = _shade(stone, 0.72)
    moss = (72, 120, 64, 255)
    _oval(px, 8, 10, 7, 5, stone)
    _oval(px, 6, 8, 3, 2, stone_hi)
    _oval(px, 11, 12, 3, 2, stone_dk)
    for (x, y) in [(4, 7), (10, 6), (13, 10)]:
        px[y][x] = moss
    _png(os.path.join(ROOT, "assets/sprites/props/prop_rock.png"), w, h, px)


def gen_prop_planter():
    # A stone planter with a small shrub, 16x16, base at bottom.
    w, h = 16, 16
    px = _blank(w, h)
    pot = (150, 120, 96, 255)
    pot_dk = _shade(pot, 0.72)
    leaf = (56, 118, 64, 255)
    leaf_hi = (86, 150, 84, 255)
    _oval(px, 8, 6, 5, 4, leaf)
    _oval(px, 6, 5, 2, 2, leaf_hi)
    _rect(px, 4, 9, 12, 15, pot)
    _rect(px, 4, 13, 12, 15, pot_dk)
    _rect(px, 4, 9, 12, 10, _shade(pot, 1.2))     # rim highlight
    _png(os.path.join(ROOT, "assets/sprites/props/prop_planter.png"), w, h, px)


# --- Sect emblems (16x16, Aetheria tu-tiên palette, Phase 06) -----------------
# Small self-made pixel insignia used by the Sect UI (HUD chip + detail panel) and a hub
# banner. Jade/ink for an orthodox cloud sect; vermilion/gold for a demonic flame sect.
# nearest filter, project-owned (recorded in docs/ASSET_LICENSES.md).

def gen_sect_emblem_azure():
    # A jade "cloud" sigil on a dark ink roundel (Azure Cloud Sect — orthodox).
    w, h = 16, 16
    px = _blank(w, h)
    ink = (26, 32, 38, 255)
    jade = (72, 170, 140, 255)
    jade_hi = _shade(jade, 1.3)
    _oval(px, 8, 8, 7, 7, ink)              # roundel
    _oval(px, 8, 8, 6, 6, _shade(ink, 1.4))
    # Stylized ruyi cloud: two curls + a sweep.
    _oval(px, 6, 7, 2, 2, jade)
    _oval(px, 10, 7, 2, 2, jade)
    _rect(px, 4, 9, 12, 11, jade)
    _rect(px, 6, 6, 7, 7, jade_hi)
    _rect(px, 9, 6, 10, 7, jade_hi)
    _png(os.path.join(ROOT, "assets/sprites/sects/emblem_azure_cloud.png"), w, h, px)


def gen_sect_emblem_crimson():
    # A vermilion flame tipped with gold on a dark roundel (Crimson Flame Sect — demonic).
    w, h = 16, 16
    px = _blank(w, h)
    ink = (34, 24, 26, 255)
    red = (176, 48, 48, 255)
    red_hi = _shade(red, 1.3)
    gold = (210, 180, 90, 255)
    _oval(px, 8, 8, 7, 7, ink)
    _oval(px, 8, 8, 6, 6, _shade(ink, 1.3))
    # Flame body (teardrop): wide base, narrow tip.
    _rect(px, 6, 9, 10, 13, red)
    _oval(px, 8, 10, 3, 4, red)
    _rect(px, 7, 5, 9, 10, red)
    _rect(px, 7, 5, 8, 8, red_hi)           # inner highlight
    px[4][8] = gold                          # gold tip
    px[5][8] = gold
    _png(os.path.join(ROOT, "assets/sprites/sects/emblem_crimson_flame.png"), w, h, px)


def gen_sect_emblems():
    gen_sect_emblem_azure()
    gen_sect_emblem_crimson()


def gen_props():
    gen_prop_lantern()
    gen_prop_tree()
    gen_prop_rock()
    gen_prop_planter()


if __name__ == "__main__":
    gen_player()
    gen_tileset()
    gen_character_sheets()
    gen_props()
    gen_sect_emblems()
    print("done")
