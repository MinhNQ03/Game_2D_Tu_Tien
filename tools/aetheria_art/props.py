"""World props, the training post and the sect emblems (top-down, 16px grid, pixel art).

Every prop that MOVES in the world (D-057B) is authored with transparent PADDING on the side it
moves toward: the ambient-motion shader shifts pixel rows inside the sprite's own rectangle, so
a sway with no room to sway into would be clipped at the sprite edge. A prop that moves around a
pivot is split from what it hangs on — a banner's cloth from its pole, a lantern from its post —
so the cloth waves and the lantern swings while the wood stays put.
"""
import os

from . import raster

TILE = 16
INK = (18, 18, 26, 255)

# The floor's MEASURED palette (Verdant moss, `assets/tiles/verdant/v16_ground.png`). Grass is
# drawn in the same family, a step more saturated, so a tuft reads ON the floor rather than as
# a sticker from another game.
MOSS_DEEP = (31, 53, 36, 255)
MOSS_DARK = (47, 77, 44, 255)
MOSS = (61, 122, 60, 255)
MOSS_LIGHT = (95, 154, 69, 255)
MOSS_TIP = (124, 184, 82, 255)


def _save(root, rel, px):
    raster.write_png(os.path.join(root, rel), px)
    w, h = raster.size(px)
    print("wrote %s (%dx%d)" % (rel, w, h))


# --- moving props (D-057B) -----------------------------------------------------------------

# Grass: thin blades fanning from a dark root, tips lit. Three variants so a patch is never one
# stamp repeated. (base x, height, lean) per blade.
_TUFTS = (
    ((3, 6, -2), (5, 8, -1), (7, 9, 0), (9, 7, 1), (11, 6, 2), (6, 5, -1), (10, 5, 1)),
    ((4, 7, -1), (6, 10, 0), (8, 8, 1), (10, 6, 2), (5, 5, -2), (9, 6, 1)),
    ((3, 5, -2), (5, 7, -1), (7, 6, 0), (8, 8, 1), (10, 9, 1), (12, 6, 2), (6, 4, 0)),
)


def gen_grass(root):
    for i, blades in enumerate(_TUFTS):
        w, h = 16, 12                      # 2px of air each side for the sway
        px = raster.blank(w, h)
        for (bx, height, lean) in blades:
            tip_x, tip_y = bx + lean, h - 1 - height
            raster.line(px, bx, h - 1, tip_x, tip_y, MOSS)
            raster.line(px, bx + (1 if lean >= 0 else -1), h - 1, tip_x, tip_y + 2, MOSS_DARK)
            raster.put(px, tip_x, tip_y, MOSS_TIP)
            raster.put(px, tip_x - (1 if lean > 0 else 0), tip_y + 1, MOSS_LIGHT)
        raster.rect(px, 4, h - 2, 12, h, MOSS_DEEP)                         # root shadow
        _save(root, "assets/sprites/props/prop_grass_%d.png" % (i + 1), px)


def gen_banner(root):
    """The Thanh Vân Tông banner: a lacquered pole and crossbar, and the cloth hanging from it.

    Two files on purpose. The cloth is CLOTH — it waves, with the wave travelling away from the
    pole and growing toward the free edge — while the pole is rigid wood and must not bend.
    """
    pole = raster.blank(16, 48)
    wood = (88, 56, 40, 255)
    wood_hi = raster.shade(wood, 1.35)
    raster.rect(pole, 7, 4, 9, 47, wood)
    raster.rect(pole, 7, 4, 8, 47, wood_hi)
    raster.rect(pole, 2, 4, 15, 6, wood)                                   # crossbar
    raster.rect(pole, 2, 4, 15, 5, wood_hi)
    raster.oval(pole, 8, 2.5, 1.6, 1.6, (206, 176, 104, 255))              # gilded finial
    raster.oval(pole, 8, 45.5, 4, 1.6, (96, 100, 104, 255))                # stone footing
    raster.outline(pole, INK)
    _save(root, "assets/sprites/props/prop_banner_pole.png", pole)

    cloth = raster.blank(20, 28)                                            # 6px of air: the wave
    silk = (226, 230, 236, 255)
    silk_dk = (184, 192, 204, 255)
    jade = (72, 170, 140, 255)
    jade_hi = raster.shade(jade, 1.3)
    gold = (206, 176, 104, 255)
    raster.rect(cloth, 1, 0, 13, 24, silk)
    raster.rect(cloth, 10, 0, 13, 24, silk_dk)                              # shaded fold
    raster.rect(cloth, 1, 0, 13, 2, raster.shade(silk, 0.9))                # hem under the bar
    # The cloud sigil of the sect, the same mark as its emblem, woven in jade.
    raster.oval(cloth, 5, 9, 2, 2, jade)
    raster.oval(cloth, 9, 9, 2, 2, jade)
    raster.rect(cloth, 3, 11, 11, 13, jade)
    raster.put(cloth, 5, 8, jade_hi)
    raster.put(cloth, 9, 8, jade_hi)
    raster.rect(cloth, 4, 16, 10, 17, jade)                                 # a ruled line
    # A swallow-tail lower edge with a gold fringe.
    raster.polygon(cloth, [(1, 24), (13, 24), (13, 26), (7, 23), (1, 26)], silk)
    for x in range(1, 14, 2):
        raster.put(cloth, x, 25 if x in (1, 13) else 24, gold)
    raster.outline(cloth, INK)
    _save(root, "assets/sprites/props/prop_banner_cloth.png", cloth)


def gen_tree(root):
    """A broadleaf tree: a lobed canopy over a trunk with a root flare. 40x44, 3px of air at
    each side and the top for the canopy's sway; the trunk barely moves (heavy, rooted)."""
    w, h = 40, 44
    px = raster.blank(w, h)
    trunk = (92, 66, 44, 255)
    trunk_dk = raster.shade(trunk, 0.7)
    leaf = (46, 104, 56, 255)
    leaf_hi = (76, 142, 78, 255)
    leaf_tip = (104, 168, 90, 255)
    leaf_dk = (32, 76, 44, 255)
    raster.polygon(px, [(17, 30), (23, 30), (24, 42), (27, 43), (13, 43), (16, 42)], trunk)
    raster.polygon(px, [(20, 30), (23, 30), (24, 42), (27, 43), (20, 43)], trunk_dk)
    raster.oval(px, 20, 42.5, 9, 1.6, (12, 16, 22, 90))                    # contact shadow
    # Canopy: lobes, dark ones first so the lit ones overlap them (top-left light).
    for (cx, cy, rx, ry, col) in ((12, 22, 8, 7, leaf_dk), (28, 22, 8, 7, leaf_dk),
                                  (20, 25, 10, 6, leaf_dk), (14, 15, 8, 7, leaf),
                                  (26, 15, 8, 7, leaf), (20, 10, 9, 7, leaf),
                                  (20, 19, 10, 7, leaf)):
        raster.oval(px, cx, cy, rx, ry, col)
    for (cx, cy, rx, ry) in ((16, 9, 5, 3), (11, 14, 3, 3), (22, 6, 3, 2)):
        raster.oval(px, cx, cy, rx, ry, leaf_hi)
    # Leaf clusters: a lit crescent on top of each lobe and a dark notch under it, placed by
    # hand. An ordered dither over the whole canopy read as a polka-dot grid, not foliage.
    for (cx, cy) in ((12, 18), (27, 18), (20, 21), (26, 11), (14, 11), (20, 15), (31, 15)):
        raster.rect(px, cx - 1, cy - 1, cx + 2, cy, leaf_hi)
        raster.put(px, cx, cy - 2, leaf_tip)
        raster.rect(px, cx - 1, cy + 1, cx + 1, cy + 2, leaf_dk)
    for (x, y) in ((15, 7), (19, 5), (10, 13), (24, 9), (13, 17)):
        raster.put(px, x, y, leaf_tip)
    raster.outline(px, INK)
    _save(root, "assets/sprites/props/prop_tree_broadleaf.png", px)


def gen_lantern_post(root):
    """A wooden lantern post with an arm, and the paper lantern that hangs from it (separate,
    so the lantern can swing about its cord while the post stays put)."""
    post = raster.blank(20, 48)
    wood = (84, 58, 42, 255)
    raster.rect(post, 3, 6, 6, 47, wood)
    raster.rect(post, 3, 6, 4, 47, raster.shade(wood, 1.3))
    raster.rect(post, 3, 6, 17, 8, wood)                                   # the arm
    raster.rect(post, 3, 6, 17, 7, raster.shade(wood, 1.3))
    raster.oval(post, 4.5, 45.5, 3, 1.4, (96, 100, 104, 255))
    raster.outline(post, INK)
    _save(root, "assets/sprites/props/prop_lantern_post.png", post)

    lantern = raster.blank(16, 24)                                          # 3px of air for swing
    red = (176, 48, 48, 255)
    gold = (210, 180, 90, 255)
    raster.rect(lantern, 7, 0, 9, 4, (60, 50, 40, 255))                     # cord
    raster.rect(lantern, 5, 4, 11, 5, gold)
    raster.oval(lantern, 8, 10.5, 4.5, 5.5, red)
    raster.oval(lantern, 6.5, 9, 1.6, 2.6, raster.shade(red, 1.35))
    raster.rect(lantern, 4, 10, 13, 11, raster.shade(red, 0.72))
    raster.rect(lantern, 5, 16, 11, 17, gold)
    raster.rect(lantern, 7, 17, 9, 21, (196, 60, 60, 255))                  # tassel
    raster.outline(lantern, INK)
    raster.glow(lantern, 8, 10, 6, (255, 200, 120, 255), 70)               # a warm paper glow
    _save(root, "assets/sprites/props/prop_lantern_hanging.png", lantern)


def gen_mist(root):
    """Low mist for the field: a soft, pale bank with no hard edge. Alpha is built from
    concentric bands and ordered-dithered between them, so the bank thins out in PIXELS (a
    pixel-art gradient) instead of a smooth alpha ramp that would read as a blurred sticker.
    The runtime shader drifts and thins it; the texture itself is still."""
    w, h = 64, 20
    px = raster.blank(w, h)
    pale = (214, 224, 234)
    # Three overlapping lobes, not one ellipse: a single oval read as a pale disc on the floor.
    lobes = ((-13.0, 1.5, 1.0), (1.0, -1.5, 1.15), (15.0, 1.0, 0.9))       # (dx, dy, size)
    bands = ((17, 8, 42), (13, 6, 70), (9, 4, 96))            # (rx, ry, alpha): outer -> core
    for (rx, ry, alpha) in bands:
        for y in range(h):
            for x in range(w):
                d = min(((x + 0.5 - w / 2.0 - lx) / (rx * k)) ** 2
                        + ((y + 0.5 - h / 2.0 - ly) / (ry * k)) ** 2 for (lx, ly, k) in lobes)
                if d > 1.0:
                    continue
                # Dither the outer third of each band, so the step to the next band is a
                # scatter of pixels rather than a ring.
                if d > 0.66 and raster.BAYER4[y % 4][x % 4] < int((d - 0.66) / 0.34 * 16):
                    continue
                raster.put(px, x, y, pale + (alpha,))
    _save(root, "assets/sprites/props/prop_mist.png", px)


def gen_training_post(root):
    """The training post (mộc nhân), drawn as something a cultivator TRAINS on: a straw-bound
    head on a wooden post, two short wooden arms jutting from the shoulders of a straw bale, a
    painted mark at the heart, standing in a packed-earth footing.

    The first D-057B pass put a crossbar ABOVE the bale; at 1x it read as a grave cross, which a
    xianxia courtyard must not show. The arms now sit at the bale's shoulders, below a head, so
    the silhouette reads as a figure — what a training dummy is for.

    Its pivot is the footing (bottom centre): a hit makes it WOBBLE about its base — a rigid
    object's response — where a creature recoils."""
    w, h = 32, 48
    px = raster.blank(w, h)
    wood = (104, 76, 48, 255)
    wood_hi = raster.shade(wood, 1.25)
    wood_dk = raster.shade(wood, 0.68)
    straw = (198, 168, 98, 255)
    straw_hi = raster.shade(straw, 1.18)
    straw_dk = raster.shade(straw, 0.74)
    rope = (150, 112, 62, 255)
    mark = (176, 56, 52, 255)
    raster.oval(px, 16, 46, 8, 1.6, (12, 16, 22, 96))                      # contact shadow
    raster.oval(px, 16, 44.5, 6, 2, (110, 92, 70, 255))                     # earth footing
    raster.rect(px, 14, 10, 19, 45, wood)                                   # the post
    raster.rect(px, 17, 10, 19, 45, wood_dk)
    # The arms: short pegs jutting from the bale's shoulders, tips dropping a pixel, lit on top.
    for (x0, x1, tip) in ((4, 11, 4), (21, 28, 27)):
        raster.rect(px, x0, 19, x1, 21, wood)
        raster.rect(px, x0, 19, x1, 20, wood_hi)
        raster.rect(px, tip, 21, tip + 1, 22, wood_dk)
    # The head: a straw knot bound to the top of the post.
    raster.oval(px, 16, 7, 3.6, 3.6, straw)
    raster.oval(px, 15, 6, 1.6, 1.6, straw_hi)
    raster.rect(px, 13, 9, 20, 10, rope)
    # The body: a tall bale with vertical strands, lit upper-left, shaded lower-right.
    raster.oval(px, 16, 26, 8, 10, straw)
    raster.oval(px, 13, 22, 4, 5, straw_hi)
    raster.oval(px, 19, 30, 4, 5, straw_dk)
    for x in range(10, 23, 3):
        raster.line(px, x, 18, x + 1, 34, straw_dk)
    raster.dither_where(px, straw, straw_hi, 3)
    raster.rect(px, 8, 18, 25, 19, rope)
    raster.rect(px, 8, 31, 25, 32, rope)
    # A painted target RING with a centre dot (a filled mark of this size read as a red cross).
    raster.oval(px, 16, 25, 3.6, 3.6, mark)
    raster.oval(px, 16, 25, 2.2, 2.2, straw)
    raster.put(px, 16, 25, mark)
    raster.outline(px, INK)
    _save(root, "assets/sprites/characters/training_dummy.png", px)


# --- static props and emblems (ported unchanged from the D-029/Phase-06 generator) ----------

def gen_rock(root):
    w, h = 16, 16
    px = raster.blank(w, h)
    stone = (120, 122, 130, 255)
    raster.oval(px, 8, 10, 7, 5, stone)
    raster.oval(px, 6, 8, 3, 2, raster.shade(stone, 1.25))
    raster.oval(px, 11, 12, 3, 2, raster.shade(stone, 0.72))
    for (x, y) in [(4, 7), (10, 6), (13, 10)]:
        px[y][x] = (72, 120, 64, 255)
    _save(root, "assets/sprites/props/prop_rock.png", px)


def gen_planter(root):
    w, h = 16, 16
    px = raster.blank(w, h)
    pot = (150, 120, 96, 255)
    raster.oval(px, 8, 6, 5, 4, (56, 118, 64, 255))
    raster.oval(px, 6, 5, 2, 2, (86, 150, 84, 255))
    raster.rect(px, 4, 9, 12, 15, pot)
    raster.rect(px, 4, 13, 12, 15, raster.shade(pot, 0.72))
    raster.rect(px, 4, 9, 12, 10, raster.shade(pot, 1.2))
    _save(root, "assets/sprites/props/prop_planter.png", px)


def gen_emblems(root):
    px = raster.blank(16, 16)
    ink = (26, 32, 38, 255)
    jade = (72, 170, 140, 255)
    raster.oval(px, 8, 8, 7, 7, ink)
    raster.oval(px, 8, 8, 6, 6, raster.shade(ink, 1.4))
    raster.oval(px, 6, 7, 2, 2, jade)
    raster.oval(px, 10, 7, 2, 2, jade)
    raster.rect(px, 4, 9, 12, 11, jade)
    raster.rect(px, 6, 6, 7, 7, raster.shade(jade, 1.3))
    raster.rect(px, 9, 6, 10, 7, raster.shade(jade, 1.3))
    _save(root, "assets/sprites/sects/emblem_azure_cloud.png", px)

    px = raster.blank(16, 16)
    ink = (34, 24, 26, 255)
    red = (176, 48, 48, 255)
    gold = (210, 180, 90, 255)
    raster.oval(px, 8, 8, 7, 7, ink)
    raster.oval(px, 8, 8, 6, 6, raster.shade(ink, 1.3))
    raster.rect(px, 6, 9, 10, 13, red)
    raster.oval(px, 8, 10, 3, 4, red)
    raster.rect(px, 7, 5, 9, 10, red)
    raster.rect(px, 7, 5, 8, 8, raster.shade(red, 1.3))
    px[4][8] = gold
    px[5][8] = gold
    _save(root, "assets/sprites/sects/emblem_crimson_flame.png", px)


def gen_prototype_tileset(root):
    """The retired 48x16 prototype strip (D-022). No map references it; kept reproducible."""
    w, h = TILE * 3, TILE
    px = raster.blank(w, h, (0, 0, 0, 255))
    base, light, dark, blade = (58, 110, 60, 255), (84, 146, 82, 255), (44, 88, 50, 255), \
        (108, 170, 98, 255)
    raster.rect(px, 0, 0, TILE, TILE, base)
    for y in range(TILE):
        for x in range(TILE):
            if raster.BAYER4[y % 4][x % 4] < 7:
                px[y][x] = light
    for (x, y) in [(2, 11), (10, 4), (13, 13), (6, 14), (3, 5)]:
        px[y][x] = dark
        if y + 1 < TILE:
            px[y + 1][x] = dark
    for (x, y) in [(4, 9), (8, 6), (12, 10), (6, 12), (10, 13)]:
        px[y][x] = blade
        if y - 1 >= 0:
            px[y - 1][x] = blade
    ox = TILE
    raster.rect(px, ox, 0, ox + TILE, TILE, (182, 158, 118, 255))
    for y in range(TILE):
        for x in range(TILE):
            if raster.BAYER4[y % 4][x % 4] < 6:
                px[y][ox + x] = (206, 184, 146, 255)
    for y in range(TILE):
        for x in range(TILE):
            if x % 8 == 0 or y % 8 == 0:
                px[y][ox + x] = (150, 126, 92, 255)
    for (x, y) in [(3, 3), (11, 5), (5, 11), (13, 12), (6, 6)]:
        px[y][ox + x] = (168, 142, 104, 255)
    ox = TILE * 2
    raster.rect(px, ox, 0, ox + TILE, TILE, (92, 104, 120, 255))
    for y in range(0, TILE, 5):
        raster.rect(px, ox, y, ox + TILE, y + 2, (72, 84, 100, 255))
        if y + 2 < TILE:
            raster.rect(px, ox, y + 2, ox + TILE, y + 3, (52, 60, 74, 255))
    raster.rect(px, ox, 0, ox + TILE, 2, (150, 150, 142, 255))
    raster.rect(px, ox, 2, ox + TILE, 3, (116, 116, 110, 255))
    for y in range(TILE):
        px[y][ox] = (52, 60, 74, 255)
        px[y][ox + TILE - 1] = (52, 60, 74, 255)
    raster.rect(px, ox, TILE - 1, ox + TILE, TILE, (52, 60, 74, 255))
    _save(root, "assets/tiles/prototype/prototype_tileset.png", px)

def gen_cultivation_landmarks(root):
    """The PHYSICAL marks of a vein (Phase 12) — what a mortal sees where qi surfaces. The qi
    itself is a runtime effect gated by perception; these are stone, water and torn earth."""
    stone = (118, 120, 126, 255)
    stone_hi = raster.shade(stone, 1.25)
    stone_dk = raster.shade(stone, 0.7)
    # Lạc Hà spring: a ring of stones around a small clear pool.
    px = raster.blank(32, 20)
    raster.oval(px, 16, 11, 14, 7, stone_dk)
    raster.oval(px, 16, 10, 13, 6, stone)
    raster.oval(px, 16, 11, 10, 4.2, (40, 92, 120, 255))
    raster.oval(px, 14, 10, 6, 2, (70, 140, 168, 255))
    raster.put(px, 12, 9, (200, 236, 240, 255))
    for (x, y) in ((4, 9), (9, 5), (16, 4), (23, 5), (28, 9), (25, 15), (8, 15), (16, 17)):
        raster.oval(px, x, y, 2, 1.6, stone_hi)
    raster.outline(px, INK)
    _save(root, "assets/sprites/props/prop_spirit_spring.png", px)
    # The vein fissure: torn earth with jade-green crystal glints in the crack.
    px = raster.blank(48, 20)
    earth = (86, 70, 54, 255)
    raster.oval(px, 24, 11, 22, 7, earth)
    raster.oval(px, 24, 10, 20, 5, raster.shade(earth, 1.15))
    crack = [(4, 12), (11, 9), (17, 12), (24, 8), (31, 12), (38, 9), (44, 11)]
    for a, b in zip(crack, crack[1:]):
        raster.line(px, a[0], a[1], b[0], b[1], (24, 20, 18, 255))
        raster.line(px, a[0], a[1] + 1, b[0], b[1] + 1, (36, 30, 26, 255))
    for (x, y) in ((11, 8), (24, 7), (38, 8), (30, 11)):
        raster.put(px, x, y, (110, 210, 170, 255))
        raster.put(px, x, y - 1, (180, 250, 220, 255))
    raster.outline(px, INK)
    _save(root, "assets/sprites/props/prop_vein_fissure.png", px)
    # The Lạc Hà stele: an upright carved stone on a low plinth.
    px = raster.blank(20, 36)
    raster.oval(px, 10, 34, 8, 1.6, (12, 16, 22, 96))
    raster.rect(px, 3, 29, 17, 34, stone_dk)
    raster.rect(px, 3, 29, 17, 30, stone)
    raster.rect(px, 5, 4, 15, 30, stone)
    raster.rect(px, 5, 4, 7, 30, stone_hi)
    raster.oval(px, 10, 5, 5, 3, stone)
    for y in range(9, 27, 3):
        raster.rect(px, 9, y, 13, y + 1, stone_dk)       # carved lines of text
    raster.rect(px, 8, 6, 14, 7, (150, 128, 80, 255))   # a weathered gilt heading
    raster.outline(px, INK)
    _save(root, "assets/sprites/props/prop_stele.png", px)
