#!/usr/bin/env python3
"""Write a map layout's solid props into its scene (D-062 CP10), idempotently.

    python3 tools/aetheria_art_pipeline/world/sync_scene.py lac_ha src/gameplay/maps/hub_map.tscn

The layout YAML is the source of truth for WHERE a house or a tree stands; the scene holds the
nodes so the editor and the tests see them. This rewrites every `Prop_*` WorldProp under
`Visual/Decor` from the layout, removes the retired decor sprites, and drops grass-tuft sprites
the painted floor no longer has grass under (a tuft on paving or in water).
"""
import os
import re
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
PIPE = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(PIPE))
sys.path.insert(0, HERE)

import ground  # noqa: E402

PROP_SCRIPT = "res://src/gameplay/world/props/world_prop.gd"


def _blocks(text):
    head, *rest = re.split(r"\n(?=\[node |\[connection )", text)
    return head, rest


def _drop_unused_ext(text):
    """Remove every ext_resource no `ExtResource("id")` references any more (the retired tile
    set, a retired decor texture), so a synced scene carries no dead dependencies."""
    def used(match):
        rid = match.group(1)
        return match.group(0) if 'ExtResource("%s")' % rid in text else ""
    text = re.sub(r'\[ext_resource [^\]]*id="([^"]+)"\]\n', used, text)

    def used_sub(match):
        rid = match.group(1)
        return match.group(0) if 'SubResource("%s")' % rid in text else ""
    # a sub_resource block runs to the next blank line
    text = re.sub(r'\[sub_resource [^\]]*id="([^"]+)"\]\n(?:[^\n]+\n)*\n', used_sub, text)
    return re.sub(r'\[ext_resource [^\]]*id="([^"]+)"\]\n', used, text)


def _painted_ground(block, layout_id):
    """The scene's `Visual/Ground` as a PaintedGround bound to this layout's data (idempotent: a
    Ground already painted is rewritten the same way)."""
    if not re.match(r'\[node name="Ground" type="(TileMapLayer|Sprite2D)" parent="Visual"\]', block):
        return block
    return ('[node name="Ground" type="Sprite2D" parent="Visual"]\n'
            "z_index = -2\n"
            "texture_filter = 1\n"
            "centered = false\n"
            'script = ExtResource("p_ground")\n'
            'layout = ExtResource("p_layout")\n')


def sync(layout_id, scene_rel):
    with open(os.path.join(PIPE, "designs", "maps", layout_id + ".yaml"), encoding="utf-8") as f:
        L = yaml.safe_load(f)
    _, _, mat, (ox, oy, w, h) = ground.paint(os.path.join(PIPE, "designs", "maps",
                                                          layout_id + ".yaml"))
    scene = os.path.join(ROOT, scene_rel)
    with open(scene, encoding="utf-8") as f:
        text = f.read()
    head, blocks = _blocks(text)
    retire = set(L.get("retire_decor", []))
    kept = []
    for b in blocks:
        m = re.match(r'\[node name="([^"]+)"[^\]]*parent="([^"]*)"', b)
        if m:
            name, parent = m.groups()
            top = parent.split("/")
            if parent == "Visual/Decor" and (name.startswith("Prop_") or name in retire):
                continue
            if parent.startswith("Visual/Decor/") and (top[2].startswith("Prop_")
                                                       or top[2] in retire):
                continue
            if parent == "Visual/Decor" and name.startswith("Grass"):
                pos = re.search(r"\nposition = Vector2\(([-\d.]+), ([-\d.]+)\)", b)
                if pos:
                    x, y = int(float(pos.group(1))) - ox, int(float(pos.group(2))) - oy
                    if not (0 <= x < w and 0 <= y < h) or \
                            mat[y * w + x] not in (ground.GRASS, ground.FOREST):
                        continue
        kept.append(b)
    # the floor: a tiled Ground becomes the PaintedGround drawn from this layout
    kept = [_painted_ground(b, layout_id) for b in kept]
    # ext resources: the WorldProp script and each prop's data
    ext_ids = {}
    head = re.sub(r'\n\[ext_resource [^\]]*id="(p_[^"]+)"\]', "", head)
    lines = []
    lines.append('[ext_resource type="Script" path="res://src/gameplay/maps/painted_ground.gd" '
                 'id="p_ground"]')
    lines.append('[ext_resource type="Resource" path="res://data/maps/ground/%s_ground.tres" '
                 'id="p_layout"]' % layout_id)
    lines.append('[ext_resource type="Script" path="%s" id="p_script"]' % PROP_SCRIPT)
    for p in sorted({e["prop"] for e in L.get("props", [])}):
        ext_ids[p] = "p_%s" % p
        lines.append('[ext_resource type="Resource" path="res://data/world/props/%s.tres" '
                     'id="p_%s"]' % (p, p))
    first_sub = head.find("\n[sub_resource")
    insert_at = first_sub if first_sub >= 0 else len(head)
    head = head[:insert_at] + "\n" + "\n".join(lines) + head[insert_at:]
    # the props, right after the Decor node itself
    nodes = []
    for e in L.get("props", []):
        nodes.append('[node name="Prop_%s" type="StaticBody2D" parent="Visual/Decor"]\n'
                     "position = Vector2(%g, %g)\n"
                     'script = ExtResource("p_script")\n'
                     'prop = ExtResource("%s")\n' % (e["name"], e["at"][0], e["at"][1],
                                                     ext_ids[e["prop"]]))
    out, placed = [], False
    for b in kept:
        out.append(b)
        if not placed and re.match(r'\[node name="Decor" type="Node2D" parent="Visual"\]', b):
            out.extend(n.rstrip("\n") + "\n" for n in nodes)
            placed = True
    text = head + "\n" + "\n".join(x.rstrip("\n") + "\n" for x in out)
    text = _drop_unused_ext(text)
    count = text.count("[ext_resource") + text.count("[sub_resource")
    text = re.sub(r"load_steps=\d+", "load_steps=%d" % (count + 1), text, count=1)
    with open(scene, "w", encoding="utf-8") as f:
        f.write(text)
    return len(nodes)


if __name__ == "__main__":
    print("placed", sync(sys.argv[1], sys.argv[2]), "props")
