# TEST_PLAN — Aetheria

> Testing strategy. Rules summary: `.kiro/steering/05-performance-testing.md`.
> Goal: **not** blind 100% coverage — strong coverage of high-risk logic, cheap smoke
> coverage of the whole flow, and every fixed bug pinned by a regression test.
>
> Status: strategy defined; `tests/` scaffold created; no gameplay to test yet.

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

## 4. Framework (decision pending — D-004)

Two viable options, to be chosen in `docs/DECISIONS.md` before Phase 1:
- **GUT** (Godot Unit Test) — mature, assertions, test discovery, CI-friendly.
- **Minimal custom runner** — a `SceneTree` script that runs `tests/` and reports
  pass/fail; zero dependency, less featureful.

Default lean: **GUT**, unless we want zero third-party dependency. Either way, tests
live under `tests/` and run headless.

## 5. Running headless (general form)

```
# with a custom SceneTree runner:
godot --headless --path . -s res://tests/run_tests.gd

# with GUT (once installed):
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

The exact command is pinned in `docs/DECISIONS.md` once D-004 is decided, and wired into
CI so every push runs unit + integration + smoke. Performance tests may run on a slower
cadence (nightly / pre-release).

## 6. Directory layout

```
tests/
  unit/            # pure logic
  integration/     # components together
  gameplay/        # scripted scenarios
  smoke/           # whole-flow boot checks
  performance/     # budget assertions
  README.md        # how to run, how to add a test
  run_tests.gd     # placeholder runner entry (until D-004 decided)
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

## 9. Current scaffold status

`tests/` exists with the folder layout, a `README.md`, and a placeholder `run_tests.gd`
that reports "no tests yet" and exits 0. Real tests arrive with each gameplay phase.
