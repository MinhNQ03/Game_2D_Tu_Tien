# WORLD_SIMULATION — Aetheria

> **Design only. No simulation code implemented.** Defines how Characters, Sects,
> Factions, and the World "live" without running full AI for hundreds of NPCs every
> frame. Companion to `docs/CHARACTER_SYSTEM.md`, `docs/SECT_SYSTEM.md`,
> `docs/RELATIONSHIP_SYSTEM.md`. Performance rules: `.kiro/steering/05-performance-testing.md`.

## 1. Goal & non-goal

- **Goal:** a world that evolves — characters age, pursue goals, change relationships;
  sects rise, war, and schism; events ripple — so the setting feels alive and reactive.
- **Non-goal / hard constraint:** **do NOT run full real-time AI for hundreds of NPCs
  every frame.** That would wreck performance and isn't needed for off-screen entities.

## 2. Level-of-detail (LOD) simulation — the core idea

Simulation fidelity scales with distance/relevance to the player:

| Band | Who | Fidelity | Cost |
|---|---|---|---|
| **Near (active)** | characters in the player's current scene | **real-time** — full entity, AIComponent, movement, combat | highest; bounded by scene population |
| **Mid (nearby)** | same region, off-screen | **coarse real-time / frequent ticks** — approximate movement & actions, no rendering | medium |
| **Far (background)** | rest of the world | **abstract** — no entity; state advances on slow ticks & events only | lowest; O(events), not O(frames) |

Only the **Near** band creates `CharacterEntity` nodes (per `CHARACTER_SYSTEM.md` §6).
Mid/Far bands operate purely on serializable `CharacterState` / `SectState` — no nodes,
no `_process`, no animation, no physics. Crossing a band promotes/demotes a character
between "has an entity" and "pure state".

## 3. Simulation drivers (how state advances)

Background simulation is **event/tick/schedule-driven**, never per-frame polling of
everyone:

- **Schedule:** each character has a data-defined routine (`schedule_ref`,
  `CHARACTER_SYSTEM.md`) — where they are and what they do by time-of-day/week. Resolving
  "where is NPC X now" is a cheap schedule lookup, not a simulation of their day.
- **Tick:** a coarse world clock advances the Far band on an interval (e.g. per in-game
  hour/day), applying batched **state transitions** to characters/sects/factions.
- **Event:** significant happenings (a sect war, a death, a breakthrough) are events on
  the EventBus that mutate state and can cascade (relationship shifts, faction moves).
- **State transition:** background actors are effectively small state machines
  (e.g. a disciple: TRAINING → MISSION → RETURNED), advanced on ticks, not frames.

This keeps background cost proportional to the number of *events/ticks*, not to the
number of NPCs × frames.

## 4. Promotion / demotion (band changes)

- **Far → Near (player arrives):** instantiate a `CharacterEntity` from the character's
  persistent `CharacterState`; "catch up" any schedule/tick deltas so the character
  appears where simulation says it should be.
- **Near → Far (player leaves):** free the entity, write back any changed persistent
  state, and hand the character back to abstract simulation. Freeing an entity never
  destroys the character (its authoritative state persists).

Clean promotion/demotion is why authoritative state is kept out of presentation nodes
(`CHARACTER_SYSTEM.md` §2–3).

## 5. Determinism & save

- Simulation uses the **seeded RNG** service so background evolution is reproducible and
  testable (and multiplayer-friendly later). No wall-clock-based randomness.
- The **world clock**, each character/sect/faction's `sim_state`, and pending scheduled
  transitions are **persistent** state in the save (`docs/SAVE_FORMAT.md`). On load,
  simulation resumes exactly where it left off. Loading after a long absence may run a
  bounded "catch-up" of missed ticks (capped to avoid a load-time spike — a documented
  budget in `docs/PERFORMANCE.md`).

## 6. Performance guardrails (from `05-performance-testing.md`)

- No `_process` on background actors (they have no nodes).
- Stagger/batch ticks; never tick the whole world on one frame.
- Cap per-frame promotion work when the player moves fast across regions (budget + queue).
- Measure with the profiler/monitors before optimizing; log notable optimizations in
  `docs/PERFORMANCE.md` (problem/cause/solution/impact/measurement).
- Performance tests assert background simulation of N characters stays within a
  frame-time/allocation budget (`docs/TEST_PLAN.md`).

## 7. Multiplayer readiness

World-event state and the world clock are authoritative world state a server would own
and advance; clients would receive results, not run their own divergent sim. Keeping the
simulation deterministic (seeded) and state-driven (not node-driven) is exactly what a
future authoritative server needs. Added to `docs/MULTIPLAYER_PLAN.md`. No networking now.

## 8. Testing (high-risk once implemented)

- A seeded run of K ticks produces identical world state twice (determinism).
- Promotion/demotion preserves persistent state exactly (no loss on band change).
- Save mid-simulation + load resumes to identical state.
- Catch-up after a long absence stays within the documented tick/time budget.
See `docs/TEST_PLAN.md`.

## 9. Explicitly NOT in this step

No simulation engine, no scheduler, no tick loop, no AI implemented. This document is the
contract for the World Simulation phase (`docs/ROADMAP.md`).
