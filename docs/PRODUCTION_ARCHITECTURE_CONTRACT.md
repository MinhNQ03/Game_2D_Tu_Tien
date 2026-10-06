# PRODUCTION ARCHITECTURE CONTRACT — Aetheria

> **Status: CONTRACT, frozen by D-056. Almost none of it is implemented, and that is correct.**
>
> This document separates **TARGET CONTRACT** (what the architecture must be able to become)
> from **CURRENT IMPLEMENTATION** (what exists at the SHA that froze it). Every section labels
> both. A reader who confuses the two will think Aetheria has a server; it does not, and
> nothing here adds one.
>
> **What this document is for.** Aetheria must be able to travel
> `offline playable foundation → content-heavy offline game → production release →
> authoritative multiplayer` without a rewrite of the domain, the gameplay layer or the
> presentation pipeline. The cheapest time to decide who will own what is BEFORE the content
> explosion, because every phase after this one adds consumers of these boundaries.
>
> **What this document is NOT.** It is not a networking plan, a vendor selection, a deployment
> runbook or a schedule. `docs/MULTIPLAYER_PLAN.md` keeps the per-seam readiness view and the
> Stage-1 non-work list; this file owns the TARGET topology, the version domains, the
> authority model and the responsibility split.

---

## 1. Build topology

**TARGET.** Three build flavours out of one source tree:

| Build | Contains | Target platform | Purpose |
|---|---|---|---|
| **CLIENT** | presentation + gameplay + domain + data | Windows x64 (primary), macOS (planned, release-gated only when actually supported) | what a player runs |
| **DEDICATED SERVER** | gameplay + domain + data, **no presentation** | Linux x64 | authoritative simulation |
| **TOOLS / TEST** | everything + `tools/` | any dev host | CI gates, capture, playtest, asset generation |

**CURRENT.** One flavour: the source tree, run by the editor binary or headless. The ten CI
gates run the TOOLS/TEST flavour. **No export preset, no artifact, no server build exists.**

**The rule that makes this reachable:** a dedicated-server build must be able to drop
`src/presentation/**` and still run. That is already true by layer direction (nothing in
`domain` or `gameplay` imports `presentation`) with **two known exceptions**, both documented
and both deliberate: `Player` and `Enemy` preload `character_visual_component.gd` to attach a
visual. Those are the only two upward references in the tree, they are composition rather than
rule-ownership, and a server build would need them stubbed or guarded. **Recorded here so the
first server build does not discover it.** No other gameplay or domain file may join them —
the colour-authoring walk in `tests/unit/presentation/test_damage_feedback.gd` already fails
on any `src/gameplay` file that reaches for a presentation token.

**Do not confuse** "the source tree runs" with "a production artifact runs". An export has its
own failure modes: missing resources, stripped classes, import settings, path case, `user://`
location. The release contract (§10) exists because of that gap. Phases P30/P31 own it.

### Vendor neutrality in the build

No platform SDK, store SDK or backend SDK appears in `domain` or `gameplay`, ever. If a client
build later needs one, it is reached through an adapter (§8) owned by `infrastructure`.

---

## 2. VERSION CONTRACT

**TARGET.** Five independent version domains. They are not one number, because they answer
different questions and change at different rates.

| Domain | Changes when | Breaks what | Owner |
|---|---|---|---|
| `game_version` | any shipped build of the game changes | nothing by itself; it is the human-facing identity | release |
| `content_version` | authored content changes (`.tres`, locale rows, maps, art) **without** a rule change | nothing mechanical; it is what a content patch bumps, and what a client/server pair must agree on to render the same world | content pipeline |
| `save_version` | a persisted schema changes shape | **old saves** — requires a migration or a clean refusal | `SaveService` |
| `network_protocol_version` | the wire shape of commands/events/state changes | **client ↔ server compatibility** | protocol (does not exist yet) |
| `server_build_id` | every server build, always | nothing; it is build IDENTITY for observability and rollback | release |

**CURRENT.** Exactly one of the five exists: `save_version` is specified in
`docs/SAVE_FORMAT.md` (an integer, `SAVE_VERSION_CURRENT` in `SaveService`, ordered migrations
on load, refuse a newer one) — and `SaveService` itself is not built yet. `WorldSimulationState`
additionally carries its own block-level schema version, independent of the global
`save_version`; that pattern (a sub-schema versioning itself) is endorsed and should be
followed by other large state blocks. The other four do not exist in any form.

### Worked answers to the questions this contract has to settle

* **Gameplay rule changes** (damage formula, XP curve shape, AI tuning) → `game_version`; and
  `network_protocol_version` **only if** the wire shape changed, which a formula change does
  not. A rule change with an unchanged protocol is still a reason to refuse a mixed session —
  see compatibility below.
* **Art-only change** → `content_version`. Not `save_version`: a sprite is not persisted.
  Not `network_protocol_version`: the wire does not carry pixels.
* **An old save becomes unreadable** → only `save_version`.
* **Client and server cannot talk** → only `network_protocol_version`.
* **Which build produced this log line** → `server_build_id` (and `game_version` on a client).

### Compatibility rule

```
compatible(client, server) :=
      client.network_protocol_version == server.network_protocol_version
  AND client.content_version         == server.content_version
```

`game_version` is deliberately NOT in the predicate: two builds may differ cosmetically and
still interoperate. `content_version` IS, because a client whose authored content differs
would render a different world from the one the server is simulating — different reach on an
attack, a map that is a different shape — which is indistinguishable from a bug.

A mismatch must be **refused cleanly, naming which domain mismatched**, never half-connected.

### Supported lifecycles

```
old save        → ordered migration → current save        (save_version)
newer save      → refuse, say so                          (save_version)
incompatible client ↔ server → reject at handshake, name the domain
compatible   client ↔ server → connect
```

---

## 3. AUTHORITY MODEL — the direction is now decided

**This is the decision D-056 exists to make.** `docs/MULTIPLAYER_PLAN.md` §6 previously left
the model open ("the exact model is undecided and will be a `DECISIONS.md` entry"). It is now
decided as a TARGET; implementation remains unscheduled.

**TARGET: authoritative dedicated server.**

```
Client
  ↓  intent / command            (the ONLY thing a client sends)
Dedicated authoritative server
  ↓  validate
  ↓  resolve using THE SAME domain rules
  ↓  authoritative state mutation
  ↓  authoritative events
Client presentation
```

**CURRENT: local authority, same pipeline.**

```
Input → local command/intent → local authority → the SAME domain rules
      → the SAME state mutation → the SAME events → the SAME presentation
```

**The frozen invariant, and the whole point of the milestone:**

> Offline and online run the **same domain rules**. They differ in **authority and transport**,
> never in **game rule**. There is no "multiplayer damage formula".

A client never asserts an outcome. These are permanently forbidden message shapes:

```
"I dealt 500 damage"      "I gained 100 XP"
"my level is 50"          "I own this item"
"my cooldown finished"    "I completed this quest"
```

A client may only say *what it is trying to do*. The server decides what happened.

**Already true today, and why.** `ProgressionService.grant_xp()` is the only writer of
`CharacterState.xp` and a structural test enforces it; `CombatService` resolves hits and
`DamageRules` computes damage, both pure domain with no node dependency; presentation decides
nothing (`DamageFeedback` reads a signal and writes `modulate`). Moving authority to a server
therefore means changing *who calls the service*, not what the service does.

---

## 4. MULTIPLAYER BOUNDARY CONTRACT

Twelve boundaries. Each answers the seven questions a boundary must answer, or it does not
have a clean contract. "Server later / client later" columns are TARGET; everything else is
CURRENT.

| Boundary | Owns it | May mutate | May request | Serialized | Persistent / Runtime / Presentation | Server owns later | Client owns later |
|---|---|---|---|---|---|---|---|
| **Input / Intent** | `InputService` (autoload) | the service | presentation reads intent | no | runtime | nothing — it receives the intent | all of it; input is inherently local |
| **Combat command** | `AttackComponent` (per entity) | itself, via `request_attack()` | player input, `AIComponent` | not yet; the intent is a method call | runtime | validation + resolution | the request, and local anticipation (§ presentation contract) |
| **Character state** | `CharacterState` (domain) | the owning system per field; `xp` only via `ProgressionService` | gameplay runtimes | **yes** (`to_dict`/`from_dict`) | persistent (identity, xp, life state) + runtime (health) + presentation (visual profile ref) | all persistent fields | a read-only view for rendering |
| **World state** | `WorldRuntime` + `MapCatalog` data | the runtime | `SceneRouter`, maps | map id + spawn, yes | persistent (location) + runtime (live scene) | which map an actor is in | the loaded scene and its cosmetics |
| **Progression state** | `CharacterState.xp` + `ProgressionCurveData` | **`ProgressionService.grant_xp()` and nothing else** | `ProgressionRuntime` only (holds the reward ledger) | yes | persistent (xp); level is **derived, never stored** | the grant | the `ProgressionView` DTO |
| **Relationship state** | `RelationshipStore` (domain) | `RelationshipService` | gameplay runtimes | yes | persistent | the graph | a view |
| **Sect state** | `SectStore` (domain) | `SectService` | `SectRuntime` | yes | persistent | membership, resources, diplomacy | a view |
| **Faction state** | `FactionStore` (domain) | `FactionService` | `FactionRuntime` | yes | persistent | politics | a view |
| **World simulation** | `WorldSimulationState` + seeded `RngService` | `WorldSimulationService` | `WorldSimulationRuntime` on gameplay beats | yes, incl. its own block schema version | persistent (clock, cast, bands) + runtime (indexes, rebuilt on hydrate) | the whole simulation and the RNG streams | the event feed it is told about |
| **Inventory state** | **does not exist** (P13/P14) | — | — | — | will be persistent | ownership and every transfer | a view |
| **Persistence** | `SaveService` (**not built**) | the service | systems offer `to_dict` | it IS the serialization | persistent only | durable state of record | local settings and caches only |
| **Presentation** | each presentation node | itself | gameplay pushes views/cues | **never** | presentation | **nothing, ever** | all of it |

**The row that matters most:** *Presentation* is the only boundary a server owns nothing of.
Presentation state must never become replicated gameplay state. A client choosing a different
sprite must not be able to change an outcome.

---

## 5. COMMAND / INTENT CONTRACT

**TARGET shape** (conceptual — no wire format, no serializer, nothing implemented):

```
command_id            stable identity, for dedup / replay rejection
actor_id              who is trying to act
command_type          what kind of attempt
payload               the minimum facts of the attempt
client_tick           when the client believed it acted  (later, only if prediction lands)
simulation_tick       when the server applied it          (server-side, later)
```

**Three things a command is not:**

```
command != result                 (it is an attempt, not an outcome)
command != authoritative state    (it mutates nothing by existing)
command != presentation           (it is not a cue; cues come from results)
```

So an `AttackIntent` carries direction and the attack it is attempting — and **must never**
carry `damage = 999`, `xp_reward = 5000` or `target_hp_after = 0`. Those are outcomes, and
outcomes belong to whoever holds authority.

**Stable identity is already a proven pattern here, not a theory.** `ProgressionRuntime` keys
its reward ledger by `reward_id`, which is derived from map + spawn row rather than a counter,
and that is what makes "a defeat pays exactly once" enforceable by the ledger instead of by
every caller remembering. The empty-id case is rejected on all four halves (no XP, no event,
no level change, no ledger entry) precisely because an empty key is a key every malformed
event would share. **Future commands and events that must resist duplication or replay should
carry a stable identity of the same shape** — derived from the thing, not from a counter.

---

## 6. SESSION / CONNECTION / RECONNECT CONTRACT

**TARGET.** Six identities, deliberately distinct. One id for everything is how a reconnect
becomes impossible to express.

| Identity | Lifetime | Survives |
|---|---|---|
| `account_id` | forever | everything |
| `player_id` | forever, per account | everything |
| `character_id` | until the character is deleted | disconnect, server restart |
| `session_id` | one logical play session | a brief reconnect |
| `connection_id` | one transport connection | nothing — a reconnect is a NEW connection id on the SAME session id |
| `server_instance_id` | one server process | nothing |

That `connection_id ≠ session_id` split is the entire reason a reconnect can be expressed at
all: the player returns to the same `session_id` on a new `connection_id`.

**Lifecycle events the contract must leave room for** (none implemented): disconnect ·
temporary reconnect within a grace window · server restart (session lost, character and
account survive) · session expiry · version mismatch at handshake · duplicate command ·
duplicate event.

**CURRENT.** One concept exists: `GameState`'s local session (BOOT → MENU → RUNNING), plus
`run_id` as the local run's identity. There is no account, no player id, no connection. The
seven-subsystem session order and its exact reverse teardown is the local analogue of a
session lifecycle and is already enforced by test.

---

## 7. SERVER / CLIENT RESPONSIBILITY MATRIX

| Concern | Offline (CURRENT) | Online client (TARGET) | Online server (TARGET) |
|---|---|---|---|
| Input | local | local | receives intent only |
| Combat result | local authority | **never authoritative** | authoritative |
| XP | local authority | display / view | authoritative |
| Character persistent state | local save | view + local presentation | authoritative |
| World simulation | local | view | authoritative |
| Relationship | local | view / request | authoritative |
| Sect | local | view / request | authoritative |
| Faction | local | view | authoritative |
| RNG | local seeded authority | normally not authoritative | authoritative |
| Save | local | local settings/cache only where allowed | persistent authoritative state |
| Animation | local presentation | local presentation | **never owns visual state** |
| VFX / SFX | local presentation | local | **never authoritative** |
| UI | local | local | none |

---

## 8. TRANSPORT AND BACKEND — VENDOR-NEUTRAL ADAPTERS

**No vendor is chosen, and choosing one now would be the mistake.** Explicitly absent and to
stay absent until a multiplayer phase: `SteamMultiplayerPeer`, ENet, WebSocket, RPC,
`MultiplayerSpawner`, `MultiplayerSynchronizer`, any backend SDK, Redis, Kubernetes, any
database.

Five adapter SLOTS are named so the eventual choice has somewhere to go:

```
Transport Adapter             move bytes
Authentication Adapter        prove who an account is
Matchmaking Adapter           decide who plays together
Server Allocation Adapter     find/start a server instance
Persistent Backend Adapter    durable storage of record
```

**`domain` must never import any of them.** They belong to `infrastructure`, behind the
smallest interface that the one real consumer needs — and per the project's standing
anti-over-engineering rule, **an adapter is written when its first real consumer exists**, not
now. These are slots in a document, not files.

Research deferred to the multiplayer phases: Godot's high-level multiplayer and its
dedicated-server/headless export support, Steam networking and Steam Game Servers with
lobby/matchmaking, or custom UDP. All are implementation choices **behind** the slots above,
and none is a dependency of the offline core.

---

## 9. SECURITY CONTRACT

**The client is untrusted.** One line, and most of the design follows from it.

A server must not accept a client's word on: damage · XP · level · item ownership · currency ·
cooldown completion · movement result · quest completion · loot ownership.

The client **requests**; the server **validates and resolves**. No anti-cheat system is being
designed. But **no future API may be shaped client-authoritatively**, because that shape is
what makes anti-cheat impossible later. Concretely, for every new system from here on: if a
method would let a caller state an outcome, it belongs behind a service that computes the
outcome instead. `ProgressionService.grant_xp(state, amount)` is the right shape (the service
derives the new level from the authored curve); `set_level(50)` would be the wrong one.

---

## 10. OBSERVABILITY AND RELEASE

### Observability (TARGET, abstraction level only)

Structured log records should be able to carry: `session_id` · `server_instance_id` ·
`player_id` · `command_id` · error category · `game_version` · `content_version` ·
`network_protocol_version`.

**Never logged:** secrets, tokens, passwords, or personal data. Production telemetry and crash
reporting belong to P29/P30+.

**CURRENT.** Tagged `push_error`/`push_warning` with a `[subsystem]` prefix, and the
`EventBus.debug_log` flag. No structured logging, no correlation ids.

### Release pipeline (TARGET)

```
commit → lint → parse/compile → headless tests → E2E
       → build artifacts → artifact smoke test → checksum → staging → release
```

The first five steps exist today as the ten CI gates. Everything from `build artifacts`
onward does not. A release must eventually produce: a client artifact, a server artifact, a
version manifest naming all five version domains, checksums, release notes, and a rollback
identity (`server_build_id`).

**The artifact smoke test is the step most easily skipped and least safe to skip:** it is the
only gate that distinguishes "the source tree runs" from "the thing we shipped runs".

### Deployment topology (TARGET, responsibility only)

```
                INTERNET
                    |
             Game Coordinator
          /         |         \
       Auth    Matchmaking   Version
                    |
             Server Allocation
                    |
        +-----------+-----------+
        |           |           |
     GS-SEA-01   GS-SEA-02   GS-JP-01
        |
 Authoritative Game Simulation
        |
 Persistent Backend
```

| Tier | Owns |
|---|---|
| **Coordinator** | auth, session tickets, server allocation, version compatibility, region selection, matchmaking/lobby |
| **Dedicated game server** | game simulation, authority, combat, world, progression, social state, session lifecycle |
| **Persistent backend** | durable account/player data, online persistent state when introduced, required telemetry records |
| **Client** | presentation, input, local UX; prediction and reconciliation later **only if justified** |

**`domain` must not know the coordinator or the backend exist.**

---

## 11. WHAT THIS CONTRACT FORBIDS FROM NOW ON

1. A gameplay or domain file that imports `presentation` (two legacy exceptions, §1).
2. A second authority for a value that already has one (there is one XP writer; a structural
   test enforces it, by exact path, against both static and dynamic mutation forms).
3. An API shaped so a caller states an outcome (§9).
4. Collapsing the five version domains into one number (§2).
5. Presentation state becoming replicated gameplay state (§4).
6. Any networking, transport, lobby or backend code before a multiplayer phase.
7. A speculative adapter, manager or framework with no second concrete use case.
