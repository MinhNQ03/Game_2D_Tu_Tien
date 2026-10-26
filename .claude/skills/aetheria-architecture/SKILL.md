---
name: aetheria-architecture
description: Aetheria architecture rules - layer direction, one owner per state, autoload budget, save/hydrate safety, signals, data-driven content, multiplayer seams. Use before adding or moving gameplay code.
---

# Aetheria architecture — the rules code must keep

Owners (they win): `.kiro/steering/03-architecture.md`, `docs/ARCHITECTURE.md`,
`docs/SYSTEM_DEPENDENCY_MATRIX.md`, `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md`, `docs/SAVE_FORMAT.md`,
`docs/DATA_SCHEMA.md`, `docs/DECISIONS.md` (cite `D-nnn`). Reviewer: `aetheria-architecture-reviewer`.

## Layers — dependencies point down only
```
presentation → gameplay → domain (rules) → data
                  ↓                          ↑
           infrastructure  ←──────  persistence
```
- UI reads state and sends INTENTS; it never decides a rule.
- Domain never imports presentation; a "domain" class typed on a `Node` is an upward dependency
  (L-036). A gameplay/domain file that writes a colour is in the wrong layer (L-037).
- Animation is a follower, never an authority: "frame 7 reached" never triggers damage (L-041).
- Presentation never writes the simulation clock; a hit-stop freezes an IMAGE (D-057).

## State
- One owner per state, in tiers: **persistent / runtime / presentation**. Only persistent is saved.
- Character, relationship, sect, faction, world-simulation are core domain systems (D-011).
- Autoloads are a frozen budget of FIVE (D-017, `GAME_DESIGN_FREEZE.md` §5): `EventBus`,
  `GameState`, `Localization`, `InputService`, `SceneRouter`. No new autoload. Go through the
  owning service, never its raw vocabulary (L-003). Fail loud when a REQUIRED service is missing at a real boot (L-004).

## Save / load / transactions
- Never serialize runtime lifecycle (phase, "active") — persist identity + data; derive flags (L-001).
- Hydrate: check `typeof()` FIRST and reject, then coerce (L-024); return bool, fail loud.
- Never destroy the old value before the replacement succeeded; list every side effect before
  the commit point (L-023, L-056). A session starter builds into locals and commits last (L-025).
- The save version is bumped on any breaking schema change, with a migration + test (`docs/SAVE_FORMAT.md`).

## Signals and data
- Emitters never depend on listeners. Add a signal/API only with a real producer AND consumer now
  (L-005). An emit is a re-entry point (L-047).
- New content = new Resource/data + keys, not core edits. No magic numbers (L-002); an ORDER is a
  value stored once (L-030). Derive instead of stepping a copy (L-032).
- An optional field nobody authors is a no-op with green gates — author it or delete it (L-029).
- No abstraction before the second real use case.

## Multiplayer seams (target, not implementation)
D-056/D-074: authoritative dedicated server is the TARGET. Keep player, combat commands, world,
inventory, progression, character/relationship/sect/faction/world-sim state serializable and
presentation-free. Offline and online run the same domain rules. **No networking code yet.**

## Before you call it done
Callers and tests of everything you touched were read; layer direction holds; no duplicated
order/state; docs that describe the contract were updated in the same change (L-014).
