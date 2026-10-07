#!/usr/bin/env python3
"""Measure produced art against the Aetheria Visual DNA (`style/aetheria_style.yaml`).

  style_check.py sheet <sheet.png> [--cell 32x48] [--loops|--one-shot]
  style_check.py ui-surface <png> [--interior x0,y0,x1,y1]
  style_check.py icons <png> [<png> ...]
  style_check.py frame <capture.png> [--idle]

Every check prints one JSON report and exits non-zero when a rule fails, so the pipeline (and a
reviewer) gets the same verdict. A rule the script cannot measure stays `review: manual` in the
YAML and is NOT pretended here.
"""
import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "style"))

import metrics  # noqa: E402
import style  # noqa: E402


def _rule(report, name, value, ok, limit):
    report["rules"].append({"rule": name, "value": value, "limit": limit, "pass": bool(ok)})
    if not ok:
        report["pass"] = False


def check_sheet(path, cell, loops):
    s = style.load()
    ch = s["character"]
    ink = style.role("ink", s)
    sheet = metrics.load_rgba(path)
    cw, chh = cell
    report = {"check": "sheet", "file": path, "pass": True, "rules": [], "frames": []}
    if sheet.width % cw or sheet.height % chh:
        _rule(report, "grid", "%dx%d" % sheet.size, False, "multiple of %dx%d" % cell)
        return report
    grid = metrics.frames_of(sheet, cw, chh)
    lo_h, hi_h = ch["height_px"]
    worst = {"colours": 0, "orphan_share": 0.0, "outline_coverage": 1.0}
    heights = []
    for r, row in enumerate(grid):
        for c, cell_img in enumerate(row):
            m = metrics.sprite_metrics(cell_img, ink)
            m["row"], m["col"] = r, c
            report["frames"].append(m)
            heights.append(m["height_px"])
            worst["colours"] = max(worst["colours"], m["colours"])
            worst["orphan_share"] = max(worst["orphan_share"], m["orphan_share"])
            worst["outline_coverage"] = min(worst["outline_coverage"], m["outline_coverage"])
    standing = heights if "meditate" not in os.path.basename(path) else []
    if standing:
        _rule(report, "height_px", [min(standing), max(standing)],
              min(standing) >= lo_h - 2 and max(standing) <= hi_h, ch["height_px"])
    _rule(report, "max_colours_per_frame", worst["colours"],
          worst["colours"] <= ch["max_colours_per_frame"], ch["max_colours_per_frame"])
    _rule(report, "orphan_pixel_share", round(worst["orphan_share"], 4),
          worst["orphan_share"] <= ch["orphan_pixel_share_max"], ch["orphan_pixel_share_max"])
    cov_min = s["outline"]["sprite_outline_coverage_min"]
    _rule(report, "outline_coverage", round(worst["outline_coverage"], 4),
          worst["outline_coverage"] >= cov_min, cov_min)
    # Motion: adjacent frames differ (L-029) and facings differ.
    still = []
    for r, row in enumerate(grid):
        last = len(row) if loops else len(row) - 1
        for f in range(last if len(row) > 1 else 0):
            d = metrics.frame_difference(row[f], row[(f + 1) % len(row)])
            if d < 2:
                still.append("row%d:%d->%d" % (r, f, (f + 1) % len(row)))
    _rule(report, "every_frame_moves", still or "ok", not still, ">= 2px between frames")
    same_facing = []
    for a in range(len(grid)):
        for b in range(a + 1, len(grid)):
            if metrics.frame_difference(grid[a][0], grid[b][0]) == 0:
                same_facing.append("%d=%d" % (a, b))
    _rule(report, "facings_differ", same_facing or "ok", not same_facing, "every row distinct")
    report["frames"] = len(report["frames"])
    return report


def _gold_like(p, gold_family):
    lab = style.to_lab(p)
    for g in gold_family:
        if sum((lab[i] - g[i]) ** 2 for i in range(3)) ** 0.5 <= 18:
            return True
    return False


def check_ui_surface(path, interior):
    s = style.load()
    ui = s["ui"]
    img = metrics.load_rgba(path)
    gold_family = [style.to_lab(style.role(r, s)) for r in ("gold", "gold_light", "gold_shadow")]
    data = list(img.getdata())
    opaque = [p for p in data if p[3] > 0]
    gold = sum(1 for p in opaque if _gold_like(p, gold_family))
    report = {"check": "ui-surface", "file": path, "pass": True, "rules": []}
    share = gold / max(1, len(opaque))
    _rule(report, "ornament_share", round(share, 4), share <= ui["ornament_share_max"],
          ui["ornament_share_max"])
    if interior:
        x0, y0, x1, y1 = interior
        alphas = [img.getpixel((x, y))[3] / 255.0
                  for y in range(y0, y1, 2) for x in range(x0, x1, 2)]
        mean_a = sum(alphas) / max(1, len(alphas))
        lo, hi = ui["translucency"]
        _rule(report, "interior_alpha", round(mean_a, 3), lo <= mean_a <= hi, ui["translucency"])
    return report


def check_icons(paths):
    s = style.load()
    ic = s["icons"]
    report = {"check": "icons", "pass": True, "rules": [], "icons": {}}
    lo, hi = ic["subject_fill_share"]
    for p in paths:
        img = metrics.load_rgba(p)
        data = list(img.getdata())
        colours = len(set(px[:3] for px in data if px[3] > 0))
        name = os.path.basename(p)
        report["icons"][name] = {"size": list(img.size), "colours": colours}
        _rule(report, name + ":size", list(img.size), list(img.size) == ic["size"], ic["size"])
        _rule(report, name + ":colours", colours, colours <= ic["max_colours"], ic["max_colours"])
    return report


def check_frame(path, idle):
    s = style.load()
    img = metrics.load_rgba(path).convert("RGB")
    px = metrics.rgb_pixels(img.reduce(2))
    report = {"check": "frame", "file": path, "pass": True, "rules": []}
    warm = metrics.warm_share(px)
    t = s["temperature"]
    _rule(report, "warm_share", round(warm, 4),
          t["warm_pixel_share_min"] <= warm <= t["warm_pixel_share_max"],
          [t["warm_pixel_share_min"], t["warm_pixel_share_max"]])
    if idle:
        glow = metrics.glow_share(px)
        _rule(report, "glow_share_idle", round(glow, 4),
              glow <= s["vfx"]["emissive_share_idle_max"], s["vfx"]["emissive_share_idle_max"])
    edges = metrics.edge_density(img)
    lo, hi = s["world"]["edge_density_target"]
    _rule(report, "edge_density", round(edges, 4), lo <= edges <= hi, [lo, hi])
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("sheet")
    a.add_argument("path")
    a.add_argument("--cell", default="32x48")
    a.add_argument("--one-shot", action="store_true")
    b = sub.add_parser("ui-surface")
    b.add_argument("path")
    b.add_argument("--interior", default="")
    c = sub.add_parser("icons")
    c.add_argument("paths", nargs="+")
    d = sub.add_parser("frame")
    d.add_argument("path")
    d.add_argument("--idle", action="store_true")
    args = ap.parse_args(argv)
    if args.cmd == "sheet":
        cw, chh = (int(v) for v in args.cell.split("x"))
        report = check_sheet(args.path, (cw, chh), not args.one_shot)
    elif args.cmd == "ui-surface":
        box = tuple(int(v) for v in args.interior.split(",")) if args.interior else None
        report = check_ui_surface(args.path, box)
    elif args.cmd == "icons":
        report = check_icons(args.paths)
    else:
        report = check_frame(args.path, args.idle)
    print(json.dumps(report, indent=1, ensure_ascii=False))
    return 0 if report["pass"] else 1


if __name__ == "__main__":
    sys.exit(main())
