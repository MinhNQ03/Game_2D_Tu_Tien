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

## D-003 — Map/scene strategy: instanced scenes vs. streaming  — **Open**
**Context:** "nhiều map" + dungeons; need clean transitions with no leaks.
**Options:** (a) one PackedScene per map, loaded/unloaded via SceneRouter; (b) a streamed
/ chunked world.
**Decision:** *Undecided.* Lean toward (a) for a chapter-based top-down RPG; SceneRouter
abstraction keeps this changeable later.
**Blocking:** Phase 03 (World / Map).

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

---

## How to add a decision
Append `D-00N — <title> — <status> (date)` with Context / Options / Decision /
Consequence (or Blocking). Never silently change a shipped decision — mark the old one
**Superseded** and add a new entry.
