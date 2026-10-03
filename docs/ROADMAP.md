# ROADMAP — Aetheria

> Phased plan. Phases are ordered by dependency, not by calendar. Each phase has an
> **exit criteria** — the next phase shouldn't start until it's met.
>
> Every phase respects the extensibility invariant (`docs/GAME_FLOW.md`) and the AI
> review protocol (`.kiro/steering/08-ai-review-protocol.md`). "Build passes" is never
> an exit criterion by itself.
>
> **35 phases (00–34).** Phase 00 (Foundation) is **CLOSED** (CI-verified on `651c16f`,
> 2026-10-02). Phase 01 (Core Framework) is **CLOSED** (CI-verified 2026-10-02). Phase 02
> (Player) is **CLOSED** (CI-verified 2026-10-02). Phase 03 (World / Map) is **IN PROGRESS**
> (code + tests written 2026-10-02; CLOSED only once all 9 CI gates are green). Phase 04
> (Character) is the next phase after Phase 03 closes.
>
> **Reorder note (2026-10-02, Phase 1 kickoff):** the core social/world systems
> (Character / Relationship / Sect / Faction / World Simulation) were moved **earlier** —
> to phases 04–08, immediately after World/Map and **before Combat** — because they are
> the substrate that later systems (NPC, Dialogue, Quest, Story, and even enemy/boss
> flavor) read from (D-011, `docs/GAME_FLOW.md` §1b). This is a planning/sequencing change
> only; it does **not** authorize implementing those systems early. Older documents that
> referenced the previous numbering (Character=11 … Save=22 … MP=27) were updated to this
> numbering.

## Phase 00 — Foundation *(CLOSED — CI-verified 2026-10-02)*
Documentation, standards, process. Project renamed → `Aetheria` (D-006); 2D config cleaned,
3D physics removed (D-002); test framework = custom runner (D-004); bootable bootstrap
`main.tscn` (D-010); real smoke test + runner; core social/world design docs (D-011); CI
(D-012). **Status: MET** — GitHub Actions ran the full pipeline on `651c16f` with
`conclusion=success`. Evidence: `docs/PHASE_0_EXIT_CHECKLIST.md`.

## Phase 01 — Core Framework *(CLOSED — CI-verified 2026-10-02)*
The minimal correct runtime skeleton: application lifecycle + runtime session state
(`GameState`), semantic InputMap + input-gating ownership (`InputService`), `EventBus`,
`SceneRouter` (single safe transition entry), `Localization` (vi/en), a localized
main-menu shell (New Game / Quit), a first-scene/prologue shell, and bootstrap wiring.
Autoloads are the 5 justified in D-017 (`EventBus`, `GameState`, `Localization`,
`InputService`, `SceneRouter`). `Config` / `RNG` / `SaveService` are **deliberately
deferred** (D-017) — not part of Phase 01. No gameplay, no networking.
**Exit (MET):** boot → menu → new game → session init → first scene runs; GameState +
SceneRouter + EventBus + Localization + Input covered by headless tests + a real
application end-to-end flow test; each autoload justified in `DECISIONS.md`; CI green.
Hardened and CI-verified on the Phase 01 commits (see `docs/CHANGELOG.md`).

## Phase 02 — Player *(CLOSED — CI-verified 2026-10-02)*
Player entity via composition (`CharacterBody2D` + StatsComponent/HealthComponent/
MovementComponent) — no inheritance chain, no God object. Semantic input only (via
`InputService`); top-down 8-direction movement with normalized diagonals and collision;
stats from a `StatBlock` Resource (data, not magic numbers); health with enforced
invariants (`0<=hp<=max`, `died` once, DEAD terminal). A minimal, model-agnostic damage
rule lives once in `src/domain/combat/damage_rules.gd` (NOT a combat system — D-007 stays
Open). A Training Dummy (same components, no AI) and a playable **Player Sandbox** scene
prove a bidirectional damage exchange. The player is modeled as a Character conceptually
(Phase 04): authoritative numbers are data, the node is a runtime view, so Phase 04 binds
the same composition to a `CharacterState` without a rewrite (D-020).
**Exit (MET):** player moves and takes/returns damage against a dummy; Stats/Health/Movement
and the damage rule unit-tested; player+dummy integration + a real-application player E2E
(New Game → sandbox → move → attack → death → cleanup) green in CI. The sandbox is a
*temporary Phase-02 gameplay-validation* first scene; Phase 03 replaces it with a real map.
No combat system, no AI, no inventory/equipment/skill/cultivation, no networking, no
save/load, no new autoloads (D-003 / D-005 / D-007 remain Open).

## Phase 03 — World / Map
MapData-driven maps, SceneRouter transitions, a hub map + one field map. Clean
load/unload (no leaked nodes/signals). Uses stable `world_id` / `map_id` / `scene_key`.
**Exit:** move between ≥2 maps repeatedly with no leaks; map-transition tests pass.

**Implementation (2026-10-02, D-003 resolved / D-021):** `MapData` + `MapExit` resources
(`src/data/maps/`), two authored maps `data/maps/map_hub.tres` + `map_field.tres`, a
`WorldRuntime` node under `Main/Systems` (not an autoload) that registers each map's
`scene_key` with SceneRouter, owns ONE persistent per-session Player, and resolves
transitions; two content scenes `src/gameplay/maps/hub_map.tscn` + `field_map.tscn`
(`MapBase` + `MapExitZone`, semantic `interact` exits via InputService, prototype vector
art). New Game now enters the hub map (the Phase-02 sandbox is retained but no longer first
scene). Tests: `tests/unit/world/test_map_data.gd`, `tests/integration/test_map_transitions.gd`
(no-leak), `tests/gameplay/test_map_scenes.gd` (structure), and the dedicated E2E
`tests/e2e/run_world_flow.gd` (9th CI gate). CLOSED pending all gates green in CI.

> **Core social/world systems come next (Phases 04–08), BEFORE Combat and before
> NPC/Dialogue/Quest/Story**, because those depend on them (D-011, `GAME_FLOW.md` §1b).

## Phase 04 — Character System
Data-driven Characters as core domain state (`docs/CHARACTER_SYSTEM.md`):
`CharacterTemplateData` + `CharacterState`, 3-tier state (persistent/runtime/presentation),
`CharacterEntity` as a *view*, player modeled as a Character.
**Exit:** add a character purely via data; `CharacterState` round-trips through save;
life-state transitions persist; no presentation leaks into persistent tier; tests pass.

## Phase 05 — Relationship System
Serializable relationship graph (`docs/RELATIONSHIP_SYSTEM.md`): `RelationshipEdge` with
affinity/trust/respect/fear/rivalry/debt + type; Char↔Char, Player↔Char, Char↔Sect.
**Exit:** edges create/update/query + round-trip save; event→delta deterministic; tests pass.

## Phase 06 — Sect System
Core sects (`docs/SECT_SYSTEM.md`): `SectTemplateData` + `SectState`, membership/ranks,
resources/territory/reputation, alliances mirrored as relationship edges. Canonical
membership = sect roster (D-015).
**Exit:** add a sect via data only; `SectState` round-trips; membership stays in sync with
`CharacterState`; tests pass.

## Phase 07 — Faction / Sect Politics
Internal factions + emergent politics (`docs/SECT_SYSTEM.md` §7): `FactionState`,
influence, attitudes toward player/other factions, resolved as rules over data.
**Exit:** multi-faction sect authored via data; a faction influence/attitude change
produces documented, deterministic outcomes; round-trips; tests pass.

## Phase 08 — World Simulation
LOD simulation (`docs/WORLD_SIMULATION.md`): Near real-time / Far abstract; schedule/tick/
event/state-transition drivers; promotion/demotion; seeded determinism; save-resumable.
**Exit:** seeded K-tick run reproduces identical state; promotion/demotion loses no
persistent state; save mid-sim + load resumes; catch-up within budget; perf test passes.

## Phase 09 — Combat
Single documented damage formula (domain, pure), Hitbox/Hurtbox, basic attack, seeded RNG.
Combat emits events only. Timing model decided here (D-007).
**Exit:** deterministic damage from data; damage/combat unit + integration tests pass.

## Phase 10 — Enemy AI
EnemyData-driven enemies, AIComponent with controlled tick rate, spawn tables.
**Exit:** add a new enemy via data only; AI tick-rate measured; no per-frame churn.

## Phase 11 — Progression
XP curve, level. Reacts to combat events.
**Exit:** XP → level works; serializable; tests pass.

## Phase 12 — Cultivation
Cảnh giới / tu luyện breakthrough rules (the second progression axis, distinct from level).
Gates content/capability, not just numbers (`.kiro/steering/02-game-design.md`).
**Exit:** cultivation → realm unlocks work; serializable; breakthrough rules tested.

## Phase 13 — Item
InventoryComponent (serializable), item pickup/use, ItemData.
**Exit:** add/use/drop items via data; inventory ops unit-tested; serializes/restores.

## Phase 14 — Equipment
EquipmentData, equip/unequip applying stat modifiers through the damage formula.
**Exit:** equipment changes damage deterministically; covered by tests.

## Phase 15 — Skill
SkillComponent, SkillData (active/passive), cooldowns, mana/linh khí cost, công pháp
gating of usable skills.
**Exit:** add a skill via data; cooldown/cost/gating tested.

## Phase 16 — Pet
PetData, pet as an Entity with ally AIComponent; follows/assists in combat.
**Exit:** add a pet via data; pet state serializes; combat assist tested.

## Phase 17 — NPC
NPC interaction & services (shops) built **on** the Character/Sect/Relationship systems.
**Exit:** interact + trade; shop state serializes; standing uses the relationship graph.

## Phase 18 — Dialogue
DialogueData (localization keys), dialogue runner, choices feeding story + relationship +
sect state.
**Exit:** branching dialogue in `vi` + `en`; choices set flags/relationship deltas; tested.

## Phase 19 — Quest
Quest FSM (domain), QuestData, objectives driven by EventBus; quests arise from and affect
characters/sects/politics.
**Exit:** add a quest via data; full lifecycle incl. serialize mid-quest; tested.

## Phase 20 — Story
Story/flag engine; branches read character/sect/faction state + flags; chapter loop +
world-state-change feedback (`docs/GAME_FLOW.md` §1b).
**Exit:** a branch diverges on a prior choice/relationship/faction state; chapter
transition works; tested.

## Phase 21 — Dungeon
DungeonData, instance modifiers on top of map+combat+loot.
**Exit:** add a dungeon via data; clear/exit cleanly; tested.

## Phase 22 — Boss
BossData with phases, boss AI; chapter-gating defeat.
**Exit:** add a boss via data; phases trigger; `boss_defeated` gates chapter; tested.

## Phase 23 — Save / Load
Full versioned save/load across all systems (incl. character/relationship/sect/world-sim);
migration framework. Save format decided here (D-005). See `SAVE_FORMAT.md`.
**Exit:** save/load round-trips every system's state; a v1→v2 migration demonstrated;
save/load tests pass.

## Phase 24 — Localization
Full `vi`/`en` content pass; verify no hard-coded strings; font glyph coverage. (The
localization *foundation* and mechanism land in Phase 01 / D-008; this phase is the full
content sweep.)
**Exit:** key-coverage test green for both languages; no literal UI strings in code.

## Phase 25 — UI
Production UI/HUD stack, menus, the full input-modal ownership built on the Phase 01
input-gating rule.
**Exit:** core screens navigable; UI never drives gameplay truth; tests pass.

## Phase 26 — Audio / VFX
Music, SFX, feedback, transition polish.
**Exit:** audio/VFX hooks event-driven; no per-frame waste; smoke pass.

## Phase 27 — Vertical Slice
One cohesive end-to-end slice (prologue → village → quest → combat → progress → save) using
real systems, to validate the whole flow.
**Exit:** the slice is playable start-to-finish offline; no placeholder-only systems in it.

## Phase 28 — Full Audit
Cross-system audit: architecture boundaries, state ownership, determinism, doc consistency,
test coverage of high-risk areas.
**Exit:** audit report with no unresolved critical findings.

## Phase 29 — Performance
Profiler-driven only. Pooling where churn is proven. Each optimization logged in
`PERFORMANCE.md` (problem/cause/solution/impact/measurement).
**Exit:** frame-time/allocation budgets met on target hardware; optimizations logged.

## Phase 30 — Release Candidate
Build pipeline, export presets, credits (asset attributions from `ASSET_LICENSES.md`),
final regression + smoke pass.
**Exit:** reproducible export; all attributions satisfied; regression suite green.

## Phase 31 — Offline Release
Ship the offline game. Offline remains the source of truth.
**Exit:** released build tagged; post-release monitoring/debug playbook in place.

## Phase 32 — Multiplayer Readiness Audit
*Research + readiness only, still no shipped networking.* Validate the Stage-2 seams hold
(serializable player/world/inventory/progression **and** character/relationship/sect/
faction/world-sim state, in persistent/runtime/presentation tiers; command intents;
authoritative-state boundary). See `MULTIPLAYER_PLAN.md`.
**Exit:** documented gap analysis per seam + a go/no-go recommendation. No networking
dependency merged into the offline game.

## Phase 33 — Multiplayer Foundation
*Only if 32 is go.* Transport/authority scaffolding behind the existing command-intent and
authoritative-state seams. Domain rules remain transport-agnostic.
**Exit:** a vertical networked prototype of one seam, domain code unchanged in substance.

## Phase 34 — Multiplayer Gameplay
*Only if 33 succeeds.* Extend networking across the authoritative systems incrementally.
**Exit:** co-op/PvE slice runs authoritatively; offline remains fully playable.

## Guardrails across all phases
- Offline is the source of truth until the multiplayer phases are explicitly approved.
- No premature abstraction; content added as data + scenes.
- High-risk logic (damage, combat, inventory, progression, XP, level, cultivation,
  skill, quest, save/load, localization, map transitions) ships with tests.
- Character / Sect / Relationship / Faction / World-Sim are core domain systems, not NPC
  decoration (D-011); their authoritative state is domain-owned and serializable.
