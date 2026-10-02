# 01 — Product (Aetheria)

> Steering: always included. This is the north star for *what* we are building and *why*.

## Working title

**Aetheria** (tên tạm thời / temporary name).

## Elevator pitch

A single-player, offline-first 2D top-down fantasy / tu tiên (cultivation) RPG. The
player grows from a mortal into a cultivator, advancing through **cảnh giới**
(realms) by **tu luyện** (cultivation), learning **công pháp** (techniques) and
**skills**, collecting **equipment / items / pets**, and progressing a **branching
story** across many maps, dungeons, and bosses.

## Pillars (ranked)

1. **Progression that feels earned** — level, XP, cultivation realms, công pháp.
2. **Readable top-down combat** — skills, equipment, pets matter and are legible.
3. **Story with branches** — chapters, quests, NPCs, dialogue, meaningful choices.
4. **Longevity by design** — adding a map / chapter / enemy / boss / skill / item
   must be *data + content*, not a rewrite of existing systems.

## Scope by stage

- **Stage 1 — Offline (current):** the entire game is single-player and offline.
  This is the primary source of truth for all gameplay rules.
- **Stage 2 — Multiplayer (future, not now):** only *after* the offline game is
  complete and stable do we research online multiplayer. No networking code or
  networking dependency is added during Stage 1. See `docs/MULTIPLAYER_PLAN.md`.

## Audience & platform

- 2D, top-down, pixel art / stylized.
- Desktop first (Windows confirmed in project config). Mobile is possible later —
  the renderer is already `gl_compatibility`, which is mobile-friendly.

## Languages (first-class)

- Vietnamese (`vi`) and English (`en`). Both are supported from the foundation.
  **No user-facing text is hard-coded.** See `.kiro/steering/07-localization.md`.

## Content domains the design must accommodate

cốt truyện fantasy / tu tiên · level · tu luyện · cảnh giới · công pháp · skill ·
equipment · item · pet · NPC · dialogue · quest · dungeon · boss · nhiều map ·
progression · branching story.

## Core social / world systems (first-class, not quest decoration)

Characters, relationships, sects (tông môn), internal factions/politics, and a living
world simulation are **core systems**, designed up front (D-011). NPCs are data-driven
Characters with their own goals, relationships, sect membership, reputation, and secrets;
the world evolves even off-screen. See `docs/CHARACTER_SYSTEM.md`,
`docs/RELATIONSHIP_SYSTEM.md`, `docs/SECT_SYSTEM.md`, `docs/WORLD_SIMULATION.md`. These
are built (Phases 11–15) *before* the NPC/Dialogue/Quest/Story systems that depend on them.

## Explicit non-goals (for now)

- No gameplay implementation during the foundation step.
- No multiplayer / networking code in Stage 1.
- No 3D. (Note: project config currently enables a 3D physics engine — see
  `docs/DECISIONS.md` D-002; this is flagged, not used.)
- No premature engine-wide abstractions before a concrete second use case exists.

## Definition of a "good" change

A change is good when it advances a pillar, keeps the layers in
`.kiro/steering/03-architecture.md` intact, adds content as data where possible,
and leaves the project easier (not harder) to extend next time.
