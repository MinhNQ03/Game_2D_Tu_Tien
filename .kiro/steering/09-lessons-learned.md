# 09 — Lessons Learned (do-not-repeat)

> Steering: always included. A running list of mistakes that were caught in review and
> fixed, so they are NOT repeated. Before writing code, scan this list; when a new class
> of mistake is caught and fixed, add it here (short: symptom → rule). Keep it specific
> and actionable, not generic advice. Link the ADR / phase where it was fixed.

## How to use this file

- **Before coding:** skim the rules below; they are the concrete traps already hit in
  this project.
- **After a review fix:** if the mistake could recur, append a new `L-00N` entry.
- Keep each entry tiny: what went wrong, the one-line rule, where it was fixed.

---

## L-001 — Serializing runtime lifecycle into a save (invalid-state reload)
- **Symptom:** `GameState.to_dict()` persisted `session_active`, and `from_dict()` wrote
  it while the runtime `phase` stayed at default `BOOT` → a load could reconstruct the
  impossible `phase == BOOT && session_active == true`.
- **Rule:** **Never serialize runtime-only lifecycle/phase state.** Persist *identity +
  data* only (e.g. `run_id`, location). Derive flags like "active" from data presence.
  Load = **data-only hydrate**; the caller drives the state machine afterward through the
  normal transitions. Guard hydrate against unsafe phases and invalid snapshots (fail
  loud, return bool).
- **Fixed:** D-018 (Phase 01 hardening). See `GameState.to_dict`/`hydrate_session`.

## L-002 — Magic enum ints at call sites
- **Symptom:** presentation called `input.reset_to(0)` / `reset_to(1)` — raw enum ints
  (`Context.GAMEPLAY`/`MENU`) leaking as magic numbers into UI code.
- **Rule:** **No magic numbers at call sites.** Expose intent-revealing methods
  (`set_gameplay_context()`, `set_menu_context()`, `push_modal_context()`); keep the raw
  index mutation private. Call sites read as intent, not as integers.
- **Fixed:** D-018. See `InputService` semantic context API.

## L-003 — Bypassing the owning service for input/vocabulary
- **Symptom:** `prologue_shell` read input directly via
  `event.is_action_pressed("open_menu")`, bypassing `InputService` (the owner of input
  gating + semantic actions). A modal/gating rule could be silently ignored.
- **Rule:** **Go through the owning service, never read the raw vocabulary directly.**
  Resolve input intent via `InputService` (e.g. `is_system_action_just_pressed`), text via
  `Localization`, scene moves via `SceneRouter`. If a service owns a concept, don't reach
  around it.
- **Fixed:** D-018. See `prologue_shell._unhandled_input`.

## L-004 — Silently tolerating missing core services (null-safe → null-blind)
- **Symptom:** the bootstrap used null-safe `get_node_or_null` getters everywhere, so a
  real run with a mis-wired autoload would limp along silently instead of failing.
- **Rule:** **Fail loud on missing REQUIRED dependencies at a real boot;** only tolerate
  absence in the explicit test-harness context (e.g. zero autoloads present = headless
  unit tests). Also **check return values** of state-machine transitions instead of
  fire-and-forget.
- **Fixed:** D-018. See `Main._verify_core_autoloads` + `_boot` transition checks.

## L-005 — Speculative signals/APIs with no real producer+consumer
- **Symptom:** `EventBus` declared `new_game_requested` / `session_started` /
  `session_ended` that nothing emitted *and* nothing listened to — speculative surface.
- **Rule:** **Add a signal/API only when a real producer AND a real consumer exist now.**
  No speculative generality (see `03-architecture.md` anti-over-engineering). Remove
  dead signals; add them back in the phase that actually needs them.
- **Fixed:** D-018. EventBus trimmed to boot / scene-transition / language signals.

## L-006 — Test asserts "nothing broke" instead of exercising the real path
- **Symptom:** a boot/integration test that constructs fresh objects and drives them by
  hand can pass even when the *real* wiring (menu → bootstrap → router → lifecycle) is
  broken, because it never runs the real path.
- **Rule:** **At least one test must exercise the REAL path end-to-end:** real autoloads
  under `/root`, the real `main.tscn`, the real UI signal — then assert the observable end
  state and a clean (no-orphan) teardown. Keep direct-drive unit tests too, but don't let
  them be the only coverage.
- **Fixed:** D-018. See `tests/integration/test_app_flow.gd`.

## L-007 — "Build/parse passes" treated as "done"
- **Symptom:** relying on GDScript diagnostics / parse-only checks as proof of done.
- **Rule:** **Parse/compile passing is NOT done** (`08-ai-review-protocol.md`). The
  authoritative check is the headless suite in CI:
  `godot --headless --path . -s res://tests/run_tests.gd`. Godot is not invocable locally
  (D-009) → push and verify the CI check-run `Foundation gates (Godot 4.7)` is
  `success` before claiming done.
- **Fixed:** standing rule since Phase 0 (D-009 / D-012).

## L-008 — Committing a scene/script without its generated `.uid`
- **Symptom:** staged `tests/.../test_app_flow.gd` but not its `.uid` sibling that Godot
  generates. The `.uid` is not git-ignored and is part of the resource identity.
- **Rule:** **When adding a `.gd`/`.tscn`/`.tres`, stage its generated `.uid` too.** Stage
  files by explicit path (not `git add -A`), but don't forget the `.uid`. `.uid` files are
  tracked; only agent/CI scratch files are git-ignored.
- **Fixed:** noted during Phase 01 hardening follow-up.

## L-009 — Scratch files leaking into the repo / `.git`
- **Symptom:** temporary `.ps1`/`.txt`/`.log` helpers (and files written under `.git/`)
  left behind after git automation.
- **Rule:** **Clean up every scratch file you create.** Prefer scratch names covered by
  `.gitignore` patterns (`*_tmp.txt`, etc.); never `git add -A` (it sweeps them in). Delete
  helper scripts/logs when done; don't write working files under `.git/`.
- **Fixed:** cleaned in Phase 0 close-out and Phase 01 hardening.

## L-010 — Tests that mutate a shared autoload/singleton (cross-test contamination)
- **Symptom:** an in-process test booted the real app (`main.tscn`) and drove the shared
  `/root/GameState` autoload to `RUNNING`; a later test's boot then hit
  `illegal transition RUNNING -> INITIALIZING`. The suite only "passed" because the later
  test didn't assert the boot result. Also: spawning nodes named like the autoloads
  (`add_child` with `name="GameState"`) creates **duplicate autoloads** — Main still reads
  the REAL one, so the spawns are both useless and misleading.
- **Rule:** **The project `[autoload]` singletons are LIVE under `/root` in every Godot
  run — including the `-s` test runner.** So:
  - Unit/integration tests use **fresh `Script.new()` instances**, never the live
    singletons; never `add_child` a node named like an autoload (no duplicates).
  - Anything that must boot the **real** app (drives the shared singletons) runs in its
    **own Godot process** with a dedicated entrypoint, as a separate CI gate — not inside
    the shared runner.
  - The shared runner keeps an **isolation guard**: snapshot the shared GameState phase and
    FAIL the suite if any test leaves it changed (detect contamination, don't reset it).
  - Prefer process isolation over adding a production `reset_for_tests()` API or relying on
    test order.
- **Fixed:** D-019 (Phase 01 hardening). See `tests/e2e/run_app_flow.gd`,
  `tests/run_tests.gd` isolation guard, structural `tests/smoke/test_boot.gd`.

## L-011 — A test "passes" while the real boot path actually failed
- **Symptom:** CI was green even though the boot emitted
  `[boot] begin_initialization rejected` — because no test asserted the lifecycle result.
- **Rule:** **A test that exercises boot MUST assert the boot CONTRACT** (reached the
  expected phase, services wired), not just "didn't crash". A successful normal run must be
  free of unexpected `ERROR:`/`illegal transition` lines; such lines are acceptable ONLY in
  explicit negative-path tests (invalid transition / missing scene / missing key).
- **Fixed:** D-019. Real boot asserted in the dedicated E2E process; smoke no longer hides a
  boot failure.

## L-013 — Touching the viewport/tree AFTER emitting a signal that unloads the scene
- **Symptom:** `PlayerSandbox._unhandled_input` did `return_to_menu_requested.emit()` then
  `get_viewport().set_input_as_handled()`. Emitting ran the coordinator (Main) which swapped
  the scene out synchronously, so by the next line the node was out of the tree and
  `get_viewport()` was null → `Cannot call method 'set_input_as_handled' on a null value`.
- **Rule:** **A signal emit can synchronously tear down the emitter.** Do everything that
  needs the node to be in the tree (viewport, `get_node`, `get_tree`) BEFORE emitting, and
  null-check tree/viewport accessors in `_input`/`_unhandled_input`/callbacks that can fire
  during a transition. Order: read/handle locally first, emit the "please change scene"
  signal last.
- **Fixed:** Phase 02 follow-up. `player_sandbox.gd` + `prologue_shell.gd` capture + null-check
  the viewport and mark input handled before emitting the return-to-menu signal.

## L-014 — Spec/implementation/doc drift (contract words that don't match code)
- **Symptom (Phase 02 hardening found several):** `apply_intent` contract said `(intent,
  speed, delta)` but code was `(intent, speed)`; HealthComponent said "`died` once, ever"
  while `reset_dummy()` could die again; `CollisionLayers` constants existed but scenes
  hard-coded `1/2/4/5`; docs referenced old phase numbers (11–15, Phase 17) after a
  renumber; a test called `MovementComponent.apply_intent`/`resolve_player_attack()`
  directly and claimed to prove the "real player flow".
- **Rule:** **A contract/comment/doc that contradicts the code is a bug.** When you write
  an invariant or signature in a docstring/spec, the code must match it (or change the
  words). A named-constant "source of truth" must actually be consumed at runtime (add a
  test that fails on drift). An E2E that claims to test a boundary must drive THAT boundary
  (semantic input), not a shortcut. On any renumber/rename, grep the whole repo for the old
  value.
- **Also:** do not `assert()`-abort inside a boundary validator used for fail-closed
  behaviour — aborting the process prevents the owner from degrading gracefully and differs
  between debug/release. Use loud `push_error` + a checked return; the OWNER fails closed.
- **Fixed:** Phase 02 final hardening (contract alignment + source-of-truth tests + doc sync).

## L-015 — Explicit-path staging drops sibling/companion files (hit TWICE in Phase 02)
- **Symptom:** staging by explicit path (correctly avoiding `git add -A`, L-009) silently
  left out files that belong with the change, forcing follow-up "fix" commits:
  - Phase 02: committed `player.tscn`/`training_dummy.tscn` but forgot the `data/stats/*.tres`
    those scenes reference (they live under `data/`, not `src/data/`) → patch commit.
  - Phase 02 hardening: committed test `.gd` but forgot their generated `.uid` siblings →
    patch commit.
  Both would have broken scene loading / left untracked companions if not caught.
- **Rule:** **Before every commit, reconcile the staged set against `git status`.** Run
  `git status --short` and confirm EVERY intended change — and its companions — is staged:
  - a `.tscn`/`.tres` → its `.uid`, AND every resource it `ext_resource`-references
    (follow the paths; they may be in a different top-level dir like `data/`);
  - a new `.gd`/scene → its generated `.uid`;
  - a `.csv` that Godot imports → the regenerated `.import`/`.translation` outputs if tracked.
  If `git status` still lists a `??`/` M` file that logically belongs to this change, stage
  it NOW — do not ship a follow-up "oops" commit. Leftover unrelated noise (e.g. a Godot
  line-reorder in `project.godot`) may stay unstaged, but decide consciously, not by omission.
- **Fixed:** adopted as the pre-commit reconciliation step. Supersedes the narrow "remember
  the .uid" of L-008 with "reconcile the whole staged set vs. git status".

## L-016 — Headless `-s` E2E can't rely on Area2D `body_entered` or input-pump timing
- **Symptom:** the Phase-03 world E2E drove a map transition by teleporting/walking the
  player onto a `MapExitZone` and bumping `interact`, expecting the Area2D's `body_entered`
  to set `MapBase._active_exit`. In the headless `godot --headless -s run_world_flow.gd`
  process there is no game window and the physics-overlap pipeline does NOT raise
  `body_entered` the way a real game loop does, so `_active_exit` stayed `null` and `interact`
  was a silent no-op. CI failed 5 commits in a row with the SAME message
  (`interact actually changed the active map (was 'map_hub')`) because the fixes targeted the
  input side, not the real cause (the sensor signal never firing).
- **Rule:** **In a `-s` SceneTree E2E, do not depend on Area2D `body_entered`/physics overlap
  or on precise `is_action_just_pressed` frame timing.** To exercise a sensor-gated path,
  **emit the node's own real signal** (`zone.emit_signal("body_entered", player)`) — that
  drives the REAL handler (`_on_exit_body_entered` → `_active_exit`) deterministically, and
  everything downstream (gate, `exit_requested`, WorldRuntime, SceneRouter) still runs for
  real. For an edge-triggered input gate, press the action and **retry the handler dispatch a
  bounded number of frames** until the observable effect happens, instead of guessing the one
  frame the edge is live. Keep a self-diagnosing assertion that names the exact failed link.
- **Also (process):** Godot is not runnable locally (D-009), so a CI-only failure must be
  diagnosed by **reading the code for the root cause**, not by push-and-pray. If a gate fails
  opaquely, make it print the runner output (job summary + `::error::` annotations) ONCE so
  the real message is readable via the API, then fix the true cause — don't push repeated
  speculative fixes.
- **Fixed:** Phase 03 (D-021 follow-up). See `tests/e2e/world_flow_case.gd`
  (`_stand_in_exit` + bounded interact retry). CI green on `b7cc9b6`.
