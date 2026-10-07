"""Pixel raster primitives for the Aetheria asset generator (stdlib only).

A canvas is a list of rows, each row a list of (r, g, b, a) tuples. Every primitive clips to the
canvas, so a pose that reaches past the cell edge is cut rather than wrapped. Nothing here knows
what a character is: the figure, beast and prop modules compose these.
"""
import os
import struct
import zlib

TRANSPARENT = (0, 0, 0, 0)


def blank(w, h, color=TRANSPARENT):
    return [[color for _ in range(w)] for _ in range(h)]


def size(px):
    return (len(px[0]), len(px)) if px else (0, 0)


def put(px, x, y, color):
    if 0 <= y < len(px) and 0 <= x < len(px[0]):
        px[y][x] = color


def get(px, x, y):
    if 0 <= y < len(px) and 0 <= x < len(px[0]):
        return px[y][x]
    return TRANSPARENT


def rect(px, x0, y0, x1, y1, color):
    """Fill [x0, x1) x [y0, y1)."""
    for y in range(max(0, y0), min(len(px), y1)):
        row = px[y]
        for x in range(max(0, x0), min(len(row), x1)):
            row[x] = color


def oval(px, cx, cy, rx, ry, color):
    """Fill an axis-aligned ellipse centred on (cx, cy)."""
    rx = max(rx, 0.5)
    ry = max(ry, 0.5)
    for y in range(max(0, int(cy - ry) - 1), min(len(px), int(cy + ry) + 2)):
        for x in range(max(0, int(cx - rx) - 1), min(len(px[0]), int(cx + rx) + 2)):
            dx = (x - cx) / float(rx)
            dy = (y - cy) / float(ry)
            if dx * dx + dy * dy <= 1.0:
                px[y][x] = color


def polygon(px, points, color):
    """Fill a polygon by scanline (even-odd), sampling pixel centres."""
    if len(points) < 3:
        return
    ys = [p[1] for p in points]
    for y in range(max(0, int(min(ys))), min(len(px), int(max(ys)) + 1)):
        sy = y + 0.5
        xs = []
        n = len(points)
        for i in range(n):
            (x0, y0), (x1, y1) = points[i], points[(i + 1) % n]
            if (y0 <= sy < y1) or (y1 <= sy < y0):
                xs.append(x0 + (sy - y0) * (x1 - x0) / float(y1 - y0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(max(0, int(xs[i] + 0.5)), min(len(px[0]), int(xs[i + 1] + 0.5))):
                px[y][x] = color


def limb(px, x0, y0, x1, y1, w0, w1, color):
    """A tapered segment from (x0, y0) width w0 to (x1, y1) width w1 — a sleeve, a leg, a tail.

    Drawn as a quad around the segment's normal so a diagonal limb keeps its width, plus round
    caps, so two limbs meeting at a joint never leave a notch between them.
    """
    dx, dy = x1 - x0, y1 - y0
    length = (dx * dx + dy * dy) ** 0.5
    if length < 0.01:
        oval(px, x0, y0, w0 / 2.0, w0 / 2.0, color)
        return
    nx, ny = -dy / length, dx / length
    a, b = w0 / 2.0, w1 / 2.0
    polygon(px, [
        (x0 + nx * a, y0 + ny * a), (x1 + nx * b, y1 + ny * b),
        (x1 - nx * b, y1 - ny * b), (x0 - nx * a, y0 - ny * a),
    ], color)
    oval(px, x0, y0, a, a, color)
    oval(px, x1, y1, b, b, color)


def line(px, x0, y0, x1, y1, color):
    """A 1px Bresenham line."""
    x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        put(px, x0, y0, color)
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def shade(color, factor):
    """Lighten (factor > 1) or darken (< 1) an RGBA colour, alpha kept."""
    r, g, b, a = color
    return (max(0, min(255, int(r * factor))), max(0, min(255, int(g * factor))),
            max(0, min(255, int(b * factor))), a)


def mix(a, b, t):
    """Linear blend of two RGBA colours."""
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(4))


def with_alpha(color, alpha):
    return (color[0], color[1], color[2], alpha)


BAYER4 = (
    (0, 8, 2, 10),
    (12, 4, 14, 6),
    (3, 11, 1, 9),
    (15, 7, 13, 5),
)


def dither_where(px, match, replacement, density, x0=0, y0=0, x1=None, y1=None):
    """Ordered-dither `replacement` over pixels that currently equal `match` (masked, so the
    transparent canvas around a shape is never speckled — the training-dummy lesson, L-029)."""
    w, h = size(px)
    for y in range(y0, h if y1 is None else y1):
        for x in range(x0, w if x1 is None else x1):
            if px[y][x] == match and BAYER4[y % 4][x % 4] < density:
                px[y][x] = replacement


def outline(px, ink, threshold=255):
    """Trace a 1px ink edge around every pixel at or above `threshold` alpha.

    Derived from the pixels, never hand-drawn, so it stays correct for every pose. Only FULLY
    opaque neighbours count by default, so a soft glow drawn afterwards is never outlined.
    """
    w, h = size(px)
    edge = []
    for y in range(h):
        for x in range(w):
            if px[y][x][3] != 0:
                continue
            for (dx, dy) in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and px[ny][nx][3] >= threshold:
                    edge.append((x, y))
                    break
    for (x, y) in edge:
        px[y][x] = ink


def inner_shadow(px, base, shadow, side):
    """Darken the edge pixels of every region of `base` on one side (-1 left, +1 right), giving
    a flat colour field a lit side and a shadowed side without hand-placing a single pixel."""
    w, h = size(px)
    hits = []
    for y in range(h):
        for x in range(w):
            if px[y][x] != base:
                continue
            nx = x + side
            if not (0 <= nx < w) or px[y][nx][3] == 0:
                hits.append((x, y))
    for (x, y) in hits:
        px[y][x] = shadow


def glow(px, cx, cy, radius, color, peak=255):
    """A soft radial halo blended over the canvas (partial alpha at the rim)."""
    r2 = float(radius * radius) or 1.0
    w, h = size(px)
    for y in range(max(0, int(cy - radius)), min(h, int(cy + radius) + 1)):
        for x in range(max(0, int(cx - radius)), min(w, int(cx + radius) + 1)):
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
                px[y][x] = (int(color[0] * k + dr * (1 - k)), int(color[1] * k + dg * (1 - k)),
                            int(color[2] * k + db * (1 - k)), max(da, a))


def blit(dst, src, ox, oy):
    """Copy the opaque pixels of `src` onto `dst` at (ox, oy)."""
    sw, sh = size(src)
    dw, dh = size(dst)
    for y in range(sh):
        ty = oy + y
        if not 0 <= ty < dh:
            continue
        srow, drow = src[y], dst[ty]
        for x in range(sw):
            c = srow[x]
            if c[3] == 0:
                continue
            tx = ox + x
            if 0 <= tx < dw:
                drow[tx] = c


def mirror(px):
    return [list(reversed(row)) for row in px]


def write_png(path, px):
    """Write a PNG with only zlib + struct (no third-party imaging library).

    Lossless and small: an image of <=256 distinct RGBA values (every sprite here) is written
    as 8-bit palette + per-entry alpha (tRNS), anything else as RGBA8."""
    w, h = size(px)
    pixels = [(0, 0, 0, 0) if c[3] == 0 else tuple(c) for row in px for c in row]
    palette = sorted(set(pixels), key=lambda c: (c[3] != 0, c))
    indexed = len(palette) <= 256
    raw = bytearray()
    if indexed:
        index = {c: i for i, c in enumerate(palette)}
        for y in range(h):
            raw.append(0)
            raw += bytes(index[c] for c in pixels[y * w:(y + 1) * w])
    else:
        for y in range(h):
            raw.append(0)
            for c in pixels[y * w:(y + 1) * w]:
                raw += bytes(c)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    head = chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 3 if indexed else 6, 0, 0, 0))
    if indexed:
        head += (chunk(b"PLTE", bytes(v for c in palette for v in c[:3]))
                 + chunk(b"tRNS", bytes(c[3] for c in palette)))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + head
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
