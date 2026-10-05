# COMBAT_DESIGN — Aetheria

> **Owner of:** combat identity, the weapon families, the elemental/status vocabulary, build
> identity, boss/telegraph grammar.
> **NOT the owner of the damage formula** — that lives ONLY in `docs/DATA_SCHEMA.md` and is
> referenced, never restated here (one rule, one owner).
> Realm/technique semantics: `docs/PROGRESSION_CULTIVATION_DESIGN.md`. Phases 09/10/15 implement.

---

## 0. CURRENT STATUS — design vs. implementation (D-051)

This document is the **frozen DESIGN** for the full combat system. Most of it is not built yet,
and that is normal — but "not built yet" has to be said per item, not as a blanket claim. The
header used to read *"Nothing here is implemented. Combat today exists only as the Phase-02
sandbox."*, which stopped being true the moment Phase 09 shipped and then stayed on the page.

Read every section below as DESIGN. What exists in the build is only this:

**IMPLEMENTED (Phase 09, D-007):**
- Real-time action resolution with the `READY → WINDUP → ACTIVE → RECOVERY → READY` lifecycle
  (`AttackStateMachine`, pure domain, exact-delta tested).
- Timing, reach, arc, power and crit authored as **data** (`AttackData` → `data/combat/*.tres`).
- Hit resolution against the **ANALYTIC HURTBOX MODEL** (§10a) — not Area2D sensors.
- One damage formula, still owned by `DATA_SCHEMA.md`, now including power and crit multipliers.
- Crit rolled from the **seeded** `RngService.STREAM_COMBAT` (§10).
- `CombatRuntime` as a per-session subsystem; a real target (the training post) in the hub.
- A player health gauge on the D-050 UI foundation.

**IMPLEMENTED (Phase 10):** enemy AI — see `§7` for the grammar it implements and
`DECISIONS.md` for what it deliberately does not do yet. Plus both halves of combat
feedback — `AttackFeedback` (the swing you make) and `DamageFeedback` (the hit you take, and
the corpse) — which **clears the §10b presentation debt**.

**NOT IMPLEMENTED (design only, owned by a later phase):** the defensive-action model
(dodge/parry/block, §2 — still NOT frozen, §11) · combo logic and cancels · control/stagger ·
status effects and the element/resistance sets (§3) · weapon families (§4) · technique ×
weapon compatibility (§5) · build identity (§6) · boss grammar and phases (§8) · the linh khí
resource model (§9) · projectiles · environmental interaction.

A section carrying no marker above is DESIGN, not a description of the build.

---

## 1. The three questions combat must answer

Combat design is judged against time, not against a feature list.

| Horizon | What must be fun | Mechanism |
|---|---|---|
| **Hour 1** | moving and hitting feels good; threats are readable | clear verbs, honest telegraphs, immediate feedback |
| **Hour 20** | *my build* is mine; encounters ask different questions | weapon × technique interactions, status/element play, enemy variety |
| **Hour 100** | the same fight means something new at a higher realm | realm changes capability (not just numbers); mastery of combinations; boss mechanics that test learned language |

If an addition does not improve one of these three, it is decoration.

## 2. Combat verbs (the vocabulary, frozen)

Every encounter is built from these. Adding a verb is a design change (`DECISIONS.md`); adding
*content* that uses them is data.

**basic attack** *(implemented, Phase 09)* · **movement** *(implemented; reposition is a real
defensive option, and under the real-time model D-007 chose it is currently the ONLY defensive
option)* · **defensive action** *(design only — the dodge/parry/block model is still NOT frozen,
§11; D-007 settled the TIMING model, not this)* · **combo logic** ·
**telegraph reading** · **control/stagger** · **resource management** (linh khí) ·
**status effects** · **technique interaction** · **environmental interaction**.

**Explicitly rejected: damage-spam.** A fight whose optimal play is "press attack until it dies"
has no skill expression, and at hour 100 it has nothing left to give.

## 3. Element and status vocabulary (frozen, closed sets)

Closed so content can rely on them and UI can give each one a permanent colour/icon
(`UI_UX_BIBLE.md` §4).

**Elements:** `elem_hoa` **Hỏa** (fire) · `elem_thuy` **Thủy** (water) · `elem_phong` **Phong**
(wind) · `elem_loi` **Lôi** (lightning).
**Statuses:** `status_choang` **Choáng** (stagger/stun) · `status_doc` **Độc** (poison/decay) ·
`status_hu` **Hư** (weaken/hollow) · `status_thieu_dot` **Thiêu Đốt** (burn/DoT) ·
`status_hut_phap` **Hút Pháp** (qi drain).

Each element has an identity beyond a damage type: Hỏa trades sustained pressure (Thiêu Đốt) for
burst, Thủy controls and cleanses, Phong buys mobility and repositioning, Lôi buys interruption
(Choáng). **Elements are not a rock-paper-scissors chart** — a chart makes gear selection a lookup
instead of a decision.

## 4. Weapon families (CL-10)

Each family must have a genuine gameplay identity. **Forbidden: same attack, different damage
number.**

| Family | Role | Range | Mobility | Control | Identity | Later PvP niche |
|---|---|---|---|---|---|---|
| **Kiếm** (sword) | precise, defensive counter | short | medium | medium | the technique weapon: rewards timing and counters; the orthodox icon | duelist |
| **Đao** (sabre) | aggressive pressure | short | medium | low | commits to offence; momentum-based; punishes hesitation | bruiser |
| **Thương** (spear) | spacing and denial | mid | low-med | high | owns a zone; best at controlling where the fight happens | zoner |
| **Cung** (bow) | positional damage | long | high | low | must keep distance; fragile when caught | skirmisher |
| **Pháp Trượng** (staff/implement) | technique amplification | varies | low | high | the least physical; multiplies technique and status play | caster/support |

**Orthodox vs forbidden within one family** is where social consequence meets build choice. Worked
example (sword):

| | Orthodox sword | Cấm Pháp sword |
|---|---|---|
| Behaviour | stable, precise, defensive counter | unstable, stronger burst |
| Cost | none beyond resources | a self-cost paid from body/soul |
| Social | accepted everywhere | visible; reputation and sect consequences |
| Long term | predictable | a worsening condition to manage |

Both are viable. Neither is strictly better — that is the design requirement (see
`PROGRESSION_CULTIVATION_DESIGN.md` §5).

## 5. Technique × weapon compatibility

Compatibility is authored per technique (`TechniqueData.weapon_compatibility`), and
**incompatibility is equally first-class**. Rules:

1. A technique names which families it supports; an unsupported pairing is either unusable or
   usable at a stated penalty (authored, not silent).
2. Some technique *pairs* conflict (a body-tempering art and a soul-hollowing art are not
   compatible in one body). The conflict must be visible before commitment.
3. A technique that works equally with everything has no identity and should be rejected in
   content review.

## 6. Build identity

```
WEAPON × TECHNIQUE × SKILLS × EQUIPMENT × CULTIVATION PATH × PET × PLAYER CHOICES
```

A build is an *emergent* intersection, not a selected class. The design requirement is **real
tradeoffs**: every build must be clearly better at something and clearly worse at something else.
A build with no weakness is a balance bug.

**Equipment must not become the whole build.** Gear modifies; technique and cultivation define.
The failure state to avoid is the gear-score game, where the answer to every problem is "find a
bigger number" — that is also why Knowledge exists as a separate progression concept.

## 7. Enemy and encounter grammar

- **Telegraph language is global and learned once.** A wind-up reads as a wind-up everywhere. A
  new enemy may introduce a new telegraph, but may not re-use an existing telegraph to mean
  something different — that is a betrayal of learned language, not difficulty.
- **Encounter variety comes from the question asked**, not from HP: one enemy that punishes
  standing still, one that punishes approaching, one that must be interrupted, one that must be
  out-sustained.
- **Enemies are data** (`EnemyData`, Phase 10) with controlled AI tick rate
  (`05-performance-testing.md`). Adding an enemy is data.
- **Realm matters in encounters.** A fight against a higher-realm enemy should feel like a
  different *category* of problem, and winning it must use one of the named legitimate reasons
  (`WORLD_BIBLE.md` §5) — preparation, terrain, matchup, a price paid — never a stat check the
  player passes by grinding.

## 8. Boss grammar

Every major boss defines: **story identity** (who they are and why this fight exists) ·
**relation to the chapter** · **combat identity** (the one thing this fight is about) ·
**telegraph language** (reusing the global vocabulary) · **phases** · **escalation** ·
**reward identity** · **post-boss consequence** (the world changes).

**A boss tests mechanics introduced earlier in its chapter.** A boss that demands a mechanic the
player was never taught is unfair; a boss that demands nothing is filler. The fight is the exam
for that chapter's lesson.

## 9. Resource model

Linh khí is the combat/skill resource (`02-game-design.md` glossary). Design requirements: it must
be *spendable into a decision* (not a passive refill), techniques shape its behaviour
(regeneration, cost curves, conversion), and running dry must be a survivable tactical state
rather than an instant loss.

## 10. Dependencies and determinism

- Combat (09) needs: Character (04, done) for stats, `DATA_SCHEMA.md` for the formula, and a
  **seeded RNG** source.
- **RNG OWNERSHIP, corrected (D-051).** This section used to say combat "is the likely first
  caller, so per C-010 it must introduce the seeded seam in its own phase". That prediction was
  overtaken: **Phase 08 (World Simulation) introduced the seam** (`RngService` + `RngStream`,
  D-040/C-010), and **Phase 09 combat CONSUMES it** via `RngService.STREAM_COMBAT`. Combat
  introduced no RNG architecture of its own, and must not. The properties that matter and are
  preserved:
  - **one seed per run/world** — the world seed is the world's identity, so a save names exactly
    one. Combat does NOT hold a second seed.
  - **subsystem-scoped streams** — `derive_state(world_seed, stream_id)` makes streams START
    independently, so a combat roll can never shift the simulation's sequence, and a run where
    the player fought evolves the same world as one where they did not.
  - **deterministic + injectable** — `CombatService` is handed its stream and refuses to work
    without one; it never constructs a generator. That is what makes combat unit-testable.
  - **replayable** — one draw per HIT (never per candidate), asserted, so where the player
    stands cannot change the dice.
  - **no global `rand*()`** anywhere, including AI (Phase 10 draws from its own stream).
  - **save-compatible** — `RngService.to_dict()` records the seed AND each stream's position,
    because a seed alone only reproduces a run from the beginning (`SAVE_FORMAT.md` §3b).
- Combat emits events only (`hit`, `damaged`, `enemy_died`, `xp_gained`) and knows nothing about
  UI, quests or save (`GAME_FLOW.md` §3.7). That is what lets Progression, Quest and Economy
  consume it later without coupling.
- The **combat command** is the multiplayer seam: an explicit, serializable *intent*, never a
  direct mutation from UI (`MULTIPLAYER_PLAN.md` §3).
- Determinism: same inputs + same seed → same outcome. Required for tests now and for any
  authoritative model later.

## 10a. The ANALYTIC HURTBOX MODEL (implemented, Phase 09 — D-007)

Aetheria resolves hits **analytically**, and this is a named model rather than an implementation
detail, because the terminology invites the wrong thing:

```
AttackComponent          (gameplay: owns the lifecycle, asks for a resolution)
  → CombatHurtboxRegistry (gameplay: who can be hit right now, id-sorted)
  → CombatService         (domain: reach + arc test, crit roll, per-target filter)
  → DamageRules           (domain: the one formula)
  → HurtboxComponent      (gameplay: applies the hit through the entity's own take_damage)
```

**There are no `Area2D` sensors, and there are no `HITBOX`/`HURTBOX` collision-layer bits.**
`HurtboxComponent` is a plain `Node`. A target is a **point plus a radius**; an attack is a
**reach plus an arc** centred on the attacker's facing.

Why, in the order the reasons actually mattered:
1. **Deterministic headless testing.** In the headless `-s` runner an Area2D overlap does not
   fire reliably (L-016, L-017 — the two costliest lessons in this repository). A combat system
   that detected hits that way could not be tested end to end, so "does my attack damage the
   target" would be answerable only by a human watching a window.
2. **Reliable E2E.** The world E2E drives a real attack key and asserts the target LOST HP. That
   assertion is only possible because resolution does not wait on a physics tick.
3. **Controlled performance.** No Area2D per attack and no physics query per swing; the hit
   window opens and closes with the state machine. Cost is a cheap linear broad-phase scan,
   measured at ~0.42 µs per candidate (PERF-002).
4. **Future authoritative multiplayer.** Resolution is a pure function of (attacker transform,
   `AttackData`, target records). A server can run it with no scene, which a physics-sensor
   model cannot promise.
5. **Sufficient accuracy.** On a 16px grid with 32×48 characters, point+radius versus polygon is
   not a distinction a player can perceive.

**Do NOT revert to `Area2D` merely to match the words "hitbox/hurtbox".** The terminology is
kept because it names the ROLES correctly; the implementation is deliberate. Add shape-accurate
overlap the day something genuinely needs it (a swept projectile, a terrain-shaped AoE) —
together with its consumer, and without taking the analytic path away from everything else.

## 10b. COMBAT PRESENTATION DEBT (recorded by the D-051 audit — CLEARED in Phase 10)

**STATUS: CLEARED in Phase 10 (both halves). Kept here as the record of what was wrong and
what now renders it, because the debt is what explains the shape of the fix.**

What the D-051 audit found: the four lifecycle states were **not visually distinguishable**.
Pressing attack produced no swing, no flash, no impact and no recovery pause the player could
see — only a health number changing on the target. The state machine was correct and invisible.

Consequence per §1 ("Hour 1: moving and hitting feels good; threats are readable") and the
§7 rule that telegraph language is global and learned once: a telegraph the player cannot see
is not a telegraph. **That was DEBT, not a design change** — the design in §2/§7 already
required readable timing; the build simply did not render it.

Cleared by two restrained presentation nodes, both pure presentation (they decide nothing,
resolve nothing, and deleting either changes no outcome), both idle-free (`_process` off until
there is something to show), and both drawing every colour from `UIPalette` so combat feedback
cannot drift from the game's palette:

| Node | Half | What it renders |
|---|---|---|
| `AttackFeedback` | the swing you MAKE | one arc whose radius, width and alpha distinguish WINDUP (gathering, dim, growing) from ACTIVE (bright, full reach, thickest — the only phase that can land) from RECOVERY (fading at full reach, so the cost of having swung is visible). Derived from the state machine's own remaining time, never a clock of its own. |
| `DamageFeedback` | the hit you TAKE | a short decaying tint on the entity that was damaged — crimson normally, brighter gold on a crit (`damaged` carries `is_critical` for exactly this) — plus the corpse look once it dies. It owns the entity's `modulate` channel entirely. |

No particles, no shaders, no tweens, no VFX framework. The remaining presentation gap is a
death ANIMATION and impact particles, which belong to whichever phase owns combat VFX; a
dimmed, cooled, slightly translucent body is the minimum that distinguishes a corpse from a
live creature.

Two traps worth not repeating, both found by LOOKING at playtest captures rather than by any
assertion:
- A corpse tint has to be **measured against the worst (sprite, floor-tile) pair**, and it took
  three values to get there. The shipped tint and the first correction both landed the corpse
  within 0.014 luminance of the floor — invisible to brightness alone, so the first correction
  only looked better because it was blue against green and the whole signal rested on hue. The
  second correction then passed when scored against the floor's MEAN and failed at 0.082 the
  moment the test measured PER FILL TILE, on the pale player over the dimmest moss. Averaging a
  background averages away the case that breaks. The mark now carries on both axes: at least
  0.12 of luminance below every fill tile, plus the blue shift.
- A **time-limited** effect cannot be proven by a screenshot taken at an arbitrary frame. The
  flash lasts 0.16s; on a frame-starved run the capture named `08_attack` showed an untouched
  target. `tools/playtest_flow.gd` now REPORTS whether the shot caught the flash instead of
  leaving the reader to assume it did.

## 11. Explicitly NOT frozen

The defensive-action model (dodge/parry/block) · damage numbers · HP · cooldowns · stagger
thresholds · status durations · AI tick rates. Frozen: the verbs, the families, the
element/status sets, build philosophy, telegraph and boss grammar.

**Resolved since this list was written:** real-time vs turn-based resolution — **D-007 is
ACCEPTED as REAL-TIME TOP-DOWN ACTION COMBAT** (2026-10-05, Phase 09), with the lifecycle
`READY → WINDUP → ACTIVE → RECOVERY → READY`. It settled the TIMING model only; the
defensive-action model above remains unfrozen, and enemy AI, combo/cancel, status/resistance
and projectiles remain future scope owned by their own phases.
