"""Pack rendered VFX frames into the shipped strips and their data (experience upgrade).

    python3 tools/aetheria_art_pipeline/build.py vfx [effect ...]

For every effect of designs/vfx.yaml: `work/vfx/<effect>/frame_NN.png` (Blender's intensity
pass at render_scale x, see blender/build_vfx.py) ->
  assets/fx/<category>/<effect>.png      one horizontal strip, frame width = size[0]
  data/fx/<effect>.tres                  its VfxSequenceData (fps, anchor, blend)

THE ADAPTATION (not resize-and-pixelate): each frame is reduced by an area average to world
pixels; each pixel's ALPHA is thresholded to three levels (empty, a soft edge, solid) and its
INTENSITY is banded onto the effect's ramp, so every opaque pixel is one of the ramp's tones —
exactly as a sprite's pixels are its ramp's (`AETHERIA_ART_PIPELINE.md` §6). Light is drawn
with a white core and the element's hue around it (style `vfx.colour`).

VALIDATION (fails the build): a frame that is empty or fully opaque (an accidental background),
two adjacent frames that are identical (an animation that does not move), the anchor outside
the frame, an opaque pixel that is not a ramp tone, and a frame whose lit area at the game's 2x
zoom would exceed the DNA's `vfx.peak_screen_share_max` of a 1280x720 frame.
"""
import os
import sys

from PIL import Image

PIPE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(PIPE, "pixel"))

import pngout  # noqa: E402

# the alpha the strip keeps: empty, a soft edge, solid
ALPHA_LEVELS = ((0.12, 0), (0.45, 150), (1.01, 255))
# intensity band edges onto a five-tone ramp (dark ... white core)
BANDS = (0.18, 0.38, 0.62, 0.86)
GAME_ZOOM = 2
SCREEN = (1280, 720)
TRES = """[gd_resource type="Resource" script_class="VfxSequenceData" load_steps=3 format=3]

[ext_resource type="Script" path="res://src/data/fx/vfx_sequence_data.gd" id="1_vfx"]
[ext_resource type="Texture2D" path="res://assets/fx/{category}/{effect}.png" id="2_tex"]

[resource]
script = ExtResource("1_vfx")
id = &"{effect}"
texture = ExtResource("2_tex")
frame_size = Vector2i({w}, {h})
anchor = Vector2i({ax}, {ay})
fps = {fps}
additive = {additive}
"""


def _hex(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def adapt_frame(path, size, scale, ramp):
    src = Image.open(path).convert("RGBA")
    w, h = size
    if src.size != (w * scale, h * scale):
        raise SystemExit("%s is %s, expected %s" % (path, src.size, (w * scale, h * scale)))
    small = src.reduce(scale)
    out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    tones = [_hex(c) for c in ramp]
    sp, op = small.load(), out.load()
    for y in range(h):
        for x in range(w):
            r, g, b, a = sp[x, y]
            alpha = a / 255.0
            level = 0
            for edge, value in ALPHA_LEVELS:
                if alpha < edge:
                    level = value
                    break
            if level == 0:
                continue
            # the emission was white at the intensity: un-premultiply by coverage
            intensity = (max(r, g, b) / 255.0) / max(alpha, 1e-3)
            band = sum(1 for e in BANDS if intensity >= e)
            op[x, y] = tones[band] + (level,)
    return out


def validate(effect_id, frames, size, anchor, ramp):
    problems = []
    tones = {_hex(c) for c in ramp}
    w, h = size
    if not (0 <= anchor[0] < w and 0 <= anchor[1] < h):
        problems.append("anchor %s outside the %sx%s frame" % (anchor, w, h))
    limit = 0.12 * SCREEN[0] * SCREEN[1]
    for i, im in enumerate(frames):
        px = list(im.getdata())
        lit = [p for p in px if p[3] > 0]
        if not lit:
            problems.append("frame %d is empty" % i)
        if len(lit) == len(px):
            problems.append("frame %d is fully opaque (a background was rendered)" % i)
        if any(p[:3] not in tones for p in lit):
            problems.append("frame %d has a pixel off the ramp" % i)
        if len(lit) * GAME_ZOOM * GAME_ZOOM > limit:
            problems.append("frame %d lights %d px at 2x, over the 12%% screen share"
                            % (i, len(lit) * 4))
        if i and list(frames[i - 1].getdata()) == px:
            problems.append("frames %d and %d are identical" % (i - 1, i))
    if problems:
        raise SystemExit("[vfx] %s FAILS:\n  %s" % (effect_id, "\n  ".join(problems)))


def pack(spec, root, only=None):
    written = []
    scale = int(spec["render_scale"])
    for effect_id, e in spec["effects"].items():
        if only and effect_id not in only:
            continue
        src_dir = os.path.join(PIPE, "work", "vfx", effect_id)
        frames = [adapt_frame(os.path.join(src_dir, "frame_%02d.png" % i), e["size"], scale,
                              e["ramp"]) for i in range(int(e["frames"]))]
        validate(effect_id, frames, e["size"], e["anchor"], e["ramp"])
        w, h = e["size"]
        strip = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
        for i, im in enumerate(frames):
            strip.paste(im, (i * w, 0))
        out = os.path.join(root, "assets", "fx", e["category"], effect_id + ".png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        pngout.save(strip, out)
        tres = os.path.join(root, "data", "fx", effect_id + ".tres")
        os.makedirs(os.path.dirname(tres), exist_ok=True)
        with open(tres, "w", encoding="utf-8") as f:
            f.write(TRES.format(category=e["category"], effect=effect_id, w=w, h=h,
                                ax=e["anchor"][0], ay=e["anchor"][1],
                                fps="%.1f" % float(e["fps"]),
                                additive="true" if e.get("blend") == "add" else "false"))
        written.append((out, os.path.getsize(out), len(frames)))
    return written
