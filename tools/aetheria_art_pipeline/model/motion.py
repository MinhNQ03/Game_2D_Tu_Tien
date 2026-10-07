"""The Aetheria motion library: every animation as POSES of the canonical rig (D-062 CP6).

Pure Python, so the poses are reviewable and testable without Blender; `blender/build_actor.py`
keys them into real Blender Actions and renders from those. A pose is

  {"root": (dx, dy, dz)            whole-body offset in the character frame (-Y = forward)
   "lift": dz                      upper-body rise on the spine (breath; the feet stay put)
   "rot":  {bone: 3x3}             rotation in ARMATURE axes, relative to the parent (see below)
   "eyes_closed": bool}

ROTATION CONVENTION. A bone's matrix is applied on top of its parent's: the posed orientation
is parent_effect · Q · Rest. So an arm's swing is one `rx(...)` on the upper arm and the forearm
inherits it. Pitch rx(a) with a < 0 swings a downward-pointing bone FORWARD (toward -Y).

LAWS (MOTION_DESIGN_CONTRACT §3, CHARACTER_ART_BIBLE §6b/§6c), enforced by construction:
- feet are placed by IK on the ground plane — a planted foot never slides or floats;
- one arm does the whole gesture; no limb is ever re-parented or teleported between frames;
- the walk is a stride clocked by distance (8 frames per `stride_px`), opening/closing on the
  columns where the feet are near the idle stance;
- secondary masses (hair, sash tails) LAG the body by a beat, so the figure never moves as one
  rigid block.
"""
import math

DEG = math.pi / 180.0


# --- 3x3 rotation helpers --------------------------------------------------------------------

def ident():
    return [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rx(deg):
    c, s = math.cos(deg * DEG), math.sin(deg * DEG)
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def ry(deg):
    c, s = math.cos(deg * DEG), math.sin(deg * DEG)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def rz(deg):
    c, s = math.cos(deg * DEG), math.sin(deg * DEG)
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def chain(*ms):
    out = ident()
    for m in ms:
        out = mul(out, m)
    return out


def _pose():
    return {"root": (0.0, 0.0, 0.0), "lift": 0.0, "rot": {}, "eyes_closed": False}


def _set(p, bone, m):
    p["rot"][bone] = mul(p["rot"].get(bone, ident()), m)


# --- legs: analytic two-bone IK on the ground ------------------------------------------------

def leg_ik(spec, side, root, ankle_target, toe_pitch=0.0):
    """Thigh/shin/foot rotations that put the ankle at `ankle_target` (character frame, with
    the root offset already applied to the hip). Returns {bone: 3x3}. Sagittal-plane IK: the
    knee always bends FORWARD, the planted foot stays flat (its world pitch cancels)."""
    b = spec["body"]
    sfx = "L" if side > 0 else "R"
    hip = (side * b["hip_x"] + root[0], root[1], b["hip"] + root[2])
    l1 = b["hip"] - b["knee"]
    l2 = b["knee"] - b["ankle"]
    dy = ankle_target[1] - hip[1]
    dz = ankle_target[2] - hip[2]
    dist = min(math.hypot(dy, dz), l1 + l2 - 1e-3)
    phi = math.atan2(dy, -dz)                    # direction to the target, 0 = straight down
    cos_b = max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist)))
    a1 = phi - math.acos(cos_b)                  # thigh tilts forward: the knee leads
    knee = (hip[1] + l1 * math.sin(a1), hip[2] - l1 * math.cos(a1))
    a2 = math.atan2(ankle_target[1] - knee[0], -(ankle_target[2] - knee[1]))
    return {
        "thigh." + sfx: rx(a1 / DEG),
        "shin." + sfx: rx((a2 - a1) / DEG),
        "foot." + sfx: rx(-a2 / DEG + toe_pitch),
    }


def _stance_ankle(spec, side, fwd=0.0, lift=0.0, out=0.0):
    b = spec["body"]
    return (side * (b["hip_x"] + out), -fwd, b["ankle"] + lift)


def _legs(spec, p, near, far, toe=(0.0, 0.0)):
    """near/far = (forward, lift) for the LEFT / RIGHT foot."""
    for side, (fwd, lift), tp in ((1, near, toe[0]), (-1, far, toe[1])):
        for bone, m in leg_ik(spec, side, p["root"], _stance_ankle(spec, side, fwd, lift),
                              tp).items():
            _set(p, bone, m)


def _hair(p, back, side=0.0):
    """Hair chain lag: `back` degrees trailing per bone (+ = toward +Y), `side` sway."""
    for i, bone in enumerate(("hair_1", "hair_2", "hair_3")):
        k = 0.5 + 0.35 * i
        _set(p, bone, chain(rx(back * k), ry(side * k)))
    for sfx in ("L", "R"):
        _set(p, "lock." + sfx, rx(back * 0.35))
    _set(p, "sash_tail", rx(back * 0.6))


def _arm(p, sfx, swing=0.0, out=0.0, elbow=0.0, wrist=0.0, twist=0.0):
    """swing: pitch of the upper arm (- = forward); out: abduction (+ = away from the body);
    elbow: forearm pitch relative (- = bend forward/up); wrist: hand pitch relative."""
    side = 1 if sfx == "L" else -1
    _set(p, "upper_arm." + sfx, chain(rx(swing), ry(-side * out), rz(twist)))
    if elbow:
        _set(p, "forearm." + sfx, rx(elbow))
    if wrist:
        _set(p, "hand." + sfx, rx(wrist))


# --- IDLE: one breath in six beats ------------------------------------------------------------

_IDLE = (  # (breath 0..1, hair back deg, hair side deg)
    # Six DISTINCT beats: an inhale over three, an exhale over three, the hair answering a
    # beat late. The first table held the breath for two frames and the validator caught it —
    # two identical beats are a stall the eye reads as a hitch, not a pause.
    (0.0, 0.0, -1.0), (0.45, 2.5, 0.5), (0.9, 5.0, 2.5),
    (0.7, 2.0, 3.0), (0.35, -2.0, 0.5), (0.1, -4.0, -2.5))


def idle(spec, f):
    p = _pose()
    breath, hb, hs = _IDLE[f]
    p["lift"] = 1.0 * breath
    _legs(spec, p, (0.6, 0.0), (-0.6, 0.0))
    for sfx in ("L", "R"):
        _arm(p, sfx, swing=-3.0 - 5.0 * breath, elbow=-6.0 * breath)
    _set(p, "chest", rx(2.0 * breath))
    _hair(p, hb, hs)
    return p


# --- WALK: a stride, clocked by distance -------------------------------------------------------

STRIDE = 4.2                          # half stride length (units) at the ankle
_WALK_BOB = (-0.7, -0.1, 0.45, -0.1, -0.7, -0.1, 0.45, -0.1)


def _foot(phase):
    """(forward, lift) of a foot at stride phase [0, 1). Stance: planted, travelling back
    under the body (pushing the ground). Swing: lifted, travelling forward."""
    if phase < 0.5:
        t = phase / 0.5
        return (STRIDE - 2 * STRIDE * t, 0.0)
    t = (phase - 0.5) / 0.5
    return (-STRIDE + 2 * STRIDE * t, 1.5 * math.sin(math.pi * t))


def walk(spec, f):
    p = _pose()
    ph = f / 8.0
    near = _foot(ph)
    far = _foot((ph + 0.5) % 1.0)
    lateral = 0.45 if near[1] == 0 and far[1] > 0 else (-0.45 if far[1] == 0 and near[1] > 0
                                                         else 0.0)
    p["root"] = (lateral, -0.6, _WALK_BOB[f])
    toe_l = -12.0 if near[1] > 0 else 0.0
    toe_r = -12.0 if far[1] > 0 else 0.0
    _legs(spec, p, near, far, (toe_l, toe_r))
    swing = 16.0 * (near[0] / STRIDE)        # the arm swings OPPOSITE its own side's leg
    _arm(p, "L", swing=swing, elbow=-8.0 - max(0.0, -swing) * 0.4)
    _arm(p, "R", swing=-swing, elbow=-8.0 - max(0.0, swing) * 0.4)
    _set(p, "spine", rx(-3.0))
    _set(p, "chest", rz(4.0 * (near[0] / STRIDE)))   # the shoulders counter-rotate the hips
    trail = 7.0 + (3.0 if _WALK_BOB[f] < 0 else 0.0)
    _hair(p, trail, 2.0 * math.sin(2 * math.pi * (ph - 0.15)))
    return p


# --- ATTACK: the palm strike (the right hand), timed to the gameplay lifecycle ------------------
# 25% windup (frames 0-1: weight BACK, the striking hand drawn to the hip, knees sink), the hit
# on frame 2 (full extension, a step in), 3 the follow-through, 4-7 the recovery to ready.

_ATTACK = (
    # root(y fwd-, z), lead foot fwd, rear foot fwd, upper arm swing, elbow, wrist, out,
    # rear arm swing, chest twist, hair
    ((0.5, -0.4), 0.8, -1.0, 28.0, -70.0, 0.0, 12.0, -8.0, 10.0, -3.0),
    ((0.9, -0.8), 1.0, -1.4, 34.0, -95.0, -10.0, 16.0, -12.0, 16.0, -5.0),
    ((-1.2, -0.6), 3.8, -1.8, -82.0, -6.0, -80.0, -6.0, 22.0, -14.0, 10.0),
    ((-1.5, -0.6), 4.0, -1.6, -88.0, 0.0, -85.0, -8.0, 26.0, -18.0, 14.0),
    ((-1.1, -0.5), 3.4, -1.4, -70.0, -14.0, -60.0, -4.0, 20.0, -12.0, 9.0),
    ((-0.6, -0.3), 2.4, -1.0, -40.0, -22.0, -30.0, 2.0, 10.0, -6.0, 5.0),
    ((-0.2, -0.1), 1.2, -0.6, -15.0, -14.0, -8.0, 4.0, 3.0, -2.0, 2.0),
    ((0.0, 0.0), 0.6, -0.6, -5.0, -6.0, 0.0, 2.0, 0.0, 0.0, 0.0),
)


def attack(spec, f):
    p = _pose()
    (ry_, rz_), lead, rear, sw, el, wr, out, rsw, tw, hair = _ATTACK[f]
    p["root"] = (0.0, ry_, rz_)
    # the RIGHT foot leads the strike (the striking side steps in)
    _legs(spec, p, (rear, 0.0), (lead, 0.0))
    _arm(p, "R", swing=sw, elbow=el, wrist=wr, out=out)
    _arm(p, "L", swing=rsw, elbow=-35.0 if f in (2, 3, 4) else -12.0, out=4.0)
    _set(p, "chest", rz(tw))
    _set(p, "spine", rx(-4.0 if f in (2, 3, 4) else 3.0 if f < 2 else 0.0))
    _hair(p, hair, 0.0)
    return p


# --- CAST (thi triển): seal at the chest, rise, release, recover --------------------------------
# PREPARE [0,.25) CHANNEL [.25,.5) RELEASE [.5,.75) RECOVER [.75,1] — two columns each.

_CAST = (
    # root(y, z), lead foot, rear foot, R(swing, elbow, wrist, out), L(swing, elbow, out), twist,
    # hair
    ((0.3, -0.3), 0.6, -0.6, (-30.0, -100.0, 0.0, -24.0), (-30.0, -100.0, -24.0), 0.0, 1.0),
    ((0.5, -0.6), 0.8, -0.8, (-38.0, -112.0, 0.0, -26.0), (-38.0, -112.0, -26.0), 0.0, 2.0),
    ((0.2, -0.2), 0.8, -0.8, (-62.0, -100.0, 0.0, -26.0), (-62.0, -100.0, -26.0), 0.0, 3.0),
    ((0.2, -0.5), 0.8, -0.8, (-70.0, -104.0, 0.0, -24.0), (-70.0, -104.0, -24.0), 0.0, 5.0),
    ((-1.0, -0.5), 3.2, -1.6, (-84.0, -8.0, -75.0, -4.0), (18.0, -30.0, 6.0), -14.0, 9.0),
    ((-1.3, -0.5), 3.6, -1.6, (-88.0, 0.0, -82.0, -6.0), (22.0, -32.0, 6.0), -16.0, 12.0),
    ((-0.6, -0.2), 2.0, -1.0, (-40.0, -20.0, -30.0, 0.0), (8.0, -16.0, 4.0), -6.0, 5.0),
    ((-0.1, 0.0), 0.8, -0.6, (-8.0, -8.0, 0.0, 2.0), (-2.0, -6.0, 2.0), 0.0, 1.0),
)


def cast(spec, f):
    p = _pose()
    (ry_, rz_), lead, rear, r, l_, tw, hair = _CAST[f]
    p["root"] = (0.0, ry_, rz_)
    _legs(spec, p, (rear, 0.0), (lead, 0.0))
    _arm(p, "R", swing=r[0], elbow=r[1], wrist=r[2], out=r[3])
    _arm(p, "L", swing=l_[0], elbow=l_[1], out=l_[2])
    _set(p, "chest", rz(tw))
    _hair(p, hair, 0.0)
    return p


# --- MEDITATE: seated, lotus, eyes closed -------------------------------------------------------
# Frame 0 is the descent (the body half-risen: a cultivator LOWERS into the seat); frames 1-3 are
# one slow breath, looped by the runtime.

SEAT_Z = 4.2                           # pelvis height when seated
_MEDITATE = ((0.45, 0.0, 1.0), (0.0, 0.0, 0.0), (0.0, 0.7, 2.0), (0.0, 0.35, 3.0))


def meditate(spec, f):
    p = _pose()
    b = spec["body"]
    rise, breath, hair = _MEDITATE[f]
    drop = (b["hip"] - SEAT_Z) * (1 - rise)
    p["root"] = (0.0, 0.4, -drop)
    p["lift"] = 0.6 * breath
    p["eyes_closed"] = True
    fold = 1 - rise
    for sfx, side in (("L", 1), ("R", -1)):
        # thighs forward to horizontal and out; shins fold back across the front
        _set(p, "thigh." + sfx, chain(rz(side * 38.0 * fold), rx(-88.0 * fold)))
        _set(p, "shin." + sfx, chain(rz(-side * 70.0 * fold), rx(150.0 * fold)))
        _set(p, "foot." + sfx, rx(-60.0 * fold))
        # hands rest in the lap, one over the other at the dantian
        _arm(p, sfx, swing=-28.0 * fold - 4.0, elbow=-62.0 * fold, out=-6.0 * fold)
    _set(p, "head", rx(6.0 * fold))
    _hair(p, -1.0 + hair * 0.8, 0.0)
    return p


ANIMATIONS = {
    "idle": idle,
    "walk": walk,
    "attack": attack,
    "meditate": meditate,
    "cast": cast,
}


# --- MIRRORING: the LEFT facing ---------------------------------------------------------------
#
# Every action is authored for one striking side (the right hand). Turned to face screen-LEFT,
# that hand would be the FAR one, and a palm strike would leave the body at head height instead
# of chest height — the gameplay contract (the strike, its VFX origin and its target height
# agree in every facing; test_character_locomotion) needs LEFT to mirror RIGHT. So the LEFT
# facing renders the MIRRORED pose: the same rig and meshes, lit by the same canonical light,
# with the near hand leading. It is a real 3D render, not a flipped image, so the light stays
# top-left and the garment's own asymmetry (the crossed collar) stays correct.

_S = [[-1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]


def mirror_name(bone):
    if bone.endswith(".L"):
        return bone[:-2] + ".R"
    if bone.endswith(".R"):
        return bone[:-2] + ".L"
    return bone


def mirror(pose):
    """The pose reflected across the body's sagittal plane (x -> -x): left and right bones
    swap, and each rotation conjugates by the reflection, S·M·S."""
    out = dict(pose)
    x, y, z = pose["root"]
    out["root"] = (-x, y, z)
    out["rot"] = {mirror_name(b): mul(mul(_S, m), _S) for b, m in pose["rot"].items()}
    return out
