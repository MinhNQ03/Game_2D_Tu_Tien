# 03 — Architecture (rules)

> Steering: always included. The binding architectural rules. The full narrative
> design lives in `docs/ARCHITECTURE.md`; this file is the short, enforceable rulebook.

## Layers (strict direction of dependency)

```
presentation  →  gameplay  →  domain (game rules)  →  data
                      ↓                                   ↑
               infrastructure  ←───────────  persistence ─┘
```

- **presentation** — scenes, UI, HUD, input mapping, animation, audio, VFX.
- **gameplay** — nodes that coordinate entities in a running scene (spawning,
  encounters, map transitions, combat orchestration).
- **domain / game rules** — pure logic: damage formula, XP curve, cultivation
  breakthrough rules, quest state machine. No Godot node dependencies where avoidable.
- **data** — Resources (`.tres`/custom `Resource`) describing items, skills, enemies,
  công pháp, dialogue, quests. Content, not behavior.
- **persistence** — save/load, versioning, migration.
- **infrastructure** — cross-cutting services: event bus, localization, logging, RNG,
  config, scene router.

**Dependencies point downward/inward only.** Presentation may call gameplay; domain
must not reach up into presentation.

## Hard boundaries (non-negotiable)

- UI must **not** decide gameplay rules. UI reads state and sends intents; rules live
  in the domain layer.
- An enemy must **not** contain save-game logic.
- The player must **not** directly manage an inventory database/persistence. It owns
  an inventory *component*; persistence serializes it.
- The domain layer must **not** import presentation.

## Preferred mechanisms

- **Composition over inheritance.** Entities are nodes composed of components
  (Health, Stats, Inventory, Hitbox, Hurtbox, AI, etc.), not deep class trees.
- **Signals / events for cross-system reactions.** Combat emits; quests/UI/progression
  listen. Emitters never depend on listeners.
- **Data-driven design.** New content = new Resource + content scene.
- **Dependency inversion where it pays off.** Depend on a small interface/contract, not
  a concrete, when a seam is genuinely needed (e.g. save target, RNG source).
- **Loose coupling.** Prefer a global event bus (one documented autoload) over nodes
  reaching across the tree with `get_node("../../..")`.

## Autoload / singleton policy

Singletons are a **budget, not a default**. Each autoload must be justified in
`docs/DECISIONS.md`. Anticipated minimal set (added only when first needed):

- `EventBus` — global signals.
- `GameState` — current run/session state (not a dumping ground).
- `SceneRouter` — scene transitions / map loading.
- `Localization` — language + translation lookup.
- `SaveService` — persistence entry point.
- `Config` / `RNG` — tunables and seeded randomness.

No arbitrary global mutable state outside these, and even these expose intent-revealing
methods, not raw public fields to be mutated anywhere.

## Anti-over-engineering

Do not introduce an abstraction, interface, or system until there is a concrete second
use case or a real seam (save, localization, multiplayer boundary). Flag speculative
generality in review (`.kiro/steering/08-ai-review-protocol.md`).

## Core social / world systems (domain-authoritative)

Character, Relationship, Sect, Faction, and World-Simulation are **core domain systems**
(D-011), not quest add-ons. Rules for them:
- Authoritative state lives in the **domain** layer, serializable, presentation-free.
  Presentation renders a *view*; it never owns character/sect/relationship truth.
- State is partitioned into **persistent / runtime / presentation** tiers; only the
  persistent tier is saved and (later) server-owned.
- They are **data-driven**: add a character/sect/faction via Resources + content, not core
  edits.
- They communicate via the EventBus; emitters never import listeners.
Design docs: `docs/CHARACTER_SYSTEM.md`, `docs/RELATIONSHIP_SYSTEM.md`,
`docs/SECT_SYSTEM.md`, `docs/WORLD_SIMULATION.md`.

## Multiplayer-ready seams (keep clean now, wire later)

Keep these independently serializable and free of presentation coupling so Stage 2 can
add authority/replication with minimal changes to core code: player state, combat
commands, world state, inventory, progression, authoritative state, persistence,
**character state,
relationship state, sect state, faction state, world-event/sim state** (in
persistent/runtime/presentation tiers). The TARGET model is frozen by D-056 as an
**authoritative dedicated server**, contracted in `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md`
(five version domains, twelve boundaries, command/intent shape, identity split, vendor-neutral
adapter slots) — **target, not implementation**. Offline and online run the SAME domain rules
and differ only in authority and transport. Per-seam readiness: `docs/MULTIPLAYER_PLAN.md`.
**No networking
code or dependency in Stage 1.**
