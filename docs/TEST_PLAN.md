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

```
godot --headless --path . -s res://tests/run_tests.gd
```

Expected on success: per-test `[PASS]` lines, a summary, `RESULT: PASS`, exit code **0**.
On any failure: `[FAIL]` lines, `RESULT: FAIL`, exit code **1**.

> **Note (D-009):** the AI agent could not run this locally — no Godot binary was
> reachable from its shell. All scripts were statically validated via the GDScript
> language server (zero errors). The authoritative headless run happens in CI (D-012) and
> can be run manually by any developer with Godot 4.7 installed.

## 6. Directory layout

```
tests/
  framework/
    test_case.gd   # TestCase base + assert_* API (D-004)
  unit/            # pure logic
  integration/     # components together
  gameplay/        # scripted scenarios
  smoke/
    test_boot.gd   # REAL smoke test: boot + main-scene load/structure
  performance/     # budget assertions
  README.md        # how to run, how to add a test
  run_tests.gd     # real custom runner (not a placeholder)
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

`tests/` has the layer folders, `framework/test_case.gd`, a real `run_tests.gd` runner,
and one real smoke test `smoke/test_boot.gd` (asserts: main scene exists, is declared in
`project.godot`, project name is `Aetheria`, scene loads as a `PackedScene`, instantiates
with the `Main/Systems/World/UI` structure, and the harness records failures correctly).
Unit/integration/gameplay/performance tests arrive with each gameplay phase. CI (D-012)
runs the suite headless on every push.
