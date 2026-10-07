#!/usr/bin/env python3
"""The Aetheria visual benchmark (D-062 CP11): VISUAL STRUCTURE / QUALITY similarity of a real
gameplay capture to the quality reference — never a pixel difference.

    visual_benchmark.py <capture.png> [--regions capture.json] [--reference ref.png]
                        [--annotation ref.json] [--out scorecard]   (-> .json and .md)

Both images are reduced to the SAME analysis grid (a box-filtered 320x180 / 320x213 view plus
region masks) and described by STRUCTURAL measures — where the HUD sits and how much it takes,
where the eye lands, the warm/cool balance, the luminance hierarchy, the edge and colour richness
of the world, how the figures separate from it, how much of the frame the technique covers, how
dark and how restrained the HUD surfaces are, how crisp the pixels are. Each measure becomes a
0-100 similarity (or, where the Visual DNA sets an absolute rule, a 0-100 compliance), every
measure is printed with its two values and why it scored what it did, and the categories are
weighted as D-062 §19 specifies:

    Composition 20 · Palette/lighting 15 · Environment 15 · Character silhouette 15 ·
    Motion/combat 10 · UI hierarchy/material 10 · VFX/spiritual 10 · Pixel readability 5

Foundation target >= 60-65; FAIL when any ESSENTIAL category (composition, palette, environment,
character, UI) scores under 50. Standard library + PIL only.
"""
import argparse
import colorsys
import json
import math
import os
import sys

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
REF_DIR = os.path.join(ROOT, "docs", "visual_benchmarks")

WEIGHTS = [
    ("composition", "Composition", 20, True),
    ("palette", "Palette / lighting", 15, True),
    ("environment", "Environment", 15, True),
    ("character", "Character silhouette", 15, True),
    ("combat", "Motion / combat", 10, False),
    ("ui", "UI hierarchy / material", 10, True),
    ("vfx", "VFX / spiritual language", 10, False),
    ("pixel", "Pixel readability", 5, False),
]
TARGET = 60.0
ESSENTIAL_FLOOR = 50.0
GRID_W = 320

# The Visual DNA's absolute rules this tool enforces (aetheria_style.yaml).
HUD_BUDGET = 0.15            # ui.permanent_area_max
HUD_FLOOR = 0.08             # below this the HUD cannot carry identity + place + actions
GOLD_SHARE_MAX = 0.10        # ui.gold_share_max
VFX_PEAK_MAX = 0.12          # vfx.peak_screen_share_max


def similarity(a, b, tolerance):
    """100 when equal, falling linearly to 0 at `tolerance` apart."""
    return max(0.0, 100.0 * (1.0 - abs(a - b) / tolerance))


class Frame:
    """One image reduced to the analysis grid, with its HUD / actor regions in grid units."""

    def __init__(self, path, regions):
        src = Image.open(path).convert("RGB")
        self.size = src.size
        self.w = GRID_W
        self.h = int(round(src.size[1] * GRID_W / src.size[0]))
        self.k = src.size[0] / float(self.w)
        img = src.resize((self.w, self.h), Image.BOX)
        self.rgb = list(img.getdata())
        self.hsv = [colorsys.rgb_to_hsv(r / 255.0, g / 255.0, b / 255.0) for r, g, b in self.rgb]
        self.lum = [(0.299 * r + 0.587 * g + 0.114 * b) / 255.0 for r, g, b in self.rgb]
        edges = img.convert("L").filter(ImageFilter.FIND_EDGES)
        self.edge = [v / 255.0 for v in edges.getdata()]
        self.native = src            # pixel-scale measures need the real pixels
        self.hud = [self._rect(r[1:] if isinstance(r[0], str) else r) for r in regions["hud"]]
        self.actors = {k: self._rect(v) for k, v in regions.get("actors", {}).items()}
        self.hud_mask = [False] * (self.w * self.h)
        for x0, y0, x1, y1 in self.hud:
            for y in range(max(0, y0), min(self.h, y1)):
                for x in range(max(0, x0), min(self.w, x1)):
                    self.hud_mask[y * self.w + x] = True
        self.play = [i for i in range(self.w * self.h) if not self.hud_mask[i]]

    def _rect(self, r):
        x, y, w, h = r
        return (int(x / self.k), int(y / self.k), int(math.ceil((x + w) / self.k)),
                int(math.ceil((y + h) / self.k)))

    def idx(self, x, y):
        return y * self.w + x

    def region(self, rect):
        x0, y0, x1, y1 = rect
        return [self.idx(x, y) for y in range(max(0, y0), min(self.h, y1))
                for x in range(max(0, x0), min(self.w, x1))]


# --- measures ------------------------------------------------------------------------------------

def hud_share(f):
    return sum(f.hud_mask) / float(len(f.hud_mask))


def centre_clear(f):
    x0, x1, y0, y1 = int(f.w * 0.25), int(f.w * 0.75), int(f.h * 0.25), int(f.h * 0.75)
    cells = [f.idx(x, y) for y in range(y0, y1) for x in range(x0, x1)]
    return 1.0 - sum(1 for i in cells if f.hud_mask[i]) / float(len(cells))


def saliency(f):
    """Per-cell visual pull: local edge energy + saturation + distance from mean luminance."""
    mean_l = sum(f.lum[i] for i in f.play) / max(1, len(f.play))
    out = [0.0] * len(f.lum)
    for i in f.play:
        out[i] = f.edge[i] * 1.5 + f.hsv[i][1] * 0.6 + abs(f.lum[i] - mean_l)
    return out


def focal_point(f, sal):
    tot = sum(sal) or 1.0
    fx = sum(sal[i] * (i % f.w) for i in f.play) / tot / f.w
    fy = sum(sal[i] * (i // f.w) for i in f.play) / tot / f.h
    return fx, fy


def balance(f, sal):
    left = sum(sal[i] for i in f.play if i % f.w < f.w // 2)
    right = sum(sal[i] for i in f.play if i % f.w >= f.w // 2)
    return left / max(1e-6, left + right)


def actors_centre(f):
    pts = [((r[0] + r[2]) / 2.0 / f.w, (r[1] + r[3]) / 2.0 / f.h) for r in f.actors.values()]
    if not pts:
        return 0.5, 0.5
    return sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)


def warm_share(f):
    n = 0
    for i in f.play:
        h, s, v = f.hsv[i]
        if s >= 0.25 and v > 0.2 and (h * 360.0 <= 70.0 or h * 360.0 >= 330.0):
            n += 1
    return n / max(1, len(f.play))


def lum_hist(f):
    bins = [0] * 5
    for i in f.play:
        bins[min(4, int(f.lum[i] * 5))] += 1
    n = float(max(1, len(f.play)))
    return [b / n for b in bins]


def rms_contrast(f):
    vals = [f.lum[i] for i in f.play]
    m = sum(vals) / max(1, len(vals))
    return math.sqrt(sum((v - m) ** 2 for v in vals) / max(1, len(vals)))


def mean_sat(f):
    return sum(f.hsv[i][1] for i in f.play) / max(1, len(f.play))


def edge_density(f):
    return sum(1 for i in f.play if f.edge[i] > 0.12) / max(1, len(f.play))


def colour_richness(f):
    """Colours (5 bits per channel) that each cover >= 0.3% of the playfield."""
    counts = {}
    for i in f.play:
        r, g, b = f.rgb[i]
        key = (r >> 3, g >> 3, b >> 3)
        counts[key] = counts.get(key, 0) + 1
    floor = 0.003 * len(f.play)
    return sum(1 for c in counts.values() if c >= floor)


def texture_spread(f):
    """How unevenly detail is spread over a 16x9 grid (std of per-cell edge means): a rich world
    has quiet and busy places, a flat one is uniformly one or the other."""
    gx, gy = 16, 9
    cells = []
    for cy in range(gy):
        for cx in range(gx):
            vals = []
            for y in range(cy * f.h // gy, (cy + 1) * f.h // gy):
                for x in range(cx * f.w // gx, (cx + 1) * f.w // gx):
                    i = f.idx(x, y)
                    if not f.hud_mask[i]:
                        vals.append(f.edge[i])
            if vals:
                cells.append(sum(vals) / len(vals))
    m = sum(cells) / max(1, len(cells))
    return math.sqrt(sum((c - m) ** 2 for c in cells) / max(1, len(cells)))


def actor_separation(f, name):
    """Colour/luminance distance between an actor's core and the ring of world around it."""
    if name not in f.actors:
        return None
    x0, y0, x1, y1 = f.actors[name]
    w, h = x1 - x0, y1 - y0
    core = f.region((x0 + w // 4, y0 + h // 6, x1 - w // 4, y1 - h // 6))
    ring = [i for i in f.region((x0 - w // 2, y0 - h // 3, x1 + w // 2, y1 + h // 3))
            if i not in set(f.region((x0, y0, x1, y1)))]
    if not core or not ring:
        return None

    def mean(idx):
        return [sum(f.rgb[i][c] for i in idx) / len(idx) / 255.0 for c in range(3)]

    a, b = mean(core), mean(ring)
    return math.sqrt(sum((a[c] - b[c]) ** 2 for c in range(3)))


def actor_scale(f, name):
    if name not in f.actors:
        return None
    return (f.actors[name][3] - f.actors[name][1]) / float(f.h)


def outline_share(f, name):
    """Native-resolution share of dark (ink) pixels on the actor box's silhouette band."""
    if name not in f.actors:
        return None
    x0, y0, x1, y1 = [int(v * f.k) for v in f.actors[name]]
    img = f.native
    dark = n = 0
    for y in range(max(0, y0), min(img.size[1], y1), 2):
        for x in range(max(0, x0), min(img.size[0], x1), 2):
            r, g, b = img.getpixel((x, y))
            n += 1
            if 0.299 * r + 0.587 * g + 0.114 * b < 40:
                dark += 1
    return dark / max(1, n)


def combat_box(f):
    if len(f.actors) < 2:
        return None
    rects = list(f.actors.values())
    if "second_actor" in f.actors:
        rects = [f.actors[k] for k in f.actors if k != "second_actor"]
    x0 = min(r[0] for r in rects)
    y0 = min(r[1] for r in rects)
    x1 = max(r[2] for r in rects)
    y1 = max(r[3] for r in rects)
    pad = int(0.25 * (x1 - x0))
    return (x0 - pad, y0 - pad, x1 + pad, y1 + pad)


def combat_focus(f, sal):
    box = combat_box(f)
    if box is None:
        return None
    inside = sum(sal[i] for i in f.region(box))
    return inside / max(1e-6, sum(sal))


def combat_spacing(f):
    if "player" not in f.actors or "enemy" not in f.actors:
        return None
    a, b = f.actors["player"], f.actors["enemy"]
    ax, ay = (a[0] + a[2]) / 2.0, (a[1] + a[3]) / 2.0
    bx, by = (b[0] + b[2]) / 2.0, (b[1] + b[3]) / 2.0
    return math.hypot(ax - bx, ay - by) / f.w


def vfx_pixels(f):
    """Technique light: bright, saturated playfield cells (an element's hue at its brightest)."""
    return [i for i in f.play if f.hsv[i][2] > 0.72 and f.hsv[i][1] > 0.25
            and not (0.15 < f.hsv[i][0] < 0.45 and f.hsv[i][2] < 0.85)]


def hue_unity(f, cells):
    if not cells:
        return None
    bins = [0] * 12
    for i in cells:
        bins[int(f.hsv[i][0] * 12) % 12] += 1
    best = max(bins[k] + bins[(k + 1) % 12] for k in range(12))
    return best / float(len(cells))


def hud_darkness(f):
    cells = [i for i, m in enumerate(f.hud_mask) if m]
    return sum(f.lum[i] for i in cells) / max(1, len(cells))


def hud_gold(f):
    cells = [i for i, m in enumerate(f.hud_mask) if m]
    n = 0
    for i in cells:
        h, s, v = f.hsv[i]
        if 30 <= h * 360 <= 55 and s > 0.3 and v > 0.45:
            n += 1
    return n / max(1, len(cells))


def hud_spread(f):
    cells = sorted(f.lum[i] for i, m in enumerate(f.hud_mask) if m)
    if not cells:
        return 0.0
    return cells[int(len(cells) * 0.97)] - cells[int(len(cells) * 0.05)]


def crispness(f):
    """Native share of 2x2 blocks that are one colour in the playfield centre: pixel art drawn
    at an integer scale is made of such blocks; a resampled or painted image is not."""
    img = f.native
    w, h = img.size
    same = n = 0
    for y in range(int(h * 0.3), int(h * 0.7) - 1, 6):
        for x in range(int(w * 0.3), int(w * 0.7) - 1, 6):
            a = img.getpixel((x, y))
            n += 1
            if a == img.getpixel((x + 1, y)) == img.getpixel((x, y + 1)) == \
                    img.getpixel((x + 1, y + 1)):
                same += 1
    return same / max(1, n)


# --- scoring -------------------------------------------------------------------------------------

def _richness(cand, ref):
    """One-sided: richer than the reference is not a defect (more materials), up to 2x; beyond
    that the extra colours are more likely noise than material."""
    if cand <= ref:
        return 100.0 * cand / max(1, ref)
    return similarity(cand, 2 * ref, 2 * ref) if cand > 2 * ref else 100.0


def _m(name, cand, ref, score, why):
    return {"measure": name, "capture": cand, "reference": ref, "score": round(score, 1),
            "why": why}


def score(cand, ref):
    cats = {}
    sal_c, sal_r = saliency(cand), saliency(ref)

    hc, hr = hud_share(cand), hud_share(ref)
    fc, fr = focal_point(cand, sal_c), focal_point(ref, sal_r)
    ac, ar = actors_centre(cand), actors_centre(ref)
    bc, br = balance(cand, sal_c), balance(ref, sal_r)
    clear = centre_clear(cand)
    # The reference's occupancy includes features canon FORBIDS (minimap, chat, quest tracker,
    # menu column — R-7), so it is reported, not chased: the DNA's band is the target. A HUD
    # inside [8%, 15%] is compact AND present; below it is too thin to carry identity, above it
    # eats the playfield.
    if HUD_FLOOR <= hc <= HUD_BUDGET:
        hud_ok = 100.0
    elif hc < HUD_FLOOR:
        hud_ok = similarity(hc, HUD_FLOOR, HUD_FLOOR)
    else:
        hud_ok = similarity(hc, HUD_BUDGET, 0.10)
    cats["composition"] = [
        _m("hud_occupancy", round(hc, 3), "%.3f (band %.2f-%.2f)" % (hr, HUD_FLOOR, HUD_BUDGET),
           hud_ok, "share of the frame the HUD takes, against the DNA's compact band (the "
           "reference's own share includes forbidden features and is shown, not chased)"),
        _m("playfield_centre_clear", round(clear, 3), 1.0, 100.0 * clear,
           "the middle 50%x50% (where the camera keeps the player) free of HUD"),
        _m("focal_point", [round(v, 2) for v in fc], [round(v, 2) for v in fr],
           similarity(math.hypot(fc[0] - fr[0], fc[1] - fr[1]), 0.0, 0.35),
           "where the eye lands (saliency centroid) relative to the reference's"),
        _m("action_centrality", [round(v, 2) for v in ac], [round(v, 2) for v in ar],
           similarity(math.hypot(ac[0] - 0.5, ac[1] - 0.5),
                      math.hypot(ar[0] - 0.5, ar[1] - 0.5), 0.25),
           "how central the actors are, compared with the reference's staging"),
        _m("left_right_balance", round(bc, 2), round(br, 2), similarity(bc, br, 0.3),
           "visual weight split between the halves"),
    ]

    wc, wr = warm_share(cand), warm_share(ref)
    lc, lr = lum_hist(cand), lum_hist(ref)
    l1 = sum(abs(a - b) for a, b in zip(lc, lr))
    cc, cr = rms_contrast(cand), rms_contrast(ref)
    sc, sr = mean_sat(cand), mean_sat(ref)
    cats["palette"] = [
        _m("warm_share", round(wc, 3), round(wr, 3), similarity(wc, wr, 0.25),
           "share of warm, saturated playfield colour (lanterns, wood, fire, skin)"),
        _m("luminance_hierarchy", [round(v, 2) for v in lc], [round(v, 2) for v in lr],
           max(0.0, 100.0 * (1.0 - l1 / 1.2)),
           "the 5-band luminance distribution (shadows -> highlights) vs the reference"),
        _m("contrast", round(cc, 3), round(cr, 3), similarity(cc, cr, 0.12),
           "RMS luminance contrast of the playfield"),
        _m("saturation", round(sc, 3), round(sr, 3), similarity(sc, sr, 0.25),
           "mean saturation of the playfield"),
    ]

    ec, er = edge_density(cand), edge_density(ref)
    rc, rr = colour_richness(cand), colour_richness(ref)
    tc, tr = texture_spread(cand), texture_spread(ref)
    cats["environment"] = [
        _m("edge_density", round(ec, 3), round(er, 3), similarity(ec, er, max(0.12, er)),
           "share of strong edges in the world: richness of built and grown detail"),
        _m("colour_richness", rc, rr, _richness(rc, rr),
           "distinct colours each covering >= 0.3% of the playfield: at least the reference's "
           "material variety; past twice it is counted as noise"),
        _m("detail_rhythm", round(tc, 3), round(tr, 3), similarity(tc, tr, max(0.04, tr)),
           "how unevenly detail is spread: quiet ground beside busy architecture"),
    ]

    sep_c, sep_r = actor_separation(cand, "player"), actor_separation(ref, "player")
    sca_c, sca_r = actor_scale(cand, "player"), actor_scale(ref, "player")
    out_c, out_r = outline_share(cand, "player"), outline_share(ref, "player")
    char = []
    if sep_c is not None and sep_r is not None:
        char.append(_m("figure_ground_separation", round(sep_c, 3), round(sep_r, 3),
                       min(100.0, 100.0 * sep_c / max(0.05, sep_r)),
                       "colour distance between the player and the world around them"))
    if sca_c is not None and sca_r is not None:
        char.append(_m("figure_scale", round(sca_c, 3), round(sca_r, 3),
                       similarity(sca_c, sca_r, 0.08), "player height as a share of the frame"))
    if out_c is not None and out_r is not None:
        char.append(_m("ink_definition", round(out_c, 3), round(out_r, 3),
                       min(100.0, 100.0 * out_c / max(0.02, out_r)),
                       "dark (ink) pixels defining the figure, vs the reference's linework"))
    if "second_actor" in cand.actors:
        sep2 = actor_separation(cand, "second_actor")
        char.append(_m("second_actor_separation", round(sep2 or 0.0, 3), round(sep_r or 0, 3),
                       min(100.0, 100.0 * (sep2 or 0.0) / max(0.05, sep_r or 0.05)),
                       "the second actor reads against the world too"))
    cats["character"] = char

    cf_c, cf_r = combat_focus(cand, sal_c), combat_focus(ref, sal_r)
    sp_c, sp_r = combat_spacing(cand), combat_spacing(ref)
    vfx_c, vfx_r = vfx_pixels(cand), vfx_pixels(ref)
    box_c = combat_box(cand)
    vfx_near = 0.0
    if box_c is not None and vfx_c:
        inside = set(cand.region(box_c))
        vfx_near = sum(1 for i in vfx_c if i in inside) / float(len(vfx_c))
    combat = []
    if cf_c is not None and cf_r is not None:
        combat.append(_m("combat_focus", round(cf_c, 3), round(cf_r, 3),
                         min(100.0, 100.0 * cf_c / max(0.05, cf_r)),
                         "share of the frame's visual pull inside the fight"))
    if sp_c is not None and sp_r is not None:
        combat.append(_m("combat_spacing", round(sp_c, 3), round(sp_r, 3),
                         similarity(sp_c, sp_r, 0.25),
                         "distance between the combatants (staging read at a glance)"))
    combat.append(_m("technique_at_the_fight", round(vfx_near, 3), 1.0, 100.0 * vfx_near,
                     "technique light that lands between the combatants, not elsewhere"))
    cats["combat"] = combat

    fp_c = len(vfx_c) / float(max(1, len(cand.play)))
    fp_r = len(vfx_r) / float(max(1, len(ref.play)))
    unity = hue_unity(cand, vfx_c)
    restraint = 100.0 if fp_c <= VFX_PEAK_MAX else similarity(fp_c, VFX_PEAK_MAX, 0.08)
    cats["vfx"] = [
        _m("vfx_presence", round(fp_c, 4), round(fp_r, 4),
           min(100.0, 100.0 * fp_c / max(0.005, fp_r * 0.35)),
           "technique light on screen at the peak; a third of the reference's spectacle is the "
           "DNA's restrained target (glow is never the design)"),
        _m("vfx_restraint", round(fp_c, 4), VFX_PEAK_MAX, restraint,
           "the DNA cap: a technique covers <= 12% of the frame"),
        _m("element_unity", round(unity or 0.0, 3), 0.8,
           100.0 * min(1.0, (unity or 0.0) / 0.8) if unity is not None else 0.0,
           "one element, one hue family (the DNA: never a second element's hue)"),
    ]

    dk_c, dk_r = hud_darkness(cand), hud_darkness(ref)
    gd_c, gd_r = hud_gold(cand), hud_gold(ref)
    sp2_c, sp2_r = hud_spread(cand), hud_spread(ref)
    regions_c, regions_r = len(cand.hud), len(ref.hud)
    cats["ui"] = [
        _m("surface_darkness", round(dk_c, 3), round(dk_r, 3), similarity(dk_c, dk_r, 0.25),
           "HUD surfaces are dark lacquer that light text sits on, like the reference's"),
        _m("gold_restraint", round(gd_c, 3), GOLD_SHARE_MAX,
           100.0 if gd_c <= GOLD_SHARE_MAX else similarity(gd_c, GOLD_SHARE_MAX, 0.1),
           "antique gold is structure, <= 10% of the HUD (the DNA)"),
        _m("legibility_spread", round(sp2_c, 3), round(sp2_r, 3),
           min(100.0, 100.0 * sp2_c / max(0.2, sp2_r)),
           "luminance range inside the HUD (text against its surface)"),
        _m("information_grouping", regions_c, regions_r,
           similarity(regions_c, max(4, min(regions_r, 6)), 4.0),
           "the HUD as a few grouped plaques (the reference's 8 include forbidden features; "
           "4-6 is the target)"),
    ]

    cr_c = crispness(cand)
    cats["pixel"] = [
        _m("pixel_crispness", round(cr_c, 3), 0.5, min(100.0, 100.0 * cr_c / 0.5),
           "2x2 one-colour blocks in the playfield: integer-scaled pixel art, not resampled"),
    ]

    result = {"categories": {}, "total": 0.0, "pass": True, "failures": []}
    total = 0.0
    for key, label, weight, essential in WEIGHTS:
        ms = cats.get(key, [])
        s = sum(m["score"] for m in ms) / len(ms) if ms else 0.0
        result["categories"][key] = {"label": label, "weight": weight, "essential": essential,
                                     "score": round(s, 1), "measures": ms}
        total += weight * s / 100.0
        if essential and s < ESSENTIAL_FLOOR:
            result["pass"] = False
            result["failures"].append("%s %.1f < %d" % (label, s, ESSENTIAL_FLOOR))
    result["total"] = round(total, 1)
    if total < TARGET:
        result["pass"] = False
        result["failures"].append("total %.1f < target %d" % (total, TARGET))
    return result


def markdown(result, capture, reference):
    lines = ["# Aetheria visual benchmark — scorecard", "",
             "Capture: `%s`  " % capture, "Reference: `%s` (REFERENCE ONLY — structure and "
             "quality, never pixels)" % reference, "",
             "**TOTAL %.1f / 100 — %s** (target >= %d; essential categories >= %d)" % (
                 result["total"], "PASS" if result["pass"] else "FAIL", TARGET, ESSENTIAL_FLOOR),
             ""]
    if result["failures"]:
        lines += ["Failures: " + "; ".join(result["failures"]), ""]
    lines += ["| Category | Weight | Score | Weighted |", "|---|---:|---:|---:|"]
    for key, label, weight, essential in WEIGHTS:
        c = result["categories"][key]
        lines.append("| %s%s | %d | %.1f | %.1f |" % (label, " *(essential)*" if essential else "",
                                                       weight, c["score"],
                                                       weight * c["score"] / 100.0))
    lines.append("")
    for key, label, weight, essential in WEIGHTS:
        c = result["categories"][key]
        lines += ["## %s — %.1f" % (label, c["score"]), "",
                  "| Measure | Capture | Reference / rule | Score | Why |", "|---|---|---|---:|---|"]
        for m in c["measures"]:
            lines.append("| %s | %s | %s | %.1f | %s |" % (m["measure"], m["capture"],
                                                            m["reference"], m["score"], m["why"]))
        lines.append("")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("capture")
    ap.add_argument("--regions", help="the capture's regions JSON (golden_combat.json)")
    ap.add_argument("--reference", default=os.path.join(
        REF_DIR, "aetheria_gameplay_quality_reference.png"))
    ap.add_argument("--annotation", default=os.path.join(REF_DIR, "reference_annotation.json"))
    ap.add_argument("--out", help="write <out>.json and <out>.md")
    args = ap.parse_args(argv)
    if not os.path.exists(args.reference):
        print("reference missing: %s (it is gitignored; place the benchmark image there)"
              % args.reference)
        return 2
    regions_path = args.regions or os.path.splitext(args.capture)[0] + ".json"
    with open(regions_path, encoding="utf-8") as f:
        cand_regions = json.load(f)
    with open(args.annotation, encoding="utf-8") as f:
        ref_regions = json.load(f)
    cand = Frame(args.capture, cand_regions)
    ref = Frame(args.reference, ref_regions)
    result = score(cand, ref)
    result["capture"] = os.path.relpath(args.capture, ROOT) if args.capture.startswith(ROOT) \
        else os.path.basename(args.capture)
    md = markdown(result, result["capture"], os.path.basename(args.reference))
    if args.out:
        with open(args.out + ".json", "w", encoding="utf-8") as f:
            json.dump(result, f, indent=1, ensure_ascii=False)
        with open(args.out + ".md", "w", encoding="utf-8") as f:
            f.write(md + "\n")
    print(md)
    return 0 if result["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
