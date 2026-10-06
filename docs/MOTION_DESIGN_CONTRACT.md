# MOTION DESIGN CONTRACT — Aetheria

> **Status: CONTRACT, frozen by D-057 (2026-10-06).** Owner of the **motion and feedback design
> language** — what moves, why, how much and when — and of the **player-experience review**
> that judges it. Every rule has an id (`M-n.n`) so a review can cite it.
>
> **Not owner of** (cite, do not restate — `GAME_DESIGN_FREEZE.md` §2):
>
> | Concern | Owner |
> |---|---|
> | How presentation is WIRED: layers, timing authority, cues, performance, determinism | `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` (D-056) |
> | What makes a motion AETHERIA: xianxia identity, the reference library and how to study it | `docs/XIANXIA_IDENTITY_CONTRACT.md` (D-057A) |
> | Sprite technical rules: grid, 32×48, anchor, palette, outline | `docs/CHARACTER_ART_BIBLE.md`, `.kiro/steering/06-art-assets.md` |
> | UI visual language, information hierarchy, screen inventory, **HUD composition** (weight ladder, negative-space budgets) | `docs/UI_UX_BIBLE.md` (§3c for HUD composition) |
> | Which phase seeds which presentation capability | `docs/ROADMAP.md` (Continuous Visual Integration) |
> | Canon: names, realms, elements, weapons, world laws | `docs/CANON_LEDGER.md`, `docs/WORLD_BIBLE.md` |
>
> **What D-057 implemented** — deliberately little: the HUD composition correction measured in
> §11 (rules in `UI_UX_BIBLE.md` §3c), the reference-library isolation (`XIANXIA_IDENTITY_CONTRACT.md`
> §2.2) and the simulation-clock guard (§4). Everything else here is design law that future
> phases are reviewed against. (Phase 12 had not started when D-057 froze this; P12-P15 are
> implemented since D-058…D-061 and were reviewed against it.)

---

## 0. How to use this document

* **Before** designing any visual feature, classify what moves (§2) and write the deliberation
  record (§13). For a major feature, also the Reference → Original note
  (`XIANXIA_IDENTITY_CONTRACT.md` §13).
* **While** building, the rules are constraints, not inspiration: an `M-` rule that is broken
  needs a `DECISIONS.md` entry, the same as any frozen rule.
* **After** building, the review questions in each section and the self-critique in §19 are the
  acceptance criteria. A bad answer to any one of them can be the reason a feature is NOT DONE.

The two failure modes this document exists to prevent:

```
1. correct gameplay, dead presentation  — a number changes and nothing is felt
2. busy presentation, no meaning         — everything glows, shakes and loops, and nothing reads
```

Both pass every automated gate. Both fail the product.

---

## 1. The first law: perception is the goal, not animation

**M-1.1 — Start from what is happening, never from "what animation do we need".** The design
question is *what is happening to this thing, and how should it react?* The animation, effect
or transition is the answer to that question, not the starting point.

**M-1.2 — Every motion sits on a causal chain.**

```
CAUSE → INTENTION → STATE CHANGE → RESPONSE → CONSEQUENCE → RECOVERY / SETTLE
```

The basic attack, as the build renders it today (the worked example every later feature is
compared against):

| Stage | Basic attack |
|---|---|
| CAUSE | the player presses the semantic `attack` action |
| INTENTION | `AttackComponent.request_attack()` — an intent, not a result |
| STATE CHANGE | `READY → WINDUP → ACTIVE → RECOVERY` (`AttackStateMachine`, gameplay-owned) |
| RESPONSE | the action layer poses the body from the lifecycle's own progress; `AttackFeedback` draws the arc gathering, striking, fading |
| CONSEQUENCE | the target flashes (`DamageFeedback`), its gauge drops, it dies, its body stays as a corpse, the target plaque says **Defeated** |
| RECOVERY / SETTLE | the recovery frames, then locomotion resumes; the plaque retires after its linger |

**M-1.3 — Nothing moves without a reason.** Before any animation or effect, answer: *what caused
this · what is moving · why · where does the force originate · what reacts first · what reacts
second · what stays still · how does it stop.* If any answer is missing: **reconsider the
motion.**

**M-1.4 — Not everything animates.** Animation must improve at least one of readability,
immersion, response, emotion, feedback or world life. A correctly placed still object beats a
superfluous loop. **Animation is not the goal; perception is.**

**M-1.5 — Every motion has a purpose**, at least one of: communicate gameplay · state ·
physical reaction · emotion · world life · reward · danger · consequence · create anticipation
· improve responsiveness. "So it has an animation" is not a purpose.

**M-1.6 — The "So what?" test.** If removing the motion would not make the experience worse,
remove or simplify it.

---

## 2. Classify before you design: the governing laws

There is no single biomechanics for everything. Each moving thing obeys a **governing
principle**; choosing the wrong one is how a cloth banner snaps like a door and a qi orb falls
like a rock.

**M-2.1 — Classify the subject first, then apply ITS law.** Never apply one motion template to
every category.

| Category | Examples | Governing principle | Review questions |
|---|---|---|---|
| **Humanoid** | player, NPC, cultivator, enemy cultivator | anatomy · balance · weight transfer · joint continuity · anticipation · follow-through | anatomy? balance? weight? gesture? (§3) |
| **Creature** | mist wolf, pets, beasts, bosses | species movement · centre of mass · limb/tail/wing coordination | does it move like *this* animal? where is its weight? |
| **Rigid object** | weapon, door, chest, crate, rock, projectile | mass · pivot · inertia · collision | how heavy? where is the pivot? how does it stop? |
| **Flexible material** | cloth, banner, rope, hair, hanging lantern, talisman paper | bend · delay · oscillation · damping | what lags behind what? how long until it settles? |
| **Fluid / atmosphere** | water, mist, fog, cloud, rain, snow | flow · ripple · dispersion · propagation | where does it come from and go? does it propagate? |
| **Fire / smoke** | torch, brazier, burning effect | updraft · turbulence · expansion · dissipation | does it rise, flicker and thin out? |
| **Energy / magic** | qi, techniques, formations | source → gather → focus → release → propagate → impact → dissipate | where is the source? what gathers? what is left after? |
| **Camera** | follow, focus, impact response | focus · anticipation · impact · recovery | why is it moving? what should be noticed? how does it return? (§9) |
| **UI** | panels, prompts, rewards, warnings | attention · selection · confirmation · transition · hierarchy | what does the player's eye need, and in what order? (§11) |
| **World event** | weather, vein disturbance, sect conflict | before → during → after → consequence | was there a warning? what remains afterwards? (§10) |
| **Narrative moment** | story beat, reveal | world cause → warning → escalation → event → aftermath | which layers does THIS beat need — and which not? (§10) |

**M-2.2 — Do not invent visual logic from thin air.** When the right motion is unknown:
**STOP → REFERENCE → REASON → DESIGN → IMPLEMENT.** A random geometric approximation that merely
satisfies a state machine is a defect (the D-056 pass-2 "floating blue blob beside a motionless
figure" was exactly that). How to study references, and which ones, is
`XIANXIA_IDENTITY_CONTRACT.md` §3–§4.

---

## 3. Humanoid and creature motion at Aetheria's scale

**M-3.1 — The joint chain is continuous.** For a humanoid action the chain is
`feet → legs → pelvis → spine → shoulders → upper arm → elbow → forearm → wrist → hand`, and a
pose must preserve **joint continuity, balance, weight and intent** — a pose a real body could
hold. A palm strike reads as `stance → preparation → body shift → shoulder rotation → elbow
alignment → forearm extension → palm direction → release → follow-through → recovery`, at
whatever resolution the sprite allows. A pose built only to "look like a spell" is a defect.

**M-3.2 — At 32×48 top-down, the silhouette carries the motion.** The character is 2 tiles wide
(`CHARACTER_ART_BIBLE.md` §2), so most of the chain above is implied, not drawn. What CAN carry
it, and must: a silhouette change between key poses that reads at 1× · a 1px body shift for
weight · the limb that acts staying attached to the body that drives it.

**M-3.3 — Hard rules, each learned from a shipped defect (D-056):**
* **One limb does the whole gesture.** The arm that coils in the anticipation is the arm that
  strikes. (Pass 1 derived the arm from the sign of the thrust and swapped arms mid-action.)
* **No limb teleports.** A limb that moves is connected to its root on every frame — draw the
  bridging segment. (Pass 2 moved the forearm and left a gap to the shoulder.)
* **No T-pose, no circle-hand shortcut, no broken joints, no floating feet.**
* **Inspect magnified before shipping** (6× to 10×), then again at 1× in a real capture.

**M-3.4 — A creature moves like its species.** Weight sits where its anatomy puts it: the mist
wolf's lunge drives from the hindquarters, the head leads and the body follows. A creature is
never a humanoid template with a different sprite.

**M-3.5 — Movement during an action must read as intended.** The action layer out-ranks
locomotion, so a character that moves while acting slides in its action pose. That is legitimate
only when the action reads as a moving action (a stepping strike); a static pose sliding across
the floor is the floating-feet defect. Review it per action from P15 on (`CAST` is where a
casting stance must decide whether it roots the caster).

---

## 4. Timing grammar

**M-4.1 — Before → happening → result.** Important actions follow
`anticipation → action → consequence → recovery`. Not every action needs four drawn phases,
but the player must perceive a *before*, a *happening* and a *result*. Applies to attacks,
casts, boss attacks, heavy objects, doors, level-up, breakthrough and world events.

**M-4.2 — Gameplay timing owns the truth; presentation never lengthens it.** The duration of an
action is authored gameplay data (`AttackData` windup/active/recovery). Presentation derives its
frames from that lifecycle (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §3) and may not stretch an
action to fit an animation. If the animation needs more time, that is a gameplay-data decision,
argued as one.

**M-4.3 — Presentation never writes simulation time.** A held frame on impact (hit-stop) is
presentation holding ITS OWN pose and effects — never `Engine.time_scale`, never the physics
tick. The one-line Godot recipe for hit-stop slows the entire simulation, so the attack
lifecycle, AI and movement would run slower because an effect said so — and an authoritative
server could never honour it. **Guarded:** `tests/unit/presentation/test_motion_contract.gd`.

**M-4.4 — Response latency.** Input is acknowledged in the frame it lands: the action layer
starts on `attack_started`, the same frame the intent is accepted. A visual response is not an
authoritative result (§12).

**M-4.5 — Stillness is part of the animation.** A short hold after anticipation, or a brief
settle after impact, makes the release stronger. Do not force continuous motion.

**M-4.6 — Rhythm.** `calm → buildup → action → payoff → recovery → calm`. Constant flashing,
constant shake, constant particles or constant UI movement remove the contrast that makes
excitement legible; without contrast, excitement is noise.

**M-4.7 — Three scales of motion, never one intensity.**

| Scale | Examples | Intensity budget |
|---|---|---|
| **Micro** | breathing idle, cloth, leaves, small particles, UI feedback | subtle; never draws the eye on its own |
| **Mid** | walk, attack, NPC gesture, object interaction, combat VFX | readable at a glance; one focal point |
| **Macro** | boss entrance, storm, sect conflict, story reveal, **breakthrough** | may own the screen — rarely, and earned |

A level-up is **mid**; a realm breakthrough is **macro** — the two progression axes must not
look alike (`PROGRESSION_CULTIVATION_DESIGN.md` §1: level is getting better at fighting, a realm
is becoming a different kind of being).

**M-4.8 — Design for repeated viewing.** An action seen once may carry a flourish. An action seen
a hundred or a thousand times — the basic attack, a pickup, a menu toggle — must be readable,
short, unexhausting and quiet. Length is set by the gameplay loop, not by the animation's ambition.

---

## 5. The causal chain and layered feedback

**M-5.1 — Show CAUSE → EFFECT.** The player strikes → the body moves → the weapon or palm moves
→ impact → the target reacts → damage feedback → (if warranted) the world responds. "The enemy's
HP drops" with no sense that it was struck is a defect.

**M-5.2 — Eight possible layers; choose ENOUGH, not MOST.**

| Layer | Basic attack today | Note |
|---|---|---|
| 1. body animation | ✅ action layer (8-frame palm strike; 6-frame wolf lunge), D-057B redraw | the strike roots the striker: `AttackData.committed_move_scale` |
| 2. object motion | — | no weapon object exists yet |
| 3. VFX | ✅ D-057B: air released FROM the drawn palm (`palm` anchor), angled to body height, dissipating in recovery; a hostile wind-up telegraphs its reach on the ground | the player's own swing draws no ring (M-4.8) |
| 4. SFX | ❌ | audio is P26; the cue timing already exists (§9) |
| 5. camera response | — | **deliberately none**: a basic attack is seen a thousand times (M-4.8) |
| 6. target reaction | ✅ hit flash · corpse look · gauge · D-057B: RECOIL (creature) / PIVOT WOBBLE (rooted post) along the blow, contact flash + material debris (`HitReaction`) | a struck object warms (`flash_strength`) instead of bleeding |
| 7. UI feedback | ✅ target plaque, **Defeated** row | |
| 8. environment reaction | — | nothing in the world reacts to a basic attack, correctly |

**M-5.3 — Camera, effect, sound and body agree.** Every layer of one action derives from the
SAME lifecycle or cue, so they cannot disagree: the VFX follows the body's origin, the sound
lands on the active moment, a camera response lands on the impact. A camera shake 0.4s before
the impact is a defect, and it is structurally prevented by deriving all layers from the one
lifecycle rather than from separate clocks (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §3).

**M-5.4 — No desynchronized presentation clocks.** A presentation layer derives from the
semantic gameplay state or from an explicit cue. It may run a clock only for TRANSIENT feedback
that decides nothing (a flash's decay) — never a gameplay-like clock that could claim
"the attack is active" while gameplay is in recovery.

---

## 6. Attention and visual hierarchy

**M-6.1 — Priority, when several things happen at once:**

```
primary action > primary target reaction > secondary effect > ambient effect
```

**M-6.2 — Every moment names what the player sees FIRST, SECOND, and what stays PERIPHERAL.**
Mandatory for combat, boss, quest, story, world event and UI design reviews.

**M-6.3 — No effect hides its subject.** A particle burst may never cover the player, the enemy,
an important telegraph or the origin of a skill. Transient feedback modulates what is showing;
it does not cover it (the three-layer rule in `PRESENTATION_ARCHITECTURE_CONTRACT.md` §2).

**M-6.4 — Telegraphs are learned once** (`COMBAT_DESIGN.md` §7). A wind-up reads as a wind-up
everywhere; a telegraph is never re-used to mean something else, and no effect may be louder
than the telegraph it shares the screen with.

---

## 7. Curiosity, consequence and world memory

**M-7.1 — "What just happened — and what happens next?"** When a moment ends, the player has
enough information to understand it but not necessarily everything that follows. Curiosity comes
from **causal feedback, timing, world reaction and meaningful change** — partial reveal,
foreshadowing, an unusual event, a visible consequence, a character's reaction, new information,
escalation.

**M-7.2 — Curiosity is never manufactured.** Random flashing, random screen effects or constant
rewards are forbidden as excitement. Aetheria has a canon list of open questions kept for a
reason (`CANON_LEDGER.md` CL-15 — e.g. *why the Hoang Vực veins are failing now*):
presentation may FORESHADOW them through the world and must never answer them early.

**M-7.3 — The world remembers what happened.** Where it fits, consequence stays visible: combat
leaves a corpse and a changed target plaque · a world event leaves the environment changed · a
boss leaves the arena changed · a completed quest changes NPCs · a sect event changes banners
and behaviour. The world must feel like a system, not a sequence of disconnected screens.

---

## 8. Variation without chaos

**M-8.1 — Vary what repetition makes stale**: idle timing, breathing, leaf motion, particle
offset, reaction strength, small camera response, NPC idle gesture.

**M-8.2 — Variation is bounded, intentional, readable, and deterministic where it touches a test
or a capture** — a seeded or fixed pattern, never `randf()` in a test-critical path, and never a
draw from the domain RNG streams (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §14). Do not
randomize everything.

---

## 9. Camera and sound

**M-9.1 — Camera motion has semantics:** follow · focus · anticipate · pan · reveal · impact ·
shake · zoom · recovery. Each use answers: *why is the camera moving? what should the player
notice? how long? how strong? how does it return?*

**M-9.2 — Camera responses are proportional and earned.** A boss slam and a basic hit never get
the same reaction by default. **Shake is not decoration**: the default reaction to a hit is
none.

**M-9.3 — One owner per camera.** Today the map camera follows the player with smoothing inside
data-driven limits (`MapBase`, D-036); nothing else moves it. A future impact or reveal response
is presentation, driven by a cue, applied by that single owner — two systems writing the same
camera offset is a defect.

**M-9.4 — A top-down 2D camera frames; it does not change angle.** "Cinematic" in Aetheria means
position, hold, pan, zoom and timing — not isometric, three-quarter or close-up shots, which this
camera cannot take (see `XIANXIA_IDENTITY_CONTRACT.md` §4, `10_camera_story_moments`).

**M-9.5 — Sound is part of motion.** Every major action carries a design thought for animation
+ VFX + SFX together (heavy attack: anticipation → acceleration → impact → low strong sound →
brief reaction). No audio system exists until P26; the cue contract already carries the timing a
sound needs, so nothing has to be re-plumbed when it arrives.

---

## 10. Environment, world events and narrative moments

**M-10.1 — The environment has an ambient motion language, not a wallpaper.** External force →
material response → delay → propagation → damping. Wind reaches grass first and lightly, leaves
more strongly, branches slower. **Forbidden:** identical amplitude everywhere, identical timing
everywhere, synchronized loops — the "fake animated wallpaper".

**M-10.2 — Life, not noise.** Ambient motion is micro scale (M-4.7). A screen in which everything
moves has no place for the eye to rest and nothing to notice when something important moves.

**M-10.3 — A world event has before, during and after.** A storm: wind rises → leaves react →
clouds darken → the ambient sound changes → lightning → rain → aftermath. An event flag that
produces only a giant popup is a defect unless the popup is the intended presentation.

**M-10.4 — A narrative beat chooses its layers.** A beat may change pose, camera, lighting,
environment, particles, UI, sound and timing — and most beats need only one or two of them.

---

## 11. UI motion, and the HUD as presentation

**M-11.1 — UI motion has intent, direction, hierarchy, duration, ease and settle.** Not every
widget fades in and out over 0.2s by reflex. A transition exists to carry attention (what
changed, where to look next).

**M-11.2 — High-frequency UI is instant.** A panel the player toggles constantly opens without a
transition: a slide added to every toggle is latency paid a thousand times (M-4.8). Motion is
for state CHANGES that need attention — a level-up, a target acquired, a reward. Today the side
panels and the target plaque appear instantly, and that is correct.

**M-11.3 — The HUD frames the game; it does not cover it.** The composition rules — every
permanent element earns its screen space, composition before components, the weight ladder, and
the negative-space budgets — are owned by **`UI_UX_BIBLE.md` §3c** and enforced by tests there.
This contract requires that motion and feedback respect them: no effect, transition or
announcement may enter the playfield centre, and none may push the permanent HUD over its
budget.

**M-11.4 — The D-057 HUD correction, measured.** Found by opening real captures, not by tests:

| Defect | Before | After |
|---|---|---|
| Desktop "safe area" applied as a notch inset | left plaques **85px** from the edge, right plaques **18px**, top **50px** — the GNOME dock (66px) and top bar (32px) of an OS work area, applied although the window was wholly inside it; on Windows the taskbar would lift the prompts | **18px on every side**; desktop never insets, mobile insets only the part of the window a notch covers (`GameplayHUD.safe_area_insets`, tested) |
| Key prompts in a framed plaque | ~609×68, gold corners, the same weight as the identity plaque | **585×36 quiet band** (`HINT_BAND_ALPHA` 0.65 — a legal text surface even over pure white) |
| Bottom reserve | 78px, of which 32px reserved nothing | **54px** (strip + one margin), bounded from above by a test; the side panels gained 24px — the vi sect panel no longer clips its resources line at 720p |
| Defeated target | an empty row between the name and the gauge for the whole linger | the row states **Defeated / Đã hạ gục** — the consequence, where the player is looking |
| Permanent HUD occupancy | **16.5%** of 1280×720 | **14.3%** (12.9% at 1280×800) |

**M-11.5 — The full-screen reality check.** A HUD or layout change is never passed on a unit,
state or rectangle test alone. Capture vi/en × 1280×720 / 1280×800 with `tools/capture_ui.gd`
and LOOK, judging visual density, playfield occupancy, motion readability, silhouette, effects,
UI collision, negative space and focus (`PHASE_EXECUTION_PROTOCOL.md` §9).

---

## 12. Multiplayer compatibility

**M-12.1 — Every major presentation event must be renderable from an authoritative event.**

```
CLIENT INTENT → SERVER AUTHORITY → AUTHORITATIVE RESULT → PRESENTATION CUE → CLIENT PRESENTATION
```

Future authoritative events the presentation must be able to render from: character attack
started · attack hit · damaged · defeated · level up · world event started / resolved. Each
carries semantic facts (who, what, which phase, sequence), never a node.

**M-12.2 — Nothing visual is authoritative state.** No `SpriteFrames`, `Texture`,
`AnimationPlayer`, UI node or VFX node ever enters domain or authoritative state.

**M-12.3 — Prediction is presentation only.** A client may later play an anticipation before the
server answers; that is not authority, and a rejected command must cancel it cleanly
(`end_action()` is that path today).

---

## 13. Design deliberation (mandatory for every major visual feature)

Written before code, in the feature's `DECISIONS.md` entry or change description — "small" is
not an exemption:

```
1. What is happening?                     6. What are the key poses / stages?
2. What causes it?                        7. What is the timing (and who owns it)?
3. What should the player notice first?   8. What is the consequence?
4. What is moving?                        9. What is the recovery / settle?
5. Which governing law applies? (§2)     10. What will be reused later, and by whom?
```

Paired, for any feature with an Aetheria-specific look, with the Reference → Original note
(`XIANXIA_IDENTITY_CONTRACT.md` §13).

---

## 14. Reuse and the second-use rule

**M-14.1 — Reuse lives in contracts, not in a manager:** the semantic action, the motion
vocabulary, the presentation cue, the profile/data, the timing contract and the layer contract.
One motion principle may have many consumers — `CAST` serves the player, an NPC, an enemy, a boss,
a pet and a remote player through different profiles; a WIND principle could serve grass, trees,
cloth, lanterns and fog through different response profiles.

**M-14.2 — The second-use rule.** A new abstraction requires **use case A + a real CURRENT use
case B** (player attack + enemy attack; tree wind + banner wind). Without B, do not create the
abstraction yet. A future consumer is not a second use — which is why the shared
progression-celebration seam waits for breakthrough (§20).

**M-14.3 — No copy-paste per actor.** `player_attack.gd`, `enemy_attack.gd`, `boss_attack.gd`
are forbidden; semantic action + profile + asset is the shape.

**M-14.4 — Never created:** `UniversalAnimationManager`, `UniversalVisualManager`,
`XianxiaEffectManager`, `GlobalMotionManager`, `PresentationSingleton` — nor any of the
frameworks already listed in `PRESENTATION_ARCHITECTURE_CONTRACT.md` §15.

---

## 15. Quality is not quantity

**M-15.1 — Frame count is not quality.** Six good frames beat twenty bad ones. Judge pose,
timing, spacing, silhouette, weight, anticipation, follow-through, clarity and intent.

**M-15.2 — VFX is not quality.** More particles, more glow, more flash, more colours or more
shake never raise quality. Quality is the right effect, in the right place, at the right time,
scale, duration and hierarchy.

---

## 16. Evidence and acceptance

**M-16.1 — Three kinds of evidence, never confused:**

| Evidence | Proves | Does not prove |
|---|---|---|
| **STATE** — a test reads a variable, a signal, a column | the logic ran | that anything was drawn, or drawn well |
| **PIXEL** — a real capture, opened and inspected | what is on screen | why, or that it holds at other frames |
| **REFERENCE** — a reference board (`XIANXIA_IDENTITY_CONTRACT.md` §11) | the design intent and its research basis | anything about the build |

**M-16.2 — Tests assert relationships, not flags.** Test semantic state, presentation state, the
timing relationship between them, cancellation, cleanup, profile resolution, reuse across actors,
missing-asset handling and the deterministic path. `state == true → PASS` for an animation whose
capture looks wrong is not a test of the animation.

**M-16.3 — The player-experience test.** For every major presentation feature: *what did the
player do? what happened? what did they feel? what did they understand? what do they expect
next?* No answer → redesign.

**M-16.4 — The "would a player notice?" test.** Look at the screen as someone who has never read
the code: can they tell what happened, why, and where? anticipate the danger? recognise the
reward? see the consequence?

**M-16.5 — DONE means all of:** implementation · player readability · visual quality · timing
coherence · composition · performance · reuse. Compiling, passing tests and changing animation
state are necessary and not sufficient.

---

## 17. The anti-dead-game rule

Aetheria avoids: static characters · a static environment · instant state changes · popup-driven
feedback · identical loops everywhere · an empty world · UI covering the game · effects without
causality.

Aetheria aims for: a world with life · actions with weight · events with consequence ·
characters with personality · combat with rhythm · progression with celebration · world changes
that feel meaningful.

**Honest status at D-057:** combat has a causal chain end to end (§1) and the HUD frames the
game instead of covering it (§11). The world itself is still mostly static — no ambient motion,
no world-event presentation — and progression celebration is below its bar (§20). Those are
owned by the phases in §18, not deferred to Phase 25.

---

## 18. Phase seeding

The per-phase presentation seeds live in **one** place, `docs/ROADMAP.md` (Continuous Visual
Integration), and are not restated here. D-057 sharpened four of them there: the P12
breakthrough seam is also the level-up's second consumer (§20); P15 `CAST` is ONE action whose
lifecycle has phases, not four actions; camera responses arrive with the phase that first needs
one; and which reference categories each phase studies is `XIANXIA_IDENTITY_CONTRACT.md` §12.
Presentation does not begin at P25.

---

## 19. Final self-critique (run before calling a visual feature done)

```
 1. Does this motion have a cause?
 2. Does it obey the right law — organic, rigid, flexible, fluid, energy, UI, camera? (§2)
 3. Does it look believable from THIS camera?
 4. Does the player understand what happened?
 5. Does the timing read as anticipation → action → consequence?
 6. Does the action have weight?
 7. Is anything louder than it should be?
 8. Is the VFX supporting the subject or hiding it?
 9. Is the environment alive without being noisy?
10. Does the screen breathe?
11. Is the HUD occupying too much of the game? (UI_UX_BIBLE §3c)
12. Would a player enjoy seeing this a hundred times?
13. Is there variation where repetition goes stale?
14. Is there stillness where constant motion would be noise?
15. Does this moment make the player wonder what happens next?
16. Is that curiosity caused by meaningful information, not random spectacle?
17. Can another actor reuse this presentation logic?
18. Can a future multiplayer client render it from an authoritative event?
19. Did we add unnecessary framework?
20. Did we measure and inspect the actual screen?
```

And the Aetheria identity review that follows it: `XIANXIA_IDENTITY_CONTRACT.md` §15.

---

## 20. Known presentation debt (named, owned, not hidden)

| Debt | Why it is debt | Owner |
|---|---|---|
| **Level-up is below its own bar.** `PRESENTATION_ARCHITECTURE_CONTRACT.md` §9 requires recognition → buildup → light/vertical effect → **character response** → result; today it is a badge flash and a banner, and the character does not react. | It is a mid-scale celebration with no body. | **P12.** The breakthrough presentation seam is the level-up's second consumer (M-14.2), so the shared progression-celebration seam is built there — at a larger scale for breakthrough, smaller for level-up, never the same look (M-4.7). |
| ~~**No physical hit reaction.**~~ **Closed by D-057B.** `HurtboxComponent.damaged` now carries `push_direction` (an explicit cue-contract change); `HitReaction` recoils the VISUAL (never the body) or wobbles a rooted object, and draws the impact. | — | — |
| **No death animation.** A corpse is a tint, not a fall. | `COMBAT_DESIGN.md` §10b already names it. | The phase that owns combat VFX (P15/P26). |
| **No world-event presentation.** Ambient motion exists since D-057B (grass, canopy, banner cloth, hanging lanterns, low mist — one `pixel_sway` law with per-material data, phase from world position, a travelling gust); world EVENTS still only show as a plaque line. | §10 / §17. | P17 (NPC idle/variation), P20/P21 (world and environmental events), weather with its first consumer. P12 breakthrough and the P15 Phong technique are the first two consumers of a wind IMPULSE (M-14.2). |
| **No audio.** | M-9.5. | P26. |

---

## 21. What this contract does NOT do

It starts no phase and adds no gameplay system, no skill, cultivation, NPC, quest or story logic,
no networking, no autoload and no presentation framework. It does not override the art or UI
bibles, the presentation architecture contract, or canon. Discovering presentation debt is never
a licence to open Phase 12 or any later system early: the debt is recorded (§20) and owned by its
phase.
