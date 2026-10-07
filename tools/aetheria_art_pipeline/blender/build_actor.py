"""Blender side of the Aetheria art pipeline (D-062 CP4-CP7). Runs INSIDE Blender 5.2.

  build(spec_path)                       scene: armature, meshes, weights, materials, cameras,
                                         lights, and one real Action per animation
  render_frames(spec_path, anims=None)   controlled passes for the pixel adapter
  render_presentation(spec_path, out)    the beauty turnaround (design review / docs)
  build_and_render_all(actor)            all of the above for one actor (work/<actor>/)
  save(blend_path)

Run from the blender-pro MCP (`exec(open(this).read())` then call), or headless:
  blender -b -P tools/aetheria_art_pipeline/blender/cli.py -- <actor> [build|render|all]

WHY PASSES, NOT A BEAUTY RENDER. A 4x beauty render box-filtered to 32x48 is mud: every edge
becomes an in-between colour. The gameplay sprite is instead RECONSTRUCTED from three exact
1-sample passes — material ID (which material owns each sample, plus a back-face flag for the
sleeve lining), light (the canonical key/fill/rim as a scalar), depth (for inner contours) —
and `pixel/pixelize.py` picks each output pixel's material by weighted vote and its tone from the
actor's own 4-tone ramp. Blender owns form, light and motion; the palette stays authored.
"""
import json
import math
import os
import sys

import bpy
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Matrix, Quaternion, Vector

PIPE = os.path.dirname(os.path.dirname(os.path.abspath(__file__))) if "__file__" in globals() \
    else os.environ.get("AETHERIA_PIPE", "")
if os.path.join(PIPE, "model") not in sys.path:
    sys.path.insert(0, os.path.join(PIPE, "model"))

import humanoid  # noqa: E402
import motion  # noqa: E402

MODES = {"beauty": 0, "id": 1, "light": 2, "depth": 3}
NO_CAST = ("hair", "eye", "lash", "pin")
# Calibrated so a white surface square to the key reads ~1.0 in the light pass: the light bands
# in aetheria_style.yaml are then fractions of "fully lit", not of an arbitrary render level.
KEY_ENERGY = 2.6
DIRECTIONS = (("down", 0.0), ("up", 180.0), ("left", -90.0), ("right", 90.0))
# The facing that renders the MIRRs RIGHT rORED actions (motion.mirror): the striking hand stays the
# near one, so LEFT ieflected — strike height, VFX origin and anchors agree.
MIRRORED = ("left",)
MIRROR_SUFFIX = "_M"
DEPTH_SPAN = 40.0
CAM_DISTANCE = 120.0


def _srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def load_spec(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# --- scene -------------------------------------------------------------------------------------

def reset_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for coll in list(bpy.data.collections):
        bpy.data.collections.remove(coll)
    for block in (bpy.data.meshes, bpy.data.armatures, bpy.data.materials, bpy.data.actions,
                  bpy.data.cameras, bpy.data.lights, bpy.data.node_groups):
        for item in list(block):
            block.remove(item)


def _view3d_override():
    win = bpy.context.window_manager.windows[0]
    for area in win.screen.areas:
        if area.type == "VIEW_3D":
            region = next(r for r in area.regions if r.type == "WINDOW")
            return {"window": win, "area": area, "region": region, "screen": win.screen}
    return {"window": win, "screen": win.screen}


def mode_group():
    """ONE switch for every material: the Value node 'mode' (0 beauty, 1 id, 2 light, 3 depth)."""
    g = bpy.data.node_groups.get("AE_Mode")
    if g:
        return g
    g = bpy.data.node_groups.new("AE_Mode", "ShaderNodeTree")
    out = g.nodes.new("NodeGroupOutput")
    val = g.nodes.new("ShaderNodeValue")
    val.name = "mode"
    val.outputs[0].default_value = 0.0
    for i, key in enumerate(("is_id", "is_light", "is_depth")):
        g.interface.new_socket(key, in_out="OUTPUT", socket_type="NodeSocketFloat")
        cmp_ = g.nodes.new("ShaderNodeMath")
        cmp_.operation = "COMPARE"
        cmp_.inputs[1].default_value = float(i + 1)
        cmp_.inputs[2].default_value = 0.1
        g.links.new(val.outputs[0], cmp_.inputs[0])
        g.links.new(cmp_.outputs[0], out.inputs[i])
    return g


def set_mode(name):
    bpy.data.node_groups["AE_Mode"].nodes["mode"].outputs[0].default_value = float(MODES[name])


def _linear(rgb):
    return tuple(_srgb_to_linear(c) for c in rgb[:3]) + (1.0,)


def make_material(name, mspec, bands):
    """Every material is the same graph: lighting -> (beauty ramp | id | light | depth)."""
    mat = bpy.data.materials.new("AE_" + name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    N, L = nt.nodes.new, nt.links.new
    out = N("ShaderNodeOutputMaterial")
    diff = N("ShaderNodeBsdfDiffuse")
    diff.inputs["Color"].default_value = (1, 1, 1, 1)
    s2rgb = N("ShaderNodeShaderToRGB")
    L(diff.outputs[0], s2rgb.inputs[0])
    bw = N("ShaderNodeRGBToBW")
    L(s2rgb.outputs["Color"], bw.inputs[0])
    # beauty: the actor's 4-tone ramp, banded at the SAME thresholds the pixel adapter uses
    ramp = N("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "CONSTANT"
    tones = mspec["ramp"]
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = _linear(tones[0])
    els[1].position = bands[0]
    els[1].color = _linear(tones[1])
    e2 = els.new(bands[1])
    e2.color = _linear(tones[2])
    e3 = els.new(bands[2] if mspec.get("highlight") else 1.0)
    e3.color = _linear(tones[3] if mspec.get("highlight") else tones[2])
    L(bw.outputs[0], ramp.inputs[0])
    # id: R = material id * 20 (sRGB-exact), G = back-face flag (the sleeve lining)
    geo = N("ShaderNodeNewGeometry")
    comb = N("ShaderNodeCombineColor")
    comb.inputs[0].default_value = _srgb_to_linear(mspec["id"] * 20)
    L(geo.outputs["Backfacing"], comb.inputs[1])
    comb.inputs[2].default_value = 0.0
    # depth: camera view depth mapped near=1 .. far=0 around the subject
    cam = N("ShaderNodeCameraData")
    mr = N("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = CAM_DISTANCE - DEPTH_SPAN
    mr.inputs["From Max"].default_value = CAM_DISTANCE + DEPTH_SPAN
    mr.inputs["To Min"].default_value = 1.0
    mr.inputs["To Max"].default_value = 0.0
    L(cam.outputs["View Z Depth"], mr.inputs["Value"])
    grp = N("ShaderNodeGroup")
    grp.node_tree = mode_group()
    m1 = N("ShaderNodeMix")
    m1.data_type = "RGBA"
    L(grp.outputs["is_id"], m1.inputs["Factor"])
    L(ramp.outputs["Color"], m1.inputs[6])
    L(comb.outputs[0], m1.inputs[7])
    m2 = N("ShaderNodeMix")
    m2.data_type = "RGBA"
    L(grp.outputs["is_light"], m2.inputs["Factor"])
    L(m1.outputs[2], m2.inputs[6])
    L(bw.outputs[0], m2.inputs[7])
    m3 = N("ShaderNodeMix")
    m3.data_type = "RGBA"
    L(grp.outputs["is_depth"], m3.inputs["Factor"])
    L(m2.outputs[2], m3.inputs[6])
    L(mr.outputs["Result"], m3.inputs[7])
    emit = N("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.0
    L(m3.outputs[2], emit.inputs["Color"])
    L(emit.outputs[0], out.inputs["Surface"])
    return mat


def build_armature(spec, coll):
    arm = bpy.data.armatures.new("AE_rig")
    ob = bpy.data.objects.new("AE_rig", arm)
    coll.objects.link(ob)
    bpy.context.view_layer.objects.active = ob
    with bpy.context.temp_override(**_view3d_override(), active_object=ob, object=ob):
        bpy.ops.object.mode_set(mode="EDIT")
        for b in humanoid.bones(spec):
            eb = arm.edit_bones.new(b["name"])
            eb.head = b["head"]
            eb.tail = b["tail"]
            eb.roll = 0.0
            eb.use_connect = False
        for b in humanoid.bones(spec):
            if b["parent"]:
                arm.edit_bones[b["name"]].parent = arm.edit_bones[b["parent"]]
        bpy.ops.object.mode_set(mode="OBJECT")
    return ob


def build_meshes(spec, rig, coll, materials):
    import bmesh
    objs = []
    ink = _ink_material(spec["style"]["ink"])
    for part in humanoid.build(spec):
        me = bpy.data.meshes.new(part["name"])
        me.from_pydata([tuple(v) for v in part["verts"]], [], [tuple(f) for f in part["faces"]])
        me.update()
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        for poly in me.polygons:
            poly.use_smooth = part["smooth"]
        ob = bpy.data.objects.new(part["name"], me)
        coll.objects.link(ob)
        mat = materials.get(part["material"])
        if mat is None:
            raise RuntimeError("part %s uses material '%s' the actor does not define"
                               % (part["name"], part["material"]))
        me.materials.append(mat)
        ob.parent = rig
        for bone, weights in part["weights"].items():
            vg = ob.vertex_groups.new(name=bone)
            for i, w in enumerate(weights):
                if w > 1e-4:
                    vg.add([i], w, "REPLACE")
        # Hair and face details never shade the face: a lit face is a readability rule, not a
        # lighting accident (the fringe's cast shadow read as a mask at 32x48).
        if part["material"] in NO_CAST:
            ob.visible_shadow = False
        ob["aetheria_lod"] = part.get("lod", "all")
        ob.hide_render = ob["aetheria_lod"] not in ("all", "sprite")
        mod = ob.modifiers.new("rig", "ARMATURE")
        mod.object = rig
        _add_ink_hull(ob, ink)
        objs.append(ob)
    return objs


INK_HULL = 0.22      # world units: ~2 px at the presentation scale


def _ink_material(rgb):
    mat = bpy.data.materials.get("AE_ink_hull")
    if mat:
        return mat
    mat = bpy.data.materials.new("AE_ink_hull")
    mat.use_nodes = True
    mat.use_backface_culling = True
    nt = mat.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = _linear(rgb)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return mat


def _add_ink_hull(ob, ink):
    """The presentation renders' ink line: an inverted hull (solidify outward, normals flipped,
    back faces culled) in the style's one ink colour (aetheria_style.yaml §3). It draws the
    figure as Aetheria draws everything — an outlined form — instead of a lit plastic toy. OFF
    in every gameplay pass: the sprite's outline is traced from its pixels by the adapter."""
    ob.data.materials.append(ink)
    mod = ob.modifiers.new("ink_hull", "SOLIDIFY")
    mod.thickness = -INK_HULL
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.material_offset = len(ob.data.materials) - 1
    mod.show_render = False
    mod.show_viewport = False


def _ink_hulls(on):
    for ob in bpy.data.objects:
        mod = ob.modifiers.get("ink_hull") if ob.type == "MESH" else None
        if mod:
            mod.show_render = on


def _look_rotation(elevation_deg, yaw_deg=0.0):
    """Camera rotation looking toward +Y, pitched down by `elevation_deg`."""
    return (math.radians(90.0 - elevation_deg), 0.0, math.radians(yaw_deg))


def setup_cameras(spec, coll):
    cg = spec["camera"]["gameplay"]
    w, h = cg["cell"]
    el = math.radians(cg["elevation_deg"])
    fwd = Vector((0.0, math.cos(el), -math.sin(el)))
    up = Vector((0.0, math.sin(el), math.cos(el)))
    # Put the FEET ORIGIN at cell pixel (w/2, feet_row): the view centre is that far above it,
    # in world units (the cell height spans `ortho_units`).
    units = float(cg.get("ortho_units", h))
    centre = up * (units / 2.0 - (h - cg["feet_row"]) * units / h)
    cam_data = bpy.data.cameras.new("AE_cam_gameplay")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = units
    cam_data.clip_start = 1.0
    cam_data.clip_end = 400.0
    cam = bpy.data.objects.new("AE_cam_gameplay", cam_data)
    cam.location = centre - fwd * CAM_DISTANCE
    cam.rotation_euler = _look_rotation(cg["elevation_deg"])
    coll.objects.link(cam)
    cp = spec["camera"]["presentation"]
    pdata = bpy.data.cameras.new("AE_cam_presentation")
    pdata.lens = cp["focal_mm"]
    pel = math.radians(cp["elevation_deg"])
    pfwd = Vector((0.0, math.cos(pel), -math.sin(pel)))
    pcam = bpy.data.objects.new("AE_cam_presentation", pdata)
    pcam.location = Vector((0.0, 0.0, 26.0)) - pfwd * float(cp.get("distance", 150.0))
    pcam.rotation_euler = _look_rotation(cp["elevation_deg"])
    coll.objects.link(pcam)
    cpt = spec["camera"]["portrait"]
    tdata = bpy.data.cameras.new("AE_cam_portrait")
    tdata.type = "ORTHO"
    lo, hi = cpt["frame"]
    tdata.ortho_scale = hi - lo
    tel = math.radians(cpt["elevation_deg"])
    tfwd = Vector((0.0, math.cos(tel), -math.sin(tel)))
    tcam = bpy.data.objects.new("AE_cam_portrait", tdata)
    tcam.location = Vector((0.0, 0.0, (lo + hi) / 2.0)) - tfwd * CAM_DISTANCE
    tcam.rotation_euler = _look_rotation(cpt["elevation_deg"])
    coll.objects.link(tcam)
    return cam, pcam, tcam


def setup_lights(spec, coll):
    """The CANONICAL light (aetheria_style.yaml §2): a key from the screen's upper left and a
    little toward the viewer, a cool fill as world ambient, a qi-tinted rim from behind. The
    lights are fixed to the CAMERA frame and the figure turns under them, so every facing is
    lit from the same screen direction."""
    lt = spec["style"]["lighting"]
    key = bpy.data.lights.new("AE_key", "SUN")
    key.energy = KEY_ENERGY
    key.angle = math.radians(1.0)
    key.color = (1.0, 0.97, 0.92)
    kob = bpy.data.objects.new("AE_key", key)
    el = math.radians(lt["key_elevation_deg"])
    to_light = Vector((-math.cos(el) * 0.78, -math.cos(el) * 0.62, math.sin(el))).normalized()
    kob.rotation_euler = to_light.to_track_quat("Z", "Y").to_euler()
    coll.objects.link(kob)
    rim = bpy.data.lights.new("AE_rim", "SUN")
    rim.energy = float(lt["rim"]["ratio"]) * 0.8
    rim.angle = math.radians(2.0)
    rim.color = (0.80, 0.92, 1.0)
    rob = bpy.data.objects.new("AE_rim", rim)
    rob.rotation_euler = Vector((0.55, 0.75, 0.45)).normalized().to_track_quat("Z", "Y").to_euler()
    coll.objects.link(rob)
    world = bpy.data.worlds.get("AE_world") or bpy.data.worlds.new("AE_world")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    fill = float(lt["fill_ratio"])
    bg.inputs["Color"].default_value = (0.78 * fill, 0.84 * fill, 1.0 * fill, 1.0)
    bg.inputs["Strength"].default_value = 1.0
    bpy.context.scene.world = world


def configure_render(scene, width, height, samples=1):
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = samples
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.dither_intensity = 0.0
    scene.render.filter_size = 0.0 if samples == 1 else 1.5
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0.0
    scene.view_settings.gamma = 1.0


# --- poses and actions ----------------------------------------------------------------------------

def _rest3(rig, bone):
    return rig.data.bones[bone].matrix_local.to_3x3()


def apply_pose(rig, pose):
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector()
        pb.scale = Vector((1, 1, 1))
    rest = {b.name: _rest3(rig, b.name) for b in rig.data.bones}
    root = Vector(pose["root"])
    rig.pose.bones["root"].location = rest["root"].inverted() @ root
    rig.pose.bones["spine"].location = rest["spine"].inverted() @ Vector((0, 0, pose["lift"]))
    for bone, q in pose["rot"].items():
        Q = Matrix(q)
        rb = rest[bone]
        rig.pose.bones[bone].rotation_quaternion = (rb.inverted() @ Q @ rb).to_quaternion()
    closed = pose.get("eyes_closed", False)
    if "eyes_open" in rig.pose.bones:
        rig.pose.bones["eyes_open"].scale = Vector((1, 1, 1)) * (0.001 if closed else 1.0)
        rig.pose.bones["eyes_closed"].scale = Vector((1, 1, 1)) * (1.0 if closed else 0.001)


def key_actions(spec, rig):
    """One real Blender Action per animation, keyed frame-by-frame (CONSTANT interpolation:
    a sprite frame is a held pose, never an in-between)."""
    if rig.animation_data is None:
        rig.animation_data_create()
    actions = {}
    for anim, info in spec["animations"].items():
        for suffix, shape in (("", lambda p: p), (MIRROR_SUFFIX, motion.mirror)):
            act = _key_action(spec, rig, "AE_" + anim + suffix, info["frames"],
                              lambda f, a=anim, sh=shape: sh(motion.ANIMATIONS[a](spec, f)))
            actions[anim + suffix] = act
    return actions


def _key_action(spec, rig, name, frames, pose_at):
    act = bpy.data.actions.get(name) or bpy.data.actions.new(name)
    act.use_fake_user = True
    rig.animation_data.action = act
    for f in range(frames):
        apply_pose(rig, pose_at(f))
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f + 1)
            pb.keyframe_insert("location", frame=f + 1)
            pb.keyframe_insert("scale", frame=f + 1)
    _constant_interpolation(act)
    return act


def _constant_interpolation(act):
    curves = []
    if hasattr(act, "fcurves"):
        curves = list(act.fcurves)
    if not curves:
        for layer in getattr(act, "layers", []):
            for strip in layer.strips:
                for bag in getattr(strip, "channelbags", []):
                    curves += list(bag.fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "CONSTANT"


# --- build -----------------------------------------------------------------------------------

def build(spec_path):
    spec = load_spec(spec_path)
    reset_scene()
    scene = bpy.context.scene
    coll = bpy.data.collections.new("AE_" + spec["id"])
    scene.collection.children.link(coll)
    bands = spec["style"]["pixel"]["light_bands"]
    materials = {name: make_material(name, m, bands) for name, m in spec["materials"].items()}
    rig = build_armature(spec, coll)
    build_meshes(spec, rig, coll, materials)
    # Stature is ONE number on the rig object: meshes, bones, poses and the projected anchors
    # all scale together, and the feet stay on the origin (D-062: same rig, different design).
    sc = float(spec["body"].get("scale", 1.0))
    rig.scale = (sc, sc, sc)
    cam, pcam, tcam = setup_cameras(spec, coll)
    setup_lights(spec, coll)
    key_actions(spec, rig)
    scene.camera = cam
    scene.frame_start = 1
    scene.frame_end = 8
    rig["aetheria_actor"] = spec["id"]
    rig["aetheria_spec"] = os.path.relpath(spec_path, PIPE)
    return rig


def _dir_index(dname):
    return [d for d, _ in DIRECTIONS].index(dname)


def _rig():
    return next(o for o in bpy.data.objects if o.type == "ARMATURE")


def _project(scene, cam, co, cell):
    v = world_to_camera_view(scene, cam, co)
    return (v.x * cell[0], (1.0 - v.y) * cell[1])


def render_frames(spec_path, anims=None, out_dir=None, passes=("id", "light", "depth"),
                  only_frames=None, directions=None):
    """Render every (anim, direction, frame) as exact 1-sample passes at render_scale x the
    cell, and write anchors.json (cell-pixel coordinates, NOT yet feet-relative)."""
    spec = load_spec(spec_path)
    scene = bpy.context.scene
    rig = _rig()
    cam = bpy.data.objects["AE_cam_gameplay"]
    scene.camera = cam
    cg = spec["camera"]["gameplay"]
    cell = cg["cell"]
    k = cg["render_scale"]
    configure_render(scene, cell[0] * k, cell[1] * k, 1)
    out_dir = out_dir or os.path.join(os.path.dirname(spec_path), "frames")
    os.makedirs(out_dir, exist_ok=True)
    anchors_path = os.path.join(out_dir, "anchors.json")
    anchors = {}
    if os.path.exists(anchors_path):
        with open(anchors_path) as f:
            anchors = json.load(f)
    points = spec["anchors"]
    for anim, info in spec["animations"].items():
        if anims and anim not in anims:
            continue
        per = {name: [] for name in points}
        for dname, yaw in DIRECTIONS:
            if directions and dname not in directions:
                per_old = anchors.get(anim, {})
                for name in points:
                    per[name].append(per_old.get(name, [[]] * 4)[_dir_index(dname)])
                continue
            mirrored = dname in MIRRORED
            rig.animation_data.action = bpy.data.actions[
                "AE_" + anim + (MIRROR_SUFFIX if mirrored else "")]
            rig.rotation_euler = (0.0, 0.0, math.radians(yaw))
            rows = {name: [] for name in points}
            for f in range(info["frames"]):
                if only_frames is not None and f not in only_frames:
                    continue
                scene.frame_set(f + 1)
                bpy.context.view_layer.update()
                for name, bone in points.items():
                    if mirrored:
                        bone = motion.mirror_name(bone)
                    pb = rig.pose.bones[bone]
                    co = rig.matrix_world @ ((pb.head + pb.tail) * 0.5 if bone.startswith("hand")
                                             else pb.head)
                    rows[name].append(_project(scene, cam, co, cell))
                for pas in passes:
                    set_mode(pas)
                    scene.render.filepath = os.path.join(
                        out_dir, "%s_%s_%d_%s.png" % (anim, dname, f, pas))
                    bpy.ops.render.render(write_still=True)
            for name in points:
                per[name].append(rows[name])
        if only_frames is None:
            anchors[anim] = per
    rig.rotation_euler = (0.0, 0.0, 0.0)
    set_mode("beauty")
    with open(anchors_path, "w") as f:
        json.dump(anchors, f)
    return out_dir


def render_presentation(spec_path, out_path, yaw_list=(0.0, -90.0, 180.0, 90.0),
                        anim="idle", frame=0, size=(512, 768), samples=32):
    """The beauty turnaround: the same materials in beauty mode, perspective camera."""
    spec = load_spec(spec_path)
    scene = bpy.context.scene
    rig = _rig()
    rig.animation_data.action = bpy.data.actions["AE_" + anim]
    scene.frame_set(frame + 1)
    set_mode("beauty")
    _show_lod("portrait")
    _ink_hulls(True)
    scene.camera = bpy.data.objects["AE_cam_presentation"]
    configure_render(scene, size[0], size[1], samples)
    paths = []
    base, ext = os.path.splitext(out_path)
    for i, yaw in enumerate(yaw_list):
        rig.rotation_euler = (0.0, 0.0, math.radians(yaw))
        scene.render.filepath = "%s_%d%s" % (base, i, ext)
        bpy.ops.render.render(write_still=True)
        paths.append(scene.render.filepath)
    rig.rotation_euler = (0.0, 0.0, 0.0)
    _show_lod("sprite")
    _ink_hulls(False)
    scene.camera = bpy.data.objects["AE_cam_gameplay"]
    return paths


def render_portrait(spec_path, out_dir=None):
    spec = load_spec(spec_path)
    scene = bpy.context.scene
    rig = _rig()
    rig.animation_data.action = bpy.data.actions["AE_idle"]
    scene.frame_set(1)
    rig.rotation_euler = (0.0, 0.0, math.radians(-12.0))
    cp = spec["camera"]["portrait"]
    k = cp["render_scale"]
    _show_lod("portrait")
    scene.camera = bpy.data.objects["AE_cam_portrait"]
    configure_render(scene, cp["size"][0] * k, cp["size"][1] * k, 1)
    out_dir = out_dir or os.path.join(os.path.dirname(spec_path), "frames")
    os.makedirs(out_dir, exist_ok=True)
    for pas in ("id", "light", "depth"):
        set_mode(pas)
        scene.render.filepath = os.path.join(out_dir, "portrait_%s.png" % pas)
        bpy.ops.render.render(write_still=True)
    set_mode("beauty")
    _show_lod("sprite")
    rig.rotation_euler = (0.0, 0.0, 0.0)
    scene.camera = bpy.data.objects["AE_cam_gameplay"]
    return out_dir


def _show_lod(lod):
    """Render the parts of `lod` ('sprite' or 'portrait') plus every 'all' part."""
    for ob in bpy.data.objects:
        if "aetheria_lod" in ob:
            ob.hide_render = ob["aetheria_lod"] not in ("all", lod)


def save(blend_path):
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, compress=True, copy=False)
    return blend_path


DETAIL_SHOTS = (  # (name, action, frame, yaw): where a hand must read as a hand
    ("hand_strike", "attack", 3, -60.0),
    ("hand_rest", "idle", 0, -25.0),
    ("hand_seal", "cast", 3, -20.0),
)


def render_details(spec_path, size=320, samples=32):
    """Close-ups of the striking hand in three poses (beauty, portrait LOD, ink hull): the
    review evidence that the hands are hands (CHARACTER_ART_BIBLE §6b: no circle-hand)."""
    scene = bpy.context.scene
    rig = _rig()
    set_mode("beauty")
    _show_lod("portrait")
    _ink_hulls(True)
    data = bpy.data.cameras.new("AE_cam_detail")
    data.lens = 100
    cam = bpy.data.objects.new("AE_cam_detail", data)
    scene.collection.objects.link(cam)
    configure_render(scene, size, size, samples)
    scene.camera = cam
    paths = []
    for name, anim, frame, yaw in DETAIL_SHOTS:
        rig.animation_data.action = bpy.data.actions["AE_" + anim]
        scene.frame_set(frame + 1)
        rig.rotation_euler = (0.0, 0.0, math.radians(yaw))
        bpy.context.view_layer.update()
        pb = rig.pose.bones["hand.R"]
        hand = rig.matrix_world @ ((pb.head + pb.tail) * 0.5)
        cam.location = hand + Vector((-6.0, -26.0, 8.0))
        cam.rotation_euler = (hand - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(os.path.dirname(spec_path), name + ".png")
        bpy.ops.render.render(write_still=True)
        paths.append(scene.render.filepath)
    bpy.data.objects.remove(cam)
    bpy.data.cameras.remove(data)
    rig.rotation_euler = (0.0, 0.0, 0.0)
    _ink_hulls(False)
    _show_lod("sprite")
    scene.camera = bpy.data.objects["AE_cam_gameplay"]
    return paths


def build_and_render_all(actor):
    """The whole Blender side for one actor: scene, presentation turnaround, every gameplay
    pass, the portrait passes. Returns the actor's work dir (system Python takes over there)."""
    work = os.path.join(PIPE, "work", actor)
    spec_path = os.path.join(work, "spec.json")
    build(spec_path)
    render_presentation(spec_path, os.path.join(work, "present.png"), size=(384, 576), samples=8)
    render_frames(spec_path)
    render_portrait(spec_path)
    render_details(spec_path)
    return work
