"""The canonical Aetheria humanoid as DATA: rest-pose meshes, skin weights and bones.

Pure Python (math only) so the SAME geometry feeds the Blender build (`blender/build_actor.py`,
which only instantiates what this returns) and the pre-model design sheet (`designs/
design_sheet.py`, which projects it). One geometry source: a proportion fixed here is fixed in
the model, the sheet, the sprites and the anchors at once.

Frame: X = the character's LEFT, Y = BACK (the figure faces -Y, toward the camera at rest),
Z = up. Units are gameplay pixels before foreshortening (`designs/cultivator.yaml`).

A part is {"name", "material", "verts", "faces", "weights": {bone: [w per vert]}, "smooth",
"lod"}. lod "all" renders everywhere; "sprite" only in the 32x48 gameplay passes (the one-pixel
eye); "portrait" only in the portrait and the presentation render (face detail that would be
noise at 32x48 but is the face at 56x56).
A bone is {"name", "head", "tail", "parent"}.
"""
import math

TAU = math.tau


# --- small vector helpers -----------------------------------------------------------------------

def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _mul(a, s):
    return (a[0] * s, a[1] * s, a[2] * s)


def _len(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


def _norm(a):
    n = _len(a) or 1.0
    return (a[0] / n, a[1] / n, a[2] / n)


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _lerp(a, b, t):
    return a + (b - a) * t


def _smooth(e0, e1, x):
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def _interp_rows(rows, z):
    """Linear interpolation in a [z, a, b] table sorted either way by z."""
    rows = sorted(rows, key=lambda r: r[0])
    if z <= rows[0][0]:
        return rows[0][1:]
    for lo, hi in zip(rows, rows[1:]):
        if lo[0] <= z <= hi[0]:
            t = (z - lo[0]) / (hi[0] - lo[0])
            return [_lerp(lo[i], hi[i], t) for i in range(1, len(lo))]
    return rows[-1][1:]


# --- mesh primitives ----------------------------------------------------------------------------

class Mesh:
    def __init__(self):
        self.verts = []
        self.faces = []

    def add_ring_loft(self, rings, cap_start=False, cap_end=False):
        base = len(self.verts)
        n = len(rings[0])
        for r in rings:
            self.verts.extend(r)
        for k in range(len(rings) - 1):
            for i in range(n):
                a = base + k * n + i
                b = base + k * n + (i + 1) % n
                c = base + (k + 1) * n + (i + 1) % n
                d = base + (k + 1) * n + i
                self.faces.append((a, b, c, d))
        for cap, ring_index in ((cap_start, 0), (cap_end, len(rings) - 1)):
            if not cap:
                continue
            ring = rings[ring_index]
            centre = _mul((sum(p[0] for p in ring), sum(p[1] for p in ring),
                           sum(p[2] for p in ring)), 1.0 / n)
            ci = len(self.verts)
            self.verts.append(centre)
            off = base + ring_index * n
            for i in range(n):
                self.faces.append((off + i, off + (i + 1) % n, ci))
        return base

    def add_strip(self, left_pts, right_pts):
        """A ribbon between two polylines of equal length."""
        base = len(self.verts)
        n = len(left_pts)
        self.verts.extend(left_pts)
        self.verts.extend(right_pts)
        for i in range(n - 1):
            self.faces.append((base + i, base + i + 1, base + n + i + 1, base + n + i))
        return base


def ellipse_ring(cx, cy, z, rx, ry, n=20, phase=-math.pi / 2):
    """Points around an ellipse at height z; index 0 faces -Y (the front)."""
    return [(cx + rx * math.cos(phase + TAU * i / n), cy + ry * math.sin(phase + TAU * i / n), z)
            for i in range(n)]


def sphere(centre, radii, seg=16, rings=12):
    m = Mesh()
    cx, cy, cz = centre
    rx, ry, rz = radii
    loops = []
    for j in range(1, rings):
        v = math.pi * j / rings
        z = cz + rz * math.cos(v)
        s = math.sin(v)
        loops.append(ellipse_ring(cx, cy, z, rx * s, ry * s, seg))
    m.add_ring_loft(loops)
    top = len(m.verts)
    m.verts.append((cx, cy, cz + rz))
    bottom = len(m.verts)
    m.verts.append((cx, cy, cz - rz))
    for i in range(seg):
        m.faces.append((top, i, (i + 1) % seg))
        off = (len(loops) - 1) * seg
        m.faces.append((bottom, off + (i + 1) % seg, off + i))
    return m


def tube(path, radii, seg=10, up=(0.0, -1.0, 0.0), squash=1.0, cap=True):
    """Rings perpendicular to a polyline. `radii` per point; `squash` flattens the ring along
    the second frame axis (a ribbon-like strand when < 1)."""
    m = Mesh()
    rings = []
    for i, p in enumerate(path):
        if i == 0:
            d = _sub(path[1], path[0])
        elif i == len(path) - 1:
            d = _sub(path[-1], path[-2])
        else:
            d = _sub(path[i + 1], path[i - 1])
        d = _norm(d)
        a = _norm(_cross(d, up))
        if _len(a) < 1e-6:
            a = (1.0, 0.0, 0.0)
        b = _norm(_cross(a, d))
        r = radii[i]
        ring = []
        for k in range(seg):
            t = TAU * k / seg
            off = _add(_mul(a, r * math.cos(t)), _mul(b, r * squash * math.sin(t)))
            ring.append(_add(p, off))
        rings.append(ring)
    m.add_ring_loft(rings, cap_start=cap, cap_end=cap)
    return m


# --- the body -----------------------------------------------------------------------------------

def _arm_points(spec, side):
    """Shoulder, elbow, wrist, fingertip for one arm at rest (side = +1 left, -1 right)."""
    b = spec["body"]
    spread = math.radians(b["arm_rest_spread_deg"])
    sh = (side * b["shoulder_x"], 0.2, b["shoulder"])
    el = (sh[0] + side * math.sin(spread) * b["upper_arm"], 0.5,
          sh[2] - math.cos(spread) * b["upper_arm"])
    fs = spread * 0.55
    wr = (el[0] + side * math.sin(fs) * b["forearm"], -0.3, el[2] - math.cos(fs) * b["forearm"])
    tip = (wr[0] + side * math.sin(fs) * b["hand"] * 0.6, -0.5, wr[2] - b["hand"])
    return sh, el, wr, tip


def _hair_back_y(spec, z):
    """The Y just behind the head/back at height z, where the back hair lies. Hair FALLS: it
    never tucks back in under the skull into the neck's hollow, so the surface is a running
    maximum from the crown down."""
    top = spec["hair"]["back"]["top_z"]
    best = -99.0
    zz = top
    while zz >= z:
        best = max(best, _surface_back_y(spec, zz))
        zz -= 0.5
    hanging = max(best, _surface_back_y(spec, z))
    # Below the shoulders the hair lies ON the back (it drapes over the shoulder blades), so
    # from the side it is one mass with the body instead of a strand hanging behind it.
    sh = spec["body"]["shoulder"]
    t = _smooth(sh, sh - 7.0, z)
    return _lerp(hanging, _surface_back_y(spec, z), t)


def _hair_chain_z(hb):
    """Heights of the three hair bones: the hair's own length in thirds, so a shoulder-length
    cut gets a short chain and waist-length hair a long one."""
    top = hb["top_z"] - 2.5
    return [_lerp(top, hb["bottom_z"], t / 3.0) for t in range(4)]


def _surface_back_y(spec, z):
    b = spec["body"]
    hx, hy, hz = b["head_centre"]
    rx, ry, rz = b["head_radii"]
    dz = (z - hz) / rz
    head_back = hy + ry * math.sqrt(max(0.0, 1 - dz * dz)) if abs(dz) < 1 else -99
    bod = spec["garment"]["bodice"] + spec["garment"]["skirt"]
    in_body = min(r[0] for r in bod) <= z <= max(r[0] for r in bod)
    body_back = _interp_rows(bod, z)[1] if in_body else -99
    neck_back = b["neck_radius"] + 0.2 if b["neck_base"] - 1 <= z <= hz else -99
    return max(head_back, body_back, neck_back)


def bones(spec):
    b = spec["body"]
    g = spec["garment"]
    h = spec["hair"]
    hx, hy, hz = b["head_centre"]
    head_top = hz + b["head_radii"][2]
    out = [
        {"name": "root", "head": (0, 0, 0), "tail": (0, 0, 2.0), "parent": None},
        {"name": "pelvis", "head": (0, 0, b["hip"]), "tail": (0, 0, b["waist"]),
         "parent": "root"},
        {"name": "spine", "head": (0, 0, b["waist"]), "tail": (0, 0, b["chest"]),
         "parent": "pelvis"},
        {"name": "chest", "head": (0, 0, b["chest"]), "tail": (0, 0, b["neck_base"]),
         "parent": "spine"},
        {"name": "neck", "head": (0, 0, b["neck_base"]), "tail": (0, 0, b["neck_top"]),
         "parent": "chest"},
        {"name": "head", "head": (0, 0, b["neck_top"]), "tail": (0, 0, head_top),
         "parent": "neck"},
        {"name": "core", "head": (0, -4.0, b["waist"] - 1.6), "tail": (0, -5.0, b["waist"] - 1.6),
         "parent": "pelvis"},
    ]
    # Eyes open / closed are two tiny bones the poses SCALE between (a lid is a pose, not a
    # second sprite), so an Action can close the eyes for meditation.
    e = spec["face"]["eyes"]
    face_y = hy - b["head_radii"][1] * 0.9
    for name in ("eyes_open", "eyes_closed"):
        out.append({"name": name, "head": (0, face_y + 1.2, e["z"]),
                    "tail": (0, face_y + 1.2, e["z"] + 1.0), "parent": "head"})
    hb = h["back"]
    zs = _hair_chain_z(hb)
    pts = [(0, _hair_back_y(spec, z) + hb["thickness"] * 0.5, z) for z in zs]
    parent = "head"
    for i in range(3):
        name = "hair_%d" % (i + 1)
        out.append({"name": name, "head": pts[i], "tail": pts[i + 1], "parent": parent})
        parent = name
    sk = g["sash"]
    knot = tuple(sk["knot"])
    out.append({"name": "sash_tail", "head": knot,
                "tail": (knot[0], knot[1], knot[2] - sk["tail_length"]), "parent": "pelvis"})
    # The lock bones exist even when the design has no locks: every actor shares ONE skeleton,
    # so the motion library and the anchors never branch on a design.
    lk = h.get("locks") or {"from": [4.4, 0.7, 41.6], "to_z": 34.6}
    for side, suffix in ((1, "L"), (-1, "R")):
        sh, el, wr, tip = _arm_points(spec, side)
        out += [
            {"name": "shoulder." + suffix, "head": (side * 1.6, 0.2, b["shoulder"]), "tail": sh,
             "parent": "chest"},
            {"name": "upper_arm." + suffix, "head": sh, "tail": el,
             "parent": "shoulder." + suffix},
            {"name": "forearm." + suffix, "head": el, "tail": wr,
             "parent": "upper_arm." + suffix},
            {"name": "hand." + suffix, "head": wr, "tail": tip, "parent": "forearm." + suffix},
            {"name": "thigh." + suffix, "head": (side * b["hip_x"], 0, b["hip"]),
             "tail": (side * b["hip_x"], 0, b["knee"]), "parent": "pelvis"},
            {"name": "shin." + suffix, "head": (side * b["hip_x"], 0, b["knee"]),
             "tail": (side * b["hip_x"], 0.2, b["ankle"]), "parent": "thigh." + suffix},
            {"name": "foot." + suffix, "head": (side * b["hip_x"], 0.2, b["ankle"]),
             "tail": (side * b["hip_x"], 0.2 - b["foot"]["length"] * 0.8, 0.6),
             "parent": "shin." + suffix},
            {"name": "lock." + suffix, "head": (side * lk["from"][0], lk["from"][1], lk["from"][2]),
             "tail": (side * (lk["from"][0] + 0.9), lk["from"][1] - 1.0, lk["to_z"]),
             "parent": "head"},
        ]
    return out


def _part(name, material, mesh, weights, smooth=True, lod="all"):
    return {"name": name, "material": material, "verts": mesh.verts, "faces": mesh.faces,
            "weights": weights, "smooth": smooth, "lod": lod}


def _rigid(mesh, bone):
    return {bone: [1.0] * len(mesh.verts)}


def _blend_z(mesh, stops):
    """Weights from a list of (z, bone) stops, top to bottom: linear between neighbours."""
    stops = sorted(stops, key=lambda s: -s[0])
    w = {bone: [0.0] * len(mesh.verts) for _, bone in stops}
    for i, v in enumerate(mesh.verts):
        z = v[2]
        if z >= stops[0][0]:
            w[stops[0][1]][i] = 1.0
            continue
        if z <= stops[-1][0]:
            w[stops[-1][1]][i] = 1.0
            continue
        for (z0, b0), (z1, b1) in zip(stops, stops[1:]):
            if z1 <= z <= z0:
                t = (z0 - z) / max(1e-6, z0 - z1)
                w[b0][i] += 1 - t
                w[b1][i] += t
                break
    return w


def shape_head(spec, p):
    """Sculpt a point of the head ELLIPSOID into the Aetheria face (D-062, moodboard 01
    'character': oval face, a jaw that narrows to a pointed chin, cheekbones, a shallow face
    plane, a full skull behind). A pure deformation, so anything placed ON the ellipsoid (eyes,
    brows, mouth) can be put through the same function and stays on the skin.

    The SIZE of the head is canon and does not move here (CHARACTER_ART_BIBLE §4: head ≈ 1/3 of
    the 32x48 figure, R-5); only its SHAPE follows the reference — a ball reads as a toy."""
    sh = spec["face"].get("shape", {})
    b = spec["body"]
    hx, hy, hz = b["head_centre"]
    rx, ry, rz = b["head_radii"]
    x, y, z = p[0] - hx, p[1] - hy, p[2] - hz
    ux, uy, uz = x / rx, y / ry, z / rz
    face = _smooth(-0.15, -0.75, uy)                 # 1 on the face, 0 at the sides/back
    low = _smooth(0.05, -1.0, uz)                    # 0 above the cheek line, 1 at the chin
    # the jaw: narrows toward the chin, most at the front (a V, not a U)
    x *= 1.0 - sh.get("jaw", 0.42) * (low ** 1.2) * (0.55 + 0.45 * face)
    # the chin: a little longer and forward
    z -= sh.get("chin", 0.12) * rz * low * face
    y -= 0.10 * ry * low * face
    # cheekbones under the eyes, at the outer face
    cheek = math.exp(-((uz + 0.12) / 0.25) ** 2) * _smooth(0.35, 0.9, abs(ux)) * face
    x *= 1.0 + sh.get("cheek", 0.05) * cheek
    # a shallower face plane: the front is flatter than a ball
    y *= 1.0 - 0.10 * face * (1.0 - low * 0.5)
    # the skull is fuller behind and above
    back = _smooth(0.1, 0.8, uy) * _smooth(-0.3, 0.6, uz)
    y *= 1.0 + 0.10 * back
    return (hx + x, hy + y, hz + z)


def _head(spec):
    b = spec["body"]
    m = sphere(b["head_centre"], b["head_radii"], 24, 18)
    m.verts = [shape_head(spec, v) for v in m.verts]
    parts = [_part("head", "skin", m, _rigid(m, "head"))]
    # ears: small, set between the eye line and the nose, mostly under the hair
    hx, hy, hz = b["head_centre"]
    rx = b["head_radii"][0]
    e = spec["face"]["eyes"]
    for side, sfx in ((1, "L"), (-1, "R")):
        ear = sphere(shape_head(spec, (hx + side * rx * 0.97, hy + 0.3, e["z"] - 0.9)),
                     (0.35, 0.75, 1.05), 8, 6)
        parts.append(_part("ear." + sfx, "skin", ear, _rigid(ear, "head"), lod="portrait"))
    return parts


def _neck(spec):
    b = spec["body"]
    r = b["neck_radius"]
    m = tube([(0, 0.2, b["neck_base"] - 0.8), (0, 0.1, b["neck_top"] + 1.2)], [r, r * 0.95], 10)
    return _part("neck", "skin", m, _blend_z(m, [(b["neck_top"], "head"),
                                                 (b["neck_base"], "chest")]))


def _eyes(spec):
    """Two eye LODs on the same rig. SPRITE: one dark ellipsoid per eye — at 32x48 an eye is one
    ink pixel (CHARACTER_ART_BIBLE §4). PORTRAIT: an almond eye — white, a dark iris under a
    heavy upper lash line that sweeps out at the corner (moodboard 01/03 'character' faces).
    The closed lid (meditation) serves both."""
    e = spec["face"]["eyes"]
    out = []
    for side, sfx in ((1, "L"), (-1, "R")):
        x = side * e["x"]
        c = _face_point(spec, x, e["z"], -0.05)
        m = sphere(c, tuple(e["size"]), 8, 6)
        out.append(_part("eye_" + sfx, "eye", m, _rigid(m, "eyes_open"), lod="sprite"))
        sx, sy, sz = e["size"]
        lid = sphere(_face_point(spec, x, e["z"] - sz * 0.25, -0.02),
                     (sx * 1.25, sy, sz * 0.3), 8, 6)
        out.append(_part("lash_" + sfx, "lash", lid, _rigid(lid, "eyes_closed")))
        # portrait: the almond (sclera), the iris, the upper lash line
        w = e.get("almond", [1.05, 0.55])
        white = sphere(_face_point(spec, x, e["z"], 0.0), (w[0] * 0.5, 0.18, w[1] * 0.5), 12, 8)
        out.append(_part("sclera_" + sfx, "sclera", white, _rigid(white, "eyes_open"),
                         lod="portrait"))
        iris = sphere(_face_point(spec, x - side * 0.05, e["z"] - 0.02, 0.06),
                      (w[1] * 0.42, 0.12, w[1] * 0.5), 10, 8)
        out.append(_part("iris_" + sfx, "eye", iris, _rigid(iris, "eyes_open"), lod="portrait"))
        inner, outer = x - side * w[0] * 0.55, x + side * w[0] * 0.62
        line = [_face_point(spec, inner, e["z"] + w[1] * 0.18, 0.08),
                _face_point(spec, x, e["z"] + w[1] * 0.5, 0.1),
                _face_point(spec, outer, e["z"] + w[1] * 0.28, 0.08),
                _face_point(spec, outer + side * 0.25, e["z"] + w[1] * 0.4, 0.06)]
        ln = tube(line, [0.07, 0.11, 0.1, 0.04], 6, up=(0, -1, 0), squash=0.5)
        out.append(_part("lashline_" + sfx, "eye", ln, _rigid(ln, "eyes_open"), lod="portrait"))
    return out


def _face_point(spec, x, z, out=0.05):
    """A point ON the sculpted face at ellipsoid coordinates (x, z), lifted `out` off the
    skin. `x`/`z` are taken on the ELLIPSOID and then sculpted, so a feature keeps its place on
    the face whatever the jaw and cheek settings are."""
    b = spec["body"]
    hx, hy, hz = b["head_centre"]
    rx, ry, rz = b["head_radii"]
    dz = (z - hz) / rz
    y = hy - ry * math.sqrt(max(0.0, 1 - ((x - hx) / rx) ** 2 - dz * dz))
    sx, sy, sz = shape_head(spec, (x, y, z))
    return (sx, sy - out, sz)


def _face_detail(spec):
    """Portrait-LOD face: brows, the bridge of the nose, the mouth. At 32x48 the face is two
    eye pixels on lit skin (CHARACTER_ART_BIBLE §4) — these would be noise there; at the 56px
    portrait they are what makes it a face and not a mask."""
    e = spec["face"]["eyes"]
    f = spec["face"].get("detail", {})
    out = []
    brow_dz = f.get("brow_dz", 1.25)
    for side, sfx in ((1, "L"), (-1, "R")):
        inner, outer = e["x"] - 0.75, e["x"] + 0.85
        path = [_face_point(spec, side * inner, e["z"] + brow_dz - 0.05),
                _face_point(spec, side * (inner + outer) / 2, e["z"] + brow_dz + 0.2),
                _face_point(spec, side * outer, e["z"] + brow_dz - 0.1)]
        m = tube(path, [0.17, 0.2, 0.13], 6, up=(0, -1, 0), squash=0.6)
        out.append(_part("brow." + sfx, "lash", m, _rigid(m, "head"), lod="portrait"))
    # the nose: a narrow bridge from between the eyes to a small tip — a wedge, not a ball
    nz = e["z"] - f.get("nose_dz", 1.7)
    bridge = [_face_point(spec, 0.0, e["z"] - 0.2, -0.05), _face_point(spec, 0.0, nz + 0.4, 0.1),
              _face_point(spec, 0.0, nz, 0.28)]
    nose = tube(bridge, [0.16, 0.24, 0.3], 8, up=(1, 0, 0), squash=0.8)
    out.append(_part("nose", "skin", nose, _rigid(nose, "head"), lod="portrait"))
    mz = e["z"] - f.get("mouth_dz", 3.0)
    mw = f.get("mouth_w", 0.75)
    mouth = tube([_face_point(spec, -mw, mz + 0.05), _face_point(spec, 0.0, mz - 0.05),
                  _face_point(spec, mw, mz + 0.05)], [0.1, 0.13, 0.1], 6, up=(0, -1, 0),
                 squash=0.6)
    out.append(_part("mouth", "lash", mouth, _rigid(mouth, "head"), lod="portrait"))
    return out


def _bodice(spec):
    g = spec["garment"]
    rings = [ellipse_ring(0, 0, z, rx, ry, 24) for z, rx, ry in g["bodice"]]
    m = Mesh()
    m.add_ring_loft(rings)
    b = spec["body"]
    w = _blend_z(m, [(b["neck_base"], "chest"), (b["chest"], "chest"),
                     (b["waist"] + 0.5, "spine"), (b["waist"] - 0.5, "pelvis")])
    return _part("bodice", "robe", m, w)


def _surface_front(spec, x, z, out=0.0):
    """A point on the FRONT of the bodice/skirt surface at (x, z), pushed `out` along -Y."""
    g = spec["garment"]
    rows = g["bodice"] + g["skirt"]
    rx, ry = _interp_rows(rows, z)
    k = max(0.0, 1 - (x / rx) ** 2)
    return (x, -ry * math.sqrt(k) - out, z)


def _collar(spec):
    """The giao lĩnh crossed collar, LEFT over RIGHT: the outer edge runs from the wearer's left
    neck (+X) down across the chest to the right side of the sash; the right lapel shows only
    above where the left one crosses it. Each edge is a dark trim ribbon with the white inner
    robe showing as a narrower ribbon inside it."""
    g = spec["garment"]
    c = g["collar"]
    b = spec["body"]
    top = b["neck_base"] + 0.2
    parts = []
    lines = [((2.3, top), (c["cross_x"] - 2.6, c["cross_z"])),          # the left lapel
             ((-2.3, top), (-0.2, top - 4.4))]                          # the right one
    for li, (p0, p1) in enumerate(lines):
        for layer, (width, mat, out) in enumerate(((c["width"], "trim", c["depth"]),
                                                   (c["inner_width"], "robe_inner",
                                                    c["depth"] * 0.6))):
            steps = 9
            left, right = [], []
            # the inner robe shows on the NECK side of the trim edge
            sgn = 1 if p0[0] > 0 else -1
            shift = (width if layer == 1 else 0.0) * sgn
            for i in range(steps):
                t = i / (steps - 1.0)
                x = _lerp(p0[0], p1[0], t) + shift
                z = _lerp(p0[1], p1[1], t)
                left.append(_surface_front(spec, x, z, out))
                right.append(_surface_front(spec, x + sgn * width, z, out))
            m = Mesh()
            m.add_strip(left, right)
            w = _blend_z(m, [(b["neck_base"], "chest"), (b["chest"], "chest"),
                             (b["waist"], "spine")])
            parts.append(_part("collar_%d_%d" % (li, layer), mat, m, w, smooth=False))
    return parts


def _skirt_weights(spec, m):
    b = spec["body"]
    rows = spec["garment"]["skirt"]
    waist_z, hem_z = rows[0][0], rows[-1][0]
    names = ["pelvis", "thigh.L", "thigh.R", "shin.L", "shin.R"]
    w = {n: [0.0] * len(m.verts) for n in names}
    for i, (x, y, z) in enumerate(m.verts):
        t = max(0.0, min(1.0, (waist_z - z) / (waist_z - hem_z)))
        pel = (1 - t) ** 2.2
        leg = 1 - pel
        side = _smooth(-1.8, 1.8, x)
        shin_share = 0.55 * _smooth(b["knee"], b["ankle"], z)
        for suffix, s in (("L", side), ("R", 1 - side)):
            w["thigh." + suffix][i] += leg * s * (1 - shin_share)
            w["shin." + suffix][i] += leg * s * shin_share
        w["pelvis"][i] += pel
    return w


def _skirt(spec):
    g = spec["garment"]
    rows = g["skirt"]
    lift = g["hem_front_lift"]
    rings = []
    hem_z = rows[-1][0]
    for z, rx, ry in rows:
        ring = ellipse_ring(0, 0, z, rx, ry, 28)
        # The front lift fades in from ~8 units above the hem, so EVERY ring below the knee
        # rises with the hem. Lifting only the last ring left the ring above it lower than the
        # hem: the cloth folded back down over the shoes and no step ever showed.
        w = max(0.0, 1.0 - (z - hem_z) / 8.0)
        ring = [(x, y, zz + lift * w * max(0.0, -y / ry) ** 1.5) for x, y, zz in ring]
        rings.append(ring)
    m = Mesh()
    m.add_ring_loft(rings)
    parts = [_part("skirt", "robe", m, _skirt_weights(spec, m))]
    # The hem band: a trim ribbon just outside the last ring, so the floor-length robe ends in
    # a defined edge instead of fading into the shoes.
    hem = rings[-1]
    z, rx, ry = rows[-1]
    up = [(x * 1.012, y * 1.012, zz + 1.1) for x, y, zz in hem]
    down = [(x * 1.012, y * 1.012, zz) for x, y, zz in hem]
    band = Mesh()
    band.add_ring_loft([up, down])
    parts.append(_part("hem_band", "trim", band, _skirt_weights(spec, band)))
    # The front edge of the outer robe: from the sash knot side down to the hem.
    c = g["collar"]
    left, right = [], []
    for i in range(10):
        t = i / 9.0
        zz = _lerp(rows[0][0] - 0.8, rows[-1][0] + 0.6, t)
        x = c["cross_x"] - 2.6 - 0.9 * t
        left.append(_surface_front(spec, x, zz, 0.22))
        right.append(_surface_front(spec, x + c["width"], zz, 0.22))
    edge = Mesh()
    edge.add_strip(left, right)
    parts.append(_part("robe_edge", "trim", edge, _skirt_weights(spec, edge), smooth=False))
    return parts


def _sash(spec):
    g = spec["garment"]
    s = g["sash"]
    z0, z1 = s["z"]
    rings = []
    for z in (z0, (z0 + z1) / 2, z1):
        rx, ry = _interp_rows(g["bodice"] + g["skirt"], z)
        rings.append(ellipse_ring(0, 0, z, rx + s["out"], ry + s["out"], 24))
    m = Mesh()
    m.add_ring_loft(rings)
    parts = [_part("sash", "sash", m, _rigid(m, "pelvis"))]
    kx, ky, kz = s["knot"]
    knot = sphere((kx, ky, kz), (0.9, 0.6, 0.8), 10, 8)
    parts.append(_part("sash_knot", "sash", knot, _rigid(knot, "pelvis")))
    # ONE broad tail, not two cords: at 32x48 two thin tails and a knot read as a green
    # squiggle; one ribbon reads as a sash.
    path = [(kx, ky - 0.2, kz - 0.3),
            (kx - 0.5, ky - 0.5, kz - s["tail_length"] * 0.5),
            (kx - 0.8, ky - 0.6, kz - s["tail_length"])]
    tail = tube(path, [0.9, 0.95, 1.0], 8, squash=0.3)
    parts.append(_part("sash_tail_0", "sash", tail,
                       _blend_z(tail, [(kz, "pelvis"), (kz - 2.5, "sash_tail")])))
    return parts


def _sleeve_rings(spec, side):
    g = spec["garment"]["sleeve"]
    sh, el, wr, _tip = _arm_points(spec, side)
    pts = []
    prof = g["profile"]
    n_steps = 9
    for i in range(n_steps):
        t = i / (n_steps - 1.0)
        # position along shoulder->elbow->wrist by t (half each)
        if t <= 0.5:
            p = tuple(_lerp(sh[k], el[k], t / 0.5) for k in range(3))
        else:
            p = tuple(_lerp(el[k], wr[k], (t - 0.5) / 0.5) for k in range(3))
        r = _interp_rows([[a, b2, b2] for a, b2 in prof], t)[0]
        pts.append((t, p, r))
    return pts


def _sleeves(spec):
    parts = []
    for side, sfx in ((1, "L"), (-1, "R")):
        pts = _sleeve_rings(spec, side)
        path = [p for _, p, _ in pts]
        radii = [r for _, _, r in pts]
        # The cuff opening ends just past the wrist: the WHOLE hand is outside it. (It reached
        # 1.3 past the wrist once, and with a short hand the palm never left the sleeve — the
        # strike was an empty sleeve thrust forward.)
        sh, el, wr, tip = _arm_points(spec, side)
        d = _norm(_sub(wr, el))
        path.append(_add(wr, _mul(d, 0.35)))
        radii.append(radii[-1])
        m = tube(path, radii, 14, up=(0, -1, 0), cap=False)
        n = 14
        names = ["shoulder." + sfx, "upper_arm." + sfx, "forearm." + sfx]
        w = {nm: [0.0] * len(m.verts) for nm in names}
        rings_t = [t for t, _, _ in pts] + [1.05]
        for ri, t in enumerate(rings_t):
            for k in range(n):
                vi = ri * n + k
                if t < 0.08:
                    w["shoulder." + sfx][vi] = 1.0
                elif t < 0.45:
                    w["upper_arm." + sfx][vi] = 1.0
                elif t < 0.6:
                    s = (t - 0.45) / 0.15
                    w["upper_arm." + sfx][vi] = 1 - s
                    w["forearm." + sfx][vi] = s
                else:
                    w["forearm." + sfx][vi] = 1.0
        parts.append(_part("sleeve." + sfx, "robe", m, w))
        # cuff band (trim) at the opening
        cuff = tube([path[-2], path[-1]], [radii[-1] * 1.03, radii[-1] * 1.03], 14,
                    up=(0, -1, 0), cap=False)
        parts.append(_part("cuff." + sfx, "trim", cuff, _rigid(cuff, "forearm." + sfx)))
    return parts


def _hands(spec):
    """A real hand on each wrist: a palm, four fingers and a thumb, relaxed — fingers together
    and gently curled toward the palm, the thumb set forward. The moodboard hand is long and
    fine; the CHARACTER_ART_BIBLE forbids the "circle-hand shortcut" (§6b). At 32x48 it still
    reduces to 2-3 skin pixels, but its silhouette — narrower than a ball, longer than wide —
    is what the pixel vote sees, and at portrait / presentation scale it is a hand."""
    parts = []
    hs = spec["body"].get("hand_shape", {})
    for side, sfx in ((1, "L"), (-1, "R")):
        _sh, _el, wr, tip = _arm_points(spec, side)
        d = _norm(_sub(tip, wr))                       # along the hand, wrist -> fingertips
        fwd = (0.0, -1.0, 0.0)                         # the thumb side faces forward at rest
        palm_n = _norm(_cross(d, fwd))                 # out of the palm
        if palm_n[0] * side > 0:
            palm_n = _mul(palm_n, -1.0)                # the palm faces the body
        across = _norm(_cross(palm_n, d))              # across the knuckles
        if across[1] > 0:
            across = _mul(across, -1.0)                # toward the thumb (forward)
        hand_len = spec["body"]["hand"]
        palm_len = hand_len * 0.5
        finger_len = hs.get("finger", 0.44) * hand_len
        p0 = _add(wr, _mul(d, -0.2))                   # the wrist, just inside the cuff
        p1 = _add(wr, _mul(d, palm_len))
        palm = tube([p0, _lerp_v(p0, p1, 0.45), p1], [0.5, 0.78, 0.72], 10, up=palm_n,
                    squash=0.45)
        parts.append(_part("palm." + sfx, "skin", palm, _rigid(palm, "hand." + sfx)))
        for i, (off, ln) in enumerate(((0.48, 0.92), (0.16, 1.0), (-0.16, 0.96), (-0.46, 0.78))):
            base = _add(_add(p1, _mul(across, off)), _mul(d, -0.15))
            L = finger_len * ln
            mid = _add(_add(base, _mul(d, L * 0.55)), _mul(palm_n, 0.15))
            end = _add(_add(base, _mul(d, L * 0.95)), _mul(palm_n, 0.45))
            f = tube([base, mid, end], [0.2, 0.18, 0.13], 6, up=palm_n)
            parts.append(_part("finger%d.%s" % (i, sfx), "skin", f, _rigid(f, "hand." + sfx)))
        tb = _add(_add(wr, _mul(d, palm_len * 0.3)), _mul(across, 0.55))
        tm = _add(_add(tb, _mul(across, 0.45)), _mul(d, 0.65))
        te = _add(_add(tm, _mul(d, 0.6)), _mul(palm_n, 0.25))
        th = tube([tb, tm, te], [0.26, 0.21, 0.15], 6, up=palm_n)
        parts.append(_part("thumb." + sfx, "skin", th, _rigid(th, "hand." + sfx)))
    return parts


def _lerp_v(a, b, t):
    return tuple(_lerp(a[k], b[k], t) for k in range(3))


def _legs(spec):
    b = spec["body"]
    parts = []
    r0, r1 = b["leg_radius"]
    f = b["foot"]
    for side, sfx in ((1, "L"), (-1, "R")):
        x = side * b["hip_x"]
        m = tube([(x, 0, b["hip"] + 1.0), (x, 0, b["knee"]), (x, 0.2, b["ankle"] - 0.2)],
                 [r0, (r0 + r1) / 2, r1], 10)
        w = _blend_z(m, [(b["knee"] + 1.0, "thigh." + sfx), (b["knee"] - 1.0, "shin." + sfx)])
        parts.append(_part("leg." + sfx, "trousers", m, w))
        path = [(x, 0.9, f["height"] * 0.55), (x, -f["length"] * 0.45, f["height"] * 0.5),
                (x, -f["length"] * 0.8, f["height"] * 0.35)]
        shoe = tube(path, [f["width"] * 0.5, f["width"] * 0.5, f["width"] * 0.38], 10,
                    up=(0, 0, 1), squash=0.75)
        parts.append(_part("shoe." + sfx, "shoe", shoe, _rigid(shoe, "foot." + sfx)))
    return parts


def _hair(spec):
    h = spec["hair"]
    b = spec["body"]
    parts = []
    hx, hy, hz = b["head_centre"]
    rx, ry, rz = b["head_radii"]
    # Scalp cap: the head sphere, slightly larger, cut along a line that is high at the front
    # (forehead and parted fringe), lower at the sides (over the ears) and low at the back.
    fr = h["fringe"]
    cap = sphere((hx, hy + 0.15, hz + 0.2), (rx * fr["scale"], ry * fr["scale"],
                                              rz * fr["scale"]), 22, 16)
    keep = []
    for (a, b2, c, *rest) in cap.faces:
        idx = (a, b2, c) + tuple(rest)
        ok = True
        for vi in idx:
            x, y, z = cap.verts[vi]
            # angle from the FRONT: 0 = forehead, 90 = over the ear, 180 = nape
            theta = math.degrees(math.atan2(abs(x - hx), -(y - hy)))
            # the parted fringe: higher at the centre part, two bangs lower at |x| ~ 2.6
            bangs = 0.9 * math.exp(-((abs(x) - 2.6) ** 2) / 2.2) - 0.7 * math.exp(-(x * x) / 0.8)
            # The hairline is HIGH over the whole face and the cheek, and only falls BEHIND the
            # ear: in profile the face must stay readable, and the first pass (hair to the jaw
            # from 70°) left a profile that was a white hood with a sliver of cheek at 32x48.
            if theta < 82:              # forehead, temples, cheek: the hairline stays high
                cut = fr["cut_z"] - bangs * max(0.0, 1 - theta / 60.0)
            elif theta < 108:           # over and behind the ear the hair falls to the jaw line
                t = (theta - 82) / 26.0
                cut = _lerp(fr["cut_z"], hz - 2.6, t)
            else:                       # behind the ear down to the nape
                t = min(1.0, (theta - 108) / 45.0)
                cut = _lerp(hz - 2.6, hz - 6.5, t)
            if z < cut:
                ok = False
                break
        if ok:
            keep.append(idx)
    cap.faces = keep
    # Strands: a shallow ridge every ~25° of longitude, so the key light breaks the cap into
    # combed bands instead of one smooth shell (moodboard hair is strands, never a helmet).
    grooves = fr.get("grooves", 0.035)
    cap.verts = [_groove(v, (hx, hy + 0.15, hz + 0.2), grooves) for v in cap.verts]
    # the hair follows the sculpted skull: on a ball it would stand off the narrowed jaw like
    # a helmet
    cap.verts = [shape_head(spec, v) for v in cap.verts]
    parts.append(_part("hair_cap", "hair", cap, _rigid(cap, "head")))
    parts += _bangs(spec)
    # The back mass: waist-length, lying on the back, widening slightly then tapering.
    hb = h["back"]
    rings = []
    steps = 12
    for i in range(steps):
        t = i / (steps - 1.0)
        z = _lerp(hb["top_z"], hb["bottom_z"], t)
        wdt = _interp_rows([[0.0, hb["width"][0], 0], [0.45, hb["width"][1], 0],
                            [0.8, hb["width"][2] * 1.5, 0], [1.0, hb["width"][2], 0]], t)[0]
        y = _hair_back_y(spec, z) + hb["thickness"] * 0.5 + hb["flare"] * t * t
        rings.append(ellipse_ring(0, y, z, wdt * 0.5, hb["thickness"] * 0.5 * (1 - 0.3 * t),
                                  16))
    m = Mesh()
    m.add_ring_loft(rings, cap_end=True)
    z0, z1, z2, z3 = _hair_chain_z(hb)
    w = _blend_z(m, [(z0, "head"), (z1, "hair_1"), (z2, "hair_2"), (z3, "hair_3")])
    parts.append(_part("hair_back", "hair", m, w))
    # Side locks framing the face, falling in front of the shoulders.
    lk = h.get("locks")
    for side, sfx in (((1, "L"), (-1, "R")) if lk else ()):
        fx, fy, fz = lk["from"]
        z_mid = (fz + lk["to_z"]) / 2
        # The lock HANGS: straight down beside the jaw, drifting a little outward. It used to
        # be pulled forward onto the chest surface, which in profile drew a white diagonal
        # across the cheek at 32x48.
        path = [(side * fx, fy, fz),
                (side * (fx + 0.25), fy + 0.1, z_mid),
                (side * (fx + 0.45), fy + 0.2, lk["to_z"])]
        strand = tube(path, [lk["width"] * 0.6, lk["width"] * 0.55, lk["width"] * 0.35], 8,
                      up=(0, -1, 0), squash=0.55)
        w = _blend_z(strand, [(fz, "head"), (lk["to_z"], "lock." + sfx)])
        parts.append(_part("lock." + sfx, "hair", strand, w))
    bun = h.get("bun")
    if bun:
        m = sphere(tuple(bun["centre"]), (bun["radius"], bun["radius"] * 0.95,
                                          bun["radius"] * 0.9), 12, 10)
        parts.append(_part("bun", "hair", m, _rigid(m, "head")))
        pin = h.get("pin")
        if pin:
            cx, cy, cz = bun["centre"]
            L = pin["length"]
            pm = tube([(cx - L / 2, cy, cz + 0.3), (cx + L / 2, cy, cz + 0.6)],
                      [pin["radius"], pin["radius"]], 8, up=(0, 0, 1))
            parts.append(_part("pin", "pin", pm, _rigid(pm, "head")))
    return parts


def _pendant(spec):
    w = spec["body"]["waist"]
    m = sphere((2.6, -4.0, w - 4.4), (0.95, 0.35, 1.05), 10, 8)
    cord = tube([(2.4, -3.8, w - 1.6), (2.6, -4.0, w - 3.4)], [0.18, 0.18], 6)
    return [_part("pendant", "pendant", m, _rigid(m, "pelvis")),
            _part("pendant_cord", "sash", cord, _rigid(cord, "pelvis"))]


def _beard(spec):
    b = spec["body"]
    hx, hy, hz = b["head_centre"]
    rx, ry, rz = b["head_radii"]
    chin = (hx, hy - ry * 0.75, hz - rz * 0.8)
    path = [chin, (hx, hy - ry * 0.95, hz - rz * 1.15), (hx, hy - ry * 0.9, hz - rz * 1.55)]
    m = tube(path, [2.0, 1.5, 0.5], 10, up=(0, -1, 0), squash=0.6)
    return [_part("beard", "hair", m, _blend_z(m, [(chin[2], "head"), (path[-1][2], "chest")]))]


def _cap(spec):
    """A cloth head-wrap (khăn) over the topknot: the merchant's and villager's head."""
    b = spec["body"]
    hx, hy, hz = b["head_centre"]
    rx, ry, rz = b["head_radii"]
    m = sphere((hx, hy + 0.4, hz + rz * 0.62), (rx * 0.95, ry * 0.95, rz * 0.5), 16, 10)
    return [_part("cap", "accent", m, _rigid(m, "head"))]


def _groove(v, centre, depth):
    """Push a vertex in/out radially by a ridge pattern around the vertical axis."""
    dx, dy, dz = v[0] - centre[0], v[1] - centre[1], v[2] - centre[2]
    k = 1.0 + depth * math.sin(math.atan2(dx, dy) * 14.0)
    return (centre[0] + dx * k, centre[1] + dy * k, centre[2] + dz)


def _bangs(spec):
    """Curtain bangs from a centre part: on each side a broad lock leaves the part, sweeps over
    the temple and falls past the eye to the cheekbone, with a thinner strand inside it. This is
    what turns a straight hairline (a bowl cut) into parted, framed hair — the face is shown
    BETWEEN two locks, as on every moodboard cultivator. Designs tune or drop it (`bangs`)."""
    bg = spec["hair"].get("bangs")
    if not bg:
        return []
    b = spec["body"]
    hx, hy, hz = b["head_centre"]
    rx, ry, rz = b["head_radii"]
    e = spec["face"]["eyes"]
    parts = []
    for side, sfx in ((1, "L"), (-1, "R")):
        # Every lock clears the eye: by the eye line it is OUTSIDE the outer corner
        # (eye x + almond half-width + a margin), so the face is framed, never covered.
        clear = e["x"] + e.get("almond", [1.05, 0.55])[0] * 0.62 + 0.5
        for k, (spread, width, drop, out) in enumerate(bg["locks"]):
            xs = [0.35, 0.55 * clear + spread, clear + spread, clear + 0.35 + spread]
            zs = [hz + rz * 0.92, hz + rz * 0.5, e["z"] + 0.3, e["z"] - drop]
            path = [_face_point(spec, side * min(x, rx * 0.97), z, out + 0.12 * i)
                    for i, (x, z) in enumerate(zip(xs, zs))]
            lock = tube(path, [width * 0.7, width, width * 0.8, width * 0.35], 8,
                        up=(0, -1, 0), squash=0.35)
            parts.append(_part("bang%d.%s" % (k, sfx), "hair", lock, _rigid(lock, "head")))
    return parts


def _pibo(spec):
    """披帛 — the long silk stole of a cultivator in light robes: draped across the back of the
    shoulders, falling OUTSIDE the sleeves and hanging free to the knee. At 32x48 it is two
    ribbons of accent colour beside the robe: a silhouette no male archetype has.

    Weighting makes it cloth, not a hoop: the part across the back follows the chest, the part
    over the arm follows the upper arm, and the free tail runs from the forearm down to the hip."""
    b = spec["body"]
    pb = spec["pibo"]
    parts = []
    sleeve_r = max(r for _, r in spec["garment"]["sleeve"]["profile"])
    for side, sfx in ((1, "L"), (-1, "R")):
        sh, el, wr, _tip = _arm_points(spec, side)
        out_x = abs(wr[0]) + sleeve_r + pb["gap"]
        path = [(side * 1.0, 2.9, b["shoulder"] - 0.6),
                (side * (abs(sh[0]) - 0.6), 2.4, b["shoulder"] + 0.5),
                (side * (abs(sh[0]) + 1.6), 0.6, b["shoulder"] - 2.6),
                (side * (out_x - 0.4), -0.4, el[2]),
                (side * out_x, -0.2, _lerp(el[2], pb["end_z"], 0.5)),
                (side * (out_x - 0.3), 0.2, pb["end_z"])]
        w_r = pb["width"]
        m = tube(path, [w_r * 0.8, w_r, w_r, w_r, w_r, w_r * 0.9], 8, up=(0, 0, 1),
                 squash=0.32)
        # The free tail hangs from the forearm but FALLS toward the hip: silk draped over an
        # arm never sticks out rigidly with it (a seated figure's forearms are horizontal).
        w = _blend_z(m, [(b["shoulder"] + 0.5, "chest"), (b["shoulder"] - 2.6,
                                                           "upper_arm." + sfx),
                         (el[2], "forearm." + sfx), (pb["end_z"], "pelvis")])
        parts.append(_part("pibo." + sfx, "accent", m, w))
    return parts


PIECES = {
    "pibo": _pibo,
    "pendant": _pendant,
    "beard": _beard,
    "cap": _cap,
}


def build(spec):
    """All mesh parts of a resolved actor spec (cultivator + actor overrides)."""
    parts = _head(spec) + [_neck(spec)]
    parts += _eyes(spec)
    parts += _face_detail(spec)
    parts.append(_bodice(spec))
    parts += _collar(spec)
    parts += _skirt(spec)
    parts += _sash(spec)
    parts += _sleeves(spec)
    parts += _hands(spec)
    parts += _legs(spec)
    parts += _hair(spec)
    for piece in spec.get("pieces", []):
        parts += PIECES[piece](spec)
    return parts
