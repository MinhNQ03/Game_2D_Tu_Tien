"""Blender-side VFX renderer: qi_gather / attack_slash / vein_erupt frame sequences.

    blender -b -P tools/aetheria_art_pipeline/blender/build_vfx.py -- \\
        --effect qi_gather --rawdir <dir>

Renders with CYCLES on the CPU (this environment has no libEGL, so EEVEE cannot
start). Emission-only materials -- no lights, no shadows, no volumetrics --
transparent film, orthographic cameras. Every frame is posed PARAMETRICALLY from
the frame index (no keyframes, no RNG, CYCLES seed fixed): re-running the same
command produces byte-identical raw PNGs.

The raw frames are finished by the system Python step (pngout -> assets/vfx/);
see the VFX DESIGN docs. Palette roles come from style/aetheria_style.yaml:
qi #85ccea, jade #5cc79e, antique gold #c9a865 -- plus white cores per the VFX
grammar (MOTION_DESIGN_CONTRACT M-2.1: the element's own hue + white core).
"""
import argparse
import math
import os
import sys

import bpy
import bmesh
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Euler, Vector

# ---------------------------------------------------------------- palette (sRGB) ---
QI = "#85ccea"          # style qi: cultivation / linh khi
QI_DEEP = "#2c7a63"     # jade in shadow
JADE = "#5cc79e"
WHITE = "#ffffff"
GOLD = "#e8a83e"        # technique-fire gold (brighter than antique #c9a865: this is energy)
GOLD_LIGHT = "#f7d774"
GOLD_CORE = "#fff6e0"

CYCLES_SEED = 11


def _srgb_to_linear_triplet(hexstr):
    h = hexstr.lstrip("#")
    out = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)


# ------------------------------------------------------------ easing (pure math) ---
def clamp01(x):
    return 0.0 if x <= 0.0 else (1.0 if x >= 1.0 else x)


def smoothstep(a, b, x):
    t = clamp01((x - a) / (b - a)) if b > a else 0.0
    return t * t * (3.0 - 2.0 * t)


def ease_out_quad(x):
    x = clamp01(x)
    return 1.0 - (1.0 - x) * (1.0 - x)


def ease_in_quad(x):
    x = clamp01(x)
    return x * x


# ------------------------------------------------------------------- scene ---
def clear_all():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for coll in (bpy.data.meshes, bpy.data.curves, bpy.data.materials,
                 bpy.data.cameras, bpy.data.lights):
        for x in list(coll):
            coll.remove(x)


def setup_render(w, h, samples):
    sc = bpy.context.scene
    r = sc.render
    r.engine = "CYCLES"
    r.resolution_x, r.resolution_y = w, h
    r.resolution_percentage = 100
    r.film_transparent = True
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    r.image_settings.color_depth = "8"
    c = sc.cycles
    c.samples = samples
    c.device = "CPU"
    c.seed = CYCLES_SEED
    c.use_denoising = False
    sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    return sc


def make_camera(name, elevation_deg, ortho_scale):
    """Orthographic camera; elevation 30 == the gameplay camera (build_actor)."""
    cd = bpy.data.cameras.new(name)
    cd.type = "ORTHO"
    cd.ortho_scale = ortho_scale
    ob = bpy.data.objects.new(name, cd)
    bpy.context.scene.collection.objects.link(ob)
    ob.rotation_euler = Euler((math.radians(90.0 - elevation_deg), 0.0, 0.0), "XYZ")
    ob.location = (0.0, -100.0, 100.0 * math.tan(math.radians(elevation_deg))
                   if elevation_deg > 0.5 else 0.0)
    return ob


def aim(ob, target_world, anchor_px, w, h):
    """Shift the ortho camera so target_world projects exactly at anchor_px.

    Exact in one step (orthographic projection is linear); asserts < 0.6 px error.
    """
    sc = bpy.context.scene
    sc.camera = ob
    bpy.context.view_layer.update()
    v = world_to_camera_view(sc, ob, Vector(target_world))
    want = Vector((anchor_px[0] / w, 1.0 - anchor_px[1] / h))
    s = ob.data.ortho_scale
    # visible height in world units = s * h / w; moving the camera +localY moves the
    # projected point -viewY.
    dx = (v.x - want.x) * s
    dy = (v.y - want.y) * s * h / w
    m3 = ob.matrix_world.to_3x3()
    lx, ly = m3 @ Vector((1, 0, 0)), m3 @ Vector((0, 1, 0))
    ob.location = ob.location + lx * dx + ly * dy
    bpy.context.view_layer.update()
    v2 = world_to_camera_view(sc, ob, Vector(target_world))
    ex, ey = abs(v2.x - want.x) * w, abs(v2.y - want.y) * h
    assert ex < 0.6 and ey < 0.6, "aim failed: err=(%.2f, %.2f)px" % (ex, ey)
    print("aim: target -> (%.1f, %.1f)px" % (v2.x * w, (1.0 - v2.y) * h))


# ------------------------------------------------------------------ nodes ---
def _node(nt, typ, **kw):
    n = nt.nodes.new(typ)
    for k, v in kw.items():
        setattr(n, k, v)
    return n


def _link(nt, a, b):
    nt.links.new(a, b)


def _fade_chain(nt, out, emi, transp, grad_out):
    """grad_out (0..1 brightness shape) * fade uniform -> Mix(Transparent, Emission)."""
    fade = _node(nt, "ShaderNodeMath", operation="MULTIPLY")
    fade.inputs[1].default_value = 1.0
    mix = _node(nt, "ShaderNodeMixShader")
    _link(nt, grad_out, fade.inputs[0])
    _link(nt, fade.outputs["Value"], mix.inputs["Fac"])
    _link(nt, transp.outputs["BSDF"], mix.inputs[1])
    _link(nt, emi.outputs["Emission"], mix.inputs[2])
    _link(nt, mix.outputs["Shader"], out.inputs["Surface"])
    return fade


def _white_core(nt, emi, dist_value, hex_color, edge_at=1.6):
    """White at the centre fading to hex_color: the VFX grammar's white core."""
    gain = _node(nt, "ShaderNodeMath", operation="MULTIPLY")
    gain.inputs[1].default_value = edge_at
    clamp = _node(nt, "ShaderNodeClamp")
    clamp.inputs["Min"].default_value = 0.0
    clamp.inputs["Max"].default_value = 1.0
    cmap = _node(nt, "ShaderNodeMix", data_type="RGBA", blend_type="MIX")
    cmap.inputs["A"].default_value = (*_srgb_to_linear_triplet(WHITE), 1.0)
    cmap.inputs["B"].default_value = (*_srgb_to_linear_triplet(hex_color), 1.0)
    _link(nt, dist_value, gain.inputs[0])
    _link(nt, gain.outputs["Value"], clamp.inputs["Value"])
    _link(nt, clamp.outputs["Result"], cmap.inputs["Factor"])
    _link(nt, cmap.outputs["Result"], emi.inputs["Color"])


# --------------------------------------------------------------- materials ---
def _base_mat(name):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    m.node_tree.nodes.clear()
    return m


def solid_emission(name, hex_color, strength=3.0):
    """Opaque emissive material (crystals, shards, orbs)."""
    m = _base_mat(name)
    nt = m.node_tree
    out = _node(nt, "ShaderNodeOutputMaterial")
    emi = _node(nt, "ShaderNodeEmission")
    emi.inputs["Color"].default_value = (*_srgb_to_linear_triplet(hex_color), 1.0)
    emi.inputs["Strength"].default_value = strength
    _link(nt, emi.outputs["Emission"], out.inputs["Surface"])
    return m


def radial_disc_mat(name, hex_color, radius, strength=3.0, power=2.0,
                    core_white=True):
    """Camera-agnostic soft disc: white core -> hue -> transparent edge.

    Uses Object coordinates (no UVs needed): valid for any mesh centred on its
    local origin. Returns (material, fade_node); set fade_node.inputs[1] per frame.
    """
    m = _base_mat(name)
    nt = m.node_tree
    out = _node(nt, "ShaderNodeOutputMaterial")
    transp = _node(nt, "ShaderNodeBsdfTransparent")
    emi = _node(nt, "ShaderNodeEmission")
    emi.inputs["Strength"].default_value = strength
    texco = _node(nt, "ShaderNodeTexCoord")
    xy = _node(nt, "ShaderNodeVectorMath", operation="SUBTRACT")
    xy.inputs[1].default_value = (0.0, 0.0, 0.0)
    leng = _node(nt, "ShaderNodeVectorMath", operation="LENGTH")
    norm = _node(nt, "ShaderNodeMath", operation="DIVIDE")
    norm.inputs[1].default_value = radius
    inv = _node(nt, "ShaderNodeMath", operation="SUBTRACT")
    inv.inputs[0].default_value = 1.0
    clamp = _node(nt, "ShaderNodeClamp")
    clamp.inputs["Min"].default_value = 0.0
    clamp.inputs["Max"].default_value = 1.0
    pw = _node(nt, "ShaderNodeMath", operation="POWER")
    pw.inputs[1].default_value = power
    _link(nt, texco.outputs["Object"], xy.inputs[0])
    _link(nt, xy.outputs["Vector"], leng.inputs[0])
    _link(nt, leng.outputs["Value"], norm.inputs[0])
    _link(nt, norm.outputs["Value"], inv.inputs[1])
    _link(nt, inv.outputs["Value"], clamp.inputs["Value"])
    _link(nt, clamp.outputs["Result"], pw.inputs[0])
    if core_white:
        _white_core(nt, emi, norm.outputs["Value"], hex_color)
    else:
        emi.inputs["Color"].default_value = (*_srgb_to_linear_triplet(hex_color), 1.0)
    fade = _fade_chain(nt, out, emi, transp, pw.outputs["Value"])
    return m, fade


def axial_tube_mat(name, hex_color, strength=3.5, power=1.5):
    """Wisp tube: bright head (UV.u=1) fading to a transparent tail (UV.u=0)."""
    m = _base_mat(name)
    nt = m.node_tree
    out = _node(nt, "ShaderNodeOutputMaterial")
    transp = _node(nt, "ShaderNodeBsdfTransparent")
    emi = _node(nt, "ShaderNodeEmission")
    emi.inputs["Color"].default_value = (*_srgb_to_linear_triplet(hex_color), 1.0)
    emi.inputs["Strength"].default_value = strength
    texco = _node(nt, "ShaderNodeTexCoord")
    sep = _node(nt, "ShaderNodeSeparateXYZ")
    pw = _node(nt, "ShaderNodeMath", operation="POWER")
    pw.inputs[1].default_value = power
    _link(nt, texco.outputs["UV"], sep.inputs["Vector"])
    _link(nt, sep.outputs["X"], pw.inputs[0])
    fade = _fade_chain(nt, out, emi, transp, pw.outputs["Value"])
    return m, fade


def vertical_pillar_mat(name, hex_color, half_height, strength=3.0, power=1.6):
    """Light pillar: bright at the base (local z=-half_height), gone at the top."""
    m = _base_mat(name)
    nt = m.node_tree
    out = _node(nt, "ShaderNodeOutputMaterial")
    transp = _node(nt, "ShaderNodeBsdfTransparent")
    emi = _node(nt, "ShaderNodeEmission")
    emi.inputs["Strength"].default_value = strength
    texco = _node(nt, "ShaderNodeTexCoord")
    sep = _node(nt, "ShaderNodeSeparateXYZ")
    norm = _node(nt, "ShaderNodeMath", operation="DIVIDE")
    norm.inputs[1].default_value = 2.0 * half_height
    shift = _node(nt, "ShaderNodeMath", operation="ADD")
    shift.inputs[1].default_value = half_height
    inv = _node(nt, "ShaderNodeMath", operation="SUBTRACT")
    inv.inputs[0].default_value = 1.0
    clamp = _node(nt, "ShaderNodeClamp")
    clamp.inputs["Min"].default_value = 0.0
    clamp.inputs["Max"].default_value = 1.0
    pw = _node(nt, "ShaderNodeMath", operation="POWER")
    pw.inputs[1].default_value = power
    _link(nt, texco.outputs["Object"], sep.inputs["Vector"])
    _link(nt, sep.outputs["Z"], shift.inputs[0])
    _link(nt, shift.outputs["Value"], norm.inputs[0])
    _link(nt, norm.outputs["Value"], inv.inputs[1])
    _link(nt, inv.outputs["Value"], clamp.inputs["Value"])
    _link(nt, clamp.outputs["Result"], pw.inputs[0])
    _white_core(nt, emi, norm.outputs["Value"], hex_color, edge_at=2.2)
    fade = _fade_chain(nt, out, emi, transp, pw.outputs["Value"])
    return m, fade


# ------------------------------------------------------------------ meshes ---
def _link_object(ob):
    bpy.context.scene.collection.objects.link(ob)
    return ob


def tube_arc(name, radius, a0_deg, a1_deg, tube_r, rings=16, sides=6):
    """A tube along a circular arc in the XY plane; UV.u runs tail(0)->head(1)."""
    bm = bmesh.new()
    a0, a1 = math.radians(a0_deg), math.radians(a1_deg)
    ring_verts = []
    for i in range(rings + 1):
        a = a0 + (a1 - a0) * i / rings
        cx, cy = radius * math.cos(a), radius * math.sin(a)
        # frame: radial dir and z dir
        rx, ry = math.cos(a), math.sin(a)
        ring = []
        for j in range(sides):
            b = 2.0 * math.pi * j / sides
            vx = cx + tube_r * (math.cos(b) * rx)
            vy = cy + tube_r * (math.cos(b) * ry)
            vz = tube_r * math.sin(b)
            v = bm.verts.new((vx, vy, vz))
            ring.append(v)
        ring_verts.append(ring)
    uv = bm.loops.layers.uv.new("UVMap")
    for i in range(rings):
        for j in range(sides):
            v0 = ring_verts[i][j]
            v1 = ring_verts[i][(j + 1) % sides]
            v2 = ring_verts[i + 1][(j + 1) % sides]
            v3 = ring_verts[i + 1][j]
            try:
                f = bm.faces.new((v0, v1, v2, v3))
            except ValueError:
                continue
            u0, u1 = i / rings, (i + 1) / rings
            for loop, u in zip(f.loops, (u0, u0, u1, u1)):
                loop[uv].uv = (u, 0.5)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _link_object(bpy.data.objects.new(name, me))


def sector(name, r1, r2, a0_deg, a1_deg, segs=28):
    """Flat annulus sector in the XY plane (slash arcs)."""
    bm = bmesh.new()
    a0, a1 = math.radians(a0_deg), math.radians(a1_deg)
    inner, outer = [], []
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        c, s = math.cos(a), math.sin(a)
        inner.append(bm.verts.new((r1 * c, r1 * s, 0.0)))
        outer.append(bm.verts.new((r2 * c, r2 * s, 0.0)))
    for i in range(segs):
        try:
            bm.faces.new((inner[i], inner[i + 1], outer[i + 1], outer[i]))
        except ValueError:
            pass
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _link_object(bpy.data.objects.new(name, me))


def sector_xz(name, r1, r2, a0_deg, a1_deg, segs=28):
    """Flat annulus sector in the XZ plane: the billboard plane of a front camera
    (which looks along +Y and sees world X right / world Z up)."""
    bm = bmesh.new()
    a0, a1 = math.radians(a0_deg), math.radians(a1_deg)
    inner, outer = [], []
    for i in range(segs + 1):
        a = a0 + (a1 - a0) * i / segs
        c, s = math.cos(a), math.sin(a)
        inner.append(bm.verts.new((r1 * c, 0.0, r1 * s)))
        outer.append(bm.verts.new((r2 * c, 0.0, r2 * s)))
    for i in range(segs):
        try:
            bm.faces.new((inner[i], outer[i], outer[i + 1], inner[i + 1]))
        except ValueError:
            pass
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    return _link_object(bpy.data.objects.new(name, me))


def disc(name, radius, z, verts=40):
    bpy.ops.mesh.primitive_circle_add(vertices=verts, radius=radius,
                                      fill_type="NGON", location=(0.0, 0.0, z))
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def plane_billboard(name, size, location, facing_euler):
    bpy.ops.mesh.primitive_plane_add(size=size, location=location,
                                     rotation=facing_euler)
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def ball(name, radius, location, subdiv=2):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=radius,
                                          location=location)
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def crystal(name, length, radius, location):
    """Hexagonal tapered crystal along +Z, base at location."""
    bpy.ops.mesh.primitive_cone_add(vertices=6, radius1=radius, radius2=radius * 0.28,
                                    depth=length,
                                    location=(location[0], location[1],
                                              location[2] + length / 2.0))
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def shard(name, location):
    """Small pyramid shard (slash impact debris)."""
    bpy.ops.mesh.primitive_cone_add(vertices=4, radius1=1.0, radius2=0.0, depth=2.4,
                                    location=location)
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    ob.scale = (0.9, 0.9, 2.6)
    return ob


def thin_box(name, length, width, location, rot_z_deg):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location,
                                    rotation=(0.0, 0.0, math.radians(rot_z_deg)))
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    ob.scale = (length, width, 0.25)
    return ob


# ------------------------------------------------------- shared material ---
def uniform_emission(name, hex_color, strength=3.0):
    """Emissive with one global alpha uniform. Returns (material, fade_value_node)."""
    m = _base_mat(name)
    nt = m.node_tree
    out = _node(nt, "ShaderNodeOutputMaterial")
    transp = _node(nt, "ShaderNodeBsdfTransparent")
    emi = _node(nt, "ShaderNodeEmission")
    emi.inputs["Color"].default_value = (*_srgb_to_linear_triplet(hex_color), 1.0)
    emi.inputs["Strength"].default_value = strength
    mix = _node(nt, "ShaderNodeMixShader")
    fade = _node(nt, "ShaderNodeValue")
    _link(nt, fade.outputs[0], mix.inputs["Fac"])
    _link(nt, transp.outputs["BSDF"], mix.inputs[1])
    _link(nt, emi.outputs["Emission"], mix.inputs[2])
    _link(nt, mix.outputs["Shader"], out.inputs["Surface"])
    return m, fade


# ============================================================ 1. QI GATHER ===
def build_qi_gather(sc):
    """Cyan wisps spiral inward to the feet point, then sink. One-shot, clean end.

    Canvas 64x64. Anchor (32, 40): the convergence point = where the character
    stands. 16 frames @ 12 fps = 1.33 s.
    """
    cam = make_camera("cam_qi", 30.0, 64.0)
    aim(cam, (0.0, 0.0, 0.0), (32.0, 40.0), 64, 64)

    glow_mat, glow_fade = radial_disc_mat("qi_glow", QI, radius=22.0, strength=1.6)
    glow = disc("glow", 22.0, 0.4)
    glow.data.materials.append(glow_mat)

    wisp_mat, wisp_fade = axial_tube_mat("qi_wisp", QI, strength=2.0)
    wisps = bpy.data.objects.new("wisps", None)
    _link_object(wisps)
    for k in range(6):
        w = tube_arc("wisp_%d" % k, 24.0, -15.0, 85.0, 1.15)
        w.data.materials.append(wisp_mat)
        w.rotation_euler = Euler((0.0, 0.0, math.radians(k * 60.0)), "XYZ")
        w.location = (0.0, 0.0, 2.0 + (k % 2) * 1.6)
        w.parent = wisps

    sink_mat, sink_fade = uniform_emission("qi_sink", WHITE, strength=4.0)
    sink = ball("sink", 1.0, (0.0, 0.0, 3.0))
    sink.data.materials.append(sink_mat)

    def pose(t):
        glow_fade.inputs[1].default_value = \
            smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.68, 1.0, t)) * 0.85
        s = 1.0 - 0.30 * t
        glow.scale = (s, s, 1.0)
        wisps.rotation_euler = Euler((0.0, 0.0, math.radians(30.0 + t * 540.0)), "XYZ")
        ws = 1.0 - 0.78 * ease_in_quad(t)
        wisps.scale = (ws, ws, 1.0)
        wisp_fade.inputs[1].default_value = \
            smoothstep(0.0, 0.10, t) * (1.0 - smoothstep(0.70, 0.96, t))
        ss = clamp01((t - 0.70) / 0.30)
        sink.scale = (max(0.001, 5.5 * math.sin(math.pi * ss)),) * 3
        sink.location = (0.0, 0.0, 3.0 - 2.0 * ss)
        sink_fade.outputs[0].default_value = 1.0  # visibility via scale

    return {"pose": pose}


# ========================================================= 2. ATTACK SLASH ===
def build_attack_slash(sc):
    """Golden slash: gather -> sweep -> burst -> dissipate. Billboard (front view).

    Canvas 96x64. Anchor (24, 38): the gather origin = the striker's hand/weapon
    point. The arc sweeps from -70 deg to +50 deg in local space; rotate the
    presentation node to aim it. 12 frames @ 12 fps = 1.0 s.
    """
    root = bpy.data.objects.new("slash_root", None)
    _link_object(root)
    root.location = (-24.0, 0.0, -6.0)
    cam = make_camera("cam_slash", 0.0, 96.0)
    aim(cam, (-24.0, 0.0, -6.0), (24.0, 38.0), 96, 64)

    orb_mat, orb_fade = uniform_emission("slash_orb", GOLD_CORE, strength=3.5)
    orb = ball("orb", 1.0, (0.0, 0.0, 0.0))
    orb.data.materials.append(orb_mat)
    orb.parent = root

    ring_mat, ring_fade = uniform_emission("slash_ring", GOLD, strength=2.8)
    bpy.ops.mesh.primitive_torus_add(major_radius=1.0, minor_radius=0.32,
                                     major_segments=36, minor_segments=8,
                                     location=(0.0, 0.0, 0.0))
    ring = bpy.context.view_layer.objects.active
    ring.name = "gather_ring"
    ring.data.materials.append(ring_mat)
    ring.rotation_euler = Euler((math.radians(90.0), 0.0, 0.0), "XYZ")  # into XZ
    ring.parent = root

    body_mat, body_fade = uniform_emission("slash_body", GOLD, strength=2.6)
    arc_body = sector_xz("arc_body", 16.0, 26.0, -50.0, 50.0)
    arc_body.data.materials.append(body_mat)
    arc_body.parent = root

    core_mat, core_fade = uniform_emission("slash_core", GOLD_CORE, strength=4.0)
    arc_core = sector_xz("arc_core", 19.0, 24.0, -35.0, 35.0)
    arc_core.data.materials.append(core_mat)
    arc_core.location = (0.0, -0.25, 0.0)  # toward the camera: no z-fight with body
    arc_core.parent = root

    trail_mat, trail_fade = uniform_emission("slash_trail", GOLD, strength=1.8)
    trails = []
    for k in range(2):
        tr = sector_xz("trail_%d" % k, 17.0, 25.0, -45.0, 45.0)
        tr.data.materials.append(trail_mat)
        tr.location = (0.0, 0.25 + 0.2 * k, 0.0)  # behind the body: no z-fight
        tr.parent = root
        trails.append(tr)

    ix = 26.0 * math.cos(math.radians(50.0))
    iz = 26.0 * math.sin(math.radians(50.0))
    flash_mat, flash_fade = radial_disc_mat("slash_flash", GOLD, radius=14.0,
                                            strength=3.0, power=2.4)
    flash = plane_billboard("flash", 28.0, (ix, 0.0, iz),
                            (math.radians(90.0), 0.0, 0.0))
    flash.data.materials.append(flash_mat)
    flash.parent = root

    shard_mat, shard_fade = uniform_emission("slash_shard", GOLD, strength=2.8)
    shard_dirs = [-55.0, -32.0, -10.0, 12.0, 34.0, 56.0, 78.0]
    shards = []
    for k, d in enumerate(shard_dirs):
        sh = shard("shard_%d" % k, (0.0, 0.0, 0.0))
        sh.data.materials.append(shard_mat)
        sh.parent = root
        shards.append((sh, d, 1 if k % 2 == 0 else -1))

    def arc_rot(t):
        s = clamp01((t - 0.18) / 0.62)
        return -70.0 + 120.0 * ease_out_quad(s), s

    def pose(t):
        s = clamp01(t / 0.25)
        orb.scale = (2.0 + 3.5 * s,) * 3
        orb_fade.outputs[0].default_value = \
            smoothstep(0.0, 0.25, s) * (1.0 - smoothstep(0.6, 1.0, s))
        s = clamp01(t / 0.30)
        rs = 13.0 - 9.5 * s
        ring.scale = (rs, rs, rs)
        ring_fade.outputs[0].default_value = math.sin(math.pi * s) ** 0.8

        rot, s = arc_rot(t)
        # sweep about world Y: rotation_y = -angle puts (1,0,0) at angle `rot`
        # measured from +X toward +Z.
        arc_body.rotation_euler = Euler((0.0, math.radians(-rot), 0.0), "XYZ")
        body_fade.outputs[0].default_value = \
            smoothstep(0.0, 0.12, s) * (1.0 - smoothstep(0.72, 1.0, s))
        arc_core.rotation_euler = Euler((0.0, math.radians(-rot - 8.0), 0.0), "XYZ")
        core_fade.outputs[0].default_value = \
            smoothstep(0.0, 0.10, s) * (1.0 - smoothstep(0.70, 1.0, s))

        s2 = clamp01((t - 0.25) / 0.60)
        for k, tr in enumerate(trails):
            tr.rotation_euler = Euler(
                (0.0, math.radians(-rot + 18.0 + 22.0 * k), 0.0), "XYZ")
        trail_fade.outputs[0].default_value = \
            smoothstep(0.0, 0.15, s2) * (1.0 - s2) * 0.55

        s3 = clamp01((t - 0.55) / 0.30)
        fs = 0.3 + 1.6 * ease_out_quad(s3)
        flash.scale = (fs, fs, 1.0)
        flash_fade.inputs[1].default_value = \
            smoothstep(0.0, 0.20, s3) * (1.0 - smoothstep(0.55, 1.0, s3))

        s4 = clamp01((t - 0.55) / 0.35)
        dist = 4.0 + 24.0 * ease_out_quad(s4)
        pop = smoothstep(0.0, 0.15, s4)
        for sh, d, spin in shards:
            a = math.radians(d)
            sh.location = (ix + math.cos(a) * dist, 0.5, iz + math.sin(a) * dist)
            sh.rotation_euler = Euler((math.radians(20.0),
                                       math.radians(-(d + 90.0 + s4 * 240.0 * spin)),
                                       0.0), "XYZ")
            sh.scale = (0.9 * pop, 0.9 * pop, 2.6 * pop)
        shard_fade.outputs[0].default_value = 1.0 - smoothstep(0.55, 1.0, s4)

    return {"pose": pose}


# ============================================================ 3. VEIN ERUPT ===
def build_vein_erupt(sc):
    """Teal crystal eruption: glow+cracks -> shards+pillar -> settling embers.

    Canvas 128x128. Anchor (64, 92): the fissure point on the ground. 20 frames
    @ 12 fps = 1.67 s. One-shot with a clean end.
    """
    cam = make_camera("cam_vein", 30.0, 128.0)
    aim(cam, (0.0, 0.0, 0.0), (64.0, 92.0), 128, 128)

    glow_mat, glow_fade = radial_disc_mat("vein_glow", QI, radius=42.0,
                                          strength=1.6, power=2.2)
    glow = disc("vein_glow", 42.0, 0.4, verts=48)
    glow.data.materials.append(glow_mat)

    crack_mat, crack_fade = uniform_emission("vein_crack", JADE, strength=1.6)
    cracks = []
    for c, base_ang in enumerate((15.0, 105.0, 195.0, 285.0)):
        for j, zig in enumerate((0.0, 14.0, -12.0)):
            a = math.radians(base_ang + zig)
            r = 7.0 + j * 10.0
            seg = thin_box("crack_%d_%d" % (c, j), 11.0, 0.55,
                           (math.cos(a) * r, math.sin(a) * r, 0.25),
                           math.degrees(a) + 90.0)
            seg.data.materials.append(crack_mat)
            cracks.append(seg)

    shards = []
    for k in range(9):
        ang = math.radians(13.0 + k * 40.0)
        dist = 5.0 + (k * 7) % 12
        rise = 60.0 + (k * 11) % 28
        size = 0.75 + ((k * 5) % 9) / 18.0
        spin = 1.0 if k % 2 == 0 else -1.0
        omat, ofade = uniform_emission("vshard_%d" % k, QI, strength=2.2)
        cmat, cfade = uniform_emission("vshard_core_%d" % k, WHITE, strength=3.2)
        ob = crystal("vshard_%d" % k, 15.0, 2.4, (0.0, 0.0, 0.0))
        ob.data.materials.append(omat)
        core = crystal("vshard_core_%d" % k, 12.0, 1.05, (0.0, 0.0, 1.5))
        core.data.materials.append(cmat)
        core.parent = ob
        shards.append((ob, ofade, cfade, ang, dist, rise, size, spin))

    pillar_mat, pillar_fade = vertical_pillar_mat("vein_pillar", QI,
                                                  half_height=47.5, strength=2.2)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=9.0, depth=95.0,
                                        location=(0.0, 0.0, 47.5))
    pillar = bpy.context.view_layer.objects.active
    pillar.name = "pillar"
    pillar.data.materials.append(pillar_mat)

    ember_mat, ember_fade = radial_disc_mat("vein_ember", QI, radius=3.0,
                                            strength=2.0, power=1.8)
    cam_euler = (math.radians(60.0), 0.0, 0.0)
    embers = []
    for k in range(10):
        a = math.radians(37.0 * k + 11.0)
        em = plane_billboard("ember_%d" % k, 6.0, (0.0, 0.0, 0.0), cam_euler)
        em.data.materials.append(ember_mat)
        embers.append((em, a, (k % 3) * 4.0))

    def glow_alpha(t):
        if t < 0.26:
            return 0.10 + 0.08 * math.sin(t / 0.26 * 3.0 * math.pi)
        if t < 0.62:
            blaze = smoothstep(0.26, 0.38, t) * (1.0 - smoothstep(0.55, 0.68, t))
            return 0.15 + 0.75 * blaze
        return 0.03 + 0.19 * (1.0 - smoothstep(0.80, 1.0, t))

    def pose(t):
        glow_fade.inputs[1].default_value = glow_alpha(t)
        gs = 0.8 + 0.4 * smoothstep(0.26, 0.50, t)
        glow.scale = (gs, gs, 1.0)
        crack_fade.outputs[0].default_value = \
            smoothstep(0.02, 0.18, t) * (1.0 - smoothstep(0.78, 0.98, t)) * 0.85

        s = clamp01((t - 0.30) / 0.48)
        e = ease_out_quad(s)
        s2 = clamp01((t - 0.78) / 0.22)
        for ob, ofade, cfade, ang, dist, rise, size, spin in shards:
            x = math.cos(ang) * dist * e
            y = math.sin(ang) * dist * e
            z = rise * e * (1.0 - 0.92 * s2 * s2)
            ob.location = (x, y, z)
            ob.rotation_euler = Euler((spin * e * 2.6, 0.0,
                                       ang + spin * e * 1.2), "XYZ")
            scf = size * smoothstep(0.0, 0.10, s) * (1.0 - 0.3 * s2)
            ob.scale = (scf, scf, scf)
            fa = 1.0 - smoothstep(0.45, 1.0, s2)
            ofade.outputs[0].default_value = fa * 0.88
            cfade.outputs[0].default_value = fa

        grow = smoothstep(0.30, 0.44, t)
        pillar_fade.inputs[1].default_value = \
            grow * (1.0 - smoothstep(0.66, 0.80, t)) * 0.85
        pillar.scale = (0.7 + 0.3 * grow, 0.7 + 0.3 * grow, 0.25 + 0.75 * grow)

        s5 = clamp01((t - 0.72) / 0.28)
        for em, a, lift in embers:
            r = 8.0 + 14.0 * s5
            em.location = (math.cos(a) * r, math.sin(a) * r, 3.0 + 26.0 * s5 + lift)
            es = 0.7 + 0.9 * s5
            em.scale = (es, es, 1.0)
        ember_fade.inputs[1].default_value = (1.0 - s5) * smoothstep(0.0, 0.15, s5) * 0.8

    return {"pose": pose}


# ------------------------------------------------------------------ driver ---
EFFECTS = {
    "qi_gather": {"frames": 16, "size": (64, 64), "samples": 16,
                  "build": build_qi_gather},
    "attack_slash": {"frames": 12, "size": (96, 64), "samples": 16,
                     "build": build_attack_slash},
    "vein_erupt": {"frames": 20, "size": (128, 128), "samples": 24,
                   "build": build_vein_erupt},
}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--effect", required=True, choices=list(EFFECTS) + ["all"])
    ap.add_argument("--rawdir", required=True,
                    help="raw Blender PNGs go to <rawdir>/<effect>/raw_XX.png")
    ap.add_argument("--preview", default="",
                    help="render only this frame index (debug), e.g. 0")
    args = ap.parse_args(argv)
    names = list(EFFECTS) if args.effect == "all" else [args.effect]
    for name in names:
        meta = EFFECTS[name]
        clear_all()
        sc = setup_render(*meta["size"], meta["samples"])
        handle = meta["build"](sc)
        d = os.path.join(args.rawdir, name)
        os.makedirs(d, exist_ok=True)
        idxs = [int(args.preview)] if args.preview != "" else range(meta["frames"])
        for i in idxs:
            t = i / (meta["frames"] - 1)
            handle["pose"](t)
            bpy.context.view_layer.update()
            sc.render.filepath = os.path.join(d, "raw_%02d.png" % i)
            bpy.ops.render.render(write_still=True)
            print("rendered %s frame %d/%d" % (name, i + 1, meta["frames"]),
                  flush=True)
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    sys.exit(main(argv))
