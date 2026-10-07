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
}


def build(prop_spec):
    return BUILDERS[prop_spec["kind"]](prop_spec.get("params", {}))
