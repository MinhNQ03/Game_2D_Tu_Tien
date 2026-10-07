"""The one way the pipeline writes a shipped PNG: indexed, losslessly.

Pipeline art is a handful of ramp tones and the ink (a sheet ~22 colours, a painted floor ~44),
so an 8-bit palette with a per-entry alpha (tRNS) holds EVERY pixel exactly, at about half the
bytes of RGBA. An image with more than 256 distinct RGBA values is written as RGBA, unchanged —
nothing is ever quantized. Godot imports both the same (lossless, no mipmaps).

  python3 pngout.py <png>...     re-save existing assets in place (pixel-identical, verified)
"""
import os
import sys

from PIL import Image


def _indexed(img):
    rgba = img.convert("RGBA")
    colours = rgba.getcolors(256)
    if colours is None:
        return None
    # every fully transparent pixel is one entry, whatever its RGB was
    data = [(0, 0, 0, 0) if c[3] == 0 else c for c in rgba.getdata()]
    keys = sorted(set(data), key=lambda c: (c[3] != 0, c))
    index = {c: i for i, c in enumerate(keys)}
    out = Image.new("P", rgba.size)
    out.putdata([index[c] for c in data])
    out.putpalette([v for c in keys for v in c[:3]])
    return out, bytes(c[3] for c in keys)


def save(img, path):
    """Write `img` to `path` as the smallest lossless PNG; returns `path`."""
    packed = _indexed(img)
    if packed is None:
        img.save(path, optimize=True)
    else:
        packed[0].save(path, optimize=True, transparency=packed[1])
    return path


def _same(a, b):
    def norm(im):
        return [(0, 0, 0, 0) if c[3] == 0 else c for c in im.convert("RGBA").getdata()]
    return a.size == b.size and norm(a) == norm(b)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        before = Image.open(p)
        before.load()
        size0 = os.path.getsize(p)
        save(before, p)
        if not _same(before, Image.open(p)):
            sys.exit("pngout: %s changed pixels" % p)
        print("%7d -> %7d  %s" % (size0, os.path.getsize(p), p))
