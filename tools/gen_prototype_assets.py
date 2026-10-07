#!/usr/bin/env python3
"""Generate Aetheria's project-owned pixel art (creatures, props, emblems).

HUMANOIDS AND ICONS ARE NOT HERE. Since D-062 every humanoid sheet (player, Thanh Vân robe, Lâm Nguyệt,
Thẩm Bất Kỳ, Kha Thản) comes from ONE source: the Blender pipeline in
`tools/aetheria_art_pipeline/` (one rig, one renderer, design data per actor). The stdlib
pose-drawn humanoid that lived here was retired with it, and so were the 16px item and skill
icons (now rendered from Blender by the same pipeline, `build.py icons`), so no two tools can
write the same file.

A BUILD-TIME TOOL. The game never imports it; it exists so every committed texture is
reproducible and provably self-made (`.kiro/steering/06-art-assets.md`). Standard library only
(zlib + struct): no imaging library is needed to rebuild the art. The drawing lives in the
`aetheria_art` package beside this file:

  raster.py      pixel primitives, outline, PNG writer
  sheet.py       sheet assembly, the "does it actually animate" verifier, anchor export
  beast.py       Vụ Lang, the pose-driven 32x32 mist wolf
  props.py       world props (the moving ones padded for their sway), the training post,
                 sect emblems

Outputs:
  assets/sprites/enemies/mist_wolf_<anim>.png
  data/characters/visual/anchors/*.tres              per-frame anchor points (palm, core, jaw)
  assets/sprites/props/*.png, assets/sprites/sects/*.png, the training post

Run:  python3 tools/gen_prototype_assets.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from aetheria_art import beast, props, raster, sheet  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANCHOR_DIR = "data/characters/visual/anchors"


def _save(rel, px):
    raster.write_png(os.path.join(ROOT, rel), px)
    w, h = raster.size(px)
    print("wrote %s (%dx%d)" % (rel, w, h))


def gen_mist_wolf():
    anchors = {}
    for anim, (frames, loops, pose_fn) in beast.ANIMATIONS.items():
        cells, jaws, cores = [], [], []
        for direction in range(4):
            row, d_jaw, d_core = [], [], []
            for f in range(frames):
                p = pose_fn(f)
                px, jaw = beast.render_facing(direction, p)
                row.append(px)
                d_jaw.append(jaw)
                d_core.append(beast.core_point(direction, p))
            cells.append(row)
            jaws.append(d_jaw)
            cores.append(d_core)
        sheet.verify_animates("mist_wolf/%s" % anim, cells, loops=loops)
        _save("assets/sprites/enemies/mist_wolf_%s.png" % anim, sheet.assemble(cells))
        anchors[anim] = {"palm": jaws, "core": cores}
    # The wolf's striking point is its jaw. It is exported under the SAME name the cultivator
    # uses for its striking hand ("palm"), so a strike effect asks one question of any actor.
    sheet.write_anchor_resource(os.path.join(ROOT, ANCHOR_DIR, "mist_wolf_anchors.tres"),
                                "anchors_mist_wolf", (beast.W, beast.H), anchors)
    print("wrote %s/mist_wolf_anchors.tres" % ANCHOR_DIR)


def gen_props():
    props.gen_grass(ROOT)
    props.gen_banner(ROOT)
    props.gen_tree(ROOT)
    props.gen_lantern_post(ROOT)
    props.gen_mist(ROOT)
    props.gen_cultivation_landmarks(ROOT)
    props.gen_training_post(ROOT)
    props.gen_rock(ROOT)
    props.gen_planter(ROOT)
    props.gen_emblems(ROOT)
    props.gen_prototype_tileset(ROOT)


if __name__ == "__main__":
    gen_mist_wolf()
    gen_props()
    print("done")
