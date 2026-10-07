"""The Aetheria Visual DNA, loaded: role names -> colours, plus the colour maths every producer
shares. System-Python side only (PyYAML); Blender never parses YAML — it receives a RESOLVED
spec (`build.py resolve`) so there is one parser and one meaning for every rule.
"""
import functools
import os

import yaml

STYLE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "aetheria_style.yaml")


@functools.lru_cache(maxsize=1)
def load(path=STYLE_PATH):
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def hex_rgb(value):
    """'#rrggbb' -> (r, g, b) ints."""
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def role(name, style=None):
    """A palette ROLE (e.g. 'gold') -> (r, g, b). A producer asks for a role, never a hex."""
    style = style or load()
    entry = style["palette"].get(name)
    if entry is None:
        raise KeyError("unknown palette role '%s' (aetheria_style.yaml §1)" % name)
    return hex_rgb(entry["hex"])


def resolve_colour(value, style=None):
    """A design colour is either a palette role name or a '#rrggbb' literal."""
    if isinstance(value, str) and value.startswith("#"):
        return hex_rgb(value)
    if isinstance(value, (list, tuple)):
        return tuple(int(c) for c in value[:3])
    return role(value, style)


# --- colour maths ------------------------------------------------------------------------------

def srgb_to_linear(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(v):
    v = max(0.0, min(1.0, v))
    s = v * 12.92 if v <= 0.0031308 else 1.055 * (v ** (1 / 2.4)) - 0.055
    return int(round(s * 255))


def luminance(rgb):
    """Relative luminance (WCAG), 0..1."""
    r, g, b = (srgb_to_linear(c) for c in rgb[:3])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast_ratio(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def to_lab(rgb):
    """sRGB -> CIE L*a*b* (D65): the space palette matching is done in, so 'nearest colour'
    means nearest to the eye, not nearest in RGB."""
    r, g, b = (srgb_to_linear(c) for c in rgb[:3])
    x = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883

    def f(t):
        return t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(x), f(y), f(z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def lab_distance(a, b):
    la, lb = to_lab(a), to_lab(b)
    return ((la[0] - lb[0]) ** 2 + (la[1] - lb[1]) ** 2 + (la[2] - lb[2]) ** 2) ** 0.5


def hsv(rgb):
    """(hue degrees, saturation 0..1, value 0..1)."""
    r, g, b = (c / 255.0 for c in rgb[:3])
    mx, mn = max(r, g, b), min(r, g, b)
    d = mx - mn
    if d == 0:
        h = 0.0
    elif mx == r:
        h = (60 * ((g - b) / d)) % 360
    elif mx == g:
        h = 60 * ((b - r) / d) + 120
    else:
        h = 60 * ((r - g) / d) + 240
    return h, (0.0 if mx == 0 else d / mx), mx


def shade(rgb, factor):
    return tuple(max(0, min(255, int(round(c * factor)))) for c in rgb[:3])


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))
