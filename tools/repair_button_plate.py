#!/usr/bin/env python3
"""repair_button_plate — derive the shipped painted button plate from the pack's raw crop.

WHY THIS EXISTS
---------------
The painted jade plate (`assets/ui/aetheria/buttons/button_jade.png`, D-044) was imported as
the pack's raw 245x90 crop, and opening a real capture at 3x showed three defects that no
assertion could see (D-056 UI pass):

  1. Its outer background is OPAQUE navy, so every menu button drew a dark rectangle around
     the plate's chamfered silhouette.
  2. The crop CUTS the right end-cap: the left gold spike has ~15px of air before the edge,
     the right one runs off it, so the right end of every button read as sliced off.
  3. It was 9-sliced at 245x90 into a 64px-high box with 44px side bands, while the qi-swirl
     emblem is ~95px wide — so the emblem sat partly in the STRETCHED centre (drawn ~1.6x
     wide) and also squashed vertically, and a long label ("Tiếng Việt — đang dùng") was laid
     over it.

This tool makes the fix REPRODUCIBLE instead of a hand edit nobody can redo:

  * the missing right tip is rebuilt from the MIRRORED left end, spliced in where the two
    overlap best (searched, not guessed) with a short cross-fade;
  * the outer background is flood-filled from the image border to transparent — the plate's
    own bright frame line stops the fill, so the dark well inside is never touched — with a
    soft 1px alpha ring so the LINEAR-filtered edge does not fringe;
  * the result is trimmed and resampled ONCE, with Lanczos, to exactly `--height` pixels
    (UIPalette.BUTTON_HEIGHT), so at the authored button height there is no vertical
    9-slice stretch at all and the side bands can protect the WHOLE emblem.

Pillow, unlike the CI tools (`measure_ui_assets.py`, `gen_prototype_assets.py`) which are
stdlib-only so they run anywhere CI runs: this is an OFFLINE, run-once asset derivation, never
a gate, and a hand-rolled Lanczos would be more code than the fix.

USAGE
    git show <rev>:assets/ui/aetheria/buttons/button_jade.png > /tmp/raw.png
    python3 tools/repair_button_plate.py /tmp/raw.png assets/ui/aetheria/buttons/button_jade.png

The input must be the RAW crop (pre-D-056 revision `e19e795` or the pack's
`05_generated_ui/button_cyan.png`) — running it on its own output would splice a second tip.
"""

import argparse
import sys
from collections import deque

from PIL import Image

## Width of the left end searched for a mirror match. Covers the gold spike and the chamfer.
MIRROR_SPAN = 70

## Colour distance from the background that is still "background" for the flood fill, and the
## distance at which an edge pixel becomes fully opaque (the soft ring in between).
TOL_BACKGROUND = 14.0
TOL_OPAQUE = 40.0

## An edge pixel never drops below this alpha: a ring fully faded out would eat into the
## plate's dark outline and make the silhouette look thinner than it is drawn.
EDGE_ALPHA_FLOOR = 0.35


def _median_border_colour(px, w, h):
    border = ([px[x, 0] for x in range(w)] + [px[x, h - 1] for x in range(w)]
              + [px[0, y] for y in range(h)])
    return tuple(sorted(c[i] for c in border)[len(border) // 2] for i in range(3))


def _column(px, x, h):
    return [px[x, y] for y in range(h)]


def _mean_abs_diff(col_a, col_b):
    return sum(abs(a[i] - b[i]) for a, b in zip(col_a, col_b) for i in range(3))


def splice_mirrored_tip(im):
    """Return a wider RGB image whose truncated right end is completed from the mirrored left."""
    w, h = im.size
    px = im.load()
    mirrored = [_column(px, MIRROR_SPAN - 1 - i, h) for i in range(MIRROR_SPAN)]
    best = None
    for overlap in range(6, 36):
        for start in range(0, MIRROR_SPAN - overlap):
            d = sum(_mean_abs_diff(_column(px, w - overlap + k, h), mirrored[start + k])
                    for k in range(overlap)) / float(overlap * h * 3)
            if best is None or d < best[0]:
                best = (d, overlap, start)
    diff, overlap, start = best
    tail = mirrored[start + overlap:]
    out = Image.new("RGB", (w + len(tail), h))
    op = out.load()
    for x in range(w):
        for y in range(h):
            op[x, y] = px[x, y]
    for k in range(overlap):
        t = (k + 0.5) / overlap
        x = w - overlap + k
        for y in range(h):
            a, b = px[x, y], mirrored[start + k][y]
            op[x, y] = tuple(int(round(a[i] * (1.0 - t) + b[i] * t)) for i in range(3))
    for k, column in enumerate(tail):
        for y in range(h):
            op[w + k, y] = column[y]
    print("[plate] splice: overlap %dpx, mirror start %d, mean diff %.1f/255, +%dpx"
          % (overlap, start, diff, len(tail)))
    return out


def clear_outer_background(im):
    """Flood the background from the border to transparent; returns a trimmed RGBA image."""
    w, h = im.size
    px = im.load()
    bg = _median_border_colour(px, w, h)

    def dist(c):
        return sum((c[i] - bg[i]) ** 2 for i in range(3)) ** 0.5

    outside = [[False] * w for _ in range(h)]
    queue = deque([(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)]
                  + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)])
    while queue:
        y, x = queue.popleft()
        if outside[y][x] or dist(px[x, y]) > TOL_BACKGROUND:
            continue
        outside[y][x] = True
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not outside[ny][nx]:
                queue.append((ny, nx))

    out = Image.new("RGBA", (w, h))
    op = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if outside[y][x]:
                op[x, y] = (r, g, b, 0)
                continue
            on_edge = any(0 <= y + dy < h and 0 <= x + dx < w and outside[y + dy][x + dx]
                          for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            alpha = 1.0
            if on_edge:
                ramp = (dist((r, g, b)) - TOL_BACKGROUND) / (TOL_OPAQUE - TOL_BACKGROUND)
                alpha = max(EDGE_ALPHA_FLOOR, min(1.0, ramp))
            op[x, y] = (r, g, b, int(round(255 * alpha)))
    bbox = out.getchannel("A").getbbox()
    print("[plate] background %s cleared, trimmed to %s" % (str(bg), str(bbox)))
    return out.crop(bbox)


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("src", help="the RAW pack crop (opaque background, truncated tip)")
    parser.add_argument("dst", help="where to write the shipped plate")
    parser.add_argument("--height", type=int, default=64,
                        help="output height in px; keep equal to UIPalette.BUTTON_HEIGHT")
    args = parser.parse_args(argv)

    source = Image.open(args.src)
    # Refuse an already-repaired plate: its corner is transparent, and a second pass would
    # splice a second mirrored tip onto the first.
    if "A" in source.getbands() and source.getchannel("A").getpixel((0, 0)) < 255:
        print("[plate] REFUSED: %s already has a transparent background — pass the RAW crop"
              % args.src, file=sys.stderr)
        return 2
    raw = source.convert("RGB")
    plate = clear_outer_background(splice_mirrored_tip(raw))
    width = int(round(plate.width * args.height / float(plate.height)))
    plate = plate.resize((width, args.height), Image.LANCZOS)
    plate.save(args.dst, optimize=True)
    print("[plate] wrote %s (%dx%d) from %s (%dx%d)"
          % (args.dst, plate.width, plate.height, args.src, raw.width, raw.height))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
