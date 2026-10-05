# WORLD_SIMULATION — Aetheria

> **Status: IMPLEMENTED (Phase 08, D-048).** Defines how Characters, Sects, Factions and the
> World "live" without running full AI for hundreds of NPCs every frame. Companion to
> `docs/CHARACTER_SYSTEM.md`, `docs/SECT_SYSTEM.md`, `docs/RELATIONSHIP_SYSTEM.md`. Performance
> rules: `.kiro/steering/05-performance-testing.md`, measured results in `docs/PERFORMANCE.md`.
>
> **What is live:** the deterministic RNG seam (`RngService`/`RngStream`), the world clock
> (`WorldClock`), the serializable simulation tier (`WorldSimulationState`/`WorldSimActor`), the
> evolution engine (`WorldSimulationService`), the per-session owner
> (`WorldSimulationRuntime`, a node under `Main/Systems` — **no new autoload**), the authored
> content (`data/worldsim/`), and a minimal HUD surface (world date + the last world event).
>
> **What is deliberately NOT here:** succession, schism, coup, purge, war resolution, economy
> simulation, daily-life AI, NPC rendering, procedural generation. Those are RULES and CONTENT
> built on this substrate by later phases (`docs/SOCIAL_DESIGN.md` §5/§7, `docs/ROADMAP.md`).

## 1. Goal & non-goal

- **Goal:** a world that evolves — characters keep routines, sects and factions gain and lose
  sway, relationships shift — so the setting feels alive and reactive.
- **Non-goal / hard constraint:** **do NOT run full real-time AI for hundreds of NPCs every
  frame.** The implementation honours this literally: background characters have **no nodes at
  all**, and the simulation has **no per-frame code**.

## 2. Level-of-detail (LOD) simulation — the core idea

Simulation fidelity scales with relevance to the player:

| Band | Who | Fidelity | Cost |
|---|---|---|---|
| **Near (active)** | actors in the player's current map | inspected every tick; the band in which a later phase will instantiate a `CharacterEntity` | highest; bounded by map population |
| **Mid (nearby)** | actors one map-exit hop away | inspected every tick, no rendering | medium |
| **Far (background)** | everyone else | **not inspected at all**; state computed on demand | zero per tick |

The band is **derived, never authored**: it is a RELATIONSHIP to the player, recomputed by
`WorldSimulationService.assign_bands(player_map_id, adjacent_map_ids)` whenever the player
arrives somewhere. "Adjacent" comes from the real `MapData.exits` graph, walked by
`WorldSimulationRuntime` and handed down — a domain service has no business loading the map
catalog.

**No band creates nodes in Phase 08.** Entity instantiation for NEAR belongs to the phase that
renders background characters; until then the "Far has no entity nodes" guarantee is true of
every band, and the tests assert the node count rather than trusting the sentence.

**The shipped two-map world (hub ↔ field) has no FAR actors**, because both maps are adjacent.
FAR becomes reachable the moment a third, non-adjacent map is authored; all three bands are
exercised by the unit tests against a three-map graph, and the E2E asserts the census the
shipped world should actually have rather than a hopeful `>= 0`.

### 2a. The one decision that makes LOD safe: activity is DERIVED

An actor's abstract activity is a **pure function of `(world_tick − joined_tick, schedule)`**.
The obvious alternative — step a phase index forward each tick — looks equivalent and is not,
because it makes an actor's state depend on HOW OFTEN it was stepped. Under LOD that is fatal: a
FAR actor is not stepped (that is the entire saving), so it would fall behind, and promotion
would either lose time or need a catch-up whose result depended on the player's travel history.

With a derived activity:
- NEAR, MID and FAR actors compute the **same** answer from the same clock;
- promotion/demotion cannot lose or invent state;
- the band controls only how often the simulation **looks**, never what it sees.

A test asserts exactly that: a FAR actor's activity equals an observed actor's on the same
routine at every tick, and promoting it lands on the value it already should have had.

## 3. Simulation drivers (how state advances)

Event/tick/schedule-driven, never per-frame polling of everyone:

- **Schedule** (`WorldSimScheduleData`) — a cyclic list of phases, each an activity held for an
  authored number of ticks. Resolving "what is NPC X doing now" is arithmetic, not a simulation
  of their day. A CYCLE rather than a timeline, because a routine that ended would need a
  decision about what happens next, and a decision is behaviour — later phases, not data.
- **Clock** (`WorldClock`) — a monotonic tick counter plus a deterministic conversion to
  in-world time. The calendar (ticks/hour, hours/day, days/season, seasons/year) is **authored
  data**; `WORLD_BIBLE.md` freezes no calendar. Day/season/year are DERIVED from the single
  stored tick, never stored beside it.
- **Explicit beats** — time passes when the game says so: at session start
  (`ticks_on_session_start`) and when the player arrives in a map
  (`ticks_per_map_transition`). There is no timer and no wall-clock read anywhere. Only the
  arrival beat is wired, because hub ↔ field is currently the only gameplay beat that exists; a
  later phase adds its own beats as data beside these.
- **Scheduled events** (`WorldSimEventData`) — a first due tick, an optional period, and a
  magnitude range drawn from the seeded stream. This is where randomness is actually consumed.
- **State transition** — background actors are small state machines
  (TRAINING → MISSION → RETURNING → RESTING) advanced by the clock, not by frames.

Background cost is therefore proportional to **observed actors + due events**, not to
NPCs × frames (`docs/PERFORMANCE.md` PERF-001).

### 3a. Events mutate through the OWNING system, never directly

World Simulation owns world *evolution*, not world *state*. Each event kind names a subject and
a magnitude and asks the owner to apply it:

| Kind | Applied through | Why |
|---|---|---|
| `SECT_INFLUENCE` | `SectService.adjust_influence` | the sect store owns that number, and clamps it |
| `FACTION_INFLUENCE` | `FactionService.adjust_influence` | same, with the faction's own bounds |
| `RELATIONSHIP_SHIFT` | `RelationshipService.apply_delta` | the graph owns dimensions, clamping, bounded history and symmetry (CL-12) |

An event that wrote `SectState.influence` or `RelationshipEdge.dimensions` directly would be the
D-015 defect reintroduced from a new direction. Tests prove the real path was used by observing
what only the OWNER does: the value stops at the owner's ceiling, and the relationship service
wrote history the simulation does not implement.

**All edge creation happens at preparation time, never inside a tick.** A tick cannot abort
halfway (the clock has moved and a draw is spent), so `prepare_events()` validates every
authored event against the LIVE stores — target exists, dimension configured, endpoints are
simulated actors — and ensures the character↔character edge, before any time passes. A missing
owner service is a **start failure**, not a skipped step (the D-047 rule).

## 4. Promotion / demotion (band changes)

- **Far → Near (player arrives):** the band is set and the actor's cached activity refreshed to
  the value the clock says it already has. A later phase instantiates a `CharacterEntity` from
  the character's persistent `CharacterState` here.
- **Near → Far (player leaves):** the band is set. Nothing else changes — there is no entity to
  free yet, and the authoritative state never lived in one.

A band change touches the band and nothing else: not the activity, not the schedule, not
`joined_tick`, not the character. A test walks FAR → MID → NEAR → MID → FAR with the world
ticking between each move and asserts the actor record is the SAME object with identical
routine, location and origin tick, no actor duplicated or dropped, and the derived cache
consistent again afterwards.

## 5. Determinism & save

- **Seeded, stream-scoped RNG** (`RngService`, the seam D-040/C-010 froze and this phase
  introduces as its first real consumer). One world seed fans out into named streams; drawing
  from one cannot move another, so a future combat fix cannot silently change the world. The
  seed comes from the RUN (hashed `GameState.run_id`), never from the clock.
- **The whole simulation is serializable** (`WorldSimulationState.to_dict/from_dict`), using the
  key names `docs/DATA_SCHEMA.md` reserves (`world_clock`, `pending_transitions`, `rng_seed`)
  plus what a deterministic resume additionally requires.
- **The resume contract, asserted by test:** `save → load → advance K` produces the identical
  world to `advance K` on a run that never stopped. That holds only if every input to a future
  tick is in the snapshot, and four are easy to forget: the **stream positions** (a seed alone
  reproduces a world only from tick 0 — `SAVE_FORMAT.md` §3b), the **pending queue** (a
  recurring event's next due tick is computed when it fires), the **carry-over debt**, and each
  actor's **`joined_tick`**.
- **Hydrate is strict and atomic:** every field is `typeof()`-checked before conversion and the
  receiver is written only once everything validated, so a corrupt payload leaves the simulation
  byte-identical (L-024). A pending event due at or before the restored tick is REFUSED rather
  than fired late or dropped — both would change the world relative to the save.

### 5a. Catch-up is bounded, and never drops time

`advance_ticks(n)` processes at most `catch_up_budget_ticks`; the remainder becomes **carry-over
debt**, drained first on later calls. So returning to a long-abandoned world cannot stall on a
thousand ticks in one frame, and no simulated time is lost:

```
advance_ticks(25) with budget 10  ->  processes 10, owes 15
advance_ticks(1)                  ->  processes 10 (debt first), owes 6
advance_ticks(1)                  ->  processes 7,  owes 0
```

The clock ends exactly as old as the time it was given. A test asserts the equivalence that
makes this legitimate: **processing N ticks as `a + b` produces the identical world to
processing N at once** — otherwise how fast the player travelled would change world history.

## 6. Performance guardrails

Measured results and the full discipline list are in `docs/PERFORMANCE.md` (PERF-001 + the
Phase-08 note). In summary: no nodes for background actors, no `_process` anywhere in the
subsystem (guarded by a source-reading test), per-tick work `O(observed + due events)`, a
sorted event queue, a once-per-session map-neighbour index, a bounded event feed, and a bounded
catch-up.

## 7. Multiplayer readiness

The world clock, the per-actor simulation tier, the pending queue and the RNG stream positions
are exactly the authoritative world state a Stage-2 server would own and advance; clients would
receive results rather than running their own divergent sim. Keeping the simulation
**deterministic (seeded, no wall clock)** and **state-driven (not node-driven)** is what makes
that possible, and both are now properties the tests enforce rather than intentions. See
`docs/MULTIPLAYER_PLAN.md`. **No networking code.**

## 8. State ownership (the single-owner rule applied here)

| State | Owner | Notes |
|---|---|---|
| world clock, RNG streams, pending queue, carry-over, event feed | `WorldSimulationState` | persistent tier, saved |
| per-actor band / routine position / location | `WorldSimActor` inside that state | persistent tier, saved |
| `CharacterState.sim_state` | **the simulation, as a DERIVED CACHE** | the record wins on disagreement; `verify_character_caches()` reports drift rather than papering over it (the D-015 shape) |
| who exists | `CharacterRegistry` (owned by `WorldRuntime`) | the simulation ADDS its cast to the shared registry; it never keeps a private character model |
| sect roster / influence | `SectService` | the simulation enrols and adjusts THROUGH it |
| faction roster / influence | `FactionService` | same |
| relationship dimensions | `RelationshipService` | same |

## 9. Content extensibility

Adding somebody to the living world, a new routine, or a new thing that happens is **data**: a
new `.tres` plus a catalog line, no code. `WorldSimCatalog` validates the cross-entry integrity
a single entry cannot (unique ids, every actor's schedule listed, magnitudes that can actually
be felt), and the runtime performs the cross-catalog checks no data resource can see (every
actor's home map exists; every sect, rank and faction resolves). There is no
`if actor == "abc"` anywhere.

The two closed vocabularies — four activities and three event kinds — are closed on purpose.
Adding to either is a code change AND a localization key, which is the friction that keeps this
from growing into a simulation of eating and sleeping.

## 10. Testing

`docs/TEST_PLAN.md` lists the Phase-08 files. The assertions that matter:
- a seeded run of K ticks produces an identical world twice, and a different seed produces a
  different one;
- `save → load → advance K` == `advance K` (the resume contract);
- `a + b` ticks == `a+b` ticks (the catch-up equivalence), and the clock is exactly as old as
  the time it was given;
- FAR → MID → NEAR → MID → FAR preserves the record, and a FAR actor is never behind an
  observed one;
- influence stops at the OWNER's ceiling and relationship history is written by the OWNER;
- a malformed snapshot leaves the simulation byte-identical;
- 200 actors × 300 ticks creates zero nodes, and a 10× FAR population does not change the
  per-tick cost;
- in the real application: the world clock advanced across 20 map transitions, the event feed
  is non-empty, zero nodes were spawned, and the HUD leaks no raw id or unsubstituted
  placeholder.
