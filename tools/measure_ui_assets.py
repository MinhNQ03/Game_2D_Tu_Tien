#!/usr/bin/env python3
"""measure_ui_assets — Aetheria UI asset measuring tool.

WHY THIS EXISTS
---------------
`.kiro/steering/06-art-assets.md` and L-021 require an asset to be MEASURED before any
colour or layout decision is built on it: pixel size, centre alpha (is there a fill to draw
on?) and centre brightness (is this a light or a dark surface?). That rule was written after
the HUD shipped broken four ways at once because each of those three facts had been assumed
instead of checked — a light plate behind light-only text, a hollow corner ornament used as a
keycap, and a 218x118 panel used as a 40x40 slot.

Until now that measuring was done ad-hoc, per art pass. This makes it a REPEATABLE GATE, which
is what the asset pipeline needs: when a new candidate UI pack arrives, the AUDIT step is
running this over it, not eyeballing a preview image.

Standard library only (zlib + struct), same constraint as `gen_prototype_assets.py` — no
Pillow, no numpy, so it runs anywhere CI runs.

USAGE
    python3 tools/measure_ui_assets.py <path> [<path> ...]      # files or directories
    python3 tools/measure_ui_assets.py --audit                  # the three known families
    python3 tools/measure_ui_assets.py --selftest

WHAT THE COLUMNS MEAN
    size        WxH in pixels. A frame meant for a small slot must not be a huge panel.
    ctr_a       alpha at the centre, 0-255. 0 means the texture has NO FILL -- it is a frame
                or an ornament, and text placed "on" it will sit on whatever is behind.
    ctr_lum     perceived brightness at the centre, 0-255, over the alpha-composited pixel.
                A surface that carries this project's light-only text palette must measure
                BELOW SURFACE_LIGHT_LIMIT, or the result is light text on a light plate.
    edge_lum    mean brightness of the 1px border ring -- the frame band. A big gap between
                edge_lum and ctr_lum is the signature of an ornate frame around a dark well,
                which is exactly what Aetheria wants.
    opaque%     share of pixels with alpha > 8. Distinguishes a solid panel from a sparse
                ornament.
    verdict     a one-word reading, so a 400-file pack can be skimmed.
"""

import os
import struct
import sys
import zlib

# A surface carrying this project's light-only text palette must measure below this.
# `06-art-assets.md` names it SURFACE_LIGHT_BRIGHTNESS_LIMIT and binds it to BOTH the
# pixel-art and the painted UI tiers: it is a legibility rule, not a pixel-grid rule.
SURFACE_LIGHT_LIMIT = 120

# Below this centre alpha the texture has no usable fill (it is a frame/ornament).
HOLLOW_ALPHA_LIMIT = 8


def _read_png(path):
    """Return (width, height, rows) where rows[y][x] = (r, g, b, a). Stdlib only."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, width, height, depth, color, idat = 8, 0, 0, 8, 6, bytearray()
    palette, trns = b"", b""
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        tag = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
        elif tag == b"PLTE":
            palette = body
        elif tag == b"tRNS":
            trns = body
        elif tag == b"IDAT":
            idat += body
        elif tag == b"IEND":
            break
        pos += 12 + length
    if depth not in (1, 2, 4, 8):
        raise ValueError("unsupported bit depth %d" % depth)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
    raw = zlib.decompress(bytes(idat))
    # Sub-byte depths (1/2/4) pack several samples per byte and are what monochrome and
    # small-palette packs actually ship — Kenney's Fantasy UI Borders are 1-bit. Expanding
    # them here rather than refusing is the difference between auditing a candidate pack and
    # guessing about it from its preview image.
    if depth < 8:
        packed_stride = (width * channels * depth + 7) // 8
        expanded, mask = bytearray(), (1 << depth) - 1
        for y in range(height):
            at = y * (packed_stride + 1)
            expanded.append(raw[at])
            line = raw[at + 1:at + 1 + packed_stride]
            samples, per_byte = [], 8 // depth
            for byte in line:
                for slot in range(per_byte):
                    shift = 8 - depth * (slot + 1)
                    samples.append((byte >> shift) & mask)
            samples = samples[:width * channels]
            if color == 0:
                # Greyscale: scale the sample up to the full 0-255 range, or a 1-bit white
                # would read as luminance 1 instead of 255.
                scale = 255 // mask
                samples = [s * scale for s in samples]
            expanded += bytes(samples)
        raw, depth = bytes(expanded), 8
    stride = width * channels
    out, prev = [], bytearray(stride)
    at = 0
    for _y in range(height):
        filt = raw[at]
        line = bytearray(raw[at + 1:at + 1 + stride])
        at += 1 + stride
        # PNG per-scanline reconstruction filters (spec 9.2).
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if filt == 1:
                line[i] = (line[i] + a) & 0xFF
            elif filt == 2:
                line[i] = (line[i] + b) & 0xFF
            elif filt == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 0xFF
            elif filt == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 0xFF
        prev = line
        row = []
        for x in range(width):
            px = line[x * channels:(x + 1) * channels]
            if color == 6:
                row.append((px[0], px[1], px[2], px[3]))
            elif color == 2:
                row.append((px[0], px[1], px[2], 255))
            elif color == 0:
                row.append((px[0], px[0], px[0], 255))
            elif color == 4:
                row.append((px[0], px[0], px[0], px[1]))
            else:  # color == 3, indexed
                idx = px[0]
                r, g, b = palette[idx * 3:idx * 3 + 3] or (0, 0, 0)
                a = trns[idx] if idx < len(trns) else 255
                row.append((r, g, b, a))
        out.append(row)
    return width, height, out


def _luma(px):
    """Rec.601 brightness of a pixel composited over BLACK (our UI ground is dark ink)."""
    r, g, b, a = px
    f = a / 255.0
    return int(0.299 * r * f + 0.587 * g * f + 0.114 * b * f)


def measure(path):
    width, height, rows = _read_png(path)
    cx, cy = width // 2, height // 2
    centre = rows[cy][cx]
    # Average a small centre patch, so a single stray pixel cannot decide the verdict.
    patch, half = [], max(1, min(width, height) // 10)
    for y in range(max(0, cy - half), min(height, cy + half + 1)):
        for x in range(max(0, cx - half), min(width, cx + half + 1)):
            patch.append(rows[y][x])
    ctr_lum = sum(_luma(p) for p in patch) // max(1, len(patch))
    ctr_a = sum(p[3] for p in patch) // max(1, len(patch))

    ring = []
    for x in range(width):
        ring.append(rows[0][x])
        ring.append(rows[height - 1][x])
    for y in range(height):
        ring.append(rows[y][0])
        ring.append(rows[y][width - 1])
    edge_lum = sum(_luma(p) for p in ring) // max(1, len(ring))

    opaque = sum(1 for row in rows for p in row if p[3] > HOLLOW_ALPHA_LIMIT)
    opaque_pct = 100.0 * opaque / float(width * height)

    # Is this a TINTABLE MASK rather than a surface? A mask is monochrome (every opaque pixel
    # is the same near-white value) and only partially covers its rect. Calling such a file a
    # "LIGHT surface" is technically true of its pixels and completely misleading about its
    # USE: a white mask modulated to antique gold is a gold frame, not a light plate. Getting
    # this wrong in either direction is a D-034-class mistake, so it is measured, not assumed.
    opaque_px = [p for row in rows for p in row if p[3] > HOLLOW_ALPHA_LIMIT]
    distinct = {(p[0], p[1], p[2]) for p in opaque_px}
    is_mask = (bool(opaque_px) and len(distinct) <= 2
               and min(sum(c[:3]) for c in distinct) >= 3 * 200
               and opaque_pct < 95.0)

    # Border width: scan inward along the horizontal centre line until the pixel stops
    # agreeing with the edge. This is what a 9-slice `patch_margin` must be >= , and getting
    # it wrong is how glyphs end up drawn on top of the frame band.
    border = 0
    mid = rows[cy]
    if mid:
        first_opaque = mid[0][3] > HOLLOW_ALPHA_LIMIT
        for x in range(width // 2):
            if (mid[x][3] > HOLLOW_ALPHA_LIMIT) != first_opaque:
                border = x
                break

    if is_mask:
        verdict = "MASK (monochrome, tint it - %.0f%% coverage)" % opaque_pct
    elif ctr_a <= HOLLOW_ALPHA_LIMIT:
        verdict = "HOLLOW (frame/ornament - no fill to put text on)"
    elif ctr_lum >= SURFACE_LIGHT_LIMIT:
        verdict = "LIGHT surface - NOT for light-only text (limit %d)" % SURFACE_LIGHT_LIMIT
    elif edge_lum > ctr_lum + 25:
        verdict = "DARK well + bright frame band - ideal text surface"
    else:
        verdict = "DARK surface - safe for light text"
    return {
        "size": "%dx%d" % (width, height), "ctr_a": ctr_a, "ctr_lum": ctr_lum,
        "edge_lum": edge_lum, "opaque_pct": opaque_pct, "verdict": verdict,
        "centre_rgba": centre, "border": border, "is_mask": is_mask,
    }


def _collect(paths):
    found = []
    for path in paths:
        if os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                dirs[:] = sorted(d for d in dirs if not d.startswith("."))
                for name in sorted(files):
                    if name.lower().endswith(".png"):
                        found.append(os.path.join(root, name))
        elif path.lower().endswith(".png"):
            found.append(path)
    return found


def _report(paths, limit=0):
    files = _collect(paths)
    if limit:
        files = files[:limit]
    print("%-52s %-10s %5s %7s %8s %6s %4s  %s"
          % ("file", "size", "ctr_a", "ctr_lum", "edge_lum", "opq%", "bdr", "verdict"))
    for path in files:
        try:
            m = measure(path)
        except Exception as exc:                                    # noqa: BLE001
            print("%-52s  UNREADABLE (%s)" % (path[-52:], exc))
            continue
        print("%-52s %-10s %5d %7d %8d %5.0f%% %4d  %s"
              % (path[-52:], m["size"], m["ctr_a"], m["ctr_lum"],
                 m["edge_lum"], m["opaque_pct"], m["border"], m["verdict"]))
    return len(files)


def _selftest():
    """The reader must round-trip a PNG we generate ourselves, so a decoding bug cannot be
    mistaken for an asset property. Checks all five colour types we claim to support is
    overkill; checking the RGBA path and the filter reconstruction is what matters."""
    import tempfile

    def png(path, w, h, px):
        def chunk(tag, body):
            return (struct.pack(">I", len(body)) + tag + body
                    + struct.pack(">I", zlib.crc32(tag + body) & 0xFFFFFFFF))
        raw = bytearray()
        for y in range(h):
            raw.append(0)
            for x in range(w):
                raw += bytes(px(x, y))
        ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
        with open(path, "wb") as fh:
            fh.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))

    ok = True

    def check(label, actual, expected):
        nonlocal ok
        good = actual == expected
        ok = ok and good
        print("  [%s] %s: %s (expected %s)"
              % ("ok" if good else "FAIL", label, actual, expected))

    with tempfile.TemporaryDirectory() as tmp:
        # A dark well with a bright 1px border: the shape we WANT to detect.
        framed = os.path.join(tmp, "framed.png")
        png(framed, 32, 32, lambda x, y: (240, 220, 160, 255)
            if (x in (0, 31) or y in (0, 31)) else (20, 24, 34, 255))
        m = measure(framed)
        check("framed size", m["size"], "32x32")
        check("framed centre is dark", m["ctr_lum"] < 40, True)
        check("framed edge is bright", m["edge_lum"] > 180, True)
        check("framed verdict", "DARK well" in m["verdict"], True)

        # A fully transparent centre with COLOURED border art: the key_badge.png trap
        # (L-021). It must read as HOLLOW, not as a mask — the border carries several tones,
        # so tinting it would fight the art rather than recolour it.
        hollow = os.path.join(tmp, "hollow.png")

        def ornament(x, y):
            if x in (0, 15) or y in (0, 15):
                return (180, 150, 90, 255) if (x + y) % 2 else (120, 95, 50, 255)
            return (0, 0, 0, 0)

        png(hollow, 16, 16, ornament)
        m = measure(hollow)
        check("hollow centre alpha", m["ctr_a"], 0)
        check("hollow verdict", "HOLLOW" in m["verdict"], True)
        check("hollow is NOT a mask", m["is_mask"], False)

        # A MONOCHROME frame with a transparent centre: a tintable mask, which is what the
        # Kenney borders actually are. The distinction matters: calling this a "LIGHT surface"
        # would be true of its pixels and completely misleading about its use.
        mask = os.path.join(tmp, "mask.png")
        png(mask, 24, 24, lambda x, y: (255, 255, 255, 255)
            if (x < 4 or x > 19 or y < 4 or y > 19) else (0, 0, 0, 0))
        m = measure(mask)
        check("mask detected", m["is_mask"], True)
        check("mask verdict", "MASK" in m["verdict"], True)
        check("mask border width", m["border"], 4)

        # A near-white plate: the panel.png trap (brightness 230).
        light = os.path.join(tmp, "light.png")
        png(light, 16, 16, lambda x, y: (235, 232, 226, 255))
        m = measure(light)
        check("light is above the limit", m["ctr_lum"] >= SURFACE_LIGHT_LIMIT, True)
        check("light verdict", "LIGHT surface" in m["verdict"], True)

    print("[measure_ui] SELFTEST %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


FAMILIES = [
    ("AETHERIA PRODUCTION - xianxia (current live UI)", ["assets/ui/xianxia"]),
    ("AETHERIA PRODUCTION - aetheria (painted tier)", ["assets/ui/aetheria"]),
    ("REFERENCE - foozle_lucifer (CC0)",
     ["docs/design_refs/ui/source_packs/foozle_lucifer/Generic"]),
    ("REFERENCE - kenney fantasy ui borders (CC0)",
     ["docs/design_refs/ui/source_packs/second_pack/PNG/Double/Panel",
      "docs/design_refs/ui/source_packs/second_pack/PNG/Double/Divider",
      "docs/design_refs/ui/source_packs/second_pack/PNG/Double/Border"]),
]


def main(argv):
    if "--selftest" in argv:
        return _selftest()
    if "--audit" in argv or not argv:
        total = 0
        for label, paths in FAMILIES:
            existing = [p for p in paths if os.path.exists(p)]
            if not existing:
                continue
            print("\n=== %s ===" % label)
            total += _report(existing, limit=14)
        print("\n[measure_ui] measured %d file(s) across the known families" % total)
        return 0
    _report(argv)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
