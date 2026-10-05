# SECT_SYSTEM — Aetheria

> Tông môn (Sect) is a **core** system (D-011), not quest decoration. Includes internal
> factions & politics (§7). Companion to `docs/CHARACTER_SYSTEM.md`,
> `docs/RELATIONSHIP_SYSTEM.md`, `docs/WORLD_SIMULATION.md`.
>
> **Implementation status (Phase 06, D-032):** the Sect CORE is now IMPLEMENTED — the §3–§6,
> §8 contract (SectTemplateData/SectRankData/SectCatalog + SectState/SectStore/SectService +
> SectRuntime, roster-authoritative membership D-015, resources/territory/reputation/influence,
> alliance/enemy mirror to the relationship graph, serialization seam) plus a localized Sect UI
> (HUD chip + detail panel + hub banner).
>
> **Factions & internal politics (§7) are IMPLEMENTED as of Phase 07 (D-042)** — in their OWN
> domain (`FactionState`/`FactionStore`/`FactionService` + `FactionRuntime`), not as a field on
> `SectState`. A faction names its parent sect; the sect does not own a list of factions. That
> keeps `SectState` unchanged and lets faction content be added without touching the sect domain.
> The §4 fields `technique_ids`/`rules`/`secrets`/`event_hooks`/`story_flags` remain design
> contract only (not modeled yet; added when their phase needs them — anti-over-engineering).

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
- **Factions:** internal politics (see §7). **As built (D-042) this is NOT a field on
  `SectState`:** a `FactionState` names its `parent_sect_id` and lives in its own
  `FactionStore`, keyed by faction id and indexed by parent sect. The sect does not own a list
  of factions. That inversion keeps `SectState` unchanged by Phase 07, lets faction content be
  authored without touching the sect domain, and means a sect with no factions costs nothing.
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

Each `FactionState` is data (no hard-coded faction). **IMPLEMENTED in Phase 07 (D-042)** —
this is the shipped shape, not a sketch:

```
FactionState:
  id: StringName
  template_id: StringName            # the FactionTemplateData it was built from
  parent_sect_id: StringName         # the sect it is internal to (required)
  leader_ref: instance_id            # must be one of member_refs; &"" = leaderless
  member_refs: Array[instance_id]    # a SUBSET of the parent sect's roster
  goals: Array[StringName]           # authored goal ids (structured; see FactionGoalData)
  influence: int                     # weight within the sect, bounded [0, 100]
  resources: Dictionary              # faction-controlled assets (int >= 0)
  stance: int                        # FactionTemplateData.Stance ordinal
  allied_faction_ids / rival_faction_ids   # DECLARED politics, mirrored to graph edges
```

**Internal politics are emergent, not scripted:** faction `influence`, `goals`, and the
Relationship graph among the factions (and among their leaders/members) drive outcomes like
succession, schism, purge, or coup. These resolve as **rules over data** on world-simulation
ticks (`docs/WORLD_SIMULATION.md`) and story events — never as a pile of per-sect booleans.
The Phase-07 rules shipped are `influence_share`, `dominant_faction_of` and `is_contested`,
all deterministic with explicit tie-breaks and **no RNG** (the seeded seam is Phase 08, D-040).

### Standings are EDGES, not inline scalars (pinned, D-042)

This section used to list `attitude_toward_player: int` and
`attitudes_toward_factions: Dictionary` as inline `FactionState` fields, and left the choice of
representation open ("a detail to pin when the Faction phase is built"). **That question is now
closed: both are DROPPED and neither is implemented.** `FactionState` has no attitude storage.

Faction↔Faction and Faction↔Player standings are **relationship edges**
(`docs/RELATIONSHIP_SYSTEM.md`), with both endpoints typed `RelationshipEndpoint.Kind.FACTION`
(or one `CHARACTER` for the player). The reason is not tidiness: `affinity` and `rivalry` are
two of the **six frozen dimensions** (CL-12), already clamped by `RelationshipConfigData` and
already carrying a bounded history log. An inline copy would answer "how does A feel about B" a
second time, with no mechanism keeping the two in step — the exact defect **D-015** had to undo
for sect membership.

What `FactionState` *does* carry is the **declared** relation (`allied_faction_ids` /
`rival_faction_ids`): a political fact the sect has announced, not a measured standing. Same
split `SectState` already uses for declared ally/enemy, and `FactionService` keeps the
declaration and the mirrored edge transactionally in step (relationship side first, checked;
an existing edge of the wrong type is **retyped in place**, never destroyed — L-023).

### Membership and the player (D-042)

A faction seat requires **existing parent-sect membership** — the sect roster remains the single
membership authority (D-015) — and a character may hold **one seat per sect**, which is what
makes `CharacterState.faction_id` a valid single value. Phase 07 is that field's only writer.

Phase 07 **enrols nobody**. The authored start sect is a scaffold (C-003); making it an authored
*faction* allegiance would hand the player a political identity they never chose. Factions ship
leaderless and memberless, `FactionRuntime.start_session` asserts that as a post-condition, and
taking a side becomes a gameplay act from P-17 onward.

## 8. Serialization

`SectState` is persistent domain state, written to the save's
`sects` section (`docs/SAVE_FORMAT.md`), keyed by sect `id`, referencing character
`instance_id`s and other sect `id`s. No presentation data. Alliances/enmities are mirrored
as Sect↔Sect relationship edges so there is one consistent graph.

`FactionState` serializes **alongside** it, not inside it: `FactionStore.to_dict()` emits a
`factions` list (sorted by id, so the snapshot is byte-stable), each entry carrying its own
`parent_sect_id`. Declared faction politics is likewise mirrored as Faction↔Faction edges in the
same graph, under the `faction_rel:` edge-id namespace so it can never collide with the
`sect_rel:` mirror. Standings themselves are NOT serialized here — they are dimensions on those
edges (D-042, see §7).

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

**IMPLEMENTED — Phase 07 (D-042):**
- Data: `FactionGoalData` · `FactionTemplateData` · `FactionCatalog` (`src/data/factions/`,
  authored in `data/factions/*.tres`). A template validates itself; the catalog validates what
  only exists BETWEEN templates (unique ids, declared politics resolving to real factions, those
  factions **sharing a parent sect**, and pair symmetry). A dangling or one-sided declaration
  makes the catalog invalid.
- Domain: `FactionState` (authoritative, serializable, strictly-typed fail-closed `from_dict`) ·
  `FactionStore` (with a `sect_id -> [faction_id]` index, so the politics queries the UI makes on
  every refresh are not full scans) · `FactionService` (the single mutation path; it READS the
  sect roster as the membership authority and the relationship graph as the standings authority,
  and duplicates neither).
- Runtime: `FactionRuntime` (a node under `Main/Systems`, NOT an autoload) starts LAST because it
  reads both the sect store and the relationship graph, and is ended FIRST on EVERY teardown —
  a failed start and a normal return to menu alike (one ordered path, D-047).
  `start_session()` is FAIL-CLOSED and commits nothing until the catalog, every template, every
  registration, the cross-store parent-sect check, the politics mirror and the post-conditions
  have all succeeded.
- Rules (deterministic, no RNG): `influence_share` · `dominant_faction_of` (ties broken by
  lexicographically smaller id) · `is_contested`.
- UI: the `faction_panel` toggle rendering a read-only `SectPoliticsView` in the D-041 visual
  language. No raw id or enum ordinal reaches the screen; status is carried by words, not colour.
- Content: three Thanh Vân Tông factions (`WORLD_BIBLE` §8), a real disagreement with no villain.

**STILL A CONTRACT ONLY (not implemented):** sect techniques/rules/secrets, sect events + event
resolution, succession rules, recruitment, missions/contribution, faction-driven schism/purge/coup
outcomes (those need the world-simulation tick, P-08) and sect/faction persistence through
`SaveService` (P-23). Those belong to later phases (`docs/ROADMAP.md`). Nothing above may be
anticipated with speculative fields (`.kiro/steering/03-architecture.md`).
