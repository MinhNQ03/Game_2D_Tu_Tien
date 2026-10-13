"""World prop geometry (D-062 CP10): Hoang Vực village architecture and nature, built from the
same primitives as the cultivator and rendered by the same passes, so a house, a tree and a
person share light, ramps and ink.

UNITS are the character's: the canonical cultivator stands ~50 units, so 1 m ~ 29 units. The
gameplay camera renders props at the character's pixel density (designs/cultivator.yaml
camera.gameplay: `ortho_units` per `cell` height), so a doorway is a person tall.

Every prop's ORIGIN is the centre of its FRONT BASE (y = 0 is the front wall line, the body
extends toward +Y, away from the camera). That is where the depth sort compares it with a
walking figure: in front of the line you are in front of the house.
"""
import math

from humanoid import Mesh, sphere, tube


def _part(name, material, mesh, smooth=False):
    return {"name": name, "material": material, "verts": mesh.verts, "faces": mesh.faces,
            "smooth": smooth}


def _pyramid(x0, y0, z0, x1, y1, za):
    """A square pyramid: the base ring at z0 lofted to one apex. Flat-shaded faces (the
    recalc in the Blender side fixes the winding)."""
    m = Mesh()
    ax, ay = (x0 + x1) / 2.0, (y0 + y1) / 2.0
    m.verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (ax, ay, za)]
    m.faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4), (3, 2, 1, 0)]
    return m


def _lump(seed, cx, cy, cz, rx, ry, rz, jxy=6.0, jz=5.0):
    """A jittered solid lump of living rock (flat-shaded facets, like `boulder`)."""
    m = sphere((cx, cy, cz), (rx, ry, rz), 14, 10)
    m.verts = [(x + (_h(int(x), int(z), seed) - 0.5) * jxy,
                y + (_h(int(y), int(x), seed) - 0.5) * jxy * 0.8,
                max(0.0, z + (_h(int(z), int(y), seed) - 0.5) * jz))
               for x, y, z in m.verts]
    return m


def _h(x, y, seed):
    v = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    v = ((v ^ (v >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0


def box(x0, y0, z0, x1, y1, z1):
    m = Mesh()
    m.verts = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0),
               (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
    m.faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6),
               (3, 0, 4, 7)]
    return m


def cylinder(cx, cy, z0, z1, r, seg=16):
    m = Mesh()
    rings = []
    for z in (z0, z1):
        rings.append([(cx + r * math.cos(math.tau * i / seg), cy + r * math.sin(math.tau * i / seg),
                       z) for i in range(seg)])
    m.add_ring_loft(rings, cap_start=True, cap_end=True)
    return m


def gable_roof(x0, x1, y0, y1, z_eave, z_ridge, overhang, side_over, lift=7.0, cols=None,
               rows=6, ridge_y=None, course=6.0):
    """A tiled gable roof: two slopes meeting at a ridge along X, the eave overhanging the
    walls and the four corners swept UP (the curve of an East Asian eave). Each slope is a
    grid whose alternate columns ride 1.6 units higher — the tile courses running down the
    slope, which the light pass turns into the roof's stripes at pixel scale."""
    ry = (y0 + y1) / 2.0 if ridge_y is None else ridge_y
    xa, xb = x0 - side_over, x1 + side_over
    # one tile course every `course` units (~5-6 px at the gameplay scale): narrow enough to
    # read as courses, wide enough to survive the 4x4 vote
    if cols is None:
        cols = max(4, int((xb - xa) / (course / 2.0)))
        cols += cols % 2
    parts = []
    for ya, yb in ((y0 - overhang, ry), (y1 + overhang, ry)):
        m = Mesh()
        grid = []
        for r in range(rows + 1):
            t = r / rows                       # 0 at the eave, 1 at the ridge
            y = ya + (yb - ya) * t
            z_lin = z_eave + (z_ridge - z_eave) * t
            sag = -3.0 * math.sin(math.pi * t)  # a gently concave slope
            row = []
            for c in range(cols + 1):
                u = c / cols
                x = xa + (xb - xa) * u
                corner = max(0.0, 1.0 - t * 3.0) * (abs(u - 0.5) * 2.0) ** 3
                # alternate columns are the round "cover" tiles riding over the pan tiles: a
                # deep enough step that the light breaks the slope into courses
                z = z_lin + sag + lift * corner + (3.4 if c % 2 else 0.0) * (1.0 - t * 0.25)
                row.append((x, y, z))
            grid.append(row)
        for row in grid:
            m.verts.extend(row)
        n = cols + 1
        for r in range(rows):
            for c in range(cols):
                a = r * n + c
                m.faces.append((a, a + 1, a + n + 1, a + n))
        parts.append(m)
    # the eave fascia: the roof's thickness seen at its lower edge
    fascia = Mesh()
    for ya in (y0 - overhang,):
        lo, hi = [], []
        for c in range(cols + 1):
            u = c / cols
            x = xa + (xb - xa) * u
            corner = (abs(u - 0.5) * 2.0) ** 3
            z = z_eave + lift * corner
            hi.append((x, ya, z + 0.5))
            lo.append((x, ya - 0.5, z - 3.0))
        fascia.add_strip(hi, lo)
    # the round tile-ends along the front eave: a dotted edge at pixel scale
    for c in range(1, cols, 2):
        u = c / cols
        x = xa + (xb - xa) * u
        corner = (abs(u - 0.5) * 2.0) ** 3
        cap = sphere((x, y0 - overhang - 0.6, z_eave + lift * corner + 1.2), (1.9, 1.2, 1.9), 6, 4)
        base = len(fascia.verts)
        fascia.verts.extend(cap.verts)
        fascia.faces.extend(tuple(i + base for i in f) for f in cap.faces)
    ridge = tube([(xa + 4, ry, z_ridge + 1.0), (xb - 4, ry, z_ridge + 1.0)], [3.6, 3.6], 8,
                 up=(0, 0, 1))
    ends = [sphere((x, ry, z_ridge + 4.0), (3.4, 2.6, 4.2), 8, 6) for x in (xa + 3, xb - 3)]
    return parts, fascia, ridge, ends


def dwelling(d):
    """A frontier dwelling: a plinth of fieldstone, lime-plastered walls between dark timber
    posts, a plank door and two paper lattice windows, a slate-tiled gable roof."""
    W, D, H = d.get("w", 150.0), d.get("d", 96.0), d.get("h", 64.0)
    x0, x1, y0, y1 = -W / 2, W / 2, 0.0, D
    parts = [_part("plinth", "stone", box(x0 - 4, y0 - 4, 0, x1 + 4, y1 + 4, 7)),
             _part("walls", "plaster", box(x0, y0, 7, x1, y1, H))]
    for x in (x0, x1, -W / 6, W / 6):
        parts.append(_part("post%g" % x, "timber", box(x - 3, y0 - 2, 7, x + 3, y0 + 3, H)))
    parts.append(_part("beam", "timber", box(x0 - 2, y0 - 2.5, H - 7, x1 + 2, y0 + 3, H)))
    parts.append(_part("sill", "timber", box(x0 - 2, y0 - 2.5, 7, x1 + 2, y0 + 3, 11)))
    parts.append(_part("door", "door", box(-13, y0 - 2, 11, 13, y0 + 1, 54)))
    for sx in (-1, 1):
        cx = sx * W * 0.33
        parts.append(_part("window%d" % sx, "paper", box(cx - 12, y0 - 1.5, 26, cx + 12,
                                                         y0 + 1, 44)))
        for k in (-4, 4):
            parts.append(_part("lattice%d%d" % (sx, k), "timber",
                               box(cx + k - 0.8, y0 - 2.2, 26, cx + k + 0.8, y0 + 1, 44)))
        parts.append(_part("lattice_h%d" % sx, "timber", box(cx - 12, y0 - 2.2, 34.2, cx + 12,
                                                             y0 + 1, 35.8)))
    slopes, fascia, ridge, ends = gable_roof(x0, x1, y0, y1, H - 2, H + 46, 20, 14, lift=9.0)
    parts += [_part("roof_front", "roof", slopes[0]), _part("roof_back", "roof", slopes[1]),
              _part("fascia", "roof_dark", fascia), _part("ridge", "roof_dark", ridge)]
    parts += [_part("ridge_end%d" % i, "roof_dark", e) for i, e in enumerate(ends)]
    return parts


def outpost_hall(d):
    """The Thanh Vân OUTPOST (a lesser hall of a larger power, WORLD_BIBLE §4.5): a raised stone
    terrace with steps, a veranda of cinnabar-lacquered pillars under a deep eave, a gilt name
    board over the door, a heavier tiled roof with a steeper ridge. Modest — an outpost, not a
    palace."""
    W, D, H = d.get("w", 200.0), d.get("d", 120.0), d.get("h", 76.0)
    x0, x1, y0, y1 = -W / 2, W / 2, 26.0, 26.0 + D
    parts = [_part("terrace", "stone", box(x0 - 14, 0, 0, x1 + 14, y1 + 8, 12))]
    for i, (w2, y2) in enumerate(((60, -10), (52, -5))):
        parts.append(_part("step%d" % i, "stone_light", box(-w2 / 2, y2, 0, w2 / 2, 0, 4 + 4 * i)))
    parts.append(_part("walls", "plaster", box(x0, y0, 12, x1, y1, H)))
    parts.append(_part("door", "door", box(-18, y0 - 1.5, 12, 18, y0 + 1, 62)))
    parts.append(_part("board", "gilt", box(-16, y0 - 6, 64, 16, y0 - 2, 72)))
    for sx in (-1, 1):
        cx = sx * W * 0.3
        parts.append(_part("window%d" % sx, "paper", box(cx - 16, y0 - 1.5, 30, cx + 16,
                                                         y0 + 1, 52)))
        for k in (-8, 0, 8):
            parts.append(_part("lattice%d%d" % (sx, k), "timber",
                               box(cx + k - 0.8, y0 - 2.2, 30, cx + k + 0.8, y0 + 1, 52)))
    for i, x in enumerate((x0 + 6, -W * 0.16, W * 0.16, x1 - 6)):
        parts.append(_part("pillar%d" % i, "lacquer_red", cylinder(x, 8, 12, H + 2, 3.6, 12)))
        parts.append(_part("pillar_base%d" % i, "stone_light", cylinder(x, 8, 12, 15, 5.0, 12)))
    parts.append(_part("lintel", "lacquer_red", box(x0, 4, H - 4, x1, 12, H + 2)))
    slopes, fascia, ridge, ends = gable_roof(x0, x1, y0, y1, H - 2, H + 64, 34, 18, lift=12.0,
                                             rows=7)
    parts += [_part("roof_front", "roof", slopes[0]), _part("roof_back", "roof", slopes[1]),
              _part("fascia", "roof_dark", fascia), _part("ridge", "roof_dark", ridge)]
    parts += [_part("ridge_end%d" % i, "roof_dark", e) for i, e in enumerate(ends)]
    return parts


def broadleaf_tree(d):
    """A broad frontier tree: a leaning, tapering trunk splitting into two limbs, and a canopy of
    lumpy leaf masses (displaced spheres) so the light breaks it into clumps, not a ball."""
    seed = int(d.get("seed", 1))
    s = d.get("scale", 1.0)
    trunk = tube([(0, 0, 0), (2 * s, 2 * s, 34 * s), (4 * s, 3 * s, 62 * s)],
                 [7 * s, 5.2 * s, 4.0 * s], 10, up=(0, -1, 0))
    limbs = [tube([(4 * s, 3 * s, 58 * s), (-16 * s, 6 * s, 82 * s)], [3.2 * s, 2.0 * s], 8,
                  up=(0, -1, 0)),
             tube([(4 * s, 3 * s, 58 * s), (22 * s, 0, 86 * s)], [3.0 * s, 1.8 * s], 8,
                  up=(0, -1, 0))]
    parts = [_part("trunk", "bark", trunk, smooth=True)]
    parts += [_part("limb%d" % i, "bark", m, smooth=True) for i, m in enumerate(limbs)]
    masses = [(0, 4, 104, 34), (-26, 8, 90, 26), (28, 4, 92, 27), (-12, -10, 118, 24),
              (16, -8, 120, 23), (2, 14, 126, 22), (-30, -4, 108, 18), (32, 14, 106, 19)]
    for i, (cx, cy, cz, r) in enumerate(masses):
        m = sphere((cx * s, cy * s, cz * s), (r * s, r * s * 0.9, r * s * 0.82), 14, 10)
        m.verts = [(x + (_h(int(x * 3), int(z * 3), seed + i) - 0.5) * 7 * s,
                    y + (_h(int(y * 3), int(x * 3), seed + i) - 0.5) * 5 * s,
                    z + (_h(int(z * 3), int(y * 3), seed + i) - 0.5) * 6 * s)
                   for x, y, z in m.verts]
        parts.append(_part("leaves%d" % i, "leaves", m, smooth=True))
    return parts


def fence(d):
    """A post-and-two-rail fence along +X, `length` units, posts every 30."""
    L = d.get("length", 150.0)
    n = max(2, int(L // 30) + 1)
    parts = []
    for i in range(n):
        x = -L / 2 + L * i / (n - 1)
        parts.append(_part("post%d" % i, "timber", box(x - 2.5, -2.5, 0, x + 2.5, 2.5, 34)))
        parts.append(_part("cap%d" % i, "timber_light", box(x - 3, -3, 34, x + 3, 3, 36)))
    for z in (12, 26):
        parts.append(_part("rail%d" % z, "timber_light", box(-L / 2, -1.5, z, L / 2, 1.5, z + 4)))
    return parts


def well(d):
    """A village well: a fieldstone ring, a timber frame with a windlass, a small tiled cap."""
    parts = [_part("ring", "stone", cylinder(0, 20, 0, 20, 20, 20)),
             _part("water", "water", cylinder(0, 20, 18, 19, 16, 20))]
    for sx in (-1, 1):
        parts.append(_part("post%d" % sx, "timber", box(sx * 24 - 2.5, 17.5, 0, sx * 24 + 2.5,
                                                        22.5, 56)))
    parts.append(_part("axle", "timber_light", tube([(-24, 20, 44), (24, 20, 44)], [2.2, 2.2], 8,
                                                     up=(0, 0, 1))))
    slopes, fascia, ridge, ends = gable_roof(-30, 30, 8, 32, 54, 70, 8, 6, lift=3.0, rows=3)
    parts += [_part("cap_front", "roof", slopes[0]), _part("cap_back", "roof", slopes[1]),
              _part("cap_ridge", "roof_dark", ridge)]
    parts.append(_part("bucket", "timber_light", cylinder(10, 6, 0, 10, 6, 10)))
    return parts


def weapon_rack(d):
    """A training-yard rack: a timber frame with staves leaning on it."""
    parts = [_part("frame_l", "timber", box(-30, -2, 0, -26, 2, 40)),
             _part("frame_r", "timber", box(26, -2, 0, 30, 2, 40)),
             _part("bar", "timber_light", box(-32, -2.5, 34, 32, 2.5, 38))]
    for i, x in enumerate((-20, -10, 0, 10, 20)):
        parts.append(_part("staff%d" % i, "timber_light",
                           tube([(x, 6, 0), (x + 2, -1, 44)], [1.4, 1.2], 6, up=(1, 0, 0))))
    return parts


# The carts stand a little askew to the camera (D-073 follow-up, H21-17). Seen square-on from
# above-front a cart's wheels are edge-on: two dark slabs, and the thing reads as a box on
# posts. Turned this far, each wheel shows its FACE - a rim, a hub, spokes - which is what
# says "cart" at 1x.
CART_YAW_DEG = 34.0
# How far each is moved back after the turn so its bed's nearest corner sits on y = 0. The
# turned bed is a rectangle seen corner-on; its solid base (pixel/pixelize.py `_footprint`)
# is the rectangle INSIDE that diamond, so the two walkable corners are not walls.
CART_BACK = 10.0
WRECK_BACK = 14.0


def _wheel(name, cx, cy, cz, r, axis="x", rim="timber", spoke="timber_light", hub="wood_pale"):
    """A spoked cart wheel centred at (cx, cy, cz): a rim, six spokes, a hub. `axis` is the
    axle's direction - "x" for a wheel standing on its cart, "z" for one lying on the ground."""
    parts = []
    seg = 16
    ring = []
    for i in range(seg + 1):
        a = math.tau * i / seg
        u, v = r * math.cos(a), r * math.sin(a)
        ring.append((cx, cy + u, cz + v) if axis == "x" else (cx + u, cy + v, cz))
    up = (1, 0, 0) if axis == "x" else (0, 0, 1)
    parts.append(_part(name + "_rim", rim, tube(ring, [1.9] * len(ring), 6, up=up)))
    for k in range(3):                                   # three bars across = six spokes
        a = math.pi * k / 3 + 0.26
        u, v = (r - 1.0) * math.cos(a), (r - 1.0) * math.sin(a)
        if axis == "x":
            ends = [(cx, cy - u, cz - v), (cx, cy + u, cz + v)]
        else:
            ends = [(cx - u, cy - v, cz), (cx + u, cy + v, cz)]
        parts.append(_part("%s_spoke%d" % (name, k), spoke, tube(ends, [1.0, 1.0], 5, up=up)))
    if axis == "x":
        ends = [(cx - 2.6, cy, cz), (cx + 2.6, cy, cz)]
        parts.append(_part(name + "_hub", hub, tube(ends, [3.0, 3.0], 8, up=(0, 0, 1))))
    else:
        parts.append(_part(name + "_hub", hub, cylinder(cx, cy, cz - 1.2, cz + 2.4, 3.0, 8)))
    return parts


def cart(d):
    """A frontier haul cart, standing unhitched: a plank bed on two spoked wheels, shafts
    resting on a prop-stick, and a load of nailed crates under a tarpaulin roped down. The
    crates are the point - nobody in Lạc Hà has seen inside one."""
    parts = [_part("bed", "timber", box(-26, 2, 13, 26, 34, 17)),
             _part("rail_l", "timber_light", box(-27, 2, 17, -24, 34, 24)),
             _part("rail_r", "timber_light", box(24, 2, 17, 27, 34, 24)),
             _part("tail", "timber_light", box(-26, 32, 17, 26, 34, 23))]
    for sx in (-1, 1):
        x = sx * 30
        parts += _wheel("wheel%d" % sx, x, 18, 13, 13)
        parts.append(_part("shaft%d" % sx, "timber_light",
                           tube([(sx * 16, 2, 15), (sx * 13, -30, 12)], [1.6, 1.4], 6,
                                up=(0, 0, 1))))
    parts.append(_part("yoke", "timber", box(-15, -31, 10.5, 15, -28.5, 13.5)))
    parts.append(_part("prop", "timber", box(-1.2, -27, 0, 1.2, -25, 11)))
    for i, (x0, y0, x1, y1, z1) in enumerate(((-22, 5, -3, 20, 32), (-1, 5, 21, 19, 30),
                                              (-18, 20, 4, 32, 31), (6, 19, 22, 32, 28))):
        parts.append(_part("crate%d" % i, "wood_pale", box(x0, y0, 17, x1, y1, z1)))
        parts.append(_part("band%d" % i, "timber", box(x0 - 0.4, y0 - 0.4, z1 - 5, x1 + 0.4,
                                                       y1 + 0.4, z1 - 3)))
    parts.append(_part("tarp", "plaster", box(-24, 16, 31, 24, 34, 33.5)))
    parts.append(_part("tarp_fall", "plaster", box(-24, 33, 20, 24, 34.6, 33)))
    parts.append(_part("rope", "timber", box(-25, 24, 33.5, 25, 25.4, 34.6)))
    # turned about the bed's middle, then moved back so the turned bed's nearest corner is on
    # the origin line (y = 0): the origin stays "the front of the thing", as for every prop
    return _tilt(parts, (0.0, 18.0, 0.0), yaw_deg=CART_YAW_DEG, shift=(0.0, CART_BACK, 0.0))


def _tilt(parts, pivot, roll_deg=0.0, pitch_deg=0.0, yaw_deg=0.0, shift=(0.0, 0.0, 0.0)):
    """Rotate `parts` about `pivot` — roll about the Y (depth) axis, pitch about X, yaw about Z,
    in that order — then move them by `shift`. Nothing may end below the ground."""
    cr, sr = math.cos(math.radians(roll_deg)), math.sin(math.radians(roll_deg))
    cp, sp = math.cos(math.radians(pitch_deg)), math.sin(math.radians(pitch_deg))
    cy, sy = math.cos(math.radians(yaw_deg)), math.sin(math.radians(yaw_deg))
    px, py, pz = pivot
    for part in parts:
        out = []
        for x, y, z in part["verts"]:
            x, y, z = x - px, y - py, z - pz
            x, z = x * cr + z * sr, -x * sr + z * cr
            y, z = y * cp - z * sp, y * sp + z * cp
            x, y = x * cy - y * sy, x * sy + y * cy
            out.append((x + px + shift[0], y + py + shift[1], max(0.0, z + pz + shift[2])))
        part["verts"] = out
    return parts


def cart_wreck(d):
    """The carter's cart as the Night left it (D-073 §3): the near wheel torn off and lying in
    the litter, the bed down on its bare axle and canted hard over, one shaft snapped, the
    tarpaulin dragged off. Two crates rode it down; two went over the side and split, and what
    was packed in them — pale shards of vein stone, not pine — lies in the open.

    Built from the standing cart's own measures so it is recognisably THAT cart, broken."""
    bed = [_part("bed", "timber", box(-26, 2, 13, 26, 34, 17)),
           _part("rail_l", "timber_light", box(-27, 2, 17, -24, 34, 24)),
           _part("rail_r", "timber_light", box(24, 2, 17, 27, 34, 24)),
           _part("tail", "timber_light", box(-26, 32, 17, 26, 34, 23)),
           # the bare axle stub where the other wheel was
           _part("axle", "timber_light", tube([(-34, 18, 13), (-24, 18, 13)], [1.8, 1.8], 6,
                                             up=(0, 0, 1))),
           _part("shaft_whole", "timber_light", tube([(16, 2, 15), (13, -30, 12)], [1.6, 1.4], 6,
                                                    up=(0, 0, 1))),
           _part("shaft_stub", "timber_light", tube([(-16, 2, 15), (-15, -9, 14)], [1.6, 1.5], 6,
                                                   up=(0, 0, 1))),
           # the two crates that stayed aboard, shifted against the low rail
           _part("crate_a", "wood_pale", box(-23, 16, 17, -5, 31, 31)),
           _part("band_a", "timber", box(-23.4, 15.6, 26, -4.6, 31.4, 28)),
           _part("crate_b", "wood_pale", box(-3, 17, 17, 14, 30, 29)),
           _part("band_b", "timber", box(-3.4, 16.6, 24, 14.4, 30.4, 26))]
    # the wheel that held: still on its axle, taking the whole weight
    bed += _wheel("wheel_on", 30, 18, 13, 13)
    # down on the stub: the bed rolls about the standing wheel's foot until the axle end lands
    parts = _tilt(bed, (30.0, 18.0, 0.0), roll_deg=-21.0, shift=(0.0, 0.0, 0.0))
    # the wheel that came off, flat in the litter, a spoke's length from where it broke
    parts += _wheel("wheel_off", -46, 2, 1.9, 13, axis="z")
    # the snapped half of the shaft, thrown forward
    parts.append(_part("shaft_piece", "timber_light",
                       tube([(-22, -14, 1.4), (-6, -27, 1.4)], [1.5, 1.3], 6, up=(0, 0, 1))))
    # the crate that burst: four staved sides fallen open round its floor, the lid thrown off
    cx, cy = -8.0, -12.0
    parts.append(_part("burst_floor", "timber", box(cx - 9, cy - 7, 0, cx + 9, cy + 7, 1.2)))
    parts.append(_part("burst_back", "wood_pale", box(cx - 9, cy + 6, 0, cx + 9, cy + 8, 11)))
    parts.append(_part("burst_side", "wood_pale", box(cx + 8, cy - 7, 0, cx + 10, cy + 7, 8)))
    parts.append(_part("burst_flap", "wood_pale", box(cx - 21, cy - 6, 0, cx - 9, cy + 6, 1.6)))
    parts.append(_part("burst_lid", "wood_pale", box(cx + 14, cy - 16, 0, cx + 29, cy - 5, 1.8)))
    parts.append(_part("lid_band", "timber", box(cx + 20, cy - 16.4, 1.8, cx + 22.5, cy - 4.6, 2.6)))
    # the crate that went over whole and split along one seam, lying on its side
    side = [_part("split_crate", "wood_pale", box(30, -18, 0, 46, -4, 13)),
            _part("split_band", "timber", box(29.6, -18.4, 8, 46.4, -3.6, 10)),
            _part("split_dark", "door", box(33, -18.6, 2, 43, -17.6, 11))]
    parts += _tilt(side, (38.0, -11.0, 0.0), yaw_deg=24.0)
    # what was in them: raw shards of vein stone, a spill of them from the burst crate
    shards = ((cx - 2, cy - 1, 3.4, 5.6), (cx + 3, cy + 2, 2.8, 4.4), (cx - 5, cy + 3, 2.4, 3.6),
              (cx + 1, cy - 12, 2.6, 3.8), (cx - 13, cy - 11, 2.2, 3.0), (cx + 8, cy - 15, 2.0, 2.8),
              (34, -22, 2.6, 3.6), (27, -25, 2.0, 2.6))
    for i, (x, y, r, h) in enumerate(shards):
        m = Mesh()
        ring = [(x + r * math.cos(math.tau * j / 5 + i), y + r * 0.8 * math.sin(math.tau * j / 5 + i),
                 0.0) for j in range(5)]
        tip = [(x + 0.35 * r * math.cos(math.tau * j / 5 + i) + 0.6,
                y + 0.3 * r * math.sin(math.tau * j / 5 + i), h) for j in range(5)]
        m.add_ring_loft([ring, tip], cap_start=True, cap_end=True)
        parts.append(_part("shard%d" % i, "vein_stone", m))
    # the tarpaulin, pulled off and lying where it was dropped, its rope trailing
    tarp = sphere((-34, 40, 2.0), (16, 8, 3.0), 12, 6)
    tarp.verts = [(x + (_h(int(x * 2), int(y * 2), 31) - 0.5) * 3.0,
                   y + (_h(int(y * 2), int(x * 2), 32) - 0.5) * 2.0,
                   max(0.0, z + (_h(int(x), int(y), 33) - 0.5) * 2.4)) for x, y, z in tarp.verts]
    parts.append(_part("tarp", "plaster", tarp))
    parts.append(_part("rope", "timber", tube([(-20, 44, 0.6), (-4, 40, 0.6), (10, 44, 0.6)],
                                              [0.8, 0.8, 0.8], 5, up=(0, 0, 1))))
    return _tilt(parts, (0.0, 18.0, 0.0), yaw_deg=CART_YAW_DEG, shift=(0.0, WRECK_BACK, 0.0))


def survey_shaft(d):
    """The Survey Shaft, Hầm Khảo Mạch (D-073 §1): a surveyor's adit driven into an outcrop of
    the north-east rocks, where the vein was sounded. A squared timber frame holds a plank door
    BOARDED shut with two crossed battens; a seal strip is pasted across the join and pinned
    with a knob of cinnabar wax. A worn stone sill; moss on the crown; and beside the mouth the
    last stake of the survey line, cut square and capped — stake four.

    The ORIGIN is the centre of the sill's front edge: the door is what a person walks up to."""
    rock = sphere((0, 26, 20), (46, 26, 30), 16, 10)
    rock.verts = [(x + (_h(int(x), int(z), 41) - 0.5) * 7,
                   max(3.0, y + (_h(int(y), int(x), 42) - 0.5) * 6),
                   max(0.0, z + (_h(int(z), int(y), 43) - 0.5) * 7)) for x, y, z in rock.verts]
    shoulder = sphere((-34, 20, 10), (20, 16, 15), 12, 8)
    shoulder.verts = [(x + (_h(int(x), int(z), 44) - 0.5) * 5,
                       max(2.0, y + (_h(int(y), int(x), 45) - 0.5) * 4),
                       max(0.0, z + (_h(int(z), int(y), 46) - 0.5) * 5))
                      for x, y, z in shoulder.verts]
    spur = sphere((36, 18, 8), (17, 14, 12), 12, 8)
    spur.verts = [(x + (_h(int(x), int(z), 47) - 0.5) * 5,
                   max(2.0, y + (_h(int(y), int(x), 48) - 0.5) * 4),
                   max(0.0, z + (_h(int(z), int(y), 49) - 0.5) * 5)) for x, y, z in spur.verts]
    parts = [_part("rock", "stone", rock), _part("shoulder", "stone", shoulder),
             _part("spur", "stone_light", spur),
             _part("moss", "moss", sphere((4, 30, 47), (26, 15, 4), 10, 6), smooth=True),
             _part("moss_low", "moss", sphere((-36, 20, 23), (11, 8, 2.6), 8, 5), smooth=True),
             _part("sill", "stone_light", box(-17, 0, 0, 17, 6, 3)),
             # the dark of the adit behind the door (seen at the gaps and above the lintel)
             _part("mouth", "door", box(-13, 2.6, 3, 13, 5, 37)),
             _part("post_l", "timber", box(-16, 1, 3, -12, 5, 40)),
             _part("post_r", "timber", box(12, 1, 3, 16, 5, 40)),
             _part("lintel", "timber", box(-18, 0.5, 38, 18, 5.5, 43)),
             _part("door", "timber_light", box(-12, 1.6, 3, 12, 3.2, 38))]
    for i, x in enumerate((-6.0, 0.0, 6.0)):                     # the planks' joins
        parts.append(_part("join%d" % i, "timber", box(x - 0.5, 1.2, 3, x + 0.5, 2.0, 38)))
    for i, (z0, z1) in enumerate(((10.0, 30.0), (30.0, 10.0))):  # two battens, crossed
        m = Mesh()
        m.verts = [(-13, 0.4, z0 - 1.8), (13, 0.4, z1 - 1.8), (13, 0.4, z1 + 1.8),
                   (-13, 0.4, z0 + 1.8), (-13, 1.6, z0 - 1.8), (13, 1.6, z1 - 1.8),
                   (13, 1.6, z1 + 1.8), (-13, 1.6, z0 + 1.8)]
        m.faces = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3),
                   (3, 7, 4, 0)]
        parts.append(_part("batten%d" % i, "wood_pale", m))
    parts.append(_part("seal", "paper", box(-2.6, 0.0, 11, 2.6, 0.5, 29)))
    parts.append(_part("wax", "lacquer_red", sphere((0, -0.2, 20), (2.6, 1.2, 2.6), 8, 6)))
    # stake four of the survey line: squared, capped, still standing
    parts.append(_part("stake", "timber_light", box(25, -4, 0, 28, -1, 20)))
    parts.append(_part("stake_cap", "gilt", box(24.4, -4.6, 20, 28.6, -0.4, 22)))
    return parts


def pine(d):
    """A frontier pine: a straight trunk under stacked, ragged tiers of needles — the forest's
    vertical, so Rừng Vỡ Mạch reads as a FOREST and not a park of round trees."""
    seed = int(d.get("seed", 1))
    s = d.get("scale", 1.0)
    parts = [_part("trunk", "bark", tube([(0, 0, 0), (0, 1, 60 * s)], [5 * s, 2.5 * s], 8,
                                         up=(0, -1, 0)), smooth=True)]
    tiers = [(18, 34, 30), (38, 28, 26), (56, 21, 22), (72, 14, 18), (86, 8, 14)]
    for i, (z, r, h) in enumerate(tiers):
        m = Mesh()
        rings = []
        for k, (zz, rr) in enumerate(((z * s, r * s), (z * s + h * s * 0.45, r * s * 0.7),
                                      ((z + h) * s, 0.8 * s))):
            ring = []
            for j in range(20):
                a = math.tau * j / 20
                jag = 1.0 + (0.22 if j % 2 else -0.08) * (1.0 if k == 0 else 0.5)
                jag += (_h(i, j, seed) - 0.5) * 0.2
                ring.append((rr * jag * math.cos(a), rr * jag * math.sin(a) * 0.92, zz))
            rings.append(ring)
        m.add_ring_loft(rings, cap_start=True, cap_end=True)
        parts.append(_part("tier%d" % i, "needles", m))
    return parts


def boulder(d):
    """A weathered boulder with moss on its crown: flat-shaded facets so the key light chips it
    into planes."""
    seed = int(d.get("seed", 1))
    s = d.get("scale", 1.0)
    m = sphere((0, 14 * s, 15 * s), (26 * s, 18 * s, 17 * s), 12, 8)
    m.verts = [(x + (_h(int(x), int(z), seed) - 0.5) * 6 * s,
                y + (_h(int(y), int(x), seed) - 0.5) * 5 * s,
                max(0.0, z + (_h(int(z), int(y), seed) - 0.5) * 5 * s)) for x, y, z in m.verts]
    moss = sphere((-4 * s, 16 * s, 29 * s), (17 * s, 12 * s, 4 * s), 10, 6)
    return [_part("rock", "stone", m), _part("moss", "moss", moss, smooth=True)]


def stele(d):
    """The Lạc Hà stele (a knowledge source): a weathered tablet on a plinth, its face carved in
    columns of text under a worn gilt heading, moss creeping up the base."""
    parts = [_part("plinth", "stone", box(-16, 0, 0, 16, 12, 8)),
             _part("tablet", "stone_light", box(-11, 3, 8, 11, 8, 52)),
             _part("cap", "stone", sphere((0, 5.5, 52), (12.5, 3.6, 5.5), 12, 6))]
    for i, (x, top) in enumerate(((-6.5, 44), (-3.2, 40), (0.0, 44), (3.2, 36), (6.5, 42))):
        parts.append(_part("text%d" % i, "carve", box(x - 0.9, 2.4, 14, x + 0.9, 3.2, top)))
    parts.append(_part("heading", "gilt", box(-6, 2.2, 46, 6, 3.2, 50)))
    parts.append(_part("moss", "moss", sphere((-9, 1, 6), (9, 3, 3), 10, 6), smooth=True))
    return parts


def spirit_spring(d):
    """Lạc Hà spring (a cultivation site): a still pool welling with qi inside a ring of
    fieldstones. The ORIGIN is the pool's centre — the site itself, not a front edge."""
    parts = [_part("pool", "spring", cylinder(0, 0, 0, 1.4, 19, 24)),
             _part("bed", "stone", cylinder(0, 0, -1.5, 0.2, 21, 24))]
    for i in range(11):
        a = math.tau * i / 11 + 0.2
        r = 22.0 + (_h(i, 3, 17) - 0.5) * 3
        m = sphere((r * math.cos(a), r * math.sin(a) * 0.95, 2.5),
                   (5.2 + _h(i, 1, 17) * 2, 4.2, 3.6 + _h(i, 2, 17) * 2), 8, 6)
        m.verts = [(x, y, max(0.0, z)) for x, y, z in m.verts]
        parts.append(_part("stone%d" % i, "stone" if i % 3 else "stone_light", m))
    parts.append(_part("well_light", "qi", sphere((0, 2, 1.6), (6, 4, 0.4), 12, 6), smooth=True))
    return parts


def training_post(d):
    """The mộc nhân: a pale pine training figure (light wood reads against the yard's earth, and
    its broken state reads against its whole one) — crossed feet, a post, a head, two arms and a
    third striking arm, a cinnabar target ring on its chest."""
    parts = [_part("foot_a", "timber_light", box(-14, -3, 0, 14, 3, 5)),
             _part("foot_b", "timber_light", box(-3, -10, 0, 3, 16, 5)),
             _part("post", "wood_pale", cylinder(0, 3, 0, 52, 4.2, 12)),
             _part("head", "wood_pale", sphere((0, 3, 57), (6, 5.5, 6.5), 12, 8), smooth=True)]
    for i, (path, r) in enumerate(((((-3, 3, 40), (-14, 2, 43), (-19, 0, 41)), 1.8),
                                   (((3, 3, 40), (14, 2, 43), (19, 0, 41)), 1.8),
                                   (((0, 0, 28), (0, -10, 27), (0, -14, 24)), 1.6))):
        parts.append(_part("arm%d" % i, "wood_pale", tube(list(path), [r, r * 0.9, r * 0.8], 8,
                                                        up=(0, 0, 1)), smooth=True))
    ring = tube([(0, -1.4, 36), (0, -2.0, 36)], [6.2, 6.2], 16, up=(0, 0, 1))
    parts.append(_part("target", "lacquer_red", ring))
    parts.append(_part("target_core", "paper", tube([(0, -2.0, 36), (0, -2.4, 36)], [3.2, 3.2],
                                                     12, up=(0, 0, 1))))
    # a mộc nhân stands about a person's height, never taller than the one striking it
    k = d.get("scale", 0.75)
    for p in parts:
        p["verts"] = [(x * k, y * k, z * k) for x, y, z in p["verts"]]
    return parts


def stone_lantern(d):
    """A stone garden lantern (đèn đá): a plinth and shaft of fieldstone, a firebox whose warm
    paper panes glow between stone posts, a pyramid cap and a jewel, moss on the cap. The pair
    flanking the spring court is the village's warm accent on cool stone — the reference's
    lantern principle, in the DNA's own stone/paper ramps."""
    seed = int(d.get("seed", 1))
    parts = [_part("plinth", "stone", box(-12, -4, 0, 12, 12, 6)),
             _part("plinth_cap", "stone_light", box(-10, -3, 6, 10, 11, 8)),
             _part("shaft", "stone", cylinder(0, 4, 8, 30, 4.2, 10)),
             _part("collar", "stone_light", box(-6, -1, 28, 6, 9, 31)),
             _part("fire_floor", "stone", box(-9, -4, 31, 9, 12, 34))]
    for sx in (-7.5, 7.5):
        for sy in (-2.5, 10.5):
            parts.append(_part("post_%g_%g" % (sx, sy), "stone_light",
                               box(sx - 1.5, sy - 1.5, 34, sx + 1.5, sy + 1.5, 45)))
    # the warm panes, recessed a hair behind the posts' faces (never coplanar with them)
    parts.append(_part("panes", "paper", box(-6, -0.5, 34, 6, 9, 45)))
    parts.append(_part("fire_roof", "stone", box(-10, -5, 45, 10, 13, 48)))
    parts.append(_part("cap", "stone", _pyramid(-13, -7, 48, 13, 15, 59)))
    parts.append(_part("jewel", "stone_light", sphere((0, 4, 60), (2.6, 2.6, 2.8), 8, 6)))
    moss = sphere((-5, 6, 54), (6, 4, 1.8), 8, 5)
    moss.verts = [(x + (_h(int(x), int(z), seed) - 0.5) * 2.0,
                   y + (_h(int(y), int(x), seed) - 0.5) * 2.0,
                   z) for x, y, z in moss.verts]
    parts.append(_part("moss", "moss", moss, smooth=True))
    return parts


def rock_cluster(d):
    """A cluster of living rock: one solid outcrop lump (the body's core sits under it) with a
    top stone and a side knob, moss on the crowns. One mass, never scattered singles."""
    seed = int(d.get("seed", 1))
    parts = [_part("outcrop", "stone", _lump(seed, 0, 12, 8, 26, 16, 12)),
             _part("top", "stone_light", _lump(seed + 1, -4, 14, 22, 14, 11, 11)),
             _part("knob", "stone", _lump(seed + 2, 20, 8, 6, 9, 8, 7)),
             _part("moss_top", "moss", sphere((-4, 15, 32), (9, 7, 2.6), 10, 6), smooth=True),
             _part("moss_low", "moss", sphere((14, 12, 18), (8, 6, 2.2), 8, 5), smooth=True)]
    return parts


def grove(d):
    """A vegetation cluster: a young broadleaf rising from a solid mound of undergrowth, three
    bush crowns breaking its silhouette, a sapling and a mossy stone at its foot. Planted OVER
    the map's lush regions, it reads as one mass — never one tree to a lawn."""
    seed = int(d.get("seed", 1))
    parts = []
    mound = sphere((0, 8, 4), (26, 14, 7), 14, 10)
    mound.verts = [(x + (_h(int(x), int(z), seed) - 0.5) * 4.0,
                    y + (_h(int(y), int(x), seed) - 0.5) * 3.0,
                    max(0.0, z + (_h(int(z), int(y), seed) - 0.5) * 3.0))
                   for x, y, z in mound.verts]
    parts.append(_part("mound", "moss", mound, smooth=True))
    for i, (cx, cy, r) in enumerate(((-13, 8, 10), (2, 12, 12), (15, 7, 9))):
        b = sphere((cx, cy, 10), (r, r * 0.85, r * 0.8), 10, 8)
        b.verts = [(x + (_h(int(x * 2), int(z * 2), seed + 10 + i) - 0.5) * 4.0,
                    y + (_h(int(y * 2), int(x * 2), seed + 10 + i) - 0.5) * 3.0,
                    max(2.0, z + (_h(int(z * 2), int(y * 2), seed + 10 + i) - 0.5) * 4.0))
                   for x, y, z in b.verts]
        parts.append(_part("bush%d" % i, "leaves", b, smooth=True))
    for p in broadleaf_tree({"seed": seed + 20, "scale": 0.5}):
        p["verts"] = [(x - 2, y + 10, z + 4) for x, y, z in p["verts"]]
        p["name"] = "young_" + p["name"]
        parts.append(p)
    parts.append(_part("sapling", "bark", tube([(18, 2, 0), (19, 3, 16)], [1.1, 0.7], 6,
                                                up=(0, 0, 1)), smooth=True))
    parts.append(_part("sapling_crown", "leaves", sphere((19, 3, 19), (5, 4.5, 4.5), 8, 6),
                       smooth=True))
    parts.append(_part("foot_stone", "stone", sphere((-18, 4, 2), (5, 4, 3), 8, 6)))
    return parts


def water_edge(d):
    """A water-edge detail: flat stones laid at the waterline, a mossy hummock behind them with
    a clump of reeds and two cattail spikes. For the stream's bank and the spring's overflow."""
    seed = int(d.get("seed", 1))
    parts = []
    for i, (cx, cy, r) in enumerate(((-11, 2, 8), (0, 5, 9), (11, 2, 7))):
        parts.append(_part("stone%d" % i, "stone", cylinder(cx, cy, 0, 3.2, r, 12)))
        parts.append(_part("stone_top%d" % i, "stone_light",
                           cylinder(cx, cy, 3.2, 4.2, r * 0.92, 12)))
    h = sphere((2, 12, 1.5), (13, 7, 3), 10, 8)
    h.verts = [(x + (_h(int(x), int(z), seed) - 0.5) * 2.0,
                y + (_h(int(y), int(x), seed) - 0.5) * 2.0,
                max(0.0, z)) for x, y, z in h.verts]
    parts.append(_part("hummock", "moss", h, smooth=True))
    for i, (cx, cy, hgt, lean) in enumerate(((-6, 12, 26, -0.08), (-2, 14, 30, 0.05),
                                             (2, 13, 24, 0.12), (6, 11, 28, -0.05),
                                             (10, 13, 22, 0.10))):
        parts.append(_part("reed%d" % i, "leaves",
                           tube([(cx, cy, 2), (cx + lean * hgt, cy + 2, 2 + hgt)],
                                [1.0, 0.5], 5, up=(0, 0, 1)), smooth=True))
    for i, (cx, cy, hgt) in enumerate(((-3, 13, 32), (7, 12, 26))):
        parts.append(_part("spike%d" % i, "timber_light",
                           tube([(cx, cy, 2), (cx, cy + 1, hgt)], [0.8, 0.8], 5, up=(0, 0, 1))))
        parts.append(_part("cattail%d" % i, "timber", cylinder(cx, cy + 1, hgt, hgt + 6, 1.6, 6)))
    return parts


BUILDERS = {
    "stele": stele,
    "spirit_spring": spirit_spring,
    "training_post": training_post,
    "pine": pine,
    "boulder": boulder,
    "dwelling": dwelling,
    "outpost_hall": outpost_hall,
    "broadleaf_tree": broadleaf_tree,
    "fence": fence,
    "well": well,
    "weapon_rack": weapon_rack,
    "cart": cart,
    "cart_wreck": cart_wreck,
    "survey_shaft": survey_shaft,
    "stone_lantern": stone_lantern,
    "rock_cluster": rock_cluster,
    "grove": grove,
    "water_edge": water_edge,
}


def build(prop_spec):
    return BUILDERS[prop_spec["kind"]](prop_spec.get("params", {}))
