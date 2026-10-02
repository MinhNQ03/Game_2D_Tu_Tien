# SAVE_FORMAT — Aetheria

> Save system design. Owned by `SaveService` (persistence layer). No other system knows
> the on-disk format; each system exposes `to_dict()` / `from_dict()` and SaveService
> orchestrates (`.kiro/steering/03-architecture.md`).
>
> Status: **design only.** No save code exists yet.

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
- A migration is pure data transformation + a test proving `old → new` works. Phase 17
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
    world_clock: int
    pending_transitions: Array
    rng_seed: int
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

## 4. Serialization mechanism (decision pending — D-005)

Options to decide in `DECISIONS.md` before Phase 17:
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
