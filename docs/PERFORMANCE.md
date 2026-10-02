# PERFORMANCE — Aetheria

> Performance principles + the mandatory log of every non-trivial optimization.
> Rules summary: `.kiro/steering/05-performance-testing.md`.
>
> Status: no gameplay yet, so no measurements exist. The log below is empty on purpose.

## 1. Principles

1. **Measure first.** Use the Godot profiler and the Performance monitors before
   changing anything. Optimize the *proven* hot path, never a guess.
2. **Mind the update loops.** Don't put `_process` / `_physics_process` on thousands of
   objects. Prefer event-driven updates, timers, or batched/staggered ticks.
3. **Avoid hot-path allocation.** No continuous object creation and no needless temp
   arrays/dicts/string building per frame in combat and update loops.
4. **Pool only where churn is proven** (projectiles, floating damage numbers, common
   enemies). Pooling everywhere is itself a cost and complexity we don't pay blindly.
5. **Assets.** Pixel-art import correct (nearest, no mipmaps), use atlases, no oversized
   textures. See `.kiro/steering/06-art-assets.md`.
6. **No duplicate nodes** doing the same job.
7. **Signals.** No redundant connections; disconnect when a node leaves the tree.
8. **Physics.** Use collision layers/masks, let bodies sleep, disable unused physics.
9. **Animation.** Don't animate off-screen / inactive entities.
10. **AI tick rate.** Slow or disable distant AI; stagger ticks so they don't all fire
    on the same frame.

## 2. Budgets (targets; refined once we can measure)

- Target 60 FPS on the desktop dev machine with a representative combat scene.
- No sustained per-frame heap growth during combat (allocation budget ≈ flat).
- Map transition: no leaked nodes/signals (verified by tests, not just eyeballing).

These numbers are provisional until Phase 20 lets us measure on target hardware.

## 3. How to measure (quick reference)

- **Debugger → Profiler** for per-function frame cost.
- **Debugger → Monitors** for object/node/orphan counts, draw calls, memory.
- Watch **orphan node count** to catch leaks after map transitions.
- Seed RNG so performance scenarios are reproducible between runs.

## 4. Optimization log (REQUIRED for every non-trivial optimization)

Each entry MUST record: **problem · cause · solution · impact · how measured**
(with before/after numbers). No "I think this is faster" changes.

Template:

```
### PERF-00X — <short title>  (YYYY-MM-DD)
- Problem:   what was slow / what budget was violated
- Cause:     root cause found via profiler (not a guess)
- Solution:  what changed
- Impact:    before → after (fps / ms / allocations / draw calls / orphan count)
- Measured:  tool + scene + conditions used
- Links:     commit / test / DECISIONS entry
```

> No entries yet — nothing has been measured because no gameplay exists.

## 5. Relationship to tests

Performance budgets become `tests/performance/` assertions where feasible (e.g. frame
time or orphan count under a scripted combat scenario), so regressions surface in CI
rather than during play. See `docs/TEST_PLAN.md`.
