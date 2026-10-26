---
name: aetheria-narrative-canon
description: Aetheria story and canon rules - who owns which fact, frozen vs tunable, reveal ladder, story-catalog generator, and the owner's depth bar. Use before writing quests, dialogue, NPCs, items or lore.
---

# Aetheria narrative and canon — authority first, then depth

Authority (cite ids, never paraphrase from memory): `docs/GAME_DESIGN_FREEZE.md` (who owns which
rule; v2.1 frozen D-039), `docs/CANON_LEDGER.md` (`CL-nn` frozen facts: hierarchy, cosmology,
Hạo Nguyên Giới, Thiên Khế, the historical Tà Đế, Đêm Vỡ Mạch, the five Origins, weapon families),
`docs/WORLD_BIBLE.md`, `docs/NARRATIVE_MASTER_PLAN.md` (§9 reveal ladder, §9a clue ledger, §14
story-state scopes), `docs/CONTRADICTION_REGISTER.md` (`C-nnn`), `docs/XIANXIA_IDENTITY_CONTRACT.md`,
`docs/CONTENT_BIBLE.md`. Map: `docs/knowledge/AETHERIA_KNOWLEDGE_HUB.md`.
Reviewer: `aetheria-narrative-reviewer`.

## Status words mean something
`EXISTING CANON` (frozen) · `ACCEPTED DECISION` (`D-nnn`) · `PROPOSAL` (not canon until the owner
accepts) · `OPEN QUESTION` · `HISTORICAL`. A proposal or a reference board is never canon (L-044).
Changing frozen canon is an owner decision (escalate with evidence; do not edit around it).

## Frozen vs tunable
May not vary in any playthrough, male or female (`NARRATIVE_MASTER_PLAN.md` §12): major world
events · the act structure · the reveal ladder · sect/faction politics · the Thiên Khế and Tà Đế
canon · any system rule. Tunable without a decision (`GAME_DESIGN_FREEZE.md` §6): XP curves,
damage/HP, drop rates, currency, cooldowns, spawn rates, map sizes. Access is never level-gated (C-002): realm + quest + knowledge + standing + world
state + key item.

## How story data is built
- `tools/author_story_data.py` is the ONLY writer of `data/story/story_catalog.tres`,
  `origin_catalog.tres`, `story_scene_catalog.tres`. Edit its tables, re-run, and
  `python3 tools/author_story_data.py --check` (a configured check). Never hand-edit those `.tres`.
- Every string is a key in `locale/aetheria.csv`, vi and en.
- Personal story, world chronicle, party/instance and social state are separate scopes; personal
  story is never shared (`NARRATIVE_MASTER_PLAN.md` §14, `MULTIPLAYER_PLAN.md`). Each system's state
  has one owner (`SYSTEM_DEPENDENCY_MATRIX.md`).

## The owner's depth bar (playtest feedback 2026-10-11)
- Everything in the world leads into a story: no free pickup without a reason the player can see.
- Every NPC has a goal, a fear and a secret that SHOW in play; inner conflict over exposition.
- Plant foreshadowing inside canon: seed twists, never break the reveal ladder.
- A complete system is not an engaging one (L-053): judge from the player's seat.
- A second character must differ in silhouette and palette at 1×, not only in details.

## Player pull: what a released tu-tiên game does that we must beat (owner survey 2026-10-21)
Source: `docs/design_refs/cotienlo_2026_10_21/GHI_CHU_CAI_TIEN.md` (gitignored; principles only,
never their text, data or pictures). Cổ Tiên Lộ hooks players by staying close to its source novel
and putting story on screen in the first second. Our answer:
- **Hook in the first 5 minutes:** a scene, not a menu. The first real choice comes early and its
  consequence is SEEN later: an NPC remembers, a door opens or shuts, standing moves.
- **The protagonist has a voice:** cold, sharp and calculating lines that are theirs, not only a
  narrator's. Literary narration, shown whole (ui-01).
- **Quests read as schemes:** a goal, two or more ways to reach it (kill, deceive, manipulate,
  trade) and the price of each. The reward is story or standing, never a free pickup.
- **Teach through people:** a tutorial hint is a line spoken by a master, a rival or a heart
  demon, not plain instruction text.
- **Story beats change the world:** every major beat has a visible reaction (light, sound, a
  mark on the floor, a closed exit) and a chapter banner carrying one line in the protagonist's
  voice.
- **Our own loop, not theirs:** never the "raise gu" loop. Ours grows out of our canon: seize
  and refine (power at a cost), sect and faction standing, secrets gathered as clues (§9a).
- **Canon guard:** the reference proposes a "Tà niệm" meter. Our frozen canon says Tà Đế is NOT
  a meter (`NARRATIVE_MASTER_PLAN.md` §3): read consequences from the persistent state. Use that
  state for mood and ambience, never a single score. Following an outside novel's plot is an
  owner decision (canon freeze and copyright): never import its characters, events or text.

## Before calling narrative work done
Cause → effect is visible to the player; every claim in a doc is grounded in data or code; the
clue ledger and contradiction register are updated when you add or resolve a thread.
