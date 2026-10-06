#!/usr/bin/env python3
"""Generate Aetheria's project-owned pixel art (characters, creatures, props, emblems).

A BUILD-TIME TOOL. The game never imports it; it exists so every committed texture is
reproducible and provably self-made (`.kiro/steering/06-art-assets.md`). Standard library only
(zlib + struct): no imaging library is needed to rebuild the art. The drawing lives in the
`aetheria_art` package beside this file:

  raster.py      pixel primitives, outline, PNG writer
  sheet.py       sheet assembly, the "does it actually animate" verifier, anchor export
  cultivator.py  the pose-driven 32x48 humanoid (four archetype palettes)
  beast.py       Vụ Lang, the pose-driven 32x32 mist wolf
  props.py       world props (the moving ones padded for their sway), the training post,
                 sect emblems

Outputs:
  assets/sprites/characters/<archetype>_<anim>.png   grid: 4 facings x N frames
  assets/sprites/enemies/mist_wolf_<anim>.png
  data/characters/visual/anchors/*.tres              per-frame anchor points (palm, core, jaw)
  assets/sprites/props/*.png, assets/sprites/sects/*.png, the training post

Run:  python3 tools/gen_prototype_assets.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from aetheria_art import beast, cultivator, props, raster, sheet  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ANCHOR_DIR = "data/characters/visual/anchors"


def _save(rel, px):
    raster.write_png(os.path.join(ROOT, rel), px)
    w, h = raster.size(px)
    print("wrote %s (%dx%d)" % (rel, w, h))


def gen_cultivators():
    """Every archetype x every animation, plus ONE anchor file: all archetypes share the
    skeleton and the poses, and differ only in palette, so their anchors are identical."""
    anchors = {}
    for name, pal in cultivator.ARCHETYPES.items():
        for anim, (frames, loops, pose_fn) in cultivator.ANIMATIONS.items():
            cells = []
            palms, rears, cores = [], [], []
            for direction in range(4):
                row, d_palm, d_rear, d_core = [], [], [], []
                for f in range(frames):
                    p = pose_fn(f)
                    px, lead, rear = cultivator.render_facing(direction, pal, p)
                    row.append(px)
                    d_palm.append(lead)
                    d_rear.append(rear)
                    d_core.append(cultivator.core_point(direction, p))
                cells.append(row)
                palms.append(d_palm)
                rears.append(d_rear)
                cores.append(d_core)
            sheet.verify_animates("%s/%s" % (name, anim), cells, loops=loops)
            _save("assets/sprites/characters/%s_%s.png" % (name, anim), sheet.assemble(cells))
            anchors[anim] = {"palm": palms, "rear_palm": rears, "core": cores}
    sheet.write_anchor_resource(os.path.join(ROOT, ANCHOR_DIR, "cultivator_anchors.tres"),
                                "anchors_cultivator", (cultivator.W, cultivator.H), anchors)
    print("wrote %s/cultivator_anchors.tres" % ANCHOR_DIR)
    # The static fallback frame `player.tscn` shows before its profile resolves: the SAME
    # drawing as the idle sheet's first DOWN frame, so the two can never disagree.
    px, _, _ = cultivator.render_facing(0, cultivator.ARCHETYPES["player_proto"],
                                        cultivator.idle_pose(0))
    _save("assets/sprites/characters/player_proto.png", px)


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
    props.gen_training_post(ROOT)
    props.gen_rock(ROOT)
    props.gen_planter(ROOT)
    props.gen_emblems(ROOT)
    props.gen_prototype_tileset(ROOT)


if __name__ == "__main__":
    gen_cultivators()
    gen_mist_wolf()
    gen_props()
    print("done")
