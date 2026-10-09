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
import json
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


def build_weapon_action(spec, root, work, anim="slash", grip="palm", tip="blade", scale=7):
    """The review board for a WEAPON action: every frame of `anim`, all four facings, magnified,
    with the blade the runtime will draw from the `grip` anchor to the `tip` anchor of that frame
    — white where the anchor depth says it is in front of the body, grey where behind — and the
    tip's path through the action. It shows the body and the weapon as the game will layer them,
    so "do they read as ONE action" is judged on the real data (D-063 A3)."""
    from PIL import ImageDraw
    prefix = spec["outputs"]["sheet_prefix"]
    sheet = Image.open(os.path.join(root, "assets/sprites/characters/%s_%s.png"
                                    % (prefix, anim))).convert("RGBA")
    cw, ch = spec["camera"]["gameplay"]["cell"]
    feet = spec["camera"]["gameplay"]["feet_row"]
    frames = sheet.width // cw
    with open(os.path.join(work, "frames", "anchors.json")) as f:
        anchors = json.load(f)[anim]
    depths = {}
    path = os.path.join(work, "frames", "anchor_depths.json")
    if os.path.exists(path):
        with open(path) as f:
            depths = json.load(f).get(anim, {})
    pad = 24
    tile_w, tile_h = (cw + pad * 2) * scale, (ch + pad * 2) * scale
    board = Image.new("RGBA", (tile_w * frames, tile_h * 4), (52, 58, 52, 255))
    draw = ImageDraw.Draw(board)
    for d in range(4):
        trail = []
        for c in range(frames):
            cell = sheet.crop((c * cw, d * ch, (c + 1) * cw, (d + 1) * ch))
            big = _on(GROUND, cell).resize((cw * scale, ch * scale), Image.NEAREST)
            ox, oy = c * tile_w + pad * scale, d * tile_h + pad * scale
            board.alpha_composite(big, (ox, oy))
            gx, gy = anchors[grip][d][c]
            tx, ty = anchors[tip][d][c]
            front = depths.get(tip, [[1] * frames] * 4)[d][c] >= 0.0
            colour = (240, 244, 250, 255) if front else (130, 136, 146, 255)
            a = (ox + gx * scale, oy + gy * scale)
            b = (ox + tx * scale, oy + ty * scale)
            draw.line([a, b], fill=colour, width=3)
            draw.ellipse([b[0] - 5, b[1] - 5, b[0] + 5, b[1] + 5], outline=(230, 80, 80, 255))
            trail.append(b)
            draw.line([(ox, oy + feet * scale), (ox + cw * scale, oy + feet * scale)],
                      fill=(200, 170, 90, 255), width=1)
            draw.text((c * tile_w + 6, d * tile_h + 6), "%s f%d %s" % (
                ("down", "up", "left", "right")[d], c, "front" if front else "behind"),
                fill=(255, 255, 255, 255))
    out = os.path.join(work, "review_%s.png" % anim)
    board.save(out)
    return out
