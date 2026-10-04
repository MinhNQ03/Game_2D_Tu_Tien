# GAME_DESIGN_FREEZE — Aetheria · v2.1

> **MASTER INDEX. Read this first.** This document does not contain design — it says WHO OWNS
> each design rule, so that a future contributor (human or AI) never has to guess which of
> fourteen documents is authoritative about cultivation realms, map gating or the meaning of
> Tà Đế.
>
> Frozen by **D-039**, 2026-10-04. Design-only: **no gameplay code, no networking, no new
> autoload, no runtime behaviour changed** by this freeze.
>
> **What "frozen" means here:** the STRUCTURE, the LOGIC, the DEPENDENCIES and the CANON are
> fixed and need a `DECISIONS.md` entry to change. Numerical BALANCE is deliberately NOT frozen
> (§6). Architecture before numbers.

---

## 1. Why this freeze exists

Aetheria is at the exact point where the risk changes shape. Phases 00–06 built a correct
foundation: lifecycle, input, localization, maps, Character, Relationship, Sect — each one
serializable, data-driven and tested. The remaining 28 phases add *content-bearing* systems
(combat, cultivation, items, quests, story, dungeons, a multi-world cosmos), and those systems
fail differently. They do not fail by crashing; they fail by being **individually reasonable and
collectively incoherent** — a cultivation ladder that no map respects, a sect that no quest can
dramatise, a world that grows by wallpaper.

That failure is unaffordable because it is only visible in aggregate, hundreds of quests later,
when the fix is a rewrite. So the design is frozen BEFORE the content exists, while changing a
realm name still costs one markdown edit instead of a save-format migration.

The freeze also exists because the audit found eleven real contradictions already present in the
repository — including one that invalidated the game's own premise (the player was being handed
a sect in minute one while the narrative doc promised them "no sect standing"). They are all
recorded, each with a named owner: `docs/CONTRADICTION_REGISTER.md`.

## 2. Rule ownership (the point of this document)

Every rule has exactly ONE authoritative document. Other documents may *reference* a rule; they
must not restate it as if they owned it. If two documents disagree, the owner wins and the other
is a bug (L-014).

| Concept | AUTHORITATIVE OWNER | Everyone else |
|---|---|---|
| Product vision, pillars, stage scope | `.kiro/steering/01-product.md` | reference |
| Canonical glossary, two-axis progression contract, extensibility rule | `.kiro/steering/02-game-design.md` | reference |
| Layer boundaries, autoload budget, state partition | `.kiro/steering/03-architecture.md` | reference |
| **Frozen facts: names, hierarchies, ids, world laws** | **`docs/CANON_LEDGER.md`** | cite `CL-nn` |
| **Known contradictions + their resolutions** | **`docs/CONTRADICTION_REGISTER.md`** | cite `C-nnn` |
| Cosmology, geography, factions-in-the-world, Thiên Khế, historical Tà Đế | `docs/WORLD_BIBLE.md` | reference |
| Premise, prologue, Origins, acts, reveal ladder, branch/convergence policy | `docs/NARRATIVE_MASTER_PLAN.md` | reference |
| Realm hierarchy semantics, 9 layers, level≠realm, knowledge, paths | `docs/PROGRESSION_CULTIVATION_DESIGN.md` | reference |
| Weapon identity, technique model, combat verbs, boss/telegraph language | `docs/COMBAT_DESIGN.md` | reference |
| Resource sources/sinks, crafting, grind lanes, anti-inflation | `docs/ECONOMY_CRAFTING_DESIGN.md` | reference |
| Character bible, relationship consequences, sect/faction design, world-sim content | `docs/SOCIAL_DESIGN.md` | reference |
| Map grammar, **access gating**, dungeon grammar, boss placement, revisit | `docs/MAP_DUNGEON_DESIGN.md` | reference |
| Quest taxonomy + quality rules | `docs/MAP_DUNGEON_DESIGN.md` §7 | reference |
| System ownership, inputs/outputs, phase + risk, MP seams | `docs/SYSTEM_DEPENDENCY_MATRIX.md` | reference |
| Content authoring templates (what fields a thing must have) | `docs/CONTENT_BIBLE.md` | reference |
| Visual language, UI information hierarchy, per-phase UI evolution | `docs/UI_UX_BIBLE.md` | reference |
| The runnable flow + per-system contracts | `docs/GAME_FLOW.md` | reference |
| Phase numbers, order, exit criteria | `docs/ROADMAP.md` | reference |
| Multiplayer seams + the narrative state split | `docs/MULTIPLAYER_PLAN.md` | reference |
| Save tiers, versioning, migration | `docs/SAVE_FORMAT.md` | reference |
| Damage formula + data shapes | `docs/DATA_SCHEMA.md` | reference |
| Every binding decision, with rationale and date | `docs/DECISIONS.md` | — |

**Deliberately NOT duplicated:** the damage formula lives only in `DATA_SCHEMA.md`
(`COMBAT_DESIGN.md` describes combat *identity*, never the maths); relationship dimensions live
only in `RELATIONSHIP_SYSTEM.md`; phase numbers live only in `ROADMAP.md`.

## 3. The thirteen freeze documents

| Document | Status | What it answers |
|---|---|---|
| `GAME_DESIGN_FREEZE.md` | this file | who owns which rule |
| `CANON_LEDGER.md` | NEW | "is X canon, and what is it called?" |
| `CONTRADICTION_REGISTER.md` | NEW | "what did we already get wrong, and who fixed it?" |
| `WORLD_BIBLE.md` | NEW | "what is this world and why does it hold together?" |
| `NARRATIVE_MASTER_PLAN.md` | NEW | "what happens, in what order, and why does the player care?" |
| `PROGRESSION_CULTIVATION_DESIGN.md` | NEW | "what does getting stronger mean?" |
| `COMBAT_DESIGN.md` | NEW | "what is fun at hour 1, 20 and 100?" |
| `ECONOMY_CRAFTING_DESIGN.md` | NEW | "where does value come from and where does it go?" |
| `SOCIAL_DESIGN.md` | NEW | "how does the world remember what I did?" |
| `MAP_DUNGEON_DESIGN.md` | NEW | "why does this place exist and how do I get in?" |
| `SYSTEM_DEPENDENCY_MATRIX.md` | NEW | "what breaks if I change this?" |
| `CONTENT_BIBLE.md` | NEW | "what fields must a new quest/sect/map have?" |
| `UI_UX_BIBLE.md` | NEW | "what does it look like, and when does each screen arrive?" |

## 4. The player fantasy being frozen

> I entered this world as nobody. I chose my path. The world remembered what I did. Power
> changed me. Knowledge changed me. Relationships changed. Organisations reacted. The world
> changed. Eventually the world may call me savior, rebel, heretic, ruler, monster, reformer —
> or **Tà Đế**.

Four invariants make that sentence mechanically true rather than marketing copy:

1. **No guaranteed destiny.** The player is not a chosen one, not a reincarnation, not an heir,
   and is never exempt from the core `CharacterState` model (`NARRATIVE_DIRECTION.md` §6 —
   already an invariant).
2. **Identity is derived, never a counter.** "Tà Đế" is read out of accumulated history —
   cultivation, techniques, knowledge, relationships, sect/faction standing, world events,
   major decisions — and there is no `evil_score`, morality meter or alignment anywhere
   (`CANON_LEDGER.md` CL-07).
3. **The world has its own causes.** No event exists because "the player needs a quest"; every
   major event carries CAUSE → ACTORS → MOTIVATION → TRIGGER → PLAYER INVOLVEMENT → RESULT →
   SOCIAL/SYSTEM/WORLD CONSEQUENCE → FUTURE PAYOFF (`NARRATIVE_MASTER_PLAN.md` §11).
4. **Consequence has memory.** The relationship graph, sect/faction state and world-sim state
   are persistent and serializable, so an action taken at hour 3 is still readable at hour 100.

## 5. Hard invariants this freeze must not break

Carried forward unchanged from the existing architecture — the freeze is *additive*:

- Character · Relationship · Sect · Faction · World Simulation remain **core domain systems**
  (D-011), authoritative, serializable, presentation-free.
- Presentation never owns gameplay truth; UI reads a view and sends intents.
- Every core system partitions state into **persistent / runtime / presentation**; only
  persistent is saved (`MULTIPLAYER_PLAN.md` §2b).
- Content is added as **data + content scenes**, never by editing core systems per item
  (`GAME_FLOW.md` §2). Verified against a 10-quest/5-NPC/3-map/2-dungeon/2-boss/3-technique/
  2-weapon/1-sect/2-faction/1-Minor-World simulation: `CONTENT_BIBLE.md` §15.
- Offline is the source of truth. **No networking in Stage 1.**
- The autoload budget stays at **5** (`EventBus`, `GameState`, `Localization`, `InputService`,
  `SceneRouter`). No God object, no speculative framework.
- No hard-coded user-facing strings; vi + en are both first-class.

## 6. What is NOT frozen (and must stay unfrozen)

Freezing numbers this early would be false precision — they can only be set against a playable
build. Tunable without a `DECISIONS.md` entry:

XP curves · damage/HP values · drop rates · currency amounts · cultivation speed · cooldowns ·
spawn rates · grind duration · threat ratings · exact technique numbers · map sizes.

The *architecture* that those numbers plug into IS frozen. Phase 11 tunes the XP curve; it may
not decide that level gates map access (C-002).

## 7. Known content debts created by this freeze

Each is a real, named consequence of resolving a contradiction — recorded here so none is lost:

| Debt | Owner phase | From |
|---|---|---|
| `player_start_sect_id` → `&""`; sect joining becomes earned content | 17/19 (NPC/Quest) | C-003 |
| `SECT_TYPE_DEMONIC` display text → an in-world *label*, not a verdict | 24 (Localization) | C-004 |
| Xích Diễm Tông doctrine text → a defensible charter | 24 / first Xích Diễm content phase | C-005 |
| `UI_MAP_HUB_NAME` / `UI_MAP_FIELD_NAME` → canonical place names | first frontier content phase | C-008 |
| `OriginData` content resources + character-creation flow | 20/27 | C-011 |
| Seeded RNG seam introduced by the first system that needs randomness | 09 (likely) | C-010 |

## 8. Acceptance

All 51 acceptance criteria of the freeze brief are met; all 23 audits (A–W) were run and are
tabulated at the end of `CONTRADICTION_REGISTER.md`. No critical item remains "TBD": the only
open questions are balance parameters (§6) and the deliberately-unanswered canon mysteries
(`CANON_LEDGER.md` CL-15), which are open *by design* and listed with their reveal order.

**DESIGN FREEZE READY · NO GAMEPLAY CODE IMPLEMENTED · NO NETWORKING IMPLEMENTED ·
NO RUNTIME BEHAVIOR CHANGED.**
