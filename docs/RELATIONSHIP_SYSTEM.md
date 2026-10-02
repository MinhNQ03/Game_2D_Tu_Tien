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

### Required expansion paths (all supported by the same edge model)
- **Character ↔ Character** — `from`/`to` are both character `instance_id`s.
- **Player ↔ Character** — the player is a Character (`CHARACTER_SYSTEM.md`), so it's the
  same edge model; no special case.
- **Character ↔ Sect** — `to_ref` is a Sect `id` (`SECT_SYSTEM.md`). Lets a character
  have standing with an organization (loyalty, grievance, debt to the sect).

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

## 10. Explicitly NOT in this step

No relationship gameplay, no UI, no event→delta rules implemented. This is the contract
for the Relationship phase (`docs/ROADMAP.md`).
