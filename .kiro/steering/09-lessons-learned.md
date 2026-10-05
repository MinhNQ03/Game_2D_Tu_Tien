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
- **Rule (refined in the Phase-03 reopen, D-022):** In a `-s` SceneTree E2E, the two
  headless concessions are DIFFERENT and must be handled differently:
  - **Area2D physics overlap:** headless won't reliably raise `body_entered`, so emit the
    node's OWN real signal (`zone.emit_signal("body_entered", player)`). This runs the REAL
    handler (`_on_exit_body_entered` → `_active_exit`); it is a documented substitution of
    the engine-internal sensor only.
  - **Semantic input:** this is the boundary under test, so DO drive it for real —
    `Input.parse_input_event` with a real `InputEventKey` built from the action's binding —
    and let the engine update the InputMap action state + dispatch `_input`/`_unhandled_input`.
    **Do NOT call `node._unhandled_input(...)` directly** to simulate gameplay input (that
    bypasses the boundary the test claims to cover — see L-017). To absorb frame-timing
    variance, feed the key and poll the observable effect over a bounded number of frames.
  - Keep a self-diagnosing assertion that names the exact failed link.
- **Also (process):** Godot is not runnable locally (D-009), so a CI-only failure must be
  diagnosed per `.kiro/steering/10-ci-failure-protocol.md` — read the code for the root
  cause, make the gate print its output ONCE if unreadable, then fix the true cause. No
  guess-and-push.
- **Fixed:** Phase 03 reopen (D-022). See `tests/e2e/world_flow_case.gd` (`_fire_action`
  via `Input.parse_input_event`; sensor `body_entered` emit only).

## L-017 — An E2E can be green while bypassing the boundary it claims to test
- **Symptom:** the first Phase-03 world E2E called `MapBase._unhandled_input(...)` directly
  (and even considered calling `WorldRuntime.request_map_transition` / `SceneRouter`) to make
  the transition happen. The assertions passed, but the test proved nothing about the real
  input pipeline (InputMap → engine dispatch → `_unhandled_input` → InputService gate): a
  break anywhere in that chain would still show green.
- **Rule:** **An E2E MUST drive the boundary it advertises.** If it says "real semantic
  input", feed real input events through the engine (`Input.parse_input_event`), never call
  the gameplay handler directly. Engine-nondeterministic internals (headless Area2D overlap)
  may be substituted ONLY at the exact documented point (emit the sensor's own signal), never
  by shortcutting the whole boundary. If a test can't exercise the real boundary, say so and
  cover it elsewhere — don't fake a green.
- **Fixed:** Phase 03 reopen (D-022). `tests/e2e/world_flow_case.gd` drives interact/open_menu
  via `Input.parse_input_event` real key events + a real movement step; only the exit sensor's
  `body_entered` is emitted (L-016).


## L-018 — A `.gd` referencing a field/method that doesn't exist passes parse but crashes at runtime (the class_name LSP false-positive hid it)
- **Symptom (Phase 04, D-023):** `CharacterState.create_from_template()` read
  `template.default_goals`, but `CharacterTemplateData` never declared that field. GDScript
  **parse** (and the CI parse-check gate) PASSED — dynamic property access is only resolved at
  runtime — so steps 1–6 of CI were green. The headless suite (step 7) then hit
  `Invalid access to property or key 'default_goals' ...`, `create_from_template` returned
  `null`, and every dependent test errored (`Nonexistent function on base 'Nil'`). It shipped
  because the known `class_name` LSP cache false-positive ("Could not find type
  CharacterState") trained the eye to dismiss ALL diagnostics on the new cross-file classes —
  including this real one, which `get_diagnostics` did NOT actually report (it only shows a
  missing TYPE, not a missing property on a dynamically-typed `Resource`).
- **Rule:** **A field/method accessed on another class must be declared on that class — verify
  it, do not assume.** When class A reads `b.some_field`, open B and confirm `some_field`
  exists (grep it) BEFORE committing. `get_diagnostics` clean is necessary but NOT sufficient:
  it cannot catch a property that doesn't exist on a dynamically-typed base (`Resource`,
  `Node`, `Object`), nor anything behind `.call()`. For a new data↔domain seam, cross-check
  every field the factory copies against the data class's `@export`s. The parse-check gate is
  not a substitute for the headless suite (L-007). Also: when adding a `@export` field to a
  Resource that a factory consumes, add it to BOTH the class and the authored `.tres` if the
  value is non-default.
- **Also (data-vs-code drift, ties to L-014):** `docs/DATA_SCHEMA.md` listed `default_goals`
  for `CharacterTemplateData`; the code read it; the class omitted it. A documented field that
  the code consumes MUST be declared. On a schema touch, reconcile doc ↔ data class ↔ factory.
- **Fixed:** Phase 04. Declared `CharacterTemplateData.default_goals: Array`; added
  `MapCatalog.start_map_id` coverage to the catalog unit test; re-ran via CI.

## L-019 — A test that `.new()`s a Node but never frees it leaks at process exit (silent; CI stays green)
- **Symptom (Phase 04 close-out, D-025):** CI was `success` yet the headless suite process
  printed at shutdown `WARNING: 5 ObjectDB instances were leaked at exit` and
  `ERROR: 1 resources still in use at exit`. A `--verbose` CI diagnostic (steering 10 §1.3)
  named them: 3× `Node` (empty node path = never entered the tree), 1× `GDScript`
  (`res://src/infrastructure/input_service.gd`, refcount 3), 1× `GDScriptNativeClass`
  (refcount 1), and the "1 resource still in use" was that same GDScript. Root cause: the
  Phase-04 test `tests/unit/core/test_input_display_label.gd` created a fresh
  `InputService` via `InputServiceScript.new()` in **each of its 3 methods** and never freed
  it. `InputService` extends `Node` (manual memory), so an un-added, un-`free()`d local does
  NOT auto-release when the method returns — it leaks until the process dies. Each live Node
  held a ref to its script → the `input_service.gd` GDScript stayed alive (refcount 3) →
  which kept its native base class alive (refcount 1). 3 Nodes + 1 GDScript + 1
  GDScriptNativeClass = the 5 ObjectDB; the GDScript = the 1 resource. The sibling test
  `test_input_service.gd` freed its instances correctly; the newer display-label test simply
  forgot — and nothing caught it because the leak is a non-fatal shutdown WARNING (exit stays
  0) and `get_diagnostics`/parse-check cannot see a runtime ownership mistake.
- **Rule:** **In the headless `-s` runner, a `Node`/`Object` created in a test MUST be freed
  by that test** — either `add_to_tree(n)` + `free_node(n)` (TestCase helpers), or `n.free()`
  if it was never added. Only `RefCounted` (Resource, custom `RefCounted`) auto-releases;
  `Node`/`Object` do not. A leaked Node also pins its GDScript + native class, so one unfreed
  node shows up as several leaked ObjectDB + a "resource still in use". A clean suite must end
  with **0 ObjectDB leaked / 0 resources in use** — treat those shutdown lines as a failure to
  fix, never as harmless noise. When adding a test that mirrors an existing one, copy its
  teardown too (`.free()`/`free_node`), not just its arrange/act.
- **Fixed:** Phase 04 close-out (D-025). `test_input_display_label.gd` now `svc.free()`s the
  InputService node in all three methods; verified 0 leaks via CI after removing the temporary
  `--verbose` diagnostic step.

## L-020 — `:=` inferring from a `-> Variant` helper breaks the whole `class_name` compile ("base 'GDScript'")
- **Symptom (Phase 06, D-032):** `SectState.from_dict()` did
  `var staged_allies := _parse_unique_id_array(...)` where the helper is `-> Variant` (returns
  `null` on malformed input, else `Array`). Godot's warning "The variable type is being
  inferred from a Variant value, so it will be typed as Variant" is **treated as error** in
  this project, so `sect_state.gd` FAILED TO COMPILE at lines 372/376/377. A script that fails
  to compile does **not register its `class_name`**, so every `SectState.create_from_template(...)`
  / `SectState.new()` across the suite raised the misleading runtime error
  `Invalid call. Nonexistent function 'create_from_template' in base 'GDScript'.` — which looks
  like a call-site problem but is really "the class never compiled". 13 sect tests cascaded
  (`is_ally`/`is_member` on `Nil`, `set_diplomacy: unknown sect`). The parse-check gate caught
  it as `SCRIPT ERROR: Parse Error ... at: GDScript::reload (sect_state.gd:372)` + "Failed to
  compile depended scripts" for every file that depends on SectState — THAT is the real root,
  not the call sites. **Two wasted guess-pushes** (converting test call sites preload-const
  vs class_name) changed nothing because the class simply wasn't compiling; the real error was
  only read once the FULL suite/parse log was examined (the user pasted it).
- **Rule:** **A `-> Variant` helper used with `:=` yields a `Variant` var -> warning-as-error ->
  the file won't compile.** When a value can legitimately be `null` OR a typed value, declare
  the receiver `var x: Variant = helper(...)` explicitly, and cast at the typed assignment
  (`field = x as Array[StringName]`). More generally: **"Nonexistent function X in base
  'GDScript'" almost always means the target class failed to COMPILE (its `class_name` didn't
  register), not that the call syntax is wrong** — read the parse/compile error for that
  script FIRST (grep the suite log for `Parse Error`/`Compile Error`/`GDScript::reload`), fix
  the compile, and the "nonexistent function" cascade disappears. Do NOT keep editing call
  sites. `get_diagnostics`/LSP may not surface this when the inferred-Variant warning is only
  promoted to an error by the project's warning config at full compile (ties to L-018: parse-
  clean != compiles-clean under warnings-as-errors).
- **Fixed:** Phase 06 (D-032). `sect_state.gd` `from_dict` now types the three staged arrays
  as `Variant` and casts on commit; CI `b3c98cc` green (all 9 gates).

## L-021 — Using an art asset without MEASURING it (light plate behind light text, hollow ornament as a keycap, 218×118 texture as a 40×40 slot)
- **Symptom (Phase 06 follow-up, D-034):** the HUD shipped broken four ways at once and every
  cause was an unverified assumption about a PNG. Reading the actual files settled it in one
  pass: `panel.png` has a centre brightness of **230** (near white) while every text token in
  `UIPalette` is light (0.62–0.96) → "white text on a white plate"; `key_badge.png` has a
  centre **alpha of 0** (it is a hollow corner ornament, not a keycap) so the glyph had no
  backing and its two 18px border bands collapsed into each other at keycap size → prompts
  rendered as smudges; `portrait_frame.png` is a **218×118 panel**, not a small frame, and a
  `TextureRect` left at the default `expand_mode = EXPAND_KEEP_SIZE` reports its whole texture
  as its minimum size, so `custom_minimum_size = Vector2(40,40)` was a no-op floor and a giant
  empty plate covered the character name. None of this is visible in code review, and
  `get_diagnostics`/the linter/the compile gate cannot see it.
- **Rule:** **measure an asset before building layout or colour decisions on it.** Before
  wiring a texture into a `StyleBox`/`TextureRect`/`NinePatchRect`, know its pixel size, its
  centre alpha (is there a fill to draw on?) and its centre brightness (light or dark surface?)
  — a 20-line stdlib PNG reader is enough, no Pillow needed. Then:
  - a surface that CARRIES TEXT must contrast with the text palette; never pair a light plate
    with a light-only palette "because the art looks nice";
  - `content_margin >= texture_margin` on every 9-slice box, or glyphs draw on the frame band;
  - a FRAME belongs in a `NinePatchRect`; a `TextureRect` used as a fixed-size slot MUST set
    `expand_mode = EXPAND_IGNORE_SIZE` or its `custom_minimum_size` is ignored;
  - record the measured numbers in the palette next to the margins they justify, and add a test
    that asserts the pairing (e.g. "the text panel uses the DARK texture"), so the next art
    pass cannot silently regress it.
- **Also (layout):** **growth direction belongs to the node that grows.** A panel was wrapped in
  an empty size-0 `Control` carrying `grow_horizontal = BEGIN`; growth does NOT propagate to
  children, so the panel still grew the default direction (rightwards) from the right edge and
  sat ~95% off-screen — which the player reported as "the key does nothing". Set anchors and
  growth on the node being positioned, and prefer a container over an empty anchor node.
- **Fixed:** D-034. Dark ink text plate + `accent_panel_stylebox()` for the light plate, drawn
  flat keycap, text outline, HUD wears the shared theme, `NinePatchRect` portrait, sect panel
  anchored on itself; four regression tests added.

## L-022 — A static camera hides behind a view that happens to fit, and a hook on every edit taxes every edit
- **Symptom A (D-036):** each map scene's `Camera2D` was a plain child parked at the map centre
  and **nothing ever moved it** — there was no follow code anywhere, since Phase 03. It looked
  correct for three phases purely because the whole map fitted on screen. The moment the view
  became smaller than the map, the player walked straight out of frame. Compounding it: the
  derived zoom used `ceil()`, turning a needed 3.01 into 4.0 (far too close), and a 448×288 map
  is smaller than a 16:9 screen at any comfortable zoom, so "cover the map" and "let the camera
  travel" were mutually exclusive until the map itself was authored larger.
- **Rule A:** when a camera, viewport or scaling value changes, **ask what was only working
  because the old value hid it.** "The whole level fits on screen" silently satisfies the
  requirement "the camera shows the player" — so verify the mechanism exists, not just that the
  result currently looks right. Camera framing has three coupled inputs (viewport size, zoom,
  map bounds); changing one without checking the other two produces either background bleed or
  an off-screen player. And when bounds and the painted floor are authored in SEPARATE files,
  add a test comparing them (an L-014 drift guard) — they drive the camera limits.
- **Symptom B (D-033):** the `PreToolUse` AI-review hook matched `fs_write|str_replace|fs_append`
  with an `agent` action, so it intercepted EVERY file edit and the tool call had to be re-issued
  — doubling the round trips for every single edit across a long session. Meanwhile the only
  on-save hook ran `godot`, which is not on PATH (D-009), so it no-opped silently and delivered
  zero value for a process spawn per save.
- **Rule B:** **a hook's trigger must match its purpose, and a hook that cannot run is worse
  than no hook.** A "before you declare done" reminder belongs on `Stop`, not on every write.
  Scope `PostFileSave` matchers to the paths that matter and make the command check only what
  changed (e.g. `git diff`-driven), not the whole project. If a hook depends on a binary that
  the machine does not have, delete it or make its absence loud — do not leave a silent no-op
  that costs time on every save and trains people to ignore hooks.
- **Fixed:** D-033 (reminder moved to `Stop`, dead `godot` hook removed, lint hook scoped to
  `^(src|tests|tools)/.*\.gd$` + `--changed`) and D-036 (camera follow in `MapBase`, no zoom
  round-up, maps authored 960×576, bounds↔floor drift test, E2E proves the camera moved).

## L-023 — Destroying the old value BEFORE the replacement succeeds (a "rollback" that only restores one side)
- **Symptom (Phase 06 final hardening):** `SectService._ensure_edge()` flipped a Sect↔Sect
  relationship from ALLY to ENEMY by `remove_edge(id)` **then** `create_edge(id, …)`. The
  surrounding `_set_diplomacy()` was correctly written as a transaction — relationship side
  first, sect side only on success — and a test even proved the sect side rolled back. But the
  rollback restored only the SECT side: by the time `create_edge` could fail, the original edge
  was **already gone**, taking its `dimensions` and `history` with it. A rejected flip left the
  sect state saying "allied" while the relationship graph held **no edge at all** — the exact
  divergence the transaction existed to prevent. Even on the SUCCESS path the recreate silently
  discarded every accumulated dimension value and the whole history log, because a "new" edge
  is seeded from config defaults. Nothing caught it: the flip test only asserted the resulting
  `relationship_type`, so a brand-new edge of the right type looked identical to a retyped one.
- **Rule:** **Never destroy the existing value before the replacement has succeeded.** When a
  mutation means "change one field of a thing that already exists", mutate IN PLACE (add a
  narrow API for it — `set_relationship_type()`) instead of delete-then-recreate. Delete-first
  is not a transaction: it makes failure unrecoverable and makes success lossy. Two concrete
  checks:
  - **A two-store transaction must be able to fail with NOTHING destroyed.** Order the steps so
    every rejection happens before the first write, and ask "if step 2 fails, is step 1's old
    state still there?" A rollback that restores store A while store B's data is already gone
    is not a rollback.
  - **Assert IDENTITY and PRESERVED state, not just the new value.** A test that only checks
    `type == ENEMY` passes for a recreated object. Capture `get_instance_id()` plus the fields
    that must survive (dimensions, history, flags, endpoints) and assert they are unchanged —
    that is what distinguishes "retyped" from "replaced".
- **Fixed:** Phase 06 final hardening. `RelationshipService.set_relationship_type()` (in place,
  rewrites only the type); `_ensure_edge` never removes; tests 29-31 in
  `tests/unit/sect/test_sect_domain.gd` assert object identity + dimension/history survival on
  the success path AND full survival of the old edge on the rejected path.

## L-024 — Coercing a value before validating its type turns a corrupt payload into an accepted state
- **Symptom (Phase 06 final hardening):** `SectState.from_dict()` was carefully fail-closed and
  atomic — and still accepted garbage, because every field was read through a CONVERSION:
  `String(dict.get("leader_ref", ""))`, `int(resources[key])`, `int(dict.get("influence", 0))`.
  GDScript's converters do not fail, they invent: `int("100")` and `int(100.0)` both yield the
  valid quantity `100`; `int(true)` yields `1`; `String(99)` yields the plausible id `"99"`;
  `String(null)` yields `""`, which then reads as the legitimate "this sect has no leader"
  rather than "this payload is corrupt". So a save with the wrong TYPE in a field sailed through
  every subsequent range/roster check and committed, and the validator's own error messages
  could never fire. The same shape sat in `_parse_unique_id_array`, where `String(42)` made a
  number into a sect id and `String(true)` made a bool into `"true"`.
- **Rule:** **At a hydrate/deserialize boundary, check `typeof()` FIRST and reject; only then
  convert.** Never use `String()`/`int()`/`float()` as a validator — they are coercions, and a
  coercion that succeeds on bad input is indistinguishable from valid input. Concretely: an
  ID-like field must be `TYPE_STRING` or `TYPE_STRING_NAME` (not a number, bool, null, object,
  array or dict); a COUNT-like field must be `TYPE_INT` (a float is rejected even when integral,
  so `100.0` is not quietly promoted). Apply it to dictionary KEYS too, not just values — a
  roster/resource/reputation key is an id. Keep the staged-then-commit shape so a rejection
  leaves the receiver byte-identical, and write each negative test so the payload differs from a
  KNOWN-GOOD fixture in exactly one field **and would otherwise be accepted** — if the bad
  payload would fail for a second reason anyway, the test proves nothing about the type check.
- **Fixed:** Phase 06 final hardening. `SectState._is_id_token()` + per-field `typeof()` gates in
  `from_dict`/`_parse_unique_id_array`; tests 33-43 in `tests/unit/sect/test_sect_domain.gd`
  (test 33 proves the baseline fixture is accepted; each other case asserts `false` AND an
  unchanged snapshot).

## L-025 — "Warn and continue" inside a session starter publishes a half-session, and a dependency that quietly became mandatory
- **Symptom (Phase 06 final hardening):** `SectRuntime.start_session()` wrote straight to its own
  fields as it went, `continue`d past a sect that failed to register, `push_warning`ed when the
  player could not join the start sect — and then set `_session_active = true` and returned
  `true` regardless. So `is_session_active()` could report a live sect world that was missing
  sects, had no player membership, or (because `apply_default_diplomacy()` returned `void` and
  skipped unmirrorable pairs) declared enmities that the relationship graph had no record of.
  `Main` then compounded it: it treated BOTH the relationship and sect sessions as advisory
  (`push_warning`, keep going) even though the sect session had become a hard CONSUMER of the
  relationship graph and a writer of the player's derived `CharacterState.sect_id`. The
  reachable end state was a game at phase `RUNNING`, world live, `character.sect_id` set, and
  the sect subsystem inactive — membership that no system owned. Every gate was green, because
  "returns true" was the only thing anyone asserted.
- **Rule:** **A session starter must build into LOCALS and commit to its own fields only after
  every step has succeeded** — then a failure is invisible by construction (`is_session_active()`
  stays false, every getter stays empty) instead of relying on a cleanup path to undo a partial
  write. Inside such a function, `continue`/`push_warning`-and-proceed is banned: either the
  step is required (abort the whole start, loudly, naming the step) or it is genuinely optional
  (then it must be legal for it to be absent — e.g. no mirror is fine only when nothing declares
  diplomacy). Also: **when a subsystem becomes a real consumer of another, its caller must stop
  treating that dependency as advisory** — re-read the caller when you add the dependency, don't
  leave the old `push_warning`. And **name the forbidden combination and assert it**: write the
  impossible state down ("RUNNING + world live + character.sect_id set + sect session inactive")
  and put an assertion in the E2E that it cannot be reached, because "start returned true" is
  not a test of what the session contains. Extends L-004 (fail loud on a missing REQUIRED
  dependency) from the bootstrap's autoload check to every per-session subsystem.
- **Fixed:** Phase 06 final hardening. `SectRuntime.start_session()` is a 9-step fail-closed
  build with `_fail_start()`; `apply_default_diplomacy()` returns `bool` and fails closed on a
  dangling or unmirrorable declaration; `Main` makes relationship + sect failures FATAL for New
  Game and unwinds Sect → Relationship → World → GameState → MENU via
  `_unwind_failed_session()`; `tests/unit/sect/test_sect_runtime.gd` asserts no observable
  half-session after a rejected start, and `tests/e2e/world_flow_case.gd` asserts the forbidden
  combination is unreachable.

## L-026 — A test method that ABORTS is reported as PASS (the runner only counts assertion failures)
- **Symptom (Phase 06 final-hardening follow-up, D-038):** CI reported `275 passed / 0 failed`
  while the headless log contained real `SCRIPT ERROR:` lines. Seven test methods had never
  executed a single assertion. Root cause: a typed `@export` will not accept an untyped array.
  `RelationshipConfigData.dimensions` is `Array[Dictionary]` and
  `RelationshipRuleCatalog.rules` is `Array[RelationshipRuleData]`, but the fixtures pushed a
  plain `Array` at them (`_config(dims: Array)` passing its untyped parameter;
  `cat.rules = [_rule(...), ...]` where `_rule()` was declared `-> Resource`). That raises
  `Invalid assignment of property 'dimensions' with value of type 'Array'`, which is a GDScript
  **VM** error: it ABORTS the running function. So the fixture helper returned `null`, the
  caller hit `Invalid call ... on a null value`, the test method died — and because
  `TestCase` records only *assertion* failures, `get_failures()` came back empty and
  `run_tests.gd` printed `[PASS]`. Six config tests and one rule-catalog test sat green for two
  phases testing nothing. `get_diagnostics`, the linter and the parse/compile gate cannot see
  it: the code is syntactically fine and compiles; the fault only exists at runtime.
- **Rule:** **"the runner said PASS" is not "the test ran".** A custom runner that cannot catch
  exceptions (GDScript has no try/catch — D-004) cannot distinguish a passing method from one
  that aborted on the first line, so the SUITE must be checked for `SCRIPT ERROR:` separately —
  that prefix is the VM reporting a runtime fault and is distinct from the `USER ERROR:` that
  `push_error()` prints, so deliberate fail-closed tests do not trip it. The headless CI gate
  now fails on any `SCRIPT ERROR:` even when the runner exits 0. Concretely, when writing
  fixtures:
  - **A typed `@export` array needs a typed value.** Build a typed LOCAL first
    (`var dims: Array[Dictionary] = [...]`) and assign THAT; a literal assigned to a typed
    local is always safe, while `obj.typed_prop = [literal]` depends on the compiler knowing
    the property's type — which it does not when the receiver is declared as a loose base
    (`var cfg: Resource = ...`). Type fixture receivers and helper returns as the CONCRETE
    class, never `Resource`/`Node`/`Object`.
  - **Assert the fixture before asserting the behaviour.** `assert_eq(cfg.dimensions.size(), 1)`
    turns a silently-empty fixture into a visible failure.
  - **Pin the REASON in a negative test.** `assert_false(x.is_valid())` passes for a fixture
    that failed to build (it is invalid for the wrong reason); also asserting the reported error
    message makes that impossible. Every negative case should differ from a KNOWN-GOOD fixture
    in exactly one field and would otherwise be accepted (ties to L-024).
- **Fixed:** D-038. Typed fixtures in `test_relationship_config.gd`,
  `test_relationship_rules.gd`, `test_relationship_graph.gd`, `test_sect_domain.gd`,
  `test_sect_runtime.gd` (plus `_ladder()`/`_ids()`/`_catalog_of()`/`_rel_config()` typed
  builders), reason-pinned negative assertions, and the `SCRIPT ERROR:` check added to the
  EXISTING headless gate (still 10 gates).

## L-027 — A self-imposed "I cannot create a new script" belief blocked a whole phase (the `.uid` encoding is knowable, and verifiable)
- **Symptom (D-041 → D-042):** Package A rejected the cleaner factoring — extracting shared
  `UISectionTitle` / `UIValueRow` components — on the grounds that this agent cannot produce the
  `.uid` sibling Godot generates for a new `.gd`, and L-008/L-015 require that sibling to be
  committed. The whole UI pass was therefore done by editing existing files only. One task later,
  Phase 07 needed **twelve** new scripts (domain + data + runtime + presentation + tests) and the
  same belief would have blocked the entire phase. The belief was false, and nobody had checked:
  the constraint was inherited as an assumption, not measured.
- **What was actually true:** Godot's `ResourceUID` text form is `uid://` + an integer in
  **base-34**, because the engine computes its base as `('z' - 'a') + ('9' - '0') = 25 + 9 = 34`.
  Letter values come FIRST — `a`..`y` carry 0–24 — and digits follow: `0`..`8` carry 25–33.
  Most-significant digit first. Note both off-by-ones: there is no `z` and no `9` in the alphabet.
  Two related facts worth knowing: `.tres` resources in this repo carry **no** `.uid` sibling at
  all (16 of them, zero uid files), and nothing in the project references a script by `uid://` —
  every reference is `preload("res://...")`, so only `main.tscn` depends on uid stability.
- **Rule:** **Before accepting a capability limit that changes your design, test it.** A limit
  that makes you reject the better structure deserves a 10-minute experiment, not deference —
  especially when it is inherited from your own earlier reasoning rather than from a tool error
  you actually saw. And when the limit involves an encoding, **verify by round-tripping the
  REAL existing data before producing any new data**: a decoder was run against **all 96 `.uid`
  files in the repo** and had to re-encode each one to the identical string before a single new
  UID was minted. That caught a wrong first guess immediately (base 36 with digits-first decoded
  `main.gd.uid` to a value above 2^63, which is impossible for an engine id) — a guess that
  "looked fine" would have shipped 12 subtly invalid files. Mint new ids as random 63-bit values
  and collision-check them against the existing set.
- **Also:** when a constraint forces a documented design compromise, say so in the DECISIONS
  entry (D-041 did) — that is what made the compromise easy to find and reverse the moment the
  constraint turned out to be imaginary. A silent workaround would have quietly become permanent.
- **Fixed:** D-042. Twelve new scripts shipped with correct, verified `.uid` siblings.

## L-028 — `set_anchors_preset` PRESERVES the current rect; it does not reset the offsets (a 0×0 `.tscn` root stayed 0×0)
- **Symptom (D-043):** the whole main menu rendered crammed into the top-left corner at a few
  hundred pixels, with the four "screen corner" ornaments collapsed into a tiny border around
  it, on a 1904×914 window. `MainMenu._ready()` called
  `set_anchors_preset(Control.PRESET_FULL_RECT)` as its first line, so the anchors WERE
  `0,0,1,1` — which is why it looked like a mystery.
- **Root cause:** `set_anchors_preset(preset, keep_offsets = false)` does not zero the offsets.
  It RECOMPUTES them so the control's current on-screen rect is PRESERVED
  (`offset[side] += parent_range * (old_anchor - new_anchor)`). `main_menu.tscn` authors its
  root `Control` with no size properties at all, so the rect was `0×0` — and the call
  faithfully kept it `0×0` while setting full-rect anchors. The `CenterContainer` then centred
  the plaque inside a `0×0` box at the origin. The HUD never hit this because it calls the
  preset **before** `add_child`, where `parent_range` is 0, so the offsets happen to stay 0 —
  i.e. the two call sites looked identical and behaved completely differently.
- **Rule:** **for a screen that must fill its parent, call
  `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`.** Reach for `set_anchors_preset` only
  when you genuinely want to keep the existing rect. Corollary for tests: asserting the
  ANCHORS proves nothing — the broken build had correct anchors. Assert the **offsets**, which
  is where the fault actually lives.
- **Also (the same class, different node):** a toggleable panel anchored from the centre with
  `grow_vertical = BOTH` takes its CONTENT's minimum size, so a long list grew past the top and
  bottom of the viewport. Because a 9-slice frame is drawn at the control's edges, those edges
  were off-screen and the panel rendered **with no visible plate**, while also burying the
  control prompts underneath it. **A panel that can hold unbounded content must be a BOUNDED
  BOX pinned to screen anchors on all four sides, with a `ScrollContainer` inside** — then
  overflow is structurally impossible instead of depending on content staying short. Reserve
  the strip that another element owns (here the prompt row) in a named constant so "panels must
  not cover the prompts" is enforced by arithmetic, not by eye.
- **Also (input):** when every node in a panel is `MOUSE_FILTER_IGNORE` for click-through, the
  `ScrollContainer` must be explicitly `MOUSE_FILTER_STOP`, or the wheel passes through and the
  clipped content is unreachable.
- **Fixed:** D-043. `main_menu.gd` + `settings_menu.gd` use the and_offsets variant; both HUD
  side panels are bounded boxes with scrolling content; regression tests pin the OFFSETS, the
  bounded-box contract and the reserved prompt strip.

## L-029 — An OPTIONAL field that nobody authored made a whole pipeline a no-op, and every gate stayed green
- **Symptom (D-046):** the owner kept saying the character looked like dead placeholder art. The
  character visual pipeline was *correct*: `CharacterVisualProfileData` validated, the four
  archetype profiles loaded, `CharacterVisualComponent` rendered a nearest-filtered feet-anchored
  sprite, facing followed the movement vector, `player_default.tres` wired `sprite_set_ref`,
  `WorldRuntime` applied it, and a dedicated test file covered all of it. 378 tests green. And
  the character **never animated once**, because the sheet layout carried exactly ONE frame per
  direction and all four profiles left the OPTIONAL `walk_sheet` field `null`. The documented
  "falls back to idle if absent" behaviour was doing its job perfectly — it just meant the
  fallback was the only path that ever ran, in every profile, forever.
- **Rule:** **an optional field that no shipped data authors is not a feature, it is a no-op with
  documentation.** When you add an optional capability, either author it in at least one real
  piece of content in the SAME change, or write down the date it becomes required. Then assert
  the *observable effect*, not the plumbing: "the component picks the walk sheet when moving" is
  satisfied by a null walk sheet, whereas "the frame index CHANGES over time while moving" is
  not. A test that exercises a configuration no shipped data uses is testing a hypothetical.
  Concretely, for anything time-varying: assert that the output **differs between two moments**,
  and that a full cycle **returns to the start** — a pipeline that renders frame 0 forever
  passes every single-sample assertion.
- **Also (two related traps this change walked into):**
  - **Derive a count, never author it beside the data it counts.** The frame count comes from
    the texture width, so art and data cannot disagree (extends L-014). And reject a ragged
    width loudly instead of flooring it — a floor renders half a character and reports nothing.
  - **Check your own earlier claims before building on them.** Two statements I had made to the
    owner were wrong and both were cheap to verify: that `player.tscn` ignored the directional
    art (it did not — the template wires it and the static sprite is only the harness fallback),
    and that a specific external pack's hero sheets could be imported (they are side-view
    platformer art — the pack's own terrain folder is `platform_top` + slopes, the animation set
    is `jump`/`fall`/`dash`, and a direction-token scan across all nine supplied asset folders
    returned zero hits; the frames were also 111×81, not the 79×78 I had recorded, with the
    height changing per animation). An inherited assumption deserves the same scepticism as a
    new one — see L-027, which is the same failure in the opposite direction.
- **Also (art process):** generated pixel art must be **looked at magnified** before it ships.
  Inspecting the sheets at 8× caught two defects no assertion would have: the draw order put
  SKIN over the hair on every UP frame (a bare face on the back of the character's head), and
  the walk deltas were ±1px, i.e. indistinguishable from idle — a "walk animation" that
  animated nothing a player could see, which is the very defect this change existed to fix.
- **Fixed:** D-046. Grid sheet layout (direction rows × animation columns), derived frame count,
  required `walk_sheet` in all four profiles, an animation clock with a public `advance(delta)`
  for deterministic tests, and assertions that the frame index advances, wraps, stays in its row
  and resets across an idle↔walk switch.

## L-030 — Two hand-written copies of an ORDER drift, and "the dependency is absent so skip the step" is a fail-OPEN mutation
- **Symptom A (D-047):** New Game starts the per-session subsystems in dependency order
  (World → Relationship → Sect → Faction). `_unwind_failed_session()` reversed it correctly.
  `_on_return_to_menu()` was a SECOND, hand-written sequence and had drifted: it ended **World
  and Relationship first**, so a normal return to menu freed the player's `CharacterState` and
  dropped the relationship graph while the sect and faction sessions — whose state is *defined
  in terms of* those two — were still unwinding through them. Its own comment two lines above
  said "End the faction session FIRST". Three phases, every gate green, because the only thing
  ever asserted was "all four sessions are down afterwards", which is true for ANY order.
- **Rule A:** **an ORDER is a value, not a code pattern — store it once and walk it.** If two
  functions both sequence the same steps, that is not duplication you can "keep in sync", it is
  a future divergence with a comment on it. Put the order in ONE constant, have one function
  walk it (forwards or reversed), and make every entry point delegate. Then add the guard that
  would actually have caught the drift: not "is the order right" but **"is there only one place
  that does this?"** — assert that exactly one function in the file issues the call, and that it
  consumes the constant instead of re-listing the steps. And **make the order observable**
  (record what the teardown actually ended, in order): an invariant nothing can read back is
  only a comment, and "everything ended up down" never tests a SEQUENCE.
- **Symptom B (D-047):** `FactionService._set_politics()` guarded the relationship mirror with
  `if _relationship != null and not _ensure_edge(...)`, and `_ensure_edge()` itself opened with
  `if _relationship == null: return true`. With no graph installed the mirror was SKIPPED and
  `add_rivalry()` **returned true** — the faction state then recorded a declared rivalry that no
  edge backed, breaking the frozen "declared politics IS a mirrored edge" invariant. Worse, it
  was unrecoverable: `clear_politics()` fails closed on exactly that state, so the pair was
  stuck declared for the rest of the run. `apply_default_politics()` had already been hardened
  against the same situation (D-038); the MUTATION path was the door left open. The identical
  two lines sat in `SectService._set_diplomacy()`.
- **Rule B:** **"the dependency is absent, so skip that step and succeed" is only legitimate
  when it is genuinely legal for the dependency to be absent.** For a MUTATION that writes one
  fact into two stores it never is — skipping half of it and returning `true` manufactures the
  divergence the transaction exists to prevent. Check the dependency as a PRECONDITION, before
  any other rule, so the rejection names the real reason. Keep the fail-closed guard in the
  low-level helper too (`_ensure_edge`), even once every caller checks: that `return true` *was*
  the mechanism, and leaving it lets a future third caller reopen the hole without touching the
  guard. Also: **when you fix a fail-open skip, grep for its siblings** — the same two lines
  existed in the sect mirror and nobody had reported it.
- **Also (the general shape of both):** when a defect is reported in one place, ask what the
  SAME defect looks like in the neighbouring system, and write the negative test so it asserts
  all four halves of "nothing happened" — the return value, BOTH parties' state, the absence of
  the signal, and the absence of anywhere the skipped write could have hidden.
- **Also (a leak that exits 0):** the suite had been reporting `17 ObjectDB instances were
  leaked` / `8 resources still in use` at shutdown with CI green, because the engine prints that
  AFTER the runner has exited 0. Cause: a **`RefCounted` reference CYCLE** — a test fixture
  installed a resolver lambda capturing `self`, the `Callable` was stored on a service, and the
  test instance kept that service on a field. GDScript `RefCounted` is reference-COUNTED, not
  garbage-collected, so a cycle is never collected and one pinned test instance holds its whole
  fixture plus every GDScript it touches. **L-019 extends to cycles, not just unfreed `Node`s:**
  if a test stores a service that holds a `Callable` capturing `self`, clear the `Callable` in
  `after_each` (nulling the field is not enough if anything else still holds the service). The
  existing headless gate now FAILS on those two shutdown lines, exactly as it already does on
  `SCRIPT ERROR:` — same gate, no new gate.
- **Fixed:** D-047. `Main.SESSION_START_ORDER` + `_end_session_stack()` (one ordered teardown,
  both entry points delegate) + `get_last_teardown_order()`; precondition checks in
  `FactionService._set_politics` / `SectService._set_diplomacy` and fail-closed `_ensure_edge` on
  both; `tests/unit/bootstrap/test_session_lifecycle.gd` (order constant, reversal, the
  one-function structural guard), the real teardown trace asserted in
  `tests/e2e/world_flow_case.gd`, faction tests 41-43, sect test 53, and an `after_each` breaking
  the fixture cycle. Every new guard was proven able to fail against the pre-fix code.

## L-031 — An inherited "the tool cannot run here" constraint was never re-tested (D-009 was false)
- **Symptom (D-047):** D-009 recorded "Godot is not invocable locally", and that single fact
  shaped the whole process: L-007 ("parse passing is not done — push and read the CI check-run"),
  L-016/L-020 (diagnose a CI-only failure by reading code), L-027 (verify an encoding by hand),
  and all of `10-ci-failure-protocol.md`, which exists because each verification cost a CI
  round-trip measured in minutes of the owner's time. Nobody re-checked it. The 4.7-stable Linux
  build downloads in 13 seconds and runs headless fine; the complete gate set — lint, import,
  parse/compile, boot smoke, the 392-test suite and all three isolated E2E processes — runs
  locally in about three minutes.
- **Rule:** **re-test an inherited capability constraint before letting it shape a plan**, every
  time the plan is big enough that the constraint is expensive. This is L-027's rule applied to
  the environment rather than to an encoding, and it is the same failure in the same direction:
  a limit accepted from one's own earlier reasoning rather than from a tool error observed now.
  Concretely, for this project: run the gates locally FIRST, iterate there, and push a change
  that is already green. **CI stays the authority** — it is the clean-room run and the gate
  definitions live in the workflow — but it is no longer the only way to learn something is
  broken, and "guess → push → wait → guess again" (the exact pattern steering 10 forbids) now
  has no excuse at all. What is still genuinely unverifiable locally: **anything on screen.** A
  headless run renders nothing, so a layout/art claim still needs a screenshot from the owner.
- **Fixed:** D-047 (process note). The local gate mirror lives outside the repo (L-009: no
  scratch files in the tree).

## L-032 — A derived value beats a stepped one, and a performance CLAIM must be measured by a test that can fail
- **Symptom A (Phase 08, D-048 — a trap avoided, recorded because it is the whole design):** the
  obvious way to advance a background character's routine is to step a phase index each tick.
  It is also wrong under LOD, and the wrongness is invisible until late: stepping makes an
  actor's state depend on HOW OFTEN it was stepped, and *not stepping far-away actors is the
  entire point of LOD*. A stepped FAR actor falls behind; promoting it then either loses
  simulated time or needs a catch-up loop whose result depends on the player's travel history —
  so the same save, played with different routes, yields different worlds.
- **Rule A:** **when a value can be DERIVED from state you already keep, derive it — do not step
  it in parallel.** Here the activity is a pure function of `(tick − joined_tick, schedule)`, so
  NEAR/MID/FAR all compute the same answer, the LOD band controls only how often the system
  LOOKS (never what it sees), and promotion/demotion is lossless by construction rather than by
  a careful catch-up. Keep a cached copy ONLY if you need to detect a CHANGE, and then say so at
  the field and treat it as a cache (the D-015 authority/cache shape), never as the answer: the
  public read must go to the derived function, or a far-away actor's reported state silently
  depends on when it was last visited. Test the property directly — "a FAR actor's value equals
  an observed actor's on the same input at every tick" — not just that promotion "works".
- **Symptom B (same phase):** the per-tick loop needed the NEAR+MID actors and obtained them by
  FILTERING a sorted list of the whole cast. That is `O(cast · log cast)` **per tick** — the
  exact cost LOD exists to eliminate, sitting inside the code that implements LOD. Nothing was
  functionally wrong; every test passed; a comment above it said the loop was `O(observed)`.
  The budget test caught it: with the observed set held constant at 10, a 10× larger FAR
  population cost **3.57×** more per tick (50 ms vs 14 ms for 300 ticks). An incremental index
  fixed it — 12 ms for both, scaling factor **1.0×**.
- **Rule B:** **write the performance test BEFORE declaring the feature done, and make it a
  RELATIVE assertion against the build itself.** An absolute millisecond budget on shared CI
  hardware is a flaky test that gets deleted; a ratio ("10× more background actors must not cost
  3× more per tick") fails on any machine and names the architectural claim it is defending.
  Keep a generous absolute ceiling alongside it, whose only job is to catch an accidental
  quadratic. And note the shape of the bug: a comment asserting a complexity is not a complexity
  — **if the architecture's selling point is a cost model, the cost model needs an assertion, or
  the first refactor will quietly revert it.** When an index is introduced for this, make it
  DERIVED and rebuild it on hydrate rather than serializing it, and funnel the mutation that
  maintains it through ONE method (here `set_actor_band`), so the index cannot go stale behind
  somebody's back.
- **Also (a degenerate tuning value must still consume its draw):** `next_chance(0)` and
  `next_chance(100)` both advance the RNG stream. If they short-circuited, editing a probability
  to 0 or 100 would shift every subsequent draw in that stream — the same cross-subsystem
  contamination that per-stream state exists to prevent, reintroduced INSIDE one stream. The
  general rule: **a deterministic sequence's position must depend on the CALLS made, never on
  the VALUES configured.**
- **Also (draw before you apply):** when a random magnitude feeds an operation that can be
  rejected, draw it FIRST and unconditionally. If a failed application skipped the draw, a
  content bug in one event would change how far the stream had advanced and therefore every
  later random outcome in the world — a local mistake with global, invisible consequences.
- **Fixed:** D-048 / PERF-001. `WorldSimActor`'s derived activity, `WorldSimulationState`'s
  incremental `_observed` index + `set_actor_band()`, and
  `tests/performance/test_world_sim_budget.gd`.

## L-033 — A test file that fails to PARSE hung the whole runner until the CI job timed out
- **Symptom (Phase 08):** one bad line in a new test file (`runtime is CanvasItem`, which the
  compiler rejects because the type is statically known) made that file fail to parse. `load()`
  still returned a non-null `GDScript`, so `run_tests.gd` called `script.new()` on it, which
  raised `Invalid call. Nonexistent function 'new' in base 'GDScript'` — a GDScript **VM**
  error, which ABORTS the running function. `_run()` died before reaching `quit()`, so the
  headless `SceneTree` never exited and the process hung. Locally that burned a 15-minute
  timeout; in CI it would have burned the job's whole budget, and the eventual log would have
  shown a timeout rather than a parse error.
- **Rule:** **`load()` succeeding is not the same as a script being usable — check
  `can_instantiate()` before calling `new()`.** More generally, in a custom headless runner,
  every path out of the run loop must reach `quit()`: GDScript has no try/catch (D-004), so any
  VM error between the loop and the exit converts a one-line mistake into a hang, which is a far
  worse failure mode than a red test because it looks like infrastructure rather than like a
  bug. The parse-check gate runs before the suite in CI and would have named the file first,
  which is exactly why it is ordered that way — but the suite must not be *capable* of hanging
  on input the gate before it is meant to catch.
- **Also:** the same class bit THREE times in one phase. (a) `CharacterRegistry.hydrate` passed
  a payload row straight to `CharacterState.from_dict`, whose parameter is statically typed
  `Dictionary` — so a non-dictionary row was a VM error (aborting the caller) instead of a
  rejection. (b) `WorldSimulationState.from_dict`/`to_dict` dereferenced a null `_clock` when
  the object had been built with `new()` instead of its `create()` factory. (c) `activity_of()`
  null-checked one of the two fields it dereferenced. **At a hydrate/serialize boundary,
  type-check a nested value BEFORE handing it to a statically-typed parameter, and null-check
  EVERY field the method dereferences — not just the first one** — or the fail-closed path
  crashes instead of failing closed. The second one mattered most: `new()` + `from_dict()` is
  the pattern a future `SaveService` will use, so the crash sat on the critical path of a
  feature that did not exist yet and no existing test could reach it.
- **The tell that this class is present:** a class with a `create()`/factory that validates, and
  a `new()` that does not. Anything public on such a class must survive being called on the
  `new()` form — write one test that does exactly that, because every OTHER test will naturally
  use the factory and none of them will ever touch the broken path.
- **Fixed:** D-048. `tests/run_tests.gd` checks `can_instantiate()` and reports the file;
  `CharacterRegistry.hydrate` type-checks each row; `WorldSimulationState` guards both
  serialization entry points; `activity_of` guards on `is_usable()`. Regressions in
  `tests/unit/worldsim/test_world_sim_service.gd` tests 22-24, each verified to fail against the
  pre-fix code.

## L-034 — A named reserve nobody measured, and a structural guard with a hand-written file list
- **Symptom (D-050 review pass):** three defects, all introduced by the very commit that cited
  the rules they broke, and all found by *looking at a capture* rather than by any assertion.
  1. `UIPalette.TOP_PLAQUE_RESERVE` existed, was consumed correctly by both side panels, and
     was **104** — while the plaques it reserves for measure **identity 156** and **map 122**.
     So the left politics panel covered the identity plaque's affiliation tier by ~52px and the
     right sect panel cleared the map plaque by 2px. The only assertions on the constant were
     `> 0` and "the HUD source mentions the token": the arithmetic L-028 asked for was all
     there, and one of its inputs was a guess.
  2. The structural guard "no screen builds its own divider" **listed two files** —
     `main_menu.gd` and `gameplay_hud.gd` — and passed while `sect_panel.gd` and
     `faction_panel.gd` were still building their own, at a third height. The defect was live
     in two of the four screens that had it, and the commit message claimed one factory.
  3. The guard also watched the **retired** token (`TEX_TITLE_DIVIDER`), i.e. it could only
     ever catch the mistake already made. The realistic regression is a new panel copying the
     factory BODY, which names the CURRENT texture.
  Plus a near miss of the same shape: the HUD test helper that collects divider strips matched
  on the OLD texture path, so after the HUD moved it would have found zero strips — caught
  only because a sibling assertion required `>= 2`.
- **Rule:** **a reserve/limit constant must be derived from a MEASUREMENT of the thing it
  reserves for, and a test must re-measure it.** `assert_true(RESERVE > 0)` and "the source
  mentions the token" assert that somebody thought about it, not that the number is right.
  Measure with `get_combined_minimum_size()` rather than `size` so the assertion does not
  depend on the runner's window. Corollaries:
  - **A reserve is unknowable while the thing it reserves for can grow without bound.** The
    map plaque held an autowrapping sentence with no line cap, so it had no maximum height.
    Cap it (`max_lines_visible` + ellipsis overrun) so the worst case exists, and have the test
    add the lines the cap allows but the current text does not use — otherwise the number is
    right for the capture that was taken and wrong one language later.
  - **A structural source guard must WALK the directory, never list files.** A hand-written
    inventory only protects the files somebody remembered. And point it at the LIVE token (plus
    the raw filenames, so hardcoding the path does not slip past), excluding only the files
    that legitimately own the seam — the declaring palette and the one factory.
  - **Retire a superseded constant, do not leave it unused.** A named path is an invitation:
    the next screen reaches for the nearest divider-shaped constant and re-creates the bug. Drop
    it from the runtime contract list too (a list documented as "every runtime texture" must not
    contain one nothing loads), and update the provenance row to say UNWIRED rather than leaving
    a "where used" that is now fiction.
- **Also (tooling):** a capture/report tool must **fail loudly and exit non-zero** when it could
  not reach the state it is about to name. The harness flipped a panel by private field name and
  ignored the result, so a renamed field would still have written `07_sect_panel.png` with the
  panel closed. A capture that quietly lies is worse than a missing one, because the file's
  entire job is to be the evidence a human reviews.
- **Also (process):** these were found by the mandatory review pass on a commit that was already
  green on all 10 gates, by opening the screenshots the commit itself had produced. Generating
  the evidence is not reviewing it.
- **Fixed:** D-050 review pass. `TOP_PLAQUE_RESERVE` 104 -> 174 with the measurement recorded
  next to it; `HUD_WORLD_EVENT_MAX_LINES` caps the one unbounded label; the plaques are NAMED so
  the assertion can say which one is wrong; `test_the_reserved_top_strip_is_tall_enough_for_the_plaques_it_reserves_for`
  re-measures both; the divider guard walks `src/presentation` and watches the live token;
  `sect_panel`/`faction_panel` call `UITheme.ornament_divider()`; `TEX_TITLE_DIVIDER` retired;
  `capture_ui.gd` reports and exits non-zero.
