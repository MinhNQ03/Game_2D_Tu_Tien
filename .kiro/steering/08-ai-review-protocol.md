# 08 — AI Review Protocol

> Steering: always included. The mandatory checklist Kiro (and any AI contributor)
> runs for **every** code change in this project. This governs how AI works here.

## Finishing a PHASE: `docs/PHASE_EXECUTION_PROTOCOL.md` is binding

This file governs **a change**. A whole PHASE has a second, larger contract, and it lives in
**`docs/PHASE_EXECUTION_PROTOCOL.md`** — read it at the START of a phase, not at the end. From
Phase 19 it also runs the player-experience gates A–E of
**`docs/PLAYER_EXPERIENCE_STANDARD.md`** (D-067): the player-side definition of "finished".

```
PRE-FLIGHT → DEPENDENCY → AUTHORITY → EXTENSIBILITY → GAMEPLAY → NARRATIVE
    → UI → REAL PLAYTEST → VISUAL QA → PERFORMANCE → CLEANUP → DOCS → FINAL REVIEW
```

That document owns the detailed checklist, the evidence each gate requires, the capture policy
and the player-facing review. It is deliberately **not duplicated here** — two copies of a
checklist drift, and then nobody knows which one is binding.

The one line worth repeating in steering, because it is the rule most often broken:

> **Unit tests prove rules. Integration tests prove boundaries. E2E proves the real flow. A
> real-app playtest proves the player-facing experience. A visual capture proves what is
> actually on screen.** The last two were missing for nine phases, and that is where D-034's
> four HUD defects, D-050's nine UI defects and D-051's invisible attack lifecycle were hiding
> — every one of them on a green pipeline.

Two tools make those last two gates possible, and both are build-time only:
`tools/playtest_flow.gd` (real app, real semantic input, expected-vs-observed per step) and
`tools/capture_ui.gd` (real viewport). Their output is **ephemeral evidence**: inspect it, do
not commit it.

## The loop (every non-trivial feature)

```
READ  →  PLAN  →  IMPLEMENT  →  TEST  →  REVIEW  →  DOCS
```

- **READ** — architecture (`03-architecture.md`, `docs/ARCHITECTURE.md`), flow
  (`docs/GAME_FLOW.md`), and the relevant system design doc(s) (e.g.
  `CHARACTER_SYSTEM`, `SECT_SYSTEM`, `RELATIONSHIP_SYSTEM`, `WORLD_SIMULATION`,
  `DATA_SCHEMA`, `SAVE_FORMAT`). Do not touch code you have not read.
- **PLAN** — state the layer the change belongs in, the data/signals involved, the seams
  it must respect, and the tests you will add. For a large feature, write the plan down
  before editing.
- **IMPLEMENT** — smallest correct change; data-driven; no premature abstraction; respect
  layer direction and the persistent/runtime/presentation partition for core systems.
- **TEST** — write/extend tests for high-risk logic and run the suite headless
  (`godot --headless --path . -s res://tests/run_tests.gd`). Build/parse passing is not a
  pass.
- **REVIEW** — run the pre-completion gates below.
- **DOCS** — update every affected doc (see step 10 / the DOCS gate).

## Pre-completion review gates (ALL must pass before "done")

Before declaring a feature complete, explicitly review and report each:
- **Architecture review** — correct layer; no boundary violations; composition/events
  used appropriately.
- **Dependency review** — dependencies point the right way; no new upward/forbidden deps;
  no accidental new autoload (budget in `03-architecture.md`).
- **Side-effect review** — every emitted signal / mutated global/autoload state is
  intended and documented.
- **Performance review** — no new per-frame cost / hot-path allocation / duplicate nodes
  / redundant signals; measured + logged in `PERFORMANCE.md` if non-trivial.
- **Regression review** — ran smoke + related tests; any regression found became a
  permanent test.
- **Test review** — high-risk logic covered; suite green headless; a failing assertion
  actually fails the suite (non-zero exit).
- **Documentation review** — all affected docs updated; no doc now contradicts another
  (if it does, log in `DECISIONS.md`, don't silently pick one).

A feature that cannot pass every gate is not done; report which gate failed and why.

## Before writing code (every change)

1. **Read the architecture** — `.kiro/steering/03-architecture.md` and
   `docs/ARCHITECTURE.md`. Confirm which layer the change belongs in.
2. **Read the flow** — `docs/GAME_FLOW.md`. Understand how the touched system fits the
   whole game flow and what it depends on / feeds.

## While writing code

3. **Check dependencies** — does the change respect layer direction? No upward
   dependency (domain → presentation), no forbidden boundary crossing.
4. **Check duplicated logic** — is this logic already implemented elsewhere? Reuse or
   extract instead of copy/paste.
5. **Check side effects** — what signals fire, what global/autoload state mutates, what
   else reacts? Are those intended?
6. **Check error handling** — inputs validated at boundaries; failures loud in dev; no
   silently swallowed nulls/load failures.
7. **Check performance** — any new `_process`/`_physics_process` load, per-frame
   allocation, hot-path object creation, redundant signals, duplicate nodes? Measure if
   non-trivial; log per `docs/PERFORMANCE.md`.

## After writing code

8. **Check regression** — what existing behavior could this break? Run smoke + related
   tests. Convert any found regression into a permanent test.
9. **Check tests** — high-risk areas (damage, combat, inventory, progression, XP,
   level, cultivation, skill, quest, save/load, localization, map transitions) must have
   or get tests. See `docs/TEST_PLAN.md`.
10. **Update related documentation** — `GAME_FLOW`, `ARCHITECTURE`, `DATA_SCHEMA`,
    `SAVE_FORMAT`, `DECISIONS`, `CHANGELOG`, `PERFORMANCE`, `DEBUGGING` as applicable.

## Hard rule

> **"Build passes" is NOT sufficient to call a feature done.**

A green compile/parse only means the code loads. Done requires: correct layer, no
duplication, intended side effects, real error handling, acceptable (measured)
performance, no regressions, tests for high-risk logic passing, and docs updated.

## Reporting

When finishing a unit of work, report against this checklist: what was verified, what
could not be verified, and any open risks. Do not overstate confidence. Do not proceed
to the next step/feature unless asked.

## Extensibility gate

Before merging a system touch, confirm the extensibility rule still holds: can we still
add a map / chapter / quest / enemy / boss / pet / skill / item / cultivation tier as
*data + content* without editing core code? If this change broke that, flag it in
`docs/DECISIONS.md`.
