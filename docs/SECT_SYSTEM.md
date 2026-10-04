# SECT_SYSTEM — Aetheria

> Tông môn (Sect) is a **core** system (D-011), not quest decoration. Includes internal
> factions & politics (§7). Companion to `docs/CHARACTER_SYSTEM.md`,
> `docs/RELATIONSHIP_SYSTEM.md`, `docs/WORLD_SIMULATION.md`.
>
> **Implementation status (Phase 06, D-032):** the Sect CORE is now IMPLEMENTED — the §3–§6,
> §8 contract (SectTemplateData/SectRankData/SectCatalog + SectState/SectStore/SectService +
> SectRuntime, roster-authoritative membership D-015, resources/territory/reputation/influence,
> alliance/enemy mirror to the relationship graph, serialization seam) plus a localized Sect UI
> (HUD chip + detail panel + hub banner). **Factions & internal politics (§7) are NOT yet
> implemented — that is Phase 07.** The §4 fields `factions`/`technique_ids`/`rules`/`secrets`/
> `event_hooks`/`story_flags` remain design contract only (not modeled on `SectTemplateData`/
> `SectState` yet; added when their phase needs them — anti-over-engineering).

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

**Authoritative source of truth = the Sect roster** (`leader_ref`, `elder_refs`,
`disciple_refs`; factions: `FactionState.member_refs`). The character's
`sect_id`/`faction_id`/`sect_rank` are a **derived read cache**, kept in sync via events
(`character_joined_sect`, `character_rank_changed`, `character_left_sect`) emitted by the
single Sect-service mutation owner. On load the cache is rebuilt/validated from the
roster; on any disagreement the roster wins. Full contract: `docs/DECISIONS.md` **D-015**.
Rank determines authority, technique access, and faction eligibility.

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

## 12. Scope: what is implemented vs. still a contract

**IMPLEMENTED — Phase 06 (D-032), hardened in D-037:**
- Data: `SectTemplateData` · `SectRankData` · `SectCatalog` (`src/data/sects/`, authored in
  `data/sects/*.tres`). The rank ladder's array order is the official progression and
  `authority` MUST increase strictly along it (validated). The catalog validates referential
  integrity of every declared ally/enemy — a dangling id makes the catalog invalid, so the
  session refuses to load it rather than silently skipping the pair.
- Domain: `SectState` (authoritative, serializable, roster = source of truth, D-015) ·
  `SectStore` · `SectService` (the single mutation path, with membership/economy invariants
  and the transactional, NON-DESTRUCTIVE Sect↔Sect relationship mirror). `from_dict()` is
  fail-closed, atomic AND strictly typed (a wrong type is rejected, never coerced).
- Runtime: `SectRuntime` (a node under `Main/Systems`, NOT an autoload) enrols the player
  into the authored start sect and survives map swaps. `start_session()` is FAIL-CLOSED: it
  commits nothing until the catalog, every template, every registration, the diplomacy
  mirror, the player enrolment and the derived-cache sync have all succeeded.
- UI: a localized sect HUD chip, the `sect_panel` toggle, a hub banner — all rendering a
  read-only `SectMembershipView`. No raw ids reach the screen; resource ids resolve through
  `SECT_RESOURCE_*` keys with a localized generic fallback.

**STILL A CONTRACT ONLY (not implemented):** internal factions and the politics engine,
sect techniques/rules/secrets, sect events + event resolution, succession rules, recruitment,
missions/contribution, and sect persistence through `SaveService`. Those belong to Phase 07
(Faction/Politics) and later content phases (`docs/ROADMAP.md`). Nothing above may be
anticipated with speculative fields (`.kiro/steering/03-architecture.md`).
