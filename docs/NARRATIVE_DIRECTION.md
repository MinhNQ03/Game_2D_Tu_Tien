# NARRATIVE_DIRECTION — Aetheria

> **Design anchor only. No story/dialogue/quest engine is implemented by this document.** It
> gives Aetheria a consistent narrative north star from Phase 05 on, so later systems
> (NPC/Dialogue/Quest/Story — much later phases) build toward one coherent story instead of
> bolting on disconnected content each phase. All content here is ORIGINAL to Aetheria: no
> names, characters, plots, or text copied from any existing game or novel. Ties to
> `.kiro/steering/01-product.md`, `.kiro/steering/02-game-design.md`,
> `docs/RELATIONSHIP_SYSTEM.md`, `docs/CHARACTER_SYSTEM.md`.

## 1. Premise

The player begins as a **young, unranked cultivator** — someone who has only just stepped
onto the path of tu luyện, with no sect standing, no reputation, and no destiny handed to
them. They arrive at a **frontier region** where ordinary mortals, masterless wanderers (tán
tu), and the lesser outposts of larger cultivation powers all live side by side. It is a
place big enough to matter to no one important yet — which is exactly why a nobody can start
to matter here.

The story is NOT "chosen one ascends." It is "a stranger earns a place" — power and story
both grow out of the **relationships** the player builds (and breaks) at the edge of the
cultivation world, before the great sects and their rivalries ever notice them.

## 2. Themes

- **Earned, not granted.** Standing, trust, and strength are accumulated through choices and
  consequences, mirroring the two progression axes (level/XP + cảnh giới) and the
  relationship graph. Nothing important is free.
- **Relationships over alignment.** The player is not scored on a single good/evil bar. What
  the world remembers is specific: who likes them, who trusts them, who respects them, who
  fears them, who competes with them, who owes (or is owed) a debt.
- **The small before the large.** The first chapter is deliberately intimate — a handful of
  people, a few favors and grudges — before any faction-scale conflict. The player feels the
  world is personal first and political later.
- **Consequence has memory.** A kept or broken promise is not forgotten; it colors how
  characters (and later their sects) treat the player long after.

## 3. Player identity

- A newcomer cultivator of modest origin (authored as data — `data/characters/player_default.tres`).
- Defined by **choices + relationships**, not a fixed personality the narrative imposes.
- The player is a Character like any other (`docs/CHARACTER_SYSTEM.md`): the same state model,
  the same relationship edges. Nothing in the story engine (later) is allowed to make the
  player a special-cased exception to the core systems.

## 4. First arc direction (relationship-driven)

**Arc theme:** *"The player enters the cultivation world through small relationships, before
being pulled into the conflicts of the great powers."*

The first arc is a frontier settlement and its surroundings (the kind of hub ↔ field space
the current build already traverses). It introduces a few memorable characters — e.g. a
guarded elder, a rival newcomer, a wanderer in someone's debt, a merchant with their own
agenda (the four archetypes the art pipeline previews). The player's early actions shift the
**relationship dimensions** (`docs/RELATIONSHIP_SYSTEM.md` §2), and those shifts are what make
the later story diverge.

Design examples (NARRATIVE INTENT — NOT implemented as gameplay yet; later phases map these
to real events through `RelationshipRuleData`):

- Help a stranger in trouble → their **affinity** and **trust** rise.
- Keep your word → **trust** and **respect** rise.
- Break a promise → **trust** falls (and the memory lingers).
- Defeat a rival fairly → **respect** can rise even as **rivalry** also rises.
- Rescue someone who owed a debt → the **debt** relationship shifts.
- Intimidate the weak to get your way → **fear** rises, **affinity** falls.

None of these are wired into the current playable flow. They are the vocabulary the first arc
will speak, so when quests/dialogue arrive they drive the SAME relationship graph rather than
inventing parallel bespoke state.

## 5. Future branch principles

- **Branches read state, never scatter booleans.** Story divergence queries character
  relationships + sect/faction state + story flags (`.kiro/steering/02-game-design.md`
  branching contract), never a pile of unrelated per-node booleans.
- **A chapter is content, not an engine edit.** Adding a chapter/arc = new data + scenes, not
  changes to the story engine (the extensibility rule).
- **Relationships are the connective tissue.** As sects, factions, and world simulation come
  online (Phases 06–08), the story leans on the SAME relationship graph to make the world feel
  reactive — one source of truth, not a second narrative-only store.

## 6. What must NOT be broken later (invariants)

- The player is never exempt from the core Character/Relationship model.
- Relationships stay the single source of truth for "how the world feels about you" — the
  story engine reads and drives them through the service, it does not keep its own copy
  (`docs/RELATIONSHIP_SYSTEM.md` §1/§8).
- No single morality bar replaces the multi-dimensional relationship model.
- All narrative content is original to Aetheria and localized (vi + en) — no copied
  names/plots, no hard-coded user-facing strings (`.kiro/steering/07-localization.md`).
- Offline single-player remains the source of truth; nothing in the narrative design assumes
  networking (`docs/MULTIPLAYER_PLAN.md`).

## 7. Explicitly NOT in this document / phase

No dialogue system, no quest system, no story/flag engine, no scripted scenes, no NPC
gameplay. This is design intent for later phases (NPC → Dialogue → Quest → Story in the
roadmap). Phase 05 only ships the **relationship substrate** those systems will stand on, plus
the character **visual pipeline** that will show these characters on screen.
