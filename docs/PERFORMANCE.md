# PERFORMANCE — Aetheria

> Performance principles + the mandatory log of every non-trivial optimization.
> Rules summary: `.kiro/steering/05-performance-testing.md`.
>
## CURRENT STATUS (through Phase 18; the opening bullets date from Phase 11 and still hold)

- **A measured benchmark EXISTS.** `tests/performance/test_world_sim_budget.gd` measures the
  world-simulation tick loop at a representative population (200 background actors × 300
  ticks) and runs as part of the headless suite, so a regression fails CI rather than being
  noticed later.
- **The optimization log (§4) is NOT empty.** It holds **PERF-001**, a real measured
  optimization with before/after numbers: the per-tick loop was `O(cast · log cast)` and is now
  independent of the background population (50 ms → 12 ms at 200 actors; scaling factor
  3.57× → 1.0×). It was found BY the budget test, before the phase was declared done.
- **Deterministic-simulation performance discipline is established and enforced**, not merely
  intended: zero per-frame work in the world-simulation subsystem (guarded by a source-reading
  test), zero nodes for background actors in any LOD band, bounded catch-up, and a bounded
  event feed. The full list is in the Phase-08 note at the end of this document.
- **Combat has a budget too** (Phase 09): `tests/performance/test_combat_budget.gd` asserts
  that an idle attacker runs no physics callback at all, that a swing is LINEAR in candidates
  rather than quadratic, that each candidate is cheap to reject (~0.42 µs), and that the seeded
  stream advances once per HIT rather than per candidate. It produced **PERF-002**.
- **Enemy AI has a budget** (Phase 10): `tests/performance/test_ai_budget.gd` asserts that
  no enemy runs its own frame callback (ONE session callback drives every brain, so the cost
  of N creatures is one measurable number), that an enemy-free map stops ticking entirely,
  that DECISIONS are throttled to each profile's interval while movement is not, that the
  tick is LINEAR in the population, and that a spawn/tick/despawn cycle leaks no orphans.
  Measured: **40 creatures × 1800 frames = 289 ms**, scaling **10.3×** for a 10× cast
  (linear, as designed), **4.0 µs per enemy per frame**, 149 decisions where 150 were
  expected. It produced **PERF-003**.
- **Still true, and still deliberate:** no Godot *profiler* session has been run on a
  representative combat scene. The budgets that exist are in-suite timing assertions, not
  profiler captures, and the shipped world has one combat target — so these numbers bound the
  RESOLUTION cost, not the cost of a real fight with enemies and AI, which arrives with the
  phase that adds them. Phase 29 (Performance) is where target-hardware profiling happens.
- The other performance guards in the repo (map-transition orphan-node checks, the suite's
  leak gate) are **correctness/no-leak assertions, not tuned optimizations** — they are tests,
  and they are deliberately NOT optimization-log entries.
- **Progression (Phase 11) added NO measurable per-frame cost, and that is by construction
  rather than by tuning** — so it has no optimization-log entry, and inventing one would be the
  "I think this is faster" change this document forbids. What was reviewed and verified in
  D-055: `ProgressionRuntime` has **no** `_process`/`_physics_process` at all; the authored
  curve is loaded ONCE per session, not per grant; the level is DERIVED by arithmetic over a
  20-entry array rather than cached-and-invalidated; `build_view()` is called on EVENTS (map
  arrival, `xp_gained`, `level_changed`), never per frame; `GameplayHUD._refresh_progression()`
  runs only from a pushed view or a language change; and `LevelUpFeedback` keeps `_process`
  **off** whenever it is idle — asserted in both directions by
  `test_the_celebration_costs_nothing_while_idle`, because an always-on callback on a node that
  lives for the whole session would pay for 1.5 s of effect with the entire session.
- **Known environmental debt (D-054, unchanged):** `test_ai_budget` and `test_combat_budget`
  assert WALL-CLOCK budgets and fail on some development machines while passing on the CI
  runner; the numbers swing 2–3× between runs of identical code. Deliberately not "fixed" by
  loosening the limits — that would hide a real regression. They need a ratio-only formulation,
  a calibration run, or an explicit CI-class-hardware marker: a decision for whoever owns the
  performance gates, not a side effect of a progression pass.

---

- **The companion has a budget (Phase 16)**: `tests/performance/test_pet_budget.gd`. The pet runs
  NO frame callback of its own (ticked by the one combat-session callback); target choice runs on
  a 0.25 s cadence, not per frame (measured: 119 passes and 149 brain decisions over 1800 frames,
  expected ~120 / ~150); a retarget pass is one scan of the spawned enemies. Measured locally
  (2026-10-10, headless): 1800 frames with one pet — 4 hostiles 10.07 ms, 40 hostiles 15.03 ms
  (1.49× for 10× the hostiles; 8.3 µs per frame). No optimization was needed, so §4 has no entry.
- **A conversation that is not open costs nothing (Phase 18)**:
  `tests/performance/test_dialogue_budget.gd`. `DialogueRuntime` has no `_process` /
  `_physics_process`; a closed `DialoguePanel` and a `WorldNpc` nobody is talking to do not
  process. What a line offers is evaluated when a line is SHOWN and when an answer is
  submitted — never per frame (the integration suite counts view rebuilds: open 1, new line 1,
  refusal 0, close 1). Measured locally (2026-10-10, headless): `eligible_choices` on the two
  most-conditioned shipped nodes, with an edge and the gated knowledge present, **12.81 µs per
  call** over 20 000 calls (ceiling 100 µs). The panel's reaction and transition are engine
  tweens of 0.12–0.14 s, started on a line change. No optimization was needed, so §4 has no
  entry.

## HISTORICAL NOTES (kept as written; each records the discipline of its phase)

> These notes describe the state of the project AT THE TIME OF THAT PHASE. Where one of them
> says the optimization log is empty or that no benchmark exists, that was accurate when
> written and has been superseded by the CURRENT STATUS block above. They are preserved rather
> than rewritten, because the reasoning in them is still the reasoning the code follows.

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
>
> **Phase 04 note (no optimization, just discipline):** the new UI/HUD do NOT run per-frame
> loops. `GameplayHUD` and the main menu build their nodes once and refresh ONLY on demand
> (owner push) or on the `language_changed` EventBus signal — no `_process`/`_physics_process`,
> no per-frame string building. `MapBase.set_interact_available` early-returns when the value
> is unchanged, so the HUD re-renders only on an actual enter/exit edge, not every overlap
> frame. `InputService.get_action_display_label` is called only when a hint is (re)built, not
> per frame. The camera zoom is set once per map in `apply_map_data`. `CharacterState` is a
> plain `RefCounted` built once per session and read by reference (no copying on map swap).
>
> **Phase 04 UI-hardening note (D-024, no optimization, just discipline):** the asset-backed
> UI loads each texture through `load()` (cached by Godot's resource loader; the same `.ctex`
> is shared across styleboxes) and builds the `Theme` ONCE when a UI node enters the tree —
> there is no per-frame `Theme.new()`, no per-frame texture load, and no per-frame node
> creation. Styleboxes/textures are `RefCounted` and freed with their owning UI node. The menu
> background is a single tiled `TextureRect` (one draw path), not a per-frame redraw. 9-slice
> stretching is GPU-side `StyleBoxTexture`, not CPU work.

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

### PERF-001 — the world-simulation tick loop sorted the WHOLE cast every tick  (2026-10-05)

- **Problem:** the per-tick loop needs the OBSERVED (NEAR+MID) actors. `WorldSimulationState`
  derived that set by filtering `actors_sorted()`, which sorts every actor id — so each tick
  was `O(cast · log cast)` in the size of the whole background population. That is exactly the
  `O(whole cast)` per-tick cost LOD exists to eliminate, reintroduced inside the code that
  implements LOD.
- **Cause:** found by the budget test in `tests/performance/test_world_sim_budget.gd`, which
  holds the observed set CONSTANT at 10 and varies only the FAR population. A tenfold FAR cast
  cost **3.57×** more per tick — not the ~10× of a naive full-cast walk (most of the per-actor
  body was correctly skipped), but unmistakably driven by the far population, which it must not
  be at all. The sort was the whole difference.
- **Solution:** `WorldSimulationState` now maintains an incremental `_observed` index (a set of
  instance ids), updated by `add_actor()` and by the new `set_actor_band()` — which becomes the
  ONLY sanctioned way to change a band, so the index cannot go stale. `observed_actors_sorted()`
  sorts the observed set only. The index is DERIVED, so `from_dict()` rebuilds it rather than
  serializing it (a serialized index could disagree with the bands it indexes).
- **Impact:** 300 ticks, 10 observed actors in both runs —
  - cast of 20: **14 ms → 12 ms**
  - cast of 200: **50 ms → 12 ms**
  - scaling factor for a 10× larger FAR population: **3.57× → 1.0×**
  The per-tick cost is now independent of the background population, which is the property the
  architecture claims.
- **Measured:** `tests/performance/test_world_sim_budget.gd` (headless, `Time.get_ticks_msec`
  around `advance_ticks(300)`, synthetic catalog so N is controllable), run locally on Godot
  4.7-stable headless. The test prints the figures above and keeps both a relative scaling
  assertion (≤ 3× for a 10× cast) and a generous absolute ceiling (4000 ms), so a regression
  fails on any hardware rather than only on fast hardware.
- **Links:** D-048 (Phase 08), `docs/WORLD_SIMULATION.md` §6, L-032.

> This is the FIRST entry in this log, and it is here because the budget test was written
> before the code was declared done and then failed. That is the intended order
> (`§1 Measure first`): the optimization is a response to a measurement, not to a hunch.

### PERF-002 — a swing fully type-validated every candidate before rejecting it  (2026-10-05)

- **Problem:** `CombatService.resolve_hit()` ran `_validated_target()` — five `typeof` checks
  and five dictionary lookups — on EVERY entity in the hurtbox registry, and only then rejected
  it by distance. A swing in a busy area therefore paid the full validation cost for hundreds
  of entities that were nowhere near the attack, on every attack.
- **Cause:** found by the budget test in `tests/performance/test_combat_budget.gd`, which holds
  the in-range targets CONSTANT at 4 and varies only the number of irrelevant registered
  entities. A tenfold registry cost **9.00x** more per swing — i.e. the cost was dominated by
  entities that could not be hit. Validation is a BOUNDARY concern; running it per candidate
  per swing re-checks data the program itself constructed moments earlier.
- **Solution:** geometry first, full validation second. The reach/arc reject needs only
  `position` and `radius`, so those two are type-checked up front and the remaining three
  fields are validated only for candidates that survive the geometric filter. No validation was
  removed — the same fields are still checked before they are read (L-024), just not for
  entities that are about to be discarded.
- **Impact:** 2000 swings, 4 in-range targets in both runs —
  - registry of 40: **112 ms -> 52 ms**
  - registry of 400: **1005 ms -> 334 ms** (3x faster)
  - scaling factor for a 10x larger registry: **9.00x -> 6.43x**
  - broad-phase cost: **0.418 us per candidate**
- **Measured:** `tests/performance/test_combat_budget.gd` (headless, `Time.get_ticks_usec`
  around 2000 `resolve_hit` calls, synthetic target arrays so N is controllable), Godot
  4.7-stable headless.
- **A correction worth recording:** the test's first version asserted scaling "< 4x", which is
  a claim the design never made — a broad-phase scan looks at every candidate once, so 10x
  candidates legitimately costs ~10x. The assertion was wrong, and it still did its job: it
  failed at 9x and that is how the validation ordering was found. It was then restated as what
  linear MEANS (< 13x, so a quadratic scan at ~100x fails) plus a per-candidate microsecond
  budget, which is the property that actually matters. Sub-linear would need a spatial index,
  and nothing needs one yet.
- **Links:** D-007 (Phase 09), `tests/unit/combat/test_combat_resolution.gd`.

### PERF-003 — the AI decision cadence silently ran 8% slow  (2026-10-05)

- **Problem:** `AIComponent` accumulated frame time and, on reaching the profile's
  `decision_interval`, reset the accumulator to **zero** — discarding the overshoot. Twelve
  frames at 60fps sum to `0.19999999999999998`, just *under* a 0.2s interval, so the decision
  slipped to every **13th** frame: a 0.217s effective cadence against the 0.2s the content
  authored. Every state timing downstream (`alert_seconds`, `recover_seconds`) inherited the
  same 8% stretch.
- **Cause:** found by `tests/performance/test_ai_budget.gd`, which counts decisions over a
  known span instead of trusting the interval was honoured: it reported **138** decisions
  where 150 were expected. Nothing else could see it — the AI behaved plausibly, every unit
  test passed, and 8% is invisible to the eye.
- **A SECOND bug the same test exposed:** the brain was being advanced by the NOMINAL interval
  rather than by the time that actually elapsed, so under long frames its internal clock ran
  *slower than the world* — at 5-second frames it experienced 0.2s per tick, and a creature
  could sit in one state indefinitely. The long-frame integration test caught that one.
- **Solution:** carry the remainder (`fmod(elapsed, interval)`) so the long-run average is
  exactly the authored interval, and pass the REAL elapsed time to `AiBrain.decide()`.
- **Impact:** cadence **138 → 149** decisions per 30s (expected 150); long-frame behaviour
  correct instead of time-dilated. Throughput unchanged: **40 creatures × 1800 frames =
  289 ms**, **4.0 µs per enemy per frame**, scaling **10.3×** for a 10× cast.
- **Measured:** `tests/performance/test_ai_budget.gd` and
  `tests/integration/test_enemy_encounter.gd`, Godot 4.7-stable headless.
- **Links:** Phase 10, `docs/ROADMAP.md`.



## 5. Relationship to tests

Performance budgets become `tests/performance/` assertions where feasible (e.g. frame
time or orphan count under a scripted combat scenario), so regressions surface in CI
rather than during play. See `docs/TEST_PLAN.md`.

> **Phase 05 note (D-026, no optimization, just discipline):** the relationship graph does NOT
> run per-frame work. `RelationshipRuntime` has no `_process`/`_physics_process`; the graph
> changes only on explicit mutations (events/commands), never on a tick. The `RelationshipStore`
> indexes by edge id and by endpoint, so `find_between`/`find_for_endpoint` are indexed lookups
> rather than full-graph scans; a mutation touches only the one edge; history is bounded by
> `RelationshipConfigData.history_capacity` so it can't grow without limit. Decay/propagation
> and off-screen relationship evolution are deferred to the World Simulation phase (batched
> ticks), not real-time. The character visual pipeline builds its Sprite2D once per profile and
> only changes the frame index on a facing change — no per-frame texture load or node creation.
> No numbers were profiled; this is design discipline (`§1 Measure first`), so the optimization
> log (§4) stays empty.

> **Phase 08 note (D-048) — the discipline behind PERF-001.** The world simulation runs with
> **zero per-frame cost**: `WorldSimulationRuntime` has no `_process`, no `_physics_process`, no
> `Timer` and no wall-clock read, and a regression test reads the SOURCE to keep it that way
> (the cheapest way to betray the design is a `_process` that "just" accumulates delta).
> Simulated time passes on EXPLICIT gameplay beats — session start and the player arriving in a
> map — at an authored tick cost. Consequences worth recording:
> - **Background characters are not nodes, in any band.** A cast of 200 simulated for 300 ticks
>   creates ZERO nodes (asserted by `Performance.OBJECT_NODE_COUNT`, and in the real application
>   by `WorldSimulationRuntime.get_child_count() == 0` after 20 map transitions). "No `_process`
>   on background actors" is true because there are no background actors to put one on.
> - **An actor's activity is DERIVED** from `(tick, schedule)`, not stepped per tick, so a FAR
>   actor costs nothing until something asks about it — and asking is `O(1)`.
> - **Per-tick work is `O(observed + due events)`** (PERF-001), and the event queue is sorted,
>   so taking the due events is a prefix walk rather than a scan.
> - **Catch-up is BOUNDED** by an authored `catch_up_budget_ticks`; the overflow becomes
>   deterministic carry-over debt drained on later calls, so returning to a long-abandoned world
>   cannot stall on a thousand ticks in one frame. Nothing is dropped — processing `a + b` ticks
>   is asserted identical to processing `a+b` at once.
> - **The map-neighbour index for the MID band is built ONCE per session**, not per arrival.
> - **The world-event feed is capped** by `event_log_capacity`, like `RelationshipEdge.history`,
>   so it cannot grow without limit inside a save.
