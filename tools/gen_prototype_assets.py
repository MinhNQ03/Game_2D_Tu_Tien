#!/usr/bin/env python3
"""Generate Aetheria pixel-art PNG assets (project-owned, self-made).

This is a BUILD-TIME TOOL only. The game runtime never imports or depends on it; it
exists so the committed textures are reproducible and provably self-made (no external
or licensed asset enters the project — `.kiro/steering/06-art-assets.md`).

It writes true RGBA PNGs using only the Python standard library (zlib + struct), so no
third-party image library is required.

Outputs (16px base tile, nearest/no-mipmap pixel art — `06-art-assets.md`):
  assets/sprites/characters/player_proto.png        32x48 static fallback frame
  assets/sprites/characters/<name>_idle.png         128x192 (4 frames x 4 directions)
  assets/sprites/characters/<name>_walk.png         192x192 (6 frames x 4 directions)
  assets/tiles/prototype/prototype_tileset.png      48x16 strip of 3x 16x16 tiles
  assets/sprites/props/prop_*.png                   garden-courtyard props
  assets/sprites/sects/emblem_*.png                 16x16 sect insignia

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


# --- Cultivator characters: 32x48 ANIMATED 4-direction sprites (D-046) -------
#
# This REPLACES the flat 16x24 single-pose proto figure. Two things were wrong with it:
#
#   1. It carried ONE frame per direction, and every visual profile left `walk_sheet` null,
#      so the character slid across the floor without ever animating. That — not the pixel
#      count — is what read as lifeless.
#   2. 16x24 cannot carry the look this game is actually going for. The art direction is
#      taken from the two painted reference portraits in
#      `assets/sprites/characters/portraits/` (project-owned, self-generated), whose
#      MEASURED signature is: waist-length white/silver hair, a pale layered floor-length
#      robe, and one saturated qi orb held in the hand. At a 6px-wide torso none of those
#      three reads survive.
#
# 32x48 is exactly 2x the documented 16x24 baseline, so the 16px tile grid math is unchanged
# (the figure is 2 tiles wide, 3 tall) and every scale factor stays an integer.
#
# MEASURED reference palettes (sampled from the PNGs, not invented — L-021). Per-band
# dominant colours plus the most-saturated / brightest pixel of each file:
#   cultivator_male.png   (310x560): hair 208,192,192 | robe 192,192,208 -> 160,160,192
#                                    -> 80,96,128 | deep aura 32,64,112
#                                    | orb 51,153,240 | core 233,254,255
#   cultivator_female.png (300x560): hair 240,224,224 | robe 160,160,224 -> 128,128,192
#                                    -> 96,96,160 | deep aura 48,48,112
#                                    | orb 145,92,234 | core 255,252,252
# The gold filigree visible in the references is 1px-scale detail at this size, so it is
# translated honestly into a single accent line rather than faked as texture. The elder and
# merchant palettes are DERIVED in the same family (no reference was measured for them).

CHAR_W, CHAR_H = 32, 48
CHAR_CX = CHAR_W // 2
DIRECTION_COUNT = 4
IDLE_FRAMES = 4
WALK_FRAMES = 6
OUTLINE = (18, 18, 26, 255)


class Dir:
    """Sheet ROW order. MUST match `CharacterVisualProfileData.Direction`."""
    DOWN = 0
    UP = 1
    LEFT = 2
    RIGHT = 3


# Robe silhouette: half-width per row band, shoulders down to the hem sweep. The cinched
# waist then flaring A-line is the shape every reference shares.
# Shoulders must be WIDER than the head+hair or the figure reads as a bowling pin instead of
# a person; the hem then sweeps out to roughly twice the waist for the A-line.
_ROBE_BANDS = (
    (15, 18, 7),    # shoulders   14px
    (18, 27, 6),    # chest       12px
    (27, 30, 5),    # sash cinch  10px
    (30, 35, 6),
    (35, 40, 7),
    (40, 44, 8),
    (44, 47, 9),    # hem sweep   18px
)


def _robe_half(y):
    for (y0, y1, half) in _ROBE_BANDS:
        if y0 <= y < y1:
            return half
    return 0


# Per-frame animation deltas. Idle is a slow breath; walk is a hem/sleeve stride with a bob.
# A floor-length robe hides the legs, so the stride has to read from the HEM sway, the body
# bob and the sleeve swing — plus a hint of the forward foot under the hem.
_IDLE_BOB = (0, 0, 1, 0)
_IDLE_SWAY = (0, 1, 0, -1)
_IDLE_ORB = (0, -1, -1, 0)
# The walk deltas are deliberately BIG. A first pass used +/-1px and was indistinguishable
# from idle at 1x on screen, which defeats the whole point of adding a walk sheet.
_WALK_BOB = (0, -1, -1, 0, -1, -1)
_WALK_SWAY = (-2, -1, 1, 2, 1, -1)
_WALK_ORB = (0, -1, 0, 1, 0, -1)
_WALK_FOOT = (-3, -1, 2, 3, 1, -2)


def _anim_deltas(anim, frame):
    """(body bob, hem/sleeve sway, orb bob, forward-foot offset) for this animation frame."""
    if anim == "walk":
        i = frame % WALK_FRAMES
        return _WALK_BOB[i], _WALK_SWAY[i], _WALK_ORB[i], _WALK_FOOT[i]
    i = frame % IDLE_FRAMES
    return _IDLE_BOB[i], _IDLE_SWAY[i], _IDLE_ORB[i], 0


def _glow(px, cx, cy, radius, color, peak=255):
    """Soft radial halo. Blends over whatever is already there; leaves partial alpha at the
    rim so the outline pass (which only outlines FULLY opaque pixels) never traces a glow."""
    r2 = float(radius * radius) or 1.0
    for y in range(max(0, cy - radius), min(len(px), cy + radius + 1)):
        for x in range(max(0, cx - radius), min(len(px[0]), cx + radius + 1)):
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            if d2 > r2:
                continue
            t = 1.0 - (d2 / r2) ** 0.5
            a = int(peak * (t ** 1.5))
            if a <= 4:
                continue
            dr, dg, db, da = px[y][x]
            if da == 0:
                px[y][x] = (color[0], color[1], color[2], a)
            else:
                k = a / 255.0
                px[y][x] = (
                    int(color[0] * k + dr * (1 - k)),
                    int(color[1] * k + dg * (1 - k)),
                    int(color[2] * k + db * (1 - k)),
                    max(da, a),
                )


def _outline_pass(px):
    """Trace a 1px dark outline around the opaque silhouette.

    Derived from the pixels rather than hand-drawn, so the outline stays correct for every
    pose/frame instead of drifting when a limb moves. Only FULLY opaque neighbours count, so
    the soft qi-orb halo is never outlined.
    """
    h = len(px)
    w = len(px[0])
    edge = []
    for y in range(h):
        for x in range(w):
            if px[y][x][3] != 0:
                continue
            for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx = x + dx
                ny = y + dy
                if 0 <= nx < w and 0 <= ny < h and px[ny][nx][3] == 255:
                    edge.append((x, y))
                    break
    for (x, y) in edge:
        px[y][x] = OUTLINE


def _draw_robe(px, pal, bob, sway):
    """The layered floor-length robe: lit shoulders, shaded hem, a cinched sash, a centre
    lapel line standing in for the references' gold filigree, and a swaying hem."""
    cx = CHAR_CX
    for y in range(15, 47):
        half = _robe_half(y)
        if half == 0:
            continue
        # The sway only affects the loose lower robe; the shoulders stay put.
        drift = 0
        if y >= 35:
            drift = sway
        elif y >= 30:
            drift = sway // 2
        yy = y + bob if y < 30 else y
        tone = pal["robe"]
        if y < 20:
            tone = pal["robe_hi"]          # top-lit shoulders
        elif y >= 40:
            tone = pal["robe_dk"]          # hem in shadow
        elif y >= 30:
            tone = pal["robe"]
        _rect(px, cx - half + drift, yy, cx + half + drift, yy + 1, tone)
        # Inner shadow along the left edge gives the robe a round volume.
        _rect(px, cx - half + drift, yy, cx - half + drift + 1, yy + 1,
              _shade(tone, 0.78))
    # A single contact row grounds the figure. It is ONE row on purpose: a thicker band reads
    # as a dark slab bolted to the bottom of the robe rather than a shadow under a hem.
    _rect(px, cx - 8 + sway, 46, cx + 8 + sway, 47, pal["robe_deep"])
    # Sash: the cinched waist every reference shares.
    _rect(px, cx - 6, 27 + bob, cx + 6, 30 + bob, pal["trim"])
    _rect(px, cx - 6, 27 + bob, cx + 6, 28 + bob, _shade(pal["trim"], 1.25))
    # Centre lapel line (the honest pixel translation of the gold filigree).
    _rect(px, cx - 1, 16 + bob, cx + 1, 27 + bob, pal["trim"])


def _draw_sleeves(px, pal, bob, sway, swap):
    """Wide flowing sleeves. `swap` swings them in opposite phase for the walk stride."""
    cx = CHAR_CX
    for (side, phase) in ((-1, 1), (1, -1)):
        drift = (sway * phase) if swap else 0
        x0 = (cx - 9) if side < 0 else (cx + 6)
        x0 += drift
        _rect(px, x0, 18 + bob, x0 + 3, 30 + bob, pal["robe"])
        _rect(px, x0, 18 + bob, x0 + 3, 21 + bob, pal["robe_hi"])
        _rect(px, x0, 27 + bob, x0 + 3, 30 + bob, pal["robe_dk"])
        # A seam against the torso, or the sleeve dissolves into the robe and the figure
        # loses its arms entirely.
        seam_x = (x0 + 3) if side < 0 else (x0 - 1)
        _rect(px, seam_x, 18 + bob, seam_x + 1, 30 + bob, pal["robe_deep"])
        # The hand at the cuff.
        _rect(px, x0 + 1, 30 + bob, x0 + 3, 32 + bob, pal["skin"])


def _draw_head(px, pal, bob):
    """The face only. Narrow (8px) on purpose: with the hair adding a pixel each side the head
    lands at ~10px against 14px shoulders, which is what gives the figure a shoulder line."""
    cx = CHAR_CX
    _rect(px, cx - 4, 5 + bob, cx + 4, 15 + bob, pal["skin"])
    _rect(px, cx - 4, 12 + bob, cx + 4, 15 + bob, _shade(pal["skin"], 0.84))  # jaw shadow
    _rect(px, cx - 2, 15 + bob, cx + 2, 16 + bob, _shade(pal["skin"], 0.72))  # neck


def _draw_hair_down(px, pal, bob, sway):
    """Front view: a crown plus the two long white locks that frame the chest.

    `hair_dk` under the crown is what stops the hair and the face merging into one pale
    blob — at this size a hairline SHADOW does more for the read than extra hair pixels.
    """
    cx = CHAR_CX
    _rect(px, cx - 5, 2 + bob, cx + 5, 7 + bob, pal["hair"])
    _rect(px, cx - 5, 2 + bob, cx + 5, 4 + bob, pal["hair_hi"])    # top-lit crown
    _rect(px, cx - 5, 6 + bob, cx + 5, 7 + bob, pal["hair_dk"])    # hairline shadow
    _rect(px, cx - 5, 6 + bob, cx - 4, 14 + bob, pal["hair"])      # temples
    _rect(px, cx + 4, 6 + bob, cx + 5, 14 + bob, pal["hair"])
    # The long locks, drifting with the sway at their tips.
    for (x0, phase) in ((cx - 6, 1), (cx + 5, -1)):
        _rect(px, x0, 13 + bob, x0 + 2, 23 + bob, pal["hair"])
        _rect(px, x0 + (sway * phase), 23 + bob, x0 + 2 + (sway * phase), 29 + bob,
              pal["hair_dk"])
    # A topknot crown pin — the one warm accent on an otherwise cool figure.
    _rect(px, cx - 2, 1 + bob, cx + 2, 3 + bob, pal["trim"])


def _draw_hair_up(px, pal, bob, sway):
    """Back view: a full curtain of hair. Drawn AFTER the head so no skin shows through —
    the back of a head is hair, and a first pass that drew this first put a bare face on
    the character's back in every UP frame."""
    cx = CHAR_CX
    _rect(px, cx - 5, 2 + bob, cx + 5, 16 + bob, pal["hair"])
    _rect(px, cx - 5, 2 + bob, cx + 5, 5 + bob, pal["hair_hi"])
    _rect(px, cx - 6, 16 + bob, cx + 6, 27 + bob, pal["hair"])
    _rect(px, cx - 5 + sway, 27 + bob, cx + 5 + sway, 32 + bob, pal["hair_dk"])
    # A centre parting plus shaded outer edges. Without them this is one flat white block
    # that reads as a cloak or a sheet rather than a head of long hair.
    _rect(px, cx, 4 + bob, cx + 1, 30 + bob, pal["hair_dk"])
    _rect(px, cx - 6, 16 + bob, cx - 5, 27 + bob, pal["hair_dk"])
    _rect(px, cx + 5, 16 + bob, cx + 6, 27 + bob, pal["hair_dk"])
    _rect(px, cx - 2, 1 + bob, cx + 2, 3 + bob, pal["trim"])


def _draw_hair_left(px, pal, bob, sway):
    """Profile: hair swept back off the face, mass behind the head."""
    cx = CHAR_CX
    _rect(px, cx - 4, 2 + bob, cx + 5, 7 + bob, pal["hair"])
    _rect(px, cx - 4, 2 + bob, cx + 5, 4 + bob, pal["hair_hi"])
    _rect(px, cx - 4, 6 + bob, cx + 1, 7 + bob, pal["hair_dk"])    # hairline over the brow
    _rect(px, cx + 1, 4 + bob, cx + 5, 16 + bob, pal["hair"])      # swept-back mass
    _rect(px, cx + 2 + sway, 16 + bob, cx + 5 + sway, 27 + bob, pal["hair"])
    _rect(px, cx + 2 + sway, 24 + bob, cx + 5 + sway, 27 + bob, pal["hair_dk"])
    _rect(px, cx - 2, 1 + bob, cx + 2, 3 + bob, pal["trim"])


def _draw_face(px, pal, direction, bob):
    """Eyes only; at this scale a mouth reads as dirt. UP draws nothing (back of the head)."""
    cx = CHAR_CX
    eye = OUTLINE
    y = 9 + bob
    if not (0 <= y < CHAR_H):
        return
    if direction == Dir.DOWN:
        px[y][cx - 3] = eye
        px[y][cx + 2] = eye
    elif direction == Dir.LEFT:
        px[y][cx - 3] = eye
        px[y][cx - 5] = _shade(pal["skin"], 0.7)   # nose/brow edge in profile


def _draw_orb(px, pal, direction, orb_bob, sway):
    """The qi orb — the single saturated element on a pale figure, and the whole reason the
    character reads as a cultivator rather than a villager in a dress."""
    cx = CHAR_CX
    if direction == Dir.DOWN:
        ox, oy = cx - 10, 25
    elif direction == Dir.UP:
        ox, oy = cx + 10, 25
    else:                      # LEFT (RIGHT is this frame mirrored)
        ox, oy = cx - 11, 24
    oy += orb_bob
    ox += sway
    _glow(px, ox, oy, 5, pal["orb"], 120)
    _glow(px, ox, oy, 3, pal["orb"], 225)
    _rect(px, ox, oy, ox + 1, oy + 1, pal["orb_core"])


def _render_cultivator(direction, pal, anim, frame):
    """Render ONE 32x48 frame and return it. RIGHT is LEFT mirrored, so the two profiles can
    never drift apart (04-coding-standards: no duplicated drawing logic)."""
    if direction == Dir.RIGHT:
        src = _render_cultivator(Dir.LEFT, pal, anim, frame)
        return [list(reversed(row)) for row in src]

    px = _blank(CHAR_W, CHAR_H)
    bob, sway, orb_bob, foot = _anim_deltas(anim, frame)

    # A hint of the forward foot under the hem sells the stride (walk only).
    if anim == "walk" and foot != 0:
        _rect(px, CHAR_CX + foot - 2, 45, CHAR_CX + foot + 2, 47, pal["robe_hi"])

    _draw_robe(px, pal, bob, sway)
    _draw_sleeves(px, pal, bob, sway, anim == "walk")
    _draw_head(px, pal, bob)

    # Hair goes on LAST, over the head, for every facing. For UP that is what makes the back
    # of the head read as hair instead of a face.
    if direction == Dir.UP:
        _draw_hair_up(px, pal, bob, sway)
    elif direction == Dir.LEFT:
        _draw_hair_left(px, pal, bob, sway)
    else:
        _draw_hair_down(px, pal, bob, sway)

    _draw_face(px, pal, direction, bob)
    _outline_pass(px)
    _draw_orb(px, pal, direction, orb_bob, sway)   # after the outline: a halo is not a body
    return px


def _blit(px, src, ox, oy):
    for y in range(len(src)):
        ty = oy + y
        if ty < 0 or ty >= len(px):
            continue
        for x in range(len(src[0])):
            c = src[y][x]
            if c[3] == 0:
                continue
            tx = ox + x
            if 0 <= tx < len(px[0]):
                px[ty][tx] = c


def _draw_cultivator(px, ox, oy, direction, pal, anim, frame):
    _blit(px, _render_cultivator(direction, pal, anim, frame), ox, oy)


# Palettes. The player and female cultivator come from the MEASURED references (see the
# module comment); the elder and merchant are derived in the same family.
#
# ONE deliberate translation: the male reference's measured hair tone (208,192,192) is almost
# the same VALUE as its skin, so using it as the main hair colour merged the head into a
# single pale blob at this size. It is kept as `hair_dk` (the hairline/underside shadow) and
# the lit hair is a cooler, lighter silver. Pixel art needs value separation that a soft
# painted render gets from line work.
CULTIVATORS = {
    # Young cultivator (the player) — the male reference: silver hair, pale blue-white robe,
    # azure qi orb.
    "player_proto": {
        "hair": (230, 232, 242, 255), "hair_hi": (250, 252, 255, 255),
        "hair_dk": (208, 192, 192, 255),
        "skin": (236, 206, 178, 255),
        "robe_hi": (206, 208, 224, 255), "robe": (168, 172, 202, 255),
        "robe_dk": (124, 134, 170, 255), "robe_deep": (56, 72, 110, 255),
        "trim": (214, 186, 120, 255),
        "orb": (51, 153, 240, 255), "orb_core": (233, 254, 255, 255),
    },
    # Female cultivator — the female reference: white hair, violet layered robe, amethyst orb.
    "cultivator_f_proto": {
        "hair": (240, 224, 224, 255), "hair_hi": (255, 252, 252, 255),
        "hair_dk": (206, 192, 200, 255),
        "skin": (240, 212, 192, 255),
        "robe_hi": (186, 186, 230, 255), "robe": (144, 144, 206, 255),
        "robe_dk": (112, 112, 176, 255), "robe_deep": (56, 56, 120, 255),
        "trim": (222, 196, 136, 255),
        "orb": (145, 92, 234, 255), "orb_core": (255, 252, 252, 255),
    },
    # Elder — white hair, grey-jade robe, pale jade orb.
    "elder_proto": {
        "hair": (236, 238, 240, 255), "hair_hi": (255, 255, 255, 255),
        "hair_dk": (196, 200, 204, 255),
        "skin": (222, 192, 166, 255),
        "robe_hi": (176, 182, 184, 255), "robe": (130, 138, 142, 255),
        "robe_dk": (96, 104, 110, 255), "robe_deep": (46, 54, 60, 255),
        "trim": (186, 166, 104, 255),
        "orb": (120, 206, 178, 255), "orb_core": (238, 255, 250, 255),
    },
    # Wandering cultivator / merchant — dark hair, earthy robe, warm amber orb.
    "merchant_proto": {
        "hair": (86, 64, 50, 255), "hair_hi": (124, 96, 72, 255),
        "hair_dk": (52, 38, 30, 255),
        "skin": (232, 196, 160, 255),
        "robe_hi": (188, 154, 104, 255), "robe": (154, 120, 76, 255),
        "robe_dk": (118, 90, 56, 255), "robe_deep": (58, 42, 26, 255),
        "trim": (214, 186, 120, 255),
        "orb": (240, 178, 74, 255), "orb_core": (255, 246, 214, 255),
    },
}


def _cell(px, col, row):
    """The flat pixel list of one frame cell, for comparing frames."""
    out = []
    for y in range(CHAR_H):
        row_px = px[row * CHAR_H + y]
        out.extend(row_px[col * CHAR_W:(col + 1) * CHAR_W])
    return out


def _verify_sheet_animates(label, px, frames):
    """Fail LOUD if the sheet has no visible motion, or if two facings are identical.

    This guards the exact defect D-046 existed to fix (L-029): an animation INDEX that
    advances over identical frames is still a static character. No runtime assertion can see
    it — the sheet dimensions are right, the frame counter increments, every test passes — so
    the check belongs here, where the art is produced and where it can actually be run
    (Godot is not runnable locally, D-009).
    """
    if frames > 1:
        # Every ADJACENT pair must differ, wrapping round. "At least one frame differs" would
        # pass a cycle with a frozen step in it, which reads as a stutter on screen.
        for direction in range(DIRECTION_COUNT):
            for frame in range(frames):
                nxt = (frame + 1) % frames
                if _cell(px, frame, direction) == _cell(px, nxt, direction):
                    raise SystemExit(
                        "DEGENERATE ART: %s direction row %d frames %d and %d are "
                        "pixel-identical - the animation would advance its index over a "
                        "motionless character" % (label, direction, frame, nxt))
    # Every facing must be distinguishable, or the character does not turn on screen.
    for a in range(DIRECTION_COUNT):
        for b in range(a + 1, DIRECTION_COUNT):
            if _cell(px, 0, a) == _cell(px, 0, b):
                raise SystemExit(
                    "DEGENERATE ART: %s direction rows %d and %d are pixel-identical - the "
                    "character would not visibly turn" % (label, a, b))


def _gen_cultivator_sheet(name, pal, anim, frames):
    """One sheet: `frames` columns (animation) x 4 rows (DOWN, UP, LEFT, RIGHT)."""
    w = CHAR_W * frames
    h = CHAR_H * DIRECTION_COUNT
    px = _blank(w, h)
    for direction in range(DIRECTION_COUNT):
        for frame in range(frames):
            _draw_cultivator(px, frame * CHAR_W, direction * CHAR_H,
                             direction, pal, anim, frame)
    _verify_sheet_animates("%s_%s" % (name, anim), px, frames)
    _png(os.path.join(ROOT, "assets/sprites/characters/%s_%s.png" % (name, anim)), w, h, px)


def gen_character_sheets():
    for name in CULTIVATORS:
        pal = CULTIVATORS[name]
        _gen_cultivator_sheet(name, pal, "idle", IDLE_FRAMES)
        _gen_cultivator_sheet(name, pal, "walk", WALK_FRAMES)


def gen_player():
    """The single static DOWN frame used as `player.tscn`'s fallback `Sprite2D`.

    It is the SAME drawing as column 0 / row DOWN of the idle sheet (one source of truth for
    the silhouette), so the fallback and the real animated visual read as the same character.
    """
    px = _blank(CHAR_W, CHAR_H)
    _draw_cultivator(px, 0, 0, Dir.DOWN, CULTIVATORS["player_proto"], "idle", 0)
    _png(os.path.join(ROOT, "assets/sprites/characters/player_proto.png"),
         CHAR_W, CHAR_H, px)


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


def gen_training_dummy():
    """A straw training post (Phase 09's combat target).

    It replaces the flat red `Polygon2D` the dummy scene drew. A bare red square was fine as a
    Phase-02 sandbox marker and is wrong in the hub, which is at the production-foundation art
    tier (`06-art-assets.md`): the map is full of shaded, outlined, dithered art and one
    untextured rectangle reads as an unfinished build rather than as a training post.

    32x48, the character baseline, with the base on the bottom row so its origin anchors at
    the ground like every other world sprite. A wrapped straw bale on a wooden post with a
    rope binding and a painted target mark — it must read as something a cultivator HITS, at a
    glance, without a label.
    """
    w, h = 32, 48
    px = _blank(w, h)
    post = (104, 76, 48, 255)
    post_dk = _shade(post, 0.68)
    straw = (198, 168, 98, 255)
    straw_hi = _shade(straw, 1.18)
    straw_dk = _shade(straw, 0.74)
    rope = (150, 112, 62, 255)
    mark = (176, 56, 52, 255)

    # Wooden post + a shadow side, standing on the ground row.
    _rect(px, 13, 30, 19, 47, post)
    _rect(px, 17, 30, 19, 47, post_dk)
    # Straw bale: a tall oval body with a lit upper-left and a shaded lower-right.
    _oval(px, 16, 19, 10, 14, straw)
    _oval(px, 12, 14, 5, 7, straw_hi)
    _oval(px, 20, 24, 5, 7, straw_dk)
    # Ordered dither for straw texture, the same treatment the tiles use — but MASKED to
    # pixels that are already the base straw colour.
    #
    # `_dither()` is tile-local and writes unconditionally, so calling it here speckled the
    # TRANSPARENT canvas outside the bale too: a scatter of floating straw pixels above the
    # silhouette, invisible at 1x and obvious the moment the sprite was viewed at 8x (L-029 —
    # generated pixel art gets looked at magnified before it ships).
    for y in range(h):
        for x in range(w):
            if px[y][x] == straw and _BAYER4[y % 4][x % 4] < 3:
                px[y][x] = straw_hi
    # Two rope bindings, which is what makes it a BALE rather than a boulder.
    _rect(px, 7, 15, 25, 16, rope)
    _rect(px, 7, 24, 25, 25, rope)
    # A painted target mark, so the thing a player is meant to hit is where the eye goes.
    _oval(px, 16, 20, 4, 4, mark)
    _oval(px, 16, 20, 2, 2, straw_hi)
    _outline_pass(px)
    _png(os.path.join(ROOT, "assets/sprites/characters/training_dummy.png"), w, h, px)


def gen_props():
    gen_prop_lantern()
    gen_prop_tree()
    gen_prop_rock()
    gen_prop_planter()
    gen_training_dummy()


if __name__ == "__main__":
    gen_player()
    gen_tileset()
    gen_character_sheets()
    gen_props()
    gen_sect_emblems()
    print("done")
