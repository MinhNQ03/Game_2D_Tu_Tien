"""Rendered VFX frame sequences (experience upgrade). Runs INSIDE Blender 5.2, headless:

    blender -b -P tools/aetheria_art_pipeline/blender/build_vfx.py -- <spec.json> [effect ...]

`build.py vfx-spec` writes the spec (designs/vfx.yaml resolved); this renders, for every effect,
`work/vfx/<effect>/frame_NN.png`: an INTENSITY pass — white emission whose brightness is how
much light that pixel carries, alpha its coverage — at `render_scale` x the frame size, through
the gameplay camera (orthographic, the style's elevation). `build.py vfx` then maps intensity to
the effect's ramp and packs the strip; colour is never decided here.

Each frame is BUILT for its own time `t` in [0, 1] (no keyframes, no simulation): the scene is
cleared and the effect's geometry placed for that instant. Every variation comes from the
effect's `seed` through one `random.Random`, so the same spec renders the same pixels.
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector


# --- the stage ---------------------------------------------------------------------------------

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = 16
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    world = bpy.data.worlds.new("vfx_world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = world
    return scene


def camera(scene, size, anchor, elevation_deg, scale):
    """The gameplay camera: orthographic, pitched `elevation_deg`, framing `size` world px with
    the world origin (where the effect stands) on frame pixel `anchor`."""
    w, h = size
    el = math.radians(elevation_deg)
    up = Vector((0.0, math.sin(el), math.cos(el)))
    right = Vector((1.0, 0.0, 0.0))
    fwd = Vector((0.0, math.cos(el), -math.sin(el)))
    # the frame centre, relative to the anchor, in screen px -> world units on the image plane
    cx = w / 2.0 - anchor[0]
    cy = anchor[1] - h / 2.0
    centre = right * cx + up * cy
    data = bpy.data.cameras.new("vfx_cam")
    data.type = "ORTHO"
    data.ortho_scale = float(max(w, h))
    data.clip_start = 1.0
    data.clip_end = 1000.0
    cam = bpy.data.objects.new("vfx_cam", data)
    cam.location = centre - fwd * 400.0
    cam.rotation_euler = (math.radians(90.0 - elevation_deg), 0.0, 0.0)
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x = w * scale
    scene.render.resolution_y = h * scale
    scene.render.resolution_percentage = 100
    # a non-square frame: ortho_scale spans the LONGER side
    scene.render.pixel_aspect_x = 1.0
    scene.render.pixel_aspect_y = 1.0


_MATS = {}


def glow(level):
    """White emission at `level` (0..1): the intensity the packer maps onto the ramp."""
    key = round(level, 3)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new("glow_%s" % key)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (key, key, key, 1.0)
    em.inputs["Strength"].default_value = 1.0
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    _MATS[key] = m
    return m


def _link(ob, level):
    ob.data.materials.clear()
    ob.data.materials.append(glow(max(0.0, min(1.0, level))))
    return ob


def blob(at, r, level, squash=(1.0, 1.0, 1.0)):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=max(r, 0.05), location=at)
    ob = bpy.context.active_object
    ob.scale = squash
    return _link(ob, level)


def segment(a, b, r, level):
    """A rod from a to b (a streak, a fork of lightning)."""
    a, b = Vector(a), Vector(b)
    d = b - a
    if d.length < 1e-4:
        return blob(a, r, level)
    bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=max(r, 0.05), depth=d.length,
                                        location=(a + b) / 2.0)
    ob = bpy.context.active_object
    ob.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    return _link(ob, level)


def ring(at, radius, thickness, level, flat=True):
    bpy.ops.mesh.primitive_torus_add(major_radius=max(radius, 0.1),
                                     minor_radius=max(thickness, 0.05),
                                     major_segments=48, minor_segments=6, location=at)
    ob = bpy.context.active_object
    if not flat:
        ob.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    return _link(ob, level)


def _ease_out(x):
    return 1.0 - (1.0 - x) ** 3


def _ease_in(x):
    return x ** 2.2


# --- the effects (each places its geometry for the instant t in [0, 1]) -----------------------

def qi_gather(t, rng_seed):
    """SOURCE the vein under the seat -> GATHER a ring of motes rising from the ground ->
    FOCUS they spiral in, faster as they near the dantian -> settle in one soft pulse."""
    rng = random.Random(rng_seed)
    core = Vector((0.0, 0.0, 20.0))
    motes = 16
    gather_end = 0.72
    # the vein's breath at the ground: a ring that brightens as it gives, then dims
    # SOURCE first: the very first frame is the vein under the seat answering the sitting
    ground = 0.3 + 0.7 * math.sin(math.pi * min(1.0, t / 0.6)) if t < 0.6 else \
        max(0.0, 1.0 - (t - 0.6) / 0.3)
    if ground > 0.02:
        ring((0.0, 0.0, 0.5), 22.0 - 6.0 * t, 0.45, 0.22 * ground)
        blob((0.0, 0.0, 0.6), 4.0, 0.25 * ground, squash=(1.0, 0.8, 0.12))
    for i in range(motes):
        phase = rng.uniform(0.0, 0.35)          # when this mote leaves the ground
        speed = rng.uniform(0.85, 1.15)
        a0 = rng.uniform(0.0, math.tau)
        local = (t - phase) / max(0.05, (gather_end - phase) / speed)
        if local <= 0.0 or local >= 1.0:
            continue
        k = _ease_in(local)                     # accelerates toward the body
        radius = 24.0 * (1.0 - k)
        angle = a0 + 2.2 * math.pi * k
        z = 1.0 + (core.z - 1.0) * _ease_out(local)
        pos = Vector((radius * math.cos(angle), radius * math.sin(angle) * 0.8, z))
        back = max(0.0, local - 0.08)
        kb = _ease_in(back)
        prev = Vector((24.0 * (1.0 - kb) * math.cos(a0 + 2.2 * math.pi * kb),
                       24.0 * (1.0 - kb) * math.sin(a0 + 2.2 * math.pi * kb) * 0.8,
                       1.0 + (core.z - 1.0) * _ease_out(back)))
        bright = 0.45 + 0.55 * local
        segment(prev, pos, 0.55, bright * 0.7)  # its streak
        blob(pos, 1.0 + 0.4 * local, bright)
    # FOCUS -> settle: the dantian brightens, then one pulse opens and fades
    if t > 0.45:
        k = min(1.0, (t - 0.45) / 0.3)
        blob(core, 1.6 + 1.6 * k, 0.55 + 0.45 * k)
    if t > gather_end:
        k = (t - gather_end) / (1.0 - gather_end)
        ring(core, 4.0 + 12.0 * _ease_out(k), 0.7 * (1.0 - k) + 0.2, 0.9 * (1.0 - k),
             flat=False)


def _fork(rng, start, direction, length, depth, out):
    """A jagged lightning fork: a polyline that wanders off `direction`, splitting once."""
    pts = [Vector(start)]
    seg = 4
    d = Vector(direction).normalized()
    for i in range(seg):
        jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.6, 0.6)))
        nxt = pts[-1] + d * (length / seg) + jitter * (length * 0.16)
        pts.append(nxt)
    out.append(pts)
    if depth > 0:
        mid = pts[2]
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        branch = (d + side.normalized() * rng.choice((-0.8, 0.8))).normalized()
        _fork(rng, mid, branch, length * 0.55, depth - 1, out)


def lightning_burst(t, rng_seed):
    """IMPACT a white core flash -> the bolt's current cracks OUT in forks -> sparks thrown up
    fall and die (DISSIPATE). The strike point is the origin, at chest height of a target."""
    rng = random.Random(rng_seed)
    core = Vector((0.0, 0.0, 6.0))
    if t < 0.35:                                   # the flash: big, then gone
        k = t / 0.35
        blob(core, 6.0 * (1.0 - k) + 2.0, 1.0 - 0.3 * k, squash=(1.0, 1.0, 0.8))
    forks = []
    for i in range(6):
        ang = (i / 6.0) * math.tau + rng.uniform(-0.3, 0.3)
        _fork(rng, core, (math.cos(ang), math.sin(ang) * 0.7, rng.uniform(-0.1, 0.5)),
              rng.uniform(13.0, 19.0), 1, forks)
    if t < 0.6:                                    # the forks crack outward
        k = min(1.0, t / 0.3)
        fade = 1.0 - max(0.0, (t - 0.3) / 0.3)
        for pts in forks:
            n = max(1, int(round((len(pts) - 1) * k)))
            for a, b in zip(pts[:n], pts[1:n + 1]):
                segment(a, b, 0.45, 0.7 * fade)
    sparks = rng.randint(10, 14)                   # thrown, falling, dimming
    for i in range(sparks):
        ang = rng.uniform(0, math.tau)
        v = rng.uniform(10.0, 20.0)
        up = rng.uniform(4.0, 12.0)
        s = max(0.0, t - 0.15) / 0.85
        if s <= 0.0:
            continue
        pos = core + Vector((math.cos(ang) * v * s, math.sin(ang) * v * s * 0.7,
                             up * s - 14.0 * s * s))
        if pos.z < 0.0:
            continue
        blob(pos, 0.7, 0.62 * (1.0 - s))
    if 0.1 < t < 0.7:                              # the ground answers: a scorched ring
        k = (t - 0.1) / 0.6
        ring((0.0, 0.0, 0.3), 3.0 + 10.0 * _ease_out(k), 0.5, 0.45 * (1.0 - k))


def vein_rupture(t, rng_seed):
    """CAUSE the vein under the ground gives -> cracks run outward from it, glowing ->
    RELEASE a column of raw qi erupts, shards thrown -> the column falls back -> a guttering
    glow in the cracks and a few motes left hanging (DISSIPATE). Shows only that something
    broke (reveal layer 1): no figure, no sigil, no hand."""
    rng = random.Random(rng_seed)
    cracks = []
    for i in range(7):
        ang = (i / 7.0) * math.tau + rng.uniform(-0.25, 0.25)
        pts = [Vector((0.0, 0.0, 0.4))]
        length = rng.uniform(34.0, 52.0)
        for s in range(5):
            jitter = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0.0)) * 3.0
            step = Vector((math.cos(ang), math.sin(ang) * 0.8, 0.0)) * (length / 5.0)
            pts.append(pts[-1] + step + jitter)
            ang += rng.uniform(-0.35, 0.35)
        cracks.append(pts)
    grow = 0.08 + 0.92 * min(1.0, t / 0.33)
    glow_level = 0.85 if t < 0.55 else max(0.25, 0.85 - (t - 0.55) * 1.4)
    flicker = 0.85 + 0.15 * math.sin(t * 40.0)
    for pts in cracks:
        # the crack RUNS: whole segments behind its tip, and the part of the next it has reached
        total = (len(pts) - 1) * grow
        whole = int(total)
        for a, b in zip(pts[:whole], pts[1:whole + 1]):
            segment(a, b, 0.75, glow_level * flicker)
        if whole < len(pts) - 1:
            a, b = pts[whole], pts[whole + 1]
            segment(a, a + (b - a) * (total - whole), 0.75, glow_level * flicker)
    # the column: rises fast, holds, falls back
    if 0.28 < t < 0.85:
        k = (t - 0.28) / 0.57
        rise = _ease_out(min(1.0, k / 0.35))
        fall = 1.0 - _ease_in(max(0.0, (k - 0.55) / 0.45))
        height = 70.0 * rise * fall
        width = 7.0 + 5.0 * rise
        if height > 1.0:
            for j in range(6):                     # a column of stacked, twisting lobes
                z = height * (j + 0.5) / 6.0
                wob = 1.5 * math.sin(j * 1.9 + t * 25.0)
                blob((wob, 0.0, z), width * (1.0 - j / 9.0), 0.3 + 0.2 * (1.0 - j / 6.0),
                     squash=(1.0, 0.7, 1.6))
                # its bright spine, nearer the camera so it reads over the body
                blob((wob * 0.6, -width * 0.6, z), width * 0.32 * (1.0 - j / 8.0),
                     0.95, squash=(1.0, 0.6, 1.9))
            blob((0.0, 0.0, 2.0), width * 1.7, 0.5, squash=(1.4, 1.0, 0.45))
            blob((0.0, -width * 0.8, 3.0), width * 0.7, 1.0, squash=(1.3, 0.8, 0.5))
    # shards of raw vein-stone and qi, thrown out of the eruption
    if t > 0.3:
        s = (t - 0.3) / 0.7
        for i in range(12):
            ang = rng.uniform(0, math.tau)
            v = rng.uniform(22.0, 40.0)
            up = rng.uniform(26.0, 46.0)
            pos = Vector((math.cos(ang) * v * s, math.sin(ang) * v * s * 0.7,
                          up * s - 52.0 * s * s + 4.0))
            if pos.z <= 0.5:
                continue
            blob(pos, 1.1, 0.9 * (1.0 - s * 0.7))
    # what hangs in the air after: a few motes, drifting up and out
    if t > 0.7:
        s = (t - 0.7) / 0.3
        for i in range(6):
            ang = rng.uniform(0, math.tau)
            pos = Vector((math.cos(ang) * 14.0 * (0.6 + s), math.sin(ang) * 10.0,
                          10.0 + 18.0 * s + rng.uniform(0, 8)))
            blob(pos, 0.8, 0.6 * (1.0 - s))


KINDS = {"qi_gather": qi_gather, "lightning_burst": lightning_burst,
         "vein_rupture": vein_rupture}


def render_effect(effect_id, spec, out_root, elevation, scale):
    out_dir = os.path.join(out_root, effect_id)
    os.makedirs(out_dir, exist_ok=True)
    frames = int(spec["frames"])
    for f in range(frames):
        scene = reset()
        _MATS.clear()
        camera(scene, spec["size"], spec["anchor"], elevation, scale)
        t = f / float(frames - 1)
        KINDS[spec["kind"]](t, int(spec["seed"]))
        scene.render.filepath = os.path.join(out_dir, "frame_%02d.png" % f)
        bpy.ops.render.render(write_still=True)
    return out_dir


def main(argv):
    with open(argv[0], encoding="utf-8") as f:
        data = json.load(f)
    out_root = os.path.dirname(argv[0])
    wanted = argv[1:] or list(data["effects"])
    for effect_id in wanted:
        print("[vfx] rendered", render_effect(effect_id, data["effects"][effect_id], out_root,
                                               data["camera_elevation_deg"],
                                               data["render_scale"]))


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
