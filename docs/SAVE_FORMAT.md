# SAVE_FORMAT — Aetheria

> Save system design. Owned by `SaveService` (persistence layer). No other system knows
> the on-disk format; each system exposes `to_dict()` / `from_dict()` and SaveService
> orchestrates (`.kiro/steering/03-architecture.md`).
>
> Status: **design only.** No save code exists yet. The on-disk shape below is a sketch; two
> binding REQUIREMENTS were added in D-040 (§3b: deterministic resume, and knowledge as its own
> serialized block) which the Phase-23 implementation must satisfy.

## 1. Non-negotiables

- **Every save has a `save_version`.** This exists from day one so schema changes can be
  migrated later without breaking old saves.
- Save is **data**, serialized from each system's serializable state. Enemies, UI, and
  presentation never touch the save format.
- Load **validates** and **migrates** before handing state back; never trust a save file
  blindly (it's external input — validate at the boundary).

## 2. Versioning & migration

- `save_version` is an integer, bumped on any breaking schema change.
- `SAVE_VERSION_CURRENT` is a constant in `SaveService`.
- On load: if `save_version < current`, run ordered migrations
  `v(n) → v(n+1) → … → current`. Migrations live in `src/persistence/save_migrations/`.
- A migration is pure data transformation + a test proving `old → new` works. Phase 23
  demonstrates a v1→v2 migration as its exit criterion (`docs/ROADMAP.md`).
- Unknown/newer `save_version` (from a future build) → refuse to load with a clear
  localized message, don't corrupt it.

## 3. Snapshot contents (what a save holds)

```
SaveFile:
  save_version: int
  created_at: int (unix)
  updated_at: int (unix)
  playtime_seconds: int
  slot_meta: { chapter_id, player_level, realm_id, location_name_key }  # for menu display

  player:
    stats_current: { hp, mana, ... }        # current, not just max
    position: { map_id, x, y }
  progression:
    level: int
    xp: int
    realm_id: StringName                     # cảnh giới
    cultivation_progress: int                # tu luyện toward next realm
    unlocked_skills: Array[StringName]
    unlocked_techniques: Array[StringName]
  inventory:
    items: Array[{ item_id, count }]
    currency: int
  equipment:
    slots: Dictionary { slot -> equip_id }
  skills:
    equipped: Array[StringName]
    cooldowns: Dictionary                     # usually reset on load; stored if needed
  pets:
    owned: Array[{ pet_id, level, xp, stats_current }]
    active_pet: StringName
  quests:
    log: Array[{ quest_id, state, objective_progress }]
  story:
    chapter_id: StringName
    completed_chapters: Array[StringName]
    flags: Dictionary { flag -> value }
    choices: Dictionary
  characters:                                 # core system — docs/CHARACTER_SYSTEM.md
    by_instance_id: Dictionary                # instance_id -> CharacterState (persistent tier only)
    player_instance_id: StringName            # the player is a Character
    # NOTE: each CharacterState's sect_id/faction_id/sect_rank are a DERIVED cache;
    # the authority is the sect roster below and is rebuilt from it on load (D-015).
  relationships:                              # core system — docs/RELATIONSHIP_SYSTEM.md
    edges: Array[RelationshipEdge]            # one graph: Char↔Char, Player↔Char, Char↔Sect
  sects:                                      # core system — docs/SECT_SYSTEM.md
    by_id: Dictionary                         # sect_id -> SectState (incl. FactionState[])
  world_sim:                                  # core system — docs/WORLD_SIMULATION.md
    # IMPLEMENTED (D-048). `WorldSimulationState.to_dict()` produces exactly this block; the
    # full field list is in docs/DATA_SCHEMA.md. The §3b requirement below is SATISFIED here:
    # `rng_streams` carries each stream's position, not just the seed.
    schema: int
    world_clock: { tick, ticks_per_hour, hours_per_day, days_per_season, seasons_per_year }
    rng_seed: int
    rng_streams: Dictionary                   # stream_id -> { state, draws }
    pending_transitions: Array                # [{ due_tick, event_id }]
    carry_over_ticks: int                     # unspent simulation time; dropping it loses world time
    actors: Dictionary                        # instance_id -> per-actor simulation tier
    event_log: Array
    event_log_capacity: int
  world:
    map_states: Dictionary                    # per-map persistent bits (opened chests, cleared, ...)
  rng:
    seed: int                                 # for reproducibility/determinism
```

> Note: `player` above is a convenience view; the player's authoritative state is a
> `CharacterState` in `characters` (keyed by `player_instance_id`). Only the **persistent
> tier** of each character/sect is serialized (runtime/presentation tiers are rebuilt on
> load) — see `docs/CHARACTER_SYSTEM.md` §3.

All content references are **ids** (see `docs/DATA_SCHEMA.md`), so a save stays valid as
long as the referenced ids still exist. Removing a shipped id is a breaking content
change requiring a migration.

## 3b. Deterministic resume requirement (D-040 — requirement only, not a shape)

The sketch above shows a single `rng: { seed }` block. That is **not sufficient**, and the gap is
recorded here now rather than discovered in Phase 23.

**The requirement (frozen):** a load must be able to resume world evolution **exactly** — the same
seed and the same simulation state must produce the same future world. Concretely, the save must
restore the **world seed** *plus* whatever per-stream state is needed to continue each
deterministic sequence where it left off (`SYSTEM_DEPENDENCY_MATRIX.md` §4c: one run/world seed
fanning out into per-subsystem streams — world sim, combat, enemy AI, loot, …).

**Why a single seed is not enough.** A seed alone only reproduces a run *from the beginning*. A
save taken 40 hours in must also record **how far each stream has advanced**, or the post-load
world diverges from the pre-load world — which breaks `WORLD_SIMULATION.md` §5's save-resumable
guarantee, breaks reproducible bug reports, and breaks any future server-advanced world
(`MULTIPLAYER_PLAN.md` §7 lists non-determinism as a corner-painting risk).

**What is deliberately NOT frozen:** whether stream state is a counter, an algorithm state blob,
or a re-derivable `(seed, stream_id, draw_count)` triple; the field names; and where the block
sits in the file. Those are decided by the phase that implements the RNG seam (**P-08**) and the
phase that implements persistence (**P-23**) — this section only guarantees they will not be
*forgotten*.

> **SETTLED by P-08 (D-048) for the simulation's half.** Stream state is a **32-bit counter plus
> a draw count**, written as `rng_streams: { stream_id -> { state, draws } }` inside the
> `world_sim` block above (the counter alone reproduces the sequence; the draw count is kept
> because it is the one number that makes a determinism failure diagnosable — it distinguishes
> "a different value was drawn" from "a different NUMBER of values was drawn"). A deliberately
> hand-rolled mixer was chosen over the engine's `RandomNumberGenerator` for exactly the reason
> this section exists: the generator's state is part of the save format, and an engine-internal
> state blob would tie a player's world to an implementation detail we do not control and cannot
> migrate. The **resume contract is now asserted by test**:
> `save → load → advance K ticks` produces the identical world to `advance K ticks` on a run that
> never stopped. Besides the stream positions it needs three more things the sketch above did not
> name — the **pending event queue** (a recurring event's next due tick is computed when it
> fires), the **carry-over tick debt**, and each actor's **`joined_tick`**. P-23 still owns the
> file-level format, versioning and migration.

Also in scope of the same requirement: the **Knowledge Core**'s acquired-id set is persistent
domain state owned by `KnowledgeService`/`KnowledgeStore` (CL-14), so it serializes like any other
core system — through its own `to_dict`/`from_dict`, **not** inside the `story` block (C-012).

> **Session block (GameState) — D-018.** The run's lifecycle state is produced by
> `GameState.to_dict()` and holds **only run identity + location**:
> `run_id`, `current_world_id`, `current_map_id`, `current_scene_key`. It deliberately
> does **not** store the runtime lifecycle phase or a `session_active` flag — "a run
> exists" is derived from the presence of `run_id`. On load, `SaveService` calls
> `GameState.hydrate_session(block)` (data only; it does not drive the lifecycle) and then
> transitions the lifecycle to `RUNNING` through the normal path. This guarantees a save
> can never reconstruct an impossible phase/active combination.

## 4. Serialization mechanism (decision pending — D-005)

Options to decide in `DECISIONS.md` before Phase 23:
- **JSON** (`JSON.stringify` over plain dicts) — human-readable, easy to debug/migrate,
  version-friendly. Default lean.
- **Godot `Resource`/binary (`.tres`/`.res`)** — convenient but couples save to class
  layout, harder to migrate across refactors.
- Optional later: obfuscation/checksum to discourage casual edits (not security).

Default lean: **JSON of plain dictionaries** built from each system's `to_dict()`, for
migration-friendliness and testability.

## 5. Slots & atomicity

- Multiple named slots + an autosave slot.
- **Atomic write:** write to a temp file, then rename over the target, so a crash mid-save
  can't corrupt the existing save.
- Keep the previous autosave as a backup where cheap.

## 6. Save points in the flow

Save can occur at checkpoints (village, pre/post boss, chapter transition), manually
from a menu, and on quit. See the SAVE box in `docs/GAME_FLOW.md`.

## 7. Testing (high-risk area)

- Round-trip: every system's state `to_dict → from_dict` reconstructs equal state.
- Migration: `v(n)` fixture loads and upgrades to current, asserted field-by-field.
- Corruption: truncated/garbage/newer-version files fail safely with a clear message,
  never a crash or silent data loss.
See `docs/TEST_PLAN.md`.

## 8. Multiplayer note

The save snapshot is intentionally the same serializable state the Stage-2
authoritative server would own (player/world/inventory/progression). Keeping persistence
clean now is also multiplayer groundwork — see `docs/MULTIPLAYER_PLAN.md`. No networking
in Stage 1.
