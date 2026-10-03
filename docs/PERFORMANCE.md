# PERFORMANCE — Aetheria

> Performance principles + the mandatory log of every non-trivial optimization.
> Rules summary: `.kiro/steering/05-performance-testing.md`.
>
> Status: no gameplay yet, so no profiler measurements exist. The optimization log (§4) is
> empty on purpose.
>
> **Phase 01 note (no optimization, just discipline):** the Core services were written to
> avoid needless continuous work. None of the 5 autoloads (`EventBus`, `GameState`,
> `Localization`, `InputService`, `SceneRouter`) implement `_process` or
> `_physics_process` — they are event/call driven. `InputService` exposes intent via
> pull methods (callers poll only when they need it) rather than running a per-frame loop.
> The menu/first-scene shells use `_unhandled_input` (event-driven) and build their UI once
> in `_ready`. `Localization` loads the CSV once (cached). This keeps the frame budget free
> for later gameplay; it is a design choice, not a measured optimization.
>
> **Phase 02 note (no optimization, just discipline):** the Player runs `_physics_process`
> ONLY for movement + attack-intent polling (one `InputService` read per frame, no
> allocation, no SceneTree-wide queries, no `get_nodes_in_group` per frame). The
> `InputService` node is resolved ONCE in `_ready`, not re-looked-up each tick. The Training
> Dummy and the sandbox walls are static — no `_process`/`_physics_process` at all; the
> dummy uses `collision_mask = 0` and the walls are `StaticBody2D` (nothing to simulate).
> Collision uses named layer/mask constants. Movement velocity is computed by a pure static
> function (no per-frame temp objects). Signals (health → owner → coordinator) are connected
> once in `_ready` and torn down with the scene. No numbers here were profiled — this is
> design discipline (`§1 Measure first`), not a measured optimization, so the log (§4) stays
> empty.
>
> **Pause semantics (§29 of the Phase 1 brief, documented, not over-built):** the intended
> distinction is: *application* concerns (UI, menu input, transition cleanup, infrastructure
> autoloads) keep running; *gameplay* pause only suspends gameplay systems. `GameState` has
> a `PAUSED` lifecycle phase to represent gameplay pause; input gating
> (`InputService` context stack) decides who receives input while paused. We did NOT build
> a pause framework (no autoload `process_mode` juggling) — later gameplay follows this
> ownership rule when it needs pause.

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
  **Phase 03:** now enforced — `tests/integration/test_map_transitions.gd` and the
  `tests/e2e/run_world_flow.gd` E2E assert that repeated hub↔field transitions do not grow
  `Performance.OBJECT_ORPHAN_NODE_COUNT` (SceneRouter frees the outgoing scene; WorldRuntime
  re-parents the persistent player out before the free, so neither the player nor stale
  signal connections leak). This is a correctness/no-leak assertion, not a tuned
  optimization (no `PERFORMANCE.md` optimization entry needed).

These numbers are provisional until Phase 29 (Performance) lets us measure on target hardware.

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
