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

## D-026 — Phase 05 Relationship core (domain graph) + early character visual pipeline + narrative anchor — **Accepted** (2026-10-03, Phase 05)

**Context:** Phase 05 makes Relationship a real CORE domain system (D-011) and, in parallel,
starts the character VISUAL pipeline so the game stops being programmer-art-only. It also lays
a narrative anchor so later story systems build toward one coherent direction. No
NPC/Dialogue/Quest/Story/Sect/Faction/WorldSim/Combat/Inventory/Save/networking; no new
autoload; the existing flow (Menu → New Game → Hub ↔ Field → Menu) and first scene are
unchanged.

**Decisions:**
- **Relationships are a domain graph with a single source of truth** (`RELATIONSHIP_SYSTEM.md`
  §1): `RelationshipStore` owns all edges; `CharacterState` is NOT given a relationship
  dictionary. Endpoints are TYPED `{ kind, id }` (`RelationshipEndpoint`: CHARACTER | SECT), so
  a character and a sect can never be confused by a shared raw id.
- **Data-driven dimensions.** `RelationshipConfigData` (`data/relationship/relationship_config.tres`)
  owns per-dimension default/min/max + history capacity (affinity/debt −100..100,
  trust/respect/fear/rivalry 0..100). No range is a magic number in the service — it reads the
  config. Adding/retuning a dimension is a data edit.
- **One mutation path.** `RelationshipService.apply_delta/apply_event/create_edge/remove_edge`
  is the ONLY way state changes: it validates, clamps to config range, writes bounded history
  on a REAL change, and emits a DOMAIN signal `relationship_changed(edge_id, dimension, old,
  new, cause)` (NOT an EventBus signal — domain stays presentation/infra-free). A zero-effect
  delta is a no-op; a missing edge fails loud (no implicit create). No caller mutates an edge's
  dict directly.
- **Symmetric canonicalization + signed-debt perspective.** A symmetric edge is stored in
  canonical endpoint order (smaller `(kind,id)` is `from`), so `A-B`/`B-A` resolve to ONE edge
  and a duplicate symmetric create is rejected. `debt` is stored from the canonical-from
  perspective; a reverse query negates ONLY debt (the non-directional dimensions are never
  flipped). Directed edges read as stored.
- **Deterministic event→delta.** `RelationshipRuleData` + `RelationshipRuleCatalog`
  (`data/relationship/relationship_rules.tres`) map `event_kind → { dimension: delta }` with an
  optional relationship_type gate — data, not a DSL, no RNG, no global mutable state. The same
  event on the same start state is reproducible.
- **Serializable, multiplayer-clean seam.** `RelationshipStore.to_dict/hydrate` round-trips the
  whole graph deterministically (sorted by edge id), validates at the boundary and FAILS CLOSED
  (never asserts) on a malformed snapshot, and rebuilds indexes. This is the save seam
  (`SaveService` is Phase 23) and the Stage-2 authoritative-state seam (`MULTIPLAYER_PLAN.md`).
- **Runtime ownership = a node under Main/Systems, NOT an autoload.** `RelationshipRuntime`
  (sibling of `WorldRuntime`) owns the store+service+config for the session and survives map
  swaps (SceneRouter only swaps content under `Main/World`). The autoload budget (D-017) is
  unchanged; `WorldRuntime` stays the map/player coordinator (no God object).
- **Referential integrity deferred to Phase 06.** SECT endpoints are structurally supported but
  NOT validated against a real `SectState` (there isn't one yet). No fake SectState is created.
- **Character visual pipeline is presentation-only + data-driven.** `CharacterVisualProfileData`
  (referenced by the existing `CharacterTemplateData.sprite_set_ref` — a presentation ref NOT
  copied into `CharacterState`) + a `CharacterVisualComponent` that reads movement facing and
  renders a 4-direction sheet (nearest filter, anchored at the feet; `CHARACTER_ART_BIBLE.md`).
  `MovementComponent` stays the movement authority; the visual never mutates domain state. Four
  self-made CC0-equivalent prototype archetype sheets (player/female cultivator/elder/merchant,
  `tools/gen_prototype_assets.py`), a preview scene that is NOT the first scene, and the player
  wired to its `sprite_set_ref`. A missing/invalid profile fails loud and keeps the static
  fallback sprite.
- **Narrative anchor only.** `docs/NARRATIVE_DIRECTION.md` + `docs/CHARACTER_ART_BIBLE.md` are
  design documents — no story/dialogue/quest engine; all content original to Aetheria.

**Consequence:** relationships are a tested, serializable, deterministic domain graph behind one
mutation path and one domain signal, ready for NPC/Dialogue/Quest/Sect/WorldSim/UI/MP to consume;
the character visual pipeline turns a template's `sprite_set_ref` into an on-screen sprite with no
domain leak; the game flow and autoload budget are unchanged. D-005 (save) / D-007 (combat) remain
Open; Phase 06 (Sect) adds the real `SectState` + relationship referential validation.

---

## D-029 — Visual follow-up: production-foundation art for the currently-visible playable flow (world tileset + props + character), self-made in-place — **Accepted** (2026-10-03, visual follow-up to D-028)

**Context:** D-028 upgraded the UI to the CC0 Xianxia Pixel Pack, but the actual playable
flow (Menu → New Game → Hub ↔ Field) still rendered the FIRST flat prototype art: plain green
grass, a tan path strip, grey brick walls, and a tiny flat figure. The task was to start
upgrading the on-screen WORLD and CHARACTER *now*, by incremental replacement, without any
gameplay/domain/data/architecture change and without importing side-scroller art into the
top-down world.

**Options:** (a) import the Xianxia Pixel Pack characters/terrain — REJECTED: that pack is a
side-scroller set (characters/terrain not top-down, not the 16px art bible — `06-art-assets.md`);
(b) import the Verdant 00 top-down CC0 tileset — DEFERRED: a 47-mask autotile set (~878 tiles)
is heavy to wire and risks a style clash/collage with the self-made character;
(c) **redraw the project's own self-made tileset + character + add props** via the existing
`tools/gen_prototype_assets.py`, keeping the same files/dimensions/seams — CHOSEN.

**Decision:**
- **In-place art swap, no seam change.** The tileset stays the same 48×16 three-column strip
  (0=grass, 1=path, 2=wall), same `prototype_tileset.tres`, same `prototype_ground.gd`; the
  player sprite stays a single 16×24 frame used by `player.tscn`'s `Visual` `Sprite2D`; the
  idle sheets stay 64×24 (4× 16×24). So the TileSet resource, ground script, map scenes,
  `MapData`, camera bounds, wall collision, exit zones, and every test contract are UNCHANGED —
  this is a pure presentation upgrade.
- **Production-foundation tier.** Tiles get layered shading + a soft ordered (Bayer) dither so a
  tiled field no longer reads as one flat colour (mossy jade grass / warm flagstone path /
  blue-grey roof-tile wall). The character gets a full dark outline, shaded head/jaw, hair sheen,
  robe hem + a per-archetype sash accent, shaded arms, and a foot contact shadow.
- **One drawing routine for the character.** The in-game single frame (`gen_player`) now reuses
  the SAME `_draw_character_frame` as the 4-direction idle sheets (DOWN facing, player palette),
  so the sprite the player sees and the preview sheets are one coherent character — no second,
  flatter copy (`04-coding-standards`: no duplicated drawing logic). This closed the gap where
  the earlier pass had only upgraded the idle sheets, not the frame `player.tscn` actually uses.
- **Props are presentation-only decorations.** Four NEW self-made Chinese garden-courtyard props
  (lantern 16×24, tree 32×32, rock 16×16, planter 16×16) are placed as `Sprite2D` nodes under a
  new `Visual/Decor` child in `hub_map.tscn` / `field_map.tscn`, positioned in open grass away
  from the player corridor and the exit zones, within the camera bounds. They add NO collision,
  NO exit, NO spawn, NO camera, NO MapData and NO gameplay behaviour. `Visual/Ground` remains the
  first child of `Visual`, so the structural map test's node-path lookups keep resolving.
- **Still self-made / project-owned.** No external pack was imported; the palette stays coherent
  world↔character and the assets remain swappable later by a bespoke art pass. Recorded in
  `docs/ASSET_LICENSES.md` (P1/P2 + P14–P17 redrawn; P18–P21 new props).

**Consequence:** the visible playable flow now reads as a coherent production-foundation wuxia
courtyard (shaded tiles + garden props) with a shaded, outlined cultivator, while every gameplay
seam, camera bound, exit contract and test stays byte-for-byte in behaviour. This is a visual tier
step (prototype → production foundation), NOT Phase 06. D-005 (save) / D-007 (combat) remain Open.

---

## D-030 — Phase 05 close-out + visual-foundation hardening: documentation drift reconciled, Continuous Visual Integration adopted, D-029 visual contracts tested, one small UI polish — **Accepted** (2026-10-03, close-out; not a phase)

**Context:** After the D-027/D-028/D-029 visual follow-ups, several docs still described an
older state (UI as self-made prototype with Mana Soul as the "intended upgrade"; world art as a
flat prototype; ROADMAP Phase 05 "7 gates" while CI has 9; Phase 25 titled plainly "UI" implying
production UI starts there). The D-029 decorative-prop contract had no automated guard, and the
UI had not had a dedicated polish pass since the asset swap. This close-out hardens all of that
WITHOUT starting Phase 06 or changing any gameplay/domain behaviour.

**Decisions:**
- **Documentation reconciled to the real current state.** ROADMAP: Phase 05 now reads *all 9
  gates green* (matching `ci.yml`), and Phase 25 is renamed **"UI Consolidation / Production
  Polish"** — explicitly a final consolidation/polish pass, NOT where production UI begins (and
  NOT a rescue rewrite). `06-art-assets.md`, `ARCHITECTURE.md` and `GAME_FLOW.md` now state: UI =
  CC0 Xianxia Pixel Pack live (D-028, superseding the retired self-made `mana_soul` prototype;
  Mana Soul is no longer an "intended upgrade"), world/character art = **production-foundation**
  (D-029, not flat prototype, not final), Relationship core CLOSED (Phase 05), player visual =
  presentation-only, `CharacterState` = domain-only, Phase 06 NOT STARTED.
- **Continuous Visual Integration is now binding policy** (`docs/ROADMAP.md`): visuals grow
  incrementally; each feature phase owns the first usable visual treatment of its own feature;
  no placeholder chains; replace by asset/component/theme layer (via the `UITheme`/`UIPalette`
  seam) rather than rewriting; a visual swap never changes gameplay/domain truth; assets are
  chosen per domain (no single giant pack forced on the whole game, no collage). Phase 25 is the
  consolidation/polish endpoint, not a rescue.
- **D-029 visual contracts guarded by tests.** `tests/gameplay/test_map_scenes.gd` now asserts
  each map has a `Visual/Decor` with ≥1 nearest-filtered `Sprite2D` whose texture is a known prop
  at its authored pixel size (lantern 16×24, tree 32×32, rock/planter 16×16), that `Visual/Ground`
  is still the first child of `Visual`, and that the ground `TileMapLayer` is nearest-filtered.
  Character-side contracts (16×24, nearest, feet-anchor, 4-direction, no presentation leak) were
  already covered by `test_character_visual.gd`.
- **One small UI polish pass, seam-only.** Through `UIPalette`/`UITheme` only (no new screen, no
  gameplay, no architecture change): added a restrained muted-gold `COLOR_TITLE` token for the
  menu title plaque (clear warm step above body/subtitle, tu-tiên seal tone), tightened the type
  scale into a cleaner three-step hierarchy (subtitle 18→20, hint 15→14), and evened button
  vertical padding (10→12). `title > body` and all other UI-theme invariants stay green.

**Consequence:** the docs/steering no longer contradict the shipped visual state, the visual
foundation policy is explicit for every future phase, the D-029 look is regression-guarded, and
the live UI reads a step more intentionally as a tu-tiên interface. No gameplay/domain change, no
new autoload, no new system; Phase 06 (Sect) remains NOT STARTED. D-005 (save) / D-007 (combat)
remain Open.

---

## D-032 — Phase 06 Sect System: roster-authoritative domain, single mutation path, transactional relationship mirror, SectRuntime (no autoload), data-driven content + localized Xianxia UI — **Accepted** (2026-10-03, Phase 06)

**Context:** Phase 06 makes Tông môn (Sect) a real CORE domain system (D-011) built ON the
Phase-05 relationship graph, with usable UI in the same phase (Continuous Visual Integration,
D-030). Scope guard: NO Faction/Politics engine (Phase 07), World Simulation (Phase 08), Combat,
NPC/Dialogue/Quest/Story, Inventory, SaveService, or networking; NO new autoload; the runnable
flow (Menu → New Game → Hub ↔ Field → Menu) is unchanged.

**Decisions:**
- **Layering = DATA → DOMAIN → GAMEPLAY RUNTIME → PRESENTATION.** `SectTemplateData` +
  `SectRankData` + `SectCatalog` (data); `SectState`/`SectStore`/`SectService` (domain,
  presentation-free, serializable); `SectRuntime` (a node under `Main/Systems`); the HUD chip +
  `SectPanel` (presentation, read a `SectMembershipView` DTO). UI holds NO sect truth; a scene
  node is never the SectState; `CharacterState` holds NO copy of the sect.
- **The roster is the single source of truth (D-015).** `SectState` owns leader/elders/
  disciples + `rank_by_character`. `CharacterState.sect_id`/`sect_rank` are a DERIVED cache the
  `SectService` writes on join/leave/rank; `sync_character_cache()` rebuilds the cache FROM the
  roster, so on any drift the roster wins. A character the resolver can't find is rejected (no
  fake character); the resolver is an injected `Callable` seam (no `/root`, no tree walk, no new
  singleton, no per-mutation lookup — §11).
- **Single mutation path with full invariants (§7/§12).** Every change goes through
  `SectService` (no caller edits a SectState array): duplicate join / unknown leave / unknown
  rank / self-membership / two-leaders / leader-also-elder are all rejected; resources clamp at
  0 (int only), reputation clamps to [-100,100], influence clamps at 0, territory stays unique.
  The service emits domain signals (not EventBus — domain stays infra-free).
- **Rank ladder is DATA, not code.** The vocabulary (Outer Disciple → … → Sect Master) is
  authored as ordered `SectRankData`; `SectService` never hard-codes a rank string. `authority`
  is a comparable int so rules order ranks without string matching.
- **Alliances/enemies mirror to ONE relationship graph, transactionally (§14).** Declared sect
  diplomacy is mirrored to a symmetric Sect↔Sect edge via the existing `RelationshipService`
  (deterministic stable `sect_rel:a|b` id; one edge per pair; ally↔enemy retypes the single
  edge). The mirror runs FIRST; if it fails the sect-side declaration is rolled back, so the two
  stores never diverge. There is no third duplicate relationship store.
- **SectRuntime is per-session, under `Main/Systems`, NOT an autoload** (budget frozen at 5).
  It loads the catalog, registers sects, applies default diplomacy, enrolls the player into the
  authored start sect through the service (so the ROSTER is authoritative, not just the cache),
  survives map swaps, and ends/clears on return to menu. Main sequences it after the world +
  relationship sessions; WorldRuntime stays the map/player coordinator (no God object).
- **Serialization seam only (SaveService is Phase 23).** `SectState`/`SectStore` have
  deterministic `to_dict`/fail-closed `from_dict`/`hydrate`; nothing is wired to a save yet.
- **Visible in-game (Continuous Visual Integration).** The HUD shows a sect chip; a `SectPanel`
  toggles via the new semantic `sect_panel` action (label via InputService); the hub shows a
  sect banner. All text localized vi+en; no raw ids; a localized no-sect state. Self-made CC0
  emblems (recorded in `ASSET_LICENSES.md`). No new screen, no default-Godot look, no new UI
  stack (reuses `UITheme`/`UIPalette`/Xianxia).

**Consequence:** sects are a tested, serializable, roster-authoritative domain system with one
mutation path and a consistent single relationship graph, visibly represented in the playable
game, ready for Phase 07 (Faction/Politics) to add `FactionState` + internal politics on top. No
new autoload; no networking; D-005 (save) / D-007 (combat) remain Open. **Phase 06 is CLOSED only
after CI is green on the commit (all 9 gates) — see CHANGELOG/ROADMAP for the verified SHA.**

---

## How to add a decision
Append `D-00N — <title> — <status> (date)` with Context / Options / Decision /
Consequence (or Blocking). Never silently change a shipped decision — mark the old one
**Superseded** and add a new entry.

---

## D-033 — An engine-free GDScript lint gate that runs on save, plus a compile check that actually detects a broken class — **Accepted** (2026-10-03, Phase 06 follow-up)

**Context:** L-020 cost a full CI round and a misdiagnosis. `sect_state.gd` failed to compile
because three locals inferred `Variant` from a `-> Variant` helper (a warning promoted to an
error). A script that fails to compile does not register its `class_name`, so every
`SectState.create_from_template(...)` call site died at runtime with the deeply misleading
`Nonexistent function 'create_from_template' in base 'GDScript'`. Two guess-fixes were pushed
at the CALL SITES before the real error was read. Two things made that possible:
1. **No local feedback existed.** Godot is not on PATH (D-009), and the only on-save hook ran
   `godot --headless … parse_check.gd`, so it silently no-opped on every save. The author's
   first signal was always a red CI run — or pasting the log in by hand.
2. **The parse gate could not see the failure.** `tools/parse_check.gd` only checked
   `load(path) == null`, and `load()` returns a NON-NULL but unusable `GDScript` for a script
   that parses yet fails to compile. The gate was green while the class was broken.

**Decisions:**
- **Add `tools/gdscript_lint.py`** — pure Python, zero dependencies, no engine. Rules, chosen
  for ZERO false positives because a noisy gate gets ignored:
  - `GD001 variant-infer` — `var x := <Variant expression>` (the L-020 bug), detected by
	finding the call that PRODUCES the value, so `int(d.get(k))` is silent while `d.get(k)` is
	flagged. The repo-wide index of `-> Variant` functions makes project helpers count too.
  - `GD002 private-access` — `other._member` where `_member` is declared in a DIFFERENT file.
	Same-file access through another receiver stays legal (that is normal same-class access),
	and Godot's own virtuals (`_ready`, `_process`, …) are exempt.
  - `GD003 line-too-long` — the budget Godot's own diagnostics flag.
- **The linter is self-tested (`--selftest`) and CI runs the self-test first.** This gate is
  load-bearing; a linter whose rules silently stopped matching is worse than no linter. The
  GD001 cases are the real L-020 lines plus the fix that replaced them.
- **It runs BEFORE Godot is downloaded in CI** (new gate 2 of 10) so a compile-breaking warning
  fails in seconds instead of after an engine download plus import.
- **On save it checks only CHANGED files** (`--changed`, via git) while still building the
  private-member index across the whole project — a partial index cannot distinguish "private
  member owned elsewhere" from "unknown name" and would silently miss GD002.
- **`tools/parse_check.gd` now proves a script COMPILES**, not merely loads: `load()` non-null,
  `can_instantiate()` true, and — the clearest signal — a script declaring `class_name X` must
  actually appear in `ProjectSettings.get_global_class_list()`. `can_instantiate()` was chosen
  over `reload()` deliberately: `reload()` would also detect it but recompiles the running tool
  and the live autoloads (D-019), which is not a risk worth taking in a gate that cannot be
  rehearsed locally (D-009). The project has no `@abstract` classes, so "cannot instantiate"
  means "does not compile". The class_name check self-disables if the engine reports an empty
  global class list, so it can never fail the build for an environment reason.

**Consequences:** the class of bug that produced L-020 now fails on save, in Python, in under
a second. The authoritative gates are unchanged in spirit: the linter catches a known, narrow,
precisely-decidable set; everything else remains the job of the compile check and the headless
suite (`08-ai-review-protocol.md`: parse/compile passing is still not "done").

**Alternatives rejected:** installing `gdtoolkit`/`gdlint` (another toolchain to pin, and its
rules do not cover the inferred-Variant trap that actually bit us); relying on the IDE's
diagnostics (they did not report the missing property class in L-018 and are not a CI gate);
making CI print more on failure as the permanent answer (that is diagnosis, not prevention —
steering 10 §1.3 requires removing such scaffolding once the error is understood).

---

## D-034 — UI surfaces and 9-slice assets are chosen from MEASURED pixels: dark text plate, flat keycap, nine-patched frames — **Accepted** (2026-10-03, Phase 06 follow-up)

**Context:** The Phase-06 HUD shipped visually broken in four ways at once: near-invisible text,
a huge empty rosewood plate covering the character name, control prompts rendered as unreadable
smudges, and pressing `T` appearing to do nothing. Every one traced to an assumption about an
asset that nobody had measured. Reading the actual PNGs settled it:

| asset | size | centre | reality |
|---|---|---|---|
| `panel.png` | 218×118 | brightness **230** | a LIGHT plate |
| `panel_inset.png` | 216×117 | brightness **19** | a DARK plate |
| `button_normal.png` | 130×54 | brightness 193 | light |
| `portrait_frame.png` | 218×118 | brightness 229 | a light PANEL, not a small frame |
| `key_badge.png` | 61×61 | **alpha 0** | a hollow corner ornament, NOT a keycap |

**Decisions:**
- **A surface that carries text must be DARK, because every text token in `UIPalette` is light**
  (0.62–0.96). `panel_stylebox()` now uses the ink inset texture; the light jade plate is still
  available as `accent_panel_stylebox()` for decoration that carries no light text. Pairing
  light text with the light plate is what produced "white text on a white plate".
- **`content_margin >= texture_margin` on every framed box.** The 9-slice border band does not
  stretch, so a smaller content margin draws glyphs on top of the frame art.
- **The keycap is a deliberate flat chip, not the pack texture.** `key_badge.png` has a
  transparent centre, so it cannot back a glyph, and nine-slicing it down to keycap size
  collapsed its 18px border bands into each other. The pack ships no keycap, so one is drawn:
  dark fill + jade edge. This is an honest downgrade from "asset-backed", recorded here.
- **Light text gets a dark outline** (`font_outline_color`/`outline_size` on Label and Button in
  the shared theme), so labels survive a busy background without a second text palette.
- **The HUD wears the shared theme.** A `CanvasLayer` cannot hold a `Theme`, so it goes on the
  HUD's root `Control` — previously only the main menu was themed at all.
- **A `TextureRect` used as a sized slot MUST set `expand_mode = EXPAND_IGNORE_SIZE`,** and a
  FRAME belongs in a `NinePatchRect`. Left at the default `EXPAND_KEEP_SIZE`, a TextureRect
  reports its whole texture as its minimum size, which is how a 218×118 plate ended up as a
  "40×40" portrait slot and shoved the identity panel over the name.
- **Growth direction is a property of the node that grows.** The sect panel was wrapped in an
  empty size-0 `Control` carrying `grow_horizontal = BEGIN`; growth does not propagate to
  children, so the panel still grew rightwards off-screen and only a sliver of its frame was
  visible — which read as "`T` does nothing". The anchors/growth now live on the panel itself.
- **The base viewport is declared** (`1152×648`). It was previously undeclared, so the project
  ran on an engine default that nothing in the repo stated.
- **Measured facts are recorded in `ui_palette.gd`** next to the margins they justify, and
  guarded by tests (the text plate must be the dark texture; content margins must clear the
  border; the keycap must have an opaque fill; the theme must carry an outline) so this cannot
  silently regress to white-on-white.

**Consequences:** the live UI is no longer 100% asset-backed — the keycap is drawn. That is the
correct trade for legibility, and `docs/ASSET_LICENSES.md` records the pack asset as unused for
that slot. Reverting any of these pairings now fails a test rather than shipping.

---

## D-035 — Vietnamese is the default language, with an in-game Settings screen and a persisted choice (no new autoload) — **Accepted** (2026-10-03, Phase 06 follow-up)

**Context:** Per-phase beta builds are play-tested in Vietnamese, but the game started in
English and there was no way to change language without editing code. `01-product.md` makes
Vietnamese and English both first-class from the foundation, so this was a gap, not a feature
request. There was also no persistence of any kind in the project yet.

**Decisions:**
- **`DEFAULT_LANGUAGE = "vi"`.** The game starts in Vietnamese.
- **`FALLBACK_LANGUAGE = "en"` is a SEPARATE constant.** The start language and the translation
  fallback are different concerns: collapsing them means a key missing its `vi` value would
  "fall back" to `vi`, resolve to the raw key, and hide the English text that does exist.
- **A `SettingsMenu` screen** (reachable from the now-enabled Settings button) lists one button
  per `Localization.available_languages()` — so adding a third language stays a CSV change plus
  one label key, with no screen edit. The active choice is marked in TEXT, not colour alone.
- **Settings is UI, not a routed scene.** Like the main menu it is a `Control` under `Main/UI`;
  `SceneRouter` owns the CONTENT scene under `Main/World` (the map). Opening it HIDES the menu
  rather than freeing it, and closing it reveals the menu again, so the lifecycle never leaves
  the MENU phase and no `enter_menu` transition is re-requested.
- **`SettingsStore` is a `RefCounted`, not an autoload** (budget stays at 5 — D-017). It is a
  thin `ConfigFile` wrapper over `user://settings.cfg` that load-modify-saves so a future
  preference owned by someone else is not clobbered, and whose every failure path degrades to
  "no preference" with a warning — a preferences problem must never block boot. The config path
  is injectable so tests bind to a scratch file.
- **`Localization` stays DISK-FREE.** Persistence lives with the two owners of the concern: the
  settings screen writes the choice, and `Main` reads it at boot and applies it through
  `set_language()` before any UI is built. This is a correctness decision, not tidiness: unit
  tests construct a `Localization` and switch language freely, so a service that wrote to
  `user://` would leave a stale preference and make "the default language is vi" pass or fail
  on leftover disk state — the L-010 shared-state trap, on disk instead of under `/root`.

**Consequences:** `SaveService` (Phase 23) remains the owner of GAMEPLAY saves; this store is
only for application preferences and must not accumulate run/session/world data. Load Game
stays disabled until that phase.

---

## D-036 — The camera follows the player, and maps are authored larger than the view — **Accepted** (2026-10-03, Phase 06 follow-up)

**Context:** D-034 made the camera zoom cover the map so no background showed around it. That
immediately exposed a gap that had been hidden since Phase 03: each map scene's `Camera2D` is a
plain child node parked at the map centre, and **nothing ever moved it**. While the whole map
fitted on screen a static camera looked correct; once the view was smaller than the map the
player simply walked out of frame. Two further problems compounded it: rounding the derived
zoom UP (`ceil`) turned a needed 3.01 into 4.0 and framed the player far too close, and a
448×288 map is smaller than a 16:9 screen at any comfortable zoom, so "cover the map" and "let
the camera travel" were in direct conflict.

**Decisions:**
- **`MapBase` follows the player** in `_physics_process` (the player moves there too, so body
  and camera advance in the same step), with `position_smoothing` doing the visual easing. The
  target is resolved lazily, because `WorldRuntime` parents the player after the scene loads.
  The camera LIMITS (from `MapData.bounds`) still clamp the result, so following can never
  reveal anything past the map edge. Cost: one node, one assignment per physics frame.
- **No rounding up of the derived zoom.** The floor stays `CAMERA_ZOOM_MIN` (2.0); maps are
  authored comfortably larger than the view so the zoom normally lands exactly on that integer,
  and the fractional path only engages on an extreme window aspect, where covering the map
  matters more than a perfectly integer scale.
- **The hub and field maps are authored 960×576** (60×36 tiles) instead of 448×288, which is
  what actually resolves the conflict: at a 16:9-ish window the zoom settles at 2.0, the view
  (~675×324) sits comfortably inside the map, and the camera has room to travel on both axes.
  Walls, spawns, exits and decor moved with the new extent; node names and prop textures are
  unchanged, so the structural contracts still hold.
- **`MapData.bounds` is tested against the scene's painted floor.** The bounds drive the camera
  limits and the zoom while the floor lives in the scene as `fill_rect` (tile coordinates), and
  the two are hand-authored in different files. A structural test now compares them, so a future
  resize cannot silently clamp the camera to the wrong rectangle (an L-014 drift guard).
- **The E2E proves the camera MOVED**, not that it equals the player position (smoothing eases
  it over frames), and that it stayed inside the horizontal limits while following.

**Consequences:** the maps are now mostly open ground — they are prototype layouts and the extra
space is intentional room for the NPC/encounter content of later phases. The camera-follow
behaviour is per-map in `MapBase`; if a later phase needs cinematic or multi-target framing it
should become its own component rather than growing this coordinator.

---

## D-037 — Phase 06 final hardening: the sect core fails closed, never destroys before it succeeds, and never coerces at a boundary — **Accepted** (2026-10-03, Phase 06 final hardening)

**Context:** Phase 06 closed CI-green and the follow-up (D-033…D-036) added a lint gate, UI
legibility, camera follow and a Vietnamese default — all ten gates green. None of that could see
the class of defect audited here: every one of these is a path that only runs when something
goes WRONG, so a green suite proves nothing about it. Six were found and closed. "CI is green"
is explicitly not a reason to leave a failure mode open
(`.kiro/steering/08-ai-review-protocol.md`: build passing is not done).

**Decisions:**

- **A diplomacy retype is IN PLACE; nothing is destroyed before the replacement succeeds.**
  `SectService._ensure_edge()` flipped ALLY→ENEMY by `remove_edge()` **then** `create_edge()`.
  The surrounding `_set_diplomacy()` was a correct transaction and a test even proved the SECT
  side rolled back — but by the time `create_edge` could fail the original edge was already
  gone, with its dimension values and history. A rejected flip therefore left the sect state
  saying "allied" and the relationship graph holding no edge at all: exactly the divergence the
  transaction existed to prevent. On the SUCCESS path it was lossy too, because a new edge is
  seeded from config defaults. New narrow API `RelationshipService.set_relationship_type()`
  rewrites ONLY `relationship_type`, preserving `id`, `from_ref`/`to_ref` (so the endpoint
  indexes and canonical order are untouched), `symmetric`, `known`, every dimension and the
  whole history; it fails loud on an unknown edge or an empty type and never creates one. It
  emits no signal: `relationship_changed` reports a DIMENSION change with int values, and no
  consumer of a type-change event exists (no speculative surface — L-005). The tests now assert
  OBJECT IDENTITY plus preserved dimensions/history, because a test that only checks the
  resulting type passes for a recreated edge. See L-023.

- **`SectRuntime.start_session()` is fail-closed and commits nothing until every step succeeds.**
  It used to write its own fields as it went, `continue` past a sect that failed to register,
  `push_warning` when the player could not join, and then set `_session_active = true` and
  return `true` regardless — so `is_session_active()` could advertise a sect world with missing
  sects, no player membership, or declared enmities absent from the relationship graph. It is now
  nine explicit steps built into LOCALS (catalog valid → relationship dependency satisfied →
  every template valid → every state built → every registration succeeded → diplomacy mirrored →
  start sect resolves → player enrolled → derived cache agrees with the roster), committed only
  at the end, with `_fail_start()` clearing every field. A failure is invisible by construction
  rather than by a cleanup path. `apply_default_diplomacy()` returns `bool` and fails closed on a
  DANGLING declaration (previously skipped) and on declared diplomacy with no relationship
  service to mirror into (previously the whole mirror was skipped); the only legitimate no-mirror
  case is "nothing declares diplomacy", which roster-only unit tests use. See L-025.

- **A relationship or sect failure is FATAL for New Game, and the unwind is ordered.** `Main`
  still treated both as advisory even though the sect session had become a hard consumer of the
  relationship graph AND a writer of the player's derived `CharacterState.sect_id`. The reachable
  end state was phase `RUNNING` + a live world + `character.sect_id` set + an inactive sect
  session: membership no system owned. Both are now fatal, `_start_sect_session()` returns `bool`
  and reports every prerequisite it checks, and `_unwind_failed_session()` ends
  **Sect → Relationship → World → GameState** then shows the menu. That order is reverse
  dependency order: the sect session holds the graph and the character cache, both owned by
  subsystems ended after it. The E2E now asserts the forbidden combination is unreachable.

- **`SectState.from_dict()` validates `typeof()` BEFORE converting.** The validator was
  fail-closed and atomic and still accepted garbage, because every field was read through a
  COERCION. GDScript's converters do not fail, they invent: `int("100")` and `int(100.0)` both
  give the valid quantity `100`, `int(true)` gives `1`, `String(99)` gives the plausible id
  `"99"`, and `String(null)` gives `""` — which then reads as the legitimate "no leader" rather
  than "corrupt payload". Every ID-like field (`id`, `template_id`, `leader_ref`, member ids,
  rank ids, elder refs, territory/ally/enemy ids, resource ids, reputation scopes — dictionary
  KEYS included) must now be `TYPE_STRING`/`TYPE_STRING_NAME`, and every count-like field
  (resource quantity, reputation value, influence) must be `TYPE_INT`, so an integral float is
  rejected rather than quietly promoted. The staged-then-commit shape is unchanged, so a
  rejection leaves the instance byte-identical. See L-024.

- **The rank ladder's `authority` must increase STRICTLY along the authored array.** The array
  order is the official progression (§4) and `authority` is what rules compare, so the two must
  agree or the ladder means two things at once: `[10, 20, 20]` makes a promotion that grants no
  authority, and `[30, 20, 10]` makes every promotion a demotion while `lowest_rank()` /
  `highest_rank()` (which pick by authority, not position) silently disagree with the author's
  intent. With monotonicity enforced, "the next rung" and "more authority" are the same
  statement and `lowest_rank()` is always the first entry.

- **`SectCatalog` validates referential integrity of declared diplomacy.** A template can only
  check the SHAPE of its own two lists (non-self, unique, disjoint); whether a referenced id
  EXISTS is a question only the catalog can answer — and it used to be answered by silently
  dropping the pair at mirror time, producing a session whose sect state declared an enemy no
  sect in the world matched. A dangling ally/enemy now makes the catalog INVALID, so
  `SectRuntime` refuses to load it instead of booting a world that disagrees with its own data.
  A test reads the SHIPPED catalog, so authoring a dangling reference fails the suite rather
  than the player's boot (an L-014 drift guard).

- **The Sect panel renders resource NAMES, never content ids.** `_format_resources()` printed
  the dict keys (`spirit_stones`, `pills`, `manpower`, `blood_crystals`) straight onto the
  screen: both a raw-id leak (§21) and hard-coded non-localized text in a Vietnamese-first game.
  Each id now resolves through the pure naming convention
  `spirit_stones → SECT_RESOURCE_SPIRIT_STONES` with vi+en rows authored, and an id with no
  authored key falls back to a LOCALIZED generic label. Deliberately a naming rule, not a
  resource registry/lookup system: new content is two CSV rows, no code (anti-over-engineering,
  `03-architecture.md`).

**Scope guard honored:** no Faction/Politics (Phase 07), no World Simulation, no Combat,
Inventory, SaveService or networking; **no new autoload** (D-017 budget stays at 5); **no new CI
gate** (still 10) — the existing test files were expanded in place; no assertion was weakened to
make a test pass. The one intentional behavioural break is that `SectRuntime.start_session(null,
…)` against a catalog that declares diplomacy now FAILS; the unit tests that relied on the old
silent-skip were updated to supply a real in-memory `RelationshipService` (the same shape
`RelationshipRuntime` provides), and a new test pins the fail-closed behaviour.

**Consequences:** the sect world is now all-or-nothing. A content error in `data/sects/` (a
dangling reference, a bad ladder, an invalid template) will ABORT New Game back to the menu with
a loud error instead of starting a quietly-wrong session — which is the intended trade, and makes
content errors impossible to miss during authoring. `SaveService` (D-005, still Open) inherits a
`from_dict` that rejects type-drift, so a future save-format migration must convert types
explicitly rather than leaning on coercion.

---

## D-038 — Residual Phase 06 consistency: the reverse transaction, symmetric authored diplomacy, a required resolver, and test integrity — **Accepted** (2026-10-04, Phase 06 final-hardening follow-up)

**Context:** D-037 hardened the sect core and CI went green 10/10. A deeper review then found
four residual issues that the green run could not reveal — three of them in code paths that
only execute when something goes wrong, and one in the test harness itself, which is the worst
place for a defect to hide.

**Decisions:**

- **`clear_diplomacy()` is transactional in the same direction as `_set_diplomacy()`.** D-037
  fixed the *create/retype* leg but left the *remove* leg inverted: `clear_diplomacy` mutated
  BOTH `SectState`s first and then called `RelationshipService.remove_edge()` **discarding its
  boolean**. So a rejected removal left the sect state saying "no relation" while the mirrored
  edge survived — L-023's divergence, in the opposite direction. Now the relationship side runs
  FIRST and is checked; the declarations are cleared only after the edge is actually gone. Three
  further guards: a pair with nothing declared is an idempotent no-op that never reads or writes
  the graph (and emits no `diplomacy_changed`, matching the no-emit-on-no-change rule the
  economy mutators already follow — there is no consumer of that signal yet, so this is not a
  breaking change); the two sects disagreeing about the declared relation fails closed rather
  than clearing half of a corrupt hydrate; and an edge carrying a type this mirror does not own
  (`MASTER_DISCIPLE`, `RIVAL`, …) is **left alone** — the sect mirror owns only the ALLY/ENEMY
  edges it creates, and destroying another system's graph data to satisfy a sect-side clear is
  worse than refusing.

- **Authored default diplomacy must be SYMMETRIC and non-conflicting.** The per-template checks
  (self-reference, duplicates, ally/enemy overlap) and the D-037 catalog check (the id resolves)
  are all *one-sided*. But a default declaration describes a MUTUAL standing and the service
  mirrors it as ONE symmetric edge per pair, so `A ALLY B` with B silent produces an edge only
  one sect's state records, and `A ALLY B` + `B ENEMY A` has no correct answer at all — the
  surviving type would be decided by whichever sect the catalog happens to list last. Both are
  now catalog errors. The check keys every pair on the two ids **sorted**, so the verdict is
  order-independent by construction; a test asserts the same result with the sect list reversed.
  Shipped content (Azure Cloud ↔ Crimson Flame, mutual ENEMY) is unaffected. Implemented as ~40
  lines inside the existing validator — deliberately NOT a relationship registry or a new
  abstraction (`03-architecture.md`). `SectCatalog` keeps its own two local `ALLY`/`ENEMY`
  marker constants rather than importing `SectService`'s: the catalog is DATA and must not
  depend on the domain layer.

- **`SectRuntime.start_session()` requires a WORKING character resolver when the catalog names a
  player start sect.** `SectService` intentionally treats an absent resolver as "character
  checks disabled" so pure roster unit tests can exercise membership without characters — that
  service-level contract is UNCHANGED. The hole was at the runtime boundary: a real session
  enrolling a real player with an invalid (or non-resolving) resolver silently skipped both the
  existence check (§10: never invent a character) and the derived-cache write, producing a sect
  whose roster named a player no `CharacterState` was bound to. The runtime now demands a valid
  Callable that actually resolves `player_instance_id`, and fails closed otherwise — leaving no
  session, no store, no service, and the player's `sect_id`/`sect_rank` untouched.

- **A test method that ABORTS was being reported as PASS.** CI said `275 passed / 0 failed`
  while the log contained real `SCRIPT ERROR:` lines: seven methods had never executed an
  assertion. A typed `@export` array (`Array[Dictionary]`, `Array[RelationshipRuleData]`)
  rejects an untyped one, and that raises a GDScript **VM** error, which aborts the running
  function — so the fixture helper returned `null`, the caller faulted on it, the method died,
  and `TestCase` (which records only *assertion* failures) reported success. Fixes:
  - every fixture builds a **typed local** and assigns that, and fixture receivers/helper
	returns are typed as the CONCRETE class instead of `Resource`;
  - fixtures are asserted before behaviour (`assert_eq(cfg.dimensions.size(), 1)`), and the
	negative tests now pin the reported REASON — a config that failed to build is "invalid"
	for the wrong reason, which is exactly how these passed while testing nothing;
  - **the EXISTING "Headless test suite" gate now fails on any `SCRIPT ERROR:`** even when the
	runner exits 0. `push_error()` prints `USER ERROR:`, not `SCRIPT ERROR:`, so the deliberate
	fail-closed negative tests do not trip it. The same gate emits the runner's own
    "ran N test(s)" tally as a `::notice::` annotation, because annotations are readable on the
    public check-run API while the log and the step summary are not (D-009) — so the documented
    test count is quoted from CI rather than counted by hand.
  See L-026.

**Scope guard honored:** no new CI gate (**still 10** — the existing suite gate was hardened),
no new autoload (still 5), no Faction/Politics, World Simulation, Combat, Inventory, SaveService
or networking, no new global manager and no new generic framework. No gameplay scope change.

**Consequences:** the sect↔relationship mirror is now transactional in BOTH directions, and
authored diplomacy is verified to be a coherent mutual relation before a session starts. The
test suite's reported pass count is trustworthy for the first time.

**Verified:** CI green, all 10 gates, on `1dabdba` — `ran 282 test(s): 282 passed, 0 failed`
with **zero `SCRIPT ERROR:` lines**, which is the proof that the repaired fixtures now actually
execute (the seven previously-aborting methods were already being counted as passes, so the
total moved 275 → 282 purely from the seven NEW tests added here). The count is quoted from the
gate's `::notice::` annotation.

---

## D-039 — Master Game Design Freeze v2.1: the world, narrative and systems design is frozen before the content phases begin — **Accepted** (2026-10-04, documentation only)

**Context:** Phases 00–06 built a correct foundation — lifecycle, input, localization, maps,
Character, Relationship, Sect — each serializable, data-driven and CI-verified. The remaining 28
phases add *content-bearing* systems (combat, cultivation, items, quests, story, dungeons, a
multi-world cosmos), and those fail differently: not by crashing, but by being individually
reasonable and **collectively incoherent**. That failure is only visible in aggregate, hundreds of
quests later, when the fix is a rewrite. So the design was audited and frozen while changing a
realm name still costs one markdown edit instead of a save-format migration.

The audit was not a summarisation pass. It found **eleven real contradictions already in the
repository**, each recorded with an authoritative owner in `docs/CONTRADICTION_REGISTER.md`. Three
mattered enough to name here:

- **C-003 (premise-breaking).** `NARRATIVE_DIRECTION.md` §1 promises the player begins with "no
  sect standing", while `data/sects/sect_catalog.tres` enrols them into Azure Cloud at Outer
  Disciple on New Game — and D-037 had just made that enrolment *fail-closed mandatory*. The
  game's own premise ("a nobody earns a place") was false in minute one. Canon: the narrative wins;
  the enrolment is honest Phase-06 scaffolding (a HUD chip and a panel need a member to render) and
  becomes `&""` in the phase that can dramatise joining. Flipping it today would trade a true
  premise for a blank panel and lose the only live coverage of the sect path.
- **C-001 (most expensive if deferred).** The realm ladder was still the conventional
  Luyện Khí → Trúc Cơ *example* in the steering glossary. Nothing had been authored against it —
  no realm id, no `.tres`, no locale key, Phase 12 NOT STARTED — which made this the last cheap
  moment to replace it. Frozen hierarchy: **PHÀM → HẬU THIÊN → TIÊN THIÊN → NGỰ THIÊN → TRỌNG
  THIÊN** (+ structural THÁI THIÊN / VÔ THIÊN), nine layers per numbered realm, each layer meaning
  the same KIND of thing in every realm.
- **C-002 (the default a team drifts into).** The supplied design poster gated maps by level
  ("Lv 10–30"), while steering 02 binds content gating to cảnh giới. Resolution: **level is never
  an access gate**; the poster's bands are advisory **threat ratings**, and access is a layered
  gate (realm + quest/story + knowledge + sect/faction standing + world state + key item). Once
  two maps ship with a `min_level`, realms are decorative — so `MapData` is forbidden from ever
  gaining that field.

**Decisions:**
- **Thirteen documents** created, with **one authoritative owner per rule** declared in
  `docs/GAME_DESIGN_FREEZE.md` §2. Deliberately NOT duplicated: the damage formula stays only in
  `DATA_SCHEMA.md`, relationship dimensions only in `RELATIONSHIP_SYSTEM.md`, phase numbers only in
  `ROADMAP.md`. A document that restates another's rule as if it owned it is a bug (L-014).
- **Canon is a lookup table, not prose.** `CANON_LEDGER.md` holds the frozen facts as citable ids
  (`CL-nn`) because bibles get rewritten and content authors need something stable to cite.
- **Original world, structural inspiration only.** Aetheria takes the *shape* of cultivation
  fiction (a vast hierarchy, a Main World above lesser worlds, suppressed history) and none of its
  content: no characters, sects, techniques, artifacts, world names or plots from any existing
  work. New canon: **Hạo Nguyên Giới** (Main World, 5 đại vực / 12 châu), the **Hải Giới**,
  Tiểu/Tàn/Hủ/Vô Giới, the **Thiên Khế** covenant, the historical **Tà Đế** with three
  incompatible records, **ĐÊM VỠ MẠCH** as the inciting event, and five gender-independent Origins.
- **Identity is derived, never counted.** No `evil_score`, morality meter or alignment anywhere.
  "Tà Đế" is read from cultivation + techniques + knowledge + relationships + sect/faction standing
  + world events + decisions, which is what lets a compassionate player earn the title and a
  ruthless one avoid it.
- **Three categories of "forbidden" are kept distinct** (CL-01): **Ma Đạo** (a named tradition) ·
  **Tà Đạo** (a political proscription) · **Cấm Pháp** (a factual self-destructive cost).
  Collapsing them is what turns ambiguity into a verdict, so `SectType.DEMONIC` is frozen as *the
  orthodox label*, not a moral fact.
- **Knowledge (Tri Thức) is a third progression concept** — named, discrete, permanent, and
  sometimes WRONG. Without it every lock must be opened with power and the only reward the game can
  give is a bigger number; with it, the central mystery becomes playable (the Thiên Khế cannot be
  defeated, only understood).
- **Two dependency graphs are separated** (`SYSTEM_DEPENDENCY_MATRIX.md` §3): engineering
  dependency (what must exist to run) and player-facing content dependency (what must exist for a
  beat to be playable). Confusing them is how teams build a story engine before the systems its
  branches read. Audit W confirmed the roadmap follows the engineering graph correctly — Combat and
  Enemy AI before Level/XP and Cultivation is right, because XP has no source until combat emits it.
- **Balance is deliberately NOT frozen.** XP curves, damage, drop rates, cultivation speed,
  cooldowns, threat boundaries and map sizes stay tunable; the architecture they plug into is
  frozen. Phase 11 may tune the XP curve; it may not decide that level gates access.
- **Extensibility was tested, not asserted.** The 10-quest/5-NPC/3-map/2-dungeon/2-boss/
  3-technique/2-weapon/1-sect/2-faction/1-Minor-World simulation passes as data + content scenes
  (`CONTENT_BIBLE.md` §15), with two honest exceptions recorded: a **sixth weapon family** and a
  **new element/status** are closed-set design changes requiring their own decision entries.

**Scope guard honored:** documentation only. **No gameplay code, no runtime behaviour change, no
content/`.tres`/locale change, no new autoload** (budget stays at 5), **no networking**, no God
object, no speculative framework, no phase renumbering. Six content debts were created by resolving
contradictions, each bound to a named phase (`GAME_DESIGN_FREEZE.md` §7) so none is lost.

**Consequences:** future phases inherit a decided world instead of inventing one locally. The cost
is that canon changes are now expensive on purpose — critical canon (protagonist identity, Origins,
world law, Thiên Khế, realm/world hierarchy, major sects/factions, the historical Tà Đế, core
progression, economy architecture, multiplayer narrative semantics) requires a DECISIONS entry
recording OLD · NEW · WHY · IMPACT · AFFECTED CONTENT · AFFECTED SYSTEMS · MIGRATION. That friction
is the point: it is what stops Act VIII from quietly contradicting Act I.

---

## D-040 — Knowledge Core and the deterministic RNG seam get valid owners and phases — **Accepted** (2026-10-04, documentation only)

**Context:** an independent review of the D-039 freeze found **two dependency defects**. Both are
worth recording precisely, because neither was a careless typo — they are the specific blind spot
a per-system dependency matrix creates: **every row can be locally correct while the ordering
between rows is impossible.** Audits A–W each examined one *domain* (narrative, economy, maps, …)
and all passed; these two defects live in the *edges between phases*, which no single-domain audit
looks at.

### Defect 1 — Knowledge's owner and order were impossible (C-012)

The matrix said `Knowledge | P-19/20 | the story/quest state owner`. But the same freeze had
Cultivation (**P-12**) reading knowledge for breakthrough prerequisites and Technique (**P-15**)
reading it for technique prerequisites. P-12 cannot depend on authoritative state that first
exists at P-19.

Left alone, this would have resolved itself in the worst available way: Phase 12 would invent a
private "known things" dictionary to unblock itself, Phase 15 would add a second one, and Phase
20's Story engine would arrive to find two parallel sources of truth to reconcile — **exactly the
failure D-015 had to be written to undo for sect membership.** It would also have quietly demoted
knowledge from "the third progression axis" to "a bag of story flags", losing the one mechanism
that lets the Thiên Khế mystery be solved by understanding rather than by force.

**Decisions:**
- **Knowledge Core lands in PHASE 12** with its **own authoritative domain owner**:
  `KnowledgeStore` (the collection) + `KnowledgeService` (the single mutation path). **No
  autoload** (D-017 budget stays at 5), no global manager, no god object. Persistent domain state,
  injected like `RelationshipService`.
- Core responsibilities only: named knowledge **ids** · acquired state · a **deterministic grant
  path** · query · the persistence boundary · an observable `knowledge_gained` event.
- **Ownership direction:** Cultivation **reads** · Technique **reads** · Crafting **reads** ·
  Dialogue/Quest/Story **grant and read through the service** · NPC/content **expose
  opportunities**. **No system but the service may mutate the collection.** Story does not own
  knowledge; Quest does not own knowledge; knowledge is never a private story flag.
- **Phase model:** P-12 core → P-15 technique prerequisites → P-17 content exposes opportunities →
  P-18 dialogue grants → P-19 quest grants → P-20 story/history grants → later phases expand the
  catalogue. **The core precedes its producers**, which is the same shape as Phase 05: the
  relationship graph shipped as a substrate with no gameplay producer, and Phases 06+ became its
  producers (D-026). A substrate belongs with its first *consumer*, not with its first *producer*.
- **Scope guard:** Phase 12 does **not** grow a story or quest engine to support this. A store, a
  service, a grant path and an event is the entire core. Until P-18+, the authored catalogue is
  small — just the cultivation/technique prerequisites — which is exactly enough to make the core
  testable without inventing its consumers.

### Defect 2 — the RNG first consumer was named one phase too late (C-010)

D-039 resolved C-010 as WATCH with the rule "the first phase that needs randomness introduces the
seam", then guessed the first caller would be **Combat (P-09)**. That guess contradicted the same
freeze: **World Simulation is P-08** and its determinism requirement is explicit and
non-negotiable (`WORLD_SIMULATION.md` §5).

**Decisions:**
- **The deterministic RNG seam is introduced in PHASE 08, with World Simulation.** Phase 09 Combat
  **consumes the established seam** on its own stream; it does not introduce a second source.
- The seam is **stream-scoped**: one run/world seed fanning out into per-subsystem streams
  (world sim · combat · enemy AI · loot/economy · future instances).
- **Why streams rather than one shared generator:** with a single generator, adding one extra
  random call in combat silently shifts every subsequent world-simulation roll. A bug fix in one
  subsystem would change unrelated outcomes, and "same seed → same world" would stop being true.
  Per-stream state makes each subsystem's sequence reproducible **independently**, which is what
  makes a seeded replay, a regression test, and a future server-advanced world all possible at
  once.
- Frozen properties: deterministic · seeded · injectable · subsystem/stream-scoped · serializable
  where required · presentation-independent · **no global `rand*()` in domain code, ever**. **Not
  an autoload.** Class names, stream-id vocabulary, algorithm and serialized shape belong to P-08.
- **Save implication (requirement only, `SAVE_FORMAT.md` §3b):** the sketch's single
  `rng: { seed }` is **not sufficient**. A seed alone reproduces a run only *from the beginning*;
  a save taken 40 hours in must also restore **how far each stream has advanced**, or the
  post-load world diverges from the pre-load world — breaking the save-resumable guarantee,
  reproducible bug reports, and any future server-advanced world. Whether that is a counter, a
  state blob or a re-derivable `(seed, stream_id, draw_count)` triple is left to P-08/P-23; this
  freeze only guarantees it will not be forgotten.

### Process change

**Audit X — dependency topology** is added as a permanent gate, with the rule it enforces: **no
earlier phase may require authoritative state owned by a later phase.** The full edge-by-edge
check (P-07→08, P-08→09, P-11→12, P-12 Knowledge→P-15, P-17→18→19→20→21, …) is
`SYSTEM_DEPENDENCY_MATRIX.md` §4b. Audits A–W remain domain audits; X is the graph audit they
structurally could not be.

**Also fixed in passing:** the World Simulation row in the dependency matrix was missing its UI
column (14 cells in a 15-column table) — a table defect introduced in D-039, corrected here along
with a new explicit **Deterministic RNG** row.

**Scope guard honored:** documentation only. **No gameplay code, no scenes, no `.tres`, no
`project.godot`, no locale change, no runtime behaviour change, no new autoload, no networking.**
No phase renumbering: Phase 12 and Phase 08 gained explicit substrate scope, nothing moved.

**Consequences:** Phase 12 is now a two-part phase (cultivation + the Knowledge Core substrate)
and Phase 08 is now responsible for a seam three later phases depend on. Both are larger than they
read in D-039 — that is the honest cost of fixing a backwards dependency before it is built, and
it is far cheaper than the parallel-source-of-truth reconciliation it replaces.

---

## D-041 — The production-foundation visual direction is integrated into the runtime UI — **Accepted** (2026-10-02, presentation only)

**Context:** the Aetheria visual reference board (supplied by the project owner) and
`docs/UI_UX_BIBLE.md` describe a composed, deliberate ink-and-jade tu-tiên interface. What
actually shipped through Phase 06 was correct and legible (D-034 fixed the readability defects)
but **undesigned**: the main menu was a small plaque on a flat near-black `ColorRect`, every
action button carried identical weight, the HUD's identity block stacked the character's title
and the player's sect membership as two indistinguishable muted lines, and screen-edge spacing
came from the generic `SPACE_MD` token shared with inner padding. None of that is a bug a
compile, lint or assertion gate can see — which is exactly the class of defect L-021 was written
about. It is a **composition** gap, and it had to be closed before Phase 07 adds the first
Faction UI, or the new screen would inherit the undesigned language and the cost would double.

**Decision:** upgrade the runtime UI to the reference's visual direction as a **presentation-only**
pass. Four changes, in the order they matter:

### 1. The menu is composed as a scene, not a widget stack

`main_menu.gd` now builds a backdrop: a deep ink ground (`COLOR_BACKGROUND_DEEP`), a vertical
`GradientTexture2D` that gives the screen a **horizon** rather than a flat void, a restrained
radial vignette that pulls the eye to the plaque, and four corner ornaments framing the viewport.

It is built from **code-generated gradients plus one existing texture**. No new asset was
imported, so there is no new provenance or license obligation (`06-art-assets.md`), and there is
no per-frame cost: a `GradientTexture2D` rasterises once and is thereafter a static draw. The
gradient layers are the **only** UI textures set to `TEXTURE_FILTER_LINEAR` — a 16×256 ramp
stretched full-screen would show visible banding steps under the project-default nearest filter.
Everything else in the UI stays nearest, as the pixel-art rule requires.

**Rejected:** using the reference board itself as a background (it is a design document, not
game art), and pulling panels/frames from the candidate CC0 packs (`06-art-assets.md` forbids
splicing packs into a collage, and the live language is Xianxia).

### 2. Button weight becomes semantic, and the roles live in one place

`UITheme` gained `ROLE_PRIMARY` / `ROLE_SECONDARY` / `ROLE_DANGER` with `role_modulate()` and
`role_font_color()`. The menu asks for a role; **it never names a colour**. Roles **modulate** the
authored xianxia texture rather than replacing it, so the pixel art is never distorted — and
`COLOR_CRIMSON` is declared **reserved**: it means "leaving or destroying", never ordinary
emphasis, or it stops meaning anything. Per the UI bible, colour is never the only carrier: the
primary action is also the focused action on entry, and every label is still a localized word.

### 3. `key_badge.png` is finally used for what it is

D-034 **measured** this asset: 61×61 with a **centre alpha of 0**. It is a hollow **corner
ornament**, and Phase 06 had pressed it into service as a keycap — where, having no fill, it
rendered glyphs as smudges. D-041 puts it in the four screen corners, which is its real job. The
keycap stays the deliberate drawn `StyleBoxFlat` chip from D-034. The asset moved from
"recorded but unused for its slot" to "used correctly", and `docs/ASSET_LICENSES.md` records that.

### 4. The HUD plaques gain hierarchy; the sect panel gains a value column

The identity plaque is now **one unit with two tiers** — portrait + name + title above an
ornamental rule, sect chip below it — because the old flat stack made "who I am" and "who I
belong to" typographically identical. The map-name plaque gained a width **floor** so it stops
resizing every time the player walks into a map with a shorter name, and its place name is
promoted to the title tone. The sect panel's four numeric facts became an aligned
caption/value column the eye can scan instead of four sentences of differing length.
Screen-edge spacing now comes from a dedicated `HUD_MARGIN` token, and the menu panel/button
widths from `MENU_PANEL_WIDTH`/`MENU_BUTTON_WIDTH`/`BUTTON_HEIGHT`, replacing literals that had
been duplicated across three files.

### What was deliberately NOT done

- **No HP / mana / realm / XP gauge was added.** The reference board shows them, and nothing in
  the running session owns health, mana, realm progress or XP yet. A gold bar that looks right in
  a mock and is a lie in a build is worse than an absent one; a test now asserts the HUD builds
  no `ProgressBar`/`TextureProgressBar` so a later pass cannot add one before its domain owner
  exists.
- **No new `.gd` file.** Reusable `UISectionTitle` / `UIValueRow` components were the cleaner
  factoring and were rejected for a mechanical reason: this agent cannot generate the `.uid`
  sibling Godot requires for a new script (L-008/L-015), so a new file would ship broken resource
  identity. The row builder lives as a private helper in `sect_panel.gd` instead; promote it to a
  shared component the first time a second panel needs it (`03-architecture.md`
  anti-over-engineering — a second use case, not a speculative one).
- **No gameplay, domain, data or autoload change.** `git status` for this commit touches only
  `src/presentation/**` and `tests/unit/presentation/**`.

**Scope guard honored:** presentation only. No domain/gameplay file, no `.tres`, no
`project.godot`, no locale key added or renamed, no new autoload, no networking. Every string on
screen still resolves through `Localization`; the layout changes are width **floors** and
expanding dividers, so the +40% vi↔en string budget still fits.

**Verification — and one gap stated plainly:** `get_diagnostics` clean, `gdscript_lint` clean
(96 files), and the composition itself is covered by new structural tests (role distinctness,
reserved-crimson, backdrop layers, ornament identity, layout-token coherence, identity-plaque
tiering, map-plaque floor, divider stretch, shared HUD margin, no-unbound-stats, plus
behaviour-survival tests on both the menu and the HUD). **The runtime screenshots the task asked
for were NOT produced: Godot is not invocable on this machine (D-009), so no frame can be
rendered or captured here.** The visual result is therefore asserted structurally and by CI, not
observed. Someone with the editor must eyeball the Main Menu, the HUD in both maps, and the open
Sect panel in `vi` and `en` before this is called visually confirmed.

---

## D-042 — Phase 07: Faction / Sect Politics, and the §7 representation pin — **Accepted** (2026-10-02)

**Context:** `docs/SECT_SYSTEM.md` §7 declared internal factions a CORE requirement and sketched
a `FactionState` shape, but deliberately left one question open: *"Faction↔Faction and
Faction↔Player standings reuse the Relationship model where a richer edge is useful; simple
scalars live inline on the `FactionState` as above. (Which representation wins where is a detail
to pin when the Faction phase is built; both are serializable.)"* This is that phase, so this
entry pins it — and the pin contradicts part of the §7 sketch, which is why it is recorded here
rather than silently chosen (`08-ai-review-protocol.md`: a doc that contradicts another goes to
DECISIONS, you do not quietly pick one).

### The pin: standings are EDGES, not inline scalars

§7 listed `attitude_toward_player: int` and `attitudes_toward_factions: Dictionary` as fields on
`FactionState`. **Both are dropped.** They are not implemented, and `FactionState` has no
attitude storage of any kind.

The reason is not tidiness, it is that the alternative is a second source of truth.
`affinity` and `rivalry` are two of the **six frozen relationship dimensions** (CL-12), already
owned by `RelationshipStore`, already clamped by `RelationshipConfigData`, already carrying a
bounded history log. An `attitudes_toward_factions` dictionary would answer "how does A feel
about B" a second time, with its own clamp, its own (absent) history, and no mechanism keeping
the two in step — which is **exactly** the defect D-015 had to undo for sect membership, where
`CharacterState.sect_id` and the sect roster had both looked like the authority.

So: `FactionService` **reads and writes the shared graph** and stores no dimension itself.
- Faction↔Faction standing is a **symmetric relationship edge**, created through
  `RelationshipService.create_edge` with both endpoints typed `Kind.FACTION`.
- Faction↔Player standing is the same thing with a `CHARACTER` endpoint, available the moment a
  producer needs it — no faction-side scalar is reserved for it in advance (L-005).
- What `FactionState` *does* carry is the **declared political relation** (`allied_faction_ids` /
  `rival_faction_ids`) — a political *fact* the sect has announced, not a measured standing. That
  is the same split `SectState` already uses for declared ally/enemy, and the two are kept
  transactionally in step by the service.
- A test asserts the absence directly on the **serialized shape**, because that is what a save
  would carry and therefore what a future refactor would have to change to reintroduce the
  duplication.

`RelationshipEndpoint` gained `Kind.FACTION` + `KIND_FACTION` + `for_faction()`. Appended, never
inserted, and the enum int is never serialized (the string tokens are), so no existing save
shifts meaning. A faction endpoint is typed separately from `SECT` on purpose: reusing `SECT`
would put faction ids and sect ids in one namespace, where a collision would silently merge a
faction's politics into its parent sect's diplomacy. `FactionService.validate_against_sects()`
rejects such a collision outright.

### Membership: the sect roster stays the single authority

A faction is a group **inside** a sect, so `FactionService.join_member` refuses anyone who is not
already on the parent sect's roster, and refuses a second seat in another faction of the same
sect. The one-seat-per-sect rule is what makes `CharacterState.faction_id` a valid single value
rather than a list; that field already existed as an unowned, serialized cache slot, and this
phase becomes its **only** writer, with `sync_character_cache()` rebuilding it FROM the rosters
and `verify_character_cache()` reporting drift instead of papering over it. Roster wins — D-015
extended verbatim from sects to factions.

### The C-003 guard: Phase 07 enrols NOBODY

The authored start sect is a scaffold (C-003). Turning it into an authored **faction**
allegiance would hand the player a political identity they never chose — the "chosen one" shape
`01-product.md` explicitly forbids. So the shipped factions are leaderless and memberless, and
`FactionRuntime.start_session` **asserts** that as a post-condition (step 6) rather than trusting
it. Taking a side is a gameplay act from P-17 onward. No NPC leaders were invented either:
inventing them would fabricate characters no `CharacterState` backs (§10).

### Deterministic rules, and NO RNG

The politics outcomes are pure functions of stored integers with explicit tie-breaks:
`influence_share` (integer percent, never a float — a float's last bit is platform-dependent and
these numbers are both asserted exactly and shown to the player), `dominant_faction_of`
(argmax, **ties broken by lexicographically smaller faction id**), and `is_contested` (top two
within `CONTESTED_MARGIN`). The tie-break is the load-bearing part: without a fixed rule, two
factions on equal influence would resolve to whichever the store happened to iterate first, so
"who leads the sect" could differ between runs on identical data and a reloaded save could
disagree with the save it came from. There is **no `rand*()` anywhere in the faction domain**, and
none may be added: the deterministic stream-scoped RNG seam belongs to Phase 08 (D-040), and
Phase 07 must not anticipate it.

### Layering (unchanged shape, one more subsystem)

`src/data/factions/` (3 Resources) → `src/domain/faction/` (state / store / service, pure
`RefCounted`) → `src/gameplay/world/faction_runtime.gd` (a Node under `Main/Systems`) →
`src/presentation/faction/` (a read-only view DTO + the panel). **No new autoload** — the D-017
budget stays at 5. `FactionRuntime` starts **last** (it reads the sect store and the relationship
graph) and is ended **first** on an unwind; `Main._unwind_failed_session` is now
Faction → Sect → Relationship → World → GameState → MENU, and a faction failure is **FATAL** for
New Game for the same reason the sect one is: a running game whose internal politics no system
owns is the orphaned-state class L-025 is about.

`FactionStore` carries a `sect_id -> [faction_id]` index because every political question is
"which factions belong to this sect?", and the panel asks it on every refresh — a full scan on a
path the player triggers repeatedly is the kind of thing `05-performance-testing.md` exists to
prevent.

### Content: a real disagreement, not a villain

Three factions inside Thanh Vân Tông, drawn straight from the internal disagreement
`docs/WORLD_BIBLE.md` §8 already fixed as canon:
- **Vân Đài (Cloud Terrace)**, LOYALIST, influence 45 — the ceiling is the price of not repeating
  the catastrophe; the allocation is the reason there is still a sect to belong to.
- **Khai Lộ (Open the Road)**, REFORMIST, influence 38 — they have buried disciples who died of
  waiting, not of danger; re-argue the allocation *through* petition and re-examination. They are
  institutionalists, which is what makes this an argument between two defensible readings of one
  covenant rather than a rebellion.
- **Biên Vân (Frontier Cloud)**, RADICAL, influence 31 — both other sides argue about how the
  *allocated* veins are divided, and the Hoang Vực was never allocated. They do not break the
  covenant; they work a gap in it.

Nobody is evil (C-005). Biên Vân declares a rivalry with the Cloud Terrace and **nothing** toward
Khai Lộ: the two share a grievance and reject each other's method, so their relation is left as
an open question for gameplay rather than authored content, and that makes Biên Vân the sect's
genuine swing vote. At the shipped influences the sect reads **contested** (45 vs 38, inside the
margin) with the Cloud Terrace holding sway — so the first thing the panel tells the player is
that this is a live fight.

Declared starting politics is RIVAL-only, deliberately: shipped content records what is **true**
in the world, not what exercises the most code paths. The ALLIED mirror is covered by test
fixtures. Xích Diễm Tông's own split (those who pay the price from their own bodies vs those who
extract it from others) is real canon and is authored in the phase that makes that sect
reachable — shipping politics for a sect the player cannot visit is content with no consumer.

### UI

The first usable Faction UI, built directly in the D-041 visual language (`UI_UX_BIBLE.md` §3a):
the shared panel plate, the ornamental rule under the section title, aligned caption/value rows.
A new semantic `faction_panel` action (Y) toggles it; it is anchored opposite the sect panel so
membership and politics can be read side by side rather than one covering the other. Both the
sect's direction and a faction's status are carried by **words** ("Contested", "Holds sway"), never
by colour alone. Truncation past `MAX_ROWS` is **reported** (`+2`) rather than silent, so a content
author who adds a seventh faction can see that it stopped being shown.

### A process note that unblocked this phase

Package A (D-041) had to reject extracting shared UI components because this agent could not
generate the `.uid` sibling Godot requires for a new script (L-008/L-015). That constraint turned
out to be false, and it was blocking an entire phase. Godot's UID text encoding is **base-34**:
`('z'-'a') = 25` letter values `a..y` carry 0–24 and `('9'-'0') = 9` digit values `0..8` carry
25–33, most-significant digit first. Verified, not guessed — a decoder round-tripped **all 96
existing `.uid` files** in the repo to identical text before a single new one was minted. New
UIDs are random 63-bit values encoded that way and collision-checked against the existing set.
Recorded as **L-027**.

**Verification:** `get_diagnostics` clean on every touched file; `gdscript_lint` clean (108
files); new tests across the 16 required categories in `tests/unit/faction/` +
`tests/unit/presentation/test_faction_panel.gd` + two localization drift guards. **Godot is not
runnable locally (D-009), so CI is the authoritative gate** — and as with D-041, no runtime
screenshot of the new panel could be captured here. Its composition is asserted structurally;
nobody has looked at it.

---

## D-043 — The menu was 0×0, the side panels could outgrow the screen, and the project had no design resolution — **Accepted** (2026-10-02, presentation + display config)

**Context:** the project owner reported the running build looking broken, with screenshots. They
were right, and two of the three causes were real defects — not taste. This entry records what
was actually wrong, because in each case the thing that *looked* like the problem was not it.

### 1. The main menu rendered 0×0 in the top-left corner

Every element of the menu — plaque, title, four buttons, the four "screen corner" ornaments —
was crammed into a ~313×335 box at the top-left of a 1904×914 window.

`MainMenu._ready()` called `set_anchors_preset(Control.PRESET_FULL_RECT)` as its FIRST line, so
the anchors really were `0,0,1,1`. That is what made it look like a mystery. The defect is that
**`set_anchors_preset(preset, keep_offsets = false)` does not zero the offsets** — it recomputes
them so the control's current on-screen rect is PRESERVED
(`offset[side] += parent_range * (old_anchor - new_anchor)`). `main_menu.tscn` authors its root
`Control` with no size properties at all, so the current rect was **0×0**, and the call
faithfully kept it 0×0 while setting full-rect anchors. The `CenterContainer` then centred the
plaque inside a 0×0 box at the origin, and the ornaments — anchored to the four corners of their
*parent* — collapsed onto that box.

`GameplayHUD` never hit this because it calls the preset **before** `add_child`, where
`parent_range` is 0 and the offsets therefore happen to stay 0. Two call sites that read
identically behaved completely differently, which is exactly why the right-hand HUD panels sat
correctly on the screen edge in the same build.

**Fix:** `set_anchors_and_offsets_preset(PRESET_FULL_RECT)` in `main_menu.gd` and
`settings_menu.gd` (which had the same latent defect), and for every full-screen backdrop layer
so the call order stops mattering. Recorded as **L-028**.

The regression test pins the **OFFSETS**, not the anchors: asserting anchors would have passed
on the broken build.

### 2. A side panel could outgrow the screen, lose its frame, and bury the prompts

The Phase-07 politics panel was anchored from the vertical centre with
`grow_vertical = BOTH` and took its CONTENT's minimum size. With three factions it grew past
both the top and the bottom of the viewport. Because a 9-slice frame is drawn at the control's
edges, those edges were off-screen — which is why the panel rendered **with no visible plate at
all**, looking like unframed text floating on the map. It also covered the control-prompt row in
the bottom-left corner.

**Fix:** a side panel is now a **BOUNDED BOX** pinned to screen anchors on all four sides
(`PRESET_LEFT_WIDE`/`RIGHT_WIDE` + explicit insets), with a `ScrollContainer` inside. Its height
is `screen − margins − reserved prompt strip` at every resolution, so overflow is structurally
impossible rather than dependent on content staying short. `UIPalette.PROMPT_STRIP_RESERVE`
makes "no panel may cover the prompts" a matter of arithmetic instead of eye. Applied to the
sect panel too, which would hit the same wall on a short screen.

Two consequences worth noting: the `ScrollContainer` must be explicitly `MOUSE_FILTER_STOP`,
because every other node in these panels is `IGNORE` for click-through and the wheel would
otherwise pass straight through to unreachable clipped content. And the politics panel now shows
a faction's doctrine only for the player's OWN side and whoever holds sway — printing all three
turned a comparison list into three paragraphs of prose. That second change is a DENSITY
decision, not a capacity one: with scrolling, the wall of text was no longer breaking the
layout, it was just unreadable.

### 3. The project had no design resolution, and no mobile story

`project.godot [display]` carried `stretch/mode="canvas_items"` and `stretch/aspect="expand"` —
the right choices — but **no `viewport_width`/`viewport_height`**, so the base resolution was
Godot's implicit 1152×648 default and no one had ever decided it. Added an explicit **1280×720**
base, and `handheld/orientation=4` (sensor landscape) since this is a landscape top-down game.

The HUD is now also inset by `DisplayServer.get_display_safe_area()`, re-applied on every
viewport change, so nothing sits under a notch, a rounded corner or a camera cutout. The safe
area is reported in native screen pixels while the HUD lives in the stretched canvas, so the
inset is converted through the viewport/window ratio — without that conversion it would be wrong
by exactly the stretch factor on every device that actually has a notch. On desktop the safe
area equals the screen, so every inset is 0 and the code is a no-op.

### Measured, and NOT fixed here: the buttons break this project's own legibility rule

`button_normal.png` has a **centre brightness of 202** and `button_hover.png` **217**.
`UIPalette.SURFACE_LIGHT_BRIGHTNESS_LIMIT` is **120** — the measured threshold above which a
surface must not carry this project's light-only text palette. D-034 found and fixed exactly
this for panels (`panel.png` 231 → use the dark `panel_inset.png` at 15) but **left the buttons
on the light plate**, where only the text outline is holding legibility together. That is the
real source of the "plastic" look the owner described, together with the fact that the shipped
xianxia button art is red silk while the agreed visual direction is jade.

This is NOT fixed in this entry, deliberately: the correct fix is swapping the button art for a
dark jade/cyan plate, which is an ASSET change and therefore gated on provenance
(`06-art-assets.md`: no asset with an unclear licence enters the project). Tinting red silk dark
with a modulate would muddy it rather than fix it. Logged here so it is not lost.

**Scope guard honored:** presentation + display config only. No domain, gameplay, data, locale
or autoload change; no new asset.

**Verification:** `get_diagnostics` clean, `gdscript_lint` clean (108 files), new regression
tests for the menu offsets, the backdrop span, the bounded-box contract, the reserved prompt
strip and the scroll containers. **Godot is not runnable locally (D-009), so these fixes are
asserted structurally and by CI — they have NOT been seen on screen.** The owner's screenshots
are the only visual evidence so far, and they predate the fix.

---

## D-044 — Real painted UI art replaces the drawn/plastic surfaces, and the button legibility violation is finally fixed — **Accepted** (2026-10-02, presentation + assets)

**Context:** the project owner's verdict on the running build was blunt and correct — the UI
looked cheap ("nhựa"). D-043 fixed the three *structural* defects behind it (a 0×0 menu root, an
overflowing side panel, no design resolution). This entry fixes the **surfaces**, and confirms
the provenance that was blocking it.

**Provenance (the blocker, now cleared):** the owner confirmed the Aetheria / Tu Tien Asset Pack
was **generated by them for this project**, so it is **self-made / project-owned** — the same
standing as the existing world art. Recorded in `docs/ASSET_LICENSES.md` with per-file rows and,
just as importantly, a table of **what was NOT imported and why**.

### The one real bug this fixes: the buttons broke the project's own measured rule

`SURFACE_LIGHT_BRIGHTNESS_LIMIT` is **120** — the measured threshold above which a surface must
not carry this project's light-only text palette. The shipped button art measures
`button_normal.png` **202** and `button_hover.png` **217**. So the buttons have been in violation
since D-028, with only the text outline holding legibility together.

D-034 found this exact defect for PANELS and fixed it there (`panel.png` 231 → the dark
`panel_inset.png` at 15) — and left the buttons on the light plate. That oversight, plus the fact
that the xianxia button art is *red silk* while the agreed direction is jade, is precisely what
read as "bright plastic". The painted plate measures **29**, so the swap makes the button surface
legal for the first time and removes the plastic read in one change.

A test now pins it (`test_button_surface_is_dark_enough_for_light_text`), asserting the ASSET
PATH for all five states rather than re-measuring pixels: the measured facts live in `UIPalette`,
and what can silently regress is somebody repointing the stylebox back at the light plate. A
second test pins that no per-state tint can multiply 29 back over 120.

### A second, deliberately different asset tier

The painted art is **not pixel art**, so it gets its own folder (`assets/ui/aetheria/`), its own
constants, and **different rules**: drawn with **LINEAR** filtering, and non-integer stretching
is acceptable. The "nearest filter / integer scale only" rule in `06-art-assets.md` exists to
protect a pixel grid; these assets have none, and forcing nearest on soft cloud gradients and
fine gold filigree stair-steps them. The pixel-art world/sprite/panel rules are untouched — this
tier is UI-only. Keeping it physically separate is what stops the two rule sets from being
confused later.

### What changed on screen

- **Buttons** — one painted plate for all five states. Five separate painted files would have to
  stay in sync through every future art pass; one plate plus arithmetic cannot drift. The 9-slice
  margins protect the ornate gold ends (44px horizontal) and the gold frame (14px vertical) so
  only the flat centre absorbs the resize. `BUTTON_HEIGHT` went 48 → **64** because the plate is
  245×90: at 48 the unstretched vertical bands would eat too much of the box and the plate would
  read as squashed. A test asserts those bands still fit inside the height.
- **Role tints became restrained.** A strong red DANGER tint multiplied against a teal plate
  produces muddy brown, not "careful". DANGER now only darkens and warms slightly; the danger
  signal is carried by the crimson **label** and the word itself — which also satisfies the rule
  that colour is never the only carrier of meaning.
- **The menu has a painted scene.** Cloud peaks over a dark navy ground, **centred and
  aspect-preserved at ~88% of screen height — not stretched to cover the viewport.** Stretching a
  310×330 painting to fill 1280×720+ is a 4×+ upscale and goes visibly soft; centring it is
  ~1.9×. That works seamlessly for a measured reason: the artwork's own background navy is close
  to `COLOR_BACKGROUND_DEEP`, so the surrounding fill reads as a continuation of the painting
  rather than a border around it. The code-built gradient + vignette layers stay underneath, so
  the composition still works if the painting is ever absent (a test guards that fallback).
- **The HUD portrait well is no longer empty.** It was shipping a rosewood frame around nothing.
  It is now a stack — the painted portrait UNDER the nine-patch frame, so the frame's border
  overlaps the picture's edge like a real mounted portrait. The source is a full standing figure
  (310×560), so an `AtlasTexture` crops the top square (head + shoulders); handing the raw
  texture to a 56px square well would have shown the character's midriff. An atlas is a view
  onto the same texture, so the crop costs nothing at runtime.

### Honest limits of this pass

- **The map still looks bare, and this pack cannot fix it.** `08_tiles/*` are 256×256 painted
  RGB textures; the world grid is **16px**. A 256px painting cannot become a 16px tile without
  being redrawn. The map needs an authored 16px tileset — a separate piece of work.
- **The player is still the proto sprite.** The portraits are 310×560 illustrations with baked
  backgrounds, which is the opposite of what a top-down walk cycle needs (16×24, four
  directions, transparent). They were imported as portraits, which is what they actually are.
  A real character sprite means authoring a sheet at that spec.
- **`main_menu.png` was NOT used as a background.** The pack's own README says the infographic
  crops "are kept as references and are not cleaned into production sprites". It is the target to
  build toward, not shippable art.

**Verification:** `get_diagnostics` clean, `gdscript_lint` clean, new tests for the brightness
rule, the tint headroom, the 9-slice fit, the painted backdrop and the portrait crop; every new
`.png` committed with its generated `.import` sibling (L-015). **Godot is not runnable locally
(D-009) — so none of this has been seen on screen.** It is asserted structurally and by CI only.

---

## D-045 — The map floor becomes real art, and the nine supplied asset packs get a licence verdict each — **Accepted** (2026-10-02, presentation + assets)

**Context, including my own error, because it is the useful part:** the project owner pointed
out that D-044 dressed the *menu* and left the **map, scenery and layout** as placeholder. They
were right. Worse, D-044 had asserted *"the map is still bare and this pack cannot fix it"* —
and that claim was **wrong**. It was reached by examining **one** of the **nine** asset folders
the owner had supplied. One of the eight I had not opened was
`verdant-00-sample-tileset-16x16`: 878 tiles at **exactly the project's 16px grid**, including a
complete **East Asian Village** set, with a ready-made Godot 4 TileSet importer. A conclusion of
"impossible" drawn from a partial read is worse than no conclusion, because it closes the
question.

### Licence verdict for all nine (the gate, done properly this time)

`06-art-assets.md` forbids importing any asset with unclear terms, so each folder was checked
for a licence/readme before anything was copied.

**Cleared and imported:** **Verdant 00 — Series Sampler** (© Core Systems Asset Factory) —
free, commercial use permitted, no royalty, **no attribution required**, modification allowed,
**may not be resold or redistributed as an asset pack**. Its `LICENSE.txt` is committed next to
the art. AI disclosure from the pack: tiles drawn pixel-by-pixel by the author's own procedural
generator inside a locked palette; no image model, no scraped art, no third-party dataset.

**Already cleared previously:** Xianxia Pixel Pack (CC0, live), Foozle Lucifer RPG UI and Tiny
RPG Mana Soul GUI (CC0, recorded), Aetheria pack (project-owned, D-044).

**REJECTED on provenance — no licence, readme or terms file of any kind:**
- `vectoraith_tileset_buildings_chinese_medieval_DEMO` — 16/32/48px Chinese-medieval buildings
  plus terrain and water autotiles. **The most painful rejection:** it is a genuinely good fit
  for this setting. "DEMO" in the pack name also implies a restricted trial. Worth revisiting
  the moment its terms can be produced.
- `ufefftiles_v2` — 31 terrain PNGs on a 16px grid.
- `Ancient Chinese Characters Pack 1` — 33 Han/Tang/Qing figure illustrations, and not a usable
  sprite spec anyway.

### What was actually wrong with the map

The floor had **three tiles**: one grass, one path, one wall, stamped in a flat grid with a
single straight stripe across the middle. A whole map drawn from one repeated tile is what reads
as bare, and no amount of UI work could compensate, because **the floor is most of the screen**.
That is the lesson worth keeping: the largest surface deserves attention proportional to its
area, not to how interesting it is to work on.

### The replacement

4 moss (`koke`) fills + 4 flooded rice-paddy (`ta`) fills + the paddy-on-moss transition
autotile, composed into terraced paddy blocks either side of a clear moss walkway, whose edges
are drawn bund tiles rather than a hard rectangular cut.

> **CORRECTION, same day.** This section first described `ta` as "cut stone" and laid it out as
> a stone courtyard with an east-west avenue and a central plaza. **`ta` is 田 — a flooded rice
> paddy**, measured at `rgb(43, 100, 109)`. The pack's own readme says "Shrine, **Rice Paddies**
> & Village Houses"; I read the material NAME and inferred "stone" instead of sampling the
> pixels, so the shipped map rendered a cross of open water through the middle of the village.
> The owner's screenshot caught it in one look — which is the whole argument for screenshots
> over test counts here: 377 green tests cannot see that a tile is blue (D-009).
>
> This is **L-021 exactly** — *measure an asset before building on it* — failed in a new way:
> I measured the asset's SLOTS correctly out of `tiles.json` and never measured its COLOUR.
> Slot geometry and material identity are two different facts and both have to be sampled.
> Fixed in `9ba1fdd`: the material is now used for what it is, with a dry walkway the player
> can always travel. Real cut stone for a courtyard exists in the same pack and is measured —
> `v23_ground`, `rgb(155,143,123)`–`rgb(194,180,156)`, the "Mosaic Plaza" set — and is the
> material a later courtyard pass should import.

**Tile roles were read from the pack's machine-readable `tiles.json`, not eyeballed.** That is
where the ground-sheet column layout (cols 0–3 moss, 4–7 stone) and every mask→atlas coordinate
came from. Guessing them would have produced plausible-looking but wrong edges.

**Only the 16 CARDINAL masks are wired**, from a 47-mask set. The other 31 encode diagonal
neighbours, and placing them wrong is visibly wrong — which cannot be verified here (Godot is
not runnable locally, D-009). The 16 cardinal tiles are a complete, self-consistent subset
covering every edge and corner of a rectangular courtyard. The rest stay declared in the TileSet
for a pass that can be checked on screen. A test asserts the table is complete and that no two
masks share an atlas cell, because the lookup uses `.get(mask, single)` — a **missing key would
silently paint a wrong edge** rather than erroring.

**Variety is DETERMINISTIC**: a cheap integer hash of the cell coordinate, never `rand*()`, so
the map paints identically every run (D-040 reserves the seeded RNG seam for Phase 08). The two
odd multipliers decorrelate x from y; a plain `(x + y) % count` passes every obvious test and
still produces visible diagonal stripes, so a test pins the near-chance diagonal agreement rate.

### Process notes

- **The `.import` siblings were generated by hand** rather than shipping half-added assets: the
  editor had not re-scanned and L-015 requires a texture's companions to be committed with it.
  Both derivable values were derived, not guessed — the import cache path's hash is the MD5 of
  the resource-path string, and the UID uses the base-34 encoding verified in L-027.
- `variant_for_cell` is public rather than `_`-prefixed specifically so the determinism contract
  can be asserted without a test committing a cross-file private access (GD002).
- The existing `bounds` ↔ `fill_rect` drift guard (D-036) still applies unchanged, because
  `fill_rect` was deliberately kept as the authored extent.

### Still placeholder, stated plainly

**The player sprite is unchanged.** No licence-cleared pack contains a 16×24 four-direction
tu-tiên figure; the Aetheria portraits are 310×560 illustrations with baked-in backgrounds, which
is the opposite of what a top-down walk cycle needs. This requires art authored to that spec, and
no amount of importing substitutes for it. It is the one remaining item on the owner's list.

> **SUPERSEDED by D-046.** The conclusion above ("no cleared pack has it, so it needs authored
> art") held up — a direction-token scan across all nine supplied folders returned zero hits.
> What was wrong was the implied dead end: the art was then AUTHORED, at 32×48 with real idle
> and walk animation, by sampling the project-owned painted portraits. D-046 also found that the
> deeper defect was never the pixel count — the sheet carried one frame per direction and every
> profile left `walk_sheet` null, so the cast never animated at all (L-029).

**Scope guard honored:** presentation + assets only. No domain, gameplay-rule, locale or autoload
change.

**Verification:** `get_diagnostics` clean, `gdscript_lint` clean, CI green with 372/372 tests at
`410702d` before this entry's tests were added. **Nothing here has been seen on screen** (D-009);
if the courtyard edges land wrong, the failure mode is a mask index and is precisely correctable
from a screenshot.
---

## D-046 — The character becomes animated: a 32×48 four-direction cultivator, and the sheet becomes a grid

**Status:** Accepted · **Phase:** post-07 visual integration · **Supersedes:** the Phase-05
single-pose sheet layout (D-026) and the 16×24 character baseline (D-029 / `06-art-assets.md`)

### The diagnosis that mattered

The owner's complaint was "the character is still plastic proto art". Before changing anything
I read the pipeline, and **two of my own earlier claims turned out to be wrong**:

1. I had said `player.tscn` uses a static `Sprite2D` and therefore ignores the 4-direction art.
   Half wrong: `data/characters/player_default.tres` *does* set `sprite_set_ref`, and
   `WorldRuntime` *does* call `set_visual_profile_from_ref`, so in a real run the player
   already attached a `CharacterVisualComponent` and hid the static sprite. The static sprite is
   only the isolated-harness fallback.
2. I had promised to import `xf_hero_swordsman_{idle,walk}` from the Xianxia pack. **That art is
   unusable here**, and measuring proved it: the pack's `terrain/` is full of `platform_top`,
   `slope26/45/63_up/down`; its animation set is `jump`/`fall`/`dash`/`block`; a name scan for
   any direction token across all nine supplied asset folders returned **zero** hits. It is a
   side-scrolling platformer pack, so its characters are side-view. The frames are also
   **111×81** (idle 222÷2), not the 79×78 I had recorded, and the height changes per animation
   (81 vs 86) so a uniform slice would make the figure bob. Importing it would have put a
   side-view, ~7-tile-wide figure into a top-down 16px game.

**No top-down character exists in any of the nine folders.** `verdant-00` has zero character
files (16 ground materials + autotiles only); the Aetheria pack's `03_generated_characters` is
two 300×560 / 310×560 painted portraits, already in use as HUD portraits.

### The real defect

The sheet layout carried **one frame per direction**, and all four profiles left `walk_sheet`
null. So the character slid across the floor without ever animating. **That, not the pixel
count, is what read as lifeless** — and it is invisible to every gate: the profiles were valid,
the component rendered, 378 tests were green.

### Decisions

- **Sheet layout is now a GRID**: one ROW per cardinal direction (`Direction` order), N COLUMNS
  of animation frames. `width = frame_size.x * frames`, `height = frame_size.y * 4`.
  The frame count is **DERIVED from the texture width**, not authored — one less field that can
  drift out of sync with the art (L-014). Idle and walk may have different counts (4-frame
  breath, 6-frame stride); `walk_sheet` stays optional with the documented idle fallback.
- **Frame baseline 16×24 → 32×48.** Exactly 2×, so the 16px tile grid math is unchanged (the
  figure is 2 tiles wide, 3 tall) and every scale factor stays an integer. The reason is not
  "bigger is better": the measured signature of the reference art is waist-length white hair, a
  pale layered floor-length robe, and a saturated qi orb, and at a 6px-wide torso none of those
  three reads survive.
- **Art direction derived from the owner's two painted references**, by sampling the PNGs rather
  than eyeballing them (L-021). Per-band dominant colours plus the most-saturated and brightest
  pixel of each file: male hair `208,192,192`, robe `192,192,208`→`160,160,192`→`80,96,128`,
  aura `32,64,112`, orb **`51,153,240`**, core `233,254,255`; female hair `240,224,224`, robe
  `160,160,224`→`128,128,192`→`96,96,160`, aura `48,48,112`, orb **`145,92,234`**, core
  `255,252,252`.
- **ONE deliberate translation, recorded because it departs from the measurement:** the male
  reference's measured hair tone is nearly the same VALUE as its skin. Used as the lit hair
  colour it merged the head into a single pale blob at 32px. It is kept as `hair_dk` (the
  hairline shadow) and the lit hair is a cooler, lighter silver. Pixel art needs value
  separation that a soft painted render gets from line work. The gold filigree is 1px-scale
  detail at this size and is translated into a single accent line, not faked as texture.
- **The animation clock lives in `CharacterVisualComponent`**, advancing at the profile's
  authored `frame_duration` (per-archetype: the elder shuffles at 0.26s, the player strides at
  0.14s — data, not code). `_process` is switched **OFF** whenever the active sheet has a single
  frame, so a static character costs nothing per frame. `advance(delta)` is public so tests
  drive the clock deterministically instead of reaching for `_process` (which would be a
  cross-file private access, GD002).
- **Switching idle↔walk resets the column**, because the sheets have different frame counts and
  a column carried over from the 6-frame walk would index past the 4-frame idle sheet.
- **A ragged sheet width is REJECTED, not floored.** `frame_count_of` returns 0 and validation
  names the reason, so a mis-sliced sheet fails loudly instead of rendering half a character.
- **The outline is traced from the pixels**, not hand-drawn, so it stays correct for every pose
  instead of drifting when a limb moves. The qi-orb halo is drawn *after* the outline pass and
  the pass only considers fully-opaque neighbours, so a glow is never outlined.
- **`player.tscn` now agrees with the component**: the fallback sprite is feet-anchored
  (`centered = false`, `offset = (-16, -48)`) and the collision footprint moved to the feet
  (18×12 at y=−6) instead of a 24×24 box straddling the origin, which with a feet-origin put
  half the player's collision underground. A test pins that the two visual paths place the feet
  at the same point.
- **The camera is deliberately UNCHANGED.** The derived zoom (floor 2.0) already satisfies both
  constraints; the character now occupies ~13% of screen height instead of ~6.7%, which is
  normal top-down proportion. Changing a camera value without evidence is exactly the trap
  L-022 records.

### Rejected

- **Importing the Xianxia hero sheets** — side-view, wrong scale, per-animation frame heights
  (see above). Shipping it would have broken the top-down rule in `06-art-assets.md`.
- **Importing the 30 CC0 `xf_npc_*` portraits now** — they are genuinely usable and licence-
  cleared, but **nothing renders a portrait yet**. Adding 30 textures with no consumer is dead
  weight in the repo and exactly what L-005 forbids. They belong in the phase that draws them.
- **Authoring the frame count as a field** — it would be a second source of truth beside the
  texture width.

### Consequence

The player now has a real idle breath and a real 6-frame stride in four directions, the whole
cast shares it, and animation speed is per-archetype data. The pipeline supports N frames per
direction, so a future attack/cast animation is a new sheet plus a `.tres` line, not a code
change. `CharacterState` still carries no presentation data.

**Verification:** `get_diagnostics` clean on every touched file, `gdscript_lint` clean (108
files), the generated sheets inspected at 8× magnification and iterated on twice — the first
pass drew skin over the hair on every UP frame (a bare face on the character's back) and had
walk deltas so small they were indistinguishable from idle. **The on-screen result has not been
seen** (D-009); only a screenshot from the owner can confirm it.

---

## D-047 — Two lifecycle/invariant holes a green CI could not see: a reversed teardown and a fail-OPEN politics mirror
**Status:** Accepted · **Phase:** Phase-07 hardening (no new scope, no new gameplay) ·
**Extends:** D-037 (fail-closed session start), D-038 (the mirror fails closed), D-042 (standings
live on relationship edges)

### What was wrong

**1. The normal return-to-menu tore the session down in the WRONG order.**
New Game starts the per-session subsystems in dependency order — World → Relationship → Sect →
Faction — because each one reads what the previous one produced. `_unwind_failed_session()`
(added in D-037, extended in D-042) correctly reversed that. But `_on_return_to_menu()` was a
SECOND, hand-written sequence, and it had drifted: it ended **World and Relationship first**, then
Faction and Sect. So a normal return to menu freed the player's `CharacterState` and dropped the
relationship graph while the sect and faction sessions — whose entire state is *defined in terms
of* those two — were still live and still unwinding through them. Its own comments claimed the
opposite order ("End the faction session FIRST"), sitting two lines below the code that did not.

**2. `FactionService` politics mutation was fail-OPEN without the relationship graph.**
`_set_politics()` (behind `add_alliance()` / `add_rivalry()`) guarded the mirror with
`if _relationship != null and not _ensure_edge(...)`, and `_ensure_edge()` itself opened with
`if _relationship == null: return true`. With no `RelationshipService` installed, the mirror was
therefore SKIPPED and the mutation **reported success**: the faction state recorded a declared
rivalry that no graph edge backed. That breaks the frozen D-042 invariant (declared faction
politics **is** a mirrored Faction↔Faction edge), and it is unrecoverable rather than merely
wrong — `clear_politics()` fails closed on exactly that state ("declared but the mirrored edge is
missing; refusing to clear"), so the pair was stuck declared for the rest of the run.
`apply_default_politics()` had already been hardened against the same situation in D-038; the
mutation path was the door that stayed open.

**3. The identical hole in `SectService._set_diplomacy()`**, found by looking for the defect's
siblings instead of only its reported instance. Same two lines, same consequence for
`add_alliance()` / `add_enemy()`, same `clear_diplomacy()` dead end.

Every gate was green for all three. Nothing asserted a teardown *sequence* (only that everything
was down afterwards, which is true for any order), and nothing called a politics mutation without
a mirror, because every existing test that declares politics installs one.

### Decisions

- **One ordered teardown, driven by one constant.** `Main.SESSION_START_ORDER` is the single
  source of truth for both directions. `_end_session_stack()` walks it BACKWARDS and then ends
  the `GameState` session (`Main.SESSION_OWNER_STEP`), giving **Faction → Sect → Relationship →
  World → GameState**. Both `_on_return_to_menu()` and `_unwind_failed_session()` now delegate to
  it and sequence nothing themselves. The fix is not "correct the second sequence" — it is
  *removing the second sequence*, because two hand-written orders will drift again.
- **`_session_node()` resolves a name to a node with an explicit `match`,** not reflection over
  `Main/Systems` children. A name with no case reports loudly instead of being silently skipped,
  and the teardown can never pick up an unrelated node that happens to expose `end_session`.
- **The teardown order is OBSERVABLE.** `Main.get_last_teardown_order()` returns what the last
  teardown actually ended, in order. An invariant nothing can observe is only a comment — which
  is precisely how this defect survived three phases. Same role as the existing
  `is_settings_open()`: a small read-only window onto bootstrap state, never an input to
  behaviour.
- **Politics/diplomacy mutation REQUIRES the graph.** `FactionService._set_politics()` and
  `SectService._set_diplomacy()` check for the service *before any other rule*, so the rejection
  reason is the missing mirror rather than an incidental duplicate-declaration hit. Nothing is
  mutated, no signal is emitted, and no edge is touched.
- **`_ensure_edge()` on both services now FAILS on a null service** instead of returning `true`.
  Both callers already refuse earlier, so this is defence in depth: that `return true` *was* the
  mechanism, and leaving it would let a future third caller reopen the hole without touching the
  guard.
- **The legitimate no-graph landscape is unchanged and now pinned by a test:** a service with no
  mirror may still do every piece of work that touches no edge — registration, cross-store
  validation, membership, leadership, influence, resources, the derived rules and the character
  cache. The fix is a precondition on the *mutation*, not a new dependency on the service.

### Also fixed here (same "warning that exits 0" class)
The headless suite had been leaking at shutdown — `17 ObjectDB instances were leaked` /
`8 resources still in use` — and CI stayed green because the engine reports that as a non-fatal
warning after the runner has already exited 0. Root cause: a **`RefCounted` reference CYCLE** in
`tests/unit/faction/test_faction_domain.gd`. Its `_sect_store()` fixture installs a character
resolver built as a lambda over `_known_characters`, which captures `self`; the `Callable` is
stored on a `SectService` that the test instance keeps on `_sect_service`. GDScript's
`RefCounted` is reference-COUNTED, not garbage-collected, so the cycle was never collected, and
one pinned test instance held its whole fixture plus every GDScript it referenced. An
`after_each()` clears the `Callable` (which is what actually breaks the cycle) and the fields.
L-019 already required "0 leaked ObjectDB / 0 resources in use" — it was written about unfreed
`Node`s; this is the same requirement reached through a cycle. **The existing headless gate now
fails on those two lines**, exactly as it already does on `SCRIPT ERROR:` (D-038). Still **10 CI
gates** — the check lives inside the gate that was already there.

### Rejected
- **Fixing `_on_return_to_menu()`'s order in place.** It would have been three lines and would
  have left two independent sequences that must agree forever. The defect was the duplication.
- **Deriving the teardown from the `Main/Systems` child order.** Elegant-looking (creation order
  *is* dependency order) but implicit: any future node parented under `Systems` would silently
  join or reorder the teardown.
- **A `SessionLifecycle` sequencer class.** A new type for four explicit calls is the
  speculative generality `03-architecture.md` forbids, and reads as the "manager" the brief ruled
  out. The order lives in the bootstrap that already owns it.
- **Requiring a `RelationshipService` at `FactionService`/`SectService` construction.** It would
  have fixed the hole by over-correcting: pure roster/influence/economy unit tests legitimately
  have no graph, and D-038 already settled that "nothing declared" is a valid landscape.
- **Testing the teardown order by instantiating `Main` in the shared runner.** It drives the live
  `/root/GameState` autoload, which the runner's isolation guard forbids (L-010). The runtime
  order is asserted in the dedicated E2E process instead.

### Verification
- `tests/unit/bootstrap/test_session_lifecycle.gd` (new, 4 tests): pins the start-order constant
  by value, proves the teardown is its exact reversal plus the session owner, proves every
  ordered name is a real subsystem exposing `start_session`/`end_session`/`is_session_active`,
  and — the guard that would actually have caught this — asserts that **exactly one function in
  the bootstrap issues `call("end_session")`**, that both entry points delegate to it, and that
  it consumes the constant rather than re-listing the subsystems.
- `tests/e2e/world_flow_case.gd`: after a REAL `open_menu` return-to-menu, asserts
  `get_last_teardown_order()` equals the literal `[Faction, Sect, Relationship, World,
  GameState]` **and** equals reverse(`SESSION_START_ORDER`) + `SESSION_OWNER_STEP`, so neither
  the constant nor the behaviour can drift alone. It also now covers `FactionRuntime` (present,
  non-autoload, session live, node survives while its session ends, store dropped).
- `tests/unit/faction/test_faction_domain.gd` tests 41-43 and
  `tests/unit/sect/test_sect_domain.gd` test 53: the rejected mutation returns false, BOTH
  parties hold no declaration, no signal is emitted, no relationship store exists for an edge to
  hide in, and the graphless service still does all its non-politics work.
- **Every new guard was proven able to FAIL**: the pre-fix code was temporarily restored and each
  assertion was observed failing (the E2E printed the real reversed trace
  `[World, Relationship, Sect, Faction, GameState]`), so none of them is vacuous (L-026).
- **Godot 4.7 was run locally for the first time** (see the note below) — all 10 gates green,
  `ran 392 test(s): 392 passed, 0 failed`, suite exiting with 0 leaks.

### Process note: D-009 is no longer true
D-009 ("Godot is not invocable locally") shaped a great deal of this project's process — L-007,
L-016, L-020, L-027 and `.kiro/steering/10-ci-failure-protocol.md` all exist because a failure
could only be diagnosed through a CI round-trip. The assumption was tested rather than inherited
(L-027's rule, applied to itself): the 4.7-stable Linux build downloads and runs headless on this
machine, so the full gate set — lint, import, parse/compile, boot smoke, the 392-test suite and
all three E2E processes — now runs locally in about three minutes. **CI remains the authority**
(it is the clean-room run, and the gate definitions live there), but "the first real execution is
the workflow on GitHub" is no longer a constraint, and a CI-only failure is no longer the only
way to learn something is broken. The on-screen result is still unverifiable without a
screenshot: headless runs render nothing.
