# TEST_PLAN — Aetheria

> Testing strategy. Rules summary: `.kiro/steering/05-performance-testing.md`.
> Goal: **not** blind 100% coverage — strong coverage of high-risk logic, cheap smoke
> coverage of the whole flow, and every fixed bug pinned by a regression test.
>
> **CURRENT STATUS (through Phase 08 + its review pass — D-048/D-049):** strategy defined;
> runner + framework in place. The suite covers the core framework (lifecycle/scene-router/
> input/localization/event-bus/settings), the **session lifecycle contract** (the ordered
> teardown, D-047), the Player core (stats/health/movement/damage + player↔dummy integration),
> the World/Map system (MapData/MapCatalog validation, data-driven catalog, source-of-truth
> scene↔data checks, no-leak + transactional-rollback map transitions, data-driven camera
> bounds + follow, persistent player across 20 round trips), the Character core + the
> **character registry**, the Relationship core, the **Sect** core, the **Faction** core, the
> **World Simulation** core (clock, seeded RNG streams, LOD bands, determinism, resume,
> bounded catch-up, a performance budget), and the UI/theme asset contracts — plus three
> dedicated real-application E2E processes (app-flow, player-flow, world-flow).
>
> **CI runs 10 gates** (see §5) and the in-runner suite reports
> **`ran 477 test(s): 477 passed, 0 failed`** with zero `SCRIPT ERROR:` lines and **zero leaked
> ObjectDB / resources at exit** — the count is the runner's own tally, not a hand count.
> Gameplay beyond world/map traversal + the social substrate is added phase by phase; combat
> is Phase 09 and is **not started**.
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

Then the three dedicated E2E processes (app / player sandbox / world-map), one gate each —
10 gates in total.

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
every push. **Note:** these tests were authored and statically validated (GDScript
diagnostics clean); the agent cannot run Godot locally (D-009), so the authoritative run
is CI.

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
