#!/usr/bin/env python3
"""The ground painter (D-062 CP10): a map's floor painted from its LAYOUT DATA in the Visual DNA.

    python3 tools/aetheria_art_pipeline/world/ground.py lac_ha
        -> assets/maps/<id>_ground.png              the floor, 1 art px = 1 world px
        -> data/maps/ground/<id>_ground.tres        GroundLayoutData: fill rect, flooded cells,
                                                    water blockers (what the game reads)

Why painted, not tiled: a floor stamped from one 16px tile repeats on a 16px grid and reads as
"flat tile field + decorative stickers" (D-062 §24). Painting it from shapes gives organic
edges between materials, material-aware surfaces (flagstones with mortar and a lit bevel,
packed earth under the grass's shadow line, water that deepens away from its bank, terraced
paddies with bunds), and composition — paths that lead somewhere — with ONE pixel density.

Deterministic: every noise field comes from a coordinate hash (never `random`), so the same
layout paints the same bytes. Standard library + PIL only (no numpy).
"""
import math
import os
import sys

import yaml
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(PIPE))
sys.path.insert(0, os.path.join(PIPE, "style"))
sys.path.insert(0, os.path.join(PIPE, "pixel"))

import pngout  # noqa: E402
import style  # noqa: E402

ST = style.load()

# Material codes (the order is the paint priority when two shapes overlap: later wins).
GRASS, STONE, STONE_DARK, EARTH, YARD, WATER, BRIDGE, PADDY, BUND, FOREST, LITTER, \
    FISSURE, ROCK = range(13)
KINDS = {"grass": GRASS, "stone": STONE, "stone_dark": STONE_DARK, "earth": EARTH,
         "yard": YARD, "water": WATER, "bridge": BRIDGE, "paddy": PADDY, "forest": FOREST,
         "litter": LITTER, "fissure": FISSURE, "rock": ROCK}
ROUGH = {EARTH: 2.2, YARD: 2.5, WATER: 2.0, STONE: 0.0, STONE_DARK: 0.0, BRIDGE: 0.0,
         PADDY: 0.0, FOREST: 3.0, LITTER: 3.2, FISSURE: 1.6, GRASS: 2.5, ROCK: 3.0}

# Ramps [deep, shadow, base, light] — the DNA world roles where one exists, their neighbours
# where the ramp needs a step the palette does not name.
RAMPS = {
    GRASS: [(54, 84, 50), (68, 102, 58), (84, 122, 68), (102, 142, 80), (122, 160, 92)],
    EARTH: [(92, 82, 70), (118, 106, 90), (142, 128, 108), (168, 154, 132)],
    YARD: [(106, 94, 80), (132, 118, 100), (156, 142, 120), (180, 166, 142)],
    STONE: [(100, 102, 110), (124, 126, 133), (146, 148, 154), (168, 170, 175), (190, 191, 195)],
    STONE_DARK: [(72, 74, 82), (88, 90, 99), (104, 107, 116), (122, 125, 133), (140, 143, 150)],
    WATER: [(19, 50, 76), (25, 64, 94), (31, 86, 128), (47, 112, 150), (110, 168, 196)],
    PADDY: [(36, 70, 66), (44, 86, 78), (54, 100, 88), (92, 140, 122)],
    # weathered planks: sun and rain grey the timber (a dark plank hid a fallen body)
    "WOOD": [(92, 76, 60), (118, 98, 76), (142, 120, 92), (166, 144, 112)],
}
# The forest floor: the meadow's family in canopy shade — darker, cooler.
RAMPS[FOREST] = [(48, 74, 50), (58, 88, 58), (70, 104, 66), (84, 120, 74), (100, 136, 84)]
RAMPS[LITTER] = [(70, 62, 48), (90, 80, 60), (110, 98, 72), (132, 118, 86)]
LEAF_FLECKS = [(150, 104, 52), (128, 86, 44), (110, 120, 60)]
# The broken vein: fractured stone with qi seeping along its cracks (aetheria_style §5 "spirit":
# emissive only where it carries force — here, the cracks, one pixel wide).
RAMPS[FISSURE] = [(58, 60, 70), (72, 75, 86), (88, 92, 104), (106, 110, 122)]
QI_CRACK = [(47, 112, 150), (133, 204, 234)]
# Living rock: no laid kerb, moss in its cracks, lit on the faces that turn to the key light.
RAMPS[ROCK] = [(70, 72, 78), (88, 90, 96), (108, 110, 116), (128, 130, 135)]
MORTAR = (70, 72, 80)
WET_BANK = (60, 54, 46)
RICE = [(62, 110, 52), (86, 138, 62), (112, 160, 76)]
FLOWERS = [(232, 224, 168), (214, 198, 230), (236, 236, 228)]


def _hash(x, y, seed):
    h = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def noise(w, h, scale, seed):
    """Smooth value noise in [0,1] as a flat list: a hashed lattice upsampled bicubically."""
    gw, gh = w // scale + 3, h // scale + 3
    lattice = Image.new("L", (gw, gh))
    lattice.putdata([int(255 * _hash(x, y, seed)) for y in range(gh) for x in range(gw)])
    big = lattice.resize((gw * scale, gh * scale), Image.BICUBIC).crop((scale, scale,
                                                                         scale + w, scale + h))
    return [v / 255.0 for v in big.getdata()]


def _mask(w, h, ox, oy, shape, roughen=0.0, seed=0):
    """A shape as a 0/1 list, its edge optionally roughened (blur + noise + threshold) so two
    materials meet in an organic line instead of a ruler edge."""
    m = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(m)
    if "poly" in shape:
        d.polygon([(x - ox, y - oy) for x, y in shape["poly"]], fill=255)
    elif "rect" in shape:
        x, y, rw, rh = shape["rect"]
        d.rectangle([x - ox, y - oy, x - ox + rw - 1, y - oy + rh - 1], fill=255)
    elif "path" in shape:
        pts = [(x - ox, y - oy) for x, y in shape["path"]]
        r = shape["width"] / 2.0
        d.line(pts, fill=255, width=int(shape["width"]), joint="curve")
        for x, y in pts:
            d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    if roughen <= 0:
        return [1 if v > 127 else 0 for v in m.getdata()]
    soft = list(m.filter(ImageFilter.GaussianBlur(roughen)).getdata())
    n = noise(w, h, 5, seed)
    return [1 if (s / 255.0) + (nv - 0.5) * 0.55 > 0.5 else 0 for s, nv in zip(soft, n)]


def _distance_inside(mask, w, h, radius):
    """Approximate depth INSIDE a region (0 at its edge, 1 at >= radius px in), by blurring."""
    m = Image.new("L", (w, h))
    m.putdata([255 if v else 0 for v in mask])
    soft = list(m.filter(ImageFilter.GaussianBlur(radius)).getdata())
    return [max(0.0, min(1.0, (s / 255.0 - 0.5) * 2.0)) if v else 0.0
            for s, v in zip(soft, mask)]


def _tone(ramp, t):
    i = max(0, min(len(ramp) - 1, int(t * len(ramp))))
    return ramp[i]


def _voronoi_stones(w, h, cell_w, cell_h, seed):
    """Irregular flagstones: a jittered grid, nearest/second-nearest feature per pixel. Returns
    (stone id per pixel, mortar flag per pixel)."""
    feats = {}

    def feat(cx, cy):
        key = (cx, cy)
        if key not in feats:
            feats[key] = ((cx + 0.2 + 0.6 * _hash(cx, cy, seed)) * cell_w,
                          (cy + 0.2 + 0.6 * _hash(cx, cy, seed + 1)) * cell_h)
        return feats[key]

    ids, mortar = [0] * (w * h), [False] * (w * h)
    for y in range(h):
        cy = y // cell_h
        for x in range(w):
            cx = x // cell_w
            best = (1e9, None)
            second = 1e9
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    fx, fy = feat(cx + dx, cy + dy)
                    dist = (fx - x) ** 2 * 1.0 + (fy - y) ** 2 * 1.6
                    if dist < best[0]:
                        second = best[0]
                        best = (dist, (cx + dx, cy + dy))
                    elif dist < second:
                        second = dist
            i = y * w + x
            ids[i] = best[1][0] * 7919 + best[1][1]
            mortar[i] = math.sqrt(second) - math.sqrt(best[0]) < 1.25
    return ids, mortar


def paint(layout_path):
    with open(layout_path, encoding="utf-8") as f:
        L = yaml.safe_load(f)
    tile = L["tile"]
    fx, fy, fw, fh = L["fill_rect"]
    ox, oy, w, h = fx * tile, fy * tile, fw * tile, fh * tile
    base = KINDS[L.get("base", "grass")]
    mat = [base] * (w * h)
    region_masks = {}
    for k, shape in enumerate(L["regions"]):
        code = KINDS[shape["kind"]]
        rough = ROUGH[code]
        if code == PADDY:
            # the bund ring first, then the flooded field inside it
            x, y, rw, rh = shape["rect"]
            ring = _mask(w, h, ox, oy, {"rect": [x - 4, y - 4, rw + 8, rh + 8]})
            for i, v in enumerate(ring):
                if v:
                    mat[i] = BUND
        m = _mask(w, h, ox, oy, shape, rough, seed=k + 3)
        for i, v in enumerate(m):
            if v:
                mat[i] = code
        region_masks.setdefault(code, [0] * (w * h))
        rm = region_masks[code]
        for i, v in enumerate(m):
            if v:
                rm[i] = 1

    n_big = noise(w, h, 22, 11)
    n_mid = noise(w, h, 7, 12)
    n_fine = noise(w, h, 3, 13)
    water_depth = _distance_inside([1 if m in (WATER,) else 0 for m in mat], w, h, 6)
    paddy_depth = _distance_inside([1 if m == PADDY else 0 for m in mat], w, h, 3)
    stone_ids, stone_mortar = _voronoi_stones(w, h, 15, 10, 21)

    img = Image.new("RGBA", (w, h))
    px = img.load()

    def at(x, y):
        if 0 <= x < w and 0 <= y < h:
            return mat[y * w + x]
        return GRASS

    for y in range(h):
        for x in range(w):
            i = y * w + x
            m = mat[i]
            wxp, wyp = x + ox, y + oy
            if m == FOREST:
                t = 0.5 + 0.55 * (n_big[i] - 0.5) + 0.35 * (n_mid[i] - 0.5) \
                    + 0.18 * (n_fine[i] - 0.5)
                c = _tone(RAMPS[FOREST], t)
            elif m == LITTER:
                ramp = RAMPS[LITTER]
                t = 0.45 * n_big[i] + 0.4 * n_mid[i] + 0.3 * (n_fine[i] - 0.5) + 0.1
                c = _tone(ramp, t)
                if _hash(wxp, wyp, 91) < 0.05:
                    c = LEAF_FLECKS[int(_hash(wxp, wyp, 93) * 2.99)]   # fallen leaves
                elif at(x, y - 1) in (FOREST, GRASS):
                    c = ramp[0]
            elif m == ROCK:
                ramp = RAMPS[ROCK]
                if stone_mortar[i]:
                    c = RAMPS[FOREST][1] if _hash(wxp, wyp, 101) < 0.5 else RAMPS[ROCK][0]
                else:
                    base_t = 1 + int(_hash(stone_ids[i], 9, 103) * 2.6)
                    c = ramp[max(0, min(3, base_t))]
                    if (y - 1) >= 0 and stone_mortar[i - w]:
                        c = ramp[min(3, base_t + 1)]
                    elif (y + 1) < h and stone_mortar[i + w]:
                        c = ramp[max(0, base_t - 1)]
            elif m == FISSURE:
                ramp = RAMPS[FISSURE]
                if stone_mortar[i]:
                    # a crack: dark in its depth, and along part of it the qi seeping out
                    lit = _hash(stone_ids[i] % 991, 5, 97) < 0.45
                    c = (QI_CRACK[1] if _hash(wxp // 2, wyp // 2, 99) < 0.55 else QI_CRACK[0]) \
                        if lit else MORTAR
                else:
                    base_t = 1 + int(_hash(stone_ids[i], 7, 47) * 2.6)
                    c = ramp[max(0, min(3, base_t))]
                    if (y - 1) >= 0 and stone_mortar[i - w]:
                        c = ramp[min(3, base_t + 1)]
            elif m == GRASS:
                # broad sunlit drifts, a little mid-scale clumping, a whisper of grain: a
                # meadow, not camouflage (the first pass had the contrast of a pattern)
                t = 0.5 + 0.62 * (n_big[i] - 0.5) + 0.38 * (n_mid[i] - 0.5) \
                    + 0.18 * (n_fine[i] - 0.5)
                c = _tone(RAMPS[GRASS], t)
                # the grass's shadow on lower ground just below it is painted on THAT ground;
                # here: a darker blade line where grass meets a raised paving to its south
                if at(x, y + 1) in (STONE, STONE_DARK):
                    c = RAMPS[GRASS][0]
            elif m in (EARTH, YARD):
                ramp = RAMPS[m]
                t = 0.45 * n_big[i] + 0.4 * n_mid[i] + 0.3 * (n_fine[i] - 0.5) + 0.12
                c = _tone(ramp, t)
                if at(x, y - 1) == GRASS or at(x, y - 2) == GRASS:
                    c = ramp[0]          # the turf edge casts its lip of shadow on the path
                elif _hash(wxp, wyp, 31) < 0.012:
                    c = ramp[3]          # a pebble catching the light...
                elif _hash(wxp, wyp - 1, 31) < 0.012:
                    c = ramp[0]          # ...and its shadow below it
            elif m in (STONE, STONE_DARK):
                ramp = RAMPS[m]
                edge = [at(x + 1, y), at(x - 1, y), at(x, y + 1), at(x, y - 1)]
                if any(e not in (STONE, STONE_DARK) for e in edge):
                    # the kerb: paving ends in a laid edge, lit on its far side
                    c = ramp[3] if at(x, y - 1) not in (STONE, STONE_DARK) else ramp[0]
                elif stone_mortar[i]:
                    mossy = _hash(stone_ids[i] % 997, 3, 41) < 0.18 or at(x, y - 3) == GRASS
                    c = RAMPS[GRASS][1] if mossy and _hash(wxp, wyp, 43) < 0.6 else MORTAR
                else:
                    base = 1 + int(_hash(stone_ids[i], 7, 47) * 2.6)     # a tone per stone
                    t = base + (0.6 if n_fine[i] > 0.78 else 0) - (0.6 if n_fine[i] < 0.18 else 0)
                    c = ramp[max(0, min(len(ramp) - 1, int(t)))]
                    up = (y - 1) >= 0 and stone_mortar[i - w]
                    down = (y + 1) < h and stone_mortar[i + w]
                    left = x - 1 >= 0 and stone_mortar[i - 1]
                    if up or left:
                        c = ramp[min(len(ramp) - 1, base + 1)]          # the lit bevel
                    elif down:
                        c = ramp[max(0, base - 1)]                      # the shadowed edge
            elif m == WATER:
                d = water_depth[i]
                ramp = RAMPS[WATER]
                c = ramp[2] if d < 0.25 else (ramp[1] if d < 0.65 else ramp[0])
                if at(x, y - 1) not in (WATER, BRIDGE):
                    c = ramp[4]          # the bright meniscus on the far bank
                elif at(x, y - 2) not in (WATER, BRIDGE):
                    c = ramp[3]
                elif _hash(wxp // 3, wyp, 51) < 0.05 and d > 0.3:
                    c = ramp[3]          # a ripple: a short lit streak along the flow
            elif m == BRIDGE:
                ramp = RAMPS["WOOD"]
                plank = (x // 5)
                c = ramp[1 + int(_hash(plank, 0, 61) * 2.4)]
                if x % 5 == 4:
                    c = ramp[0]          # the gap between planks
                top = at(x, y - 1) != BRIDGE
                bottom = at(x, y + 1) != BRIDGE or at(x, y + 2) != BRIDGE
                if top:
                    c = ramp[3]
                elif bottom:
                    c = ramp[0]
            elif m == PADDY:
                d = paddy_depth[i]
                ramp = RAMPS[PADDY]
                c = ramp[1] if d > 0.5 else ramp[2]
                if at(x, y - 1) == BUND:
                    c = ramp[0]
                # rows of rice: a tuft every 6 px, staggered
                # planted rows: a tuft every 4 px along rows 5 px apart, so the field reads
                # as rice standing in water, not as a teal rectangle
                rx, ry = (x + (2 if (y // 5) % 2 else 0)) % 4, y % 5
                if (rx, ry) in ((1, 1), (2, 1), (1, 2)) and d > 0.15:
                    c = RICE[0] if ry == 2 else RICE[1 + int(_hash(x // 4, y // 5, 67) * 1.9)]
                elif _hash(wxp, wyp, 71) < 0.01:
                    c = ramp[3]          # sky in the water
            elif m == BUND:
                ramp = RAMPS[EARTH]
                below_water = at(x, y + 1) == PADDY
                above_water = at(x, y - 1) == PADDY
                c = ramp[3] if below_water else (ramp[0] if above_water else ramp[2])
                if _hash(wxp, wyp, 73) < 0.25 and not below_water:
                    c = RAMPS[GRASS][2]      # grass on the bund's crown
            # wet earth: one ring of dark bank around open water
            if m in (GRASS, EARTH, FOREST):
                if WATER in (at(x + 1, y), at(x - 1, y), at(x, y + 1), at(x, y - 1)):
                    c = WET_BANK
            px[x, y] = c + (255,)

    # Surface detail on grass, after the base: tufts and the rare flower — clustered by the
    # large noise, so a meadow has drifts and a trodden edge has none.
    for y in range(2, h - 2):
        for x in range(1, w - 1):
            i = y * w + x
            if mat[i] not in (GRASS, FOREST):
                continue
            ramp = RAMPS[mat[i]]
            wxp, wyp = x + ox, y + oy
            hsh = _hash(wxp, wyp, 81)
            if hsh < 0.010 * (0.4 + n_big[i]) and mat[i - 2 * w] == mat[i]:
                px[x, y] = ramp[0] + (255,)
                px[x, y - 1] = ramp[3] + (255,)
                px[x - 1, y - 1] = ramp[4] + (255,)
                px[x + 1, y - 2] = ramp[3] + (255,)
            elif hsh > 0.9994:
                px[x, y] = FLOWERS[int(_hash(wxp, wyp, 83) * 2.99)] + (255,)

    return L, img, mat, (ox, oy, w, h)


def write(layout_id):
    layout_path = os.path.join(PIPE, "designs", "maps", layout_id + ".yaml")
    L, img, mat, (ox, oy, w, h) = paint(layout_path)
    tex_rel = "assets/maps/%s_ground.png" % layout_id
    os.makedirs(os.path.join(ROOT, "assets", "maps"), exist_ok=True)
    pngout.save(img, os.path.join(ROOT, tex_rel))
    tile = L["tile"]
    fx, fy, fw, fh = L["fill_rect"]
    paddy, water = [], []
    for cy in range(fh):
        for cx in range(fw):
            counts = {}
            for yy in range(cy * tile, (cy + 1) * tile):
                for xx in range(cx * tile, (cx + 1) * tile):
                    m = mat[yy * w + xx]
                    counts[m] = counts.get(m, 0) + 1
            half = tile * tile // 2
            paddy.append(1 if counts.get(PADDY, 0) > half else 0)
            water.append(1 if counts.get(WATER, 0) > half else 0)
    blockers = ", ".join("PackedVector2Array(%s)" % ", ".join("%g, %g" % (x, y) for x, y in poly)
                         for poly in L.get("blockers", []))
    tres = (
        '[gd_resource type="Resource" script_class="GroundLayoutData" load_steps=3 format=3]\n\n'
        '[ext_resource type="Script" path="res://src/data/maps/ground_layout_data.gd" '
        'id="1_layout"]\n'
        '[ext_resource type="Texture2D" path="res://%s" id="2_tex"]\n\n'
        "[resource]\n"
        'script = ExtResource("1_layout")\n'
        'id = &"%s"\n'
        'texture = ExtResource("2_tex")\n'
        "fill_rect = Rect2i(%d, %d, %d, %d)\n"
        "tile_px = %d\n"
        "walkway_half_height = %d\n"
        "paddy_cells = PackedByteArray(%s)\n"
        "water_cells = PackedByteArray(%s)\n"
        "materials = PackedStringArray(%s)\n"
        "blockers = [%s]\n"
    ) % (tex_rel, layout_id, fx, fy, fw, fh, tile, L["walkway_half_height"],
         ", ".join(map(str, paddy)), ", ".join(map(str, water)),
         ", ".join('"%s"' % k for k, code in sorted(KINDS.items(), key=lambda kv: kv[1])
                   if code in set(mat)), blockers)
    out_dir = os.path.join(ROOT, "data", "maps", "ground")
    os.makedirs(out_dir, exist_ok=True)
    tres_rel = "data/maps/ground/%s_ground.tres" % layout_id
    with open(os.path.join(ROOT, tres_rel), "w", encoding="utf-8") as f:
        f.write(tres)
    return tex_rel, tres_rel


if __name__ == "__main__":
    for p in write(sys.argv[1] if len(sys.argv) > 1 else "lac_ha"):
        print("wrote", p)
