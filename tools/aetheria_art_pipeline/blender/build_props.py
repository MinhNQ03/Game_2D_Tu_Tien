"""Blender side of the world props (D-062 CP10). Runs INSIDE Blender 5.2.

    render_props(spec_path)   every prop in work/props/spec.json -> ID / light / depth passes,
                              a beauty preview and <prop>.json (the origin's pixel, the scale)

The canonical gameplay camera (30 degrees, orthographic) at the CHARACTER's pixel density, the
canonical light, and a ground plane that CATCHES the cast shadow: in the id pass it is the
reserved ground id, and the pixelizer turns its shadowed samples into the translucent shadow a
house or a tree throws on the floor. Same material graph as the characters.
"""
import json
import math
import os

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector

import build_actor
import props3d

PASSES = ("id", "light", "depth")
MARGIN_PX = 6


def _mesh(part, material, coll):
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
    me.materials.append(material)
    ob = bpy.data.objects.new(part["name"], me)
    coll.objects.link(ob)
    return ob


def _ground(spec, coll, ground_id, bands, size):
    mat = build_actor.make_material("ground", {"id": ground_id, "ramp": [(80, 80, 80)] * 4},
                                    bands)
    me = bpy.data.meshes.new("ground")
    s = size
    me.from_pydata([(-s, -s, 0), (s, -s, 0), (s, s, 0), (-s, s, 0)], [], [(0, 1, 2, 3)])
    me.materials.append(mat)
    ob = bpy.data.objects.new("ground", me)
    ob.visible_shadow = False
    coll.objects.link(ob)
    return ob


def _camera(coll, objects, cam_spec):
    el = math.radians(cam_spec["elevation_deg"])
    right = Vector((1.0, 0.0, 0.0))
    up = Vector((0.0, math.sin(el), math.cos(el)))
    fwd = Vector((0.0, math.cos(el), -math.sin(el)))
    us, vs = [], []
    for ob in objects:
        for v in ob.data.vertices:
            co = ob.matrix_world @ v.co
            us.append(co.dot(right))
            vs.append(co.dot(up))
    # the cast shadow falls up and to the right (light from the screen's upper left, toward
    # the viewer): leave room for it on those sides
    height = max(vs) - min(vs)
    u0, u1 = min(us), max(us) + height * 0.55
    v0, v1 = min(vs), max(vs) + height * 0.35
    units_per_px = float(cam_spec["ortho_units"]) / float(cam_spec["cell"][1])
    w_px = int(math.ceil((u1 - u0) / units_per_px)) + MARGIN_PX * 2
    h_px = int(math.ceil((v1 - v0) / units_per_px)) + MARGIN_PX * 2
    centre = right * ((u0 + u1) / 2.0) + up * ((v0 + v1) / 2.0)
    data = bpy.data.cameras.new("AE_cam_prop")
    data.type = "ORTHO"
    data.ortho_scale = max(w_px, h_px) * units_per_px
    data.clip_start = 1.0
    data.clip_end = 800.0
    cam = bpy.data.objects.new("AE_cam_prop", data)
    cam.location = centre - fwd * 300.0
    cam.rotation_euler = (math.radians(90.0 - cam_spec["elevation_deg"]), 0.0, 0.0)
    coll.objects.link(cam)
    return cam, w_px, h_px


def render_props(spec_path, only=None):
    with open(spec_path, encoding="utf-8") as f:
        data = json.load(f)
    out_dir = os.path.dirname(spec_path)
    k = data["render_scale"]
    cam_spec = data["camera"]
    done = []
    for prop_id, spec in data["props"].items():
        if only and prop_id not in only:
            continue
        build_actor.reset_scene()
        scene = bpy.context.scene
        coll = bpy.data.collections.new("AE_prop_" + prop_id)
        scene.collection.children.link(coll)
        bands = spec["style"]["pixel"]["light_bands"]
        mats = {n: build_actor.make_material(n, m, bands) for n, m in spec["materials"].items()}
        objects = [_mesh(p, mats[p["material"]], coll) for p in props3d.build(spec)]
        _ground(spec, coll, data["ground_id"], bands, 600.0)
        bpy.context.view_layer.update()
        cam, w_px, h_px = _camera(coll, objects, cam_spec)
        scene.camera = cam
        build_actor.setup_lights(spec, coll)
        build_actor.configure_render(scene, w_px * k, h_px * k, 1)
        # the depth pass's range is set for the character camera (120 units out); the prop
        # camera sits 300 out, so the depth window follows it
        for mat in bpy.data.materials:
            if mat.node_tree is None:
                continue
            for node in mat.node_tree.nodes:
                if node.type == "MAP_RANGE":
                    node.inputs["From Min"].default_value = 300.0 - 160.0
                    node.inputs["From Max"].default_value = 300.0 + 160.0
        for pas in PASSES:
            build_actor.set_mode(pas)
            scene.render.filepath = os.path.join(out_dir, "%s_%s.png" % (prop_id, pas))
            bpy.ops.render.render(write_still=True)
        origin = world_to_camera_view(scene, cam, Vector((0.0, 0.0, 0.0)))
        meta = {"width": w_px, "height": h_px,
                "origin": [origin.x * w_px, (1.0 - origin.y) * h_px],
                "px_per_unit": float(cam_spec["cell"][1]) / float(cam_spec["ortho_units"]),
                "ground_squash": math.sin(math.radians(cam_spec["elevation_deg"]))}
        with open(os.path.join(out_dir, prop_id + ".json"), "w") as f:
            json.dump(meta, f)
        build_actor.set_mode("beauty")
        build_actor.configure_render(scene, w_px * 2, h_px * 2, 16)
        scene.render.filepath = os.path.join(out_dir, "%s_beauty.png" % prop_id)
        bpy.ops.render.render(write_still=True)
        done.append(prop_id)
    return done
