"""The PRE-MODEL design sheet (D-062 CP1/CP3): the canonical cultivator projected from the same
geometry the Blender model is built from (`model/humanoid.py`), so the proportions reviewed here
are the proportions that ship.

A tiny software projector (painter's algorithm, banded Lambert with the actor's own ramps and
the style's canonical key light) — enough to judge silhouette, proportion, layering and palette
BEFORE modeling; the real render is Blender's job.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFont

import humanoid

LIGHT = None


def _font(size):
    for path in ("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def _light_dir(spec):
    lt = spec["style"]["lighting"]
    el = math.radians(lt["key_elevation_deg"])
    # key from the upper LEFT of the screen and slightly toward the viewer
    v = (-math.cos(el) * 0.78, -math.cos(el) * 0.62, math.sin(el))
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def _project(parts, yaw_deg, elev_deg):
    yaw = math.radians(yaw_deg)
    el = math.radians(elev_deg)
    cy, sy = math.cos(yaw), math.sin(yaw)
    f = (0.0, math.cos(el), -math.sin(el))
    u = (0.0, math.sin(el), math.cos(el))
    polys = []
    for part in parts:
        verts = [(x * cy - y * sy, x * sy + y * cy, z) for x, y, z in part["verts"]]
        for face in part["faces"]:
            pts = [verts[i] for i in face]
            a, b, c = pts[0], pts[1], pts[2]
            e1 = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            e2 = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
            n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2],
                 e1[0] * e2[1] - e1[1] * e2[0])
            ln = math.sqrt(sum(k * k for k in n)) or 1.0
            n = tuple(k / ln for k in n)
            depth = sum(sum(p[k] * f[k] for k in range(3)) for p in pts) / len(pts)
            scr = [(p[0], sum(p[k] * u[k] for k in range(3))) for p in pts]
            polys.append((depth, scr, n, part["material"], f))
    polys.sort(key=lambda p: -p[0])
    return polys


def _shade(spec, mat, n, f, light):
    mats = spec["materials"]
    facing = -(n[0] * f[0] + n[1] * f[1] + n[2] * f[2])
    if facing < 0:
        n = (-n[0], -n[1], -n[2])
        if mat == "robe" and "robe_inner" in mats:
            mat = "robe_inner"
    m = mats.get(mat)
    if m is None:
        return (255, 0, 255)
    b = max(0.0, n[0] * light[0] + n[1] * light[1] + n[2] * light[2]) * 0.85 + 0.15
    ramp = m["ramp"]
    if b < 0.3:
        return tuple(ramp[0])
    if b < 0.55:
        return tuple(ramp[1])
    if b < 0.9 or not m["highlight"]:
        return tuple(ramp[2])
    return tuple(ramp[3])


def _draw_view(img, spec, parts, origin, scale, yaw, elev, light):
    draw = ImageDraw.Draw(img)
    ox, oy = origin
    for depth, scr, n, mat, f in _project(parts, yaw, elev):
        col = _shade(spec, mat, n, f, light)
        draw.polygon([(ox + x * scale, oy - y * scale) for x, y in scr], fill=col + (255,))


def render(spec, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    parts = humanoid.build(spec)
    light = _light_dir(spec)
    W, H = 1700, 1060
    bg = (15, 20, 28, 255)
    img = Image.new("RGBA", (W, H), bg)
    d = ImageDraw.Draw(img)
    title, body, small = _font(30), _font(17), _font(14)
    paper = (230, 217, 191)
    gold = (201, 168, 101)
    muted = (158, 168, 184)
    d.text((40, 26), "AETHERIA — CANONICAL CULTIVATOR · design sheet (pre-model)", font=title,
           fill=paper)
    d.text((40, 66), "actor: %s — %s · geometry: model/humanoid.py · 1 unit = 1 px before "
           "foreshortening" % (spec["id"], spec["role"]), font=small, fill=muted)
    scale = 8.5
    base_y = 940
    views = [("FRONT", 0, 0), ("SIDE (facing left)", 90, 0), ("BACK", 180, 0),
             ("GAMEPLAY 30°", 0, spec["camera"]["gameplay"]["elevation_deg"])]
    for i, (name, yaw, elev) in enumerate(views):
        cx = 170 + i * 300
        _draw_view(img, spec, parts, (cx, base_y), scale, yaw, elev, light)
        d.text((cx - 70, 110), name, font=body, fill=gold)
        d.line([(cx - 110, base_y), (cx + 110, base_y)], fill=(70, 80, 96), width=1)
    # Proportion guides on the FRONT view
    b = spec["body"]
    hz = b["head_centre"][2]
    top = hz + b["head_radii"][2]
    chin = hz - b["head_radii"][2]
    for z, label in ((top, "head top %.1f" % top), (chin, "chin %.1f" % chin),
                     (b["shoulder"], "shoulder"), (b["waist"], "waist / sash"),
                     (b["knee"], "knee"), (0.0, "sole")):
        y = base_y - z * scale
        d.line([(40, y), (300, y)], fill=(60, 70, 86), width=1)
        d.text((44, y - 16), label, font=small, fill=muted)
    total = top + spec["hair"]["bun"]["radius"] * 1.6 if spec["hair"].get("bun") else top
    d.text((40, 980), "standing height %.1f u · head %.1f u (1/%.2f) · shoulders %.1f u · hem "
           "%.1f u" % (total, top - chin, total / (top - chin), 2 * b["shoulder_x"] + 2.5,
                       2 * spec["garment"]["skirt"][-1][2]), font=small, fill=muted)
    # Gameplay cell preview: the GAMEPLAY view at 1 px/unit, upscaled x6, inside a 32x48 grid.
    cell = Image.new("RGBA", (32 * 8, 48 * 8), (0, 0, 0, 0))
    _draw_view(cell, spec, parts, (16 * 8, 46.5 * 8), 8, 0,
               spec["camera"]["gameplay"]["elevation_deg"], light)
    small_cell = cell.resize((32, 48), Image.BOX).resize((32 * 6, 48 * 6), Image.NEAREST)
    gx, gy = 1250, 120
    d.rectangle([gx - 1, gy - 1, gx + 32 * 6, gy + 48 * 6], outline=(70, 80, 96))
    img.alpha_composite(small_cell, (gx, gy))
    d.text((gx, gy + 48 * 6 + 8), "32×48 cell at 1 px/unit (naive box\nreduction — the "
           "pixel adapter does better)", font=small, fill=muted)
    # Palette ramps
    py = 520
    d.text((1250, py - 34), "MATERIAL RAMPS  deep · shadow · base · light", font=body, fill=gold)
    for i, (name, m) in enumerate(sorted(spec["materials"].items(), key=lambda kv: kv[1]["id"])):
        y = py + i * 34
        for k, c in enumerate(m["ramp"]):
            d.rectangle([1250 + k * 34, y, 1250 + k * 34 + 30, y + 26], fill=tuple(c) + (255,))
        d.text((1250 + 4 * 34 + 10, y + 4), "%s%s" % (name, "  (hi)" if m["highlight"] else ""),
               font=small, fill=paper)
    path = os.path.join(out_dir, "design_sheet.png")
    img.save(path)
    return path
