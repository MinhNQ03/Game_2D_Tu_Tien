# DECISIONS — Aetheria (ADR log)

> Lightweight Architecture Decision Records. One entry per meaningful decision.
> Status values: **Accepted · Proposed · Open (undecided) · Superseded**.
> Open items must be resolved before the phase that depends on them (`docs/ROADMAP.md`).

---

## D-001 — Documentation & process foundation first  — **Accepted** (2026-10-02)
**Context:** New, essentially empty Godot project; goal is long-term maintainability,
extensibility, performance, and future multiplayer.
**Decision:** Before any gameplay, establish steering rules (`.kiro/steering`) and a
`docs/` set (flow, architecture, roadmap, tests, data, save, performance, assets,
localization, multiplayer plan) plus a `tests/` scaffold.
**Consequence:** Slower start, but every later change has rules + a review protocol to
follow. Build-pass is explicitly not "done" (`.kiro/steering/08-ai-review-protocol.md`).

## D-002 — 3D physics engine enabled on a 2D project  — **Accepted** (2026-10-02; resolved 2026-10-02)
**Context:** `project.godot` set `[physics] 3d/physics_engine="Jolt Physics"`, but
Aetheria is a 2D top-down game. Leftover default from project creation.
**Decision:** Option (b) — removed the entire `[physics]` section (it contained only the
3D engine setting). The game uses Godot's 2D physics (`PhysicsServer2D`), which is not
affected by `3d/physics_engine`. 2D top-down pixel art also led us to add
`[rendering] textures/canvas_textures/default_texture_filter=0` (nearest filtering) per
`.kiro/steering/06-art-assets.md`.
**Verification:** config re-read after edit; no `[physics]` section remains; GDScript
diagnostics clean; smoke test asserts the project still boots and the main scene loads.
No 2D physics setting depends on the removed key. (Full headless run deferred to CI — see
D-009.)
**Consequence:** honest 2D-only config; if 3D is ever needed (it should not be), re-add
the setting. Low risk, reversible.

## D-003 — Map/scene strategy: instanced scenes vs. streaming  — **Accepted** (resolved 2026-10-02, Phase 03)
**Context:** "nhiều map" + dungeons; need clean transitions with no leaks.
**Options:** (a) one PackedScene per map, loaded/unloaded via SceneRouter; (b) a streamed
/ chunked world.
**Decision:** **(a)** — one PackedScene per map, loaded/unloaded through the existing
`SceneRouter` (the single transition entry point). Rejected (b): a chapter-based top-down
RPG does not need streaming/chunking; the router abstraction keeps the strategy changeable
later if a specific huge map ever needs it, without touching call sites.
**Consequence:** Phase 03 ships two authored map scenes (hub + field) registered with
SceneRouter by `scene_key`, and a `WorldRuntime` node coordinates load/unload + the
persistent per-session player. See **D-021** for the WorldRuntime/`scene_key` details.

## D-004 — Test framework: GUT vs. custom headless runner  — **Accepted** (resolved 2026-10-02)
**Context:** Need headless CI tests from early on.
**Options:** (a) GUT (featureful, third-party addon); (b) minimal custom `SceneTree`
runner (zero dependency).
**Decision:** **(b) custom headless runner.** Rationale weighed on the criteria asked:
- **Dependency cost:** zero. GUT would be a vendored/pinned third-party addon (extra
  supply-chain + upgrade surface) that `.kiro/steering/04-coding-standards.md` says to
  avoid until there's a real need.
- **CI:** runs with the stock Godot binary via `-s res://tests/run_tests.gd`; nothing to
  install, exit code fully under our control.
- **Maintainability:** ~150 lines we own; no addon version drift against Godot 4.7.
- **Unit/integration ability:** our high-risk logic is pure domain code; the minimal
  `TestCase` assert API (`tests/framework/test_case.gd`) covers unit + integration +
  smoke needs. The runner discovers `test_*.gd`, runs `test_*` methods, and exits
  non-zero on any failure.
- **Stability:** no dependency on an addon tracking engine changes.
**Revisit trigger:** if the suite grows to need fixtures/mocks/parameterization beyond
what the minimal harness gives, re-evaluate GUT (new ADR, don't silently swap).
**Command (pinned):** `godot --headless --path . -s res://tests/run_tests.gd`
**Consequence:** `tests/run_tests.gd` is now a real runner (not a placeholder);
`docs/TEST_PLAN.md` and `tests/README.md` updated.

## D-005 — Save serialization format  — **Open**
**Context:** Versioned, migratable saves (`docs/SAVE_FORMAT.md`).
**Options:** (a) JSON of plain dicts via `to_dict/from_dict`; (b) Godot `Resource`
binary.
**Decision:** *Undecided.* Lean toward (a) JSON for migration-friendliness/testability.
**Blocking:** Phase 23 (Save / Load).

## D-006 — Project renamed to "Aetheria"  — **Accepted** (resolved 2026-10-02)
**Context:** `project.godot` had `config/name="New_Game_Project"`.
**Decision:** Renamed to `Aetheria` (temporary working title) so project identity matches
the docs.
**Verification:** `project.godot` now reads `config/name="Aetheria"`; the smoke test
`test_project_name_is_aetheria` asserts this at boot.
**Consequence:** done. Low risk, reversible.

## D-007 — Combat resolution model: real-time vs. turn-based  — **Open**
**Context:** Top-down combat; the damage formula is defined but the *timing model* isn't.
**Options:** (a) real-time action; (b) turn-based; (c) hybrid (ATB).
**Decision:** *Undecided — significant design question.* Must be resolved before Phase 4
(Combat) because it shapes the combat orchestration layer (not the damage math, which is
model-agnostic).
**Blocking:** Phase 09 (Combat).

## D-008 — Localization backing format: CSV vs. PO  — **Accepted** (resolved 2026-10-02, Phase 01)
**Context:** `vi`/`en` from the foundation, wrapped by a thin `Localization` service.
Phase 01 introduces the first real user-facing strings (main menu), so this had to be
resolved.
**Options:** (a) Godot CSV translations (one row per key, one column per locale, imported
to `.translation`); (b) gettext PO (one file per locale).
**Decision:** **(a) Godot CSV translations.** Rationale:
- **Diff-friendly:** one `locale/aetheria.csv` with columns `keys,en,vi` reviews cleanly
  in git; PO's per-locale files duplicate structure and are noisier to review.
- **Authoring:** a single table is easy for a bilingual author to fill; keys and both
  languages sit side by side.
- **Native support:** Godot imports CSV → `.translation` and serves it via
  `TranslationServer`; no third-party tooling.
- **Sufficiency:** our near-term needs are key→string lookup with simple
  `{placeholder}` substitution. PO's advanced plural/context machinery is not needed yet.
- **Revisit trigger:** if we later need rich plural rules or translator-tool workflows,
  reconsider PO (new ADR, don't silently swap).
**Implementation:** the `Localization` autoload wraps the backing store so call sites use
stable `tr(key)` / `tr_args(key, {...})` regardless of format; swapping CSV→PO later would
not change call sites. Missing-key behavior: return the key itself and `push_warning` in
dev (documented in `docs/TEST_PLAN.md` / `DEBUGGING.md`), never crash.
**Blocking (resolved):** Phase 01 (foundation strings) and Phase 24 (full content sweep).

## D-009 — Local headless Godot execution is unavailable to the AI agent  — **Accepted / documented limitation** (2026-10-02)
**Context:** During the Phase 0 foundation fix, the AI agent could not find or invoke a
Godot executable from the shell. Checked: PATH, common install dirs
(`%LOCALAPPDATA%\Programs`, Program Files, scoop, Downloads, itch), and the Windows
registry file association. All negative. The `.godot/` cache shows the project *was*
opened in the editor on this machine, so Godot exists but is not on the agent's PATH.
**Consequence / limitation:** the agent **cannot** run `godot --headless` locally and
therefore cannot produce a local test-run log. This is stated honestly rather than
claiming a pass that did not happen (`.kiro/steering/08-ai-review-protocol.md`:
build/run-pass is never assumed).
**Scope of this limitation (important — it is LOCAL only):** this is about the AI agent's
shell, **not** about the project being unverified. Godot *has* run against this project
for real — in CI. See D-012: the GitHub Actions job ran Godot 4.7 headless on commit
`651c16f` with `conclusion=success`. So:
- **Local AI agent:** cannot invoke a Godot binary → cannot produce a local run log.
- **GitHub Actions:** ran Godot 4.7 successfully (import + parse check + runtime boot +
  test suite). This is the authoritative verification and it has passed.
**Mitigations (now realized, not pending):**
- GDScript language server validated all scripts (zero errors/warnings) — static check.
- CI (D-012) is the authoritative headless run and has executed green on `651c16f`.
- **Manual local run** (for a developer who has Godot installed):
  `godot --headless --path . -s res://tests/run_tests.gd` — expect `RESULT: PASS`, exit 0.
**Action for maintainer:** add Godot 4.7 to PATH (or set a `GODOT` env var) if you want
the agent to run tests locally in future; otherwise CI remains the verification path.

## D-010 — Bootstrap main-scene structure (Main / Systems / World / UI)  — **Accepted** (2026-10-02)
**Context:** Phase 0 needs a real, bootable `main.tscn`. The example structure suggested
`Main → Systems / World / UI`.
**Decision:** Adopt exactly that: root `Main` (`Node2D`, script `src/bootstrap/main.gd`)
with children `Systems` (`Node`), `World` (`Node2D`), `UI` (`CanvasLayer`). It mirrors the
presentation / gameplay / world split so Phase 1 systems attach under the right branch
instead of a God node. The bootstrap script validates the structure (loud failure) and
exposes `has_required_structure()` for the smoke test.
**Consequence:** Phase 1 hangs infrastructure/system nodes under `Systems`, maps/entities
under `World`, HUD/menus under `UI`. No gameplay added.

## D-011 — Character, Relationship, Sect, Faction, World-Simulation are CORE systems  — **Accepted** (2026-10-02)
**Context:** The game is a tu tiên world where characters, sects, factions and their
politics are central, not quest-decoration NPCs.
**Decision:** Treat Character / Relationship / Sect / Faction / World-Simulation as core,
data-driven, serializable domain systems designed up front (design-only now). They are
sequenced in `ROADMAP.md` **before** NPC / Dialogue / Quest / Story, which depend on them.
New entities = data + content, no core rewrite.
**Consequence:** new design docs (`CHARACTER_SYSTEM`, `RELATIONSHIP_SYSTEM`,
`SECT_SYSTEM`, `WORLD_SIMULATION`), schema additions, flow + roadmap + multiplayer updates.
No gameplay code.

## D-012 — Minimal GitHub Actions CI  — **Accepted & verified** (2026-10-02)
**Context:** Repo had no CI. Phase 0 wants automated headless checks.
**Decision:** `.github/workflows/ci.yml` checks out, installs Godot **4.7** (matching
`project.godot` feature tag), imports the project, runs a project-wide GDScript parse
check, a runtime boot smoke (`--quit-after 2`), and the custom headless test runner —
failing the job on any non-zero exit. It does not swallow errors (no `|| true`).
**Verification (actual, not projected):** the workflow ran on commit `651c16f`. The job
"Foundation gates (Godot 4.7)" completed with `conclusion=success` (confirmed via the
GitHub check-runs API). All gates executed on real Godot 4.7:
- import — ran, no failure
- GDScript parse check (`tools/parse_check.gd`) — ran, no parse errors
- runtime boot smoke — booted `application/run/main_scene`, ran `Main._ready()`, exited clean
- headless test suite (`tests/run_tests.gd`) — ran, `RESULT: PASS`
**Status:** GitHub Actions is the automated **authoritative** verification for this
project. (The AI agent still cannot run Godot in its own shell — D-009 — but that is a
local-agent limitation, not a gap in CI verification.)

## D-013 — Document-review contradictions found during Phase 0 fix  — **Accepted / tracked** (2026-10-02)
**Context:** Mandatory cross-document review (`.kiro/steering` + `docs`).
**Findings & resolutions:**
1. **Stale "`main.tscn` is a single empty Node2D"** claims in `GAME_FLOW.md` and
   `DATA_SCHEMA.md`. → Resolved: those statuses are updated to reflect the real bootable
   `Main/Systems/World/UI` scene.
2. **D-004 "placeholder runner" language** in `TEST_PLAN.md`/`tests/README.md`. →
   Resolved: updated to the custom runner now that D-004 is Accepted.
3. **Boot/START flow** named autoloads (EventBus, GameState, …) as if they existed; none
   are implemented yet. → Clarified as *planned* (added only when first needed per
   `03-architecture.md` autoload budget). Not a contradiction, but tightened wording.
4. Glossary/terminology across save/localization/performance/testing/multiplayer is
   consistent with usage — no term-level contradiction.

**2026-10-02 (foundation hardening) — additional stale statements found & fixed:**
5. `docs/ARCHITECTURE.md` still said "Current repo has no scripts... empty `main.tscn`"
   (header Status) and "`main.tscn` ... currently an empty Node2D" (§8). → Fixed: Status
   now separates CURRENT STATE (bootstrap scene, runner, parse checker, CI exist) from
   TARGET; §8 marks existing entries `[exists]`.
6. `.kiro/steering/01-product.md` non-goals still said "project config currently enables
   a 3D physics engine ... flagged, not used" — contradicted D-002 (section removed). →
   Fixed to state the `[physics]` section was removed.
7. `docs/ROADMAP.md` Phase 0 said "met pending the first green CI run" in a way that
   implied self-verification. → Reworded: CI greenness must be read from GitHub Actions
   (agent cannot run it locally — D-009); gating moved to `PHASE_0_EXIT_CHECKLIST.md`.
**Consequence:** the earlier "no open conflicts remain" claim was premature; these were
caught in the hardening pass and fixed. The lesson is encoded in the AI review protocol's
documentation-review gate. No known stale statements remain as of 2026-10-02 hardening.

## D-014 — Kiro Hooks for test + review automation  — **Accepted** (2026-10-02)
**Context:** Phase 0 asked whether Kiro Hooks are usable and, if verified, to add hooks
for running tests after important changes and feeding results into agent context.
**Decision:** Created two hooks via the verified Kiro hook mechanism (not hand-written):
- `.kiro/hooks/run-tests-on-save.json` — **PostFileSave**, matcher `\.(gd|tscn)$|project\.godot$`,
  `command` action running `godot --headless --path . -s res://tests/run_tests.gd`. Its
  stdout/exit code return to the agent/user context after a save.
- `.kiro/hooks/ai-review-protocol-reminder.json` — **PreToolUse**, matcher
  `fs_write|str_replace|fs_append`, `agent` action injecting the review-protocol reminder.
  (Verified live: it fired on the agent's own edits during this foundation fix.)
**Known dependency / limitation:** the test hook needs a `godot` executable on PATH. On
this machine Godot is not reachable (D-009), so the hook will not actually run tests here;
it works on machines/CI where Godot is on PATH. This is documented rather than faked —
the hooks are real and valid, but their *effect* depends on the environment. CI (D-012)
remains the authoritative automated run.

## D-015 — Sect membership authoritative source of truth  — **Accepted** (2026-10-02)
**Context:** Membership is representable in two places (ambiguity risk):
`SectState.disciple_refs/elder_refs/leader_ref` (the roster) **and** `CharacterState`'s
`sect_id` / `faction_id` / `sect_rank`. Without a rule, these can drift and it's unclear
who a server would trust later.
**Decision — canonical membership lives on the SECT side:**
- **Canonical source of truth:** the `SectState` roster (`leader_ref`, `elder_refs`,
  `disciple_refs`) and, for factions, `FactionState.member_refs`. A character is a member
  of a sect iff that sect's roster references the character's `instance_id`.
- **Derived / denormalized fields:** `CharacterState.sect_id`, `faction_id`, `sect_rank`
  are a read cache for fast "which sect am I in?" lookups and view rendering. They are
  **never** the authority; on conflict, the roster wins.
- **Mutation owner:** a single domain Sect service (TARGET, not built now) is the only
  code that mutates membership. It updates the roster first, then updates the character
  cache, then emits `character_joined_sect` / `character_rank_changed` /
  `character_left_sect` on the EventBus. No other system writes membership.
- **Synchronization path:** roster change → service updates character cache → event. UI
  and other systems react to the event; they do not write membership directly.
- **Rebuild behavior:** on load, the roster is authoritative; each `CharacterState`'s
  cache is validated/rebuilt from the rosters. A cache that disagrees with the roster is
  corrected to match the roster (and a warning logged), never the reverse.
- **Serialization authority:** both are serialized (`sects` and `characters` sections,
  `docs/SAVE_FORMAT.md`), but the roster is the source; the character cache is
  reconstructable from it. If space/consistency ever matters, the cache may be dropped
  from the save and fully rebuilt on load — a later optimization, not required now.
- **Future multiplayer authority:** the server owns `SectState` (incl. rosters); clients
  receive membership as replicated/derived state and never author it. This matches the
  persistent/runtime/presentation partition in `MULTIPLAYER_PLAN.md`.
**Model:** canonical membership (sect roster) → derived character/sect views. This is the
preferred model and the review found no reason to deviate.
**Consequence:** `CHARACTER_SYSTEM.md`, `SECT_SYSTEM.md`, `RELATIONSHIP_SYSTEM.md`,
`SAVE_FORMAT.md`, and `DATA_SCHEMA.md` are annotated to point at this ADR as the single
authority rule. No runtime system is built in this step.

## D-016 — Hook strategy: lightweight on save, full suite on task completion  — **Accepted** (2026-10-02)
**Context:** `run-tests-on-save.json` ran the FULL headless Godot test suite on every
`.gd`/`.tscn`/`project.godot` save. Full-suite-per-save is costly and needless feedback
noise for small edits; it also can't do anything on this machine (no Godot — D-009).
**Decision:** split the cost by event:
- **PostFileSave** → lightweight parse check only (`tools/parse_check.gd`), fast, catches
  parse errors immediately after a save.
- **PostTaskExec** → full headless test suite (`tests/run_tests.gd`) after a spec task
  completes, where paying for the full run is justified.
Both still need Godot on PATH to actually run (D-009); where absent they no-op and CI
(D-012) remains authoritative.
**Consequence:** `run-tests-on-save.json` now runs the parse checker; a new
`run-full-tests-on-task.json` (PostTaskExec) runs the suite. No complex automation added.

## D-017 — Phase 01 Core autoloads (the singleton budget)  — **Accepted** (2026-10-02, Phase 01)
**Context:** Phase 01 needs cross-cutting runtime services. The autoload budget
(`.kiro/steering/03-architecture.md`) requires each one to be justified. Only services the
Phase-1 boot path actually needs are added now.
**Decision — 5 autoloads, each with a single responsibility:**
- **EventBus** (`src/infrastructure/event_bus.gd`) — global cross-system notification
  (signals only). Exists so emitters (SceneRouter, menu, localization) don't reference
  listeners. Not state, not logic. Needed now by the transition + language-change flow.
- **GameState** (`src/infrastructure/game_state.gd`) — the application lifecycle state
  machine + runtime session state (phase, derived session-active, run_id, current
  world/map/scene ids). Single source of truth for "where in the app are we". Separate
  from EventBus (notification) and SceneRouter (scene mechanics) because it owns
  authoritative session state, nothing else. No disk I/O: exposes `to_dict()` (run
  identity + location only — never the lifecycle phase) and `hydrate_session()`/`from_dict()`
  for a future SaveService (D-018).
- **Localization** (`src/infrastructure/localization.gd`) — key→string lookup (vi/en) +
  language switching. Separate service so call sites stay stable behind `t()`/`t_args()`
  regardless of backing format (D-008). Needed now by the main menu.
- **InputService** (`src/infrastructure/input_service.gd`) — semantic input intent +
  input-gating ownership (context stack UI_MODAL > MENU > GAMEPLAY). Separate from
  gameplay so physical-device details never leak into gameplay/UI. Needed now so the menu
  and first-scene own input correctly.
- **SceneRouter** (`src/infrastructure/scene_router.gd`) — the single scene/map transition
  entry point. Separate from GameState (it owns *how* to move, not session truth) and from
  gameplay (it does not decide *why*). Needed now for menu → first scene.
**Explicitly NOT added yet:** `Config`, `RNG`, `SaveService`. No Phase-1 use case requires
them: there is no gameplay randomness, no on-disk save, and the only config needed
(language, main scene) is already covered by Localization + `project.godot`. They will be
added by the phase that first needs them, each with its own justification — avoiding
speculative singletons (`§19`, `§25`, `§38`).
**No God object:** there is no GameManager/MasterManager; `Main` (bootstrap) only
sequences these services.

## D-018 — Phase 01 hardening: lifecycle is never persisted; semantic input context API — **Accepted** (2026-10-02, Phase 01)
**Context:** Final hardening of the Phase 01 core framework surfaced three contract-level
issues:
1. `GameState.to_dict()` persisted `session_active`, and `from_dict()` wrote both
   `session_active` and the session fields while leaving the runtime `phase` at its
   default `BOOT`. A loaded snapshot could therefore reconstruct the contradictory,
   never-legal state `phase == BOOT && session_active == true`.
2. Presentation set the input context by pushing a **raw enum int** (`reset_to(0)` /
   `reset_to(1)`), a magic number at the call site (violates
   `.kiro/steering/04-coding-standards.md`).
3. The prologue content scene read the raw input action directly
   (`event.is_action_pressed("open_menu")`), bypassing `InputService` — the owner of
   input gating / semantic vocabulary.
**Decision:**
- **Persistence (session identity only, never lifecycle).** `GameState.to_dict()`
  serializes **only run identity + location** (`run_id`, `current_world_id`,
  `current_map_id`, `current_scene_key`) and refuses to serialize when no session is
  active (returns `{}` + warns). `session_active` is **derived** (a snapshot with a
  `run_id` means a run exists), never stored. Loading is done by **`hydrate_session(data)`**
  (data-only; does **not** drive the lifecycle), which refuses an invalid snapshot (no
  `run_id`) and refuses to run from an unsafe phase (only `MENU`/`READY`), returning
  `bool`. `from_dict()` is kept as a thin alias of `hydrate_session()` and now returns
  `bool` (was `void`). The caller (future `SaveService`/load flow, Phase 23) drives the
  lifecycle to `RUNNING` via the normal transitions after hydrating. This closes the
  invalid-state hole and keeps the persistence seam presentation-free and multiplayer-safe.
- **Semantic input context API.** `InputService` exposes intent-revealing
  `set_gameplay_context()`, `set_menu_context()`, `push_modal_context()` (plus existing
  `pop_context()`); the raw stack-reset is now the private `_reset_to(ctx)`. Call sites
  pass no enum ints. Menu uses `set_menu_context()`, the first scene uses
  `set_gameplay_context()`.
- **Input ownership.** `prologue_shell` resolves the `open_menu` intent through
  `InputService.is_system_action_just_pressed(&"open_menu")` instead of reading the raw
  event — the scene never reads input vocabulary directly.
- **Boot fail-fast.** `Main` verifies required core autoloads (`GameState`, `SceneRouter`,
  `EventBus`) at `_ready()`: if the app is clearly running for real (some autoloads
  present) yet a required one is missing, it reports loudly and aborts boot rather than
  limping on with silent nulls. When **zero** autoloads exist (the headless unit-test
  harness) it proceeds on the null-safe path — that is not a misconfiguration. `_boot()`
  also checks the lifecycle transition return values.
- **EventBus scope.** Removed the speculative `new_game_requested` / `session_started` /
  `session_ended` signals (no real producer+consumer in Phase 01); kept `game_booted`,
  the three `scene_transition_*` signals, and `language_changed`.
**Consequence:** `to_dict`/`from_dict`/`hydrate_session` are the Phase-23 save seam; the
`save_version`-wrapped `SaveFile` in `docs/SAVE_FORMAT.md` will store this session block
without `session_active` and without any lifecycle phase. Public-contract change logged
here (D-005 save-format decision is still Open; this only fixes what the *producer* emits).
**Tests:** `test_game_state.gd` (persistence invariant: no phase/active flag in snapshot,
empty snapshot when no session, hydrate restores without fabricating phase, rejects
invalid snapshot + unsafe phase, `from_dict` alias), `test_input_service.gd` (semantic
setters reset the stack), `test_scene_router.gd` (failure/cleanup cases A–F),
`test_event_bus.gd` (holds no business state), and a real end-to-end
`tests/integration/test_app_flow.gd` (real autoloads + `main.tscn` + `MainMenu` signal →
RUNNING session + prologue loaded).

## D-019 — Test isolation: real-application E2E runs in its own process; Main requires all 5 autoloads — **Accepted** (2026-10-02, Phase 01)
**Context:** The D-018 end-to-end test `tests/integration/test_app_flow.gd` ran inside the
shared `tests/run_tests.gd` runner. Two facts combined into a real bug:
1. The project declares five `[autoload]` services in `project.godot`. Godot loads these
   under `/root` for **any** run, including `-s res://tests/run_tests.gd`. So the real
   `GameState` (etc.) singletons are live during the whole in-process test suite.
2. `test_app_flow.gd` additionally did `scene_tree.root.add_child(node)` with
   `name = "GameState"` (and the other four), creating **duplicate autoload nodes** (Godot
   auto-renames the second), then booted `main.tscn`. Main reads `/root/GameState` — the
   REAL autoload — and drove it to `RUNNING`, leaving it there (the test's teardown freed
   only the duplicate copies).

Consequently a later in-runner test that boots Main (the old smoke test) ran
`begin_initialization()` on a GameState already at `RUNNING`, producing
`ERROR: [gamestate] illegal transition RUNNING -> INITIALIZING` →
`ERROR: [boot] begin_initialization rejected`. CI stayed green only because the smoke test
did not assert the boot lifecycle result. This is a **test-isolation defect**, not a reason
to weaken assertions.

**Options:** (A) run the real-application E2E boot in its **own Godot process** with a
dedicated entrypoint; (B) keep it in the shared runner but reset the singletons / enforce
run-order. (B) requires a production `reset_for_tests()`-style API or order hacks that
exist only to serve tests — rejected (`.kiro/steering/03-architecture.md` anti-
over-engineering; `08-ai-review-protocol`). 

**Decision — (A), plus hardening:**
- **Dedicated E2E process.** `tests/e2e/run_app_flow.gd` (its own `SceneTree`, run as a
  separate CI gate) boots the real `main.tscn` against the ACTUAL `/root` autoloads, drives
  the real `MainMenu.new_game_pressed` intent (never GameState/SceneRouter directly), and
  asserts the full chain reaches `RUNNING` with the prologue loaded, then tears down with
  no orphan. Because nothing else runs in that process, driving the shared GameState
  contaminates nothing. It **does not spawn duplicate autoloads**.
- **No second framework.** The E2E assertions live in `tests/e2e/app_flow_case.gd`
  (`extends TestCase`, reusing the shared `assert_*` + failure recording); `run_app_flow.gd`
  is a thin adapter (inject SceneTree → run the case → exit 0/1).
- **In-runner smoke is structural only.** `tests/smoke/test_boot.gd` no longer boots Main
  into the tree (that would mutate the shared GameState). It instantiates `main.tscn`
  WITHOUT entering the tree and checks the static shell + `has_required_structure()`. The
  real boot lifecycle is the E2E process's job.
- **Cross-test contamination guard.** `tests/run_tests.gd` snapshots the shared
  `/root/GameState` phase before the suite and, after every test method, FAILS the suite if
  a test left it changed. This is detection, not reset — resetting would hide the bug. It
  makes the exact regression (a test mutating a shared singleton) impossible to pass
  silently again. `tests/e2e/` is excluded from in-runner discovery.
- **Main requires all five autoloads.** `REQUIRED_AUTOLOADS` is now
  `EventBus, GameState, Localization, InputService, SceneRouter` (was three). If ANY is
  missing when Main boots for real, boot fails loudly and stops (no fake menu, no half-boot,
  no silent fallback, no self-created autoload). The old "zero autoloads = tolerate" escape
  is removed — no in-runner test boots Main anymore, so there is no such case.
- **Main checks every required lifecycle bool.** `begin_initialization`, `mark_ready`,
  `enter_menu`, and `confirm_session_running` return values are all checked; a rejected
  `confirm_session_running` now unwinds (clear scene + end session + back to menu) instead
  of pretending to be RUNNING.

**CI:** adds a 7th gate — `godot --headless --path . -s res://tests/e2e/run_app_flow.gd` —
after the headless suite; no `|| true`, not swallowed, visible in the log.

**Consequence:** unit/integration isolation and real-application E2E are now distinct
boundaries. A successful normal run shows no `illegal transition` error. Intentional
negative-path diagnostics (invalid transition / missing scene / missing key tests) remain
and are expected. Does not change D-018 (persistence/input contract); supersedes nothing,
adds the test-architecture decision.

## D-020 — Phase 02 Player: composition entity, data-driven stats, domain damage slice, sandbox first-scene — **Accepted** (2026-10-02, Phase 02)
**Context:** Phase 02 builds a playable Player (movement + take/return damage vs a dummy)
without starting Phase 03+ (no Character/Combat/AI/networking) and without forcing a
Phase-04 rewrite. Several shape decisions were needed up front.
**Decision:**
- **Player = `CharacterBody2D` + components, never inheritance.** `StatsComponent`,
  `HealthComponent`, `MovementComponent` under `src/gameplay/components/`; the entity under
  `src/gameplay/entities/`. The Training Dummy reuses the SAME StatsComponent +
  HealthComponent (composition proof). `player.gd` is a thin coordinator (reads intent,
  forwards to movement, initializes health from stats, exposes an attack *intent*) — it
  owns no damage math, no max-HP calc, no inventory/quest/save, and reads no raw input
  (`docs/ARCHITECTURE.md` §3, `docs/CHARACTER_SYSTEM.md` §6).
- **Stats are DATA.** A `StatBlock` Resource (`src/data/stats/stat_block.gd`) holds the
  Phase-02 subset (`max_hp`, `attack`, `defense`, `move_speed`) with the field names from
  `docs/DATA_SCHEMA.md` §1 (so Phase 04/combat/equipment reuse the same shape). Authored
  numbers live in `data/stats/*.tres`, never in scripts (`04-coding-standards.md`). Only
  the fields with a real Phase-02 use are included (no speculative mana/resist/crit).
- **Damage math is ONE pure domain function.** `src/domain/combat/damage_rules.gd`
  (`DamageRules.compute_hit`) implements a MINIMAL, deterministic slice of the single
  `DATA_SCHEMA.md` §2 formula (`final = max(1, round(attack * scale/(scale+defense)))`),
  with no RNG/crit/resist/skill/equipment and no node deps (headless-testable). This is
  **not** a combat system and is model-agnostic, so it does not resolve the combat-timing
  model — **D-007 stays Open**. The `RNG` autoload remains deferred (D-017).
- **Health invariants + intent-revealing API.** `apply_damage`/`heal` return the amount
  actually applied, clamp to `[0,max]`, reject non-positive input, emit `died` exactly once
  **per life** (an `initialize()` begins a new life, so a reused entity such as the Training
  Dummy via `reset_dummy()` can die again — see the Phase-02 hardening entry in
  `docs/CHANGELOG.md`), and treat DEAD as terminal within a life (no revive-by-heal). Local
  signals go direct to the owner, not the EventBus; **no speculative EventBus combat signals
  were added** (L-005) — combat broadcast events are a Phase-09 concern with real consumers.
- **Movement intent boundary (MP seam).** `MovementComponent.apply_intent(intent, speed,
  _delta)` takes a direction vector so a future network command can feed the same boundary
  (`docs/MULTIPLAYER_PLAN.md` §2/§3); `_delta` is part of the contract but intentionally
  unused (`move_and_slide` owns the physics-step integration). Diagonals are normalized (not
  faster than cardinal); motion uses `move_and_slide` (collision-aware, never `position +=`).
  Player polls `InputService` semantic intent in `_physics_process` — the only input path.
- **First gameplay scene = Player Sandbox (temporary).** New Game now routes
  (`FIRST_SCENE_KEY` in `main.gd`) to `player_sandbox` instead of the prologue shell. This
  is explicitly a Phase-02 gameplay-VALIDATION scene (move + attack a dummy), NOT a story
  system; Phase 03 (World/Map) replaces it as the real first scene — a one-line change
  because it is a single registered `scene_key` through SceneRouter (D-003 stays Open). The
  prologue shell is retained but no longer the first scene. The sandbox COORDINATOR owns the
  demo interaction (range check + who-hits-whom) and resolves damage via the domain rule;
  presentation decides no outcomes (`docs/MULTIPLAYER_PLAN.md` §4).
- **Collision layers are named constants** (`src/gameplay/collision_layers.gd`), the single
  source of truth. The entity/wall scenes carry **no** `collision_layer`/`collision_mask`
  numbers; each entity sets them from the constants in `_ready()` (Player = PLAYER + mask
  WORLD|DUMMY; Dummy = DUMMY, mask 0; sandbox walls = WORLD, mask 0). An integration test
  asserts the runtime wiring matches the constants so the two can't drift.
**Testing / isolation (D-019):** unit tests (damage rule, health invariants, movement math,
stat validation) and integration tests (player wiring + real-physics move + bidirectional
damage exchange) use **fresh instances**, never the live autoloads, and never boot Main.
The sandbox gameplay smoke test is **structural-only** (instantiated but not entered) so it
doesn't mutate the shared InputService. The REAL player flow (New Game → sandbox → move →
attack → death → cleanup) runs in its own isolated process (`tests/e2e/run_player_flow.gd`),
added as a dedicated CI gate.
**Consequence:** the player composition + `StatBlock` + domain damage slice are the seams
Phase 04 (Character) and Phase 09 (Combat) build on without a rewrite. No new autoloads;
D-005/D-007 remain Open (D-003 resolved in Phase 03 — see below).

## D-021 — Phase 03 World/Map: WorldRuntime node, `scene_key`-addressed maps, persistent player — **Accepted** (2026-10-02, Phase 03)
**Context:** Phase 03 (World / Map) implements traversable maps and resolves D-003. It must
add ≥2 maps the player moves between repeatedly with no leak, keep the autoload budget
(D-017: 5), keep maps data-driven (new map = data + content scene, no core edit), and not
drift into World Simulation (that is Phase 08).
**Decisions:**
- **D-003 → option (a):** one `PackedScene` per map, swapped by the existing `SceneRouter`
  (the single transition entry point). No streaming.
- **`WorldRuntime` is a NODE, not an autoload.** It hangs under `Main/Systems` and owns the
  *why/when* of map movement + the per-session player lifecycle; `SceneRouter` keeps the
  *how* of swapping content, and `GameState` keeps the authoritative *where*
  (`set_current_location`, fed by the router). Rejected a 6th autoload — the budget stays
  frozen at EventBus/GameState/Localization/InputService/SceneRouter.
- **`MapData.scene_key: String` (not `scene: PackedScene`).** The DATA_SCHEMA sketch listed
  a direct `PackedScene` ref; instead a map carries a stable router `scene_key`, keeping
  `MapData` a pure data resource and SceneRouter authoritative for loading. DATA_SCHEMA
  synced. *(The initial Phase-03 MapData was `scene_key` + `exits{to_map_id, entry_point}`;
  the Phase-03 reopen D-022 made MapData the full source of truth — adding `scene_path`,
  `bounds`, `default_spawn_id`, exit `id`s, and a `MapCatalog`. See D-022.)*
- **Persistent per-session Player owned by WorldRuntime.** The player is parented under
  WorldRuntime between maps (so a SceneRouter content-swap can't free it) and re-parented
  into each map's `PlayerHost` at a named spawn marker on arrival. The map is detached from
  the player *before* the router frees the old scene (no accidental free, no stale signal
  connection).
- **No new EventBus signal.** `map_entered`/`map_exited` are deferred to the Quest/Story
  phases that will actually consume them (L-005: no speculative signal). Current state is
  read via `scene_transition_completed` + `GameState.get_current_map_id()`.
- **Prototype map art.** *(Initially self-made vector placeholders. The Phase-03 reopen
  D-022 replaced them with real self-made prototype PNG textures + a prototype `TileSet` +
  a `Sprite2D` player; base tile size is now 16px. See D-022 + `ASSET_LICENSES.md`.)* The
  Phase-02 sandbox + Phase-01 prologue are retained in the repo but are no longer the first
  scene; New Game now enters the hub map via WorldRuntime.
**Consequence:** a new map is `MapData` + a content scene registered in WorldRuntime's
catalog — no core edit (extensibility rule holds). Multiplayer seam stays clean (map/world
state has no presentation coupling). Verified by a 9th CI gate: `tests/e2e/run_world_flow.gd`
drives the real New Game → hub → interact → field → back → menu flow with a no-orphan-leak
assertion. No new autoloads. **Superseded in part by D-022 (Phase-03 reopen hardening).**

## D-022 — Phase 03 reopen: MapData is the full source of truth; data-driven catalog; transactional transitions; real prototype art — **Accepted** (2026-10-03, Phase 03 hardening)
**Context:** Phase 03 passed CI but was closed earlier than its acceptance contract (D-021
left several seams half-done). The reopen hardens them so CODE + TESTS + CI + DOCS + ART all
agree before CLOSED. No Phase-04 (Character) work is done here.
**Decisions:**
- **MapData is AUTHORITATIVE, not a thin key holder.** It gains `scene_path` (the one place
  the map↔scene binding is authored), `bounds: Rect2` (playable area; camera limits derive
  from it), `default_spawn_id`, and `exits` with stable `id`s. Validation checks all fields
  + `ResourceLoader.exists(scene_path)` + positive bounds + unique exit ids.
- **`MapCatalog` resource (`src/data/maps/map_catalog.gd` + `data/maps/map_catalog.tres`) is
  the data-driven map list.** It validates unique map ids / scene_keys and that every exit
  `to_map_id` resolves within the catalog (no dangling edges). `WorldRuntime` holds ONLY
  `MAP_CATALOG_PATH`; it loads + validates the catalog and registers `scene_key -> scene_path`
  with SceneRouter. **Adding a 3rd map = author data + scene + add to catalog, no WorldRuntime
  edit** (verified by test; the old hard-coded `MAP_CATALOG` array is gone).
- **MapExit is the authoritative destination; `MapExitZone` carries only `exit_id`.** The
  scene no longer duplicates `to_map_id`/`entry_point` (that caused identity drift). MapBase
  resolves `exit_id -> MapExit` and emits `exit_requested` from the data. A structural test
  fails on any zone whose `exit_id` doesn't resolve.
- **Camera limits are data-driven** from `MapData.bounds` via `MapBase.apply_map_data` (set
  by WorldRuntime on arrival); not duplicated per scene. Tested: each map's limits == bounds,
  and the limits update on transition.
- **Spawn contract fails loud.** Empty `entry_point` → `default_spawn_id`; an *explicit*
  `entry_point` that doesn't exist is a content bug and is reported loudly — NO silent
  fallback to default. Tested (structure + cross-map entry-point existence).
- **Transactional map transition.** `WorldRuntime._enter_map` snapshots the player's
  parent + position, parks the player, calls the router; on router failure it ROLLS BACK
  (player restored to the still-alive old map, active map / GameState unchanged, router not
  left transitioning), on success the old scene is freed and the SAME player instance is
  placed at the new spawn. The router-level invariant it relies on (a rejected transition
  leaves the current scene intact) is a permanent integration test.
- **Real prototype art (replaces Polygon2D placeholders).** Self-made, project-owned PNGs
  generated by `tools/gen_prototype_assets.py` (pure-Python, runtime-independent):
  `assets/sprites/characters/player_proto.png` (16×24) and
  `assets/tiles/prototype/prototype_tileset.png` (48×16, grass/path/wall). Player `Visual`
  is a `Sprite2D`; maps render a `TileMapLayer` (`PrototypeGround`) using
  `data/maps/prototype_tileset.tres`. **Base tile size = 16px**, nearest filter, mipmaps off
  (`06-art-assets.md`). Static wall collision unchanged. Recorded in `ASSET_LICENSES.md`.
- **E2E through the REAL input pipeline.** `tests/e2e/world_flow_case.gd` drives interact /
  open_menu via `Input.parse_input_event` real key events (never a direct `_unhandled_input`
  call), does a real semantic movement step, and runs **20 round trips** asserting per-round:
  map changed, SAME player instance id, exactly one Player, player in active map, one content
  scene, GameState map id == router, router not stuck — plus no orphan-node growth. The only
  headless concession is emitting the exit sensor's own `body_entered` signal (L-016/L-017).
**Consequence:** the map system is genuinely data-driven and extensible, transitions are
safe under failure, the player provably persists, and the maps render real textures. Verified
by the unit/integration/gameplay suites + the dedicated world E2E gate. Partially supersedes
D-021's data-model + art bullets. No new autoloads; D-005/D-007 remain Open.

## D-023 — Phase 04 Character core: CharacterState is authoritative; Player is a view; data-driven start map; early UI/HUD foundation — **Accepted** (2026-10-02, Phase 04)

**Context:** Phase 04 makes Character a real CORE system (D-011) — the player becomes a
Character — and lays the first UI/presentation foundation (theme, menu pass, in-map HUD,
input display labels, camera framing). No Relationship/Sect/Faction/WorldSim/Combat/Inventory/
Skill/Quest/Dialogue/Save/Networking is implemented; cultivation fields are CONTRACT only.
**Decisions:**
- **`CharacterState` (`src/domain/character/character_state.gd`, `RefCounted`) is the single
  AUTHORITATIVE, serializable, presentation-free character instance** (`docs/CHARACTER_SYSTEM.md`
  §3/§6). The player's identity + current stats + current HP + life-state live HERE, not in
  the Player node. The node is a runtime VIEW bound to the state. Domain has NO Node/scene/
  presentation dependency.
- **`CharacterTemplateData` (`src/data/characters/character_template_data.gd`, Resource,
  `char_*`) is the DATA definition** a state is built from; the player's is authored as
  `data/characters/player_default.tres`. All display text is localization keys; stats are a
  shared `StatBlock`. Validated at the content boundary. Adding a character = author a `.tres`.
- **One source of truth binding.** `WorldRuntime` builds exactly ONE player `CharacterState`
  from the template at session start (fixed `instance_id = "player"`) and binds it to the
  persistent Player BEFORE the node enters the tree. `StatsComponent` reads its numbers from
  the bound state (falls back to the authored `StatBlock` only when no state is bound, e.g.
  the Training Dummy / isolated tests). `HealthComponent` stays the RUNTIME health view; the
  Player mediates sync: HP changes → `state.set_current_hp`, death → `state.mark_dead()`.
  Composition is kept (no inheritance). The state is NOT recreated on a map swap — the same
  instance persists for the whole session (E2E-asserted over 20 round trips).
- **Life-state machine.** `LifeState { ALIVE, DEAD, MISSING, ASCENDED }`. Phase 04 implements
  ALIVE→DEAD exactly once; DEAD is terminal (no UI/gameplay revive); `death_cause` is set only
  on a valid transition. MISSING/ASCENDED are contract values for later phases.
- **Serialization is persistent-tier only.** `to_dict`/`from_dict` round-trip identity + data
  (incl. `current_hp` and `life_state`) and NEVER a Node/position/scene/presentation field
  (L-001). `from_dict` validates the snapshot and fails closed on an impossible one. This is a
  SAVE SEAM; `SaveService` is still Phase 23 (not built here).
- **Data-driven start map (completes D-022).** `MapCatalog` gains `start_map_id` (validated to
  resolve to a real map). `WorldRuntime` reads it from the catalog; the hard-coded
  `START_MAP_ID := &"map_hub"` constant is removed. Changing the start map is now a content
  edit.
- **Early UI/presentation foundation.** `UIPalette` (design tokens, single source of truth) +
  `UITheme.build()` (code-built shared `Theme`, matching the project's code-built-UI
  convention and unit-testable) style the menu + HUD. The main menu gets a presentation pass
  (background, title/subtitle, uniform styled buttons, focus) with its signals/localization/
  context behaviour UNCHANGED. A new `GameplayHUD` (presentation-only, owned by MapBase)
  renders the character's name/title (from the authoritative state), the localized map name,
  and control hints. **Input display labels** come from a new `InputService.get_action_display_label`
  (resolves the real binding, e.g. interact→"E", open_menu→"Esc"); the UI never reads physical
  keycodes (L-003). Camera uses a shared data-driven zoom baseline (2× for 16px tiles); exit
  zones show a clearer jade prototype gate instead of the yellow debug block.
**Consequence:** the player is a real Character with one authoritative, serializable,
save-ready state; stats/health have a single owner; the UI has a consistent foundation and
never hard-codes keys or user text. Verified by character unit tests (template/state/life-state/
round-trip), a player↔state binding integration test, UI structural tests, and the extended
world E2E (same CharacterState across 20 round trips). No new autoloads (WorldRuntime still
owns the state as a node member). D-005 (save format) / D-007 (combat) remain Open.

## D-024 — Phase 04 UI hardening: asset-backed pixel-art UI; self-made CC0 set (itch.io blocked); resource-warning finding — **Accepted** (2026-10-02, Phase 04 reopen)

**Context:** Phase 04's first UI pass was engine-prototype (ColorRect/Label/Button +
programmatic `StyleBoxFlat`). The reopen hardens presentation to a game-prototype look using
REAL pixel-art UI textures (9-slice framed panels, per-state buttons, graphic key badges,
title treatment, framed HUD). No character architecture change; no Relationship/Sect/Faction/
WorldSim/Combat/Inventory/Quest/Dialogue/Save/Networking.
**Decisions:**
- **Asset source — self-made CC0 set, because the preferred external pack is not
  auto-downloadable here.** The intended pack is tiopalada "Tiny RPG - Mana Soul GUI" (CC0,
  https://tiopalada.itch.io/tiny-rpg-mana-soul-gui), but itch.io returns **HTTP 403** to
  automated fetch and the download sits behind a JS button with no stable binary URL. Per
  `06-art-assets.md` provenance + the Phase-04 brief, faking a download, screenshotting, or
  pulling from an unverified mirror is forbidden. So the UI textures are **project-owned,
  self-made** pixel art generated by `tools/gen_ui_assets.py` (pure-stdlib PNG writer, no
  download, no third-party lib — same proven approach as the Phase-03 prototype art, D-022).
  They live under `assets/ui/mana_soul/` and are PROTOTYPE art; a later pass can drop in the
  itch.io pack (or original art) by replacing the files in `UIPalette.UI_ASSET_DIR`.
- **UI is asset-backed through ONE theme + tokens.** `UIPalette` holds the texture paths +
  9-slice margins (single source of truth); `UITheme.build()` produces a `Theme` whose Button
  states, PanelContainer panel, and key-badge are `StyleBoxTexture` with the authored 9-slice
  `texture_margin` (corners never stretch → crisp at any size). Each builder falls back to a
  flat `StyleBoxFlat` if a texture is missing, so the UI degrades instead of crashing; an
  asset-contract test guards that the real textures exist. MainMenu + GameplayHUD share this
  one visual language; reusable `src/presentation/ui/components/` pieces (`UIKeyBadge`,
  `UIPromptRow`) are added only where used ≥2 places.
- **Key prompts are graphic badges.** The HUD shows `[E] Interact` / `[Esc] Menu` via
  `UIKeyBadge` (a framed keycap chip), fed by `InputService.get_action_display_label` — never
  a raw action name or "Press E" text (L-003). InputService stays the single owner of
  key→label mapping.
- **UI owns no gameplay truth** (unchanged boundary): it renders state + emits intents; it
  never mutates `CharacterState`, HP, or calls `SceneRouter` (verified by grep + a test).
- **Resource-in-use warning — partially root-caused here; the rest closed in D-025.** The
  earlier RED-run leak (`9 resources still in use` + `GodotBody2D`/`GodotShape2D`/
  `DummyTexture`) WAS a side effect of the `default_goals` crash (D-023 fix): the character
  integration tests aborted mid-method, so their `free_node(player)` never ran. That part
  cleared on the green run. **However, a SMALLER independent leak survived the green runs**
  (`5 ObjectDB instances leaked` + `1 resource still in use`) and this bullet's assumption
  that a green run is leak-free was wrong — see D-025, which root-caused it to three un-freed
  `InputService` Nodes in a Phase-04 test and fixed it. Assertions were NOT lowered to hide
  it (the finding here held: investigate, don't suppress).
**Consequence:** the menu and HUD read as a framed pixel-art game UI (not default Godot
controls), buttons have distinct states, key prompts are graphic, and corners stay crisp on
resize. Verified by the presentation unit/structural tests + the asset-contract test + the
unchanged app/player/world E2E gates. Self-made assets recorded in `docs/ASSET_LICENSES.md`.
No new autoloads; Character core unchanged; D-005/D-007 remain Open.

---

## D-025 — Phase 04 close-out: residual test-exit leak root-caused + fixed; ROADMAP/DECISIONS drift corrected — **Accepted** (2026-10-03, Phase 04 close-out)

**Context:** Phase 04 (D-023 core + D-024 UI) was CI-green on `7615d88`, but two residuals
blocked a clean CLOSE: (1) the green headless-suite process still printed
`WARNING: 5 ObjectDB instances were leaked at exit` + `ERROR: 1 resources still in use at
exit` at shutdown, and (2) `docs/ROADMAP.md` still said Phase 04 was `IN PROGRESS`. No new
gameplay, UI, Character, Save, Combat, Quest, Dialogue, networking, or Relationship/Sect/
Faction/WorldSim work was done — close-out only.

**Decisions:**
- **Root-cause by evidence, not assumption (steering 10).** The leak lines are a non-fatal
  Godot shutdown WARNING/ERROR (the suite still exits 0), and the GitHub API logs endpoint
  needs auth, so a ONE-TIME CI diagnostic re-ran the suite with `--verbose` and surfaced the
  leak reporter's per-instance dump as `::error::` annotations (auth-free) on commit `906e4ef`.
  The dump named: 3× `Node` (empty node path = never entered the tree), 1× `GDScript`
  (`res://src/infrastructure/input_service.gd`, refcount 3), 1× `GDScriptNativeClass`
  (refcount 1); the "1 resource still in use" is that same GDScript.
- **Single root cause.** `tests/unit/core/test_input_display_label.gd` (added in D-023) created
  a fresh `InputService` via `.new()` in each of its 3 methods and never freed it. `InputService`
  extends `Node` (manual memory), so an un-added, un-`free()`d local leaks until the process
  dies; each live Node pinned the script (refcount 3) which pinned its native class (refcount 1).
  3 Nodes + 1 GDScript + 1 GDScriptNativeClass = the 5 ObjectDB; the GDScript = the 1 resource.
  The sibling `test_input_service.gd` freed its instances; the newer test simply forgot. Fixed by
  `svc.free()` in all three methods (matching the sibling). No production code changed, no
  assertion lowered, no teardown removed, D-019 isolation untouched. Diagnostic step then removed
  (CI back to the clean 9 gates). Lesson **L-019** added (unfreed Node in the `-s` runner leaks
  silently; a clean suite ends with 0 ObjectDB leaked / 0 resources in use).
- **No brittle regression test.** A "0 ObjectDB leaked" assertion inside the shared runner would
  be flaky (the 5 live project autoloads under `/root` make absolute object counts
  nondeterministic, and the runner can't fail on a shutdown-time leak). The fix + L-019 are the
  durable guard (`05-performance-testing.md` "no test for count's sake").
- **Doc drift corrected (L-014).** ROADMAP Phase 04 → CLOSED with evidence; the D-024
  "resource-in-use" bullet corrected (it wrongly implied a green run was leak-free — the smaller
  5-ObjectDB leak survived the green runs until this fix).

**Consequence:** the headless suite now exits with 0 ObjectDB leaked / 0 resources in use;
Phase 04 is CLOSED (CI-verified); docs match reality. No new autoloads; Character core + UI
unchanged; D-005 (save) / D-007 (combat) remain Open; Phase 05 (Relationship) NOT STARTED.

---

## How to add a decision
Append `D-00N — <title> — <status> (date)` with Context / Options / Decision /
Consequence (or Blocking). Never silently change a shipped decision — mark the old one
**Superseded** and add a new entry.
