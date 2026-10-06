# PRESENTATION ARCHITECTURE CONTRACT — Aetheria

> **Status: CONTRACT, frozen by D-056.** The ACTION LAYER described in §4 is implemented and
> proven on two actors; everything labelled VOCABULARY is a reserved name with no
> implementation, deliberately.
>
> **Why this document exists.** Aetheria must not become a game whose gameplay is correct and
> whose characters are stiff — where pressing attack produces a number changing, a skill is a
> ball appearing next to a motionless figure, a level-up is a different integer, and the world
> does not move. That outcome is reachable from a fully green pipeline, which is exactly what
> makes it dangerous: every gate can pass while the product goal fails.
>
> Presentation is therefore a system that develops **alongside** gameplay, with its own gate in
> `docs/PHASE_EXECUTION_PROTOCOL.md`, not a polish pass at the end.
>
> **Its two companions (D-057).** This document owns how presentation is WIRED. What good motion
> and feedback ARE — the governing laws, timing grammar, hierarchy, curiosity, the self-critique —
> is `docs/MOTION_DESIGN_CONTRACT.md`; what makes it look and behave like AETHERIA, and how the
> reference library is used, is `docs/XIANXIA_IDENTITY_CONTRACT.md` (D-057A).

---

## 1. THE FROZEN PRINCIPLE

```
GAMEPLAY decides WHAT happened.
PRESENTATION decides HOW it is perceived.
```

The pipeline, in one direction only:

```
AUTHORITATIVE STATE
      ↓
DOMAIN / GAMEPLAY RESULT
      ↓
SEMANTIC EVENT / CUE
      ↓
PRESENTATION RESOLUTION
      ↓
ANIMATION / VFX / AUDIO / CAMERA / UI
```

Combat reports `attack started · active · hit · recovered`. Presentation may render that as
body wind-up, arm extension, weapon motion, a trail, an impact flash, hit-stop, screen shake,
sound, a damage number and a recovery pose.

Presentation may **never** decide: damage · whether a hit landed · death · XP · cooldown ·
loot. Deleting every presentation node must change no outcome. That is the testable form of
this principle, and it is asserted.

---

## 2. THREE LAYERS, NOT ONE

A character's visual state is three independent layers. Collapsing them is how an attack
animation ends up fighting a walk cycle.

| Layer | Examples | Lifetime | Who drives it |
|---|---|---|---|
| **LOCOMOTION** | `IDLE`, `WALK` | continuous, looping | the entity's movement intent |
| **ACTION** | `BASIC_ATTACK`, later `CAST`, `HIT`, `STUN`, `DEATH`, `EMOTE`, `INTERACT` | bounded, one-shot, non-looping | an action authority (today: the attack lifecycle) |
| **TRANSIENT FEEDBACK** | hit flash, critical flash, corpse tint, level-up flash | bounded, overlaid, does not replace a pose | the event that caused it |

**Precedence: ACTION out-ranks LOCOMOTION.** A character mid-swing shows the swing even while
walking. **TRANSIENT FEEDBACK is orthogonal** — it modulates whatever pose is showing and never
replaces it, which is why `DamageFeedback` writes `modulate` on the entity and owns nothing
about frames.

Facing is **shared, not layered**: a character may turn during an action, so a facing update
changes the direction row without restarting or cancelling the action.

---

## 3. GAMEPLAY TIMING OWNS THE TRUTH

```
GAMEPLAY TIMING  = authoritative
PRESENTATION TIMING = follower
```

An animation must never be the reason something happened:

```
FORBIDDEN:  animation reached frame 7  →  therefore deal damage
```

The hit window is owned by `AttackStateMachine` and consumed as an edge exactly once per
swing. A presentation layer **derives** its frame from that lifecycle; it does not keep a
parallel clock that could drift, and it cannot advance the lifecycle.

If a future feature genuinely needs "damage on a specific animation beat", that requires an
**explicit gameplay marker contract** designed on purpose — authored as data, owned by the
domain, with the animation reading it rather than defining it. Until such a contract exists,
the default above is absolute.

**This is also a multiplayer requirement, not only a tidiness one.** A remote client's frame
rate, asset set and animation length must not be able to change an outcome.

**Hit-stop holds an IMAGE, never the simulation (D-057).** A held frame on impact is
presentation freezing its OWN pose and effects. `Engine.time_scale` and the physics tick belong to
the simulation: the one-line Godot recipe for hit-stop slows the attack lifecycle, AI, movement
and every timer because an effect said so, and an authoritative server could never honour it.
Presentation never writes them — guarded by `tests/unit/presentation/test_motion_contract.gd`
(`MOTION_DESIGN_CONTRACT.md` M-4.3).

---

## 4. THE ACTION LAYER (implemented)

The existing `CharacterVisualComponent` was **extended**, not replaced, and no manager was
introduced. It already owned the sprite, the direction grid, the frame clock and the
feet-anchor; it lacked only a second layer.

```gdscript
play_action(action: StringName) -> bool   # begin a one-shot action; false if unavailable
drive_action(progress: float) -> void     # set the action frame from EXTERNAL progress [0,1]
end_action() -> void                      # return to locomotion
is_action_playing() -> bool
current_action() -> StringName
```

**`drive_action(progress)` is the shape that makes §3 structural.** The component does not
time the action itself; it is *told* how far through the action the gameplay authority is. A
long authored wind-up spends more frames in the wind-up automatically, because the progress it
receives is the real elapsed fraction of the real lifecycle.

```
column = clamp(int(progress * frame_count), 0, frame_count - 1)
```

No magic phase split, no per-phase frame budget to keep in sync with authored durations.

**Wiring is deliberately CONCRETE and single.** The component resolves an optional sibling that
reports an attack lifecycle — a typed `AttackComponent` reference, resolved the same optional way
`AttackFeedback` and `DamageFeedback` resolve theirs (absence is legal and silent; the reads on
the hot path are direct calls, not `call()`, since the D-056 review pass). It does **not** define an "action source
interface", because a second action *source* does not exist yet — per the anti-over-engineering
rule, the abstraction arrives with its second consumer. When `CAST` lands, it calls the same
three methods and the layer does not change.

**The action ends on the lifecycle leaving its active state, not only on a finish signal.**
`AttackComponent.cancel()` emits nothing, and `Enemy._on_health_died()` calls it — so a layer
waiting on `attack_finished` would freeze a corpse mid-thrust. Reading the state is what makes
cancel, death and teardown all end the action.

---

## 5. SEMANTIC ACTION VOCABULARY

**Implemented:** `BASIC_ATTACK` (as `&"attack"`).

**VOCABULARY — reserved names, no implementation, no stub:**

```
IDLE  WALK                            (locomotion; implemented)
BASIC_ATTACK                          (action; implemented)
CAST  HIT  STUN  DEATH  EMOTE
INTERACT  LEVEL_UP  BREAKTHROUGH      (action; reserved)
```

**`CAST` is ONE action, not four (D-057).** P15's cast lifecycle — prepare → channel → release
→ recover — is a set of PHASES of one action, exactly as WINDUP / ACTIVE / RECOVERY are phases of
`BASIC_ATTACK`: the lifecycle reports its phase and progress, the action layer derives the frame.
`CAST_PREPARE`, `CAST_CHANNEL`, `CAST_RELEASE` and `CAST_RECOVER` are phase names, never four
separate actions or four sheets wired by hand.

A reserved name is a name, not a feature. **An optional field no shipped data authors is a
no-op with documentation** — the project has shipped that mistake once already (a walk sheet
left null in every profile, so the documented idle fallback was the only path that ever ran).
So: a vocabulary entry becomes real in the phase that authors content for it, in the same
change.

---

## 6. REUSE ACROSS ACTORS (proven, not asserted)

One semantic action, many actors. `CAST_FIREBALL` must be usable by the player, another
player, an NPC cultivator, an enemy mage, a boss and a remote player — with **different**
visual profile, sprite set, silhouette, frame count, VFX profile and SFX profile.

**Forbidden:** `player_cast.gd`, `enemy_cast.gd`, `npc_cast.gd`, `boss_cast.gd`. Logic is
shared; data differs.

**Structurally validated by a concrete second use case:** the player (32×48 frames, 6-frame
attack sheet) and the Vụ Lang mist wolf (32×32 frames, 4-frame attack sheet) run the same
action layer through the same three methods with no actor-specific branch. Two different frame
sizes and two different frame counts, one code path. A test asserts both resolve, and a
structural test asserts no second animation controller exists.

---

## 7. DATA-DRIVEN, NOT BRANCHED

Prefer a Resource/profile over a conditional:

```
FORBIDDEN:  if character == ... / if enemy == ... / if skill == ...
```

`CharacterVisualProfileData` gained **one optional `@export`** (`attack_sheet`) and one
validation line; `_sheet_errors` and `frame_count_of` were already sheet-agnostic and changed
not at all. There is **one** visual profile class and there must never be a second.

The target it buys:

```
add a skill      → add data + assets        → no core rewrite
add an NPC       → choose visual/locomotion/action profile → no animation rewrite
```

---

## 8. ASSET LAYOUT AND NAMING

Scalable layout (directories are created when their first asset lands, not pre-emptively):

```
assets/
  sprites/
    characters/        players + archetypes
    enemies/
    props/
    bosses/  pets/  npc/        (reserved)
    skills/  items/  effects/   (reserved)
  tiles/<set>/
  ui/<pack>/
  fx/
    combat/  skills/  cultivation/  world_events/  progression/   (reserved)
  audio/
    sfx/  music/       (reserved)
  fonts/
```

**Naming.** The project's existing convention is `<actor>_<anim>.png` with the GRID inside the
file — one ROW per cardinal direction × N animation COLUMNS — so direction is **not** in the
filename:

```
player_proto_idle.png     128x192   4 frames
player_proto_walk.png     192x192   6 frames
player_proto_attack.png   192x192   6 frames
mist_wolf_idle.png         64x128   2 frames
mist_wolf_walk.png        128x128   4 frames
mist_wolf_attack.png      128x128   4 frames
```

This is **kept** rather than replaced with `player_attack_windup_down`-style per-frame files:
the grid convention already derives the frame count from the texture width (so art and data
cannot disagree), keeps one file per animation instead of 4 × N, and is what the existing
loader, validator and generator all speak. A per-phase filename scheme would also hard-code
the phase split that §4 deliberately derives from authored durations.

**Frame counts are DERIVED from texture width, never authored beside the art.**

Art baseline unchanged (`.kiro/steering/06-art-assets.md`): 16px world grid, 32×48 character
baseline, nearest filtering, integer scaling, mipmaps off.

---

## 9. ART QUALITY BAR

Every visual feature is judged on: silhouette · timing · anticipation · follow-through ·
readability · contrast · layering · motion · impact · consistency · reuse.

**"The sprite changed frame" is not a pass.**

```
BAD basic attack:     idle → slash sprite → idle
REQUIRED:             anticipation → body/weapon motion → contact → recoil → recovery

REQUIRED skill:       prepare → channel → release → projectile/effect → impact → recovery
REQUIRED level-up:    recognition cue → buildup → light/vertical effect → character response → result
```

Breakthrough (Phase 12+) must **reuse this vocabulary at a larger scale**, not invent a second
one.

**Honest status (D-057): the shipped level-up does NOT meet the REQUIRED bar above** — it is a
badge flash and a banner, with no buildup and no character response. It is owned by **P12**: the
breakthrough presentation seam is the level-up's real second consumer, so the shared
progression-celebration seam is built there, at macro scale for a breakthrough and mid scale for a
level-up — never the same look, because a level and a realm are different axes
(`MOTION_DESIGN_CONTRACT.md` §20, M-4.7).

**Generated pixel art is inspected magnified before it ships.** This has caught defects no
assertion could: a draw order that put skin over hair on every UP frame, walk deltas of ±1px
that animated nothing a player could see, and a dither pass speckling the transparent canvas
outside a silhouette. The asset generator additionally **fails the build** on a sheet whose
adjacent frames are pixel-identical or whose direction rows cannot be told apart.

---

## 10. PRESENTATION CUE CONTRACT

Cues are **small and semantic**. A cue carries the minimum facts presentation needs to react —
never a domain object, never a large state blob.

Existing cue vocabulary (all **direct local signals or view DTOs**, which is the house pattern):

```
attack_started · attack_resolved · attack_finished      AttackComponent
damaged(amount, is_critical) · died · health_changed    HurtboxComponent / entity
enemy_defeated(reward_id, ...)                          CombatRuntime
xp_gained · level_changed                               ProgressionRuntime
ProgressionView · CombatTargetView · SectMembershipView · SectPoliticsView · WorldSimView
```

Reserved cue names with no producer yet: `critical_hit`, `cast_started`, `cast_released`,
`effect_started`, `effect_finished`, `world_event_started`, `world_event_finished`.

The D-056 brief's vocabulary, mapped onto what already exists — so a later phase reaches for
the existing producer instead of adding a synonym beside it:

| Brief cue | Existing producer (no new signal added) |
|---|---|
| `attack_started` | `AttackComponent.attack_started` |
| `attack_active` | `AttackComponent.state() == ACTIVE` (a lifecycle STATE, read by the action layer each frame); `attack_resolved` fires inside it when the hit window resolves |
| `attack_recovered` | `AttackComponent.attack_finished` — and the READY state, which also covers `cancel()`, which emits nothing (§4) |
| `damaged` / `critical_hit` | `HurtboxComponent.damaged(amount, is_critical)` — a critical is a flag on the same cue, not a second cue |
| `defeated` | entity `died`; `CombatRuntime.enemy_defeated(reward_id, …)` for the reward-bearing fact |
| `level_up` | `ProgressionRuntime.level_changed` |

**The EventBus is NOT the cue transport for local cues, and no cue was added to it.** Its own
scope rule limits it to signals with a real current producer *and* consumer, and it states that
local component→owner communication uses direct signals. Combat and progression cues are local to
an entity or a session; routing them through a global bus would add indirection and a second
place to look. **No new autoload was added for presentation, and none may be.**

**Two tiers, stated once (D-057)** — so `SYSTEM_DEPENDENCY_MATRIX.md`'s "audio/VFX listen to the
EventBus" and this section cannot be read as a contradiction:

| Cue scope | Transport | Examples |
|---|---|---|
| **entity- or session-local** | direct signals / view DTOs | attack lifecycle, `damaged`, `died`, `level_changed` |
| **world-scale**, with a real global producer AND consumer | the EventBus, under its scope rule | a world event starting or resolving (reserved), `language_changed` |

A future audio or VFX service listens on whichever tier the cue already lives in; it does not
move a local cue onto the bus to make listening easier.

Where typed data is warranted, use a small typed view DTO (the five above are the precedent),
not an untyped `Dictionary` bag.

---

## 11. OFFLINE ↔ MULTIPLAYER PRESENTATION RULE

```
TARGET:  SERVER RESULT / AUTHORITATIVE EVENT  →  CLIENT PRESENTATION
```

A client rendering a remote actor needs no domain object — only a semantic action state:

```
character_id = c123
action       = cast
phase        = active
sequence     = 91
```

From that the client chooses its own animation asset, VFX, SFX and camera response. Which
asset it picks is a **local** decision.

**Therefore presentation data must never become server-authoritative gameplay state.** The
action layer's API is already shaped for this: `play_action` + `drive_action(progress)` take a
semantic name and a scalar — exactly what an authoritative event can carry — rather than a
reference to a local node or a texture.

---

## 12. LOCAL RESPONSIVE PRESENTATION (prepared, not built)

A client may later start an anticipation animation *before* a server result, so input feels
immediate.

```
local presentation prediction  !=  local gameplay authority
```

If the server rejects the command, the presentation must be **cancellable and recoverable**.
`end_action()` plus "the action ends when the lifecycle leaves its active state" is that
cancel path, already present and already exercised by the death/cancel case. This is
preparation, not network prediction; no prediction, reconciliation or rollback is implemented.

---

## 13. PERFORMANCE CONTRACT

Presentation must not create: per-frame allocation · per-frame node creation · duplicate
animation controllers · unbounded particles · unbounded timers · one `AnimationPlayer` per
tiny effect.

Rules in force:

* **Idle costs nothing.** `_process` is off unless something is actually animating —
  `CharacterVisualComponent` switches it off for a single-frame sheet, `AttackFeedback` is off
  outside a swing, `DamageFeedback` and `LevelUpFeedback` switch themselves off when their
  effect decays. Every creature carries these, so an always-on `_process` would be N callbacks
  per frame for an effect that runs for a fraction of a second.
* **Do not animate what is not visible** when the work is avoidable.
* **Write only what changed** on the hot path (`texture`/`hframes` are set only on change;
  only `frame` changes per tick).
* **Pooling and deferred optimization only with a concrete second use case** — not by default.
* A guard that walks the source tree is itself a hot loop: compile its patterns once.

Any non-trivial optimization is recorded in `docs/PERFORMANCE.md` with **problem · cause ·
solution · impact · how measured**. "Probably faster" is not an entry. A test-harness
improvement is **not** logged there — that file tracks the game.

---

## 14. DETERMINISM IN PRESENTATION

Any presentation effect that influences a screenshot or a test must be **reproducible**.

```
FORBIDDEN in a test-critical presentation path:  randomize() / randf()
```

If an effect wants variation, it takes an injected deterministic seed or uses a fixed pattern.
**Presentation randomness may never change a domain outcome** — the seeded `RngService` streams
exist for outcomes, and a presentation effect must not draw from them.

---

## 15. ANTI-OVER-ENGINEERING (explicit extension)

Never created, in any phase:

```
UniversalAnimationFramework   UniversalEffectManager
UniversalPresentationManager  UniversalEntityFramework
UniversalReplicationFramework GenericGameObjectManager
```

Every new presentation abstraction needs **a real current use case AND at least one concrete
second use case**, or demonstrable necessity as a production/multiplayer seam. The action layer
qualifies: its second use case is the mist wolf, and the proof is a test that runs both actors
through the same path.

When in doubt: **extend the component that already owns the concern.** The action layer is
five methods on an existing component, not a new subsystem.

---

## 16. WHAT A PHASE OWES PRESENTATION

> **Every gameplay phase must leave behind at least one REUSABLE player-facing presentation
> capability when its feature has a visible gameplay consequence.**

Not a bespoke effect for one feature — a seam the next feature reuses. The per-phase seeds are
listed in `docs/ROADMAP.md`; the gate that enforces it is in
`docs/PHASE_EXECUTION_PROTOCOL.md`.

**Foundation first, content second:** the phase that introduces a *category* builds the
reusable seam before the content explosion. First skill → skill presentation seam → second
skill reuses it. First NPC → locomotion/reaction seam. First boss → phase/telegraph seam.
Never: boss A bespoke, boss B bespoke, boss C copies B.

**And it is designed before it is built (D-057):** the deliberation record
(`MOTION_DESIGN_CONTRACT.md` §13), the Reference → Original note
(`XIANXIA_IDENTITY_CONTRACT.md` §13), and — at the end — the self-critique and the Aetheria
Identity Review.
