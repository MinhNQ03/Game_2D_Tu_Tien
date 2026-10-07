#!/usr/bin/env python3
"""The Aetheria INK-LACQUER UI kit (D-062 CP2) — original UI art generated from the Visual DNA.

Every colour is a ROLE from `style/aetheria_style.yaml` (§1 palette, §8 UI grammar); nothing
here is sampled, traced or recoloured from any reference or third-party pack. The look is the
DNA's UI sentence made literal: dark ink-lacquer surfaces with a brushed grain and a one-pixel
bevel, an antique-gold hairline set 3px inside the edge with notched corners, jade for
interaction (hover underline, focus ring), restrained translucency so the world shows through.

Deterministic (a coordinate hash, never `random`): the same DNA writes the same bytes.

    python3 tools/aetheria_art_pipeline/ui/ui_kit.py      -> assets/ui/aetheria_ink/*.png

Pieces and their 9-slice contracts are listed in KIT (the Godot side reads the same numbers
from `UIPalette`; `validate/style_check.py ui-surface` measures them against the DNA).
"""
import math
import os
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(PIPE))
sys.path.insert(0, os.path.join(PIPE, "style"))
sys.path.insert(0, os.path.join(PIPE, "pixel"))

import pngout  # noqa: E402
import style  # noqa: E402

OUT_DIR = os.path.join(ROOT, "assets", "ui", "aetheria_ink")

ST = style.load()


def role(name, alpha=1.0):
    r, g, b = style.role(name, ST)
    return (r, g, b, int(round(alpha * 255)))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))


def shade(c, k):
    """Scale a colour's RGB by k (alpha untouched)."""
    return (min(255, int(c[0] * k)), min(255, int(c[1] * k)), min(255, int(c[2] * k)), c[3])


def _hash(x, y, seed=0):
    h = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


TRANSLUCENCY = ST["ui"]["translucency"]          # [min, max] panel interior alpha
PANEL_ALPHA = (TRANSLUCENCY[0] + TRANSLUCENCY[1]) / 2.0


# --- primitives --------------------------------------------------------------------------------

def _chamfer_inside(x, y, w, h, cut):
    """True inside a rectangle whose four corners are cut diagonally by `cut` px."""
    for cx, cy in ((x, y), (w - 1 - x, y), (x, h - 1 - y), (w - 1 - x, h - 1 - y)):
        if cx + cy < cut:
            return False
    return True


def lacquer(img, x0, y0, x1, y1, top, bottom, alpha, grain=0.035, seed=1):
    """Vertical lacquer gradient with a brushed horizontal grain (rows of 3-6 px streaks)."""
    px = img.load()
    h = max(1, y1 - y0 - 1)
    for y in range(y0, y1):
        t = (y - y0) / h
        base = mix(top, bottom, t)
        for x in range(x0, x1):
            streak = _hash(x // 5, y, seed) - 0.5
            k = 1.0 + grain * streak * 2.0
            c = shade(base, k)
            px[x, y] = (c[0], c[1], c[2], int(round(alpha * 255)))


def plate(w, h, cut=2, top="lacquer_lift", bottom="lacquer_deep", alpha=PANEL_ALPHA,
          ink_alpha=0.92, bevel=True, seed=1):
    """The base of every surface: a chamfered lacquer plate with an ink edge and a bevel."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    lacquer(img, 0, 0, w, h, role(top), role(bottom), alpha, seed=seed)
    px = img.load()
    ink = role("ink", ink_alpha)
    for y in range(h):
        for x in range(w):
            if not _chamfer_inside(x, y, w, h, cut):
                px[x, y] = (0, 0, 0, 0)
            elif not _chamfer_inside(x, y, w, h, cut + 1) or x in (0, w - 1) or y in (0, h - 1):
                px[x, y] = ink
    if bevel:
        edge = role("lacquer_edge", 0.95)
        for x in range(cut + 1, w - cut - 1):
            px[x, 1] = edge                                   # the lit top lip
            px[x, h - 2] = role("lacquer_deep", 0.98)         # the shadowed bottom lip
        for y in range(cut + 1, h - cut - 1):
            px[1, y] = mix(px[1, y], edge, 0.5)               # a half-lit left side
    return img


def hairline(img, inset, colour, light=None, dark=None, notch=2, knots=False):
    """The antique-gold hairline `inset` px inside the edge, its corners NOTCHED inward (a
    stepped corner, the fretwork idiom) instead of a plain right angle. `light` catches the top
    and left runs near the top-left corner (the canonical key light); `dark` the bottom-right."""
    w, h = img.size
    px = img.load()
    x0, y0, x1, y1 = inset, inset, w - 1 - inset, h - 1 - inset
    pts = set()
    for x in range(x0 + notch, x1 - notch + 1):
        pts.add((x, y0))
        pts.add((x, y1))
    for y in range(y0 + notch, y1 - notch + 1):
        pts.add((x0, y))
        pts.add((x1, y))
    # the notch: the line steps in, runs `notch` px, and steps back out
    for cx, cy, sx, sy in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        for i in range(notch + 1):
            pts.add((cx + sx * notch, cy + sy * i))
            pts.add((cx + sx * i, cy + sy * notch))
    for (x, y) in pts:
        c = colour
        if light is not None and (x + y) < (x0 + y0 + min(w, h) * 0.45):
            c = light
        elif dark is not None and (x + y) > (x1 + y1 - min(w, h) * 0.35):
            c = dark
        px[x, y] = c
    if knots:
        mid_y = h // 2
        for cx in (x0, x1):
            for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0), (0, 0)):
                px[cx + dx, mid_y + dy] = light or colour
    return pts


def save(img, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    return pngout.save(img, os.path.join(OUT_DIR, name))


# --- pieces --------------------------------------------------------------------------------------

def plaque():
    """THE text-bearing surface (identity, place, target, side panels, menu panel). 64x64,
    9-slice margin 14 (content inset >= 14). At the TOP of the DNA's translucency range: the
    world still breathes through, but a bright wall or window behind a line of text no longer
    prints through it (the mid value let a plaster window cross show beside the medallion)."""
    img = plate(64, 64, cut=2, alpha=TRANSLUCENCY[1])
    hairline(img, 3, role("gold", 0.78), role("gold_light", 0.9), role("gold_shadow", 0.9),
             notch=3)
    return img


def band(fade_right=True):
    """The QUIET band: no frame, a lacquer wash that fades out toward the playfield, a gold
    hairline above and below that fades with it. 96x40; slice left 12, right 56 (the fade is
    never stretched), top/bottom 6."""
    w, h = 96, 40
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    lacquer(img, 0, 0, w, h, role("lacquer"), role("lacquer_deep"), 1.0, seed=3)
    px = img.load()
    fade_from = 40
    for x in range(w):
        f = 1.0 if x < fade_from else max(0.0, 1.0 - (x - fade_from) / (w - fade_from)) ** 1.6
        a = 0.80 * f
        for y in range(h):
            r, g, b, _ = px[x, y]
            px[x, y] = (r, g, b, int(a * 255))
        for y, colour in ((1, role("gold", 0.62 * f)), (h - 2, role("gold_shadow", 0.7 * f))):
            if f > 0.02:
                px[x, y] = colour
    # the left cap: a short vertical gold rule with a knot, where the band starts
    for y in range(3, h - 3):
        px[2, y] = role("gold", 0.7)
    px[2, h // 2] = role("gold_light", 0.95)
    px[3, h // 2] = role("gold", 0.8)
    if not fade_right:
        img = img.transpose(Image.FLIP_LEFT_RIGHT)
    return img


def button(state):
    """A command plate with five DESIGNED states (aetheria_style.yaml ui.states). 96x40,
    9-slice margins 12 h / 10 v; the corner knots sit inside the margins, never stretched."""
    w, h = 96, 40
    if state == "focus":
        # The focus box is drawn OVER the normal one: a jade inner ring and corner ticks that
        # read with the keyboard alone — no fill of its own.
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        px = img.load()
        jade = role("jade", 0.95)
        for x in range(6, w - 6):
            px[x, 5] = jade
            px[x, h - 6] = jade
        for y in range(6, h - 6):
            px[5, y] = jade
            px[w - 6, y] = jade
        for cx, cy, sx, sy in ((0, 0, 1, 1), (w - 1, 0, -1, 1), (0, h - 1, 1, -1),
                               (w - 1, h - 1, -1, -1)):
            for i in range(4):
                px[cx + sx * i, cy] = role("jade", 1.0)
                px[cx, cy + sy * i] = role("jade", 1.0)
        return img
    if state == "disabled":
        img = plate(w, h, cut=2, top="lacquer", bottom="lacquer_deep", alpha=0.72, seed=5)
        px = img.load()
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                grey = int((r + g + b) / 3)
                px[x, y] = (grey, grey, grey + 3, a)
        hairline(img, 3, (86, 90, 98, 150), notch=2)
        return img
    top, bottom, seed = "lacquer_lift", "lacquer_deep", 7
    if state == "hover":
        top, bottom = "lacquer_edge", "lacquer"
    if state == "pressed":
        top, bottom = "lacquer_deep", "lacquer_deep"
    img = plate(w, h, cut=2, top=top, bottom=bottom, alpha=0.94, seed=seed)
    px = img.load()
    if state == "pressed":
        # the plate SINKS: an inner shadow under the top lip, no lit edge
        for x in range(3, w - 3):
            px[x, 1] = role("ink", 0.85)
            px[x, 2] = role("ink", 0.55)
        hairline(img, 3, role("gold_shadow", 0.95), notch=2, knots=True)
        return img
    gold_a = 1.0 if state == "hover" else 0.72
    hairline(img, 3, role("gold", gold_a), role("gold_light", gold_a), role("gold_shadow", 0.9),
             notch=2, knots=True)
    if state == "hover":
        for x in range(12, w - 12):
            px[x, h - 6] = role("jade", 0.95)          # the jade underline: "this will act"
    return img


def keycap():
    """The key badge: a raised lacquer cap (lit face, dark lip) with a jade edge — the colour
    of interaction. 20x22, 9-slice margin 6 (top) / 8 (bottom lip)."""
    w, h = 20, 22
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    lacquer(img, 0, 0, w, h - 4, role("lacquer_edge"), role("lacquer_lift"), 1.0, 0.02, seed=9)
    px = img.load()
    for y in range(h - 4, h):
        for x in range(w):
            px[x, y] = role("lacquer_deep", 1.0)
    ink = role("ink", 1.0)
    for y in range(h):
        for x in range(w):
            if not _chamfer_inside(x, y, w, h, 2):
                px[x, y] = (0, 0, 0, 0)
            elif x in (0, w - 1) or y in (0, h - 1) or not _chamfer_inside(x, y, w, h, 3):
                px[x, y] = ink
    for x in range(2, w - 2):
        px[x, 1] = role("jade", 0.85)
        px[x, h - 5] = role("jade_deep", 0.95)
    for y in range(2, h - 5):
        px[1, y] = role("jade_deep", 0.9)
        px[w - 2, y] = role("jade_deep", 0.9)
    return img


def gauge_well():
    """The gauge's empty well: a channel CUT into the plaque — darker than the lacquer around
    it, an ink shadow under its upper rim, a lit lower lip. No gold: a stack of gold-rimmed
    wells read as a stack of boxes (capture-found). 24x12, margin 4."""
    w, h = 24, 12
    img = plate(w, h, cut=1, top="ink", bottom="lacquer_deep", alpha=0.78, bevel=False,
                ink_alpha=0.55, seed=11)
    px = img.load()
    for x in range(2, w - 2):
        px[x, 1] = role("ink", 0.85)                    # the inner shadow under the rim
        px[x, h - 2] = role("lacquer_edge", 0.55)       # the lit lower lip
    return img


def gauge_fill():
    """A WHITE material mask the fill colour multiplies: a bright top catch-line, the body,
    a darker base — liquid in a channel, not a flat bar and not a glow. 12x12, margins 3 h /
    2 v (the 2px transparent rim keeps the well's border visible around the fill)."""
    w, h = 12, 12
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    rows = {2: 1.0, 3: 0.92, 4: 0.86, 5: 0.84, 6: 0.82, 7: 0.80, 8: 0.74, 9: 0.66}
    for y, v in rows.items():
        for x in range(2, w):
            g = int(255 * v)
            px[x, y] = (g, g, g, 255)
    for y in rows:
        px[w - 1, y] = (255, 255, 255, 255) if y < 8 else (200, 200, 200, 255)  # leading edge
    return img


def medallion_ring(size=96, disc=40):
    """The identity medallion ring (the portrait is composited INTO the disc by `medallion`).
    Ink, a 2px antique-gold ring lit from the top-left, ink, and four small knots."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) / 2.0
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c)
            if disc - 0.5 <= d < disc + 0.7:
                px[x, y] = role("ink", 1.0)
            elif disc + 0.7 <= d < disc + 2.9:
                ang = math.atan2(y - c, x - c)
                lit = math.cos(ang - math.radians(-135))
                col = role("gold_light") if lit > 0.55 else (
                    role("gold_shadow") if lit < -0.45 else role("gold"))
                px[x, y] = col
            elif disc + 2.9 <= d < disc + 4.0:
                px[x, y] = role("ink", 0.95)
    for ang in (-90, 90, 0, 180):
        a = math.radians(ang)
        kx, ky = c + math.cos(a) * (disc + 1.8), c + math.sin(a) * (disc + 1.8)
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                if abs(dx) + abs(dy) <= 3:
                    x, y = int(round(kx + dx)), int(round(ky + dy))
                    edge = abs(dx) + abs(dy) == 3
                    px[x, y] = role("ink", 1.0) if edge else (
                        role("gold_light") if dy < 0 or dx < 0 else role("gold"))
    return img


def medallion(portrait_path, size=96, disc=40):
    """A portrait in the medallion: a lacquer disc with a faint qi wash behind the figure, the
    pixel portrait at 1x (never resampled), clipped to the disc, then the ring over it."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    px = img.load()
    c = (size - 1) / 2.0
    top, bottom, qi = role("lacquer_edge"), role("lacquer_deep"), role("qi")
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - c, y - c)
            if d < disc - 0.5:
                t = y / (size - 1.0)
                base = mix(top, bottom, t)
                glow = max(0.0, 1.0 - math.hypot(x - c, y - c * 0.8) / disc) * 0.22
                px[x, y] = mix(base, qi, glow)
    portrait = Image.open(portrait_path).convert("RGBA")
    ox = (size - portrait.width) // 2
    oy = size - portrait.height - (size // 2 - disc) - 1
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    layer.alpha_composite(portrait, (ox, oy))
    lp = layer.load()
    for y in range(size):
        for x in range(size):
            if math.hypot(x - c, y - c) >= disc - 0.5:
                lp[x, y] = (0, 0, 0, 0)
    img.alpha_composite(layer)
    img.alpha_composite(medallion_ring(size, disc))
    return img


ELEMENT_ROLES = {"none": None, "phong": "elem_phong", "loi": "elem_loi", "hoa": "elem_hoa",
                 "thuy": "elem_thuy"}


def slot(element="none", size=40):
    """An icon slot (skill, item, equipment — ONE family, aetheria_style.yaml §7): a darker
    lacquer well, a gold hairline, and for a technique an inner ring in its element's hue."""
    img = plate(size, size, cut=3, top="lacquer", bottom="lacquer_deep", alpha=0.94, seed=13)
    px = img.load()
    # the well darkens toward its centre: the icon sits IN it, not on it
    c = (size - 1) / 2.0
    for y in range(4, size - 4):
        for x in range(4, size - 4):
            d = max(abs(x - c), abs(y - c)) / c
            px[x, y] = shade(px[x, y], 0.78 + 0.22 * d)
    hairline(img, 2, role("gold", 0.8), role("gold_light", 0.9), role("gold_shadow", 0.9),
             notch=2)
    hue = ELEMENT_ROLES[element]
    if hue:
        for i in range(4, size - 4):
            for (x, y) in ((i, 4), (i, size - 5), (4, i), (size - 5, i)):
                px[x, y] = role(hue, 0.85)
    return img


def divider():
    """A WHITE mask (the theme tints it gold): a 1px rule fading at both ends with a diamond
    knot at its centre. 96x7."""
    w, h = 96, 7
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = img.load()
    mid = w // 2
    for x in range(w):
        f = 1.0 - (abs(x - mid) / mid) ** 2.2
        px[x, 3] = (255, 255, 255, int(255 * max(0.0, f)))
    for dx in range(-3, 4):
        for dy in range(-3, 4):
            if abs(dx) + abs(dy) <= 3:
                px[mid + dx, 3 + dy] = (255, 255, 255, 255 if abs(dx) + abs(dy) < 3 else 150)
    return img


def frame_mask():
    """A hollow WHITE frame mask (tinted gold by the theme) with notched corners. 24x24,
    margin 8; centre alpha 0 — it frames, it never covers."""
    img = Image.new("RGBA", (24, 24), (0, 0, 0, 0))
    hairline(img, 1, (255, 255, 255, 255), notch=3)
    hairline(img, 3, (255, 255, 255, 120), notch=1)
    return img


def corner_fret():
    """The screen-corner ornament for full screens (menu, settings): a squared fretwork hook
    (回纹 idiom) as a WHITE mask. 56x56, hollow."""
    s = 56
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    px = img.load()
    path = [(2, 52), (2, 2), (52, 2)]                    # the long arms
    hook = [(10, 40), (10, 10), (40, 10), (40, 26), (26, 26), (26, 18), (34, 18)]
    for seq, a in ((path, 255), (hook, 220)):
        for (x0, y0), (x1, y1) in zip(seq, seq[1:]):
            for t in range(max(abs(x1 - x0), abs(y1 - y0)) + 1):
                x = x0 + (t if x1 > x0 else -t if x1 < x0 else 0)
                y = y0 + (t if y1 > y0 else -t if y1 < y0 else 0)
                px[x, y] = (255, 255, 255, a)
    for i in range(6):                                   # the arms fade out
        for x, y in ((52 - i, 2), (2, 52 - i)):
            px[x, y] = (255, 255, 255, int(255 * i / 6))
    return img


KIT = {
    "plaque.png": plaque,
    "band_right.png": lambda: band(True),
    "band_left.png": lambda: band(False),
    "button_normal.png": lambda: button("normal"),
    "button_hover.png": lambda: button("hover"),
    "button_focus.png": lambda: button("focus"),
    "button_pressed.png": lambda: button("pressed"),
    "button_disabled.png": lambda: button("disabled"),
    "keycap.png": keycap,
    "gauge_well.png": gauge_well,
    "gauge_fill.png": gauge_fill,
    "slot.png": lambda: slot("none"),
    "slot_phong.png": lambda: slot("phong"),
    "slot_loi.png": lambda: slot("loi"),
    "slot_hoa.png": lambda: slot("hoa"),
    "slot_thuy.png": lambda: slot("thuy"),
    "divider.png": divider,
    "frame_mask.png": frame_mask,
    "corner_fret.png": corner_fret,
}

# The medallions the game LOADS (UIPalette.TEX_MEDALLION_*), keyed by output name -> the actor
# whose built portrait (work/<actor>/portrait.png, from `build.py pixel`) it frames. Only what
# the HUD references ships; another actor gets a medallion when a screen shows it.
MEDALLIONS = {"player_proto": "player_proto", "cultivator_f_proto": "lin_yue"}


def build():
    written = [save(fn(), name) for name, fn in KIT.items()]
    for name, actor in MEDALLIONS.items():
        src = os.path.join(PIPE, "work", actor, "portrait.png")
        if os.path.exists(src):
            written.append(save(medallion(src), "medallion_%s.png" % name))
        else:
            print("skip medallion_%s: build the portrait first (build.py pixel %s)"
                  % (name, actor))
    return written


if __name__ == "__main__":
    for p in build():
        print("wrote", os.path.relpath(p, ROOT))
