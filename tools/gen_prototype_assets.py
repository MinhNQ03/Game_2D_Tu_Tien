#!/usr/bin/env python3
"""Generate Aetheria's project-owned pixel art (creatures, props, emblems).

HUMANOIDS AND ICONS ARE NOT HERE. Since D-062 every humanoid sheet (player, Thanh Vân robe, Lâm Nguyệt,
Thẩm Bất Kỳ, Kha Thản) comes from ONE source: the Blender pipeline in
`tools/aetheria_art_pipeline/` (one rig, one renderer, design data per actor). The stdlib
pose-drawn humanoid that lived here was retired with it, and so were the 16px item and skill
icons (now rendered from Blender by the same pipeline, `build.py icons`), and so were the
training post, the Lạc Hà spring and stele (Blender props) and the vein fissure (now painted
into the forest floor) — so no two tools can write the same file.

A BUILD-TIME TOOL. The game never imports it; it exists so every committed texture is
reproducible and provably self-made (`.kiro/steering/06-art-assets.md`). Standard library only
(zlib + struct): no imaging library is needed to rebuild the art. The drawing lives in the
`aetheria_art` package beside this file:

  raster.py      pixel primitives, outline, PNG writer
  sheet.py       sheet assembly, the "does it actually animate" verifier, anchor export
  beast.py       Vụ Lang, the pose-driven 32x32 mist wolf
  props.py       world decor (grass, banner, lantern, mist, rock, planter — the moving ones
                 padded for their sway), the prototype tileset,
                 sect emblems

Outputs:
  assets/sprites/enemies/mist_wolf_<anim>.png
  assets/sprites/pets/hoang_khuyen_<anim>.png
  data/characters/visual/anchors/*.tres              per-frame anchor points (palm, core, jaw)
  assets/sprites/props/*.png, assets/sprites/sects/*.png, the training post

Run:  python3 tools/gen_prototype_assets.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from aetheria_art import beast, props
from art_sheet import raster, sheet  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANCHOR_DIR = "data/characters/visual/anchors"


def _save(rel, px):
    raster.write_png(os.path.join(ROOT, rel), px)
    w, h = raster.size(px)
    print("wrote %s (%dx%d)" % (rel, w, h))


def gen_beast(name, out_dir, pal):
    """One pose-driven quadruped (`beast.py`) in palette/variant `pal`: three sheets + anchors."""
    anchors = {}
    for anim, (frames, loops, pose_fn) in beast.ANIMATIONS.items():
        cells, jaws, cores = [], [], []
        for direction in range(4):
            row, d_jaw, d_core = [], [], []
            for f in range(frames):
                p = pose_fn(f)
                px, jaw = beast.render_facing(direction, p, pal)
                row.append(px)
                d_jaw.append(jaw)
                d_core.append(beast.core_point(direction, p))
            cells.append(row)
            jaws.append(d_jaw)
            cores.append(d_core)
        sheet.verify_animates("%s/%s" % (name, anim), cells, loops=loops)
        _save("%s/%s_%s.png" % (out_dir, name, anim), sheet.assemble(cells))
        anchors[anim] = {"palm": jaws, "core": cores}
    # A beast's striking point is its jaw. It is exported under the SAME name the cultivator
    # uses for its striking hand ("palm"), so a strike effect asks one question of any actor.
    sheet.write_anchor_resource(os.path.join(ROOT, ANCHOR_DIR, "%s_anchors.tres" % name),
                                "anchors_%s" % name, (beast.W, beast.H), anchors)
    print("wrote %s/%s_anchors.tres" % (ANCHOR_DIR, name))


def gen_mist_wolf():
    gen_beast("mist_wolf", "assets/sprites/enemies", beast.PAL)


def gen_hoang_khuyen():
    gen_beast("hoang_khuyen", "assets/sprites/pets", beast.HOUND_PAL)


def gen_props():
    props.gen_grass(ROOT)
    props.gen_banner(ROOT)
    props.gen_lantern_post(ROOT)
    props.gen_mist(ROOT)
    props.gen_rock(ROOT)
    props.gen_planter(ROOT)
    props.gen_emblems(ROOT)
    props.gen_prototype_tileset(ROOT)


if __name__ == "__main__":
    gen_mist_wolf()
    gen_hoang_khuyen()
    gen_props()
    print("done")
