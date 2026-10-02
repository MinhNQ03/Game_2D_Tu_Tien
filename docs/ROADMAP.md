# ROADMAP — Aetheria

> Phased plan. Phases are ordered by dependency, not by calendar. Each phase has an
> **exit criteria** — the next phase shouldn't start until it's met. No gameplay is
> built yet; we are at the very start of **Phase 0**.
>
> Every phase respects the extensibility invariant (`docs/GAME_FLOW.md`) and the AI
> review protocol (`.kiro/steering/08-ai-review-protocol.md`). "Build passes" is never
> an exit criterion by itself.

## Phase 0 — Foundation *(current)*
Documentation, standards, process. Project rename `New_Game_Project` → `Aetheria`.
Resolve or defer the flagged config issues (3D physics engine on a 2D game, D-002).
Decide the test framework (D-004).
**Exit:** all `.kiro/steering` + `docs` in place; open decisions logged; `tests/`
scaffold present with one green smoke test; config issues resolved or explicitly
deferred.

## Phase 1 — Core
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

## Phase 11 — NPC
NPC entities, interaction, shop state.
**Exit:** interact + trade; shop state serializes.

## Phase 12 — Dialogue
DialogueData (localization keys), dialogue runner, choices feeding story flags.
**Exit:** branching dialogue in `vi` + `en`; choices set flags; tested.

## Phase 13 — Quest
Quest FSM (domain), QuestData, objectives driven by EventBus, rewards.
**Exit:** add a quest via data; full lifecycle incl. serialize mid-quest; tested.

## Phase 14 — Story
Story/flag engine, chapter + branch evaluation, chapter progression loop.
**Exit:** a branch diverges on a prior choice; chapter transition works; tested.

## Phase 15 — Dungeon
DungeonData, instance modifiers on top of map+combat+loot.
**Exit:** add a dungeon via data; clear/exit cleanly; tested.

## Phase 16 — Boss
BossData with phases, boss AI; chapter-gating defeat.
**Exit:** add a boss via data; phases trigger; `boss_defeated` gates chapter; tested.

## Phase 17 — Save
Full versioned save/load across all systems; migration framework. See `SAVE_FORMAT.md`.
**Exit:** save/load round-trips every system's state; a v1→v2 migration demonstrated;
save/load tests pass.

## Phase 18 — Localization
Full `vi`/`en` pass; verify no hard-coded strings; font glyph coverage.
**Exit:** key-coverage test green for both languages; no literal UI strings in code.

## Phase 19 — Polish
UX, feedback, audio, transitions, menus.
**Exit:** smoke run feels complete end-to-end; no obvious UX gaps.

## Phase 20 — Optimization
Profiler-driven only. Pooling where churn is proven. Each optimization logged in
`PERFORMANCE.md` (problem/cause/solution/impact/measurement).
**Exit:** frame-time/allocation budgets met on target hardware; optimizations logged.

## Phase 21 — Release
Build pipeline, export presets, credits (asset attributions from `ASSET_LICENSES.md`),
final regression + smoke pass.
**Exit:** reproducible export; all attributions satisfied; regression suite green.

## Phase 22 — Multiplayer preparation
*Research + readiness only, still no shipped networking.* Validate the Stage-2 seams
hold (serializable player/world/inventory/progression state, command intents,
authoritative-state boundary). Prototype behind a flag if desired. See
`MULTIPLAYER_PLAN.md`.
**Exit:** documented gap analysis: what each seam needs for authority/replication; a
go/no-go recommendation. No networking dependency merged into the offline game.

## Guardrails across all phases
- Offline is the source of truth until Stage 2 is explicitly approved.
- No premature abstraction; content added as data + scenes.
- High-risk logic (damage, combat, inventory, progression, XP, level, cultivation,
  skill, quest, save/load, localization, map transitions) ships with tests.
