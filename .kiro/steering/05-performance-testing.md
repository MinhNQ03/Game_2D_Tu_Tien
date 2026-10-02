# 05 — Performance & Testing

> Steering: always included. Enforceable principles. Full detail in
> `docs/PERFORMANCE.md` and `docs/TEST_PLAN.md`.

## Performance principles

- **Don't optimize blindly.** Measure with the Godot profiler/monitors first; optimize
  the proven hot path, not a guess.
- Avoid `_process` / `_physics_process` on thousands of objects when not needed. Prefer
  event-driven updates, timers, or batched ticks.
- Avoid continuous object creation in hot paths (combat, update loops). Avoid needless
  per-frame allocation (temp arrays/dicts, string building).
- Use **object pooling** only where profiling shows churn (projectiles, hit numbers,
  common enemies) — not everywhere by default.
- Manage textures/assets sensibly (atlases, import settings, no oversized textures for
  pixel art).
- Don't spawn duplicate nodes that do the same job.
- Avoid redundant signal connections; disconnect when nodes leave the tree.
- Control physics processing (layers/masks, sleeping bodies, disable unused).
- Control animation processing (don't animate off-screen / inactive entities).
- Control AI tick rate (slow/off distant AI; stagger ticks).

## Optimization logging (required)

Any non-trivial optimization MUST be recorded in `docs/PERFORMANCE.md` with:
**problem · cause · solution · impact · how measured** (with before/after numbers).
No "I think this is faster" changes.

## Testing strategy

Test layers (risk-prioritized, not blind 100% coverage):

- **Unit** — pure domain logic: damage formula, XP curve, cultivation breakthrough,
  inventory ops, quest state transitions, save (de)serialization, localization lookup.
- **Integration** — components working together (combat applying XP → level → unlock).
- **Gameplay** — scripted scenario runs (encounter resolves, quest completes).
- **Regression** — a failing bug becomes a permanent test.
- **Smoke** — boot, main menu → new game, load each map, basic combat, save/load.
- **Performance** — budget assertions on known hot paths (frame time, allocations).

### High-risk areas (must have tests)

damage · combat · inventory · progression · XP · level · cultivation · skill · quest ·
save/load · localization · map transitions.

### Running tests (headless Godot)

Tests live in `tests/`. They run headless so they fit CI. See `docs/TEST_PLAN.md` for
the exact runner and command. General form:

```
godot --headless --path . <test entry/runner args>
```

The concrete command, framework choice (e.g. GUT vs. a minimal custom runner), and CI
wiring are decided and documented in `docs/TEST_PLAN.md` before the first gameplay
feature lands.

## Done ≠ build pass

A feature is only done when its high-risk logic has tests and they pass — see
`.kiro/steering/08-ai-review-protocol.md`.
