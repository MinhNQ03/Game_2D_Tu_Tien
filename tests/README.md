# tests/

Headless-first test suite for Aetheria. Strategy & rationale: `docs/TEST_PLAN.md`.
Rules: `.kiro/steering/05-performance-testing.md`.

## Layout

```
tests/
  framework/
    test_case.gd   TestCase base + assert_* API
  unit/            pure logic (damage, XP, cultivation, inventory, quest FSM, save, localization)
  integration/     multiple components together
  gameplay/        scripted scenario runs
  smoke/
    test_boot.gd   REAL smoke test: project boots, main scene loads + structure
  performance/     hot-path budget assertions
  run_tests.gd     real custom headless runner (framework decision D-004)
```

## Running

```
godot --headless --path . -s res://tests/run_tests.gd
```

Success → per-test `[PASS]` lines, a summary, `RESULT: PASS`, exit code 0.
Failure → `[FAIL]` lines, `RESULT: FAIL`, exit code 1.

CI (`.github/workflows/ci.yml`) runs exactly this on every push with Godot 4.7.

## Writing a test

```gdscript
extends TestCase

func test_something() -> void:
    assert_eq(2 + 2, 4, "math works")
```

- File name: `test_<subject>.gd`, placed in the right layer folder.
- `extends TestCase`; define `test_*` methods.
- Assertions: `assert_true/false`, `assert_eq/ne`, `assert_not_null/null`
  (they record failures rather than throw).
- Optional `before_each()` / `after_each()` hooks.
- One behavior per test; arrange–act–assert; seed all randomness for determinism.
- High-risk areas (damage, combat, inventory, progression, XP, level, cultivation,
  skill, quest, save/load, localization, map transitions) must be covered before the
  owning feature is "done".
- A fixed bug gets a permanent regression test here.

## Status

Runner + framework are real (not placeholders). One real smoke test exists; gameplay
tests arrive with each phase. The suite always requires `smoke/test_boot.gd` — if it goes
missing, the runner fails on purpose so the suite can't silently shrink to green.
