#!/usr/bin/env python3
"""Aetheria art pipeline — the system-Python side (D-062).

  build.py resolve <actor>         design + actor + style -> work/<actor>/spec.json (Blender reads this)
  build.py design-sheet <actor>    the pre-model design sheet, projected from the same geometry
  build.py pixel <actor>           Blender frames (work/<actor>/frames) -> sheets + anchors + portrait
  build.py all-pixel               every actor in designs/actors/
  build.py review <actor>          work/<actor>/review.png: turnaround, face, portrait, sheets
  build.py icons-spec              designs/icons.yaml -> work/icons/spec.json (Blender reads this)
  build.py icons                   Blender icon passes (work/icons) -> the 32x32 icons

Blender is a BUILD tool here, never a runtime dependency: it renders controlled passes into
work/ (gitignored); this side turns them into the committed 32x48 sheets.
"""
import argparse
import copy
import json
import os
import sys

import yaml

PIPE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(PIPE))
WORK = os.path.join(PIPE, "work")
sys.path.insert(0, os.path.join(PIPE, "style"))
sys.path.insert(0, os.path.join(PIPE, "model"))

import style  # noqa: E402

MATERIAL_ORDER = ["skin", "hair", "robe", "robe_inner", "trim", "sash", "trousers", "shoe",
                  "eye", "pin", "pendant", "accent", "lash", "sclera"]


def _deep_merge(base, over):
    out = copy.deepcopy(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = _deep_merge(out[k], v)
        else:
            out[k] = copy.deepcopy(v)
    return out


def actor_ids():
    return sorted(f[:-5] for f in os.listdir(os.path.join(PIPE, "designs", "actors"))
                  if f.endswith(".yaml"))


def resolve(actor_id):
    with open(os.path.join(PIPE, "designs", "actors", actor_id + ".yaml"), encoding="utf-8") as f:
        actor = yaml.safe_load(f)
    with open(os.path.join(PIPE, "designs", actor["extends"] + ".yaml"), encoding="utf-8") as f:
        base = yaml.safe_load(f)
    spec = _deep_merge(base, {k: v for k, v in actor.items()
                              if k not in ("materials", "extends", "outputs", "role")})
    st = style.load()
    mats = {}
    for name, m in actor["materials"].items():
        if name not in MATERIAL_ORDER:
            raise SystemExit("actor %s: unknown material '%s'" % (actor_id, name))
        ramp = [style.resolve_colour(c, st) for c in m["ramp"]]
        if len(ramp) != 4:
            raise SystemExit("actor %s: material %s needs a 4-tone ramp" % (actor_id, name))
        mats[name] = {"id": MATERIAL_ORDER.index(name) + 1, "ramp": ramp,
                      "priority": float(m.get("priority", 1.0)),
                      "highlight": bool(m.get("highlight", False)),
                      # a FLAT accent (sash, trim, jade) takes two tones at most — shadow and
                      # base — and no inner contour: a 1-2px accent shaded in four tones is noise
                      "flat": bool(m.get("flat", False)),
                      # the darkest tone this material may take in a sprite: skin is never
                      # shaded below its base (a shadowed face read as a beard or a mask)
                      "min_tone": int(m.get("min_tone", 0)),
                      # samples (of render_scale^2) a PRECIOUS material needs to own a pixel:
                      # an eye grazing two samples of a block is a smear, not an eye
                      "min_coverage": int(m.get("min_coverage", 2))}
    if "lash" not in mats:
        # closed eyes: a lid line in the skin's own deepest tone
        deep = mats["skin"]["ramp"][0]
        mats["lash"] = {"id": MATERIAL_ORDER.index("lash") + 1, "ramp": [deep] * 4,
                        "priority": 5.0, "highlight": False, "flat": True}
    if "sclera" not in mats:
        # the white of the eye (portrait LOD): a warm off-white, never pure paper-white
        mats["sclera"] = {"id": MATERIAL_ORDER.index("sclera") + 1,
                          "ramp": [style.hex_rgb(h) for h in ("#b9b2ab", "#dcd6cf",
                                                              "#efebe5", "#fbf9f5")],
                          "priority": 3.0, "highlight": False, "flat": True,
                          "min_tone": 0, "min_coverage": 2}
    spec["id"] = actor_id
    spec["role"] = actor.get("role", "")
    spec["materials"] = mats
    spec["outputs"] = actor["outputs"]
    spec["style"] = {
        "ink": style.role("ink", st),
        "contact_shadow": {"rgb": style.hex_rgb(st["lighting"]["contact_shadow"]["colour"]),
                           "alpha": st["lighting"]["contact_shadow"]["alpha"]},
        "lighting": st["lighting"],
        "pixel": st["pixel_adaptation"],
        "character": st["character"],
    }
    return spec


def resolve_icons():
    """designs/icons.yaml + style -> one spec per icon, in the SAME shape the character passes
    use (materials with ids and ramps, the style's ink, light and pixel rules)."""
    with open(os.path.join(PIPE, "designs", "icons.yaml"), encoding="utf-8") as f:
        data = yaml.safe_load(f)
    st = style.load()
    out = {"cell": data["cell"], "world_cell": data.get("world_cell"),
           "render_scale": data["render_scale"], "icons": {}}
    for icon_id, icon in data["icons"].items():
        mats = {}
        for i, (name, m) in enumerate(icon["materials"].items()):
            ramp = [style.resolve_colour(c, st) for c in m["ramp"]]
            mats[name] = {"id": i + 1, "ramp": ramp, "priority": float(m.get("priority", 1.0)),
                          "highlight": bool(m.get("highlight", False)),
                          "flat": bool(m.get("flat", False)), "min_tone": 0,
                          "min_coverage": int(m.get("min_coverage", 2))}
        out["icons"][icon_id] = {
            "id": icon_id, "kind": icon["kind"], "materials": mats,
            "style": {"ink": style.role("ink", st),
                      "contact_shadow": {"rgb": style.hex_rgb(
                          st["lighting"]["contact_shadow"]["colour"]),
                          "alpha": st["lighting"]["contact_shadow"]["alpha"]},
                      "lighting": st["lighting"], "pixel": st["pixel_adaptation"]},
        }
    return out


def write_icon_spec():
    out_dir = os.path.join(WORK, "icons")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "spec.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(resolve_icons(), f, indent=1, ensure_ascii=False)
    return path


def write_spec(actor_id):
    spec = resolve(actor_id)
    out_dir = os.path.join(WORK, actor_id)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "spec.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(spec, f, indent=1, ensure_ascii=False)
    return path


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("cmd", choices=["resolve", "design-sheet", "pixel", "all-pixel", "review",
                                       "icons-spec", "icons"])
    ap.add_argument("actor", nargs="?")
    args = ap.parse_args(argv)
    if args.cmd == "resolve":
        print(write_spec(args.actor))
    elif args.cmd == "design-sheet":
        sys.path.insert(0, os.path.join(PIPE, "designs"))
        import design_sheet
        print(design_sheet.render(resolve(args.actor), os.path.join(WORK, args.actor)))
    elif args.cmd == "pixel":
        sys.path.insert(0, os.path.join(PIPE, "pixel"))
        import pixelize
        pixelize.build_actor(resolve(args.actor), os.path.join(WORK, args.actor), ROOT)
    elif args.cmd == "icons-spec":
        print(write_icon_spec())
    elif args.cmd == "icons":
        sys.path.insert(0, os.path.join(PIPE, "pixel"))
        import pixelize
        for p in pixelize.build_icons(resolve_icons(), os.path.join(WORK, "icons"), ROOT):
            print("wrote", p)
        sys.path.insert(0, os.path.join(PIPE, "validate"))
        import review_sheet
        print(review_sheet.build_icons(resolve_icons(), ROOT, os.path.join(WORK, "icons")))
    elif args.cmd == "review":
        sys.path.insert(0, os.path.join(PIPE, "validate"))
        import review_sheet
        print(review_sheet.build(resolve(args.actor), ROOT, os.path.join(WORK, args.actor)))
    else:
        sys.path.insert(0, os.path.join(PIPE, "pixel"))
        import pixelize
        for a in actor_ids():
            pixelize.build_actor(resolve(a), os.path.join(WORK, a), ROOT)
    return 0


if __name__ == "__main__":
    sys.exit(main())
