"""The Aetheria cultivator: a POSE-DRIVEN 32x48 top-down figure (D-057B).

WHY POSES, NOT FRAME DELTAS. The D-046 figure was one front-facing drawing nudged by per-frame
offsets. Inspected at 5x it failed in ways no offset can fix: the LEFT/RIGHT facings were a
frontal torso with a turned head (anatomically wrong), the walk had no feet so the whole lower
robe slid sideways like a rocking bell, and the qi orb floated a few pixels off the body — the
"cosmetic effect beside a motionless figure" D-057 forbids. Here every frame is a POSE (where
the weight is, where each foot and each hand is) drawn onto a skeleton for one of three VIEWS,
so a new animation is a list of poses rather than a new drawing routine.

THE VIEWS. FRONT (facing down), BACK (facing up) and SIDE (facing left; RIGHT is the mirror, so
the two profiles can never drift apart). The side view is a real profile: a narrower torso,
one near arm in front of the body, the far arm behind it, hair falling down the back.

NO QI IN THE SPRITE. A cultivator does not carry glowing qi while walking — qi has a source and
a purpose (`docs/XIANXIA_IDENTITY_CONTRACT.md` §5) — and a PHÀM character has none to show. The
hands are drawn; anything qi-coloured is runtime VFX attached to the exported PALM anchor, so
it can follow realm and technique instead of being baked into a texture.
"""
from . import raster

W, H = 32, 48
CX = 16
INK = (18, 18, 26, 255)
SHADOW = (12, 16, 22, 96)   # translucent contact shadow: never outlined (alpha < 255)

FRONT, BACK, SIDE = "front", "back", "side"


# --- poses ---------------------------------------------------------------------------------

def pose(bob=0, lean=0, near=(0, 0, 0), far=(0, 0, 0), lead=(0, 0), rear=(0, 0),
         palm="relaxed", hair=0, twist=0, lateral=0):
    """One frame of body state.

    bob   upper body vertical offset (+ = lower: a crouch or the contact dip of a stride)
    lean  upper body shift ALONG THE FACING (+ = forward), the weight transfer
    near  (forward, side, lift) of the near/left foot; forward is along the facing
    far   the same for the far/right foot
    lead  (forward, up) of the lead hand from its rest position; rear likewise
    palm  "relaxed" | "open" (a striking palm) | "seal" (two-finger sword seal, P15)
    hair  sway of the hair tips (+ = trailing back)
    twist lead shoulder rotated forward by this many pixels (a strike commits the shoulder)
    lateral  upper body shift sideways in the front/back views (+ = screen right): the weight
          settling over the planted foot, which is what a front-on walk reads by
    """
    return {"bob": bob, "lean": lean, "near": near, "far": far, "lead": lead, "rear": rear,
            "palm": palm, "hair": hair, "twist": twist, "lateral": lateral}


IDLE_FRAMES = 6
WALK_FRAMES = 8
ATTACK_FRAMES = 8

# Breathing, in six beats that each CHANGE something (the verifier rejects a held frame): the
# inhale starts in the hands, peaks with the chest and shoulders up a pixel, holds, releases —
# and the hair tips trail the breath and swing back, so the figure never moves as one block.
#                (chest, hands up, hair tips)
_IDLE = ((0, 0, 0), (0, 1, 2), (-1, 1, 2), (-1, 1, 0), (0, 0, 0), (0, 0, -2))


def idle_pose(f):
    chest, hands, hair = _IDLE[f]
    return pose(bob=chest, lead=(0, hands), rear=(0, hands), hair=hair)


# The stride. Phase p = f / 8. A foot is PLANTED for half the cycle and travels backward relative
# to the body (that is what makes it read as pushing the ground rather than sliding over it),
# then swings forward LIFTED for the other half. The far foot runs half a cycle behind. The
# body is lowest at the two contacts and highest at the two passing frames.
_STRIDE = 5
_BOB_WALK = (1, 0, -1, 0, 1, 0, -1, 0)


def _foot(phase):
    """(forward offset, lift) of a foot at stride phase [0, 1)."""
    if phase < 0.5:                       # stance: planted, moving back under the body
        t = phase / 0.5
        return (int(round(_STRIDE - 2 * _STRIDE * t)), 0)
    t = (phase - 0.5) / 0.5               # swing: lifted, moving forward
    lift = 2 if 0.2 < t < 0.8 else 1
    return (int(round(-_STRIDE + 2 * _STRIDE * t)), lift)


def walk_pose(f):
    p = f / float(WALK_FRAMES)
    nf, nl = _foot(p)
    ff, fl = _foot((p + 0.5) % 1.0)
    # Arms swing OPPOSITE their own side's leg: the near hand is back when the near foot is
    # forward. Three pixels each way: two stayed inside the sleeve's own silhouette at 1x, and
    # more reads as marching.
    swing = int(round(-nf * 0.7))
    # The weight rides over whichever foot is planted: near (screen-left) planted -> shift left.
    lateral = -1 if nl == 0 and fl > 0 else (1 if fl == 0 and nl > 0 else 0)
    return pose(bob=_BOB_WALK[f], lean=1, near=(nf, 0, nl), far=(ff, 0, fl),
                lead=(swing, 0), rear=(-swing, 0), hair=1 + (1 if _BOB_WALK[f] < 0 else 0),
                lateral=lateral)


# THE PALM STRIKE ("tay co ra rồi duỗi tay chưởng"), timed to the gameplay lifecycle. The
# authored attack spends 25% in WINDUP, and the hit lands on ENTERING the active window, so the
# full-extension pose is frame 2 — the frame that starts at 25% progress. Frames 0-1 are the
# anticipation (weight goes BACK, the lead hand is drawn to the hip, the knees sink), frame 2
# is the strike with a step in, 3 the follow-through, 4-7 the recovery back to ready.
_ATTACK = (
    # bob, lean, near foot,   far foot,   lead hand,  rear hand, palm,    hair, twist
    (1, -1, (2, 0, 0), (-2, 0, 0), (-3, 2), (1, 1), "relaxed", 0, 0),
    (2, -2, (2, 0, 1), (-3, 0, 0), (-5, 3), (2, 2), "relaxed", -1, -1),
    (1, 2, (6, 0, 0), (-3, 0, 0), (10, 2), (-2, 1), "open", 2, 2),
    (1, 3, (6, 0, 0), (-2, 0, 0), (12, 2), (-2, 1), "open", 4, 2),
    (1, 2, (5, 0, 0), (-2, 0, 0), (8, 1), (-1, 1), "open", 2, 1),
    (0, 1, (4, 0, 0), (-2, 0, 0), (4, 1), (0, 0), "relaxed", 1, 0),
    (0, 0, (2, 0, 0), (-1, 0, 0), (1, 0), (0, 0), "relaxed", 0, 0),
    (0, 0, (1, 0, 0), (-1, 0, 0), (0, 0), (0, 0), "relaxed", 0, 0),
)


def attack_pose(f):
    b, ln, nr, fr, ld, rr, palm, hair, tw = _ATTACK[f]
    return pose(bob=b, lean=ln, near=nr, far=fr, lead=ld, rear=rr, palm=palm, hair=hair,
                twist=tw)


ANIMATIONS = {
    # name: (frames, loops, pose function)
    "idle": (IDLE_FRAMES, True, idle_pose),
    "walk": (WALK_FRAMES, True, walk_pose),
    "attack": (ATTACK_FRAMES, False, attack_pose),
    # "meditate" is registered at the end of the module, after its seated renderer.
}


# --- drawing -------------------------------------------------------------------------------

def _shoe(px, pal, x, y, length, facing_left):
    """A cloth shoe: a dark sole and a lighter upper, toe pointing along the facing."""
    raster.rect(px, x, y, x + length, y + 2, pal["shoe"])
    if facing_left:
        raster.rect(px, x, y, x + 2, y + 1, raster.shade(pal["shoe"], 1.35))
    else:
        raster.rect(px, x + length - 2, y, x + length, y + 1, raster.shade(pal["shoe"], 1.35))


def _hand(px, pal, x, y, palm):
    """The hand at (x, y). An OPEN palm is a pixel wider and taller so a strike reads at 1x."""
    x, y = int(round(x)), int(round(y))
    if palm == "open":
        raster.rect(px, x - 1, y - 1, x + 2, y + 2, pal["skin"])
        raster.put(px, x + 1, y + 1, raster.shade(pal["skin"], 0.8))
    elif palm == "seal":
        raster.rect(px, x - 1, y, x + 1, y + 2, pal["skin"])
        raster.rect(px, x - 1, y - 2, x, y, pal["skin"])          # two raised fingers
    else:
        raster.rect(px, x - 1, y, x + 1, y + 2, pal["skin"])


def _sleeve(px, pal, sx, sy, hx, hy):
    """A wide hanfu sleeve from the shoulder to the cuff above the hand."""
    raster.limb(px, sx, sy, hx, hy - 2, 3, 4.5, pal["robe"])
    raster.limb(px, sx, sy, hx, hy - 2, 1.2, 2.2, pal["robe_hi"])
    raster.rect(px, int(round(hx)) - 2, int(round(hy)) - 2, int(round(hx)) + 2,
                int(round(hy)) - 1, pal["robe_dk"])                            # cuff


def _contact_shadow(px, spread):
    raster.oval(px, CX, 46.5, 7 + spread, 1.6, SHADOW)


def _skirt_front(px, pal, bob, x, near, far, view):
    """The lower robe from the front or back: an A-line whose hem is pushed out by the feet,
    so a stride opens the hem instead of shoving the whole skirt sideways. The waist follows
    the upper body (`x`); the hem stays planted, so a weight shift tilts the skirt."""
    top = 28 + bob
    l_out = max(0, near[0]) // 2
    r_out = max(0, far[0]) // 2
    hem_l, hem_r = CX - 9 - l_out, CX + 9 + r_out
    raster.polygon(px, [(x - 6, top), (x + 6, top), (hem_r, 44), (hem_l, 44)], pal["robe"])
    raster.polygon(px, [(hem_l + 1, 41), (hem_r - 1, 41), (hem_r, 44), (hem_l, 44)],
                   pal["robe_dk"])
    seam = x - 1 if view == FRONT else x
    raster.line(px, seam, top + 2, seam - (1 if view == FRONT else 0), 43, pal["robe_dk"])
    raster.inner_shadow(px, pal["robe"], raster.shade(pal["robe"], 0.82), 1)


def _torso_front(px, pal, bob, x, twist, view):
    top = 16 + bob
    raster.polygon(px, [(x - 7 - min(0, twist), top), (x + 7, top), (x + 6, 28 + bob),
                        (x - 6, 28 + bob)], pal["robe"])
    raster.rect(px, x - 7, top, x + 7, top + 2, pal["robe_hi"])               # lit shoulders
    # The collar rises behind the jaw. Whatever sits under the chin decides whether the face
    # reads as a face: background was outlined as a dark chinstrap, hair read as a beard (on
    # the brown-haired merchant unmistakably). Robe, in the shadow the head casts, reads as a
    # high collar.
    raster.rect(px, x - 4, top - 5, x + 4, top, pal["robe"])
    raster.rect(px, x - 3, top - 5, x + 3, top - 3, pal["robe_dk"])
    if view == FRONT:
        # The CROSSED COLLAR (giao lĩnh), left over right — the hanfu read, and the honest
        # pixel translation of the references' gold edging. A centre line read as a zipper.
        raster.line(px, x - 3, top, x + 2, top + 9, pal["trim"])
        raster.line(px, x - 2, top, x + 3, top + 9, pal["trim_dk"])
        raster.line(px, x + 3, top, x + 1, top + 3, pal["trim"])
        # Only a sliver of the white inner collar: a white V under a pale face, between two
        # locks of white hair, read as a beard at 1x.
        raster.rect(px, x - 1, top - 1, x + 1, top, pal["inner"])
    raster.rect(px, x - 6, 26 + bob, x + 6, 29 + bob, pal["trim"])            # sash
    raster.rect(px, x - 6, 26 + bob, x + 6, 27 + bob, raster.shade(pal["trim"], 1.2))
    if view == BACK:
        raster.rect(px, x - 2, 26 + bob, x + 2, 29 + bob, raster.shade(pal["trim"], 0.85))
        raster.rect(px, x - 2, 29 + bob, x - 1, 33 + bob, pal["trim"])        # knot tails
        raster.rect(px, x + 1, 29 + bob, x + 2, 32 + bob, pal["trim_dk"])
    raster.inner_shadow(px, pal["robe"], raster.shade(pal["robe"], 0.82), 1)


def _hair_behind(px, pal, bob, x):
    """Long hair falling BEHIND the head. Drawn before the face, it fills the gaps around the
    jaw that would otherwise be outlined as a dark 'beard' inside the figure."""
    t = 2 + bob
    raster.rect(px, x - 5, t + 2, x + 5, t + 9, pal["hair_dk"])


def _head_front(px, pal, bob, x):
    """An oval face that ENDS at the chin: the eyes sit at its middle, the jaw tapers in two
    steps, and the neck is a short, narrow, shadowed column that the collar closes over. A
    long pale face over a wide pale neck read as a beard at 1x (the first D-057B capture)."""
    t = 5 + bob
    raster.rect(px, x - 1, t + 8, x + 1, t + 9, raster.shade(pal["skin"], 0.7))    # neck
    raster.rect(px, x - 4, t, x + 4, t + 6, pal["skin"])
    raster.rect(px, x - 3, t + 6, x + 3, t + 7, pal["skin"])                  # jaw taper
    raster.rect(px, x - 2, t + 7, x + 2, t + 8, raster.shade(pal["skin"], 0.9))   # chin
    raster.rect(px, x - 3, t + 6, x - 3, t + 7, raster.shade(pal["skin"], 0.84))  # cheek


def _hair_front(px, pal, bob, x, sway):
    t = 2 + bob
    raster.rect(px, x - 5, t, x + 5, t + 4, pal["hair"])
    raster.rect(px, x - 5, t, x + 5, t + 2, pal["hair_hi"])
    raster.rect(px, x - 4, t + 4, x + 4, t + 5, pal["hair_dk"])               # fringe shadow
    raster.rect(px, x - 2, t + 3, x + 1, t + 5, pal["hair"])                  # parted fringe
    # Side locks framing the face, falling over the shoulders; the tips drift with `sway`.
    for (x0, side) in ((x - 6, -1), (x + 4, 1)):
        raster.rect(px, x0, t + 2, x0 + 2, t + 15, pal["hair"])
        raster.rect(px, x0 + 1 if side < 0 else x0, t + 4, x0 + 2 if side < 0 else x0 + 1,
                    t + 14, pal["hair_hi"])
        tip = side * (sway // 2)
        raster.rect(px, x0 + tip, t + 15, x0 + 2 + tip, t + 20, pal["hair_dk"])
    raster.rect(px, x - 2, t - 1, x + 2, t + 1, pal["trim"])                  # crown pin


def _hair_back(px, pal, bob, x, sway):
    """The long hair from behind: a mass narrower than the shoulders that TAPERS down the
    back, with a parting and strands. The D-046 version was a full-width white rectangle that
    read as a sheet."""
    t = 2 + bob
    raster.rect(px, x - 5, t, x + 5, t + 13, pal["hair"])
    raster.rect(px, x - 5, t, x + 5, t + 3, pal["hair_hi"])
    tip = sway // 2
    raster.polygon(px, [(x - 4, t + 12), (x + 4, t + 12), (x + 3 + tip, t + 24),
                        (x + tip, t + 28), (x - 3 + tip, t + 24)], pal["hair"])
    raster.line(px, x, t + 2, x + tip, t + 26, pal["hair_dk"])               # the parting
    raster.line(px, x - 3, t + 6, x - 2 + tip, t + 22, pal["hair_hi"])        # strands
    raster.line(px, x + 3, t + 6, x + 2 + tip, t + 22, pal["hair_dk"])
    raster.rect(px, x - 2, t - 1, x + 2, t + 1, pal["trim"])


def _face_front(px, pal, bob, x):
    y = 9 + bob
    raster.put(px, x - 1, y + 3, raster.shade(pal["skin"], 0.8))             # mouth hint
    raster.put(px, x - 3, y, pal["eye"])
    raster.put(px, x + 2, y, pal["eye"])
    raster.put(px, x - 3, y - 1, pal["hair_dk"])                              # brows
    raster.put(px, x + 2, y - 1, pal["hair_dk"])


def _front_back_hand(shoulder_x, bob, fwd, up, view, inward):
    """Where a hand lands in the front/back views for a (forward, up) arm offset.

    Forward is toward the camera in the FRONT view, so a strike brings the palm in across the
    body to CHEST height — at belly height it read as a hand resting on the robe, not a push.
    In the BACK view forward is away from the camera, so the hand rises past the shoulder line
    beside the head. A negative forward is the coil: the hand drawn back to the hip.
    """
    if fwd < 0:
        return (shoulder_x - inward, 29 + bob - up)
    if fwd <= 4:
        return (shoulder_x + inward * (fwd // 3), 30 + bob + (fwd // 2) - up)
    if view == FRONT:
        return (shoulder_x + inward * ((fwd * 6) // 10), 30 + bob - (fwd * 6) // 10 - up)
    return (shoulder_x + inward * (1 + fwd // 4), 30 + bob - (fwd * 16) // 10 - up)


def _render_front_back(pal, p, view):
    px = raster.blank(W, H)
    bob, twist = p["bob"], p["twist"]
    near, far = p["near"], p["far"]
    x = CX + p["lateral"]
    _contact_shadow(px, abs(near[0] - far[0]) // 4)
    # FEET first, so a lifted foot slips under the hem. "Forward" is toward the camera in the
    # front view (lower on screen) and away from it in the back view. A forward foot shows its
    # trouser leg below the hem — the part of the stride a floor-length robe would hide.
    sign = 1 if view == FRONT else -1
    for (foot, base_x) in ((near, CX - 5), (far, CX + 2)):
        drop = sign * ((foot[0] * 3) // 5)
        fy = 44 + drop - foot[2]
        if drop > 0:
            raster.rect(px, base_x + 1, 42, base_x + 3, fy, pal["robe_deep"])
        _shoe(px, pal, base_x + foot[1], fy, 3, False)
    _skirt_front(px, pal, bob, x, near, far, view)
    _torso_front(px, pal, bob, x, twist, view)

    # ARMS. The lead arm is the screen-left one. In the front view "forward" brings the hand
    # down toward the camera and in across the body; in the back view it goes up and in, and is
    # drawn over the hair so a reach away from the camera stays visible.
    lead_x, lead_y = p["lead"]
    rear_x, rear_y = p["rear"]
    l_sx, l_sy = x - 8 + max(0, twist), 18 + bob
    r_sx, r_sy = x + 8, 18 + bob
    l_hx, l_hy = _front_back_hand(x - 8, bob, lead_x, lead_y, view, 1)
    r_hx, r_hy = _front_back_hand(x + 8, bob, rear_x, rear_y, view, -1)
    strike_front = view == FRONT and lead_x > 4
    reaching = view == BACK and lead_x > 4
    if not (strike_front or reaching):
        _sleeve(px, pal, l_sx, l_sy, l_hx, l_hy)
        _hand(px, pal, l_hx, l_hy, p["palm"] if view == FRONT else "relaxed")
    _sleeve(px, pal, r_sx, r_sy, r_hx, r_hy)
    _hand(px, pal, r_hx, r_hy, "relaxed")

    if view == FRONT:
        _hair_behind(px, pal, bob, x)
        _head_front(px, pal, bob, x)
        _hair_front(px, pal, bob, x, p["hair"])
        _face_front(px, pal, bob, x)
        if strike_front:
            # A strike toward the viewer overlaps the body: drawn LAST so the palm sits in
            # front of the robe and reads as coming at the camera.
            _sleeve(px, pal, l_sx, l_sy, l_hx, l_hy)
            _hand(px, pal, l_hx, l_hy, p["palm"])
    else:
        _head_front(px, pal, bob, x)
        _hair_back(px, pal, bob, x, p["hair"])
        if reaching:
            _sleeve(px, pal, l_sx, l_sy, l_hx, l_hy)
            _hand(px, pal, l_hx, l_hy, "relaxed")
    raster.outline(px, INK)
    return px, (l_hx, l_hy), (r_hx, r_hy)


def _render_side(pal, p):
    """Facing LEFT. Forward is -x."""
    px = raster.blank(W, H)
    bob, lean = p["bob"], p["lean"]
    near, far = p["near"], p["far"]
    _contact_shadow(px, abs(near[0] - far[0]) // 3)
    body = CX - lean                       # upper-body centre after the weight shift
    hair_sway = p["hair"]
    t = 2 + bob

    # FAR ARM (behind the body).
    rear_x, rear_y = p["rear"]
    f_sx, f_sy = body + 2, 18 + bob
    f_hx, f_hy = body + 2 - rear_x, 30 + bob - rear_y
    raster.limb(px, f_sx, f_sy, f_hx, f_hy - 2, 3, 4, pal["robe_dk"])
    raster.rect(px, int(f_hx) - 1, int(f_hy), int(f_hx) + 1, int(f_hy) + 2,
                raster.shade(pal["skin"], 0.8))

    # HAIR MASS down the back, behind the body.
    raster.polygon(px, [(body - 1, t + 3), (body + 6, t + 3), (body + 6 + hair_sway, t + 22),
                        (body + 3 + hair_sway, t + 27), (body, t + 16)], pal["hair"])
    raster.line(px, body + 5, t + 6, body + 5 + hair_sway, t + 22, pal["hair_dk"])
    raster.line(px, body + 2, t + 8, body + 3 + hair_sway, t + 24, pal["hair_hi"])

    # The skirt keeps an A-line even with the feet together, and the STRIDE drives it: the
    # leading leg kicks the front of the hem out and, while that foot swings, lifts it; the
    # trailing leg drags the back of the hem. The D-057B capture showed a floor-length robe
    # gliding with its silhouette unchanged — at 1x the hem IS the legs.
    lead_foot, trail_foot = (near, far) if near[0] >= far[0] else (far, near)
    front_x = min(CX - lead_foot[0] - 1, CX - 5) - 1
    back_x = max(CX - trail_foot[0] + 1, CX + 4) + 3
    lift = 1 if lead_foot[2] > 0 else 0
    top = 28 + bob
    raster.polygon(px, [(body - 4, top), (body + 5, top), (back_x + 1, 42), (back_x - 1, 43),
                        (front_x - 1, 43 - lift), (front_x - 2, 42 - lift)], pal["robe"])
    raster.polygon(px, [(front_x - 1, 40 - lift), (back_x, 40), (back_x - 1, 43),
                        (front_x - 1, 43 - lift)], pal["robe_dk"])
    raster.line(px, body - 3, top + 1, front_x, 42 - lift, pal["robe_dk"])  # front panel edge
    # FEET under the hem, AFTER it: a planted shoe shows its sole and upper below the hem, and a
    # swinging one rises over the hem's edge — the step is visible, not implied. The far foot
    # is drawn first and darker. Shoes point left (forward).
    for (foot, shade_k) in ((far, 0.8), (near, 1.0)):
        fx = CX - foot[0] - 2
        fy = 44 - foot[2]
        shoe_pal = dict(pal)
        shoe_pal["shoe"] = raster.shade(pal["shoe"], shade_k)
        _shoe(px, shoe_pal, fx, fy, 4, True)

    # TORSO in profile: chest forward (left), straight back.
    top = 16 + bob
    raster.polygon(px, [(body - 5, top + 1), (body + 4, top), (body + 5, 28 + bob),
                        (body - 4, 28 + bob)], pal["robe"])
    raster.rect(px, body - 4, top, body + 4, top + 2, pal["robe_hi"])
    raster.line(px, body - 4, top + 1, body - 1, top + 7, pal["trim"])     # collar edge
    raster.rect(px, body - 4, 26 + bob, body + 5, 29 + bob, pal["trim"])     # sash
    raster.rect(px, body - 4, 26 + bob, body + 5, 27 + bob, raster.shade(pal["trim"], 1.2))
    raster.inner_shadow(px, pal["robe"], raster.shade(pal["robe"], 0.82), 1)

    _head_profile(px, pal, body, t, eyes_closed=False)

    # NEAR ARM (in front of the body). Forward = -x; an extended arm rises toward shoulder
    # height, so a strike reads as a push at chest level rather than a hand dropped forward.
    lead_x, lead_y = p["lead"]
    n_sx, n_sy = body - 1, 18 + bob
    n_hx = body - 1 - lead_x
    n_hy = 30 + bob - lead_y - (max(0, lead_x - 3) * 7) // 8
    if p["palm"] == "open" and lead_x > 3:
        # THE PALM STRIKE (chưởng) seen side-on: the sleeve runs level to the wrist and the
        # palm stands UPRIGHT at its tip, heel forward, fingers up. Drawn as a hanging hand it
        # read as a limp reach, not a blow (first D-057B capture).
        _sleeve(px, pal, n_sx, n_sy, n_hx + 1, n_hy + 1)
        hx, hy = int(round(n_hx)), int(round(n_hy))
        raster.rect(px, hx - 2, hy - 4, hx, hy, pal["skin"])
        raster.put(px, hx - 1, hy - 1, raster.shade(pal["skin"], 0.8))
        n_hx, n_hy = hx - 1, hy - 2                # the anchor: the centre of the palm
    else:
        _sleeve(px, pal, n_sx, n_sy, n_hx, n_hy)
        _hand(px, pal, n_hx, n_hy, p["palm"])
    raster.outline(px, INK)
    return px, (n_hx, n_hy), (f_hx, f_hy)


def _head_profile(px, pal, body, t, eyes_closed):
    """The head in profile, facing LEFT: hair behind first (fills the nape), then the face."""
    raster.rect(px, body - 1, t + 3, body + 5, t + 14, pal["hair_dk"])
    raster.rect(px, body - 1, t + 11, body + 2, t + 15, raster.shade(pal["skin"], 0.78))  # neck
    raster.rect(px, body - 4, t + 3, body + 3, t + 10, pal["skin"])
    raster.rect(px, body - 3, t + 10, body + 2, t + 12, pal["skin"])
    raster.put(px, body - 5, t + 7, pal["skin"])                             # nose
    raster.rect(px, body - 4, t, body + 4, t + 4, pal["hair"])
    raster.rect(px, body - 4, t, body + 4, t + 2, pal["hair_hi"])
    raster.rect(px, body - 1, t + 3, body + 5, t + 9, pal["hair"])          # over the ear
    raster.rect(px, body - 4, t + 3, body - 1, t + 4, pal["hair_dk"])       # fringe
    raster.rect(px, body - 1, t - 1, body + 3, t + 1, pal["trim"])          # crown pin
    if eyes_closed:
        raster.put(px, body - 3, t + 7, raster.shade(pal["skin"], 0.62))     # lid, lowered
    else:
        raster.put(px, body - 3, t + 7, pal["eye"])
        raster.put(px, body - 3, t + 6, pal["hair_dk"])


# --- MEDITATION (tọa thiền, Phase 12) -----------------------------------------------------
#
# Seated cross-legged, the robe spread into a wide stable base, the hands joined in a seal at
# the dantian, the eyes closed. Frame 0 is the descent (the body still half-risen: a cultivator
# lowers into the seat, he does not teleport into it); frames 1-3 are ONE slow breath, played
# as a loop by the runtime. It is the body's stillness that reads as cultivation — the qi that
# gathers is a runtime effect from the vein, never part of this drawing.

MEDITATE_FRAMES = 4
_SEAT_DROP = 11                        # how far the head sits below its standing height
_MEDITATE = ((5, 0, 1), (0, 0, 0), (0, -1, 1), (0, 0, 2))    # (rise, breath, hair)


def meditate_pose(f):
    rise, breath, hair = _MEDITATE[f]
    p = pose(bob=_SEAT_DROP - rise + breath, hair=hair)
    p["seated"] = rise
    p["breath"] = breath
    return p


def _render_seated(view, pal, p):
    px = raster.blank(W, H)
    rise = p["seated"]
    bob = p["bob"]
    x = CX
    raster.oval(px, CX, 46.5, 11, 1.6, SHADOW)
    # The crossed legs under the robe: a broad base with the knees as two low mounds.
    base_top = 38                      # the folded legs are on the ground in every frame
    if view == SIDE:
        raster.polygon(px, [(CX - 12, 46), (CX + 6, 46), (CX + 7, base_top + 1),
                            (CX - 5, base_top), (CX - 12, 42)], pal["robe"])
        raster.oval(px, CX - 9, 43, 4, 2.6, pal["robe_hi"])                 # the near knee
        raster.rect(px, CX - 12, 45, CX + 6, 46, pal["robe_dk"])
    else:
        raster.polygon(px, [(CX - 12, 46), (CX + 12, 46), (CX + 8, base_top),
                            (CX - 8, base_top)], pal["robe"])
        for kx in (CX - 7, CX + 7):
            raster.oval(px, kx, 43, 5, 2.6, pal["robe_hi"])
        raster.rect(px, CX - 12, 45, CX + 12, 46, pal["robe_dk"])
    if view == SIDE:
        body = CX
        t = 2 + bob
        # Hair down the back, the torso upright, the head; the near arm rests to the lap.
        raster.polygon(px, [(body - 1, t + 3), (body + 6, t + 3), (body + 7, t + 20),
                            (body + 3, t + 24), (body, t + 16)], pal["hair"])
        top = 16 + bob
        raster.polygon(px, [(body - 5, top + 1), (body + 4, top), (body + 5, base_top),
                            (body - 4, base_top)], pal["robe"])
        raster.rect(px, body - 4, top, body + 4, top + 2, pal["robe_hi"])
        raster.line(px, body - 4, top + 1, body - 1, top + 7, pal["trim"])
        raster.rect(px, body - 4, 26 + bob, body + 5, 29 + bob, pal["trim"])
        raster.inner_shadow(px, pal["robe"], raster.shade(pal["robe"], 0.82), 1)
        _head_profile(px, pal, body, t, eyes_closed=True)
        hx, hy = body - 4, 36 - rise
        _sleeve(px, pal, body - 1, 18 + bob, hx, hy)
        _hand(px, pal, hx, hy, "seal")
        raster.outline(px, INK)
        return px, (hx, hy), (body + 1, hy)
    # The lap: the robe from the waist down to the folded legs, so a body still lowering into
    # the seat (frame 0) is one continuous figure rather than a torso floating over its base.
    raster.polygon(px, [(x - 6, 27 + bob), (x + 6, 27 + bob), (x + 8, base_top + 1),
                        (x - 8, base_top + 1)], pal["robe"])
    _torso_front(px, pal, bob, x, 0, view)
    if view == FRONT:
        # Both sleeves come down and in to meet at the dantian; the hands join in a seal there.
        hy = 36 - rise
        _sleeve(px, pal, x - 8, 18 + bob, x - 2, hy)
        _sleeve(px, pal, x + 8, 18 + bob, x + 2, hy)
        _hand(px, pal, x, hy, "seal")
        _hair_behind(px, pal, bob, x)
        _head_front(px, pal, bob, x)
        _hair_front(px, pal, bob, x, p["hair"])
        # Eyes CLOSED: a lowered lid, a pixel wide, where the eye was.
        y = 9 + bob
        lid = raster.shade(pal["skin"], 0.62)
        raster.put(px, x - 3, y, lid)
        raster.put(px, x + 2, y, lid)
        raster.put(px, x - 1, y + 3, raster.shade(pal["skin"], 0.8))
        raster.outline(px, INK)
        return px, (x, hy), (x, hy)
    # BACK: the shoulders and the long hair; the hands are in front of the body, hidden.
    for sx in (x - 8, x + 8):
        _sleeve(px, pal, sx, 18 + bob, sx + (3 if sx < x else -3), 34 - rise)
    _head_front(px, pal, bob, x)
    _hair_back(px, pal, bob, x, p["hair"])
    raster.outline(px, INK)
    return px, (x, 36 - rise), (x, 36 - rise)


def render(view, pal, p):
    """Render one 32x48 frame. Returns (canvas, lead hand, rear hand) in cell pixels."""
    if p.get("seated") is not None:
        return _render_seated(view, pal, p)
    if view == SIDE:
        return _render_side(pal, p)
    return _render_front_back(pal, p, view)


def render_facing(direction, pal, p):
    """One frame for a sheet row: 0 down, 1 up, 2 left, 3 right (the mirror of left)."""
    if direction == 0:
        return render(FRONT, pal, p)
    if direction == 1:
        return render(BACK, pal, p)
    px, lead, rear = render(SIDE, pal, p)
    if direction == 2:
        return px, lead, rear
    return raster.mirror(px), (W - 1 - lead[0], lead[1]), (W - 1 - rear[0], rear[1])


def core_point(direction, p):
    """The dantian — where cultivation gathers qi — for this pose and facing."""
    if p.get("seated") is not None:
        return (CX, 35 - p["seated"])
    shift = 0
    if direction in (0, 1):
        shift = p["lateral"]
    elif direction == 2:
        shift = -p["lean"]
    else:
        shift = p["lean"]
    return (CX + shift, 32 + p["bob"])


# --- palettes ------------------------------------------------------------------------------
#
# The player and the female cultivator come from the MEASURED painted references (D-046). One
# deliberate translation kept from then: the male reference's hair tone is nearly the same VALUE
# as its skin, so it is the hair SHADOW and the lit hair is a cooler silver.

def _derive(pal):
    """Fill the derived tones from the authored ones, so every archetype shades the same way."""
    out = dict(pal)
    out.setdefault("trim_dk", raster.shade(pal["trim"], 0.72))
    out.setdefault("inner", raster.shade(pal["robe_hi"], 1.08))
    out.setdefault("eye", INK)
    out.setdefault("shoe", (52, 46, 56, 255))
    out.setdefault("robe_deep", raster.shade(pal["robe_dk"], 0.55))
    return out


ARCHETYPES = {
    "player_proto": _derive({
        "hair": (230, 232, 242, 255), "hair_hi": (250, 252, 255, 255),
        "hair_dk": (196, 184, 190, 255), "skin": (236, 206, 178, 255),
        "robe_hi": (214, 216, 232, 255), "robe": (176, 182, 212, 255),
        "robe_dk": (132, 142, 180, 255), "trim": (204, 174, 108, 255),
    }),
    "cultivator_f_proto": _derive({
        "hair": (240, 224, 224, 255), "hair_hi": (255, 252, 252, 255),
        "hair_dk": (200, 184, 196, 255), "skin": (240, 212, 192, 255),
        "robe_hi": (192, 192, 234, 255), "robe": (150, 150, 210, 255),
        "robe_dk": (114, 114, 178, 255), "trim": (214, 186, 126, 255),
    }),
    "elder_proto": _derive({
        "hair": (236, 238, 240, 255), "hair_hi": (255, 255, 255, 255),
        "hair_dk": (190, 194, 200, 255), "skin": (222, 192, 166, 255),
        "robe_hi": (180, 186, 188, 255), "robe": (134, 142, 146, 255),
        "robe_dk": (98, 106, 112, 255), "trim": (180, 160, 100, 255),
        "shoe": (44, 40, 38, 255),
    }),
    "merchant_proto": _derive({
        "hair": (86, 64, 50, 255), "hair_hi": (124, 96, 72, 255),
        "hair_dk": (52, 38, 30, 255), "skin": (232, 196, 160, 255),
        "robe_hi": (192, 158, 108, 255), "robe": (156, 122, 78, 255),
        "robe_dk": (120, 92, 58, 255), "trim": (210, 182, 116, 255),
        "shoe": (60, 44, 34, 255),
    }),
}

# The meditation pose function is defined after ANIMATIONS (it reads the seated renderer).
ANIMATIONS["meditate"] = (MEDITATE_FRAMES, False, meditate_pose)
