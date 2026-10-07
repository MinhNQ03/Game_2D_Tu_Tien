"""The visual-review board for one actor (D-062 §22: GENERATE -> CAPTURE -> INSPECT).

One image a reviewer reads top to bottom:
  1. the presentation turnaround (Blender beauty render, ink hull on) — the 3D master;
  2. the face close-up from the front view and the hand close-ups (strike, rest, seal) — the
     face and hands at a size they can be judged;
  3. the 80px portrait (framed into the HUD medallion) at 1x and 4x;
  4. every animation's frames, all four facings, at 1x and magnified — the gameplay sprite.

It reads only files the pipeline wrote (work/<actor>/ and the committed sheets), so it never
shows anything the game would not.
"""
import os

from PIL import Image

GROUND = (61, 122, 60, 255)
INK_BG = (18, 22, 30, 255)
ANIMS = ("idle", "walk", "attack", "cast", "meditate")


def _on(bg, im):
    out = Image.new("RGBA", im.size, bg)
    out.alpha_composite(im)
    return out


def _turnaround(work):
    shots = [Image.open(os.path.join(work, "present_%d.png" % i)).convert("RGBA")
             for i in range(4)]
    w, h = shots[0].size
    strip = Image.new("RGBA", (w * 4, h), INK_BG)
    for i, im in enumerate(shots):
        strip.alpha_composite(im, (i * w, 0))
    face = _on(INK_BG, shots[0]).crop((w // 2 - 80, 56, w // 2 + 80, 216)).resize(
        (h // 2, h // 2), Image.LANCZOS)
    return strip, face


def build(spec, root, work, scale=4):
    prefix = spec["outputs"]["sheet_prefix"]
    strip, face = _turnaround(work)
    portrait = Image.open(os.path.join(work, "portrait.png")).convert("RGBA")
    sheets = []
    for anim in ANIMS:
        sheet = Image.open(os.path.join(root, "assets/sprites/characters/%s_%s.png"
                                        % (prefix, anim))).convert("RGBA")
        sheets.append(_on(GROUND, sheet).resize((sheet.width * scale, sheet.height * scale),
                                                Image.NEAREST))
    width = max(strip.width, max(s.width for s in sheets))
    head_h = max(face.height, portrait.height * 4)
    height = strip.height + head_h + sum(s.height + 8 for s in sheets) + 16
    board = Image.new("RGBA", (width, height), (30, 30, 30, 255))
    board.alpha_composite(strip, (0, 0))
    y = strip.height + 8
    board.alpha_composite(face, (0, y))
    board.alpha_composite(_on(INK_BG, portrait), (face.width + 16, y))
    big = _on(INK_BG, portrait).resize((portrait.width * 4, portrait.height * 4), Image.NEAREST)
    board.alpha_composite(big, (face.width + 32 + portrait.width, y))
    x = face.width + 48 + portrait.width + big.width
    for name in ("hand_strike", "hand_rest", "hand_seal"):
        path = os.path.join(work, name + ".png")
        if os.path.exists(path):
            shot = _on(INK_BG, Image.open(path).convert("RGBA"))
            shot = shot.resize((head_h, head_h), Image.LANCZOS)
            if x + shot.width <= width:
                board.alpha_composite(shot, (x, y))
            x += shot.width + 8
    y += head_h + 8
    for s in sheets:
        board.alpha_composite(s, (0, y))
        y += s.height + 8
    out = os.path.join(work, "review.png")
    board.save(out)
    return out


def build_icons(icon_spec, root, work, scale=4):
    """The icon review board: each icon's beauty render above its 32px icon in its UI slot
    (element ring for a technique) at 1x and magnified — what the dock and the satchel show."""
    slot_for = {"skill_thanh_phong_chuong": "slot_phong", "skill_loi_chi": "slot_loi"}
    ids = list(icon_spec["icons"])
    cw = 136
    board = Image.new("RGBA", (len(ids) * cw, 128 + 40 * scale + 56), (40, 50, 45, 255))
    for i, icon_id in enumerate(ids):
        beauty = os.path.join(work, icon_id + "_beauty.png")
        if os.path.exists(beauty):
            board.alpha_composite(Image.open(beauty).convert("RGBA").resize((128, 128)),
                                  (i * cw, 0))
        slot = Image.open(os.path.join(root, "assets/ui/aetheria_ink/%s.png"
                                       % slot_for.get(icon_id, "slot"))).convert("RGBA")
        icon = Image.open(os.path.join(root, "assets/sprites/items/%s.png" % icon_id))
        framed = slot.copy()
        framed.alpha_composite(icon.convert("RGBA"), (4, 4))
        board.alpha_composite(framed.resize((40 * scale // 2, 40 * scale // 2), Image.NEAREST),
                              (i * cw + 28, 136))
        board.alpha_composite(framed, (i * cw + 48, 136 + 40 * scale // 2 + 8))
    out = os.path.join(work, "review_icons.png")
    board.save(out)
    return out
