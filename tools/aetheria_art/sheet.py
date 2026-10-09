"""Sheet assembly, motion verification and anchor export.

A sheet is a GRID: one ROW per facing in DOWN, UP, LEFT, RIGHT order (the order of
`CharacterVisualProfileData.Direction`), one COLUMN per animation frame. The runtime derives the
frame count from the texture width, so art and data cannot disagree.
"""
import os

from . import raster

DIRECTIONS = ("down", "up", "left", "right")


def assemble(cells):
    """`cells[row][col]` -> one sheet canvas."""
    cw, ch = raster.size(cells[0][0])
    sheet = raster.blank(cw * len(cells[0]), ch * len(cells))
    for row, frames in enumerate(cells):
        for col, cell in enumerate(frames):
            raster.blit(sheet, cell, col * cw, row * ch)
    return sheet


def verify_animates(label, cells, loops=True, min_changed=2):
    """Fail LOUD on art that would animate an index over a motionless figure (L-029).

    Every ADJACENT pair of frames must differ by at least `min_changed` pixels — a 1px
    difference is invisible at 1x and is exactly the "walk that animated nothing" D-046 shipped.
    A one-shot action may end where it began, so `loops=False` skips only the wrap pair.
    Every facing must also differ, or the character does not visibly turn.
    """
    frames = len(cells[0])
    for row, cols in enumerate(cells):
        last = frames if loops else frames - 1
        for f in range(last if frames > 1 else 0):
            nxt = (f + 1) % frames
            changed = _diff(cols[f], cols[nxt])
            if changed < min_changed:
                raise SystemExit(
                    "DEGENERATE ART: %s row %s frames %d->%d differ by %d px (< %d): the "
                    "animation would advance over a motionless figure"
                    % (label, DIRECTIONS[row], f, nxt, changed, min_changed))
    for a in range(len(cells)):
        for b in range(a + 1, len(cells)):
            if _diff(cells[a][0], cells[b][0]) == 0:
                raise SystemExit("DEGENERATE ART: %s rows %s and %s are identical - the figure "
                                 "would not visibly turn" % (label, DIRECTIONS[a], DIRECTIONS[b]))


def _diff(a, b):
    n = 0
    for ra, rb in zip(a, b):
        for ca, cb in zip(ra, rb):
            if ca != cb:
                n += 1
    return n


def write_prop_resource(path, prop_id, texture_rel, origin, footprint, footprint_round=False,
                        sways=False):
    """Write a `PropData` .tres — the ONE writer of prop data, for the Blender pipeline's props and
    this generator's alike (D-063): the texture, the ORIGIN (the texture pixel a scene stands on
    the prop's ground line), and the solid FOOTPRINT in world px relative to that origin (zero
    size = walk-through); `footprint_round` makes the body the ellipse inscribed in it."""
    body = (
        '[gd_resource type="Resource" script_class="PropData" load_steps=3 format=3]\n\n'
        '[ext_resource type="Script" path="res://src/data/world/prop_data.gd" id="1_prop"]\n'
        '[ext_resource type="Texture2D" path="res://%s" id="2_tex"]\n\n'
        "[resource]\n"
        'script = ExtResource("1_prop")\n'
        'id = &"%s"\n'
        'texture = ExtResource("2_tex")\n'
        "origin = Vector2(%d, %d)\n"
        "footprint = Rect2(%g, %g, %g, %g)\n"
        "%s"
        "sways = %s\n" % (texture_rel, prop_id, round(origin[0]), round(origin[1]),
                           footprint[0], footprint[1], footprint[2], footprint[3],
                           "footprint_round = true\n" if footprint_round else "",
                           "true" if sways else "false"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(body)


def write_anchor_resource(path, resource_id, cell_size, anchors, feet_row=None, depths=None):
    """Write a `CharacterAnchorData` .tres.

    `anchors[anim][point]` is a list over DIRECTIONS of per-frame (x, y) CELL-pixel positions.
    They are stored relative to the FEET ORIGIN the runtime anchors every sprite at (cell
    bottom-centre), so a VFX node can add them to the entity position directly, and at the
    pixel's CENTRE (+0.5) — so a point and its mirror are exactly symmetric about the body's
    axis instead of one pixel apart (the RIGHT row is the LEFT row mirrored). Keys are
    "anim/point"; each value is a PackedVector2Array ordered direction-major
    (direction * frames + frame), which the runtime indexes without any per-frame allocation.

    `depths[anim][point]` (optional) is the same layout of per-frame DEPTHS in px — how far in
    front of the body's core a point is along the camera's view axis (positive = toward the
    viewer). Written as PackedFloat32Array tracks under `depths`, only for points that carry one.
    """
    cw, ch = cell_size
    # The ground line inside the cell: the bottom edge unless the sheet stands its feet higher
    # (the Blender pipeline does, so a forward foot stays inside the cell; its profile then
    # carries anchor_offset.y = ch - feet_row and both agree on where the feet are).
    origin = ch if feet_row is None else feet_row
    lines = []
    for anim in sorted(anchors):
        for point in sorted(anchors[anim]):
            per_dir = anchors[anim][point]
            coords = []
            for frames in per_dir:
                for (x, y) in frames:
                    coords.append("%g, %g" % (x + 0.5 - cw / 2.0, y + 0.5 - origin))
            lines.append('"%s/%s": PackedVector2Array(%s)' % (anim, point, ", ".join(coords)))
    depth_lines = []
    for anim in sorted(depths or {}):
        for point in sorted(depths[anim]):
            values = [("%g" % round(float(d), 2)) for frames in depths[anim][point]
                      for d in frames]
            depth_lines.append('"%s/%s": PackedFloat32Array(%s)'
                               % (anim, point, ", ".join(values)))
    body = (
        '[gd_resource type="Resource" script_class="CharacterAnchorData" load_steps=2 format=3]\n\n'
        '[ext_resource type="Script" path="res://src/data/characters/character_anchor_data.gd" '
        'id="1_anchor"]\n\n'
        "[resource]\n"
        'script = ExtResource("1_anchor")\n'
        'id = &"%s"\n'
        "frame_size = Vector2i(%d, %d)\n"
        "points = {\n%s\n}\n" % (resource_id, cw, ch, ",\n".join(lines))
    )
    if depth_lines:
        body += "depths = {\n%s\n}\n" % ",\n".join(depth_lines)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(body)
