# CHANGELOG — Aetheria

All notable changes to this project are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); the project uses
[Semantic Versioning](https://semver.org/) once it ships builds.

Dates are ISO (YYYY-MM-DD).

## [Unreleased]

### 2026-10-02 — Phase 02 Final Hardening (contract/invariant/doc consistency, no new scope)
- **Semantic-input E2E (real boundary):** the player E2E (`tests/e2e/player_flow_case.gd`)
  now drives movement and attack through the actual InputMap → `InputService` → Player
  path (`Input.action_press("move_right")` / `Input.action_press("attack")`), not direct
  `MovementComponent.apply_intent` / `resolve_player_attack()` calls. Added an input-gating
  regression (attack does NOT fire in MENU context, DOES in GAMEPLAY) and a teardown that
  releases pressed actions + asserts no orphan / no duplicate autoload / legal GameState.
- **Collision single source of truth:** Player / Training Dummy / sandbox walls now set
  `collision_layer`/`collision_mask` from `CollisionLayers.*` at runtime (Player =
  PLAYER + mask WORLD|DUMMY; Dummy = DUMMY, mask 0; walls = WORLD). Added an integration
  test that fails if the constants and runtime wiring drift.
- **MovementComponent contract:** `apply_intent(intent, speed, _delta := 0.0)` — the
  Phase-02 contract's `delta` is explicit but intentionally unused (`move_and_slide` owns
  physics integration; no `velocity * delta`). Player passes `delta`; tests updated.
- **Health death/reset invariant made consistent:** reworded from "`died` once, ever" to
  "`died` once PER LIFE (per `initialize()` cycle)", matching `TrainingDummy.reset_dummy()`
  (a new life can die again). Added regression tests (no duplicate `died` within a life;
  re-initialize → second-life death). No resurrection added.
- **Stats fail-closed:** `Player._ready()` / `TrainingDummy._ready()` now branch on
  `StatsComponent.validate()`; an invalid/missing StatBlock reports loudly and the entity
  stays inert (Player disables physics) instead of half-running. `validate()` no longer
  `assert()`-aborts (loud `push_error` + checked return is the robust fail-loud-and-closed
  contract). Added a fail-closed test.
- **Docs sync:** `01-product` core-systems phases 11–15 → 04–08; `SAVE_FORMAT` migration
  references Phase 17 → 23; `TEST_PLAN` status line updated to the post-Phase-02 reality.
- No new scope: no combat system, no AI, no Character/Save/Inventory/networking, no new
  autoload. D-003 / D-005 / D-007 remain Open. Sandbox remains the temporary Phase-02
  validation scene.

### 2026-10-02 — Phase 02 Player Core (first playable; no combat system)
- **Player entity (composition, D-020):** `CharacterBody2D` under `src/gameplay/entities/`
  composed of `StatsComponent` + `HealthComponent` + `MovementComponent`
  (`src/gameplay/components/`). No inheritance chain, no God object; `player.gd` only
  coordinates (reads semantic intent, forwards movement, exposes an attack intent). Reads no
  physical keys — input flows only through `InputService`.
- **Top-down movement:** 8-direction, diagonals normalized (not faster than cardinal),
  collision-aware via `move_and_slide`, speed from stats. `MovementComponent.apply_intent`
  is the intent boundary a future network command reuses (MP seam).
- **Stats as data:** `StatBlock` Resource (`src/data/stats/stat_block.gd`, DATA_SCHEMA §1
  field names) with authored numbers in `data/stats/player_stats.tres` /
  `training_dummy_stats.tres`. Invariants validated at the boundary.
- **Health:** enforced invariants (`0<=hp<=max`), `apply_damage`/`heal` return applied
  amount, non-positive rejected, `died` emitted exactly once, DEAD terminal (no revive).
  Direct signals to owner; no new EventBus signals.
- **Minimal damage rule (NOT a combat system):** one pure domain function
  `src/domain/combat/damage_rules.gd` — a deterministic slice of the DATA_SCHEMA §2 formula
  (no RNG/crit/resist/skill/equipment). D-007 (combat timing) stays Open.
- **Training Dummy:** `StaticBody2D` reusing the same Stats/Health components, no AI, no
  movement, `reset_dummy()`; deterministic retaliation driven by the sandbox coordinator.
- **Player Sandbox (temporary first scene):** `src/gameplay/sandbox/player_sandbox.tscn` —
  Player + Dummy + walls + camera + localized HUD. New Game now routes here
  (`FIRST_SCENE_KEY` in `main.gd`) instead of the prologue shell; documented as a Phase-02
  gameplay-validation scene that Phase 03 replaces. Coordinator owns the range check + the
  bidirectional damage exchange via the domain rule.
- **Collision layers** named constants (`src/gameplay/collision_layers.gd`).
- **Localization:** added `UI_SANDBOX_HINT` / `UI_SANDBOX_PLAYER_HP` / `UI_SANDBOX_DUMMY_HP`
  (vi + en).
- **Tests:** unit (damage rule, health invariants + death-once, movement math, stat
  validation), integration (player wiring + real-physics movement + bidirectional damage
  exchange, fresh instances), gameplay smoke (sandbox structural, no Main boot), and a
  dedicated isolated **player E2E** process (`tests/e2e/run_player_flow.gd` +
  `player_flow_case.gd`) — New Game → sandbox → move → attack → death → cleanup. CI gained an
  8th gate for it; `test_app_flow` updated to expect `player_sandbox` as the first scene.
- No combat system, no AI, no inventory/equipment/skill/cultivation, no save/load, no
  networking, no new autoloads. D-003 / D-005 / D-007 remain Open.

### 2026-10-02 — Phase 01 Test Isolation + Boot Contract Hardening (no gameplay)
- **Fixed — cross-test singleton contamination (D-019):** the previous
  `tests/integration/test_app_flow.gd` spawned duplicate `/root` autoloads and booted Main
  on the REAL `GameState` autoload, leaving it at `RUNNING`. A later in-runner boot then hit
  `illegal transition RUNNING -> INITIALIZING`. Removed that test; the real-application E2E
  now runs in its **own isolated Godot process** (`tests/e2e/run_app_flow.gd` +
  `tests/e2e/app_flow_case.gd`), using the ACTUAL project autoloads and driving the real
  `MainMenu.new_game_pressed` intent — no duplicate autoloads, nothing to contaminate.
- **Added — isolation guard in `tests/run_tests.gd`:** snapshots the shared
  `/root/GameState` phase and FAILS the suite if any test leaves it changed (detection, not
  reset). `tests/e2e/` is excluded from in-runner discovery.
- **Changed — smoke test is structural-only:** `tests/smoke/test_boot.gd` no longer boots
  Main into the shared tree; it validates the static Systems/World/UI shell without running
  the lifecycle. The real boot contract is asserted by the E2E process.
- **Changed — Main requires all 5 autoloads (D-019):** `REQUIRED_AUTOLOADS` =
  EventBus, GameState, Localization, InputService, SceneRouter. Missing any → fail loud,
  abort boot, no silent fallback. Removed the "zero autoloads = tolerate" escape.
- **Changed — Main checks every required lifecycle bool:** `begin_initialization`,
  `mark_ready`, `enter_menu`, `confirm_session_running`. A rejected `confirm_session_running`
  now unwinds to menu instead of faking RUNNING.
- **CI:** added a 7th gate running the dedicated E2E process; no swallowed exit codes.
- **Docs:** D-019 added; TEST_PLAN updated (runner has project autoloads; isolation
  boundary; E2E own process); lesson L-010 recorded. No gameplay, no networking, no Phase 02
  (Config/RNG/SaveService still deferred per D-017).

### 2026-10-02 — Phase 01 Final Hardening (close contract/test/invariant gaps, no gameplay)
- **Fixed — GameState persistence invariant (D-018):** `to_dict()` now serializes only run
  identity + location (never `session_active`, never the lifecycle phase) and returns `{}`
  when no session is active. Loading moved to `hydrate_session(data)` (data-only; does not
  drive the lifecycle) which rejects an invalid snapshot (no `run_id`) and an unsafe phase
  (only `MENU`/`READY`); `from_dict()` is now a `bool`-returning alias. This removes the
  previously-possible invalid `phase==BOOT && session_active==true` reload state.
- **Fixed — magic input ints (D-018):** added semantic `InputService.set_gameplay_context()`
  / `set_menu_context()` / `push_modal_context()`; the raw stack reset is now private
  `_reset_to()`. Menu + first scene no longer pass enum ints.
- **Fixed — input ownership (D-018):** `prologue_shell` resolves `open_menu` via
  `InputService.is_system_action_just_pressed(&"open_menu")` instead of reading the raw
  input event.
- **Fixed — boot fail-fast (D-018):** `Main` aborts boot loudly if a required core autoload
  (`GameState`/`SceneRouter`/`EventBus`) is missing in a real run (headless test harness,
  with zero autoloads, still runs the null-safe path); `_boot()` checks transition results.
- **Removed — speculative EventBus signals (D-018):** `new_game_requested`,
  `session_started`, `session_ended` (no real producer+consumer in Phase 01). Kept
  `game_booted`, the three `scene_transition_*`, and `language_changed`.
- **Tests added/updated:** GameState persistence-invariant suite; InputService semantic
  setters; SceneRouter failure/cleanup cases A–F; EventBus "holds no business state"; and a
  real end-to-end `tests/integration/test_app_flow.gd` that stands up the actual autoloads,
  instantiates `main.tscn`, drives the real `MainMenu.new_game_pressed`, and asserts a
  RUNNING session with the prologue content scene loaded (then tears down with no orphans).
- **Docs:** ROADMAP Phase 01 → CLOSED, Phase 02 NOT STARTED; corrected the one-off
  `2026-10-03` → `2026-10-02` date across docs; D-018 added. No gameplay, no networking,
  no Phase 02 work (Config/RNG/SaveService still deferred per D-017).

### 2026-10-02 — Phase 01 Core Framework (runtime skeleton, no gameplay)
- **Lifecycle + session:** `GameState` autoload — explicit lifecycle state machine
  (`BOOT→INITIALIZING→READY→MENU→STARTING_SESSION→RUNNING→TRANSITIONING/PAUSED`), runtime
  session state (run_id, current world/map/scene ids), intent-revealing methods, illegal
  transitions rejected loudly, `to_dict/from_dict` seam, no disk I/O, no presentation refs.
- **EventBus** autoload — minimal cross-system signals for Phase 1 only (boot, scene
  transition, language). Emitters never reference listeners. *(Speculative session signals
  removed in the hardening pass — see D-018.)*
- **Localization** autoload — vi/en via a CSV table (`locale/aetheria.csv`), `t()`/`t_args()`
  with `{placeholder}` substitution, `set_language/get_language`, missing-key returns the
  key + warns. Backing format decided (D-008: CSV).
- **InputService** autoload — semantic input intent over named InputMap actions + input
  gating ownership (context stack UI_MODAL > MENU > GAMEPLAY). No physical-key leakage.
- **SceneRouter** autoload — the single scene-transition entry point; swaps content under
  `Main/World`, guards duplicate/stale/invalid/leak, explicit success/failure, records
  location in GameState. Keeps map strategy open (D-003).
- **Semantic InputMap** in `project.godot`: move_up/down/left/right, interact, attack,
  skill_1..4, dodge, open_menu, pause.
- **Presentation shells:** localized main menu (New Game / Quit; Load Game disabled) and a
  non-gameplay first-scene (`prologue_shell`) proving router + gamestate + input ownership.
- **Bootstrap** `main.gd` rewired as a thin coordinator (BOOT → MENU → New Game → first
  scene) — not a God object.
- **Autoloads justified** in `DECISIONS.md` D-017 (5 autoloads; Config/RNG/SaveService
  deliberately deferred). **D-008 Accepted** (CSV).
- **Roadmap reordered** to 35 phases (00–34): Character/Relationship/Sect/Faction/World-Sim
  moved to 04–08 (before Combat 09); Save→23; Multiplayer→32–34. Phase-number references in
  `DECISIONS.md` blocking lines updated (D-003→03, D-005→23, D-007→09, D-008→01/24).
- **Tests:** `tests/unit/core/` (GameState, SceneRouter, EventBus, Localization,
  InputService) + `tests/integration/test_boot_flow.gd` (boot→menu→new game→first scene).
- No gameplay, no networking.

### 2026-10-02 — Phase 0 CLOSED (documentation close-out, no gameplay)
- **Foundation hardening verified by CI.** GitHub Actions job "Foundation gates
  (Godot 4.7)" ran on commit `651c16f` with `conclusion=success` (confirmed via the
  GitHub check-runs API).
- **Runtime boot smoke — verified by CI:** project boots `application/run/main_scene`,
  `Main._ready()` runs, clean exit (`--quit-after 2`).
- **Parse check — verified by CI:** `tools/parse_check.gd` found no GDScript parse errors.
- **Headless test suite — verified by CI:** `tests/run_tests.gd` ran green (`RESULT: PASS`).
- **Phase 0 → READY FOR PHASE 1.** `docs/PHASE_0_EXIT_CHECKLIST.md` all blocking items
  [x]; `docs/ROADMAP.md` Phase 0 marked CLOSED, Phase 1 (Core) is next and not started.
- **Docs synced to verified state:** D-012 marked Accepted & verified; D-009 clarified
  (local-agent limitation only, CI ran Godot for real); removed "pending CI"/"first green
  run" wording across ROADMAP/checklist.
- No gameplay, no Phase 1 work.

### Changed / Added — 2026-10-02 — Foundation hardening (Phase 0, no gameplay)
- **Smoke test now really boots:** `tests/smoke/test_boot.gd` adds Main to the live
  SceneTree (runs `_ready`), asserts `is_inside_tree` + Systems/World/UI + bootstrap
  self-validation, cleans up with no orphan nodes; added a negative structure test.
- **Test runner hardened:** `tests/run_tests.gd` rewritten — recursive (nested) discovery,
  deterministic order, SceneTree injection, `await` per method, non-zero exit on
  fail/empty/missing-required. `tests/framework/test_case.gd` gained SceneTree helpers.
- **Nested-discovery + fail-detection proof:** `tests/unit/framework/test_nested_discovery.gd`.
- **Project-wide parse check:** `tools/parse_check.gd` (loads every `.gd` under
  src/tests/tools; CI gate).
- **CI hardened:** `.github/workflows/ci.yml` — removed `|| true`; gates checkout → Godot
  4.7 → import → parse check → runtime boot (`--quit-after 2`) → test suite; no swallowed
  failures.
- **Hooks split (D-016):** PostFileSave runs the lightweight parse check;
  `run-full-tests-on-task.json` (PostTaskExec) runs the full suite.
- **Authority contract (D-015):** sect membership canonical source = `SectState` roster;
  `CharacterState` sect fields are a derived cache. Annotated across CHARACTER/SECT/
  DATA_SCHEMA/SAVE_FORMAT.
- **Doc consistency:** fixed stale "empty `main.tscn`"/"no scripts" (ARCHITECTURE),
  "3D physics enabled" (01-product), and "pending first green CI" (ROADMAP); logged in
  DECISIONS D-013 (items 5–7).
- **New:** `docs/PHASE_0_EXIT_CHECKLIST.md` (gates Phase 0 → READY FOR PHASE 1 on a green CI).

### Changed / Added — 2026-10-02 — Foundation review + fix (Phase 0 completion, no gameplay)
- **Project identity:** `config/name` `New_Game_Project` → `Aetheria` (D-006 Accepted).
- **2D config cleanup:** removed the `[physics]` section (3D `Jolt Physics` leftover) —
  game is 2D-only (D-002 Accepted). Added `textures/canvas_textures/default_texture_filter=0`
  (nearest, for pixel art). Set `run/main_scene="res://main.tscn"`.
- **Bootstrap:** `main.tscn` is now a real bootable scene — `Main` (`Node2D`, script
  `src/bootstrap/main.gd`) with `Systems` / `World` / `UI` children (D-010).
- **Test framework (D-004 Accepted → custom headless runner):**
  `tests/framework/test_case.gd` (`TestCase` + `assert_*`), a real `tests/run_tests.gd`
  (discovers `test_*.gd`, non-zero exit on failure), and a real smoke test
  `tests/smoke/test_boot.gd`. Removed the placeholder behavior and `smoke/.gdkeep`.
- **Core-system design (design only, no gameplay):** new docs `CHARACTER_SYSTEM.md`,
  `RELATIONSHIP_SYSTEM.md`, `SECT_SYSTEM.md`, `WORLD_SIMULATION.md`; updates to
  `GAME_FLOW`, `DATA_SCHEMA`, `MULTIPLAYER_PLAN`, `ROADMAP`, and steering 01/02/03 to make
  Character / Relationship / Sect / Faction / World-Simulation core systems (D-011).
- **CI:** added `.github/workflows/ci.yml` (checkout → Godot 4.7 → import → headless
  tests) (D-012).
- **AI review protocol:** added the `READ → PLAN → IMPLEMENT → TEST → REVIEW → DOCS` loop
  and pre-completion review gates.
- **Decisions resolved:** D-002, D-004, D-006 → Accepted; added D-009 (local Godot
  unavailable to agent), D-010, D-011, D-012, D-013 (doc-review findings).

### Known limitation — 2026-10-02
- The AI agent could not run Godot headless locally (no binary on PATH / common dirs /
  registry — D-009). All scripts validated via the GDScript language server (zero errors);
  authoritative headless run is CI. Manual command:
  `godot --headless --path . -s res://tests/run_tests.gd`.

### Added — 2026-10-02 — Project foundation (docs & process, no gameplay)
- Steering rules in `.kiro/steering/`:
  `01-product`, `02-game-design`, `03-architecture`, `04-coding-standards`,
  `05-performance-testing`, `06-art-assets`, `07-localization`,
  `08-ai-review-protocol`.
- Core docs in `docs/`:
  `GAME_FLOW` (central flow + per-system contracts), `ARCHITECTURE` (layered design),
  `ROADMAP` (22 phases, Foundation → Multiplayer preparation), `TEST_PLAN`,
  `PERFORMANCE`, `ASSET_LICENSES`, `DATA_SCHEMA`, `SAVE_FORMAT`, `MULTIPLAYER_PLAN`,
  `DECISIONS`, `DEBUGGING`, and this `CHANGELOG`.
- `tests/` scaffold: `unit/ integration/ gameplay/ smoke/ performance/`, a `README`,
  and a placeholder headless runner `run_tests.gd`.

### Noted / flagged (from repo audit) — 2026-10-02
- Project still named `New_Game_Project` (rename to `Aetheria` planned — `DECISIONS.md`
  D-006).
- 3D physics engine (`Jolt Physics`) enabled on a 2D game — flagged for cleanup
  (`DECISIONS.md` D-002).
- `icon.svg` is the stock Godot placeholder icon — `ASSET_LICENSES.md`; replace before
  release.
- Open decisions pending: test framework (D-004), map strategy (D-003), save format
  (D-005), combat timing model (D-007), localization format (D-008).

### Not done (by design, as of 2026-10-02)
- No gameplay implemented. `main.tscn` was a single empty `Node2D`.
  *(Superseded 2026-10-02: `main.tscn` is now a non-gameplay bootstrap scene — see the
  2026-10-02 entry above.)*
- No networking / multiplayer code.

---

## How to update
- Add changes under **[Unreleased]** grouped as Added / Changed / Fixed / Removed /
  Deprecated / Security.
- When a build is cut, replace **[Unreleased]** with a version + date and start a fresh
  Unreleased section.
- Keep entries short and factual; link to `DECISIONS.md` / `PERFORMANCE.md` for detail.
