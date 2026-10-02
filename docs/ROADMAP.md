# ROADMAP — Aetheria

> Phased plan. Phases are ordered by dependency, not by calendar. Each phase has an
> **exit criteria** — the next phase shouldn't start until it's met. No gameplay is
> built yet; we are at the very start of **Phase 0**.
>
> Every phase respects the extensibility invariant (`docs/GAME_FLOW.md`) and the AI
> review protocol (`.kiro/steering/08-ai-review-protocol.md`). "Build passes" is never
> an exit criterion by itself.
>
> **28 phases (0–27).** Phase 0 (Foundation) is **CLOSED** — verified green by CI on
> `651c16f` (2026-10-03). The current/next phase is **Phase 1 — Core** (not started). The
> core social/world systems (Character/Relationship/Sect/Faction/World-Sim) are sequenced
> as Phases 11–15, before the NPC/Dialogue/Quest/Story phases that depend on them.

## Phase 0 — Foundation *(CLOSED — CI-verified 2026-10-03)*
Documentation, standards, process. **Done in the 2026-10-03 foundation fix:** project
renamed → `Aetheria` (D-006); 2D config cleaned, 3D physics removed (D-002); test
framework decided = custom runner (D-004); bootable bootstrap `main.tscn` (D-010); real
smoke test + runner; core social/world system design docs (D-011); CI added (D-012).
**Exit:** all `.kiro/steering` + `docs` in place; blocking decisions resolved (D-002,
D-004, D-006) or explicitly deferred with triggers (D-003/005/007/008); `tests/` has a
real runner + a passing smoke test; project boots to a real main scene; CI runs the
suite headless (checkout → Godot 4.7 → import → parse check → runtime boot → tests).
**Status: MET — Phase 0 CLOSED.** GitHub Actions executed the full pipeline on commit
`651c16f` with `conclusion=success` (real Godot 4.7: import + parse check + runtime boot +
headless test suite). Full checklist with evidence: `docs/PHASE_0_EXIT_CHECKLIST.md`
(status READY FOR PHASE 1). Decisions D-002/D-004/D-006 Accepted; D-012 verified; the
remaining Open decisions (D-003/005/007/008) are deferred with triggers and do not block
Phase 0.

## Phase 1 — Core *(NEXT — not started)*
Infrastructure autoloads as needed: `EventBus`, `GameState`, `Config`, `RNG`,
`SceneRouter`, `Localization`, `SaveService` (stubs where appropriate). Input map.
Main-menu → new-game → first scene boot path.
**Exit:** boot flow runs headless + in editor; EventBus + SceneRouter covered by smoke
tests; each autoload justified in `DECISIONS.md`.

## Phase 2 — Player
Player entity via composition: movement (top-down), StatsComponent, HealthComponent.
**Exit:** player moves and takes/returns damage against a dummy; components unit-tested.

## Phase 3 — World
MapData-driven maps, SceneRouter transitions, VILLAGE hub + one field map. Clean
load/unload (no leaked nodes/signals).
**Exit:** move between ≥2 maps repeatedly with no leaks; map-transition tests pass.

## Phase 4 — Combat
Single documented damage formula (domain, pure), Hitbox/Hurtbox, basic attack, seeded
RNG. Combat emits events only.
**Exit:** deterministic damage from data; damage/combat unit + integration tests pass.

## Phase 5 — Enemy
EnemyData-driven enemies, AIComponent with controlled tick rate, spawn tables.
**Exit:** add a new enemy via data only; AI tick-rate measured; no per-frame churn.

## Phase 6 — Progression
XP curve, level, cảnh giới / tu luyện breakthrough rules (two axes). Reacts to combat
events.
**Exit:** XP → level and cultivation → realm unlocks work; serializable; tests pass.

## Phase 7 — Inventory
InventoryComponent (serializable), item pickup/use, ItemData.
**Exit:** add/use/drop items via data; inventory ops unit-tested; serializes/restores.

## Phase 8 — Equipment
EquipmentData, equip/unequip applying stat modifiers through the damage formula.
**Exit:** equipment changes damage deterministically; covered by tests.

## Phase 9 — Skill
SkillComponent, SkillData (active/passive), cooldowns, mana/linh khí cost, công pháp
gating of usable skills.
**Exit:** add a skill via data; cooldown/cost/gating tested.

## Phase 10 — Pet
PetData, pet as an Entity with ally AIComponent; follows/assists in combat.
**Exit:** add a pet via data; pet state serializes; combat assist tested.

> **Core social/world systems come next (Phases 11–15), BEFORE NPC/Dialogue/Quest/Story**,
> because those depend on them (D-011, `docs/GAME_FLOW.md` §1b). Characters, relationships,
> sects, factions, and world simulation are the substrate quests and story read from.

## Phase 11 — Character System
Data-driven Characters as core domain state (`docs/CHARACTER_SYSTEM.md`):
`CharacterTemplateData` + `CharacterState`, 3-tier state (persistent/runtime/presentation),
`CharacterEntity` as a *view*, player modeled as a Character.
**Exit:** add a character purely via data; `CharacterState` round-trips through save;
life-state transitions persist; no presentation leaks into persistent tier; tests pass.

## Phase 12 — Relationship System
Serializable relationship graph (`docs/RELATIONSHIP_SYSTEM.md`): `RelationshipEdge` with
affinity/trust/respect/fear/rivalry/debt + type; Char↔Char, Player↔Char, Char↔Sect.
**Exit:** edges create/update/query + round-trip save; event→delta is deterministic;
tests pass.

## Phase 13 — Sect System
Core sects (`docs/SECT_SYSTEM.md`): `SectTemplateData` + `SectState`, membership/ranks,
resources/territory/reputation, alliances mirrored as relationship edges.
**Exit:** add a sect via data only; `SectState` round-trips; membership stays in sync with
`CharacterState`; tests pass.

## Phase 14 — Faction / Politics
Internal factions + emergent politics (`docs/SECT_SYSTEM.md` §7): `FactionState`,
influence, attitudes toward player/other factions, resolved as rules over data.
**Exit:** multi-faction sect authored via data; a faction influence/attitude change
produces documented, deterministic outcomes; round-trips; tests pass.

## Phase 15 — World Simulation
LOD simulation (`docs/WORLD_SIMULATION.md`): Near real-time / Far abstract; schedule/tick/
event/state-transition drivers; promotion/demotion; seeded determinism; save-resumable.
**Exit:** seeded K-tick run reproduces identical state; promotion/demotion loses no
persistent state; save mid-sim + load resumes; catch-up within budget; perf test passes.

## Phase 16 — NPC
NPC interaction & services (shops) built **on** the Character/Sect/Relationship systems.
**Exit:** interact + trade; shop state serializes; standing uses the relationship graph.

## Phase 17 — Dialogue
DialogueData (localization keys), dialogue runner, choices feeding story + relationship +
sect state.
**Exit:** branching dialogue in `vi` + `en`; choices set flags/relationship deltas; tested.

## Phase 18 — Quest
Quest FSM (domain), QuestData, objectives driven by EventBus; quests arise from and affect
characters/sects/politics.
**Exit:** add a quest via data; full lifecycle incl. serialize mid-quest; tested.

## Phase 19 — Story
Story/flag engine; branches read character/sect/faction state + flags; chapter loop +
world-state-change feedback (`docs/GAME_FLOW.md` §1b).
**Exit:** a branch diverges on a prior choice/relationship/faction state; chapter
transition works; tested.

## Phase 20 — Dungeon
DungeonData, instance modifiers on top of map+combat+loot.
**Exit:** add a dungeon via data; clear/exit cleanly; tested.

## Phase 21 — Boss
BossData with phases, boss AI; chapter-gating defeat.
**Exit:** add a boss via data; phases trigger; `boss_defeated` gates chapter; tested.

## Phase 22 — Save
Full versioned save/load across all systems (incl. character/relationship/sect/world-sim);
migration framework. See `SAVE_FORMAT.md`.
**Exit:** save/load round-trips every system's state; a v1→v2 migration demonstrated;
save/load tests pass.

## Phase 23 — Localization
Full `vi`/`en` pass; verify no hard-coded strings; font glyph coverage.
**Exit:** key-coverage test green for both languages; no literal UI strings in code.

## Phase 24 — Polish
UX, feedback, audio, transitions, menus.
**Exit:** smoke run feels complete end-to-end; no obvious UX gaps.

## Phase 25 — Optimization
Profiler-driven only. Pooling where churn is proven. Each optimization logged in
`PERFORMANCE.md` (problem/cause/solution/impact/measurement).
**Exit:** frame-time/allocation budgets met on target hardware; optimizations logged.

## Phase 26 — Release
Build pipeline, export presets, credits (asset attributions from `ASSET_LICENSES.md`),
final regression + smoke pass.
**Exit:** reproducible export; all attributions satisfied; regression suite green.

## Phase 27 — Multiplayer preparation
*Research + readiness only, still no shipped networking.* Validate the Stage-2 seams
hold (serializable player/world/inventory/progression **and** character/relationship/
sect/faction/world-sim state, in persistent/runtime/presentation tiers; command intents;
authoritative-state boundary). Prototype behind a flag if desired. See
`MULTIPLAYER_PLAN.md`.
**Exit:** documented gap analysis: what each seam needs for authority/replication; a
go/no-go recommendation. No networking dependency merged into the offline game.

## Guardrails across all phases
- Offline is the source of truth until Stage 2 is explicitly approved.
- No premature abstraction; content added as data + scenes.
- High-risk logic (damage, combat, inventory, progression, XP, level, cultivation,
  skill, quest, save/load, localization, map transitions) ships with tests.
