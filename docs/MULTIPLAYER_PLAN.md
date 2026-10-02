# MULTIPLAYER_PLAN — Aetheria

> **Stage 2, future.** This document describes the architectural zones we keep clean now
> so that introducing multiplayer later is **designed to minimize changes to core
> gameplay/domain code** — a design goal, not a guarantee that no changes will be needed.
> It is a plan, not a design to implement.
>
> **No networking code and no networking dependency is added in Stage 1.** Offline is the
> source of truth for all gameplay until the offline game is complete and stable
> (`.kiro/steering/01-product.md`).

## 1. Stance

- Build the best offline game first.
- Do not add multiplayer complexity (RPCs, replication, lobby, netcode libs) now.
- Instead, keep a small set of **seams** clean and serializable so authority and
  replication can be layered on later. These seams cost us nothing offline — they are
  just good decoupling.

## 2. Zones to keep independent (the seams)

| Zone | Keep it… | Why it matters for MP |
|---|---|---|
| **Player state** | serializable, presentation-free | server owns authoritative player state later |
| **Combat commands** | explicit, serializable *intents* (not direct mutations) | commands become client→server messages |
| **World state** | centralized, serializable (not scattered on scene nodes) | server replicates world to clients |
| **Inventory** | component + serializable, rules in domain | server validates inventory changes |
| **Progression** | pure domain rules, serializable (level/XP/cảnh giới) | server authoritative over power/unlocks |
| **Authoritative state** | a conceptual boundary: who decides outcomes | offline = local authority; MP = server authority |
| **Persistence** | SaveService owns format; state has `to_dict/from_dict` | same snapshots feed server-side storage |
| **Character state** | authoritative in domain, serializable, presentation-free | server owns NPC/player characters; clients render views |
| **Relationship state** | one serializable graph in a domain store (not on nodes) | server owns & replicates the social graph |
| **Sect state** | serializable domain entity | server authoritative over sect membership/resources |
| **Faction / politics state** | serializable `FactionState` (influence/attitudes) | server resolves politics; clients observe |
| **World-event / sim state** | world clock + state, seeded + deterministic | server advances the world; clients receive results |

These are the *same* seams named in `docs/GAME_FLOW.md` §5 and `docs/ARCHITECTURE.md`
§10, now extended with the core social/world systems (`docs/CHARACTER_SYSTEM.md`,
`RELATIONSHIP_SYSTEM.md`, `SECT_SYSTEM.md`, `WORLD_SIMULATION.md`).

### 2b. State partition every core system must keep (persistent / runtime / presentation)

For multiplayer later, each core system separates its state into three tiers (defined for
Character in `docs/CHARACTER_SYSTEM.md` §3 and applied the same way to Sect/Faction/World
sim):

| Tier | Who owns it later | Saved? | Replicated? |
|---|---|---|---|
| **Persistent** | authoritative server | yes | yes (authoritative) |
| **Runtime** | server computes; client may predict | no | derived / event-driven |
| **Presentation** | each client, local only | no | no (never) |

Keeping these tiers separate **now** (offline) is what lets a server own the persistent
tier and clients own only presentation **later**, aiming to keep core-code changes small
when multiplayer is introduced. The save snapshot (`docs/SAVE_FORMAT.md`) already
serializes only the persistent tier.

## 3. Why the current design already helps

- **Command intents in combat** — combat takes a "command" (attack/cast/use) rather than
  letting UI mutate state directly. Offline this is just clean input handling; in MP the
  same intent is what a client sends to an authoritative server. *(Phase 01 groundwork:*
  *`InputService` already exposes **semantic intent** over named actions — move/interact/*
  *attack/skill — decoupled from physical devices. Gameplay/domain consume intent, not*
  *keys, so a future network transport can feed the same intent without touching domain*
  *rules. The combat command object itself is still TARGET, built in Phase 09.)*
- **EventBus decoupling** — emitters don't know listeners, so a replication layer can
  subscribe to the same events without touching gameplay code.
- **Seeded RNG** — deterministic domain logic. Determinism is a prerequisite for any
  server-authoritative or lockstep model and makes outcomes reproducible/testable now.
- **Pure domain rules** — damage/XP/cultivation have no node dependencies, so a server
  could run them headless with the same code.
- **Serializable state everywhere** — the save snapshot (`docs/SAVE_FORMAT.md`) is nearly
  the same shape a server would own and sync.

## 4. The authority boundary (conceptual, not built)

Offline today: the local game is the authority. For MP later, we want a clear line
between "decide the outcome" (authority) and "show the outcome" (presentation):

```
intent (client)  →  [authority: validate + resolve via domain rules]  →  state change  →  events  →  presentation
```

Offline, authority and presentation sit in the same process. The rule we follow now so
this stays possible: **presentation never decides outcomes; domain does.** That single
discipline (already in `.kiro/steering/03-architecture.md`) is what keeps the boundary
movable later.

## 5. Explicit non-work for Stage 1

- No `MultiplayerAPI` / `RPC` / `MultiplayerSpawner` / `MultiplayerSynchronizer` usage.
- No lobby, matchmaking, transport, or server code.
- No designing around latency, prediction, or rollback yet.
- No splitting state for network ownership yet — only keeping it serializable and
  centralized.

## 6. What Phase 22 (Multiplayer preparation) will actually do

Research + readiness only (`docs/ROADMAP.md` Phase 22):
- Validate each seam above is clean (serializable, presentation-free, domain-authored).
- Choose a model to investigate (likely server-authoritative for a co-op/PvE fantasy
  world; the exact model is undecided and will be a `DECISIONS.md` entry).
- Produce a gap analysis: for each seam, what's needed to add authority/replication.
- Give a go/no-go recommendation. Ship nothing networked into the offline game.

## 7. Risks to watch (so we don't paint ourselves into a corner)

- UI quietly mutating gameplay state (breaks the authority boundary) — caught by the AI
  review protocol and architecture rules.
- Non-deterministic logic creeping in (unseeded RNG, time-based math) — breaks a future
  authoritative/replicated model.
- World state scattered across scene nodes instead of centralized/serializable — would
  force a rewrite to replicate.
- Character/sect/relationship authoritative state leaking into presentation nodes
  (portraits, sprites owning truth) — breaks the persistent/runtime/presentation
  partition (§2b) and the future server-owns-persistent model.
- World simulation using wall-clock time or unseeded RNG — breaks determinism and makes a
  server-advanced world impossible to keep in sync.

If any of these appear, flag in `docs/DECISIONS.md` immediately.
