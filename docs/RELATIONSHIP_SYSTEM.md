# RELATIONSHIP_SYSTEM — Aetheria

> **Design only. No gameplay implemented.** Defines relationships between Characters,
> between the Player and Characters, and between Characters and Sects as serializable
> domain state. Companion to `docs/CHARACTER_SYSTEM.md` and `docs/SECT_SYSTEM.md`.

## 1. Position in the architecture

Relationships are **domain state** — pure, serializable, presentation-free. They are
owned by a Relationship service/store, **not** duplicated inside each Character node.
A Character holds a handle and queries the store. This keeps a single source of truth and
makes the data trivially serializable and (later) replicable
(`docs/MULTIPLAYER_PLAN.md`).

## 2. Core dimensions (data, not hard-coded behavior)

A relationship edge between two parties carries a small set of named scalar dimensions.
These are **data**; gameplay logic interprets them, but the numbers live in state:

| Dimension | Meaning | Typical range |
|---|---|---|
| **affinity** | overall like/dislike | -100 … +100 |
| **trust** | willingness to rely on / confide | 0 … 100 |
| **respect** | regard for strength/virtue/status | 0 … 100 |
| **fear** | intimidation / threat perceived | 0 … 100 |
| **rivalry** | competitive antagonism | 0 … 100 |
| **debt** | owed favors/obligations (signed: +owed to them, -they owe) | -100 … +100 |

Ranges are tuning data (`.kiro/steering/04-coding-standards.md`: no magic numbers in
code). The dimension list is extensible — add a dimension in the schema, not in scattered
logic.

## 3. Relationship type

Beyond scalars, an edge has a **relationship_type** (a StringName from a vocabulary),
e.g. `MASTER_DISCIPLE`, `SECT_SIBLING`, `FAMILY`, `FRIEND`, `RIVAL`, `ENEMY`,
`ALLY`, `SWORN`, `STRANGER`, `ROMANTIC`. Type gives qualitative context; the scalars give
quantitative state. Both are serialized.

## 4. Edge model (who ↔ who)

A relationship is a directed or symmetric **edge** between two endpoints. Endpoints can be
a Character instance or a Sect (so the three required axes are covered):

```
RelationshipEdge:
  id: StringName                 # stable edge id
  from_ref: Ref                  # Character instance_id OR Sect id
  to_ref: Ref                    # Character instance_id OR Sect id
  relationship_type: StringName
  dimensions: Dictionary         # { affinity, trust, respect, fear, rivalry, debt }
  symmetric: bool                # if true, both directions share one edge
  known: bool                    # is this relationship public/known?
  history: Array                 # optional capped log of notable changes (data)
```

An **endpoint** is a typed reference, never a bare String: `{ kind, id }` where `kind` is
`CHARACTER` or `SECT`. So the character instance `"player"` and a sect `"sect_azure"` can
never be confused even if they shared a raw id string. Endpoints serialize as
`{ "kind": "character", "id": "player" }`.

### Required expansion paths (all supported by the same edge model)
- **Character ↔ Character** — `from`/`to` are both `CHARACTER` endpoints (character
  `instance_id`s).
- **Player ↔ Character** — the player is a Character (`CHARACTER_SYSTEM.md`), so it's the
  same edge model; no special case.
- **Character ↔ Sect** — one endpoint is a `SECT` endpoint (`SECT_SYSTEM.md`). Lets a
  character have standing with an organization (loyalty, grievance, debt to the sect).

### Directed vs. symmetric (semantic contract — Phase 05)
`symmetric` is NOT a cosmetic flag; it changes identity and query semantics:

- **DIRECTED** (`symmetric = false`): `A → B` and `B → A` are two *different* relationships
  and may both exist as separate edges. A query for `from=A, to=B` returns only the A→B
  edge. All dimensions are read as stored (`from`'s perspective of `to`).
- **SYMMETRIC** (`symmetric = true`): ONE edge represents the single shared relationship
  between A and B. To guarantee `A-B` and `B-A` can never create two different graph
  entries, a symmetric edge is stored with a **canonical endpoint order**: the two
  endpoints are compared by `(kind, id)` (kind first, then id, lexicographically) and the
  *smaller* becomes `from_ref`, the larger `to_ref`. `find_between(A, B)` and
  `find_between(B, A)` therefore resolve to the exact same edge, and creating `B-A` when
  `A-B` already exists is a **duplicate** (rejected), not a second edge.

### Debt perspective (signed dimension) — Phase 05
`debt` is the only **signed, directional-meaning** dimension: it is stored from the
**canonical `from_ref`'s perspective** (`+` = `to_ref` owes `from_ref`; `−` = `from_ref`
owes `to_ref`). This matters only for symmetric edges, where a caller may query from either
side:

- Querying a symmetric edge **in canonical order** (`from = canonical from`) returns `debt`
  as stored.
- Querying it **reversed** (`from = canonical to`) returns `debt` **negated**, so each side
  reads "how much the other owes me" correctly.
- The non-directional dimensions — `affinity`, `trust`, `respect`, `fear`, `rivalry` — are
  **never** sign-flipped on a reverse query; they describe the shared bond identically from
  both sides.
- A **directed** edge is always read exactly as stored (`from → to`), debt included; there
  is no perspective flip because a directed edge has only one perspective.

## 5. How relationships change (design intent, not code)

Relationships shift from **events**, never from scattered ad-hoc writes:
- Combat, gifts, quests, dialogue choices, betrayals, sect actions, and world-simulation
  ticks emit domain events; a relationship rule maps an event → dimension deltas.
- All changes go through the Relationship service so every change is observable
  (emits `relationship_changed(edge_id, dimension, old, new)`), testable, and persisted.

Decay/propagation (e.g. rivalry cooling over time, a sect's enmity coloring its members'
affinity toward an outsider) are **rules over data**, documented when the phase is built —
not hard-coded per character.

## 6. Serialization

The entire relationship graph is persistent domain state and is written to the save's
`relationships` section (`docs/SAVE_FORMAT.md`), keyed by edge `id`, referencing
character `instance_id`s and sect `id`s. No presentation data. On load, the graph is
restored verbatim; views are rebuilt.

## 7. Performance note (ties to World Simulation)

The graph can grow large. Design guidance (detail in `docs/PERFORMANCE.md` /
`docs/WORLD_SIMULATION.md`): don't recompute the whole graph per frame; update edges on
events; for far-from-player characters, batch/abstract relationship evolution on
simulation ticks rather than real time. Measure before optimizing.

## 8. Multiplayer readiness

The relationship graph is exactly the kind of **authoritative world state** a server
would own. Keeping it a serializable domain store (not scattered on nodes) is intended to
let Stage 2 replicate it with minimal changes to core code. Added to
`docs/MULTIPLAYER_PLAN.md`. No networking now.

## 9. Testing (high-risk once implemented)

- Edge create/update/query round-trips through save.
- An event produces the exact documented dimension deltas (deterministic).
- Character↔Sect edges resolve correctly when a referenced sect/char exists.
See `docs/TEST_PLAN.md`.

## 10. Referential integrity (Phase 05 vs. Phase 06)

Phase 05 ships the graph with **structural** support for both `CHARACTER` and `SECT`
endpoints, but it does NOT validate that a referenced sect actually exists — there is no
`SectState` yet (Phase 06). A `SECT` endpoint is a well-formed, serializable reference; its
existence/standing against a real sect roster is validated in **Phase 06** (canonical
membership, sect lifecycle, D-015). Phase 05 must NOT fabricate a fake production SectState
to make tests pass.

## 11. Implementation status (Phase 05, D-026)

Phase 05 implements the core relationship domain (this doc §1–§8) as:

- `RelationshipEndpoint` (`src/domain/relationship/relationship_endpoint.gd`, `RefCounted`)
  — typed `{ kind, id }` endpoint with canonical compare + plain-data serialize.
- `RelationshipEdge` (`src/domain/relationship/relationship_edge.gd`, `RefCounted`) — id /
  from / to / relationship_type / dimensions / symmetric / known / history.
- `RelationshipConfigData` (`src/data/relationship/relationship_config_data.gd`, `Resource`)
  — per-dimension default/min/max + `history_capacity`, validated at the boundary; authored
  `data/relationship/relationship_config.tres` carries the §2 default ranges. **No dimension
  range is a magic number in code** — the service reads the config.
- `RelationshipRuleData` + `RelationshipRuleCatalog`
  (`src/data/relationship/*`) — the minimal deterministic **event → dimension deltas**
  contract (§5): `event_kind -> { dimension: delta }`. No RNG, no DSL.
- `RelationshipStore` (`src/domain/relationship/relationship_store.gd`, `RefCounted`) — owns
  the edges, indexes **by edge id** and **by endpoint**, enforces symmetric canonical order,
  and serializes/hydrates deterministically (sorted by edge id).
- `RelationshipService` (`src/domain/relationship/relationship_service.gd`, `RefCounted`) —
  the SINGLE mutation path (`create_edge`/`apply_delta`/`apply_event`/`remove_edge`): clamps
  to config range, writes bounded history on a real change, and emits the domain signal
  `relationship_changed(edge_id, dimension, old_value, new_value, cause)`. A zero-effect
  delta is a no-op (no history, no signal); a missing edge fails loud (no implicit create).
- `RelationshipRuntime` (`src/gameplay/world/relationship_runtime.gd`, a `Node` under
  `Main/Systems`, **NOT an autoload**) — owns the store+service+config for the session and
  survives map transitions. It knows nothing about presentation/dialogue/quest/sect politics.

`CharacterState` is deliberately **not** given a relationship dictionary (§1 single source
of truth). Still NOT in Phase 05: relationship UI, NPC/dialogue/quest/story/faction/
world-sim consumers, sect referential validation, and save orchestration
(`RelationshipStore.to_dict/from_dict` is the ready seam; `SaveService` is Phase 23).
