"""Blender side of the icon set (D-062 CP2). Runs INSIDE Blender 5.2.

    render_icons(spec_path)   every icon in work/icons/spec.json -> ID / light / depth passes
                              (+ a beauty preview) in work/icons/

The same material graph, canonical light and pass modes as the characters
(`build_actor.make_material`, `setup_lights`, `set_mode`), an orthographic camera at the icon
elevation: an icon is lit and adapted exactly like a sprite, so the two read as one language.
"""
import json
import math
import os

import bpy
from mathutils import Vector

import build_actor
import icons as icon_model

PASSES = ("id", "light", "depth")


def _build(spec, coll):
    bands = spec["style"]["pixel"]["light_bands"]
    materials = {name: build_actor.make_material(name, m, bands)
                 for name, m in spec["materials"].items()}
    for part in icon_model.build(spec):
        me = bpy.data.meshes.new(part["name"])
        me.from_pydata([tuple(v) for v in part["verts"]], [], [tuple(f) for f in part["faces"]])
        me.update()
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = part["smooth"]
        me.materials.append(materials[part["material"]])
        ob = bpy.data.objects.new(part["name"], me)
        coll.objects.link(ob)


FILL = 0.84          # the subject's larger extent as a share of the cell (style: 0.35-0.80
                     # of the AREA; ~0.84 of the extent lands a diagonal subject inside it)


def _frame(coll, el):
    """Auto-framing: the subject's bounds projected on the picture plane -> the camera centre
    and ortho scale that make its larger extent FILL of the cell. Every icon is then drawn at
    the same visual weight, whatever its real size (a pill and a sword read as one set)."""
    right = Vector((1.0, 0.0, 0.0))
    up = Vector((0.0, math.sin(el), math.cos(el)))
    us, vs = [], []
    for ob in coll.objects:
        if ob.type != "MESH":
            continue
        for v in ob.data.vertices:
            co = ob.matrix_world @ v.co
            us.append(co.dot(right))
            vs.append(co.dot(up))
    cu, cv = (min(us) + max(us)) / 2.0, (min(vs) + max(vs)) / 2.0
    extent = max(max(us) - min(us), max(vs) - min(vs))
    return right * cu + up * cv, extent / FILL


def _camera(coll):
    el = math.radians(icon_model.ICON_ELEVATION_DEG)
    fwd = Vector((0.0, math.cos(el), -math.sin(el)))
    look_at, scale = _frame(coll, el)
    data = bpy.data.cameras.new("AE_cam_icon")
    data.type = "ORTHO"
    data.ortho_scale = scale
    data.clip_start = 1.0
    data.clip_end = 400.0
    cam = bpy.data.objects.new("AE_cam_icon", data)
    cam.location = look_at - fwd * build_actor.CAM_DISTANCE
    cam.rotation_euler = (math.radians(90.0 - icon_model.ICON_ELEVATION_DEG), 0.0, 0.0)
    coll.objects.link(cam)
    return cam


def render_icons(spec_path, only=None):
    with open(spec_path, encoding="utf-8") as f:
        data = json.load(f)
    out_dir = os.path.dirname(spec_path)
    k = data["render_scale"]
    w, h = data["cell"]
    written = []
    for icon_id, spec in data["icons"].items():
        if only and icon_id not in only:
            continue
        build_actor.reset_scene()
        scene = bpy.context.scene
        coll = bpy.data.collections.new("AE_icon_" + icon_id)
        scene.collection.children.link(coll)
        _build(spec, coll)
        bpy.context.view_layer.update()
        scene.camera = _camera(coll)
        build_actor.setup_lights(spec, coll)
        build_actor.configure_render(scene, w * k, h * k, 1)
        for pas in PASSES:
            build_actor.set_mode(pas)
            scene.render.filepath = os.path.join(out_dir, "%s_%s.png" % (icon_id, pas))
            bpy.ops.render.render(write_still=True)
        world = data.get("world_cell")
        if world and icon_id.startswith("item_"):
            # the same subject, same framing, for the 16px cell it lies in on the ground
            build_actor.configure_render(scene, world[0] * k, world[1] * k, 1)
            for pas in PASSES:
                build_actor.set_mode(pas)
                scene.render.filepath = os.path.join(out_dir, "%s_w_%s.png" % (icon_id, pas))
                bpy.ops.render.render(write_still=True)
        # the beauty preview, for review only
        build_actor.set_mode("beauty")
        build_actor.configure_render(scene, 256, 256, 16)
        scene.render.filepath = os.path.join(out_dir, "%s_beauty.png" % icon_id)
        bpy.ops.render.render(write_still=True)
        written.append(icon_id)
    return written
