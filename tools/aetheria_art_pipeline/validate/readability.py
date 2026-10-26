#!/usr/bin/env python3
"""Player readability numbers for the committed 32x48 sheets (CHARACTER_ART_BIBLE §4, §6b).

  readability.py <actor> [<actor> ...] [--board <png>] [--json <file>] [--ascii [--frame N]]

"Reads better" is a claim about pixels, so this measures the pixels the game loads, classified
back to the actor's own ramps (every opaque sprite pixel is one ramp tone or the ink):

  face      the skin pixels in the head band: how many, how many ramp tones (one tone is a flat
            ball, two or more is a modelled face), eye pixels, the face's own width
  hands     per facing, over idle + walk: the frames with a skin pixel within 1 px of the rig's
            own palm or rear-palm anchor (data/characters/visual/anchors) — the hand where the rig
            holds it, so neck or chin skin cannot stand in for it
  silhouette  opaque area, the width profile and the hem (widest row of the 8 above the ground
            line); the value range of the figure (luma p5/p95)
            and its gap to the moss floor it stands on most of the game
  masses    mean luma of the hair mass and of the garment above / below the sash — the DNA
            asks hair and robe to separate by value (character.value_separation_min)

With two or more actors it also prints, per facing, how many silhouette pixels differ between
each pair (alpha masks of idle frame 0) and the colour distance of their garment masses: the
"second look" must differ in SILHOUETTE and in PALETTE, not only in a recolour.

`--board` writes a review board: idle frame 0 of every facing at 1x on the moss floor (how a
player sees it) and at 8x (how an animator checks it). `--before <git rev>` also reads that
revision's sheets and anchors: the numbers of both are printed and the board puts each actor's
BEFORE row above its row now; `--export-before <dir>` instead writes that revision's idle and
walk sheets to `<dir>` (the `before_dir` of `tools/capture_player_looks.gd`).
A build-time tool: nothing ships.
"""
import argparse
import io
import json
import os
import re
import subprocess
import sys

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(PIPE))
sys.path.insert(0, PIPE)
sys.path.insert(0, os.path.join(PIPE, "style"))

import build  # noqa: E402
import style  # noqa: E402

DIRECTIONS = ("down", "up", "left", "right")
HEAD_BAND = 15          # rows from the crown: head + hair top (style character.head_px max - 1)
GARMENT = ("robe", "robe_inner", "accent", "trim")
CELL = (32, 48)
HEM_ROWS = 8            # rows above the ground line the hem is measured over


def _luma(rgb):
    r, g, b = rgb
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255.0


def _lookup(spec):
    """rgb -> material name (first owner wins in MATERIAL_ORDER; ink is 'ink')."""
    out = {tuple(spec["style"]["ink"]): "ink"}
    for name in build.MATERIAL_ORDER:
        m = spec["materials"].get(name)
        if not m:
            continue
        for tone, rgb in enumerate(m["ramp"]):
            out.setdefault(tuple(rgb), name)
    return out


def _tones(spec, name):
    return {tuple(rgb): i for i, rgb in enumerate(spec["materials"][name]["ramp"])}


def _read(rel, rev=None):
    """A repository file's bytes, from the working tree or from git revision `rev`."""
    if rev:
        return subprocess.check_output(["git", "-C", ROOT, "show", "%s:%s" % (rev, rel)])
    with open(os.path.join(ROOT, rel), "rb") as f:
        return f.read()


def _sheet(spec, anim, rev=None):
    rel = "assets/sprites/characters/%s_%s.png" % (spec["outputs"]["sheet_prefix"], anim)
    return Image.open(io.BytesIO(_read(rel, rev))).convert("RGBA")


def _hand_anchors(spec, anim, rev=None):
    """[direction][frame] -> the palm and rear-palm anchors as CELL pixels (the inverse of
    art_sheet.write_anchor_resource: feet origin, pixel centre)."""
    rel = "data/characters/visual/anchors/%s.tres" % spec["outputs"]["anchors"]
    text = _read(rel, rev).decode("utf-8")
    feet = spec["camera"]["gameplay"]["feet_row"]
    tracks = []
    for point in ("palm", "rear_palm"):
        m = re.search(r'"%s/%s": PackedVector2Array\(([^)]*)\)' % (anim, point), text)
        v = [float(s) for s in m.group(1).split(",")] if m else []
        tracks.append([(int(v[i] - 0.5 + CELL[0] / 2.0), int(v[i + 1] - 0.5 + feet))
                       for i in range(0, len(v), 2)])
    count = max(len(t) for t in tracks) // len(DIRECTIONS)
    return [[[t[d * count + f] for t in tracks if t] for f in range(count)]
            for d in range(len(DIRECTIONS))]


def _cells(sheet):
    cw, ch = CELL
    return [[sheet.crop((c * cw, r * ch, (c + 1) * cw, (r + 1) * ch))
             for c in range(sheet.width // cw)] for r in range(sheet.height // ch)]


def _pixels(cell):
    w, h = cell.size
    data = list(cell.getdata())
    return [(x, y, data[y * w + x][:3]) for y in range(h) for x in range(w)
            if data[y * w + x][3] == 255]


def frame_numbers(spec, cell, hands_at=()):
    """`hands_at`: this frame's hand anchors (cell pixels); `hand_at_rig` is whether a skin
    pixel lies within 1 px of one of them."""
    look = _lookup(spec)
    skin_tones = _tones(spec, "skin")
    px = _pixels(cell)
    if not px:
        return {}
    top = min(y for _, y, _ in px)
    face = [(x, y, c) for x, y, c in px if look.get(c) == "skin" and y < top + HEAD_BAND]
    skin = {(x, y) for x, y, c in px if look.get(c) == "skin"}
    hand_at_rig = any((hx + dx, hy + dy) in skin for hx, hy in hands_at
                      for dx in (-1, 0, 1) for dy in (-1, 0, 1))
    feet = spec["camera"]["gameplay"]["feet_row"]
    # an eye is a dark pixel set INSIDE the face: no air around it (the ink outline at the
    # cheek's edge always touches air) and skin on BOTH sides of it (the seam of ink between the
    # jaw and a lock has hair on one side; so does an eye on the edge of a curtain bang)
    at = {(x, y): c for x, y, c in px}
    eyes = [(x, y) for x, y, c in px if look.get(c) in ("ink", "eye") and y < top + HEAD_BAND
            and all((x + dx, y + dy) in at for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            and all(look.get(at[(x + dx, y)]) == "skin" for dx in (-1, 1))]
    lumas = sorted(_luma(c) for _, _, c in px if look.get(c) != "ink")
    rows = {}
    for x, y, _ in px:
        lo, hi = rows.get(y, (x, x))
        rows[y] = (min(lo, x), max(hi, x))

    def mean(names, band=None):
        sel = [_luma(c) for x, y, c in px if look.get(c) in names
               and (band is None or band(y))]
        return round(sum(sel) / len(sel), 3) if sel else None

    sash_rows = [y for _, y, c in px if look.get(c) == "sash"]
    sash = (min(sash_rows) + max(sash_rows)) / 2.0 if sash_rows else top + 24
    pct = (lambda q: round(lumas[min(len(lumas) - 1, int(q * len(lumas)))], 3)) if lumas \
        else (lambda q: None)
    return {
        "opaque_px": len(px),
        "height_px": max(y for _, y, _ in px) - top + 1,
        "max_width_px": max(hi - lo + 1 for lo, hi in rows.values()),
        "face_px": len(face),
        "face_tones": len(set(skin_tones.get(c) for _, _, c in face)),
        "face_width_px": (max(x for x, _, _ in face) - min(x for x, _, _ in face) + 1)
        if face else 0,
        "eye_px": len(eyes),
        "eye_xy": sorted(eyes),
        "face_x": [min(x for x, _, _ in face), max(x for x, _, _ in face)] if face else [],
        "hand_at_rig": hand_at_rig,
        "hem_px": max((hi - lo + 1 for y, (lo, hi) in rows.items()
                       if feet - HEM_ROWS <= y <= feet), default=0),
        "luma_p05": pct(0.05),
        "luma_p95": pct(0.95),
        "hair_luma": mean(("hair",)),
        "upper_garment_luma": mean(GARMENT, lambda y: y < sash),
        "lower_garment_luma": mean(GARMENT, lambda y: y > sash),
    }


def actor_numbers(actor_id, rev=None):
    spec = build.resolve(actor_id)
    moss = _luma(style.role("moss", style.load()))
    out = {"actor": actor_id, "rev": rev or "working tree", "facings": {}}
    idle = _cells(_sheet(spec, "idle", rev))
    walk = _cells(_sheet(spec, "walk", rev))
    at = {anim: _hand_anchors(spec, anim, rev) for anim in ("idle", "walk")}
    for r, d in enumerate(DIRECTIONS):
        f0 = frame_numbers(spec, idle[r][0], at["idle"][r][0])
        shown = [frame_numbers(spec, c, at[anim][r][f])["hand_at_rig"]
                 for anim, cells in (("idle", idle[r]), ("walk", walk[r]))
                 for f, c in enumerate(cells)]
        f0["hand_frames_shown"] = "%d/%d" % (sum(shown), len(shown))
        body = [v for v in (f0["upper_garment_luma"], f0["lower_garment_luma"]) if v is not None]
        f0["floor_gap"] = round(abs(sum(body) / len(body) - moss), 3) if body else None
        if f0["hair_luma"] is not None and body:
            f0["hair_robe_gap"] = round(abs(f0["hair_luma"] - max(body)), 3)
        out["facings"][d] = f0
    return out, spec, idle


def _mask(cell):
    return [a == 255 for (_, _, _, a) in cell.getdata()]


def _garment_lab(spec, cell):
    look = _lookup(spec)
    sel = [c for _, _, c in _pixels(cell) if look.get(c) in GARMENT + ("sash",)]
    if not sel:
        return None
    labs = [style.to_lab(c) for c in sel]
    return [sum(l[i] for l in labs) / len(labs) for i in range(3)]


def compare(a, b):
    """Per facing: silhouette pixels that differ, the hem widths, and the garment-mass Lab
    distance."""
    out = {}
    (na, sa, ia), (nb, sb, ib) = a, b
    for r, d in enumerate(DIRECTIONS):
        ma, mb = _mask(ia[r][0]), _mask(ib[r][0])
        la, lb = _garment_lab(sa, ia[r][0]), _garment_lab(sb, ib[r][0])
        out[d] = {"silhouette_diff_px": sum(1 for p, q in zip(ma, mb) if p != q),
                  "hem_px": [na["facings"][d]["hem_px"], nb["facings"][d]["hem_px"]],
                  "garment_lab_distance": round(sum((la[i] - lb[i]) ** 2
                                                    for i in range(3)) ** 0.5, 1)
                  if la and lb else None}
    return out


def ascii_head(spec, cell, rows=20):
    """The top `rows` rows of a cell as material letters (ink '#', skin by tone 'abcd' deep to
    light, hair 'h', '.' air) — a face read in a terminal, pixel by pixel."""
    look = _lookup(spec)
    skin = _tones(spec, "skin")
    w, _ = cell.size
    data = list(cell.getdata())
    top = next(i // w for i, p in enumerate(data) if p[3] == 255)
    out = []
    for y in range(top, top + rows):
        line = ""
        for x in range(w):
            p = data[y * w + x]
            if p[3] != 255:
                line += "."
                continue
            name = look.get(p[:3], "?")
            line += "#" if name in ("ink", "eye") else "abcd"[skin[p[:3]]] if name == "skin" \
                else name[0]
        out.append(line)
    return "\n".join(out)


def board(results, path, scale=8):
    """`results` rows top to bottom (with `--before`: each actor's before row, then now)."""
    moss = tuple(style.role("moss", style.load())) + (255,)
    cw, ch = CELL
    pad = 6
    row_h = ch * scale + pad
    width = len(DIRECTIONS) * (cw + pad + cw * scale + pad) + pad
    im = Image.new("RGBA", (width, row_h * len(results) + pad), (30, 30, 30, 255))
    for i, (_, _, idle) in enumerate(results):
        x = pad
        y = pad + i * row_h
        for r in range(len(DIRECTIONS)):
            cell = Image.new("RGBA", CELL, moss)
            cell.alpha_composite(idle[r][0])
            im.alpha_composite(cell, (x, y))
            x += cw + pad
            im.alpha_composite(cell.resize((cw * scale, ch * scale), Image.NEAREST), (x, y))
            x += cw * scale + pad
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    im.save(path)
    return path


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("actors", nargs="+")
    ap.add_argument("--board", default="")
    ap.add_argument("--json", default="")
    ap.add_argument("--ascii", action="store_true", help="print each look's heads, idle frame 0")
    ap.add_argument("--frame", type=int, default=0, help="the idle frame --ascii prints")
    ap.add_argument("--before", default="", help="git revision to compare the sheets against")
    ap.add_argument("--export-before", default="",
                    help="write the --before revision's idle/walk sheets to this folder (the "
                         "before_dir of tools/capture_player_looks.gd)")
    args = ap.parse_args(argv)
    if args.export_before:
        if not args.before:
            ap.error("--export-before needs --before <rev>")
        os.makedirs(args.export_before, exist_ok=True)
        for actor in args.actors:
            prefix = build.resolve(actor)["outputs"]["sheet_prefix"]
            for anim in ("idle", "walk"):
                name = "%s_%s.png" % (prefix, anim)
                with open(os.path.join(args.export_before, name), "wb") as f:
                    f.write(_read("assets/sprites/characters/" + name, args.before))
                print(os.path.join(args.export_before, name))
        return 0
    results = [actor_numbers(a) for a in args.actors]
    before = [actor_numbers(a, args.before) for a in args.actors] if args.before else []
    if args.ascii:
        for numbers, spec, idle in results:
            for r, d in enumerate(DIRECTIONS):
                print("%s %s %d\n%s\n" % (numbers["actor"], d, args.frame,
                                          ascii_head(spec, idle[r][args.frame])))
        return 0
    report = {"actors": [r[0] for r in results], "pairs": {}}
    for i in range(len(results)):
        for j in range(i + 1, len(results)):
            key = "%s~%s" % (args.actors[i], args.actors[j])
            report["pairs"][key] = compare(results[i], results[j])
    if before:
        report["before"] = {"rev": args.before, "actors": [r[0] for r in before], "pairs": {}}
        for i in range(len(before)):
            for j in range(i + 1, len(before)):
                key = "%s~%s" % (args.actors[i], args.actors[j])
                report["before"]["pairs"][key] = compare(before[i], before[j])
    text = json.dumps(report, indent=1, ensure_ascii=False)
    print(text)
    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as f:
            f.write(text + "\n")
    if args.board:
        rows = [r for pair in zip(before, results) for r in pair] if before else results
        print(board(rows, args.board))
    return 0


if __name__ == "__main__":
    sys.exit(main())
