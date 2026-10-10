# TEST_PLAN — Aetheria

> Testing strategy. Rules summary: `.kiro/steering/05-performance-testing.md`.
> Goal: **not** blind 100% coverage — strong coverage of high-risk logic, cheap smoke
> coverage of the whole flow, and every fixed bug pinned by a regression test.
>
> **CURRENT STATUS (through Phase 15 + D-063 Phase A closeout):** strategy defined;
> runner + framework in place. The suite covers the core framework (lifecycle/scene-router/
> input/localization/event-bus/settings), the **session lifecycle contract** (the ordered
> teardown, D-047), the Player core (stats/health/movement/damage + player↔dummy integration),
> the World/Map system (MapData/MapCatalog validation, data-driven catalog, source-of-truth
> scene↔data checks, no-leak + transactional-rollback map transitions, data-driven camera
> bounds + follow, persistent player across 20 round trips), the Character core + the
> **character registry**, the Relationship core, the **Sect** core, the **Faction** core, the
> **World Simulation** core (clock, seeded RNG streams, LOD bands, determinism, resume,
> bounded catch-up, a performance budget), **Combat** (Phase 09: the attack lifecycle's
> frame-timing contract, hit resolution and its determinism, the gameplay components, the
> session runtime, a performance budget), **Enemy AI** (Phase 10: the pure-domain brain, target
> selection, leash, cadence, determinism, damage/attack feedback), **Level/XP Progression**
> (Phase 11 — inventory in the per-phase list below), and the UI/theme asset contracts — plus
> four dedicated
> real-application E2E processes (app-flow, player-flow, world-flow, pet-flow).
>
> **CI runs 11 gates** (see §5; the eleventh is the Phase-16 pet E2E). That number is the COUNT OF CI GATES and is unrelated to the
> number of stages in `docs/PHASE_EXECUTION_PROTOCOL.md` — the phase protocol has more review
> stages (pre-flight → … → final review) because most of them are human review steps that no
> CI job can run. Do not "reconcile" the two numbers.
>
> The in-runner suite tally is printed by the runner itself, never hand-counted, and is
> reported in the `DECISIONS.md` entry for the change that moved it. At D-057 the runner reports
> **`ran 716 test(s)`** with zero `SCRIPT ERROR:` lines and **zero leaked ObjectDB / resources
> at exit** (704 at the D-056 review pass, three of whose seven new tests were
> `tests/unit/framework/` tests that existed since Phase 0 but had never run). On some machines
> that reads `N-2 passed, 2 failed`: the two failures
> are the wall-clock performance budgets (`test_ai_budget`, `test_combat_budget`), which fail on
> some development machines and pass on the CI runner — known environmental debt recorded in
> D-054, deliberately not "fixed" by loosening another phase's gate. **The authoritative
> pass/fail is the CI check-run `Foundation gates (Godot 4.7)`**, which must be `success` on the
> pushed SHA before a change is done (L-007).
> Gameplay beyond world/map traversal + the social substrate + combat + progression is added
> phase by phase.
>
> *(Historical: the same tally read `282 passed` at the Phase-06 close-out on `1dabdba`. The
> phase notes further down are kept as written and still quote the numbers of their own time.)*

## 1. Test layers

| Layer | Scope | Runs | Example |
|---|---|---|---|
| **Unit** | one pure function/component, no scene tree where possible | headless, fast | damage formula, XP curve, breakthrough rule, inventory add/remove, quest FSM transition, save (de)serialize, localization lookup |
| **Integration** | several components together | headless | `xp_gained` → level up → skill unlock |
| **Gameplay** | scripted scenario in a minimal scene | headless | encounter resolves, quest completes end-to-end |
| **Regression** | reproduces a past bug | headless | the exact failing case, kept forever |
| **Smoke** | whole flow boots & basic paths work | headless + manual | boot → menu → new game → load each map → basic combat → save/load |
| **Performance** | budget assertions on hot paths | headless + profiler | frame-time / allocation budget on combat with N enemies |

## 2. High-risk areas (must have tests before a feature is "done")

damage · combat · inventory · progression · XP · level · cultivation · skill · quest ·
save/load · localization · map transitions.

These map directly to the systems in `docs/GAME_FLOW.md`. A feature touching any of
them is not done until it has tests (see `.kiro/steering/08-ai-review-protocol.md`).

## 3. Why domain is pure

The `domain` layer (damage, XP, cultivation, quest FSM, story) avoids node/scene
dependencies specifically so it can be unit-tested headless with no engine boot cost and
with a **seeded RNG** for determinism. This is the single biggest testability decision.

## 4. Framework (DECIDED — D-004: custom headless runner)

**Chosen: a minimal custom `SceneTree` runner** (`tests/run_tests.gd`) with a small
`TestCase` base (`tests/framework/test_case.gd`). Rationale (dependency cost, CI,
maintainability, unit/integration ability, stability) is in `docs/DECISIONS.md` D-004.
GUT was considered and deferred (revisit trigger noted in D-004).

How it works:
- A test file lives under `tests/<layer>/` named `test_<subject>.gd` and `extends TestCase`.
- It defines `test_*` methods and uses `assert_*` helpers (which *record* failures rather
  than throw, so every failure in a method is reported).
- The runner discovers all `test_*.gd`, runs every `test_*` method, prints
  `[PASS]`/`[FAIL]` per method, and **exits non-zero** if any assertion fails, if zero
  tests run, or if the required smoke test is missing.

Assertions available: `assert_true`, `assert_false`, `assert_eq`, `assert_ne`,
`assert_not_null`, `assert_null`. Hooks: `before_each` / `after_each`.

## 5. Running headless (pinned command)

The CI pipeline (`.github/workflows/ci.yml`) runs these gates in order, each failing the
job on a non-zero exit (none are swallowed):

```
# 1. static GDScript lint — NO ENGINE NEEDED, so it runs first and is also the on-save
#    gate a developer gets locally (D-033). Catches a local inferring Variant (a
#    warning-as-error that stops a class compiling), cross-file private access, long lines.
python3 tools/gdscript_lint.py --selftest   # the rules must still fire; checked first
python3 tools/gdscript_lint.py              # or `--changed` for just your edits

# 2. project-wide GDScript COMPILE check (src/ + tests/ + tools/): load + can_instantiate
#    + a declared `class_name` must actually be registered globally (D-033)
godot --headless --path . -s res://tools/parse_check.gd

# 3. runtime boot smoke — actually boots application/run/main_scene, runs Main._ready(),
#    then quits after 2 frames (verified flag per Godot 4.7 CLI docs)
godot --headless --path . --quit-after 2

# 4. headless test suite (custom runner)
godot --headless --path . -s res://tests/run_tests.gd
```

Then the four dedicated E2E processes (app / player sandbox / world-map / pet), one gate each —
11 gates in total. The pet gate also fails on any `SCRIPT ERROR:` or leak line in its log.

> **The headless-suite gate also fails on any `SCRIPT ERROR:`, even when the runner exits 0**
> (D-038). GDScript has no try/catch (D-004), so a VM error (a bad typed-array assignment, a
> call on null, a missing property) ABORTS the running test method rather than failing it: the
> method ends with zero recorded assertion failures and `run_tests.gd` prints `[PASS]` for a
> test that never ran. `push_error()` prints `USER ERROR:`, not `SCRIPT ERROR:`, so deliberate
> fail-closed negative tests do not trip this. The gate also emits the runner's own
> "ran N test(s)" line as a `::notice::` annotation — annotations are readable on the public
> check-run API while the log and the step summary are not (D-009), so the test count recorded
> in this document is quoted from CI rather than counted by hand.

Expected (suite) on success: per-test `[PASS]` lines, a summary, `RESULT: PASS`, exit
code **0**. On any failure: `[FAIL]` lines, `RESULT: FAIL`, exit code **1**. The linter
prints `[gdlint] PASS/FAIL` (findings as `path:line:col: CODE message`) and exits 0/1; the
compile check prints `[parse_check] RESULT: PASS/FAIL` and exits 0/1. The runtime boot
prints `[boot] Aetheria main scene ready...` and exits 0 if boot didn't crash.

> The lint, compile-check and world-E2E gates also emit their findings as GitHub
> annotations + step summary, because Actions logs need auth to read (D-009) — a bare
> "exit code 1" would otherwise cost a round-trip just to learn which rule fired.

> **SUPERSEDED (L-031): Godot DOES run locally.** The note below is kept for history. Run the
> whole gate set locally FIRST — it takes about three minutes — and push a change that is
> already green; CI remains the authority because it is the clean-room run and the gate
> definitions live in the workflow. The one thing still unverifiable headlessly is **anything
> on screen**: a layout or art claim needs a capture from `tools/playtest_flow.gd` (run WITHOUT
> `--headless`) and someone actually opening it.
>
> **Note (D-009, historical):** the AI agent could not run any of these locally — no Godot binary was
> reachable from its shell. All scripts were statically validated via the GDScript
> language server (zero errors). The authoritative run happens in CI (D-012) and can be
> run manually by any developer with Godot 4.7 installed.

## 6. Directory layout

```
tests/
  framework/
	test_case.gd   # TestCase base + assert_* API + SceneTree helpers (D-004)
  unit/
	framework/
	  test_nested_discovery.gd  # proves recursive discovery + harness fail-detection
	  test_record_numbering.gd  # every L-NNN lesson number used once, in order (D-056)
	  test_reference_library_isolation.gd  # nothing under docs/ is a Godot resource (D-057)
				   # RAN FOR THE FIRST TIME in the D-056 review pass: run_tests.gd excluded
				   # the folder NAME `framework` at any depth, not just tests/framework/
  integration/     # components together (fresh instances; never the live autoloads)
  e2e/             # real-application flow — OWN process (D-019), excluded from run_tests.gd
				   #   run_world_flow.gd + world_flow_case.gd (Phase 03 — world/map)
	run_app_flow.gd    # dedicated SceneTree entrypoint (adapter)
	app_flow_case.gd   # the E2E TestCase (reuses the shared assert_* API)
  gameplay/        # scripted scenarios
  smoke/
	test_boot.gd   # STRUCTURAL smoke: validates main.tscn shell WITHOUT booting Main (D-019)
  performance/     # budget assertions
  README.md        # how to run, how to add a test
  run_tests.gd     # custom runner — RECURSIVE discovery, isolation guard, non-zero on fail
tools/
  parse_check.gd   # project-wide parse check (CI gate)
```

## 7. Conventions

- Test file names: `test_<subject>.gd` (e.g. `test_damage_formula.gd`).
- One behavior per test; arrange–act–assert; deterministic (seed all RNG).
- A reproduced bug becomes a permanent test in `tests/` referencing the issue.
- Content/data tests assert loaded Resources are valid (no missing localization keys,
  no null required fields).

## 8. What we deliberately do NOT test

- Exact pixel output / art.
- Trivial getters/setters with no logic.
- Third-party engine behavior (trust Godot).

## 9. Current status

`tests/` has the layer folders, `framework/test_case.gd`, a real `run_tests.gd` runner, a
smoke test `smoke/test_boot.gd`, and a nested-discovery proof `unit/framework/`.

**Phase 01 added Core tests:**
- `tests/unit/core/test_game_state.gd` — lifecycle valid/invalid transitions, new-game
  flow, session survives a transition, end-session clears, and the **persistence invariant
  (D-018)**: `to_dict()` carries no phase/`session_active`, empty when no session,
  `hydrate_session()` restores a run without fabricating a phase, rejects an invalid
  snapshot and an unsafe phase, `from_dict()` alias behaves identically.
- `tests/unit/core/test_scene_router.gd` — valid/invalid/no-host transitions, replace +
  cleanup (no leak), clear, idle state, plus **failure/cleanup cases A–F**: `transition_failed`
  payload, registered-but-missing-resource, a failed transition preserves the current
  scene (transactional), router left idle after a failure, clear-when-empty is safe.
- `tests/unit/core/test_event_bus.gd` — delivery + payloads for all kept signals, and
  **the bus holds no business state** (exactly one script var: the `debug_log` flag).
- `tests/unit/core/test_localization.gd` — vi/en lookup, switching, unsupported rejected,
  missing-key behavior, `{placeholder}` substitution.
- `tests/unit/core/test_input_service.gd` — all semantic InputMap actions exist, gating
  priority (modal > menu > gameplay), baseline-context protection, and the **semantic
  context setters** (`set_gameplay_context`/`set_menu_context`/`push_modal_context` reset
  the stack so no stale modal survives — D-018).
- `tests/integration/test_boot_flow.gd` — BOOT→MENU→NEW GAME→SESSION→FIRST SCENE driving
  GameState + SceneRouter directly (fresh instances), then clean return to menu.

**Phase 01 hardening (D-019) — test isolation + a dedicated E2E process:**
- `tests/e2e/run_app_flow.gd` + `tests/e2e/app_flow_case.gd` — **real end-to-end** run in a
  SEPARATE Godot process (its own CI gate). It uses the ACTUAL project autoloads under
  `/root`, boots the real `main.tscn`, drives the real `MainMenu.new_game_pressed` intent,
  and asserts the chain reaches RUNNING (the first gameplay scene `player_sandbox` loaded,
  one scene under `World`, input context GAMEPLAY, no duplicate autoload) then tears down
  with no orphan. It is isolated on purpose: booting Main drives the shared `GameState`
  singleton, which must not happen
  inside the common runner.
- `tests/run_tests.gd` **isolation guard** — the project autoloads are live under `/root`
  even in the runner process; the runner snapshots the shared `GameState` phase and FAILS
  the suite if any test leaves it changed (so cross-test singleton contamination can't pass
  silently). It excludes `tests/framework/` and `tests/e2e/` from discovery.
- `tests/smoke/test_boot.gd` is **structural only** — it validates `main.tscn`'s
  Systems/World/UI shell WITHOUT entering the tree (so it never mutates the shared
  GameState). The real boot lifecycle is the E2E process's job.

> **Runner has project autoloads (D-019).** `godot --headless --path . -s res://tests/run_tests.gd`
> loads the five `[autoload]` services under `/root`. Unit/integration tests therefore use
> **fresh `Script.new()` instances**, never the live singletons, and nothing in the runner
> boots `Main`. The real-application boot is the dedicated E2E process. This is the boundary
> between unit/integration isolation and application E2E.

**Phase 02 added Player tests (high-risk: damage/health/movement):**
- `tests/unit/gameplay/test_damage_rules.gd` — the pure domain damage slice: zero-defense =
  full attack, defense reduces, floor at 1, negative inputs clamp, deterministic, more
  defense never increases damage.
- `tests/unit/gameplay/test_health_component.gd` — starts full, damage reduces + returns
  applied, clamps to 0 + kills, `died` exactly once, heal restores + clamps to max,
  negative/zero damage & heal rejected, DEAD terminal (no revive, no further damage),
  `0<=hp<=max` invariant across ops, partial-current init.
- `tests/unit/gameplay/test_movement_component.gd` — `resolve_velocity` pure math: zero
  intent, cardinal full speed, diagonal normalized (not faster), all 8 dirs same speed,
  speed scales, zero/negative speed → zero.
- `tests/unit/gameplay/test_stats_component.gd` — StatBlock invariants + StatsComponent
  reads + validation, and the authored `.tres` content is well-formed.
- `tests/integration/test_player_components.gd` — the Player scene has its components,
  health initializes from stats, damage/death flow through the player, and a REAL physics
  step moves a body under movement intent (and zero intent keeps it still). Fresh instances.
- `tests/integration/test_damage_exchange.gd` — bidirectional damage contract: player →
  dummy and dummy → player via the domain rule, dummy reset + deterministic death. Fresh
  instances; no autoload mutation.
- `tests/gameplay/test_player_sandbox.gd` — the sandbox scene is structurally sound
  (Player + Dummy + walls + camera + HUD + the return-to-menu contract) WITHOUT booting it
  into the tree (so it never mutates the shared InputService).
- `tests/e2e/run_player_flow.gd` + `tests/e2e/player_flow_case.gd` — **dedicated isolated
  process**: boots the real app, New Game → Player Sandbox, then drives the REAL semantic
  input boundary — `Input.action_press("move_right")` → `InputService` → Player movement,
  and `Input.action_press("attack")` → Player `attack_requested` → sandbox coordinator →
  `DamageRules` (bidirectional damage). Includes an input-gating regression (attack does
  NOT fire in MENU context, DOES fire in GAMEPLAY), deterministic repeated-hit death
  (died once per life), and a no-orphan / no-duplicate-autoload teardown that releases all
  pressed actions. Its own CI gate. It does NOT shortcut through `MovementComponent.apply_intent`
  or `resolve_player_attack()` (those direct calls are only in unit/integration layers).

**Phase 02 hardening added:**
- `test_player_components.gd` — collision wiring from the `CollisionLayers` single source
  of truth (Player on PLAYER + collides WORLD|DUMMY; Dummy on DUMMY, mask 0) and a
  **fail-closed** check (a Player with a missing/invalid StatBlock disables its physics
  instead of half-running).
- `test_health_component.gd` — death/reset lifecycle: no duplicate `died` within a life;
  re-initialize begins a new life so the entity can die again (one `died` PER LIFE), matching
  `TrainingDummy.reset_dummy()`.

**Phase 03 added World/Map tests (high-risk: map transitions):**
- `tests/unit/world/test_map_data.gd` — `MapData` / `MapExit` / `MapCatalog` validation
  (D-022): required fields incl. `scene_path` exists, positive `bounds`, `default_spawn_id`,
  unique exit `id`s; catalog unique map ids / scene_keys + no dangling exit; `find_exit(id)`
  + `build_lookup`; and the authored `map_hub.tres`/`map_field.tres`/`map_catalog.tres` are
  valid with a bidirectional hub↔field graph.
- `tests/integration/test_map_transitions.gd` — the REAL `SceneRouter` (fresh instance,
  never the live autoload) registers scenes from `MapData.scene_path`, loads both maps, and
  **repeated** hub↔field transitions do not grow the orphan-node count; clearing frees the
  active scene; an unregistered key is rejected; and the **transactional-rollback invariant**
  (a rejected transition leaves the current scene intact + router not stuck + a later valid
  transition still works) is asserted — this is what `WorldRuntime`'s rollback relies on.
- `tests/gameplay/test_map_scenes.gd` — SOURCE-OF-TRUTH consistency between each map scene
  and its `MapData` (D-022): every `MapExitZone.exit_id` resolves to a `MapExit`, the
  `default_spawn_id` marker exists, each exit's `entry_point` lands on a real marker in the
  destination scene, the structure (Camera2D / Visual/Ground `TileMapLayer` / Collision/Walls
  / PlayerHost / Spawns / Exits / HUD/MapLabel) is present, and the floor renders via the
  prototype `TileMapLayer` (not a Polygon2D). Instantiated but NOT entered into the tree
  (no shared-InputService mutation).
- `tests/e2e/run_world_flow.gd` + `tests/e2e/world_flow_case.gd` — **dedicated isolated
  process** (the last CI gate): boots the real app, New Game → hub map, does a REAL semantic
  movement step, then drives interact / open_menu through the REAL input pipeline
  (`Input.parse_input_event` key events — NEVER a direct `_unhandled_input` call) across
  **20 round trips**, asserting per round: map changed, the SAME persistent Player instance,
  exactly one Player, player in the active map, one content scene, GameState map id == router,
  camera limits from `MapData.bounds`, router not stuck — plus no orphan-node growth; then a
  REAL `open_menu` returns to the menu and frees the player. The only headless concession is
  emitting the exit sensor's own `body_entered` signal (L-016/L-017). The Phase-02 player
  E2E instantiates `player_sandbox.tscn` directly; the app-flow E2E expects `map_hub` first.

**Phase 04 added Character + UI tests (high-risk: character state / life-state / save seam):**
- `tests/unit/character/test_character_template_data.gd` — `CharacterTemplateData` validation
  at the content boundary (missing id/name_key/base_stats, invalid StatBlock, negative age,
  out-of-range enum) and that the shipped `player_default.tres` loads + is valid.
- `tests/unit/character/test_character_state.gd` — `create_from_template` copies identity +
  stats (value copies, not shared with the template), rejects null/empty id; `mark_dead`
  transitions ALIVE→DEAD exactly once (DEAD terminal, cause recorded once); `set_current_hp`
  clamps and does NOT change life_state; `to_dict`/`from_dict` round-trips the persistent tier
  (incl. wounded HP and the DEAD state), `from_dict` rejects invalid snapshots, and the
  serialized dict carries NO presentation/runtime field (L-001).
- `tests/integration/test_player_character_binding.gd` — the Player reads stats from the
  bound `CharacterState` (overriding the scene StatBlock), damage syncs back to the state,
  death marks the state DEAD, a wounded state restores current HP, and composition is kept.
- `tests/unit/presentation/test_ui_theme.gd` — `UITheme.build()` carries the Button state
  styleboxes + Label styling + a key-badge box; `UIPalette` tokens are sane.
- `tests/unit/presentation/test_gameplay_hud.gd` — the HUD builds its labels, renders the
  character's localized name, and composes the control hint from the InputService display
  label (shows "E"/"Esc", never a raw keycode).
- `tests/unit/core/test_input_display_label.gd` — `get_action_display_label` resolves
  interact→"E", open_menu→"Esc", and an unknown action → "?" (no keycode leak).
- `tests/unit/core/test_localization.gd` (extended) — the Phase-04 keys exist in both vi + en
  and the HUD-hint keys substitute the `{key}` placeholder.
- `tests/e2e/world_flow_case.gd` (extended) — asserts `WorldRuntime` built the player's
  `CharacterState` (stable id, ALIVE) and that it is the SAME instance across all 20 round
  trips (not recreated on a map swap — D-023 invariant).

**Phase 04 UI hardening added presentation + asset-contract tests (D-024):**
- `tests/unit/presentation/test_ui_theme.gd` — the asset-backed theme: distinct button
  styleboxes per state, panel/inset/badge styleboxes build, `PanelContainer` carries the
  framed panel style, the theme is a `StyleBoxTexture` (asset-backed) when textures are
  present, and the **asset contract**: every path in `UIPalette.UI_TEXTURES` exists on disk
  (a missing/renamed/un-tracked UI asset fails here, not as a blank UI).
- `tests/unit/presentation/test_gameplay_hud.gd` (updated) — the HUD renders the character's
  localized name and shows graphic key badges with display labels ([E]/[Esc] + Interact/Menu),
  never a raw keycode or raw action name, with ≥2 key-badge panels.
- `tests/unit/presentation/test_main_menu.gd` — the menu wears the shared theme, builds four
  action buttons, keeps Load Game + Settings disabled, emits `new_game_pressed`/`quit_pressed`
  via the real button signals (owning no gameplay), and shows localized text (not raw keys).
- `tests/unit/core/test_localization.gd` (extended) — the new UI keys (`UI_MENU_SETTINGS`,
  `UI_HUD_INTERACT_ACTION`, `UI_HUD_MENU_ACTION`) exist in both vi + en.

Gameplay/performance tests arrive with their phases. CI (D-012) runs the gates headless on
every push, and remains the authority. **Since L-031 the gates also run locally** (~3 minutes
for lint + import + parse + boot + suite + all four E2E processes), so a change should be
green before it is pushed rather than diagnosed through CI round-trips.

**Known environmental caveat (D-054):** the two wall-clock performance budgets
(`tests/performance/test_ai_budget.gd`, `test_combat_budget.gd`) assert µs/ms figures and are
machine-dependent — they pass on the CI runner and fail on at least one development machine,
with the measured numbers swinging 2–3× between runs of identical code. Treat a failure there
as "check whether this machine is the cause" before treating it as a regression, and compare
against an unmodified baseline run.

### Phase 11 — progression (D-054)
- `tests/unit/progression/test_progression_curve.gd` — threshold semantics (exact, one before,
  one after, overflow, multi-level, large), the derived level, the ceiling as a DATA fact, and
  boundary validation (empty id/array, non-positive step, decreasing curve — a plateau is
  legal, `min_level` < 1, all problems reported at once). Also pins the shipped curve and the
  game-feel contract that ONE authored kill reaches the first level-up.
- `tests/unit/progression/test_progression_service.gd` — the single mutation path: zero grant
  as a legal no-op, negative and at-ceiling REJECTED with their reasons pinned and the state
  byte-identical, monotonicity, determinism across repeated runs, and the proof that the level
  is derived (a retuned curve re-levels the same stored XP).
- `tests/unit/progression/test_progression_runtime.gd` — fail-closed start (nothing observable
  after a refusal), the idempotency ledger, one `level_changed` per grant across several
  thresholds, teardown disconnects, and a restart deriving from persisted XP.
- `tests/unit/presentation/test_progression_hud.gd` — XP distinguishable from HP on three
  channels (hue / weight / written text), the ceiling reading COMPLETE not `0 / 0`, both
  languages resolving with no raw keys, the reserved-vocabulary guard (no *tu vi* / *đột phá*
  / *cảnh giới*), and the celebration running, decaying, terminating exactly at rest,
  cancelling cleanly and costing nothing while idle.
- `tests/integration/test_combat_awards_progression.gd` — a REAL spawned creature dying and
  paying its authored reward; a re-cleared population rewarding AGAIN (the per-spawn reward id);
  a re-announced death paying once; and the forbidden "combat live, progression owning nothing".
- `tests/e2e/world_flow_case.gd::_prove_progression` — after a kill driven by REAL attack keys:
  the authority moved, the derived level agrees with it, and the HUD shows the row. No
  `grant_xp`/`set_total_xp` anywhere in the E2E.
- `tools/playtest_flow.gd` — records level + XP on EVERY step and captures
  `12_pre_combat` → `13_enemy_killed_level_up` → `14_xp_updated` → `16_post_level`, reporting
  the celebration's STATE at the capture boundary (see the D-055 note below).

**Phase 11 close-out hardening (D-055) — the guards the ownership model had only in comments:**
- `tests/unit/progression/test_progression_authority.gd` — **NEW.** Phase 11 asserted its
  ownership model in three docstrings and nowhere else, including one that claimed a property
  was "CHECKABLE rather than aspirational" while nothing checked it. Two structural walks of
  `res://src` now enforce it: only `character_state.gd` (the storage + `xp >= 0` invariant
  boundary) and `progression_service.gd` (the semantic authority) may MUTATE XP, and only
  `progression_runtime.gd` may CALL `grant_xp` — so the ledger, not every caller's memory, is
  what makes "paid once" true. `src` only, because tests legitimately arrange XP directly. The
  allow-lists are checked to name files that EXIST, so a rename cannot quietly disable the
  guard, and both matchers have non-vacuity tests that feed them the exact bypass lines a later
  phase would write plus the innocent lines that merely mention XP (`xp_reward`, `xp_gained`,
  `xp_into_level`, a comparison, a local). The call matcher's own first run FAILED on the
  service — it was matching the `func grant_xp(...)` DECLARATION — and that false positive is
  pinned as a test case rather than papered over by widening the allow-list.
- **Strengthened in the D-055 follow-up**, because the first version guarded the spelling a
  reviewer would think of rather than the property. Three changes, each with its own
  regression: the allow-lists are now **exact repository-relative paths** (a basename list
  exempts a file by NAME, so a future `src/gameplay/progression/progression_service.gd` would
  have inherited the exemption — `test_the_allow_list_is_keyed_on_the_path_not_the_filename`
  asserts the membership predicate directly); the XP matcher covers every form that actually
  mutates the property, not just `xp = …` (`call("set_total_xp", …)`, `set("xp", v)`,
  `set_indexed`, `set_deferred`, `obj["xp"] = v`, and the compound operators); and the
  `grant_xp` matcher covers **dynamic invocation** (`call` / `callv` / `call_deferred` /
  `Callable`), which the previous version missed entirely because it required the literal
  `grant_xp(` and `call("grant_xp", …)` does not contain it. The dynamic patterns match only a
  method-name POSITION, so the service's own `push_error("… grant_xp …")` is not read as a
  call. Proven against the real tree: planting `state.set("xp", 999)` in
  `progression_runtime.gd` and `svc.call("grant_xp", …)` in `combat_runtime.gd` passes the
  pre-follow-up guard (`678 passed, 0 failed`) and is caught by this one, reported by full
  path.
- `tests/unit/progression/test_progression_runtime.gd` (extended) — the reward-id IDENTITY
  matrix. The ledger is keyed by `String(reward_id)`, so an EMPTY id is not a cosmetic problem:
  it is a key every malformed defeat would share, and the first would be paid and then occupy
  `""`, turning duplicate-protection into a collision. Now `reward_id == ""` fails closed on
  all four halves — no XP, no `xp_gained`, no `level_changed`, **and no ledger entry** — and a
  well-formed defeat still pays afterwards, which is what proves the rejection left the ledger
  usable rather than merely left the counter at zero. Plus: a respawn pays again because its
  serial differs, and a NEGATIVE reward mutates nothing yet IS recorded as settled — the
  deliberate opposite of the empty-id case, because an identified defeat that was rejected is
  finished whereas an unidentified one was never a defeat.
- `tests/unit/presentation/test_gameplay_hud.gd` (extended) — **attack discoverability**
  (D-055-G). Phase 11 shipped with no attack prompt at all, so the verb that earns every point
  of XP was the only one a player could not find on screen while `T`/`Y`/`Esc` were advertised.
  No test could see it, because every test and the whole playtest harness already KNOW the
  action name and feed it directly. Asserted now: a named prompt exists, it IS a `UIPromptRow`
  (not a hand-rolled badge), it is visible with no setup, its glyph EQUALS what
  `InputService.get_action_display_label(&"attack")` resolves — compared against the service,
  never against the letter `J`, so a rebind moves the prompt instead of breaking the test — the
  raw action name and raw keycode never reach the screen, and the action word resolves in both
  vi and en. A **structural walk of `src/presentation`** rejects `set_prompt("<literal>"`, which
  pins the seam direction `semantic action → InputService → HUD`.
- **Made ROW-SPECIFIC in the D-055 follow-up.** The positive assertions searched
  `_all_label_text(hud)`, which is a weaker claim than it reads as: the HUD renders FIVE
  badge+word rows, so "the attack glyph is somewhere on screen" can be satisfied by a
  neighbouring row and stays green with the attack row's own badge blank. They now read the
  `AttackPrompt` subtree itself — the Label owned by its `UIKeyBadge` for the glyph, the row's
  own direct Label for the word — and a new `test_only_the_attack_row_carries_the_attack_prompt`
  asserts that exactly ONE of the five rows carries the attack word, that it is the row named
  `AttackPrompt`, and that all five action words are distinct so none can stand in for another.
  Proven non-vacuous by SWAPPING the attack and menu words in the HUD: the pre-follow-up attack
  tests all passed (only an unrelated menu assertion noticed), while these report
  `expected AttackPrompt but got MenuPrompt`. All five rows are now named for that reason — three
  were anonymous, so a strip failure could only quote Godot's generated node name.
  The key-badge count assertion moved from `>= 2 (interact + menu)`, written when the strip had
  two rows, to an exact FIVE.
- `tests/unit/presentation/test_gameplay_hud.gd` (extended) — **the bottom reserve is measured
  at last.** `TOP_PLAQUE_RESERVE` had a measuring test since D-050; `PROMPT_STRIP_RESERVE` never
  did, which is L-034's "a named reserve nobody measured" still live at the other end of the
  screen — and D-055 adds a FIFTH prompt to the strip it protects. The populated strip (all five
  prompts, interact forced visible, the longer language) is now measured on both axes: HEIGHT
  against the reserve the side panels and the level-up banner both inset by, and WIDTH against
  half the AUTHORED viewport width read from `ProjectSettings` — because the strip is anchored
  bottom-LEFT and grows RIGHT while the announcement is bottom-CENTRE, so those two bottom-edge
  elements would otherwise meet once enough prompts exist.
- `tools/playtest_flow.gd` (extended) — **MODE A / MODE B split.** Mode A (step 13) is the
  mechanical, reproducible proof and teleports the player into reach before each swing; it is
  now labelled so in the report, because a build where the player moves at 2px/s or where the
  HUD never says which key swings would pass it unchanged. **Mode B (steps 18–21) is the
  player-experience proof:** the player is placed ONCE at 96px, then never repositioned by
  code — the approach is real `move_*` keys, the swing is the real `attack` key, against the
  SECOND authored creature, while it hunts back. It records the discoverability evidence
  (`attack_prompt=visible`, `attack_action=attack`, `attack_display_key=<resolved>` — never the
  literal `J`), asserts the unassisted kill pays AGAIN (the ledger is per spawn, not per
  session), and ends by proving the player can still move. Capture wording was also corrected:
  `celebration_state_active_at_capture=…` and `hit_flash_state_active_at_capture=…`, both
  marked `[STATE EVIDENCE]`. The old phrasing ("caught in shot") claimed PIXEL evidence from a
  STATE observation — nothing in the tool inspects an image, and a human still has to open it.
- **Evidence naming corrected in the D-055 follow-up.** Mode B reported one number called
  `placed_once_at`, computed as `approach_from.distance_to(living.global_position)` AFTER the
  fight — the distance from the frozen placement POINT to wherever the creature had since walked
  to. That is neither the initial gap nor the final one, and naming it after the placement made a
  derived hybrid look like setup evidence. The step now groups its evidence by what produced it:
  `setup{placements=1 initial_gap_px=96} movement{final_gap_px=18} attack{hp 34 → 0 landed=true
  killed=true}`, with `initial_gap_px` measured immediately after the single permitted placement
  and `final_gap_px` at capture. `placements` is incremented AT the write and `placements == 1`
  is part of the PASS condition, so "placed once" is asserted rather than claimed in prose. The
  two gap values differing is itself the evidence that neither side was teleported — and
  `initial_gap_px` reads 87–88 rather than the constructed 96, because the creature is already
  hunting during the settle, which is why it is measured instead of assumed.
  *(The first version of this fix initialised `placements` to a literal `1`. The review pass
  caught it: a value that cannot change is not evidence — it would have reported `1` after
  someone added a second write and the pass condition could never have failed. Proven by
  planting a per-swing reposition, which now reports `placements=4` and FAILS the step.)*

**Phase 05 added Relationship + character-visual tests (high-risk: relationship state / save seam):**
- `tests/unit/relationship/test_relationship_config.gd` — `RelationshipConfigData` validity
  (authored config valid + the six documented dimension ranges; empty/out-of-range-default/
  min>max/duplicate-id/negative-capacity rejected; clamp + defaults map).
- `tests/unit/relationship/test_relationship_graph.gd` — the core graph (matrix B–U): typed
  endpoint equality + serialize round-trip, edge create + invalid/self/duplicate reject,
  dimension defaults, delta mutation + config clamp + zero-effect no-op + unknown-dimension and
  missing-edge rejection, directed-edge query, symmetric query from either side + duplicate
  symmetric reject + reverse-side update hitting one edge, **debt perspective** (symmetric
  reverse negates only `debt`; directed never flips; non-directional dims never flip), history
  append + capacity bound + no history on no-op, `relationship_changed` payload (one per real
  change, none on no-op), **deterministic** event→delta from the authored catalog + unknown-
  event reject, serialize round-trip + index rebuild after hydrate + byte-stable re-serialize,
  malformed-snapshot fail-closed (dup id / bad endpoint / unknown dim / out-of-range), and edge
  removal updating both indexes.
- `tests/unit/relationship/test_relationship_rules.gd` — rule + catalog validity, authored
  rules mapped, duplicate `event_kind` rejected, optional relationship_type gate.
- `tests/integration/test_relationship_runtime.gd` — the `RelationshipRuntime` subsystem loads
  config + rules, builds a usable store/service, drives an authored event end-to-end, and drops
  the graph on `end_session` (fresh instance; Nodes freed, L-019).
- `tests/e2e/world_flow_case.gd` (extended) — asserts a `RelationshipRuntime` exists under
  `Main/Systems`, is session-active after New Game, is NOT an autoload, is the SAME instance
  across all 20 hub↔field round trips, and ends its session on return to menu.
- `tests/unit/presentation/test_character_visual.gd` — the four archetype
  `CharacterVisualProfileData` load + validate at the **32×48** baseline with the D-046 GRID
  sheet (direction rows × animation columns, frame count derived from width, walk sheet
  REQUIRED); the authored frame counts (4 idle / 6 walk) are pinned as an art↔data drift guard;
  a ragged sheet width is rejected with the reason named; the ANIMATION clock advances, wraps,
  stays inside its direction row, resets on an idle↔walk switch, and leaves `_process` off for
  a single-frame sheet; `player.tscn`'s fallback sprite and collision footprint agree with the
  component's feet anchor; the
  `CharacterVisualComponent` builds a nearest-filtered, feet-anchored, 4-frame Sprite2D; facing
  selects the direction frame (diagonal→cardinal, zero keeps last facing); a missing/invalid
  profile fails clearly; the preview builds all four; and a `CharacterState` serializes NO
  presentation data (the layering invariant).

**Phase 06 added Sect tests (high-risk: membership authority / diplomacy / save seam):**
- `tests/unit/sect/test_sect_domain.gd` — the whole sect domain in one pure-RefCounted file:
  - **Data validation:** `SectTemplateData`/`SectRankData` well-formed vs. malformed (missing
	name_key, tier < 1, self in the enemy list, duplicate/empty rank ladder) and the rank
	ladder's `authority` **strictly increasing along the array** (10/20/30 valid; 10/20/20,
	20/10/30 and 30/20/10 rejected), with `lowest_rank()`/`highest_rank()` matching the first
	and last authored entries.
  - **`SectCatalog` referential integrity:** a declared ally/enemy that is not in the catalog
	(the `sect_ghost` case), a self-reference, a duplicate, and an ally/enemy overlap each
	invalidate the catalog — plus a drift guard that the SHIPPED `data/sects/sect_catalog.tres`
	is referentially sound, so authoring a dangling reference fails the suite, not the player's
	boot.
  - **State + serialization:** creation from a template, a byte-stable `to_dict`/`from_dict`
	round trip, and fail-closed hydration (leader/elder not on the roster, negative resource,
	out-of-range reputation, missing id).
  - **STRICT TYPES at the hydrate boundary:** a known-good payload is proven ACCEPTED first,
	then each case mutates exactly ONE field to a wrong type and asserts both halves of the
	contract — `from_dict` returns false AND the receiving state's snapshot is unchanged:
	resource quantity as `"100"` / `100.0`, resource id as an int, influence as `"5"` / `5.0`,
	reputation value as `"10"` / `10.0` / `true` and its scope as an int, a rank id or member id
	as an int, `leader_ref` as an int or `null`, an elder ref as an int, a territory/ally/enemy
	id as an int or bool, and `template_id`/`id` as an int or `null`. The int cases deliberately
	use payloads that would otherwise VALIDATE, so they fail only because of the type check.
  - **Store:** add, duplicate-id rejection, count.
  - **Membership (roster is authority, D-015):** join/duplicate-join, leave/non-member leave,
	rank change, unknown rank, the single-leader and leader∌elder invariants, a sect cannot
	join itself, disciples = roster − leader − elders, and the `CharacterState` derived cache
	being written on join/rank/leave and REBUILT from the roster by `sync_character_cache()`.
  - **Economy:** resource clamp at 0, reputation clamp to ±100, influence clamp at 0, territory
	uniqueness.
  - **Diplomacy mirror (§14):** ally/enemy mirrored to a symmetric Sect↔Sect edge, one
	order-independent edge id per pair, duplicate declaration rejected, and the rollback when
	the relationship side fails. **Non-destructive retype:** an ally→enemy flip keeps the SAME
	edge object (asserted by instance id) with its endpoints, flags, dimension values and
	history intact; a REJECTED flip leaves the old edge fully intact and the sect side
	unchanged; `set_relationship_type` rejects an unknown edge (without creating one) and an
	empty type.
  - **`apply_default_diplomacy()` fails closed:** a dangling declaration and a declaration with
	no relationship service to mirror into are errors (not silent skips), while a roster-only
	service that declares nothing needs no mirror and the resolvable case still mirrors.
- `tests/unit/sect/test_sect_runtime.gd` — the per-session owner: it is a Node and NOT an
  autoload; a session loads the authored catalog, enrols the player at the authored start rank
  with the derived cache matching the roster, and MIRRORS the authored enmity into the shared
  relationship graph. **Fail-closed:** starting without a relationship service (while the
  catalog declares diplomacy) or with no player to enrol is REJECTED, and afterwards no session
  state is observable at all (inactive, null service/store, empty sect id, non-member view) and
  the player's `CharacterState` carries no sect id. `end_session` clears the same surface.
  Nodes are freed (L-019).
- `tests/unit/presentation/test_gameplay_hud.gd` (extended) — the `SectPanel` renders
  **localized** resource names: no raw id (`spirit_stones`/`pills`/`manpower`) reaches a label,
  the localized names + quantities do, an unlocalized id falls back to the localized generic
  label instead of leaking the token, and the `id → SECT_RESOURCE_*` key convention holds.
- `tests/unit/core/test_localization.gd` (extended) — every Phase-06 sect key exists in BOTH
  vi and en, and a drift guard reads the SHIPPED catalog so every authored `starting_resources`
  id must have its `SECT_RESOURCE_*` display name in both languages.
- `tests/e2e/world_flow_case.gd` (extended) — in the real app: a `SectRuntime` exists under
  `Main/Systems`, is NOT an autoload, is session-active after New Game, enrolled the player in
  the authored start sect, and is the SAME instance (with membership intact) across all 20
  hub↔field round trips. The HUD shows the localized sect name and leaks no raw sect or
  resource id; a REAL `sect_panel` key event opens the detail panel. The authored enmity is
  mirrored into the graph the `RelationshipRuntime` owns (proving ONE shared graph), and the
  **forbidden state** is asserted unreachable: reaching `RUNNING` implies a live sect session,
  so "RUNNING + world live + `character.sect_id` set + sect session inactive" cannot occur.

**Phase 06 follow-up (D-038) — residual consistency + test integrity:**
- `tests/unit/sect/test_sect_domain.gd` (extended) — **`clear_diplomacy()` is transactional**:
  a clean clear removes the mirrored edge AND both declarations and emits exactly one
  `diplomacy_changed(..., NONE)` (a second clear is an idempotent no-op that emits nothing); a
  REJECTED edge removal leaves the edge, its type, and both sect declarations exactly as they
  were; a declared relation whose mirrored edge has vanished — or which has no relationship
  service at all — fails closed WITHOUT clearing the sect side; and an edge carrying a type the
  sect mirror does not own (`MASTER_DISCIPLE`) is never deleted, while a successful clear leaves
  bystander edges untouched. Plus **cross-sect diplomacy symmetry**: mutual ally and mutual
  enemy are valid, one-sided ally/enemy and an ally-vs-enemy conflict are rejected with the
  reason named, and the verdict is identical with the sect list reversed (order-independence).
- `tests/unit/sect/test_sect_runtime.gd` (extended) — the runtime refuses to start when the
  catalog names a player start sect but the character resolver is invalid, or is valid yet does
  not resolve the player id; afterwards no session is observable and the player's
  `sect_id`/`sect_rank` are untouched.
- `tests/unit/relationship/test_relationship_config.gd`,
  `test_relationship_rules.gd`, `test_relationship_graph.gd` — **fixtures repaired.** These
  assigned untyped arrays to typed `@export`s, which raises a VM error that ABORTED the test
  method; seven methods were reported PASS while executing nothing. Fixtures now build typed
  locals with concrete receiver types, assert that the fixture actually carries its data, and
  pin the reported validation REASON so a silently-empty fixture can no longer satisfy a
  negative assertion.

**Phase 08 (D-048) — World Simulation + the deterministic RNG seam:**
- `tests/unit/worldsim/test_rng_seam.gd` — the three properties the seam exists for.
  **Reproducible:** the same state yields the same SEQUENCE (not just the same first value), and
  the mixer is a pure function that avalanches on adjacent inputs. **Stream-isolated:** 1000
  draws on the world stream move another stream by **zero** values — the regression that matters,
  because without it a bug fix in combat would silently change every later world roll and nothing
  would error; also that two stream ids under one seed START apart, so they are unrelated
  sequences rather than one sequence read at two offsets, and that asking for a stream twice
  returns the SAME advancing object rather than restarting it. **Resumable:** a serialized stream
  continues where it stopped (restoring only the seed would replay the world's first N rolls),
  the whole seam round-trips byte-stably, and ten malformed payloads are REJECTED with the seam
  left byte-identical. Plus: every raw draw stays inside the 32-bit window (so `>>` never touches
  a negative value), both ends of an inclusive range are REACHABLE (an off-by-one in the
  multiply-shift would make the top value impossible and no range check would notice), and a
  degenerate 0%/100% chance STILL consumes a draw — otherwise editing a probability to zero
  would shift every later draw in that stream.
- `tests/unit/worldsim/test_world_clock.gd` — monotonic (advancing by 0 or backwards is
  REJECTED, not a silent no-op), explicit (no wall clock anywhere), and the derived date checked
  at every boundary: tick 0 is hour 0 / day 1 / year 1, the last tick before midnight is still
  day 1, the hour advances WITHIN a day, and season and year roll over. The snapshot carries the
  CALENDAR alongside the tick — asserted by restoring into a clock built with a different
  calendar — because otherwise retuning `ticks_per_hour` would silently change a save's in-world
  date.
- `tests/unit/worldsim/test_world_sim_data.gd` — schedule/actor/event/catalog validation, each
  negative case differing from a known-good fixture in exactly one field. The one that matters
  most: **the activity is a PURE FUNCTION of elapsed ticks**, including that a full cycle returns
  to the start (a routine frozen on one value would pass every single-sample assertion — L-029).
  Also: a zero-tick phase can never be observed; kind-specific event fields are REFUSED where
  they are meaningless (an authored field that does nothing is a trap); a `[0,0]` magnitude is
  invalid because an event that cannot be felt is cost without content; an actor using a schedule
  the catalog does not LIST is rejected because nothing could audit it; and four drift guards
  over the SHIPPED content — the catalog is valid, every actor's home map exists in the real map
  catalog, every actor's sect/rank/faction resolves in the real sect and faction catalogs (with
  the faction's parent sect matching), and the calendar is coherent with the routines and the
  catch-up budget.
- `tests/unit/worldsim/test_world_sim_service.gd` — the engine, against REAL sect, faction and
  relationship services (a stubbed owner would let these pass while the real composition was
  broken). **Determinism:** two runs from one seed produce an identical *fingerprint* — the
  simulation snapshot PLUS sect influence, faction influence, the relationship dimension and its
  history length, and every character's `sim_state` — and a different seed produces a different
  one, and the world demonstrably MOVED (a simulation that did nothing would also be
  "identical"). **Resume:** `save → load → advance 9` equals `advance 7 then 9` unbroken.
  **Catch-up:** a request beyond the budget is deferred, the debt drains first on the next call,
  the clock ends exactly as old as the time it was given, and `5+1+12` ticks produce the
  identical world to `18` at once. **LOD:** all three bands come from the map graph; the per-tick
  working set is NEAR+MID only; FAR → MID → NEAR → MID → FAR keeps the SAME record with identical
  routine, location and `joined_tick` and no actor duplicated; and a FAR actor is never behind an
  observed one on the same routine, with promotion landing on the value it already should have
  had. **Mutation through owners:** influence stops at the OWNER's ceiling, and the relationship
  service wrote bounded history the simulation does not implement — which is what proves the
  authoritative path was used. **Fail-closed:** an event naming a non-existent sect, an
  unconfigured dimension, a stranger as an endpoint, or a missing owner service all REFUSE to
  build the world; thirteen malformed snapshots leave the simulation byte-identical, including a
  pending event due in the PAST (firing it late or dropping it would both change the world).
- `tests/unit/worldsim/test_world_sim_runtime.gd` — the per-session owner against the SHIPPED
  content. It is a plain Node and NOT an autoload; **a source-reading guard** asserts the file
  contains no `_process`/`_physics_process`/`Timer`/`Time.get_*`/`randi`/`randf` (a behavioural
  test cannot distinguish "has no `_process`" from "has one that did not matter here", and a
  real-time driver would make the world non-reproducible); the shipped world STARTS with its
  cast in the shared registry and on the authoritative sect roster, creating **zero child
  nodes**; a second start is an idempotent no-op; five missing-dependency cases and an invalid
  seed each leave NO observable session (L-025); arriving in a map advances the world by exactly
  the authored cost and moves the bands with the player; and `end_session` clears everything, is
  repeatable, and leaves the NODE alive.
- `tests/unit/character/test_character_registry.gd` — a duplicate is REFUSED rather than
  replacing a live `CharacterState` (and the ORIGINAL object is still the one answered with);
  iteration is sorted, not insertion-ordered; the resolver answers for the WHOLE population —
  including a character added AFTER it was handed out, which the world simulation relies on —
  and hydrate is atomic with the population byte-identical after every rejection.
- `tests/performance/test_world_sim_budget.gd` — the budget that **found a real defect before
  the code shipped** (PERF-001): with the observed set held constant at 10, a 10× larger FAR
  population cost 3.57× more per tick, because the per-tick loop was sorting the whole cast. It
  keeps a relative scaling assertion (≤ 3× for a 10× cast — an `O(cast)` loop shows ~10×) so it
  fails on any hardware, plus a deliberately generous absolute ceiling, and asserts that 200
  actors × 300 ticks creates **zero nodes**.
- `tests/e2e/world_flow_case.gd` (extended) — in the real application: a
  `WorldSimulationRuntime` exists under `Main/Systems`, is NOT an autoload, is session-active,
  spawned **zero** nodes, and is the SAME instance across all 20 hub↔field round trips; the
  simulated cast is in the SHARED `CharacterRegistry` alongside the player; **the world clock
  advanced across those 20 transitions and the event feed is non-empty** (simulated time passes
  on real gameplay beats, not on a timer); the band census is the one the shipped two-map world
  should have; the HUD shows a world date and leaks no raw `WORLDSIM_*` key, no `actor_*` id and
  no unsubstituted `{placeholder}`; and the session is ended FIRST of all five on return to
  menu, with its state dropped. All five of these were verified to FAIL when the arrival beat
  was disconnected.

**Phase 07 (D-042) + the D-035 settings screen + the D-047 lifecycle contract** — these
sections were missing from this list for three phases while the tests themselves were green,
which is the kind of drift L-014 calls a bug; the coverage below is real and was simply
unrecorded here:
- `tests/unit/faction/test_faction_domain.gd` — data validation, `FactionState`
  (de)serialization and invariants, `FactionStore`'s per-sect index, and the `FactionService`
  mutation path: the sect-roster membership authority, the Faction↔Faction relationship mirror
  with transactional rollback, and the deterministic politics rules. The sect side is a REAL
  `SectStore` driven through a REAL `SectService`, not a stub — the whole point of the
  membership rule is that the faction service defers to the actual roster, and a stub roster
  would let the test pass while the real composition was broken.
- `tests/unit/faction/test_faction_runtime.gd` — the fail-closed session start, the absence of
  any observable half-session after a rejected start (L-025), the C-003 guard that nobody is
  enrolled, and the read-only politics view handed to presentation. It drives the REAL node
  with the REAL shipped catalog, because the thing most worth proving is that the authored
  content actually starts a session.
- `tests/unit/presentation/test_faction_panel.gd` — a `SectPoliticsView` rendered through
  Localization, never leaking a raw content id or an enum number to the screen; "no session"
  distinguished from "this sect has no factions"; truncation REPORTED rather than silently
  dropping a faction; and the shared visual language worn. The view is built by hand, which is
  the point of a read-only DTO: presentation can be tested against landscapes the shipped
  content does not contain (a player faction, an ALLIED relation, an overflow).
- `tests/unit/core/test_settings_store.gd` — a preference round-trips, a write does NOT lose
  unrelated keys, and a missing or corrupt file never blocks boot. Every test binds a SCRATCH
  path under `user://` and deletes it, because disk is shared state and the L-010 isolation
  rule applies to it too.
- `tests/unit/presentation/test_settings_menu.gd` — one button per SUPPORTED language read
  from the service rather than a second hard-coded list, LOCALIZED language names instead of
  raw codes, a press that actually changes the active language, the active choice marked, and
  `close_requested` emitted instead of the screen navigating itself.
- `tests/unit/bootstrap/test_session_lifecycle.gd` — the frozen session order
  (`World → Relationship → Sect → Faction`, teardown exactly reversed) asserted as a VALUE:
  the order constant, the reversal, and the structural guard that exactly ONE function issues
  the teardown and consumes the constant. It exists because `_on_return_to_menu()` had drifted
  into ending World and Relationship FIRST, under a comment claiming the opposite, with every
  gate green (L-030).

**Phase 09 (D-007) — real-time action combat:**
- `tests/unit/combat/test_attack_lifecycle.gd` — the `READY → WINDUP → ACTIVE → RECOVERY`
  state machine driven with EXACT deltas: each phase lasts its authored duration, the hit
  window opens only in ACTIVE and only once per swing, a long frame consumes states in order
  rather than skipping them, and a cancel returns to READY without resolving.
- `tests/unit/combat/test_combat_resolution.gd` — hit selection against the ANALYTIC HURTBOX
  MODEL (reach plus the target's radius, inside the arc, facing respected), the damage formula
  including power and crit multipliers, and determinism: the same seeded `STREAM_COMBAT`
  reproduces the same crit sequence while another stream stays unmoved.
- `tests/unit/combat/test_combat_runtime.gd` — the per-session subsystem: registration and
  unregistration are symmetric, a corpse stops being a target, and ending the session clears
  the registry rather than leaving stale hurtboxes for the next map.
- `tests/performance/test_combat_budget.gd` — the per-swing cost against a populated registry,
  as a relative assertion so it fails on any hardware (L-032).

**Phase 10 (D-052) — deterministic data-driven enemy AI:**
- `tests/unit/ai/test_ai_brain.gd` — the pure-domain brain as plain numbers: each of the seven
  states is entered for the documented reason and left for the documented reason, the leash
  OUTRANKS a visible target, re-acquisition only happens back inside it (so a player cannot
  walk a creature across the map or pin it in a turn-around at the boundary), and the same
  perception at the same tick yields the same intent.
- `tests/integration/test_enemy_encounter.gd` — a REAL `CombatRuntime` session with a REAL
  seeded `RngService`, REAL enemies from the REAL shipped spawn table, stepped with exact
  deltas: the shipped creature and table are valid and the creature can reach what it stops
  at; instance ids are derived and stable; a length-mismatched table is REJECTED rather than
  truncated (the `PackedVector2Array` authoring bug that only this check caught — L-026);
  spawn arms and registers every row; despawn leaves the registry clean and stops the tick; the
  creature notices and CLOSES, and from inside reach it BITES through `DamageRules` with the
  formula's own number; death stops all four things at once (moving, thinking, being a target,
  landing a hit from beyond the grave); decisions are throttled while movement is not; a long
  frame causes no double swing and no stuck ATTACK; and one seed reproduces one encounter.
- `tests/performance/test_ai_budget.gd` — the budget that **found two real clock defects before
  the code shipped** (PERF-003): zeroing the decision accumulator discarded the overshoot, so
  the cadence slipped to every 13th frame, and the brain was advanced by the NOMINAL interval
  so its clock ran slower than the world under long frames. It keeps a relative scaling
  assertion (a 10× larger cast must not cost ~3× more per tick) plus a generous absolute
  ceiling, and asserts the decision count over a known span.

**Phase-10 review pass (D-053) — the receiving half of combat feedback:**
- `tests/unit/presentation/test_damage_feedback.gd` — a landed hit VISIBLY changes the entity
  and decays back to exactly its resting colour (so repeated hits cannot accumulate a residual
  tint); a crit is distinguishable from a normal hit; the tints BRIGHTEN rather than only
  darken, because `modulate` is a multiply and a darkening-only tint disappears on a dark
  creature; a hit that applied NOTHING does not flash; death wears the palette corpse look and
  the killing blow does not flash over it; a flash in flight is ABANDONED on death rather than
  restoring a living colour; only a REVIVAL clears the corpse look; the corpse tint is both
  RE-MEASURED from the actual PNGs — the corpse composite is computed per floor FILL TILE and
  per sprite and must clear both the floor and the living sprite in luminance, which caught a
  tint that passed against the floor's mean; `_process` is off whenever no flash is
  running; and a **structural walk of `src/gameplay`** fails if any file there authors a colour
  (comments stripped, so the entity can still document the literal it used to carry).
- `tests/unit/presentation/test_gameplay_hud.gd` (extended) — the target plaque RETIRES after a
  kill instead of advertising a corpse forever: a live target starts no countdown, a dead one
  stays visible on a one-shot timer set to the authored linger, the timer's own `timeout` hides
  it, and a new live target CANCELS the countdown rather than letting it hide a live creature.
- `tests/integration/test_enemy_encounter.gd` (extended) — the same flash and corpse contract
  on the REAL `enemy.tscn` spawned from the REAL table, driven through the REAL
  `HurtboxComponent.apply_hit()`. A unit test against a hand-built stub would pass with the
  node missing from the shipped scene entirely, which is the gap L-029 is about.

**D-056 — the presentation ACTION layer (foundation hardening before Phase 12):**
- `tests/unit/presentation/test_character_action_layer.gd` — **NEW.** The second semantic layer
  on `CharacterVisualComponent`. Driven through the PUBLIC API only (`play_action` /
  `drive_action` / `end_action` / `is_action_playing`), so the tests describe the contract
  rather than the cursor. Asserted: every shipped profile AUTHORS the action sheet (an optional
  field nothing authors is a no-op with documentation — L-029, and `walk_sheet` already shipped
  null in four profiles for a whole phase); a ragged action sheet is refused with the field
  NAMED; **ACTION out-ranks LOCOMOTION** (the action sheet shows while the character is still
  walking, and locomotion resumes exactly where it was); turning mid-action neither restarts nor
  cancels it, but does move the direction row; an action the profile cannot play is REFUSED and
  locomotion continues (presentation degrades, gameplay does not); the reserved-but-unimplemented
  vocabulary (`cast`/`hit`/`stun`/`death`/`emote`) is refused rather than silently rendering
  something else; the frame is a **pure function of driven progress, CLAMPED not wrapped**, so
  over- and under-driving stay on the end frames and revisiting a progress value returns the same
  frame; driving 0 → 1 **visits every frame** for BOTH actors (a one-shot that renders frame 0
  forever passes any single-sample check); `advance()` moves a driven action by **nothing**, 30
  ticks included, because gameplay timing owns it; a full action cycle leaves the character's
  authoritative `CharacterState` **byte-identical**; 25 action cycles create **zero** extra
  nodes; and a static character pays no `_process` unless an action is running, which must keep
  it alive or the action could never end.
- **The §31 reuse proof, as a test rather than a claim:** the player (32×48 frames, 6-column
  action sheet) and the mist wolf (32×32 frames, 4-column sheet) run the same contract through
  the same methods, and the test asserts the two actors genuinely differ in frame SIZE and frame
  COUNT — otherwise it would be proving one case twice. A **structural walk of `src`** asserts
  exactly ONE file declares the action API, which is what forbids `player_cast.gd` /
  `enemy_cast.gd` / `boss_cast.gd`.
- `tests/integration/test_enemy_encounter.gd` (extended) — **the real-path proof.** A real swing,
  requested by the real brain through the real `AttackComponent`, puts the creature's own sprite
  into its action layer and traverses its frames — with only the GAMEPLAY clocks advanced. This
  is the test a component fixture cannot replace: `CharacterVisualComponent` is built at runtime
  by `Enemy._apply_visual()` and has to find its sibling itself, so a unit test passes with that
  wiring entirely absent (L-029). Verified by unbinding the source: the integration test fails
  and every unit test still passes. Plus: **a swing CANCELLED by death releases the pose**, which
  pins the reason the layer ends on the lifecycle's STATE —
  `AttackComponent.cancel()` emits no `attack_finished` and `Enemy._on_health_died()` calls it,
  so a signal-only layer would freeze a corpse mid-thrust.
- `tests/unit/presentation/test_gameplay_hud.gd` (extended) — **a meter must be tall enough for
  the value it writes inside itself**, re-measured from the real label for EVERY meter in the
  HUD. Found by opening a capture at 4×: the XP meter was 8px and its `FONT_SIZE_HINT` label
  measures **20px**, so the number drew across the rail's own border — and the health gauge was
  6px short too, unnoticed for two phases. The guard reports the deficit in pixels and names the
  meter, so the next one (mana, cultivation, a boss bar) cannot repeat it.
- `tests/unit/presentation/test_progression_hud.gd` (updated) — the XP/HP distinguishability test
  now asserts the two carriers that survive measurement (**hue** and **written text**) and that
  each meter CONTAINS its own label, instead of asserting the thinness that was the carrier
  unable to hold its own text.

**D-057 — the motion design contract and the HUD composition correction (foundation, no
gameplay; every guard below was planted against and failed before it was trusted):**
- `tests/unit/framework/test_reference_library_isolation.gd` — **NEW.** Reference material never
  enters the resource pipeline: `res://docs/.gdignore` exists (it IS the property — the only thing
  Godot reads to exclude a directory), and no file under `docs/` carries an import sidecar. On a
  clone without the local libraries the walk sees only Markdown, so the walk is asserted to have
  visited the tree and the detection rule is proven on a planted list. Mutations: removing the
  marker, and planting a sidecar, each fail exactly one test.
- `tests/unit/presentation/test_motion_contract.gd` — **NEW.** Presentation never writes the
  simulation clock (`Engine.time_scale`, the physics tick — assignment, compound assignment or
  setter): hit-stop holds an image. A structural walk of `src/presentation` with the pattern
  compiled ONCE, plus a matcher fixture proving it catches the shipped-everywhere recipe and
  ignores reads, comparisons and comments. Mutation: `Engine.time_scale = 0.05` in
  `DamageFeedback._process` fails it with `file:line`.
- `tests/unit/presentation/test_gameplay_hud.gd` (extended) — the D-057 HUD composition:
  * **the desktop HUD is never inset by the OS work area** — the measured dev-machine case (a
    66px dock and 32px top bar around a window wholly inside the work area) and a full-screen
    window over a Windows taskbar both produce zero, and the live runner HUD root has no inset;
    **a mobile notch insets only the window edge it covers**, in canvas units, and a split-screen
    window below the notch is not inset at all. Mutation: applying the work area on desktop fails it;
  * **the weight ladder** — the prompts sit on the flat translucent hint band while identity, map
    and target keep the framed plaque; and **the band is a legal text surface over pure white**,
    derived from the tokens. Mutations: the framed plaque back (3 tests fail: the ladder, the area
    budget at both ratios, the reserve), alpha 0.4 (the legibility test fails);
  * **negative space, by number** — a POPULATED HUD in vi, rects computed from anchors, offsets,
    minimum size and grow direction at 1280×720 and 1280×800 (not from the runner's window),
    elements found by WALKING the root: the permanent HUD stays within
    `HUD_PERMANENT_AREA_BUDGET` (measured 14.3% / 12.9%), and no element — the target plaque and
    the level-up banner included — enters `PLAYFIELD_CLEAR_ZONE`. Mutation: the banner back at
    the screen centre fails it (and D-054's own banner test);
  * **a defeated target says so** instead of keeping an empty row; an unrated live target has no
    row. Mutation: blanking the row again fails it;
  * **the bottom reserve is bounded from above** — at most the strip plus one margin. Mutation:
    78 again fails it;
  * **a settled HUD does no per-frame work**, for the whole populated tree, with the walk itself
    asserted. Mutation: an always-on `_process` on the HUD root fails it, naming the node.

**D-057B — the visual content foundation (a gait, anchors, a causal strike, a body that reacts, a
world that moves). Every guard below was planted against: 19 mutants of the new mechanisms, all
killed, each by the test named for it (scratch subset runner, recorded in DECISIONS D-057B):**
- `tests/unit/presentation/test_character_locomotion.gd` — **NEW (17).** The shipped profiles
  author `stride_px`, rest columns and VALID anchors; the validator refuses a rest column off the
  sheet, a negative stride, anchors from another cell size or covering the wrong frame count, a
  malformed key, a ragged track. The stride follows DISTANCE (three steps of ground = three
  columns; time alone moves nothing; half the speed is half the cadence); intent that moves
  nothing STALLS and settles, and the stride resumes when the body moves; a teleport is not a
  step; a stop on a contact frame SETTLES to the next rest column, on a rest column it is
  immediate, and walking again mid-settle continues the stride; the quadruped stops at once; a
  reversal shows the intermediate facing (LEFT↔RIGHT through the front, DOWN↔UP through the last
  side) and a quarter turn or a turn mid-action is instant; facing has hysteresis across 45°;
  idle breaths of creatures placed apart differ and the same placement repeats; the `palm` anchor
  is on the facing side, further out at the strike than the coil, exactly mirrored LEFT/RIGHT,
  follows a reaction's sprite offset, and an unnamed point returns the caller's fallback.
- `tests/unit/presentation/test_hit_reaction.gd` — **NEW (8).** A creature recoils `recoil_px`
  along the blow in whole pixels and returns EXACTLY to rest while the entity never moves; the
  direction is the blow's; a critical shoves further; a hit that applied 0 does nothing. A rooted
  post starts upright, leans AWAY from the blow, rocks past upright (a damped oscillation) and
  rests at exactly zero; struck from the other side it leans the other way. The impact sits on
  the striker's side of the core, its debris flies along the blow, lives in world space (moving
  the body does not drag it), is top-level (not tinted by the body's flash) and ends; straw chaff
  falls and mist does not; consecutive impacts vary and the n-th impact is identical on every body.
- `tests/unit/presentation/test_attack_feedback.gd` — **NEW (7).** The release starts at the
  DRAWN palm anchor, runs along the facing and angles down toward body height; it dissipates by
  the end of recovery and the node stops processing; facing away draws behind the body, any other
  facing in front; only a HOSTILE wind-up telegraphs and the telegraph ends with the wind-up; a
  swing in flight scales movement by `committed_move_scale` (0.3 for the palm strike, 0.0 for the
  bite) and the data boundary refuses a value outside [0, 1]; `flash_strength` scales the hit tint
  without changing its hue.
- `tests/gameplay/test_map_scenes.gd` (extended, 4) — the world is depth-sorted (root, Visual,
  Decor, CombatTargets, PlayerHost) and the floor sits under the ground-decal layer; every prop is
  base-anchored and stands on dry ground (no prop in a flooded paddy — the old trees, planters and
  lanterns all stood in water); wind-moved props wear `pixel_sway`, all grass shares ONE material,
  hanging props hang from the top; the field's mist lies at z -1 and drifts by `mist_drift`.
- `tests/unit/presentation/test_gameplay_hud.gd` (extended, 1) — engaging a live target closes the
  side panels once; a panel re-opened mid-fight survives health updates and the kill; a new
  engagement closes it again.
- Updated for the redrawn art: the player sheets are 6/8/8 frames, the wolf's attack 6; the walk
  opens on its entry column; the idle↔walk switch is driven by moving the node.
- `tools/capture_motion.gd` — **NEW tool**, not a test: boots the real app, drives semantic input,
  writes frame STRIPS (walk, stop, turn, strike the post, banner and tree wind, the wolf's bite,
  striking the wolf). The strips found the beard, the grave cross, the limp palm, the gliding hem,
  the strike passing over the wolf and the red-silhouetted post — none of which a test saw.

**Phase 12 (D-058):** `tests/unit/knowledge/test_knowledge_core.gd` (catalog, deterministic and
idempotent grants, unknown ids refused, query by kind, persistence round trip and corrupt-payload
rejection, runtime announces once, STRUCTURAL: only the service records);
`tests/unit/cultivation/test_cultivation_service.gd` (canon ladder, the non-damage-dimension rule,
gathering caps and never banks, a breakthrough WITHHELD without knowledge and granted with it,
layer steps, the Tiên Thiên gate, capability by realm, `meets`, type-checked serialization,
STRUCTURAL: only the service decides a position); `tests/unit/cultivation/
test_cultivation_runtime.gd` (each refusal names its reason, the broken vein's realm gate and
observation knowledge, sit → settle → gather → full → break through AT the release → keep sitting,
a blow interrupts and an unreleased breakthrough changes nothing, perception follows the realm);
lifecycle tests updated to the 10-step order; HUD tests: four gauges, six prompts (the contextual
cultivate row), notices queue. E2E (`world_flow_case._prove_cultivation`): real keys refuse,
read the stele, sit, accumulate over real frames, break through into Hậu Thiên 1, rise.

**Phase 13 (D-059):** `tests/unit/inventory/test_inventory.gd` (catalog, stack maximum and bag
capacity, round trip and corrupt saves, a pickup collected once and remembered, every use through
its owner and a wasted use burning nothing); HUD: the satchel takes and returns input. E2E
(`_prove_inventory`): walk onto pickups, a real I opens the satchel, real move keys choose the
manual without walking, a real E reads it (Knowledge Core), I closes and input returns.

**Phase 14 (D-060):** `tests/unit/equipment/test_equipment.gd` (shipped equipment valid and
canon, a non-canon family refused; the bonus changes damage deterministically through
`DamageRules` and never touches base stats; a weapon swaps the attack but never mid-swing;
equipping moves items and tells the body once, bonuses sum, unequipping restores the palm; slots
persist and a robe in the weapon slot is refused; the realm gate reads cultivation). E2E
(`_prove_equipment`): pick up both, wear them through the satchel with real keys, attack power and
the armed attack change, the robe is drawn, the jian comes off again.

**Phase 15 (D-061):** `tests/unit/skills/test_skills.gd` (catalog valid and canon — Kim is not an
Aetheria element — two deliveries; the cast is one action with four phases, releases once and is
breakable only before; a technique WITHHELD without knowledge and without the realm, LEARNED the
moment both hold; cost spent at the release, the cone strikes in front and not behind with the
swing's own arc test, Phong knocks back, busy then cooldown refusals; running dry is refused and
survivable; the bolt strikes the first target on its path and stops, Lôi stuns; a blow before the
release breaks the cast and spends nothing; STRUCTURAL: only TechniqueService learns). HUD: five
gauges, the dock counted in the area budget. E2E (`_prove_technique_phong`,
`_prove_technique_loi`): a real 1 key casts at the training post (rooted, struck, cooldown); the
woods' manual teaches Lôi and a real 2 key bolts and stuns a living wolf.

**D-063 A1 (immediate player feedback):** `tests/unit/presentation/test_hud_notice_band.gd` (15:
an answer and a result are on screen right after the call with a passive notice up, vi and en;
ten passive notices all shown in order — the old queue showed five; the backlog guard reports a
runaway producer and drops nothing; the results of one action keep their order; a repeated answer
refreshes and is never duplicated; a newer answer supersedes a stale one; an interrupted result
resumes for what it had left, never under the readable minimum; the breakthrough banner yields to
an answer paused and resumes, waits for an answer on screen, outranks and preserves passive
notices, and survives a run of answers; a language change re-renders the shown and the waiting;
a new action's answer is shown despite a stale waiting duplicate, vi and en; same-frame duplicate
answers are deduplicated).
E2E `_prove_cultivation`: after REAL pickups, a REAL C at the spring and a REAL E at the stele,
the HUD is read from inside the semantic event (`cultivation_refused`, `knowledge_gained`) — exact
text, kind, and the whole waiting backlog kept in order. Real app (`tools/playtest_flow.gd`):
05a environment validity (an invalid pacing FAILS, never passes) plus 05a pickup state —
the setup pickups (`pickup_hubpill1`, `pickup_hubmanualphong`, `pickup_hubrobe`) are proven
collected via the live `InventoryRuntime.is_collected()`, never inferred from visibility;
this state proof runs even when the timing environment is invalid, so a bad clock cannot
silently skip the collection evidence. 05b/05c: the real C/E gameplay interactions always
run; the 2-frame/100 ms timing threshold is NOT MEASURED when pacing is invalid, but the
answer/result visibility and notice-preservation checks still run. 05d validates the exact
notice sequence via `NoticeSequenceValidator`: lesson 1, lesson 2, then the three pickup
notices (pill, manual, robe — in emission order), each verified by authored identity
(`ITEM_BO_HUYET_DAN_NAME`, `ITEM_MANUAL_PHONG_NAME`, `ITEM_DAO_BAO_THANH_VAN_NAME`), each
exactly once; a missing, duplicate, unexpected or out-of-order notice fails. Never derived
from a dynamic `waiting.size()`. Suite at the original A1 checkpoint: 815 tests (historical
baseline). After A1 carried item #1: 841 tests, 841 passed, 0 failed — verified by CI run
#127 (https://github.com/MinhNQ03/Game_2D_Tu_Tien/actions/runs/37898325053) on
`1d6b7bc`; latest branch HEAD `7314357` also 841 passed in CI run #130
(https://github.com/MinhNQ03/Game_2D_Tu_Tien/actions/runs/37899934278).
After A1 item #2 reopen fix: 853 tests, 853 passed, 0 failed — verified locally
(Godot 4.7.2 `ed1daf0bf`, 0 SCRIPT ERROR, 0 leaks) and by CI on the closeout HEAD.
After the resumed-notice identity regression fix (2026-10-10): the validator has 18 tests
(the recorder keeps the set of EVERY recorded id; A/41 → B/42 → A/41 resumed records A and B
only); suite 859 tests, 859 passed, 0 failed, 0 `SCRIPT ERROR:`, 0 leak lines — local.

**D-063 A2a (physical truth — the stele and the spring):** `tests/gameplay/test_prop_bodies.gd`
(4: the bodies exist from the pipeline's PropData; a walk with the player's own collision shape
meets each from 4 sides and 4 corners — stopped outside, inside the reach, held when pushed, free
to leave; no invisible wall, no ghost mass). `test_solid_props_never_block_the_play` also walks
`PropBody`. E2E `_prove_cultivation` walks INTO the stele with a real held key. Playtest 05e/05f.

**D-063 A2b (the decor drawn with mass):** `test_prop_bodies.gd` +2 — every drawn sprite in the
world holders stands on a PropBody of its own texture at its own origin, or is
INTANGIBLE_BY_DESIGN with a reason (and never has a body); a walk meets each kind of decor from 8
directions and is never trapped (vacuity-guarded: at least the 4 kinds). The mass check covers
every PropBody's data. Playtest 05g. Suite: 821 tests.

### Phase 16 — pet / linh thú (D-064)
- `tests/unit/pets/test_pet_domain.gd` (9) — the shipped catalog and first pet; every broken
  `PetData` field rejected one at a time from a valid fixture; a non-following profile and an
  unknown skill id rejected; catalog empty / null / duplicate; level and stats DERIVED from XP
  (thresholds, ceiling, authored block never mutated); acquire / activate refusals with nothing
  changed; XP once, capped at the ceiling; store round trip as plain data; ATOMIC hydration over
  14 malformed payloads (incl. a stored `level`, an integral float — L-024).
- `tests/unit/ai/test_ally_follow.gd` (4) — the three ally profile fields and the one brain
  transition; the wolf's profile unchanged.
- `tests/unit/combat/test_combat_teams.gd` (1) — a swing skips its own team and hits everyone
  else; `disarm` is idempotent.
- `tests/unit/gameplay/test_world_interactable.gd` (4) — reach as a distance, nearest wins,
  exact ties by identity not scene order, hidden never offered, a stele is an interactable.
- `tests/integration/test_pet_companion.gd` (14) — real `CombatRuntime` + real `Pet` scene:
  no-pet refusal; befriend once (the stray hides); summon / dismiss idempotent (one body, one
  ally, one attacker); gradual follow with a per-frame speed bound (no teleport) and a bounded
  amble; only a living hostile near the owner is targeted; a real kill pays combat's reward once
  and the pet's share once (duplicate id and pet-away cases); level-up applies derived stats;
  fall + recall cooldown; map change frees and re-summons; owner falls; session end leaves
  nothing; failed start; runtime `to_dict` / `from_dict` atomic; a SECOND pet from content only.
- `tests/performance/test_pet_budget.gd` (3) — no own frame callback; retarget cadence counted;
  linear in hostiles (figures in `PERFORMANCE.md`).
- `tests/unit/presentation/test_gameplay_hud.gd` (+1, 2 updated) — the pet prompt follows the
  view, yields to interact, and the strip is measured in BOTH widest states.
- `tests/unit/bootstrap/test_session_lifecycle.gd` — 13 subsystems, `PetRuntime` last.
- **E2E gate 11** `tests/e2e/run_pet_flow.gd` — isolated process, real app, semantic inputs:
  no-pet answer → walk into reach → befriend → follow → dismiss / recall → map change → real
  fight (player XP once, pet share once) → menu, `PetRuntime` torn down first.
- Mutation-checked: removing the reward dedupe, the map-leaving despawn, or the team filter each
  turns a test red.
- Real app: `tools/capture_motion.gd -- <dir> pet <vi|en>` at 1280×720 (vi) and 1920×1200 (en);
  captures opened (stray + prompt, follow strip, dismissed, fight strip with the wolf's hit
  flash). `tools/playtest_flow.gd` 30/30.
- Local tally at this checkpoint: 895 tests, 895 passed, 0 failed, 0 `SCRIPT ERROR:`, 0 leak
  lines; app / player / world / pet E2E PASS.
