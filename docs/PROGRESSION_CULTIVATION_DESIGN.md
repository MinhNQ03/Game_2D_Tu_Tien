# PROGRESSION_CULTIVATION_DESIGN — Aetheria

> **Owner of:** the realm hierarchy's semantics, the nine-layer principle, the level≠realm
> contract, the master realm table, cultivation paths, the technique MODEL, and Knowledge as a
> third progression concept.
> Frozen names: `docs/CANON_LEDGER.md` CL-02/03/13/14. Combat identity: `docs/COMBAT_DESIGN.md`.
> Phase 11 implements level/XP; Phase 12 implements cultivation. **Nothing here is implemented.**

---

## 1. Two axes, never one number

Carried forward from `.kiro/steering/02-game-design.md` (binding) and re-frozen:

| | **LEVEL / XP** | **CẢNH GIỚI / TU LUYỆN** |
|---|---|---|
| Grain | fine, frequent | chunky, rare |
| Source | combat, activity | deliberate cultivation + breakthrough |
| Gives | smooth incremental power | **capability and access** |
| Gates content? | **NEVER** | yes — this is its job |
| Feels like | getting better at fighting | becoming a different kind of being |

**Why they must not merge.** One number cannot do both jobs: if realms give smooth power they
stop being thresholds, and if levels gate content the realms become decoration (C-002). Keeping
them separate is also what lets the game be generous with levels (frequent, satisfying) while
being strict with realms (rare, meaningful).

**The two hard rules:**
1. **Level never appears in an access condition.** Not for maps, dungeons, worlds, quests,
   techniques or dialogue. Where a number is needed to communicate *difficulty*, that is a
   **threat rating** (§6) — advisory, not permission.
2. **A realm advance must always answer "what can I do now that I could not before?"** with
   something other than a bigger number. If a proposed realm step cannot answer it, the step is
   wrong.

## 2. The hierarchy (CL-02)

```
PHÀM            →  HẬU THIÊN 1-9  →  TIÊN THIÊN 1-9  →  NGỰ THIÊN 1-9  →  TRỌNG THIÊN 1-9
(mortal)           (acquired)         (innate)           (commanding)       (layered)
                                                                                 ↓
                                                              THÁI THIÊN  →  VÔ THIÊN
                                                              (structural only)
```

**Why these five and not the conventional ladder.** The conventional Luyện Khí → Trúc Cơ → Kim
Đan sequence names *stages of an internal process*, which makes every tier an internal-plumbing
upgrade and gives the designer nothing to hang world access on. Aetheria's ladder instead names
**an expanding relationship with Heaven/world-law** — acquired, innate, commanding, layered —
so each macro realm has a natural, non-numeric meaning and a natural social consequence. It is
also original (C-001), memorable, visually distinguishable, and open-ended at the top.

| Realm | What changed | Social fact |
|---|---|---|
| **PHÀM** | nothing; the baseline the world is built for | a person |
| **HẬU THIÊN** | the body has been opened and refined **by effort** | a cultivator; can be allocated vein access |
| **TIÊN THIÊN** | qi is **self-sustaining**; no longer dependent on constant input | a *real* cultivator; sects compete for you |
| **NGỰ THIÊN** | authority over an **external** domain (a vein, a place, a law of a place) | a regional power; the covenant must account for you |
| **TRỌNG THIÊN** | interaction with **world law itself** | a world-scale actor; politics is now between peers |
| **THÁI THIÊN** | structural: the tier where world-scale ceases to be the unit | — |
| **VÔ THIÊN** | structural: the horizon | — |

**Design depth by tier (deliberate, per the brief's §10):** Hậu Thiên and Tiên Thiên are detailed
and content-ready. Ngự Thiên is structurally detailed enough to plan roadmap content against.
Trọng Thiên has meaning, purpose and broad capabilities but **no ability list**. Thái Thiên and
Vô Thiên have narrative purpose only. Writing hundreds of endgame abilities now would be fiction,
not design.

## 3. The nine layers (CL-03)

Inside every numbered realm the layers mean the same KIND of thing, so the player learns the
shape once and can read it forever:

| Layer | Name | What it is |
|---|---|---|
| 1 | **Foundation** | the realm's new capability exists but is unreliable |
| 2 | **Expansion** | capacity grows; the capability becomes usable in practice |
| 3 | **Mastery** | reliable, efficient, no longer requires full attention |
| 4 | **Transformation** | the capability changes *kind* rather than degree |
| 5 | **Consolidation** | stabilised; the body/soul adapts to carry it permanently |
| 6 | **Manifestation** | becomes externally visible — others can *see* what you are |
| 7 | **ĐẠO CƠ** (Dao seed) | **the player's personal Dao forms** — the build-defining layer |
| 8 | **World Touch** | the capability begins to affect the environment, not just the self |
| 9 | **Threshold** | the edge; the next macro realm becomes attemptable |

**Layers 7 and 9 must always change what the player can DO.** Layer 7 is where the cultivation
path (§5), techniques known, and accumulated choices crystallise into something personal and
mechanically expressive — it is the main build moment inside a realm. Layer 9 is the gate.

Layers 1–6 and 8 may legitimately be *mostly* incremental, but each must still move at least one
non-damage dimension (perception range, qi efficiency, a technique slot, a social reaction).
**Nine layers of "+10% damage" is explicitly forbidden** — that is nine wasted thresholds.

## 4. What a realm changes (the capability contract)

A realm advance moves these dimensions, not just stats. Content and systems may read any of them;
they may not read level for access.

combat capability · movement/traversal · perception · technique availability · technique
combination limits · which cultivation methods are survivable · lifespan · social authority ·
eligible sect rank · territory access · map access · dungeon access · **world access** · economic
opportunities (what you may buy, be sold, or be trusted with) · NPC reactions · quest
availability · narrative possibilities.

**Worked example — HẬU THIÊN 9 → TIÊN THIÊN 1.** Qi becomes self-sustaining, so: the player can
remain in low-qi environments that previously forced retreat (traversal + map access); they can
hold a technique between encounters (combat); sects begin to court rather than test them (social,
quest); merchants extend credit (economy); and the covenant's survey now lists them (world). Not
one of those is a damage number, and all of them are legible to the player as "I am a different
thing now".

## 5. Cultivation paths (data-driven, not classes)

Paths are **authored data** the player accumulates into, never a class picked at creation and
never a hard-coded branch. Lore permits combination where the paths are compatible; incompatible
combinations have real costs rather than being silently disallowed.

| Path | Character | Costs |
|---|---|---|
| **CHÍNH ĐẠO** (orthodox) | stable, institutionally supported, allocated resources | a ceiling; obligations |
| **TÁN TU** (rogue) | flexible, independent, no permission needed | resource-starved; no protection |
| **CẤM PHÁP** (forbidden) | faster, stronger, opens otherwise-closed doors | physical price + social cost (CL-01) |
| **THỂ TU** (body) | endurance, close combat, physical resilience | slower perception/technique growth |
| **THẦN TU** (spirit/soul) | perception, control, spiritual interaction | fragile body |
| **PHÁP TU** (technique/art) | specialisation, unusual technique combinations | narrow; dependent on knowledge |

**The forbidden path must never be simply "damage ×2"** — that would make the moral/social
dimension a tax on an obvious upgrade. Cấm Pháp trades a **permanent, visible, mechanical price**
(body/soul cost, instability, a condition that worsens) for access and speed, and the social
consequence is a *second* cost on top. A player should be able to look at a Cấm Pháp technique and
genuinely hesitate.

## 6. Threat rating (replaces level gating)

Because level may not gate (§1), the game still needs to tell the player "this will kill you".
That is a **threat rating**: an advisory label expressed in the realm vocabulary, e.g.
*"Hậu Thiên 4–6"*. It appears on maps, dungeons and bosses, it is derived from authored content
difficulty, and it is **tunable balance data, not canon** (`CANON_LEDGER.md` change control).

The player may always *enter* at their own risk where the layered access gate permits
(`MAP_DUNGEON_DESIGN.md` §3). Advisory, not permission — this preserves the possibility of a
prepared, clever down-realm victory (`WORLD_BIBLE.md` §5).

## 7. KNOWLEDGE (TRI THỨC) — the third progression concept (CL-14)

Knowledge is **not** XP and **not** a realm. It is a serializable record of what the player has
LEARNED: a discovered text, an understood mechanism, a translated record, a witnessed event, a
technique's true cost.

**Why it is a separate concept.** Without it, every lock in the game has to be opened with power,
and the game can only reward the player with bigger numbers. With it, Aetheria can deliver the
line the brief asks for — *"I learned something"* — as a real progression event. It is also what
makes the central mystery playable: the Thiên Khế cannot be defeated by strength, only understood.

Knowledge may gate: hidden techniques · world gates · historical information · dialogue options ·
sect secrets · **alternate quest solutions** · crafting methods · breakthrough prerequisites ·
forbidden paths · hidden maps.

Design rules:
- Knowledge is **discrete and named** (ids), never a score. "Knowledge 47" is meaningless; "you
  have read the Lạc Hà survey fragment" is actionable.
- It is **permanent and persistent** — part of the persistent tier, saved.
- It must have at least one **non-gating** payoff too (a dialogue line, an inscription that now
  reads differently), so discovery is rewarding even when the player cannot use it yet.
- It may be **wrong**. The player can learn a false thing from a biased record; later knowledge can
  supersede it. This is the mechanical expression of `WORLD_BIBLE.md` world law 6.

## 8. Technique model (what a technique IS)

A technique is a **knowledge system**, not a stat card. Forbidden: `+5% damage` collectibles.

A `TechniqueData` may define: the cultivation method it teaches · resource behaviour (how it uses
linh khí) · combat behaviour · passives · active interactions · movement effect · weapon
compatibility · technique compatibility **and incompatibility** · risk/price · social
consequences · reputation consequences · proscribed status (Tà Đạo / Cấm Pháp — CL-01) · story
relevance.

**Compatibility and incompatibility are both first-class.** Build expression comes from the
*interaction* between techniques, which only exists if some pairs are bad together. A technique
that combines with everything has no identity.

**Technique ≠ skill.** A skill (Phase 15) is an activatable ability. A technique (a công pháp) is
the *framework* that shapes which skills are usable, how the resource behaves, and what the
cultivation costs. The roadmap builds skills first and techniques alongside them; the data model
keeps them separate resources so neither swallows the other.

## 9. Master realm table

Columns per the brief. Lower realms are specified; upper realms are deliberately structural
(§2). "Rarity" is in-world population texture, not a drop table.

| Realm | Layers | Meaning | Rarity | Lifespan | Combat | Traversal | Perception | Techniques | Weapons | Sect rank | Territory | Map | Dungeon | World | Economy | NPC reaction | Threat class | Narrative role |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **PHÀM** | — | baseline person | most of the world | mortal | none | walking | normal | none | mundane | none | none | settled areas | none | none | cash only | invisible | — | the world's stakes |
| **HẬU THIÊN** | 1–9 | body opened by effort | common among cultivators | slightly extended | basic qi-backed | sprint, light climb | sense qi nearby | foundation | all 5 families, basic | Outer → Inner Disciple | none | frontier + settled châu | entry bí cảnh | none | spirit stones, small credit | treated as a junior | T1 | **Acts I–II** |
| **TIÊN THIÊN** | 1–9 | qi self-sustaining | uncommon | notably extended | sustained technique use | qi-assisted movement, short flight at 6+ | read qi structure | specialised; first real combinations | family specialisation | Core Disciple → Elder | may hold a minor site | most of the Main World | most dungeons | **first Tiểu Giới gate at 7+** | trusted with real contracts | courted | T2 | **Acts III–V** |
| **NGỰ THIÊN** | 1–9 | authority over a domain | rare | centuries | domain-backed combat | flight; vein-assisted travel | perceive a whole site | domain techniques | signature artifacts | Elder → Sect Master | **holds a vein/region** | all Main World | all | Tiểu Giới + Tàn Giới | can move markets | deferred to; feared | T3 | **Acts VI–VII** |
| **TRỌNG THIÊN** | 1–9 | touches world law | a handful | very long | alters local law in combat | crosses the Hải Giới | perceive a world's state | law-interacting | — | beyond rank | **shapes a domain** | — | — | Hủ Giới; world gates | defines value | a political event | T4 | **Acts VIII–IX** |
| **THÁI THIÊN** | structural | beyond world scale | legend | — | — | — | — | — | — | — | — | — | — | — | — | mythic | — | **Act X / horizon** |
| **VÔ THIÊN** | structural | the unknown | unverified | — | — | — | — | — | — | — | — | — | — | — | — | — | — | permanently open (CL-15) |

## 10. Progression dependencies

- **Level/XP (11)** needs: Combat (09) for XP events. Blocks nothing content-wise *by design*.
- **Cultivation (12)** needs: Character (04, done) for persistent state; Level (11) alongside;
  and it **unblocks** map/dungeon/world access conditions, sect rank eligibility, technique
  availability.
- **Knowledge** has no engine of its own before Quest/Story (19/20); until then it is specified
  here and authored as data when its first consumer exists (anti-over-engineering).
- **Techniques (15, alongside Skill)** need: Cultivation (12) for gating, Combat (09) for
  behaviour, Weapon families (CL-10) for compatibility.
- Nothing in this document requires a new autoload, and nothing requires randomness — but the
  first system that *does* need randomness must introduce the seeded RNG seam (C-010).

## 11. Explicitly NOT frozen

XP curve shape · XP per enemy · cultivation speed · breakthrough success rates (if any) · stat
deltas per layer · technique numbers · threat-rating boundaries · lifespan values. All tuned in
Phases 11–12 against a playable build. The *architecture* above is frozen.
