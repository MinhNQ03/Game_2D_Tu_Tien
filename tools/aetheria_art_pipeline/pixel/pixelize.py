"""The pixel adapter: Blender's controlled passes -> 32x48 Aetheria sprite cells (D-062 CP8).

    BLENDER -> controlled render (1-sample ID / light / depth at 4x) -> rasterization (a
    weighted material vote per 4x4 block) -> palette (the actor's own 4-tone ramp per material,
    banded on the light pass) -> pixel-cluster correction (orphans, tone speckle) -> inner
    contours (depth breaks) -> despeckle (8-neighbour isolation) -> ink outline (opaque neighbours only) -> contact shadow -> anchor
    (projected bones, feet-relative, pixel centres) -> sheet -> validator.

NOT resize-and-pixelate: no colour in a sprite is an average of two others. Every opaque pixel
is exactly one of the actor's ramp tones or the style's ink.
"""
import json
import math
import os
import sys

from PIL import Image

PIPE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(PIPE, "style"))
sys.path.insert(0, os.path.join(os.path.dirname(PIPE), ""))

import style  # noqa: E402

DIRECTIONS = ("down", "up", "left", "right")
LINING = {"robe": "robe_inner"}          # a back-face of the outer robe shows its lining
PROTECTED_PRIORITY = 2.0                 # materials this precious survive any cleanup
DEPTH_BREAK = 0.035                      # depth-pass units (~2.8 world units) for an inner contour


def _decode(v):
    return style.srgb_to_linear(v)


class Passes:
    """The three 1-sample passes of one frame, as flat lists."""

    def __init__(self, frames_dir, stem):
        self.id = Image.open(os.path.join(frames_dir, stem + "_id.png")).convert("RGBA")
        self.light = Image.open(os.path.join(frames_dir, stem + "_light.png")).convert("RGBA")
        self.depth = Image.open(os.path.join(frames_dir, stem + "_depth.png")).convert("RGBA")
        self.w, self.h = self.id.size
        self.idd = list(self.id.getdata())
        self.ld = list(self.light.getdata())
        self.dd = list(self.depth.getdata())


def _materials_by_id(spec):
    return {m["id"]: (name, m) for name, m in spec["materials"].items()}


def _tone(light, bands, highlight):
    if light < bands[0]:
        return 0
    if light < bands[1]:
        return 1
    if light < bands[2] or not highlight:
        return 2
    return 3


def rasterize(spec, passes, k, portrait=False):
    """Weighted material vote per k x k block. Returns a grid of (material, tone, depth) or
    None (transparent)."""
    mats = _materials_by_id(spec)
    bands = spec["style"]["pixel"]["light_bands"]
    alpha_t = spec["style"]["pixel"]["alpha_threshold"]
    W, H = passes.w // k, passes.h // k
    grid = [[None] * W for _ in range(H)]
    for oy in range(H):
        for ox in range(W):
            counts, light_sum, depth_sum, back = {}, {}, {}, {}
            covered = 0
            for sy in range(k):
                row = (oy * k + sy) * passes.w + ox * k
                for sx in range(k):
                    i = row + sx
                    r, g, b, a = passes.idd[i]
                    if a < 128:
                        continue
                    mid = int(round(r / 20.0))
                    if mid not in mats:
                        continue        # transparent, or a prop's shadow-catching ground
                    covered += 1
                    counts[mid] = counts.get(mid, 0) + 1
                    light_sum[mid] = light_sum.get(mid, 0.0) + _decode(passes.ld[i][0])
                    depth_sum[mid] = depth_sum.get(mid, 0.0) + _decode(passes.dd[i][0])
                    back[mid] = back.get(mid, 0) + (1 if g > 127 else 0)
            if not counts:
                continue
            # A precious material below its coverage floor does not compete: one eye sample
            # bleeding into the next block must not paint a second eye pixel.
            eligible = [mid for mid in counts
                        if counts[mid] >= mats[mid][1].get("min_coverage", 2)
                        or mats[mid][1]["priority"] < PROTECTED_PRIORITY]
            if not eligible:
                eligible = list(counts)
                eligible = [max(eligible, key=lambda mid: counts[mid])]
                if mats[eligible[0]][1]["priority"] >= PROTECTED_PRIORITY:
                    continue
            best = max(eligible, key=lambda m: (counts[m] * mats[m][1]["priority"], counts[m]))
            name, m = mats[best]
            precious = m["priority"] >= PROTECTED_PRIORITY and counts[best] >= \
                m.get("min_coverage", 2)
            if covered < k * k * alpha_t and not precious:
                continue
            if back[best] * 2 > counts[best] and name in LINING and \
                    LINING[name] in spec["materials"]:
                name = LINING[name]
                m = spec["materials"][name]
            light = light_sum[best] / counts[best]
            tone = _tone(light, bands, m["highlight"])
            if m.get("flat"):
                # A flat accent is ONE tone, dropping to its shadow only where the form turns
                # fully away from the light: a two-tone 2px sash alternates into noise.
                tone = 1 if tone == 0 else 2
            if not portrait:
                # min_tone is a SPRITE rule (a 1px shadow on a 6px face reads as a beard); at
                # portrait scale the face takes its whole ramp and reads as form
                tone = max(tone, m.get("min_tone", 0))
            grid[oy][ox] = [name, tone, depth_sum[best] / counts[best]]
    return grid


def _neigh(grid, x, y):
    H, W = len(grid), len(grid[0])
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < W and 0 <= ny < H:
            yield grid[ny][nx]
        else:
            yield None


def clean(spec, grid):
    """Pixel-cluster correction: a pixel no 4-neighbour shares (material AND tone) is speckle —
    it takes the tone of its own material's neighbours, or failing that the majority neighbour.
    Precious materials (eyes, pins, jade) are exempt: they are meant to be single pixels."""
    mats = spec["materials"]
    H, W = len(grid), len(grid[0])
    out = [[None if c is None else list(c) for c in row] for row in grid]
    for y in range(H):
        for x in range(W):
            c = grid[y][x]
            if c is None or mats[c[0]]["priority"] >= PROTECTED_PRIORITY:
                continue
            ns = [n for n in _neigh(grid, x, y) if n is not None]
            if any(n[0] == c[0] and n[1] == c[1] for n in ns):
                continue
            same_mat = [n for n in ns if n[0] == c[0]]
            if same_mat:
                tones = [n[1] for n in same_mat]
                out[y][x][1] = max(set(tones), key=tones.count)
            elif len(ns) >= 3:
                keys = [(n[0], n[1]) for n in ns]
                mat, tone = max(set(keys), key=keys.count)
                out[y][x][0], out[y][x][1] = mat, tone
    return out


def inner_contours(spec, grid):
    """Where a surface passes BEHIND another (a depth break), its pixel on the far side darkens
    to its own deepest tone: the arm over the robe, the lock over the chest read as layers."""
    mats = spec["materials"]
    H, W = len(grid), len(grid[0])
    out = [[None if c is None else list(c) for c in row] for row in grid]
    for y in range(H):
        for x in range(W):
            c = grid[y][x]
            if c is None or mats[c[0]]["priority"] >= PROTECTED_PRIORITY or \
                    mats[c[0]].get("flat"):
                continue
            for n in _neigh(grid, x, y):
                if n is not None and n[0] != c[0] and n[2] - c[2] > DEPTH_BREAK:
                    out[y][x][1] = min(out[y][x][1], 0 if c[1] <= 1 else 1)
                    break
    return out


def despeckle(spec, grid):
    """The last cluster pass, AFTER the inner contours: a pixel whose (material, tone) none of
    its 8 neighbours shares is speckle the eye reads as dirt — it takes the most common
    (material, tone) around it. 8 neighbours, so a diagonal 1px line (a collar, a contour)
    is a run and survives. Precious materials (eyes, pins, jade) are meant to be single."""
    mats = spec["materials"]
    H, W = len(grid), len(grid[0])
    out = [[None if c is None else list(c) for c in row] for row in grid]
    for y in range(H):
        for x in range(W):
            c = grid[y][x]
            if c is None or mats[c[0]]["priority"] >= PROTECTED_PRIORITY:
                continue
            ns = [grid[y + dy][x + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                  if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H
                  and grid[y + dy][x + dx] is not None]
            if len(ns) < 5 or any(n[0] == c[0] and n[1] == c[1] for n in ns):
                continue
            keys = [(n[0], n[1]) for n in ns
                    if mats[n[0]]["priority"] < PROTECTED_PRIORITY]
            if keys:
                out[y][x][0], out[y][x][1] = max(set(keys), key=keys.count)
    return out


def to_image(spec, grid, shadow_centre=None, shadow_radii=None):
    mats = spec["materials"]
    ink = tuple(spec["style"]["ink"]) + (255,)
    H, W = len(grid), len(grid[0])
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            c = grid[y][x]
            if c is not None:
                px[x, y] = tuple(mats[c[0]]["ramp"][c[1]]) + (255,)
    # ink outline: transparent pixels touching an opaque one (never diagonals, never glow)
    edge = []
    for y in range(H):
        for x in range(W):
            if px[x, y][3] != 0:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and px[nx, ny][3] == 255:
                    edge.append((x, y))
                    break
    for x, y in edge:
        px[x, y] = ink
    if shadow_centre is None:
        return img
    # contact shadow: translucent, under the figure, never outlined
    cs = spec["style"]["contact_shadow"]
    sh = tuple(cs["rgb"]) + (int(round(cs["alpha"] * 255)),)
    cx, cy = shadow_centre
    rx, ry = shadow_radii
    for y in range(H):
        for x in range(W):
            if px[x, y][3] != 0:
                continue
            dx = (x + 0.5 - cx) / rx
            dy = (y + 0.5 - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                px[x, y] = sh
    return img


def cell(spec, frames_dir, stem, root_x=0.0, seated=False):
    k = spec["camera"]["gameplay"]["render_scale"]
    passes = Passes(frames_dir, stem)
    grid = rasterize(spec, passes, k)
    grid = clean(spec, grid)
    grid = despeckle(spec, inner_contours(spec, grid))
    cw, ch = spec["camera"]["gameplay"]["cell"]
    feet = spec["camera"]["gameplay"]["feet_row"]
    radii = (8.5, 2.2) if seated else (6.5, 1.8)
    return to_image(spec, grid, (cw / 2.0 + root_x, feet), radii)


def portrait(spec, frames_dir):
    """The HUD portrait: the SAME model, materials and ramps as the sprite, framed head and
    shoulders by the portrait camera (designs/cultivator.yaml camera.portrait) and adapted by
    the same vote / palette / cleanup / outline. A portrait can never disagree with the figure
    walking the map (the painted portrait it replaces had dark hair over a white-haired
    sprite)."""
    k = spec["camera"]["portrait"]["render_scale"]
    grid = rasterize(spec, Passes(frames_dir, "portrait"), k, portrait=True)
    grid = despeckle(spec, inner_contours(spec, clean(spec, grid)))
    return to_image(spec, grid)


def _rows(im):
    """A PIL cell as the row-major tuple grid `aetheria_art.sheet` verifies."""
    w, h = im.size
    data = list(im.getdata())
    return [data[y * w:(y + 1) * w] for y in range(h)]


def _assemble(cells):
    cw, ch = cells[0][0].size
    sheet = Image.new("RGBA", (cw * len(cells[0]), ch * len(cells)), (0, 0, 0, 0))
    for r, row in enumerate(cells):
        for c, im in enumerate(row):
            sheet.paste(im, (c * cw, r * ch))
    return sheet


def build_actor(spec, work_dir, root):
    """Every animation sheet + the anchor resource for one actor."""
    sys.path.insert(0, os.path.join(root, "tools"))
    from aetheria_art import sheet as legacy_sheet
    sys.path.insert(0, os.path.join(PIPE, "model"))
    import motion
    frames_dir = os.path.join(work_dir, "frames")
    with open(os.path.join(frames_dir, "anchors.json")) as f:
        projected = json.load(f)
    out = spec["outputs"]
    cw, ch = spec["camera"]["gameplay"]["cell"]
    anchors = {}
    written = []
    for anim, info in spec["animations"].items():
        cells = []
        for d in DIRECTIONS:
            row = []
            for fr in range(info["frames"]):
                pose = motion.ANIMATIONS[anim](spec, fr)
                rx = pose["root"][0] if d in ("down", "up") else 0.0
                if d == "up":
                    rx = -rx
                row.append(cell(spec, frames_dir, "%s_%s_%d" % (anim, d, fr), rx,
                                seated=(anim == "meditate")))
            cells.append(row)
        # THE VALIDATOR: adjacent frames must differ and facings must differ, or the runtime
        # would animate an index over a motionless figure (L-029). It FAILS the build.
        legacy_sheet.verify_animates("%s/%s" % (spec["id"], anim),
                                     [[_rows(im) for im in row] for row in cells],
                                     loops=info.get("loops", True))
        sheet_img = _assemble(cells)
        rel = "assets/sprites/characters/%s_%s.png" % (out["sheet_prefix"], anim)
        sheet_img.save(os.path.join(root, rel))
        written.append(rel)
        anchors[anim] = {}
        for point, per_dir in projected[anim].items():
            anchors[anim][point] = [[(int(math.floor(x)), int(math.floor(y))) for x, y in frames]
                                    for frames in per_dir]
    if out.get("portrait"):
        rel = "assets/sprites/characters/portraits/%s.png" % out["portrait"]
        portrait(spec, frames_dir).save(os.path.join(root, rel))
        written.append(rel)
    if out.get("fallback"):
        # The static frame a scene shows before its profile binds: the idle sheet's first DOWN
        # frame, the same pixels, so the two can never disagree.
        rel = "assets/sprites/characters/%s.png" % out["fallback"]
        cell(spec, frames_dir, "idle_down_0").save(os.path.join(root, rel))
        written.append(rel)
    path = os.path.join(root, "data/characters/visual/anchors/%s.tres" % out["anchors"])
    legacy_sheet.write_anchor_resource(path, "anchors_" + spec["id"], (cw, ch), anchors,
                                       feet_row=spec["camera"]["gameplay"]["feet_row"])
    written.append(os.path.relpath(path, root))
    _check_profile(spec, root)
    for w in written:
        print("wrote", w)
    return written


def _check_profile(spec, root):
    """The runtime profile must stand the sprite where the sheet stands its feet: its
    anchor_offset.y is exactly cell height - feet_row. A mismatch floats or sinks the figure
    and every anchor with it, so it FAILS the build instead of shipping."""
    name = spec["outputs"].get("profile")
    if not name:
        return
    cw, ch = spec["camera"]["gameplay"]["cell"]
    want = "anchor_offset = Vector2(0, %g)" % (ch - spec["camera"]["gameplay"]["feet_row"])
    path = os.path.join(root, "data/characters/visual/%s.tres" % name)
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if want not in text:
        raise SystemExit("PROFILE MISMATCH: %s must declare `%s`" % (path, want))


def icon(spec, frames_dir, icon_id, k, cell, shadow=True):
    """One icon from its passes: the character adapter, then a small contact shadow for an
    object resting on the ground (a sigil floats: no shadow; a WORLD icon gets its shadow from
    the pickup, not baked in)."""
    grid = rasterize(spec, Passes(frames_dir, icon_id), k)
    grid = despeckle(spec, inner_contours(spec, clean(spec, grid)))
    if spec["kind"].startswith("sigil") or not shadow:
        return to_image(spec, grid)
    # the shadow under the object's lowest opaque row: an object rests ON it
    rows = [y for y, row in enumerate(grid) if any(c is not None for c in row)]
    base = (rows[-1] + 0.5) if rows else cell[1] * 0.8
    return to_image(spec, grid, (cell[0] / 2.0, base), (cell[0] * 0.40, 1.6))


def build_icons(icon_spec, frames_dir, root):
    """Every icon in designs/icons.yaml -> assets/sprites/items/<id>.png (the paths the data
    already references)."""
    k = icon_spec["render_scale"]
    cell = icon_spec["cell"]
    written = []
    for icon_id, spec in icon_spec["icons"].items():
        img = icon(spec, frames_dir, icon_id, k, cell)
        rel = "assets/sprites/items/%s.png" % icon_id
        img.save(os.path.join(root, rel))
        written.append(rel)
        world = icon_spec.get("world_cell")
        if world and os.path.exists(os.path.join(frames_dir, icon_id + "_w_id.png")):
            os.makedirs(os.path.join(root, "assets/sprites/items/world"), exist_ok=True)
            rel = "assets/sprites/items/world/%s.png" % icon_id
            icon(spec, frames_dir, icon_id + "_w", k, world, shadow=False).save(
                os.path.join(root, rel))
            written.append(rel)
    return written


def cast_shadow(passes, k, ground_id, lit_fraction=0.62):
    """Where the ground plane is SHADOWED: per output pixel, True when most of its samples are
    ground and their light falls below `lit_fraction` of the ground's fully-lit level. The
    shadow a house or a tree throws, measured from the canonical light — never painted."""
    W, H = passes.w // k, passes.h // k
    ground_light = []
    for i, (r, g, b, a) in enumerate(passes.idd):
        if a >= 128 and int(round(r / 20.0)) == ground_id:
            ground_light.append(_decode(passes.ld[i][0]))
    if not ground_light:
        return [[False] * W for _ in range(H)]
    ground_light.sort()
    lit = ground_light[int(len(ground_light) * 0.9)]
    out = [[False] * W for _ in range(H)]
    for oy in range(H):
        for ox in range(W):
            n = dark = 0
            for sy in range(k):
                row = (oy * k + sy) * passes.w + ox * k
                for sx in range(k):
                    r, g, b, a = passes.idd[row + sx]
                    if a >= 128 and int(round(r / 20.0)) == ground_id:
                        n += 1
                        if _decode(passes.ld[row + sx][0]) < lit * lit_fraction:
                            dark += 1
            out[oy][ox] = n * 2 > k * k and dark * 2 > n
    return out


def prop_image(spec, frames_dir, prop_id, k, ground_id):
    """A world prop: the character adapter for the object, its ink outline, then the CAST
    shadow under it in the style's contact-shadow colour (never outlined, never over the
    object)."""
    passes = Passes(frames_dir, prop_id)
    grid = rasterize(spec, passes, k)
    grid = despeckle(spec, inner_contours(spec, clean(spec, grid)))
    img = to_image(spec, grid)
    shadow = cast_shadow(passes, k, ground_id)
    cs = spec["style"]["contact_shadow"]
    tone = tuple(cs["rgb"]) + (int(round(cs["alpha"] * 255)),)
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y][3] == 0 and shadow[y][x]:
                px[x, y] = tone
    return img


def build_props(prop_spec, frames_dir, root):
    """Every prop -> assets/sprites/props/world/<id>.png (cropped to its pixels) and
    data/world/props/<id>.tres (PropData: the texture, the origin, the collision footprint)."""
    k = prop_spec["render_scale"]
    written = []
    os.makedirs(os.path.join(root, "assets/sprites/props/world"), exist_ok=True)
    os.makedirs(os.path.join(root, "data/world/props"), exist_ok=True)
    for prop_id, spec in prop_spec["props"].items():
        with open(os.path.join(frames_dir, prop_id + ".json")) as f:
            meta = json.load(f)
        img = prop_image(spec, frames_dir, prop_id, k, prop_spec["ground_id"])
        bbox = img.getbbox()
        img = img.crop(bbox)
        ox, oy = meta["origin"][0] - bbox[0], meta["origin"][1] - bbox[1]
        tex_rel = "assets/sprites/props/world/%s.png" % prop_id
        img.save(os.path.join(root, tex_rel))
        foot = _footprint(spec, meta)
        tres_rel = "data/world/props/%s.tres" % prop_id
        with open(os.path.join(root, tres_rel), "w", encoding="utf-8") as f:
            f.write(
                '[gd_resource type="Resource" script_class="PropData" load_steps=3 format=3]\n\n'
                '[ext_resource type="Script" path="res://src/data/world/prop_data.gd" '
                'id="1_prop"]\n'
                '[ext_resource type="Texture2D" path="res://%s" id="2_tex"]\n\n'
                "[resource]\n"
                'script = ExtResource("1_prop")\n'
                'id = &"%s"\n'
                'texture = ExtResource("2_tex")\n'
                "origin = Vector2(%d, %d)\n"
                "footprint = Rect2(%g, %g, %g, %g)\n"
                "sways = %s\n" % (tex_rel, prop_id, round(ox), round(oy), foot[0], foot[1],
                                   foot[2], foot[3], "true" if spec["kind"] == "broadleaf_tree"
                                   else "false"))
        written += [tex_rel, tres_rel]
    return written


def _footprint(spec, meta):
    """The prop's SOLID base in world px, relative to its origin (the front base centre). The
    ground's depth is foreshortened by the camera (sin of the elevation)."""
    ppu = meta["px_per_unit"]
    squash = meta["ground_squash"]
    p = spec.get("params", {})
    kind = spec["kind"]
    if kind == "dwelling":
        w, d = p.get("w", 150.0) + 8, p.get("d", 96.0) + 8
    elif kind == "outpost_hall":
        w, d = p.get("w", 200.0) + 28, p.get("d", 120.0) + 34
    elif kind == "broadleaf_tree":
        w, d = 16.0 * p.get("scale", 1.0), 12.0 * p.get("scale", 1.0)
        return (-w * ppu / 2, -d * ppu * squash / 2, w * ppu, d * ppu * squash)
    elif kind == "fence":
        w, d = p.get("length", 150.0), 6.0
        return (-w * ppu / 2, -d * ppu * squash / 2, w * ppu, d * ppu * squash)
    elif kind == "well":
        w, d = 44.0, 40.0
    elif kind == "weapon_rack":
        w, d = 64.0, 8.0
    else:
        return (0, 0, 0, 0)
    return (-w * ppu / 2, -d * ppu * squash, w * ppu, d * ppu * squash)
