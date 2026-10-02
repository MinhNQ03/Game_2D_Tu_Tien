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

## D-002 — 3D physics engine enabled on a 2D project  — **Open** (2026-10-02)
**Context:** `project.godot` sets `[physics] 3d/physics_engine="Jolt Physics"`, but
Aetheria is a 2D top-down game. This is likely a leftover default and may pull in
unneeded 3D physics setup.
**Options:** (a) leave it (harmless if no 3D is used); (b) remove/clear the 3D physics
setting to keep config honest for a 2D-only game.
**Decision:** *Undecided.* Lean toward (b) during Phase 0 cleanup — remove 3D physics
config since the game is 2D-only — after confirming it has no side effects.
**Blocking:** Phase 0 exit.

## D-003 — Map/scene strategy: instanced scenes vs. streaming  — **Open**
**Context:** "nhiều map" + dungeons; need clean transitions with no leaks.
**Options:** (a) one PackedScene per map, loaded/unloaded via SceneRouter; (b) a streamed
/ chunked world.
**Decision:** *Undecided.* Lean toward (a) for a chapter-based top-down RPG; SceneRouter
abstraction keeps this changeable later.
**Blocking:** Phase 3 (World).

## D-004 — Test framework: GUT vs. custom headless runner  — **Open**
**Context:** Need headless CI tests from early on. `tests/run_tests.gd` is a placeholder.
**Options:** (a) GUT (featureful, third-party addon); (b) minimal custom SceneTree runner
(zero dependency).
**Decision:** *Undecided.* Lean toward GUT unless we want zero third-party deps.
**Blocking:** Phase 1 (Core) — pin the exact headless command here once decided.

## D-005 — Save serialization format  — **Open**
**Context:** Versioned, migratable saves (`docs/SAVE_FORMAT.md`).
**Options:** (a) JSON of plain dicts via `to_dict/from_dict`; (b) Godot `Resource`
binary.
**Decision:** *Undecided.* Lean toward (a) JSON for migration-friendliness/testability.
**Blocking:** Phase 17 (Save).

## D-006 — Project renamed to "Aetheria"  — **Proposed**
**Context:** `project.godot` `config/name="New_Game_Project"`.
**Decision:** Rename to `Aetheria` (temporary working title) during Phase 0 so the
project identity matches the docs. Low risk, reversible.
**Blocking:** Phase 0 exit (cosmetic).

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

---

## How to add a decision
Append `D-00N — <title> — <status> (date)` with Context / Options / Decision /
Consequence (or Blocking). Never silently change a shipped decision — mark the old one
**Superseded** and add a new entry.
