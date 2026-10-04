# COMBAT_DESIGN — Aetheria

> **Owner of:** combat identity, the weapon families, the elemental/status vocabulary, build
> identity, boss/telegraph grammar.
> **NOT the owner of the damage formula** — that lives ONLY in `docs/DATA_SCHEMA.md` and is
> referenced, never restated here (one rule, one owner).
> Realm/technique semantics: `docs/PROGRESSION_CULTIVATION_DESIGN.md`. Phases 09/10/15 implement.
> **Nothing here is implemented.** Combat today exists only as the Phase-02 sandbox.

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

**basic attack** · **movement** (reposition is a real defensive option) · **defensive action**
(the chosen model is Phase-09's call — D-007 — but one must exist) · **combo logic** ·
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
  **seeded RNG** source. Combat is the likely first caller, so per C-010 it must introduce the
  seeded seam in its own phase and must never call a global `rand*()`.
- Combat emits events only (`hit`, `damaged`, `enemy_died`, `xp_gained`) and knows nothing about
  UI, quests or save (`GAME_FLOW.md` §3.7). That is what lets Progression, Quest and Economy
  consume it later without coupling.
- The **combat command** is the multiplayer seam: an explicit, serializable *intent*, never a
  direct mutation from UI (`MULTIPLAYER_PLAN.md` §3).
- Determinism: same inputs + same seed → same outcome. Required for tests now and for any
  authoritative model later.

## 11. Explicitly NOT frozen

Real-time vs turn-based resolution (**D-007, open — decided in Phase 09**) · the defensive-action
model (dodge/parry/block) · damage numbers · HP · cooldowns · stagger thresholds · status
durations · AI tick rates. Frozen: the verbs, the families, the element/status sets, build
philosophy, telegraph and boss grammar.
