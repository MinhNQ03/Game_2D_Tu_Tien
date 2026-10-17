"""Grade the Origin illustrations into the shipped painted-tier files (experience upgrade).

    python3 tools/aetheria_art_pipeline/build.py origins

Reads `work/story_art/<origin>_raw.png` (rendered by `blender/build_story_art.py`) and writes
`assets/ui/aetheria/origins/<origin>.webp`. Deterministic: the same raw render gives the same
bytes (fixed seed for the grain, fixed encoder settings).

THE GRADE, and why each step exists:
  1. lift + curve   the renders are low key on purpose (a memory at night); on a monitor the
                    shadows must still separate, so the toe is lifted and the mids opened.
  2. bloom          a practical light (the lamp, the kiln, the embers, the split stone) is the
                    focal point of each picture; a glow says "light" where a flat white disc
                    reads as a hole.
  3. split tone     cold ink in the shadows, the Origin's warm in the highlights: the five
                    pictures are one family, each with its own temperature.
  4. vignette       the eye stays on the subject; the card's frame and text sit on the dark edge.
  5. grain          a faint paper tooth so the pictures read as painted, not rendered.
The painted tier is LINEAR-filtered and may be stretched (`06-art-assets.md`, D-044); it is
never drawn under the pixel-art rules.
"""
import os
import random

from PIL import Image, ImageChops, ImageEnhance, ImageFilter

ORIGINS = ("origin_ho_tieu", "origin_de_tu_bi_loai", "origin_lang_y", "origin_nghe_nhan",
           "origin_thu_thu")

# per Origin: (lift, highlight warm tint, shadow tint, bloom threshold, bloom strength)
GRADES = {
    "origin_ho_tieu": (0.02, (255, 222, 184), (14, 18, 30), 0.80, 0.45),
    "origin_de_tu_bi_loai": (0.0, (255, 240, 214), (16, 22, 36), 0.88, 0.25),
    "origin_lang_y": (0.035, (255, 206, 156), (10, 14, 28), 0.70, 0.60),
    "origin_nghe_nhan": (0.035, (255, 198, 146), (12, 10, 20), 0.70, 0.60),
    "origin_thu_thu": (0.035, (255, 212, 164), (8, 12, 24), 0.70, 0.60),
}
WEBP_QUALITY = 88
GRAIN = 3


def _curve(lift):
    """Toe lift and a gentle S: shadows open, mids a little brighter, highlights kept."""
    table = []
    for i in range(256):
        x = i / 255.0
        y = lift + (1.0 - lift) * x
        y = y + 0.18 * y * (1.0 - y) * (1.0 - 2.0 * abs(y - 0.5))
        table.append(max(0, min(255, round(y * 255))))
    return table * 3


def _bloom(im, threshold, strength):
    lum = im.convert("L")
    mask = lum.point(lambda v: 255 if v >= threshold * 255 else int(v * 0.15))
    bright = ImageChops.multiply(im, Image.merge("RGB", (mask, mask, mask)))
    glow = bright.filter(ImageFilter.GaussianBlur(10))
    wide = bright.filter(ImageFilter.GaussianBlur(36))
    glow = ImageChops.add(glow, wide)
    glow = ImageEnhance.Brightness(glow).enhance(strength)
    return ImageChops.screen(im, glow)


def _split_tone(im, warm, cold):
    lum = im.convert("L")
    warm_layer = Image.new("RGB", im.size, warm)
    cold_layer = Image.new("RGB", im.size, cold)
    hi = ImageChops.multiply(im, warm_layer)
    lo = ImageChops.screen(im, cold_layer)
    toned = Image.composite(hi, lo, lum)
    return Image.blend(im, toned, 0.18)


def _vignette(size, strength=0.45):
    w, h = size
    small = Image.new("L", (64, 36))
    px = small.load()
    for y in range(36):
        for x in range(64):
            dx, dy = (x - 31.5) / 32.0, (y - 17.5) / 18.0
            d = min(1.0, (dx * dx + dy * dy) ** 0.5)
            px[x, y] = round(255 * (1.0 - strength * d ** 2.2))
    return small.resize(size, Image.BICUBIC).filter(ImageFilter.GaussianBlur(8))


def _grain(size, seed):
    rng = random.Random(seed)
    w, h = size[0] // 2, size[1] // 2
    data = bytes(128 + rng.randint(-GRAIN, GRAIN) for _ in range(w * h))
    return Image.frombytes("L", (w, h), data).resize(size, Image.BILINEAR)


def grade(raw_path, out_path, origin_id):
    lift, warm, cold, threshold, strength = GRADES[origin_id]
    im = Image.open(raw_path).convert("RGB")
    im = im.point(_curve(lift))
    im = _bloom(im, threshold, strength)
    im = _split_tone(im, warm, cold)
    im = ImageChops.multiply(im, Image.merge("RGB", (_vignette(im.size),) * 3))
    grain = _grain(im.size, sum(map(ord, origin_id)))
    im = ImageChops.add(im, Image.merge("RGB", (grain,) * 3), scale=1.0, offset=-128)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    im.save(out_path, "WEBP", quality=WEBP_QUALITY, method=6)
    return out_path


def build_all(work_dir, root):
    out = []
    for origin_id in ORIGINS:
        raw = os.path.join(work_dir, origin_id + "_raw.png")
        if not os.path.exists(raw):
            raise SystemExit("missing %s: render it first (blender/build_story_art.py)" % raw)
        out.append(grade(raw, os.path.join(root, "assets", "ui", "aetheria", "origins",
                                           origin_id + ".webp"), origin_id))
    return out
