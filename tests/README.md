# tests/

Headless-first test suite for Aetheria. Strategy & rationale: `docs/TEST_PLAN.md`.
Rules: `.kiro/steering/05-performance-testing.md`.

## Layout

```
tests/
  unit/            pure logic (damage, XP, cultivation, inventory, quest FSM, save, localization)
  integration/     multiple components together
  gameplay/        scripted scenario runs
  smoke/           whole-flow boot checks
  performance/     hot-path budget assertions
  run_tests.gd     placeholder runner (until framework decision D-004)
```

## Running (placeholder, pre-D-004)

```
godot --headless --path . -s res://tests/run_tests.gd
```

Once the framework is decided (see `docs/DECISIONS.md` D-004), this README and the exact
command are updated. If GUT is chosen:

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

## Adding a test

- Name: `test_<subject>.gd`.
- One behavior per test; arrange–act–assert.
- Seed all randomness for determinism.
- High-risk areas (damage, combat, inventory, progression, XP, level, cultivation,
  skill, quest, save/load, localization, map transitions) must be covered before the
  owning feature is "done".
- A fixed bug gets a permanent regression test here.

## Status

No gameplay exists yet, so there are no real tests. `run_tests.gd` is a placeholder that
reports "no tests yet" and exits cleanly so CI can be wired early.
