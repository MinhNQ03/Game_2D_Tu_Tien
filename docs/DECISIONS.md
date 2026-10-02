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

## D-002 — 3D physics engine enabled on a 2D project  — **Accepted** (2026-10-02; resolved 2026-10-03)
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
**Blocking:** Phase 3 (World).

## D-004 — Test framework: GUT vs. custom headless runner  — **Accepted** (resolved 2026-10-03)
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
**Blocking:** Phase 17 (Save).

## D-006 — Project renamed to "Aetheria"  — **Accepted** (resolved 2026-10-03)
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
**Blocking:** Phase 4 (Combat).

## D-008 — Localization backing format: CSV vs. PO  — **Open**
**Context:** `vi`/`en` from the foundation, wrapped by a `Localization` service.
**Options:** (a) Godot CSV translations; (b) gettext PO.
**Decision:** *Undecided.* Either works behind the service wrapper; lean CSV for
simplicity.
**Blocking:** Phase 1/18 (whenever the first real strings land).

## D-009 — Local headless Godot execution is unavailable to the AI agent  — **Accepted / documented limitation** (2026-10-03)
**Context:** During the Phase 0 foundation fix, the AI agent could not find or invoke a
Godot executable from the shell. Checked: PATH, common install dirs
(`%LOCALAPPDATA%\Programs`, Program Files, scoop, Downloads, itch), and the Windows
registry file association. All negative. The `.godot/` cache shows the project *was*
opened in the editor on this machine, so Godot exists but is not on the agent's PATH.
**Consequence / limitation:** the agent **cannot** run `godot --headless` locally and
therefore cannot produce a local test-run log. This is stated honestly rather than
claiming a pass that did not happen (`.kiro/steering/08-ai-review-protocol.md`:
build/run-pass is never assumed).
**Mitigations:**
- The GDScript language server IS available; all new scripts were validated with zero
  errors/warnings (static verification).
- CI (GitHub Actions, D-012) is the authoritative headless run: it installs Godot 4.7
  and runs `godot --headless --path . -s res://tests/run_tests.gd`.
- **Manual local run** (for the developer who has Godot installed):
  `godot --headless --path . -s res://tests/run_tests.gd` — expect `RESULT: PASS` and
  exit code 0.
**Action for maintainer:** add Godot 4.7 to PATH (or set a `GODOT` env var) if you want
the agent to run tests locally in future.

## D-010 — Bootstrap main-scene structure (Main / Systems / World / UI)  — **Accepted** (2026-10-03)
**Context:** Phase 0 needs a real, bootable `main.tscn`. The example structure suggested
`Main → Systems / World / UI`.
**Decision:** Adopt exactly that: root `Main` (`Node2D`, script `src/bootstrap/main.gd`)
with children `Systems` (`Node`), `World` (`Node2D`), `UI` (`CanvasLayer`). It mirrors the
presentation / gameplay / world split so Phase 1 systems attach under the right branch
instead of a God node. The bootstrap script validates the structure (loud failure) and
exposes `has_required_structure()` for the smoke test.
**Consequence:** Phase 1 hangs infrastructure/system nodes under `Systems`, maps/entities
under `World`, HUD/menus under `UI`. No gameplay added.

## D-011 — Character, Relationship, Sect, Faction, World-Simulation are CORE systems  — **Accepted** (2026-10-03)
**Context:** The game is a tu tiên world where characters, sects, factions and their
politics are central, not quest-decoration NPCs.
**Decision:** Treat Character / Relationship / Sect / Faction / World-Simulation as core,
data-driven, serializable domain systems designed up front (design-only now). They are
sequenced in `ROADMAP.md` **before** NPC / Dialogue / Quest / Story, which depend on them.
New entities = data + content, no core rewrite.
**Consequence:** new design docs (`CHARACTER_SYSTEM`, `RELATIONSHIP_SYSTEM`,
`SECT_SYSTEM`, `WORLD_SIMULATION`), schema additions, flow + roadmap + multiplayer updates.
No gameplay code.

## D-012 — Minimal GitHub Actions CI  — **Accepted** (2026-10-03)
**Context:** Repo had no CI. Phase 0 wants automated headless checks.
**Decision:** Add `.github/workflows/ci.yml` that checks out, installs Godot **4.7**
(matching `project.godot` feature tag), imports the project, and runs the custom headless
runner, failing the job on non-zero exit. It does not swallow errors.
**Verification note:** the agent cannot run GitHub Actions locally (D-009); the workflow
YAML is authored to the documented `godot-ci` conventions. First real validation happens
on push to GitHub. Manual check instructions are in the workflow comments and
`docs/TEST_PLAN.md`.

## D-013 — Document-review contradictions found during Phase 0 fix  — **Accepted / tracked** (2026-10-03)
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
4. **No contradiction found** across save/localization/performance/testing/multiplayer
   terminology — glossary in `02-game-design.md` is consistent with usage.
**Consequence:** docs updated in this pass; no open conflicts remain. Future conflicts go
here, not silently resolved.

## D-014 — Kiro Hooks for test + review automation  — **Accepted** (2026-10-03)
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

---

## How to add a decision
Append `D-00N — <title> — <status> (date)` with Context / Options / Decision /
Consequence (or Blocking). Never silently change a shipped decision — mark the old one
**Superseded** and add a new entry.
