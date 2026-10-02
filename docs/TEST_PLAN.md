# TEST_PLAN — Aetheria

> Testing strategy. Rules summary: `.kiro/steering/05-performance-testing.md`.
> Goal: **not** blind 100% coverage — strong coverage of high-risk logic, cheap smoke
> coverage of the whole flow, and every fixed bug pinned by a regression test.
>
> Status: strategy defined; runner + framework in place. Through Phase 02 the suite covers
> the core framework (lifecycle/scene-router/input/localization/event-bus) and the Player
> core (stats/health/movement/damage + player↔dummy integration), plus two dedicated
> real-application E2E processes (app-flow and player-flow). Gameplay beyond the Player
> sandbox is added phase by phase.

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
# 1. project-wide GDScript parse check (src/ + tests/ + tools/)
godot --headless --path . -s res://tools/parse_check.gd

# 2. runtime boot smoke — actually boots application/run/main_scene, runs Main._ready(),
#    then quits after 2 frames (verified flag per Godot 4.7 CLI docs)
godot --headless --path . --quit-after 2

# 3. headless test suite (custom runner)
godot --headless --path . -s res://tests/run_tests.gd
```

Expected (suite) on success: per-test `[PASS]` lines, a summary, `RESULT: PASS`, exit
code **0**. On any failure: `[FAIL]` lines, `RESULT: FAIL`, exit code **1**. The parse
check prints `[parse_check] RESULT: PASS/FAIL` and exits 0/1. The runtime boot prints
`[boot] Aetheria main scene ready...` and exits 0 if boot didn't crash.

> **Note (D-009):** the AI agent could not run any of these locally — no Godot binary was
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
  integration/     # components together (fresh instances; never the live autoloads)
  e2e/             # real-application flow — OWN process (D-019), excluded from run_tests.gd
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

Gameplay/performance tests arrive with their phases. CI (D-012) runs the gates headless on
every push. **Note:** these tests were authored and statically validated (GDScript
diagnostics clean); the agent cannot run Godot locally (D-009), so the authoritative run
is CI.
