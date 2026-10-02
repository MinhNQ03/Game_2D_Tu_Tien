# SECT_SYSTEM — Aetheria

> **Design only. No gameplay implemented.** Tông môn (Sect) is a **core** system
> (D-011), not quest decoration. Includes internal factions & politics (§7). Companion
> to `docs/CHARACTER_SYSTEM.md`, `docs/RELATIONSHIP_SYSTEM.md`, `docs/WORLD_SIMULATION.md`.

## 1. Why Sect is core

In a tu tiên world, sects are the primary social, political, and power structures. The
player may join, rise within, betray, found, or destroy sects. Sects own territory,
resources, techniques, and reputations; they ally and war with each other; and they have
**internal politics** that evolve even off-screen. Sects must therefore be first-class,
data-driven, serializable domain entities.

## 2. Layering & boundaries

- **Authoritative sect state is domain, serializable, presentation-free.** UI shows a
  view; it never owns sect rules (`.kiro/steering/03-architecture.md`).
- A Sect does **not** contain save logic; it exposes `to_dict()`/`from_dict()` and
  `SaveService` orchestrates (`docs/SAVE_FORMAT.md`).
- Sects relate to characters and other sects **only** through the Relationship store
  (`docs/RELATIONSHIP_SYSTEM.md`) and the EventBus — not by cross-tree references.

## 3. Data-driven: add a sect without touching core

- `SectTemplateData` (`sect_*`) — the *definition*: identity, doctrine, rank ladder,
  default factions, starting resources/territory/techniques, rules, default alliances /
  enemies, reputation seeds. Display text = localization **keys**.
- `SectState` — the *runtime instance* in a save: current leader, elders, disciple roster
  (character `instance_id`s), live faction states, current resources/territory,
  reputation/influence, active alliances/enemies, discovered secrets, story flags.

A new sect = a new `SectTemplateData` `.tres` (+ optional content scenes for its physical
locations). No engine change — the extensibility invariant (`docs/GAME_FLOW.md`).

## 4. Sect fields (full set this system must support)

- **Identity:** `id`, `name_key`, `emblem_ref`, `type` (e.g. ORTHODOX / DEMONIC /
  NEUTRAL / HIDDEN), `tier` (minor … great sect).
- **Doctrine:** `doctrine_key` — the sect's philosophy; shapes which công pháp/techniques
  it teaches and acceptable conduct.
- **Leader:** `leader_ref` (character `instance_id`).
- **Elders:** `elder_refs` (Array[instance_id]).
- **Disciples:** `disciple_refs` (Array[instance_id]) — membership; each member also
  carries `sect_id`/`sect_rank` on their `CharacterState`.
- **Ranks:** `rank_ladder` (ordered Array of `{ rank_id, name_key, authority }`) —
  e.g. Outer Disciple → Inner Disciple → Core Disciple → Elder → Sect Master.
- **Factions:** `factions` (Array[FactionState]) — internal politics (see §7).
- **Internal politics:** emergent from faction states + relationships (see §7).
- **Resources:** `resources` (Dictionary: spirit stones, pills, materials, manpower).
- **Territory:** `territory` (Array of region/map `id`s controlled).
- **Reputation:** `reputation` (Dictionary `{ scope -> value }`).
- **Influence:** `influence` (political weight in the wider world).
- **Alliances:** `ally_sect_ids` (Array) — reflected as Sect↔Sect relationship edges.
- **Enemies:** `enemy_sect_ids` (Array) — likewise.
- **Techniques:** `technique_ids` (công pháp the sect can teach; gated by rank/doctrine).
- **Rules:** `rules` (Array of `{ rule_id, text_key, penalty }`) — breaking them changes
  reputation/relationships, may trigger events.
- **Secrets:** `secrets` (Array of `{ secret_id, known_by }`) — hidden techniques,
  forbidden history, true allegiance.
- **Events:** `event_hooks` (data references to sect-level events the world sim/story can
  fire — succession crisis, war, tribulation).
- **Story state:** `story_flags` (Dictionary) local to the sect.

## 5. Membership & rank (how a character belongs)

Membership is expressed on both sides, with the Sect roster as the authority and the
character's `sect_id`/`sect_rank` as a denormalized convenience that must stay in sync via
events (`character_joined_sect`, `character_rank_changed`, `character_left_sect`). Rank
determines authority, technique access, and faction eligibility.

## 6. Events (EventBus)

Emits: `sect_leader_changed`, `sect_rank_changed`, `sect_resource_changed`,
`sect_alliance_changed`, `sect_war_declared`, `sect_event_triggered`, `faction_shift`.
Consumes: character deaths/defections, relationship changes, world-simulation ticks.
Emitters never import listeners.

## 7. Factions & internal politics (CORE requirement)

A sect may contain **multiple internal factions**:

```
Sect
├── Faction A
├── Faction B
└── Faction C
```

Each `FactionState` is data (no hard-coded faction):

```
FactionState:
  id: StringName
  name_key: StringName
  leader_ref: instance_id            # a character (often an elder)
  member_refs: Array[instance_id]
  goals: Array                       # structured goals (power, doctrine, secession, …)
  influence: int                     # weight within the sect
  resources: Dictionary              # faction-controlled assets
  attitude_toward_player: int        # scalar, data (not hard-coded)
  attitudes_toward_factions: Dictionary  # { other_faction_id -> scalar }
  stance: StringName                 # LOYALIST / REFORMIST / RADICAL / NEUTRAL / ...
```

**Internal politics are emergent, not scripted:** faction `influence`, `goals`, and the
`attitudes_*` scalars (plus the Relationship graph among their leaders/members) drive
outcomes like succession, schism, purge, or coup. These resolve as **rules over data**
on world-simulation ticks (`docs/WORLD_SIMULATION.md`) and story events — never as a pile
of per-sect booleans. Attitudes toward the player and toward other factions are explicit
serializable scalars so the player can navigate (or exploit) sect politics.

Faction↔Faction and Faction↔Player standings reuse the Relationship model
(`docs/RELATIONSHIP_SYSTEM.md`) where a richer edge is useful; simple scalars live inline
on the `FactionState` as above. (Which representation wins where is a detail to pin when
the Faction phase is built; both are serializable.)

## 8. Serialization

`SectState` (incl. all `FactionState`s) is persistent domain state, written to the save's
`sects` section (`docs/SAVE_FORMAT.md`), keyed by sect `id`, referencing character
`instance_id`s and other sect `id`s. No presentation data. Alliances/enmities are mirrored
as Sect↔Sect relationship edges so there is one consistent graph.

## 9. Performance (ties to World Simulation)

Hundreds of sect members must not tick every frame. Sect/faction politics evolve on
batched simulation ticks and events, with detail scaling by distance from the player
(`docs/WORLD_SIMULATION.md`). Measure before optimizing (`docs/PERFORMANCE.md`).

## 10. Multiplayer readiness

Sect + faction + world-event state is authoritative world state a server would own.
Keeping it a serializable domain store is Stage-2 groundwork. Added to
`docs/MULTIPLAYER_PLAN.md`. No networking now.

## 11. Testing (high-risk once implemented)

- `SectState` (with factions) round-trips through save.
- Adding a sect purely via `SectTemplateData` works with no core edits.
- Membership/rank changes stay in sync across Sect roster and `CharacterState`.
- A faction influence/attitude change produces documented, deterministic outcomes.
See `docs/TEST_PLAN.md`.

## 12. Explicitly NOT in this step

No sect gameplay, no politics engine, no UI, no event resolution implemented. This is the
contract for the Sect and Faction/Politics phases (`docs/ROADMAP.md`).
