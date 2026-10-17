"""The five Origin illustrations (experience upgrade). Runs INSIDE Blender 5.2, headless:

    blender -b -P tools/aetheria_art_pipeline/blender/build_story_art.py -- <out_dir> [origin ...]

Writes `<out_dir>/<origin_id>_raw.png` (1280x720); `build.py origins` then grades them into the
shipped painted-tier files `assets/ui/aetheria/origins/<origin_id>.png`.

WHAT THEY ARE. Story art for the identity screen's cards and the backdrop of each Origin's
vignette: one moment of the past the player is choosing, staged as a small 2.5D diorama in the
game's own vocabulary — the canonical cultivator (seen from behind, so the picture fits every
look), the village's prop geometry (`props3d`), the Visual DNA's material roles and its ink line.
A memory, not a map: low key, one warm practical light against a cold ground, mist for depth,
and ONE thing the eye goes to first (the burnt wagons, the board, the bed, the cracked stone,
the torn ledger).

Deterministic: no random call without a fixed seed, fixed sample counts, fixed resolution. The
game never runs this; it loads the graded PNGs only.
"""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Euler, Vector

PIPE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for sub in ("blender", "model"):
    if os.path.join(PIPE, sub) not in sys.path:
        sys.path.insert(0, os.path.join(PIPE, sub))

import build_actor  # noqa: E402
import motion  # noqa: E402
import props3d  # noqa: E402

WIDTH, HEIGHT = 1280, 720
## The scenes are modelled in the props' units (one world pixel each, hundreds deep): an
## authored mist density reads per unit, so it is scaled down once, here.
FOG_SCALE = 0.05
## Point lights fall off with distance squared in those same units: energies are authored
## for a ~10-unit throw and scaled here.
LIGHT_SCALE = 40.0
SAMPLES = 48
ACTOR_SPEC = os.path.join(PIPE, "work", "player_proto", "spec.json")
PROPS_YAML = os.path.join(PIPE, "designs", "props.yaml")

ORIGINS = ("origin_ho_tieu", "origin_de_tu_bi_loai", "origin_lang_y", "origin_nghe_nhan",
           "origin_thu_thu")


# --- materials -------------------------------------------------------------------------------

def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def _lin(c):
    return tuple(build_actor._srgb_to_linear(round(v * 255)) for v in c[:3]) + (1.0,)


def _prop_ramps():
    """The DNA's world material roles (designs/props.yaml `common`), read without PyYAML: the
    file's `name: {ramp: [...]}` lines are regular enough to parse by hand inside Blender."""
    ramps = {}
    with open(PROPS_YAML, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            name, _, rest = line.partition(":")
            if not rest.strip().startswith("{ramp: ["):
                continue
            tones = rest.split("[", 1)[1].split("]", 1)[0]
            ramps[name.strip()] = [t.strip().strip('"') for t in tones.split(",")]
    return ramps


RAMPS = {}
_MATS = {}


def mat(name, tone=2, rough=0.85, emit=None, emit_strength=0.0, color=None):
    """A Principled material in a DNA role (`tone` 0..3 of its ramp), or an explicit colour."""
    key = (name, tone, rough, emit, emit_strength, color)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new("ST_%s_%d" % (name, len(_MATS)))
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    rgb = _hex(color) if color else _hex(RAMPS[name][tone])
    p.inputs["Base Color"].default_value = _lin(rgb)
    p.inputs["Roughness"].default_value = rough
    if emit:
        p.inputs["Emission Color"].default_value = _lin(_hex(emit))
        p.inputs["Emission Strength"].default_value = emit_strength
    _MATS[key] = m
    return m


def paint(name, a, b, c=None, scale=0.04, rough=0.85, bump=0.3, emit=None, emit_mask=None):
    # `scale` is noise features per world unit: 0.02 = a variation every ~50 units (a meadow),
    # 0.25 = every ~4 (charred grain, a stone's face).
    """A painterly surface: two (or three) tones of one material role mixed by a cloud noise
    in OBJECT space, with a little bump — the brush variation a flat colour lacks. `emit` +
    `emit_mask` ("crack"): a glowing network (embers in charred wood, the wrong light in a
    split stone) drawn by a Voronoi edge mask."""
    key = ("paint", name, a, b, c, scale, rough, bump, emit, emit_mask)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new("ST_paint_%s_%d" % (name, len(_MATS)))
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = scale
    noise.inputs["Detail"].default_value = 6.0
    noise.inputs["Roughness"].default_value = 0.62
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position = 0.35
    els[0].color = _lin(_hex(a))
    els[1].position = 0.65
    els[1].color = _lin(_hex(b))
    if c:
        e = els.new(0.82)
        e.color = _lin(_hex(c))
    nt.links.new(noise.outputs["Fac"], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], p.inputs["Base Color"])
    p.inputs["Roughness"].default_value = rough
    if bump:
        bn = nt.nodes.new("ShaderNodeBump")
        bn.inputs["Strength"].default_value = bump
        nt.links.new(noise.outputs["Fac"], bn.inputs["Height"])
        nt.links.new(bn.outputs["Normal"], p.inputs["Normal"])
    if emit and emit_mask == "crack":
        vor = nt.nodes.new("ShaderNodeTexVoronoi")
        vor.feature = "DISTANCE_TO_EDGE"
        vor.inputs["Scale"].default_value = scale * 1.6
        nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
        edge = nt.nodes.new("ShaderNodeMapRange")
        edge.inputs["From Min"].default_value = 0.0
        edge.inputs["From Max"].default_value = 0.025
        edge.inputs["To Min"].default_value = 1.0
        edge.inputs["To Max"].default_value = 0.0
        nt.links.new(vor.outputs["Distance"], edge.inputs["Value"])
        patch = nt.nodes.new("ShaderNodeTexNoise")
        patch.inputs["Scale"].default_value = scale * 0.3
        nt.links.new(tc.outputs["Object"], patch.inputs["Vector"])
        live = nt.nodes.new("ShaderNodeMapRange")
        live.inputs["From Min"].default_value = 0.55
        live.inputs["From Max"].default_value = 0.7
        nt.links.new(patch.outputs["Fac"], live.inputs["Value"])
        both = nt.nodes.new("ShaderNodeMath")
        both.operation = "MULTIPLY"
        nt.links.new(edge.outputs["Result"], both.inputs[0])
        nt.links.new(live.outputs["Result"], both.inputs[1])
        strength = nt.nodes.new("ShaderNodeMath")
        strength.operation = "MULTIPLY"
        strength.inputs[1].default_value = emit[1]
        nt.links.new(both.outputs[0], strength.inputs[0])
        p.inputs["Emission Color"].default_value = _lin(_hex(emit[0]))
        nt.links.new(strength.outputs[0], p.inputs["Emission Strength"])
    _MATS[key] = m
    return m


def water(deep, light, ripple=0.06):
    """Still water: a dark glossy surface with a slow ripple in its normal, mirroring what is
    lit around it (screen-space reflections)."""
    key = ("water", deep, light, ripple)
    if key in _MATS:
        return _MATS[key]
    m = bpy.data.materials.new("ST_water_%d" % len(_MATS))
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = _lin(_hex(deep))
    p.inputs["Roughness"].default_value = 0.06
    p.inputs["Specular Tint"].default_value = _lin(_hex(light))
    tc = nt.nodes.new("ShaderNodeTexCoord")
    wave = nt.nodes.new("ShaderNodeTexNoise")
    wave.inputs["Scale"].default_value = ripple * 100.0
    nt.links.new(tc.outputs["Object"], wave.inputs["Vector"])
    bn = nt.nodes.new("ShaderNodeBump")
    bn.inputs["Strength"].default_value = 0.12
    nt.links.new(wave.outputs["Fac"], bn.inputs["Height"])
    nt.links.new(bn.outputs["Normal"], p.inputs["Normal"])
    _MATS[key] = m
    return m


def ground(loc, size, material, subdiv=6, relief=6.0, seed=1):
    """A ground sheet with a gentle relief (a subdivided plane displaced by a cloud noise):
    no table-top flatness, and a horizon that is not a ruler line."""
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=loc)
    ob = bpy.context.active_object
    ob.scale = (size[0], size[1], 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    sub = ob.modifiers.new("sub", "SUBSURF")
    sub.subdivision_type = "SIMPLE"
    sub.levels = subdiv
    sub.render_levels = subdiv
    tex = bpy.data.textures.new("relief_%d" % seed, "CLOUDS")
    tex.noise_scale = 0.35
    disp = ob.modifiers.new("relief", "DISPLACE")
    disp.texture = tex
    disp.texture_coords = "OBJECT"
    disp.strength = relief
    return _finish(ob, material, 0.0, smooth=True)


def ridge(x, y, width, height, color, seed, peaks=5):
    """A far mountain range as a layered silhouette: a vertical sheet whose top edge is a sum
    of a few peaks (deterministic per seed), standing in the haze."""
    rng = random.Random(seed)
    n = 48
    tops = []
    centres = [(rng.uniform(-0.5, 0.5), rng.uniform(0.45, 1.0), rng.uniform(0.08, 0.2))
               for _ in range(peaks)]
    for i in range(n + 1):
        u = i / n - 0.5
        h = 0.18
        for cx, ch, cw in centres:
            h = max(h, ch * max(0.0, 1.0 - abs(u - cx) / cw) ** 1.3)
        h += 0.03 * math.sin(i * 1.7 + seed)
        tops.append(h)
    verts, faces = [], []
    for i, h in enumerate(tops):
        xx = x + (i / n - 0.5) * width
        verts.append((xx, y, -10.0))
        verts.append((xx, y + rng.uniform(-20, 20), h * height))
    for i in range(n):
        a = i * 2
        faces.append((a, a + 2, a + 3, a + 1))
    me = bpy.data.meshes.new("ridge")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new("ridge", me)
    bpy.context.scene.collection.objects.link(ob)
    m = mat("roof", 2, rough=1.0, color=color)
    return _finish(ob, m, 0.0)


def tufts(region, count, seed, colors=("#4b5f3c", "#5d7448", "#3e5133"), height=(4, 9)):
    """Grass tufts scattered over a region (x0, y0, x1, y1): small blades in clusters, so a
    meadow reads as grass at this distance and not as a painted floor."""
    rng = random.Random(seed)
    x0, y0, x1, y1 = region
    mats = [mat("moss", 2, color=c) for c in colors]
    for _ in range(count):
        cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
        m = mats[rng.randrange(len(mats))]
        for _blade in range(3):
            h = rng.uniform(*height)
            ob = cone((cx + rng.uniform(-3, 3), cy + rng.uniform(-3, 3), h / 2), 1.6, 0.0, h, m,
                      verts=4)
            ob.rotation_euler = (math.radians(rng.uniform(-18, 18)),
                                 math.radians(rng.uniform(-18, 18)), 0.0)


def stones(region, count, seed, color=("#5a5c63", "#73767f"), size=(3, 9)):
    rng = random.Random(seed)
    x0, y0, x1, y1 = region
    m = paint("stone", color[0], color[1], scale=0.35, bump=0.6)
    for _ in range(count):
        r = rng.uniform(*size)
        ball((rng.uniform(x0, x1), rng.uniform(y0, y1), r * 0.25), r, m,
             scale=(1.0, rng.uniform(0.7, 1.1), rng.uniform(0.45, 0.7)), outline=0.25,
             subdiv=1)


def sky_card(y, width, height, bottom, top, z0=-40.0, glow=None):
    """The sky as a painted card far behind everything: an emissive vertical gradient (horizon
    tone at the bottom, zenith at the top), with an optional sun glow `(x, z, radius, hex)`."""
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0.0, y, z0 + height / 2.0),
                                     rotation=(math.radians(90.0), 0.0, 0.0))
    ob = bpy.context.active_object
    ob.scale = (width, height, 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    m = bpy.data.materials.new("ST_sky")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = _lin(_hex(bottom))
    ramp.color_ramp.elements[1].position = 0.7
    ramp.color_ramp.elements[1].color = _lin(_hex(top))
    nt.links.new(sep.outputs["Y"], ramp.inputs[0])
    color = ramp.outputs[0]
    if glow:
        gx, gz, gr, gh = glow
        sun = nt.nodes.new("ShaderNodeTexGradient")
        sun.gradient_type = "SPHERICAL"
        mp = nt.nodes.new("ShaderNodeMapping")
        mp.inputs["Location"].default_value = (-(gx / width) - 0.5 + 0.5,
                                               -((gz - z0) / height), 0.0)
        mp.inputs["Scale"].default_value = (width / gr, height / gr, 1.0)
        nt.links.new(tc.outputs["Generated"], mp.inputs[0])
        nt.links.new(mp.outputs[0], sun.inputs[0])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "SCREEN"
        mix.inputs[7].default_value = _lin(_hex(gh))
        nt.links.new(sun.outputs["Fac"], mix.inputs["Factor"])
        nt.links.new(color, mix.inputs[6])
        color = mix.outputs[2]
    nt.links.new(color, em.inputs["Color"])
    em.inputs["Strength"].default_value = 1.0
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    ob.data.materials.append(m)
    ob.visible_shadow = False
    return ob


def ink_material():
    m = bpy.data.materials.get("ST_ink") or bpy.data.materials.new("ST_ink")
    m.use_nodes = True
    m.use_backface_culling = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = _lin((18 / 255, 18 / 255, 26 / 255))
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs["Surface"])
    return m


def ink(ob, thickness=0.5):
    """The style's one ink line, as the presentation renders draw it: an inverted hull."""
    if ob.type != "MESH":
        return
    ob.data.materials.append(ink_material())
    mod = ob.modifiers.new("ink", "SOLIDIFY")
    mod.thickness = -thickness
    mod.offset = 1.0
    mod.use_flip_normals = True
    mod.use_rim = False
    mod.material_offset = len(ob.data.materials) - 1


# --- primitives ------------------------------------------------------------------------------

def _finish(ob, material, outline, smooth=False):
    ob.data.materials.clear()
    ob.data.materials.append(material)
    if smooth:
        for poly in ob.data.polygons:
            poly.use_smooth = True
    if outline:
        ink(ob, outline)
    return ob


def box(loc, size, material, rot=(0, 0, 0), outline=0.45):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc, rotation=[math.radians(r) for r in rot])
    ob = bpy.context.active_object
    ob.scale = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(ob, material, outline)


def cyl(loc, r, depth, material, rot=(0, 0, 0), verts=20, outline=0.4):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc,
                                        rotation=[math.radians(v) for v in rot])
    return _finish(bpy.context.active_object, material, outline, smooth=True)


def cone(loc, r1, r2, depth, material, verts=24, outline=0.0):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=depth,
                                    location=loc)
    return _finish(bpy.context.active_object, material, outline, smooth=True)


def ball(loc, r, material, scale=(1, 1, 1), outline=0.0, subdiv=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=r, location=loc)
    ob = bpy.context.active_object
    ob.scale = scale
    return _finish(ob, material, outline, smooth=True)


def plane(loc, size, material, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=loc,
                                     rotation=[math.radians(r) for r in rot])
    ob = bpy.context.active_object
    ob.scale = (size[0], size[1], 1.0)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return _finish(ob, material, 0.0)


def prop(kind, params, at, yaw=0.0, scale=1.0, outline=0.6, recolor=None):
    """A village prop from the same geometry the game's sprites are rendered from."""
    parts = props3d.build({"kind": kind, "params": params or {}})
    obs = []
    for part in parts:
        me = bpy.data.meshes.new(part["name"])
        me.from_pydata([tuple(v) for v in part["verts"]], [],
                       [tuple(f) for f in part["faces"]])
        me.update()
        ob = bpy.data.objects.new(part["name"], me)
        bpy.context.scene.collection.objects.link(ob)
        name = part["material"]
        if recolor and name in recolor:
            m = recolor[name]
        else:
            m = mat(name if name in RAMPS else "stone", 2)
        _finish(ob, m, outline, smooth=part.get("smooth", False))
        ob.scale = (scale, scale, scale)
        ob.rotation_euler = Euler((0, 0, math.radians(yaw)))
        ob.location = at
        obs.append(ob)
    return obs


def light_point(loc, color, energy, radius=1.0):
    data = bpy.data.lights.new("pt", "POINT")
    data.color = _hex(color)
    data.energy = energy * LIGHT_SCALE
    data.shadow_soft_size = radius
    ob = bpy.data.objects.new("pt", data)
    ob.location = loc
    bpy.context.scene.collection.objects.link(ob)
    return ob


def light_sun(direction, color, energy, angle=2.0):
    data = bpy.data.lights.new("sun", "SUN")
    data.color = _hex(color)
    data.energy = energy
    data.angle = math.radians(angle)
    ob = bpy.data.objects.new("sun", data)
    ob.rotation_euler = Vector(direction).normalized().to_track_quat("Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def light_spot(loc, target, color, energy, size_deg=40.0, blend=0.6):
    data = bpy.data.lights.new("spot", "SPOT")
    data.color = _hex(color)
    data.energy = energy * LIGHT_SCALE
    data.spot_size = math.radians(size_deg)
    data.spot_blend = blend
    data.shadow_soft_size = 2.0
    ob = bpy.data.objects.new("spot", data)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def light_area(loc, target, color, energy, size=200.0):
    """A soft fill (a large area light): what keeps a night interior legible without
    flattening its one warm source."""
    data = bpy.data.lights.new("area", "AREA")
    data.color = _hex(color)
    data.energy = energy * LIGHT_SCALE
    data.size = size
    ob = bpy.data.objects.new("area", data)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    return ob


def roof(x0, x1, y0, y1, z_eave, z_ridge, overhang, side_over, material, lift=10.0):
    """An East Asian roof from the props' own geometry (`props3d.gable_roof`): tile courses,
    the swept-up corners, the ridge and its end ornaments — the eave the village is built of."""
    slopes, fascia, ridge_tube, ends = props3d.gable_roof(x0, x1, y0, y1, z_eave, z_ridge,
                                                          overhang, side_over, lift=lift)
    obs = []
    for i, m in enumerate(list(slopes) + [fascia, ridge_tube] + list(ends)):
        me = bpy.data.meshes.new("roof%d" % i)
        me.from_pydata([tuple(v) for v in m.verts], [], [tuple(f) for f in m.faces])
        me.update()
        ob = bpy.data.objects.new("roof%d" % i, me)
        bpy.context.scene.collection.objects.link(ob)
        _finish(ob, material, 0.4, smooth=False)
        obs.append(ob)
    return obs


def camera(loc, target, lens=35.0):
    data = bpy.data.cameras.new("cam")
    data.lens = lens
    data.clip_start = 1.0
    data.clip_end = 4000.0
    ob = bpy.data.objects.new("cam", data)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(ob)
    bpy.context.scene.camera = ob
    return ob


def world(sky_top, sky_bottom, strength=1.0, fog=None):
    """The world colour behind everything: the horizon tone (a diorama camera rarely sees sky),
    lighting the scene as a soft ambient. `sky_top` tints the ambient from above. Mist is local
    (`mist`), never a world volume — a world volume over a scene hundreds of units deep is a
    wall."""
    w = bpy.data.worlds.new("ST_world")
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = strength
    top, bottom = _hex(sky_top), _hex(sky_bottom)
    bg.inputs["Color"].default_value = _lin(tuple((a + b) * 0.5 for a, b in zip(top, bottom)))
    nt.links.new(bg.outputs[0], out.inputs["Surface"])
    bpy.context.scene.world = w
    if fog:
        mist((0, 900, 40), (5000, 2400, 260), fog[0], fog[1] * 0.25)


def mist(loc, size, color, density, soft=True):
    """Mist or smoke: a volume whose density falls to nothing at its edges (a spherical
    gradient times a cloud noise), so no box edge is ever seen. `soft=False`: an even layer."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    ob = bpy.context.active_object
    ob.scale = size
    m = bpy.data.materials.new("ST_mist")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    vol = nt.nodes.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = _lin(_hex(color))
    vol.inputs["Anisotropy"].default_value = 0.3
    dens = nt.nodes.new("ShaderNodeMath")
    dens.operation = "MULTIPLY"
    dens.inputs[1].default_value = density * FOG_SCALE * 10.0
    if soft:
        tc = nt.nodes.new("ShaderNodeTexCoord")
        grad = nt.nodes.new("ShaderNodeTexGradient")
        grad.gradient_type = "SPHERICAL"
        mapping = nt.nodes.new("ShaderNodeMapping")
        mapping.inputs["Location"].default_value = (0.0, 0.0, 0.0)
        mapping.inputs["Scale"].default_value = (2.0, 2.0, 2.0)
        nt.links.new(tc.outputs["Object"], mapping.inputs[0])
        nt.links.new(mapping.outputs[0], grad.inputs[0])
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 3.0
        noise.inputs["Detail"].default_value = 4.0
        nt.links.new(tc.outputs["Object"], noise.inputs[0])
        both = nt.nodes.new("ShaderNodeMath")
        both.operation = "MULTIPLY"
        nt.links.new(grad.outputs["Fac"], both.inputs[0])
        nt.links.new(noise.outputs["Fac"], both.inputs[1])
        nt.links.new(both.outputs[0], dens.inputs[0])
    else:
        dens.inputs[0].default_value = 1.0
    nt.links.new(dens.outputs[0], vol.inputs["Density"])
    nt.links.new(vol.outputs[0], out.inputs["Volume"])
    ob.data.materials.append(m)
    return ob


def figure(at, yaw_deg=180.0, pose="idle", frame=0, robe=None):
    """The canonical cultivator (player_proto's design), posed, in Principled materials so it
    takes the scene's coloured light; seen from behind it fits either look of the wanderer."""
    spec = build_actor.load_spec(ACTOR_SPEC)
    coll = bpy.context.scene.collection
    rig = build_actor.build_armature(spec, coll)
    mats = {}
    for name, mspec in spec["materials"].items():
        tone = mspec["ramp"][2]
        rgb = tuple(c / 255.0 for c in tone) if isinstance(tone, (list, tuple)) else _hex(tone)
        if robe and name in robe:
            rgb = _hex(robe[name])
        m = bpy.data.materials.new("ST_fig_" + name)
        m.use_nodes = True
        p = m.node_tree.nodes.get("Principled BSDF")
        p.inputs["Base Color"].default_value = _lin(rgb)
        p.inputs["Roughness"].default_value = 0.7 if name != "hair" else 0.45
        if name == "hair":
            p.inputs["Specular IOR Level"].default_value = 0.7
        mats[name] = m
    obs = build_actor.build_meshes(spec, rig, coll, mats)
    for ob in obs:
        mod = ob.modifiers.get("ink_hull")
        if mod:
            mod.show_render = True
            mod.thickness = -0.35
        ob.hide_render = ob.get("aetheria_lod", "all") not in ("all", "portrait")
    build_actor.apply_pose(rig, motion.ANIMATIONS[pose](spec, frame))
    rig.location = at
    rig.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    return rig


# --- the five pasts --------------------------------------------------------------------------

def scene_ho_tieu():
    """Ash at the ford, the morning after: the convoy's wagons burnt out across the post road,
    embers still alive, the ruts running on without them. The escort stands where the road
    meets the water and looks at what they were paid to guard."""
    world("#7d8aa3", "#c4b4a2", 0.55)
    sky_card(2600, 6000, 1500, "#e9b98a", "#41506d", glow=(260, 120, 900, "#ffd8a0"))
    for i, (yy, col) in enumerate(((2200, "#59647a"), (1800, "#6d7489"), (1450, "#848598"))):
        ridge(0, yy, 5200, 620 - i * 120, col, seed=21 + i, peaks=6)
    mist((0, 1700, 80), (7000, 1600, 700), "#d8c6b4", 0.045)
    meadow = paint("moss", "#3a4733", "#56603f", "#6e6b4b", scale=0.012, bump=0.15)
    ground((0, 500, -2), (3000, 2400), meadow, relief=10.0, seed=3)
    road = paint("timber_light", "#4f3d2e", "#6f5843", "#8a7259", scale=0.03, bump=0.4)
    ground((0, 240, 0.8), (190, 1100), road, subdiv=5, relief=2.0, seed=4)
    ground((0, 270, 1.6), (1400, 70), water("#2a3c4f", "#ffd2a0"), subdiv=3, relief=0.6,
           seed=5)
    for x in (-38, -16, 16, 38):                                     # the ruts, deep and dark
        box((x * 0.5, 110, 1.2), (3.2, 280, 0.6), mat("door", 0), outline=0)
    char = paint("door", "#140e0b", "#2a1b14", "#3d2a1e", scale=0.22, rough=0.95,
                 emit=("#ff6a1e", 4.0), emit_mask="crack")
    burnt = {n: char for n in ("timber", "timber_light", "wood_pale", "vein_stone", "paper")}
    prop("cart_wreck", {}, (-75, 230, 0), yaw=25, scale=1.6, recolor=burnt)
    prop("cart_wreck", {}, (80, 310, 0), yaw=-40, scale=1.5, recolor=burnt)
    prop("cart_wreck", {}, (220, 460, 0), yaw=70, scale=1.35, recolor=burnt)
    prop("cart_wreck", {}, (-240, 520, 0), yaw=-15, scale=1.3, recolor=burnt)
    rng = random.Random(7)
    for _ in range(18):                                              # broken planks and ash
        x, y = rng.uniform(-220, 260), rng.uniform(160, 520)
        box((x, y, 1.5), (rng.uniform(14, 26), rng.uniform(3, 5), 2.0), char,
            rot=(0, 0, rng.uniform(0, 180)), outline=0.25)
    embers = mat("door", 0, emit="#ff7a2a", emit_strength=14.0)
    for x, y in ((-70, 225), (-40, 245), (85, 306), (64, 330), (215, 456), (-235, 515)):
        ball((x, y, 3), 3.2, embers, scale=(1.5, 1.0, 0.45))
        light_point((x, y, 12), "#ff8a3c", 900.0, 8.0)
    for x, y, h in ((-60, 250, 300), (90, 340, 360)):              # smoke, rising
        mist((x + 20, y + 40, h / 2), (60, 60, h), "#4c4846", 0.12)
    tufts((-700, -60, -110, 900), 220, 1)
    tufts((110, -60, 700, 900), 220, 2)
    stones((-500, -40, 500, 700), 40, 3)
    for x, y, s in ((-360, 420, 1.7), (-290, 610, 2.0), (390, 560, 1.9), (330, 400, 1.4),
                    (-470, 280, 1.6), (470, 250, 1.5), (-540, 700, 2.2), (560, 760, 2.3)):
        prop("pine", {"seed": int(abs(x)) % 13 + 1, "scale": 1.0}, (x, y, 0), scale=s)
    figure((-34, 40, 1.0), yaw_deg=172.0)
    light_sun((0.25, 0.95, 0.28), "#ffc888", 4.5, angle=3.0)         # dawn, behind the smoke
    light_sun((-0.6, -0.5, 0.7), "#8fa8e8", 0.9)                     # the cold of the morning
    camera((10, -170, 105), (20, 330, 40), lens=30)


def scene_de_tu_bi_loai():
    """The board at the sect gate, last season: a long stair of stone up to the gate in the
    morning, the list of names hung where the light falls, and the candidate at the foot of the
    stair who is not on it."""
    world("#6f86a6", "#c9bfae", 0.45)
    sky_card(2400, 6000, 1700, "#efcfa0", "#5b7aa3", glow=(-300, 420, 1000, "#ffe2b0"))
    for i, (yy, col) in enumerate(((2200, "#7f93b0"), (1900, "#93a3ba"), (1600, "#aab5c6"))):
        ridge(0, yy, 5600, 900 - i * 160, col, seed=31 + i, peaks=5)
    mist((0, 1500, 120), (7000, 1500, 600), "#e8e2d8", 0.035)
    stone = paint("stone_light", "#6a6c73", "#82848b", "#9a9ba1", scale=0.06, bump=0.5)
    ground((0, 400, -2), (3000, 2600), paint("stone", "#5e6068", "#73757d", scale=0.01),
           relief=6.0, seed=6)
    steps = 16
    for i in range(steps):                                         # the stair
        box((0, 90 + i * 17, i * 7 + 3.5), (200 - i * 2, 17, 7), stone, outline=0.3)
    top_y, top_z = 90 + steps * 17, steps * 7
    box((0, top_y + 90, top_z - 1), (520, 200, 2), stone, outline=0.3)
    lac = paint("lacquer_red", "#6e1f25", "#8f2a31", scale=0.2, rough=0.45, bump=0.1)
    roof_mat = paint("roof_dark", "#1d222c", "#2c3340", "#3a4252", scale=0.1)
    gy = top_y + 70                                                # the sect gate: a pailou
    for x, h in ((-140, 110), (-60, 140), (60, 140), (140, 110)):
        cyl((x, gy, top_z + h / 2), 7.5, h, lac)
        box((x, gy, top_z + 4), (22, 22, 8), stone)
    box((0, gy, top_z + 128), (130, 9, 10), lac)                   # lintels
    for side in (-1, 1):
        box((side * 100, gy, top_z + 100), (90, 8, 8), lac)
    plaque = paint("gilt", "#86683a", "#c9a865", scale=0.3, rough=0.3)
    box((0, gy - 6, top_z + 112), (56, 3, 18), plaque)
    roof(-66, 66, gy - 8, gy + 8, top_z + 140, top_z + 156, 10, 14, roof_mat, lift=12.0)
    for side in (-1, 1):
        roof(side * 100 - 42, side * 100 + 42, gy - 7, gy + 7, top_z + 110, top_z + 123, 9,
             10, roof_mat, lift=9.0)
    board = paint("paper", "#c9bd9c", "#e6dcc0", scale=0.25, rough=0.6)
    box((165, top_y + 20, top_z + 34), (80, 8, 66), paint("timber", "#3d291c", "#523726",
                                                          scale=0.3))
    box((165, top_y + 15, top_z + 38), (68, 2, 54), board, outline=0.2)
    ink = mat("door", 0)
    for r in range(6):                                             # the names; one gap
        for k in range(3):
            if (r, k) == (4, 1):
                continue
            box((145 + k * 20, top_y + 13.6, top_z + 58 - r * 8), (14, 0.8, 2.2), ink,
                outline=0)
    light_spot((360, top_y - 220, top_z + 260), (165, top_y, top_z + 40), "#fff0c8", 60000,
               22, 0.5)
    tufts((-700, -40, -130, 700), 120, 7, colors=("#56684a", "#6c7d58", "#4a5c40"))
    tufts((130, -40, 700, 700), 120, 8, colors=("#56684a", "#6c7d58", "#4a5c40"))
    for x, y, s in ((-260, 340, 1.8), (-340, 220, 1.5), (300, 420, 1.9), (390, 290, 1.6),
                    (-250, 540, 2.1), (270, 620, 2.2), (-480, 420, 2.0), (500, 520, 2.1)):
        prop("pine", {"seed": int(abs(x)) % 11 + 2, "scale": 1.0}, (x, y, 0), scale=s)
    mist((0, 60, 6), (1400, 200, 36), "#eef0f2", 0.12)              # morning mist on the steps
    figure((-24, 30, 0), yaw_deg=170.0)
    light_sun((-0.55, 0.65, 0.35), "#ffe2b8", 4.2, angle=2.0)
    light_sun((0.5, -0.6, 0.5), "#a8bde0", 0.8)
    camera((-40, -190, 70), (30, 260, 110), lens=30)


def scene_lang_y():
    """The fourth fever, early this season: a hamlet room at night, an old man under a blanket,
    the lamp, the healer sitting the vigil out — and the cold of the window behind."""
    world("#101624", "#151c2c", 0.6)
    floor = paint("timber", "#33241a", "#47321f", "#5a4029", scale=0.08, bump=0.4)
    ground((0, 100, 0), (520, 420), floor, subdiv=3, relief=0.5, seed=9)
    wall = paint("plaster", "#6f6757", "#8c8473", "#a39a85", scale=0.05, bump=0.25)
    box((0, 236, 80), (520, 10, 160), wall, outline=0)
    box((-205, 100, 80), (10, 300, 160), wall, outline=0)
    for x in (-150, -40, 70, 180):                                  # posts and beams
        box((x, 230, 80), (8, 8, 160), paint("timber", "#2b1d14", "#3d291c", scale=0.2))
    box((0, 228, 156), (520, 10, 10), paint("timber", "#2b1d14", "#3d291c", scale=0.2))
    box((110, 230, 92), (70, 6, 54), mat("door", 0), outline=0.3)     # the window
    box((110, 229, 92), (60, 2, 44), mat("water", 3, emit="#5f7fbf", emit_strength=2.0))
    for k in range(3):
        box((96 + k * 14, 228, 92), (1.6, 2, 44), mat("door", 0), outline=0)
    light_spot((150, 330, 150), (-30, 150, 20), "#6f8fd0", 70000, 30, 0.8)
    bed = paint("timber_light", "#5a3d29", "#6f4c33", scale=0.15)
    box((-50, 150, 10), (140, 64, 20), bed)                          # the bed
    blanket = paint("paper", "#6b5a4c", "#7d6a5a", "#8a7766", scale=0.18, bump=0.5)
    box((-45, 150, 22), (128, 56, 6), paint("paper", "#a39782", "#b9ad97", scale=0.2))
    ball((-10, 150, 28), 14, blanket, scale=(3.6, 1.6, 0.7), outline=0.3)
    ball((-100, 150, 30), 8, paint("plaster", "#b8927a", "#c9a58a", scale=0.3),
         scale=(1, 1.1, 0.85), outline=0.3)
    ball((-104, 150, 36), 8.4, paint("paper", "#9a9a9e", "#c4c4c8", scale=0.4),
         scale=(1, 1.1, 0.6))                                        # white hair on the pillow
    table = paint("timber", "#3d291c", "#523726", scale=0.2)
    box((-118, 108, 12), (34, 30, 24), table)                         # the low table
    cyl((-122, 106, 27), 4, 6, mat("stone_light", 2))                 # the lamp
    ball((-122, 106, 33), 1.8, mat("door", 0, emit="#ffb25a", emit_strength=60.0))
    light_point((-122, 106, 40), "#ffab55", 3200.0, 2.0)
    light_area((260, -120, 260), (0, 140, 0), "#4a5f8f", 900.0, 300.0)
    for i, (x, y) in enumerate(((-108, 116), (-110, 98), (-100, 108))):   # jars of the trade
        cyl((x, y, 26 + i), 3 + i, 6 + 2 * i, paint("plaster", "#7a6650", "#94806a",
                                                      scale=0.4))
    for i in range(7):                                                # herbs drying
        box((-170 + i * 20, 226, 128), (5, 4, 26), paint("leaves", "#2a4d36", "#3a6440",
                                                          scale=0.5), outline=0.2)
    box((-60, 226, 142), (240, 2, 2), mat("door", 1), outline=0)
    figure((10, 96, 0), yaw_deg=200.0, pose="meditate", frame=0)
    light_point((-70, 108, 60), "#ffb066", 1800.0, 6.0)               # the lamp's spill
    camera((120, -120, 120), (-40, 160, 18), lens=36)


def scene_nghe_nhan():
    """Wrong at the root, last year: the workshop at night, the kiln still hot, and on the bench
    the patron's spirit stone split open — its broken heart showing the wrong light."""
    world("#120f14", "#1d1719", 0.6)
    ground((0, 100, 0), (640, 520), paint("stone", "#3a3a40", "#4d4d55", "#5c5c64",
                                          scale=0.05, bump=0.5), subdiv=3, relief=0.5)
    wall = paint("plaster", "#4a443c", "#5e574c", scale=0.05, bump=0.3)
    box((0, 246, 100), (640, 10, 200), wall, outline=0)
    box((-250, 100, 100), (10, 300, 200), wall, outline=0)
    brick = paint("lacquer_red", "#4a2c22", "#5f3a2d", "#704636", scale=0.3, bump=0.8)
    box((-140, 196, 44), (100, 80, 88), brick)                        # the kiln
    cyl((-140, 196, 108), 32, 44, brick)
    cyl((-140, 196, 160), 14, 70, brick)
    box((-140, 155, 30), (44, 4, 32), mat("door", 0, emit="#ff6a1c", emit_strength=30.0),
        outline=0)
    light_point((-140, 140, 34), "#ff7b30", 5000.0, 10.0)
    light_point((-140, 110, 12), "#ff7b30", 1500.0, 6.0)
    light_spot((-40, 60, 60), (-140, 196, 60), "#ff9a50", 9000, 60, 0.9)
    light_area((300, -120, 280), (0, 150, 0), "#3e4a6a", 900.0, 320.0)
    bench = paint("timber_light", "#5a3d29", "#6f4c33", "#83603f", scale=0.15, bump=0.4)
    box((40, 128, 24), (160, 64, 6), bench)                          # the bench
    for x in (-30, 110):
        box((x, 128, 10.5), (8, 54, 21), paint("timber", "#2b1d14", "#3d291c", scale=0.2))
    vein = paint("vein_stone", "#4f7f94", "#7fb4c6", "#b4dcea", scale=0.4, rough=0.25,
                 bump=0.6)
    ball((28, 126, 34), 8.5, vein, scale=(1.2, 1.0, 0.9), outline=0.35, subdiv=1)
    ball((48, 130, 32), 7.5, vein, scale=(1.1, 1.0, 0.8), outline=0.35, subdiv=1)
    ball((38, 128, 32), 3.2, mat("vein_stone", 3, emit="#8fe6ff", emit_strength=30.0),
         scale=(1.0, 1.0, 1.5))
    light_point((38, 118, 42), "#7fe0ff", 900.0, 1.5)
    for i, (x, w) in enumerate(((84, 3), (94, 2), (104, 4))):          # chisels
        box((x, 118, 27.5), (w, 26, 2), mat("stone_light", 3, rough=0.3), rot=(0, 0, 10 * i))
    for i in range(4):                                                # shelves of cut stone
        box((180, 240, 44 + i * 32), (130, 12, 3), paint("timber", "#2b1d14", "#3d291c",
                                                         scale=0.2))
        for j in range(5):
            ball((128 + j * 26, 238, 51 + i * 32), 5.5, paint("stone_light", "#7a7d86",
                 "#9598a0", scale=0.5), outline=0.2, subdiv=1)
    mist((-130, 170, 170), (160, 120, 160), "#5a4036", 0.015)
    figure((70, 84, 0), yaw_deg=200.0)
    camera((170, -120, 120), (-20, 170, 40), lens=32)


def scene_thu_thu():
    """Half a ledger, forty days ago: the record hall after hours, the mentor's lamp still warm
    on a desk of torn pages — and at the far end, a shape in the open door, asking for you."""
    world("#0f1219", "#161b26", 0.6)
    ground((0, 260, 0), (760, 1000), paint("timber", "#2c2018", "#3b2a1e", "#4a3424",
                                           scale=0.04, bump=0.3), subdiv=3, relief=0.4)
    shelf = paint("timber", "#2b1d14", "#3d291c", "#4c3423", scale=0.2, bump=0.3)
    scroll = paint("paper", "#b5aa8c", "#d6ccb0", scale=0.6)
    seal = paint("lacquer_red", "#5e1c22", "#7e262d", scale=0.6)
    rng = random.Random(11)
    for side in (-1, 1):                                             # aisles of shelves
        for row in range(4):
            x, y = side * 160, 190 + row * 120
            box((x, y, 76), (120, 32, 152), shelf)
            for level in range(4):
                for k in range(7):
                    cyl((x - 48 + k * 16, y - 15, 20 + level * 36), rng.uniform(3.2, 5.2), 12,
                        scroll if rng.random() > 0.2 else seal, rot=(90, 0, 0), verts=10,
                        outline=0.2)
    box((0, 700, 80), (100, 8, 160), mat("door", 0), outline=0)       # the far door
    box((0, 697, 66), (56, 4, 132), mat("plaster", 3, emit="#9fb7e0", emit_strength=4.0),
        outline=0)
    light_spot((0, 780, 130), (0, 400, 0), "#9fb7e0", 90000, 30, 0.6)
    stranger = mat("door", 0)
    cyl((0, 688, 27), 8, 54, stranger, outline=0)                      # who is asking
    ball((0, 688, 60), 6.5, stranger)
    desk = paint("timber_light", "#5a3d29", "#6f4c33", scale=0.15)
    box((0, 110, 21), (96, 50, 4), desk)                              # the desk
    for x in (-40, 40):
        box((x, 110, 9.5), (6, 42, 19), paint("timber", "#2b1d14", "#3d291c", scale=0.2))
    page = paint("paper", "#d6ccb0", "#e8dfc6", scale=0.5, rough=0.6)
    box((-13, 108, 24), (26, 36, 1.6), page, rot=(0, -6, 4))           # the half-ledger
    box((14, 108, 24), (26, 36, 1.6), page, rot=(0, 6, -3))
    for k in range(7):                                                 # the copied mark
        box((-14, 98 + k * 4, 25.0), (14, 1.0, 0.4), mat("door", 0), rot=(0, -6, 4), outline=0)
    for x, y, r in ((34, 146, 30), (-46, 88, 75), (56, 78, 12), (-22, 156, 52), (12, 170, 18)):
        box((x, y, 0.6), (18, 24, 0.6), page, rot=(0, 0, r), outline=0.2)   # torn pages
    cyl((36, 118, 26), 3.2, 5, mat("stone_light", 2))                   # the lamp, still warm
    ball((36, 118, 31), 1.5, mat("door", 0, emit="#ffbc66", emit_strength=60.0))
    light_point((36, 118, 38), "#ffb060", 4200.0, 2.0)
    light_area((260, -140, 280), (0, 200, 0), "#3d4a6c", 900.0, 320.0)
    mist((0, 560, 60), (420, 360, 140), "#2e3548", 0.012)
    figure((-12, 64, 0), yaw_deg=170.0)
    camera((50, -150, 130), (0, 320, 30), lens=31)


SCENES = {
    "origin_ho_tieu": scene_ho_tieu,
    "origin_de_tu_bi_loai": scene_de_tu_bi_loai,
    "origin_lang_y": scene_lang_y,
    "origin_nghe_nhan": scene_nghe_nhan,
    "origin_thu_thu": scene_thu_thu,
}


def configure(scene):
    scene.render.engine = "BLENDER_EEVEE"
    scene.eevee.taa_render_samples = SAMPLES
    scene.eevee.use_shadows = True
    scene.eevee.use_raytracing = True
    scene.eevee.ray_tracing_options.resolution_scale = "2"
    scene.eevee.volumetric_tile_size = "4"
    scene.eevee.volumetric_samples = 64
    scene.eevee.volumetric_end = 3000.0
    scene.render.resolution_x = WIDTH
    scene.render.resolution_y = HEIGHT
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Medium High Contrast"


## A night interior is low key by design, but its subject must still read at a card's size:
## the exposure each picture is developed at (stops).
EXPOSURE = {"origin_lang_y": 1.3, "origin_nghe_nhan": 1.2, "origin_thu_thu": 1.4}


def render(origin_id, out_dir):
    build_actor.reset_scene()
    _MATS.clear()
    scene = bpy.context.scene
    SCENES[origin_id]()
    configure(scene)
    scene.view_settings.exposure = EXPOSURE.get(origin_id, 0.0)
    scene.render.filepath = os.path.join(out_dir, origin_id + "_raw.png")
    bpy.ops.render.render(write_still=True)
    return scene.render.filepath


def main(argv):
    out_dir = argv[0]
    wanted = argv[1:] or list(ORIGINS)
    os.makedirs(out_dir, exist_ok=True)
    RAMPS.update(_prop_ramps())
    for origin_id in wanted:
        print("[story_art] wrote", render(origin_id, out_dir))


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
