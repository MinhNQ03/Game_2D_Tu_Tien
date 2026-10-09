"""Vụ Lang, the frontier mist wolf: a POSE-DRIVEN 32x32 quadruped (D-057B).

The D-046/Phase-10 wolf was a grey barrel on four straight sticks: from the front it read as a
jelly with two leaves on it, and its "walk" changed leg LENGTHS rather than moving legs. This one
is built from the parts that make a canine read at 32px — a deep chest, a tucked waist, a long
low head with a snout and upright ears, DIGITIGRADE legs (the hind hock bends backward) and a
bushy tail — and it walks with a four-beat gait in which each leg swings and plants in turn.

The MIST is its identity, not decoration: translucent pale-jade wisps trail off the spine and
the tail tip. They are drawn after the outline, so they read as vapour rather than as fur.
"""
from art_sheet import raster

W, H = 32, 32
INK = (18, 18, 26, 255)
SHADOW = (12, 16, 22, 90)

PAL = {
    "coat": (176, 184, 194, 255),
    "coat_hi": (212, 218, 226, 255),
    "coat_dk": (120, 128, 142, 255),
    "belly": (146, 154, 166, 255),
    "far": (104, 112, 126, 255),
    "nose": (44, 44, 54, 255),
    "maw": (92, 52, 60, 255),
    "fang": (236, 236, 228, 255),
    "eye": (130, 236, 188, 255),
    "mist": (178, 230, 210, 112),
    "mist_dim": (150, 200, 186, 70),
}


def pose(body=0, reach=0, head=0, tail=0, jaw=0, legs=(0.0, 0.0, 0.0, 0.0), lift=(0, 0, 0, 0),
         crouch=0, mist=0):
    """body   vertical offset of the trunk (+ = lower)
    reach  trunk/head shift along the facing (+ = forward) — the lunge
    head   head vertical offset (+ = lower)
    tail   tail tip sway
    jaw    0 closed, 1 open, 2 wide (the bite)
    legs   forward offset of each leg: near-front, far-front, near-hind, far-hind
    lift   how far each paw is off the ground
    crouch how far the hind legs fold (the spring being loaded)
    mist   phase of the drifting mist wisps
    """
    return {"body": body, "reach": reach, "head": head, "tail": tail, "jaw": jaw, "legs": legs,
            "lift": lift, "crouch": crouch, "mist": mist}


IDLE_FRAMES = 6
WALK_FRAMES = 8
ATTACK_FRAMES = 6


def idle_pose(f):
    breath = (0, 0, -1, -1, 0, 0)[f]
    return pose(body=breath, head=breath, tail=(0, 1, 1, 0, -1, -1)[f],
                jaw=1 if f in (2, 3) else 0, mist=f)


# A four-beat walk: the legs fall one after another (near-hind, near-front, far-hind, far-front),
# each planted for 3/4 of the cycle and swung forward, lifted, for the last quarter.
_PHASE = (0.25, 0.75, 0.0, 0.5)


def _leg(p):
    if p < 0.75:
        t = p / 0.75
        return (3.0 - 6.0 * t, 0)
    t = (p - 0.75) / 0.25
    return (-3.0 + 6.0 * t, 2 if 0.25 < t < 0.75 else 1)


def walk_pose(f):
    p = f / float(WALK_FRAMES)
    legs, lift = [], []
    for ph in _PHASE:
        fwd, lf = _leg((p + ph) % 1.0)
        legs.append(fwd)
        lift.append(lf)
    return pose(body=(0, 0, -1, 0, 0, 0, -1, 0)[f], head=(0, 1, 0, 0, 0, 1, 0, 0)[f],
                tail=(1, 1, 0, -1, -1, -1, 0, 1)[f], legs=tuple(legs), lift=tuple(lift), mist=f)


# THE LUNGE, timed to the bite's lifecycle: WINDUP is 38% of it and the bite lands on entering
# ACTIVE, so frame 2 (which starts at 33%) is the full stretch with the jaws open. Frames 0-1 are
# the crouch that loads the spring — the head drops, the hind legs fold — because a lunge with no
# crouch reads as a glide.
_ATTACK = (
    # body, reach, head, tail, jaw, legs (nf, ff, nh, fh), crouch
    (1, -1, 2, -1, 0, (1.0, 0.0, 1.0, 0.0), 1),
    (2, -2, 3, -2, 1, (1.0, 0.0, 2.0, 1.0), 2),
    (-1, 4, -1, 2, 2, (-4.0, -3.0, 2.0, 1.0), 0),
    (0, 4, 0, 2, 1, (-4.0, -3.0, 1.0, 1.0), 0),
    (0, 2, 0, 1, 0, (-2.0, -1.0, 1.0, 0.0), 0),
    (0, 0, 0, 0, 0, (0.0, 0.0, 0.0, 0.0), 0),
)


def attack_pose(f):
    b, r, h, t, j, legs, c = _ATTACK[f]
    return pose(body=b, reach=r, head=h, tail=t, jaw=j, legs=legs, crouch=c, mist=f)


ANIMATIONS = {
    "idle": (IDLE_FRAMES, True, idle_pose),
    "walk": (WALK_FRAMES, True, walk_pose),
    "attack": (ATTACK_FRAMES, False, attack_pose),
}


def _mist(px, x, y, phase, pal):
    """Two drifting wisps. Translucent, so the outline pass never traces them."""
    dx = (phase % 3) - 1
    raster.oval(px, x + dx, y, 1.8, 1.0, pal["mist"])
    raster.oval(px, x + dx + 2, y - 1 - (phase % 2), 1.3, 0.8, pal["mist_dim"])


def _side(p, pal):
    """Facing LEFT; forward is -x."""
    px = raster.blank(W, H)
    b, r = p["body"], p["reach"]
    raster.oval(px, 17, 30.5, 9, 1.5, SHADOW)
    nf, ff, nh, fh = p["legs"]
    lf = p["lift"]
    shoulder_x, hip_x = 11 - r, 22 - r // 2
    trunk_y = 20 + b

    def leg(x_top, y_top, fwd, lift, colour, hind):
        paw_x = x_top - fwd
        paw_y = 30 - lift
        if hind:
            hock_x = x_top + 2 - fwd // 2
            hock_y = 26 - lift // 2 - p["crouch"]
            raster.limb(px, x_top, y_top, hock_x, hock_y, 3.2, 2.4, colour)
            raster.limb(px, hock_x, hock_y, paw_x, paw_y, 2.2, 2.0, colour)
        else:
            raster.limb(px, x_top, y_top, paw_x, paw_y, 2.8, 2.0, colour)
        raster.rect(px, int(paw_x) - 2, paw_y, int(paw_x) + 1, paw_y + 1, colour)   # paw

    # FAR legs first (darker), then the trunk, then the NEAR legs over it.
    leg(shoulder_x + 2, trunk_y + 1, ff, lf[1], pal["far"], False)
    leg(hip_x + 1, trunk_y, fh, lf[3], pal["far"], True)
    # Tail: bushy, low, trailing.
    t = p["tail"]
    raster.limb(px, hip_x + 3, trunk_y - 2, hip_x + 8, trunk_y + 1 + t, 4.2, 2.6, pal["coat"])
    raster.limb(px, hip_x + 3, trunk_y - 2, hip_x + 7, trunk_y - 1 + t, 1.6, 1.2, pal["coat_hi"])
    # Trunk: a deep chest, a tucked waist, the haunch.
    raster.oval(px, shoulder_x + 1, trunk_y - 1, 4.5, 4.2, pal["coat"])
    raster.oval(px, (shoulder_x + hip_x) / 2.0 + 1, trunk_y, 6, 3.0, pal["coat"])
    raster.oval(px, hip_x, trunk_y - 0.5, 4, 3.6, pal["coat"])
    raster.rect(px, shoulder_x - 2, trunk_y + 1, hip_x + 2, trunk_y + 3, pal["belly"])
    raster.oval(px, (shoulder_x + hip_x) / 2.0, trunk_y - 3, 6, 1.2, pal["coat_hi"])   # spine
    # Neck and head, forward and LOW: the two cues that read as canine, not as livestock.
    # The head is carried LOW, about level with the back: an upright neck read as a horse.
    hx, hy = shoulder_x - 5, trunk_y - 5 + p["head"]
    raster.limb(px, shoulder_x + 1, trunk_y - 2, hx + 1, hy + 1, 5, 4, pal["coat"])
    raster.oval(px, hx, hy, 3.4, 3.0, pal["coat"])
    jaw = p["jaw"]
    raster.limb(px, hx - 1, hy + 1, hx - 5, hy + 1, 3.0, 2.2, pal["coat"])   # muzzle
    if jaw:
        raster.limb(px, hx - 1, hy + 3, hx - 4, hy + 2 + jaw, 1.8, 1.4, pal["coat_dk"])  # lower jaw
        raster.put(px, hx - 4, hy + 2, pal["maw"])
        raster.put(px, hx - 4, hy + 1, pal["fang"])
    raster.put(px, hx - 6, hy + 1, pal["nose"])
    # Ears: pointed, upright, the dark coat tone so they read against the lit head.
    raster.polygon(px, [(hx, hy - 1), (hx + 2, hy - 5), (hx + 3, hy - 1)], pal["coat_dk"])
    raster.oval(px, hx + 1, hy - 1, 1.6, 1.0, pal["coat_hi"])
    # NEAR legs over the trunk.
    leg(shoulder_x, trunk_y + 1, nf, lf[0], pal["coat_dk"], False)
    leg(hip_x - 1, trunk_y, nh, lf[2], pal["coat_dk"], True)
    raster.outline(px, INK)
    raster.put(px, hx - 1, hy - 1, pal["eye"])
    _mist(px, hip_x + 9, trunk_y + t, p["mist"], pal)
    _mist(px, (shoulder_x + hip_x) // 2 + 3, trunk_y - 5, p["mist"] + 1, pal)
    return px, (hx - 5, hy + 2)


def _front(p, pal):
    """Facing DOWN (toward the camera): the head and chest lead, the body behind."""
    px = raster.blank(W, H)
    b = p["body"]
    raster.oval(px, 16, 30.5, 7, 1.5, SHADOW)
    nf, ff, nh, fh = p["legs"]
    lf = p["lift"]
    r = p["reach"]
    # Hind legs, mostly hidden behind the chest.
    for (x, fwd, li) in ((11, nh, lf[2]), (21, fh, lf[3])):
        raster.limb(px, x, 18 + b, x, 28 - li - int(fwd) // 3, 2.6, 2.2, pal["far"])
    raster.oval(px, 16, 19 + b, 6.5, 4.5, pal["coat"])                       # body behind
    for (x, fwd, li) in ((13, nf, lf[0]), (19, ff, lf[1])):
        drop = int(-fwd) // 2 + r // 2
        raster.limb(px, x, 21 + b, x, 29 + drop - li, 3, 2.4, pal["coat_dk"])
        raster.rect(px, x - 1, 29 + drop - li, x + 2, 30 + drop - li, pal["coat_dk"])
    hy = 13 + p["head"] + r // 2
    # The RUFF: a wolf's neck fur is wider than its head and frames it from below. Without it
    # (the first D-057B pass) a round head on a round body read as a cat or a bear cub.
    raster.polygon(px, [(9, hy + 1), (23, hy + 1), (21, hy + 8), (16, hy + 10), (11, hy + 8)],
                   pal["belly"])
    raster.line(px, 10, hy + 3, 12, hy + 7, pal["coat"])
    raster.line(px, 22, hy + 3, 20, hy + 7, pal["coat"])
    # The HEAD is a WEDGE: broad across the ears, tapering to a long muzzle that points at the
    # viewer, so the face reads as a snout coming forward rather than a flat disc.
    raster.polygon(px, [(10, hy - 3), (22, hy - 3), (20, hy + 2), (18, hy + 6), (14, hy + 6),
                        (12, hy + 2)], pal["coat"])
    raster.rect(px, 12, hy - 3, 20, hy - 1, pal["coat_hi"])                   # lit brow
    for (x0, x1, tip) in ((10, 14, 11), (18, 22, 21)):                        # tall ears
        raster.polygon(px, [(x0, hy - 2), (tip, hy - 9), (x1, hy - 3)], pal["coat_dk"])
        raster.put(px, tip, hy - 6, pal["maw"])                                # inner ear
    raster.polygon(px, [(14, hy + 1), (18, hy + 1), (18, hy + 6), (16, hy + 7), (14, hy + 6)],
                   pal["coat_hi"])                                               # pale muzzle
    if p["jaw"]:
        raster.rect(px, 14, hy + 6, 19, hy + 7 + p["jaw"], pal["maw"])
        raster.put(px, 14, hy + 6, pal["fang"])
        raster.put(px, 18, hy + 6, pal["fang"])
    raster.rect(px, 15, hy + 5, 18, hy + 7, pal["nose"])                      # nose at the tip
    raster.outline(px, INK)
    # Eyes set wide and slanted, either side of the muzzle's root.
    raster.put(px, 13, hy, pal["eye"])
    raster.put(px, 19, hy, pal["eye"])
    raster.put(px, 12, hy - 1, pal["coat_dk"])
    raster.put(px, 20, hy - 1, pal["coat_dk"])
    _mist(px, 22, 18 + b, p["mist"] + 1, pal)
    return px, (16, hy + 7)


def _back(p, pal):
    """Facing UP (away): haunches and tail toward the camera, the head beyond them."""
    px = raster.blank(W, H)
    b = p["body"]
    raster.oval(px, 16, 30.5, 7, 1.5, SHADOW)
    nf, ff, nh, fh = p["legs"]
    lf = p["lift"]
    r = p["reach"]
    hy = 10 + p["head"] - r // 2
    raster.limb(px, 16, 16 + b, 16, hy + 1, 5, 4, pal["coat"])               # the neck joins it
    raster.oval(px, 16, hy, 4, 3.4, pal["coat"])                             # head beyond
    for x0 in (12, 17):
        raster.polygon(px, [(x0, hy - 1), (x0 + 1, hy - 5), (x0 + 3, hy - 1)], pal["coat_dk"])
    for (x, fwd, li) in ((12, nf, lf[0]), (20, ff, lf[1])):
        raster.limb(px, x, 15 + b, x, 22 - li + int(fwd) // 3, 2.4, 2, pal["far"])
    raster.oval(px, 16, 17 + b, 5, 5, pal["coat"])                           # shoulders
    raster.oval(px, 16, 22 + b, 7, 4.5, pal["coat"])                         # haunches
    raster.line(px, 16, 13 + b, 16, 24 + b, pal["coat_hi"])                  # spine
    for (x, fwd, li) in ((11, nh, lf[2]), (21, fh, lf[3])):
        raster.limb(px, x, 23 + b, x, 29 - li - int(fwd) // 3, 3, 2.4, pal["coat_dk"])
        raster.rect(px, x - 1, 29 - li, x + 2, 30 - li, pal["coat_dk"])
    t = p["tail"]
    # The brush: bushy, hanging, with a dark tip — the wolf's signature seen from behind.
    raster.limb(px, 16, 24 + b, 17 + t, 30, 4, 2.6, pal["coat"])
    raster.limb(px, 16, 24 + b, 17 + t, 29, 1.4, 1, pal["coat_hi"])
    raster.rect(px, 16 + t, 29, 19 + t, 31, pal["coat_dk"])
    raster.outline(px, INK)
    _mist(px, 15 + t, 30, p["mist"], pal)
    return px, (16, hy - 3)


def render_facing(direction, p, pal=PAL):
    """One 32x32 frame for a sheet row (0 down, 1 up, 2 left, 3 right). Returns (canvas, jaw)."""
    if direction == 0:
        return _front(p, pal)
    if direction == 1:
        return _back(p, pal)
    px, jaw = _side(p, pal)
    if direction == 2:
        return px, jaw
    return raster.mirror(px), (W - 1 - jaw[0], jaw[1])


def core_point(direction, p):
    r = p["reach"]
    if direction == 2:
        return (16 - r, 19 + p["body"])
    if direction == 3:
        return (16 + r, 19 + p["body"])
    return (16, 19 + p["body"])
