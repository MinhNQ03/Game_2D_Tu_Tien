"""Structural image metrics shared by `style_check.py` and `visual_benchmark.py`.

PIL only (no numpy on the system Python), written so a 1280x720 capture is measured in about a
second: per-pixel work goes through `Image.getdata()` / `ImageFilter` / `ImageStat`, never
`getpixel` in a double loop.

Every function returns plain numbers; THRESHOLDS live in `aetheria_style.yaml` and the
benchmark's scoring table, never here, so a metric's meaning cannot drift with a tuning edit.
"""
import os
import sys

from PIL import Image, ImageFilter, ImageStat

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "style"))
import style  # noqa: E402


def load_rgba(path):
    return Image.open(path).convert("RGBA")


def rgb_pixels(img):
    return list(img.convert("RGB").getdata())


# --- colour distribution -----------------------------------------------------------------------

def warm_share(pixels, min_sat=0.25):
    """Share of pixels whose hue is warm (red..yellow, 0-70 deg, or > 330) and saturated."""
    n = warm = 0
    for p in pixels:
        h, s, v = style.hsv(p)
        n += 1
        if s >= min_sat and v > 0.2 and (h <= 70 or h >= 330):
            warm += 1
    return warm / max(1, n)


def glow_share(pixels, min_value=0.93, min_sat=0.18):
    """Share of near-white, tinted pixels: what 'glow' looks like once it is rendered."""
    n = hot = 0
    for p in pixels:
        h, s, v = style.hsv(p)
        n += 1
        if v >= min_value and s >= min_sat:
            hot += 1
    return hot / max(1, n)


def hue_family_share(pixels, rgb, max_lab=14.0, sample_step=1):
    """Share of pixels within `max_lab` (CIE76) of a reference colour."""
    target = style.to_lab(rgb)
    n = hit = 0
    for i in range(0, len(pixels), sample_step):
        lab = style.to_lab(pixels[i])
        n += 1
        if ((lab[0] - target[0]) ** 2 + (lab[1] - target[1]) ** 2
                + (lab[2] - target[2]) ** 2) ** 0.5 <= max_lab:
            hit += 1
    return hit / max(1, n)


def value_stats(img):
    """(mean, stddev) of luma 0..255 — the frame's key and its contrast."""
    stat = ImageStat.Stat(img.convert("L"))
    return stat.mean[0], stat.stddev[0]


def saturation_mean(img):
    hsv_img = img.convert("RGB").convert("HSV")
    return ImageStat.Stat(hsv_img).mean[1] / 255.0


def value_histogram_spread(img, bins=8):
    """How many of `bins` value bands hold >= 2% of the frame — a key with no darks or no
    lights is flat, a frame that uses every band has a value structure."""
    hist = img.convert("L").histogram()
    total = float(sum(hist))
    per = 256 // bins
    used = 0
    for b in range(bins):
        if sum(hist[b * per:(b + 1) * per]) / total >= 0.02:
            used += 1
    return used


# --- structure --------------------------------------------------------------------------------

def edge_density(img, threshold=48):
    """Share of pixels on a strong luma edge (FIND_EDGES >= threshold)."""
    edges = img.convert("L").filter(ImageFilter.FIND_EDGES)
    hist = edges.histogram()
    return sum(hist[threshold:]) / float(max(1, sum(hist)))


def edge_density_map(img, cols, rows, threshold=48):
    """Edge density per grid cell — where the detail is (focal structure, not noise)."""
    edges = img.convert("L").filter(ImageFilter.FIND_EDGES).point(
        lambda v: 255 if v >= threshold else 0)
    w, h = edges.size
    out = []
    for r in range(rows):
        row = []
        for c in range(cols):
            box = (c * w // cols, r * h // rows, (c + 1) * w // cols, (r + 1) * h // rows)
            row.append(ImageStat.Stat(edges.crop(box)).mean[0] / 255.0)
        out.append(row)
    return out


def high_frequency_ratio(img, threshold=48):
    """Fine-grain noise vs structure: edges at 1x scale over edges after a 2x box reduction.
    Noise (single-pixel speckle) vanishes when reduced; structure (outlines, architecture)
    survives. A ratio well above ~2 means the detail is mostly speckle."""
    fine = edge_density(img, threshold)
    small = img.reduce(2)
    coarse = edge_density(small, threshold)
    return fine / max(1e-6, coarse)


def local_contrast(img, box):
    """Luma stddev inside `box` relative to the whole frame's — does a region stand out."""
    region = img.crop(box).convert("L")
    return ImageStat.Stat(region).stddev[0] / max(1e-6, ImageStat.Stat(img.convert("L")).stddev[0])


def region_value_gap(img, inner_box, ring=12):
    """Mean luma difference between a region and the ring around it (figure/ground)."""
    l_img = img.convert("L")
    x0, y0, x1, y1 = inner_box
    inner = ImageStat.Stat(l_img.crop(inner_box)).mean[0]
    outer_box = (max(0, x0 - ring), max(0, y0 - ring),
                 min(img.width, x1 + ring), min(img.height, y1 + ring))
    o = ImageStat.Stat(l_img.crop(outer_box))
    inner_area = (x1 - x0) * (y1 - y0)
    outer_area = (outer_box[2] - outer_box[0]) * (outer_box[3] - outer_box[1])
    ring_sum = o.sum[0] - inner * inner_area
    ring_mean = ring_sum / max(1, outer_area - inner_area)
    return abs(inner - ring_mean) / 255.0


# --- sprites ----------------------------------------------------------------------------------

def frames_of(sheet, cell_w, cell_h):
    cols, rows = sheet.width // cell_w, sheet.height // cell_h
    return [[sheet.crop((c * cell_w, r * cell_h, (c + 1) * cell_w, (r + 1) * cell_h))
             for c in range(cols)] for r in range(rows)]


def sprite_metrics(cell, ink_rgb):
    """Per-frame figures for a sprite cell (RGBA)."""
    w, h = cell.size
    data = list(cell.getdata())
    opaque = [[data[y * w + x][3] == 255 for x in range(w)] for y in range(h)]
    rows = [y for y in range(h) if any(opaque[y])]
    cols = [x for x in range(w) if any(opaque[y][x] for y in range(h))]
    colours = set(data[i][:3] for i in range(len(data)) if data[i][3] == 255)
    # Orphans: an opaque pixel whose colour NONE of its 8 neighbours shares — an isolated
    # speckle. 8, not 4: a 1px line in pixel art steps DIAGONALLY by design (the outline, the
    # crossed collar, a robe edge), and a diagonal line is a run, not noise. The one deliberate
    # single pixel is an eye: ink set inside the face, touching no air.
    ink_c = tuple(ink_rgb)
    diag = ((1, 1), (1, -1), (-1, 1), (-1, -1))
    orphans = solid = 0
    border = ink_border = 0
    for y in range(h):
        for x in range(w):
            if not opaque[y][x]:
                continue
            solid += 1
            c = data[y * w + x][:3]
            same = False
            touches_air = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h:
                    if opaque[ny][nx] and data[ny * w + nx][:3] == c:
                        same = True
                    if not opaque[ny][nx] and data[ny * w + nx][3] == 0:
                        touches_air = True
                else:
                    touches_air = True
            if not same:
                same = any(0 <= x + dx < w and 0 <= y + dy < h and opaque[y + dy][x + dx]
                           and data[(y + dy) * w + x + dx][:3] == c for dx, dy in diag)
            if not same and c == ink_c and not touches_air:
                same = True
            if not same:
                orphans += 1
            if touches_air:
                border += 1
                if c == tuple(ink_rgb):
                    ink_border += 1
    return {
        "height_px": (rows[-1] - rows[0] + 1) if rows else 0,
        "width_px": (cols[-1] - cols[0] + 1) if cols else 0,
        "top_row": rows[0] if rows else -1,
        "bottom_row": rows[-1] if rows else -1,
        "colours": len(colours),
        "opaque_px": solid,
        "orphan_share": orphans / max(1, solid),
        "outline_coverage": ink_border / max(1, border),
    }


def frame_difference(a, b):
    """Pixels that differ between two RGBA cells."""
    da, db = list(a.getdata()), list(b.getdata())
    return sum(1 for p, q in zip(da, db) if p != q)
