"""Icon geometry (D-062 CP2 icon grammar): every item, equipment and technique icon is a small
3D object or sigil built from the SAME primitives as the canonical cultivator, rendered by the
SAME passes and adapted by the SAME pixelizer — one visual language across sprite, portrait,
icon and slot (aetheria_style.yaml §7).

Units: world units; the icon camera FRAMES each subject (build_icons._frame), so geometry only
needs sound proportions, not a size.
Z is up; the camera looks from -Y down at `ICON_ELEVATION_DEG`. Items are OBJECTS resting on
the ground plane (z = 0, contact-shadowed); techniques are SIGILS standing in the picture
plane, facing the camera.
"""
import math

from humanoid import Mesh, _add, _mul, _norm, _sub, sphere, tube

ICON_UNITS = 16.0
ICON_ELEVATION_DEG = 50.0


def _part(name, material, mesh, smooth=True):
    return {"name": name, "material": material, "verts": mesh.verts, "faces": mesh.faces,
            "smooth": smooth}


def _superellipse_ring(cx, cy, z, rx, ry, n=4.0, seg=32):
    out = []
    for i in range(seg):
        t = math.tau * i / seg - math.pi / 2
        c, s = math.cos(t), math.sin(t)
        x = rx * math.copysign(abs(c) ** (2.0 / n), c)
        y = ry * math.copysign(abs(s) ** (2.0 / n), s)
        out.append((cx + x, cy + y, z))
    return out


def rounded_slab(cx, cy, z0, z1, rx, ry, bevel=0.35, n=5.0, yaw=0.0):
    """A soft-cornered slab (a book, a folded robe, a dish): superellipse rings with a bevel
    at top and bottom, capped."""
    rings = []
    for z, k in ((z0, 1.0 - bevel / max(rx, ry)), (z0 + bevel, 1.0), (z1 - bevel, 1.0),
                 (z1, 1.0 - bevel / max(rx, ry))):
        rings.append(_superellipse_ring(0, 0, z, rx * k, ry * k, n))
    m = Mesh()
    m.add_ring_loft(rings, cap_start=True, cap_end=True)
    c, s = math.cos(yaw), math.sin(yaw)
    m.verts = [(cx + x * c - y * s, cy + x * s + y * c, zz) for x, y, zz in m.verts]
    return m


def _cam_basis():
    el = math.radians(ICON_ELEVATION_DEG)
    right = (1.0, 0.0, 0.0)
    up = (0.0, math.sin(el), math.cos(el))
    toward = (0.0, -math.cos(el), math.sin(el))     # from the subject toward the camera
    return right, up, toward


def _picture(u, v, depth=0.0, lift=6.0):
    """A point in the picture plane (u right, v up, in units), `lift` above the ground."""
    right, up, toward = _cam_basis()
    return _add(_add(_add((0.0, 0.0, lift), _mul(right, u)), _mul(up, v)), _mul(toward, depth))


# --- items -------------------------------------------------------------------------------------

def pill_dish(d):
    """Bổ Huyết Đan: two cinnabar pills on a small celadon dish."""
    parts = [_part("dish", "porcelain", rounded_slab(0, 0.5, 0.0, 1.0, 5.4, 4.0, 0.4, 2.0))]
    parts.append(_part("dish_well", "porcelain", rounded_slab(0, 0.5, 1.0, 1.25, 4.2, 3.0,
                                                              0.12, 2.0)))
    parts.append(_part("pill", "pill", sphere((-0.6, 0.6, 3.0), (2.3, 2.3, 2.1), 18, 14)))
    parts.append(_part("pill2", "pill", sphere((2.6, -0.8, 2.2), (1.4, 1.4, 1.3), 14, 10)))
    return parts


def spirit_stone(d):
    """Linh thạch: a faceted crystal and a smaller shard leaning on it (flat-shaded facets)."""
    big = sphere((0.0, 0.8, 4.6), (2.6, 2.2, 4.6), 6, 4)
    small = sphere((3.0, -0.6, 2.0), (1.3, 1.1, 2.0), 6, 4)
    small.verts = [(x + (z - 2.0) * 0.25, y, z) for x, y, z in small.verts]
    return [_part("crystal", "crystal", big, smooth=False),
            _part("shard", "crystal", small, smooth=False)]


def jian(d):
    """Kiếm (a straight double-edged jian) lying on the ground, hilt lower-left, tip upper-
    right: blade, guard, wrapped grip, pommel and a short tassel (a sword family is canon)."""
    dirv = _norm((0.78, 0.62, 0.0))
    side = _norm((-dirv[1], dirv[0], 0.0))
    base = (-5.4, -4.0, 1.0)

    def at(t, s=0.0, z=0.0):
        return _add(_add(_add(base, _mul(dirv, t)), _mul(side, s)), (0.0, 0.0, z))

    blade = tube([at(3.6), at(8.0), at(12.0), at(13.6)], [0.75, 0.68, 0.55, 0.05], 8,
                 up=(0.0, 0.0, 1.0), squash=0.25)
    ridge = tube([at(3.8, 0, 0.18), at(12.4, 0, 0.12)], [0.1, 0.06], 6, up=(0.0, 0.0, 1.0))
    guard = tube([at(3.3, -1.5), at(3.3, 1.5)], [0.42, 0.42], 8, up=(0.0, 0.0, 1.0),
                 squash=0.7)
    grip = tube([at(0.6), at(3.2)], [0.42, 0.42], 8, up=(0.0, 0.0, 1.0))
    pommel = sphere(at(0.3), (0.62, 0.62, 0.55), 10, 8)
    tassel = tube([at(0.1), at(-0.6, -0.9, -0.3), at(-0.9, -2.0, -0.5)], [0.28, 0.24, 0.12], 6,
                  up=(0.0, 0.0, 1.0), squash=0.6)
    return [_part("blade", "steel", blade), _part("ridge", "steel_light", ridge),
            _part("guard", "brass", guard), _part("grip", "wrap", grip),
            _part("pommel", "brass", pommel), _part("tassel", "accent", tassel)]


def folded_robe(d):
    """A folded outer robe: the folded body, the crossed collar (inner white over trim), and a
    sash band across it."""
    parts = [_part("body", "cloth", rounded_slab(0, 0, 0.0, 2.6, 5.6, 4.6, 0.6, 6.0, -0.12))]
    top = 2.62
    parts.append(_part("collar_inner", "inner", tube(
        [(-2.2, 3.8, top), (0.0, 0.6, top), (2.0, 3.6, top)], [0.45, 0.5, 0.45], 6,
        up=(0, 0, 1), squash=0.3)))
    parts.append(_part("collar_trim", "trim", tube(
        [(-3.0, 3.9, top + 0.05), (-0.6, 0.2, top + 0.05)], [0.42, 0.42], 6, up=(0, 0, 1),
        squash=0.3)))
    parts.append(_part("collar_trim2", "trim", tube(
        [(3.0, 3.8, top + 0.05), (0.6, 0.2, top + 0.05)], [0.42, 0.42], 6, up=(0, 0, 1),
        squash=0.3)))
    parts.append(_part("sash", "sash", tube(
        [(-5.5, -1.6, top), (0.0, -1.9, top + 0.1), (5.5, -1.4, top)], [0.8, 0.85, 0.8], 8,
        up=(0, 0, 1), squash=0.25)))
    return parts


def manual(d):
    """A thread-bound manual (sách khâu chỉ): the book, a paper title slip with the element's
    mark, and the stitches along the spine."""
    yaw = -0.18
    c, s = math.cos(yaw), math.sin(yaw)

    def rot(x, y, z):
        return (x * c - y * s, x * s + y * c, z)

    parts = [_part("book", "cover", rounded_slab(0, 0, 0.0, 2.0, 4.8, 6.0, 0.3, 8.0, yaw))]
    parts.append(_part("pages", "paper", rounded_slab(0.15, 0.15, 0.25, 1.75, 4.75, 5.9, 0.1,
                                                      8.0, yaw)))
    slip = rounded_slab(0, 0, 2.0, 2.15, 1.0, 3.8, 0.05, 8.0, 0.0)
    slip.verts = [_add(rot(x + 1.6, y + 0.6, z), (0, 0, 0)) for x, y, z in slip.verts]
    parts.append(_part("slip", "paper", slip))
    mark = sphere(rot(1.6, 2.4, 2.2), (0.85, 0.85, 0.12), 10, 6)
    parts.append(_part("mark", "accent", mark))
    for i in range(4):
        y = -4.5 + i * 3.0
        st = tube([rot(-4.9, y, 0.2), rot(-4.2, y, 2.1)], [0.16, 0.16], 6, up=(0, 1, 0))
        parts.append(_part("stitch%d" % i, "thread", st))
    return parts


# --- technique sigils ----------------------------------------------------------------------------

def sigil_wind(d):
    """Thanh Phong Chưởng: three crescent gusts swirling about a calm core — wind as a turning
    force, never a blob. Built in the picture plane, facing the camera."""
    parts = []
    for k in range(3):
        a0 = math.radians(90 + k * 120)
        pts, radii = [], []
        for i in range(9):
            t = i / 8.0
            a = a0 + t * math.radians(150)
            r = 2.2 + 3.8 * t
            pts.append(_picture(r * math.cos(a), r * math.sin(a), depth=0.3 * t))
            radii.append(0.25 + 0.75 * math.sin(math.pi * min(1.0, t * 1.1)))
        parts.append(_part("gust%d" % k, "sigil", tube(pts, radii, 8, up=_cam_basis()[2],
                                                         squash=0.35)))
    parts.append(_part("core", "sigil_core", sphere(_picture(0, 0, 0.4), (1.3, 1.3, 1.3),
                                                      12, 10)))
    return parts


def sigil_thunder(d):
    """Lôi Chỉ: a forked bolt struck down from a point — the fork and the pointing tip are the
    technique (lightning from a fingertip), sparks where it lands."""
    main = [(-1.0, 6.4), (1.2, 2.6), (-0.9, 1.4), (1.8, -2.4), (-0.4, -3.2), (0.8, -6.6)]
    pts = [_picture(u, v, 0.0) for u, v in main]
    radii = [0.6, 1.3, 1.2, 1.1, 0.9, 0.3]
    parts = [_part("bolt", "sigil", tube(pts, radii, 8, up=_cam_basis()[2], squash=0.4),
                   smooth=False)]
    fork = [_picture(u, v, 0.1) for u, v in ((1.2, 2.6), (3.6, 1.0), (4.6, -1.6))]
    parts.append(_part("fork", "sigil", tube(fork, [0.85, 0.65, 0.2], 6, up=_cam_basis()[2],
                                             squash=0.4), smooth=False))
    for i, (u, v) in enumerate(((-2.4, -5.6), (2.6, -5.0), (-3.4, 2.8))):
        parts.append(_part("spark%d" % i, "sigil_core", sphere(_picture(u, v, 0.2),
                                                                 (0.45, 0.45, 0.45), 6, 4)))
    return parts


BUILDERS = {
    "pill_dish": pill_dish,
    "spirit_stone": spirit_stone,
    "jian": jian,
    "folded_robe": folded_robe,
    "manual": manual,
    "sigil_wind": sigil_wind,
    "sigil_thunder": sigil_thunder,
}


def build(icon_spec):
    return BUILDERS[icon_spec["kind"]](icon_spec)
