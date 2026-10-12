# PROPOSAL — NOT FROZEN: Online Multiplayer-First Authority Architecture

> **Status:** PROPOSAL — NOT FROZEN. Documentation only. No application code changes,
> no networking implementation, no canon edits, no admin authorization system.
> This document describes target boundaries. The owner decides.

| Field | Value |
|---|---|
| Proposal | Online multiplayer-first authority architecture |
| Author role | Systems Architect (AI-assisted draft) |
| Source SHA | `ce4b94c0e430cbe84182e76c198c2a6ffe470f5c` |
| Source ref | `origin/main` — verified by ref check 2026-10-12 |
| Source CI | run `38211074765` — SUCCESS, `head_sha` = `ce4b94c`, branch `main`, attempt 1 (GitHub API) |
| Date | 2026-10-12 |
| Owner for approval | Project owner (canon/design authority) |

## 0. Product direction and relationship to frozen docs

**Product direction (owner-issued, this brief):** Aetheria is an online
multiplayer-first, persistent-world, 2D top-down cultivation RPG. Online multiplayer
is the primary production experience and the architecture's main optimization target.
Offline play is a restricted, secondary **Admin Offline Test Mode** for authorized
administrators to run the game end-to-end locally, reproduce issues, test features,
validate content, and evaluate updates before or independently of online release.

**Honest tension, stated plainly:** the frozen docs currently describe Stage 1 as
offline-first — `.kiro/steering/01-product.md`: *"Stage 1 — Offline (current): the
entire game is single-player and offline. This is the primary source of truth for all
gameplay rules."* This proposal documents the **target** architecture under the new
direction. Where the target contradicts frozen Stage-1 framing, the frozen text is
**not** rewritten here; formal adoption requires `docs/DECISIONS.md` entries and
canon updates, which are explicitly out of scope for this documentation task.
Per the brief: do not describe Aetheria as offline-first; do not treat offline and
online as equally important production deployment targets.

**Label vocabulary:** `CANON` = frozen fact (cited); `PROPOSAL — NOT FROZEN` = this
document's recommendation; `OPEN QUESTION` = deferred, not silently settled;
`IMPLEMENTED` / `DOCUMENTED DESIGN` / `PROPOSED — NOT IMPLEMENTED` /
`UNKNOWN — NOT VERIFIED` describe build state at the source SHA.

---

## 1. Architecture objective

Design the current and future system around a trusted server-authoritative
multiplayer world, while preserving the ability to run the same domain rules locally
for admin testing.

**CANON** basis (unchanged by this proposal): offline and online run the **same
domain rules**; they differ in authority and transport only (D-056,
`PRODUCTION_ARCHITECTURE_CONTRACT.md`). There is no "multiplayer damage formula."

The objective is to avoid a future rewrite of game rules, state ownership,
persistence boundaries, and gameplay authority when online multiplayer is
implemented. Concretely:

- Every authoritative mutation has an explicit owner **today** (the domain services),
  so the server target is a change of *where the owner runs*, not a redesign of
  *what the owner is*.
- Persistence boundaries are drawn around domain-owned state, not around the local
  save file — so production persistence does not inherit single-player assumptions.
- The admin offline mode is a local execution environment, **not** an alternative
  authority over production world data.

---

## 2. Authority model

### 2.1 Online production — primary

- The server is authoritative for protected persistent state and shared-world outcomes.
- Clients send validated commands/intents, **never** authoritative outcome assertions.
  (Frozen forbidden shapes: `"I dealt 500 damage"`, `"I own this item"` — D-056.)
- The server validates permissions, preconditions, ownership, timing, and domain
  invariants before accepting mutations.
- The server determines: combat outcomes, item and currency mutations, cultivation
  progression, relationship changes, sect/faction changes, instance results, reward
  eligibility, and reward claims.
- Authoritative mutations have explicit owners and safe retry/idempotency semantics
  where applicable. **IMPLEMENTED** precedent: `RewardLedger.claim(reward_id)` —
  idempotent by stable ID; duplicate delivery is silently survivable by design.
  **DOCUMENTED DESIGN** precedent: `command_id` as stable identity for dedup/replay
  rejection (production contract §3).
- State replication and event publication expose **only** information the recipient is
  authorized to know (see §4 visibility column).
- Client presentation and prediction, if introduced later, must not override
  authoritative outcomes. (**CANON**: "animation is a follower, never an authority" —
  `09-lessons-learned.md`, D-056.)

### 2.2 Admin offline test mode — secondary

- Runs gameplay locally using the same domain rules wherever practical.
- Uses local authority adapters and isolated test persistence.
- Supports end-to-end testing of progression and content without a live online session.
- **Isolation requirements (PROPOSAL — NOT FROZEN):**
  - Must not silently connect local test state to, overwrite, or impersonate
    production world state.
  - Must not create a client-side privilege-escalation path into production.
  - Admin-only capabilities (debug grants, world resets, simulated users) are
    authorized through a trusted boundary appropriate to the execution environment —
    **no admin authorization system is designed or implemented in this task.**
  - Test fixtures, debug grants, simulated users, and local world resets remain
    isolated from production data.
- **IMPLEMENTED** foundation: the entire game currently runs locally through the same
  domain services the server target will host — the offline build *is* the
  domain-rule executable the admin mode needs. What does not exist yet: the local
  authority *adapter* boundary that marks "this mutation is a test mutation."

---

## 3. Persistence and deployment strategy

- **Online production persistence is the primary persistence target.**
- **Current state (verified at `ce4b94c`):** persistence is **design only**.
  `docs/SAVE_FORMAT.md`: *"Status: **design only.** No save code exists yet."*
  Phase 23 is the planned implementation. Every claim below about persistence is
  therefore `DOCUMENTED DESIGN` or `PROPOSED — NOT IMPLEMENTED`, never implemented.
- Recommended domain-owned state and persistence boundaries must support:
  authoritative writes, concurrency control, safe retries, recovery, schema
  evolution, and future operational scaling.
- **Boundaries (PROPOSAL — NOT FROZEN):** one persistence boundary per state owner —
  the units in §4's "authoritative owner" column are the candidate persistence
  modules. Each module owns its schema version, its migration path, and its
  idempotency keys. Cross-module references use stable IDs, never embedded copies
  (the `RewardLedger` precedent: "It records IDS and nothing else").
- Admin offline mode may use a local persistence adapter or disposable local test
  data. It **must not** force production persistence architecture to be designed
  around a single local save file. (The current `SAVE_FORMAT.md` sketch *is* a
  single local save file — it remains valid as the **admin-mode** shape, not as the
  production shape.)
- Domain rules stay independent of transport, database implementation, and
  deployment mode. (**CANON**: vendor neutrality — no platform/backend SDK in
  `domain` or `gameplay`, ever — D-056.)
- **Backend target (PROPOSAL — NOT FROZEN):** a modular monolith with explicit module
  boundaries. Repository evidence supports this: the domain layer is already
  partitioned by owner (`domain/character`, `domain/sect`, `domain/reward`,
  `domain/knowledge`, `domain/relationship`, `domain/worldsim`), each with a single
  mutation path. No microservices or distributed infrastructure — nothing in the
  measured requirements justifies them.

---

## 4. Architectural evaluation per state category

Identity concepts are evaluated separately first. **Account, character, shard/world,
and instance are distinct concepts and are not interchangeable.** The production
contract's six session identities are **DOCUMENTED DESIGN** (nothing implemented):
`account_id` (forever) · `player_id` (forever, per account) · `character_id` (until
deletion) · `session_id` (one logical play session) · `connection_id` (one transport
connection) · `server_instance_id` (one server process).

**Not invented here (OPEN QUESTION):** account-to-character cardinality,
shard-transfer policy, cross-shard policy, admin permission hierarchy. This document
does not assume or specify any of them.

| # | State category | Authoritative owner | Online authority + persistence scope | Visibility | Replication rule | Concurrency / duplicates | Admin offline exercise | Build state @ `ce4b94c` |
|---|---|---|---|---|---|---|---|---|
| 1 | Account identity | Account service (proposed) | Server; persistent | Private to account holder | Never to other clients | Creation idempotent by account ID | N/A — no local accounts; test harness uses fixture identities | PROPOSED — NOT IMPLEMENTED |
| 2 | Character identity | `CharacterRegistry` / `CharacterState` | Server; persistent per character | Private to owning player; public summary per authz | Full state to owner; authorized subset to others | Instance IDs stable per save; server allocates | Local registry as today | IMPLEMENTED (offline) |
| 3 | Shard/world identity | World-simulation host (proposed) | Server; persistent per shard | Public within shard | World facts to shard members per authz | One logical writer per shard tick (logical ownership, not process topology — see §8) | Single local world as today (no shard concept) | PROPOSED — NOT IMPLEMENTED |
| 4 | Instance identity | Instance host (proposed) | Server; transient encounter state discarded on close; durable outcomes (reward records, close-out events) persist via their owners | Party/instance members only | Instance state to members only; never beyond | One writer per instance; close-out once | Local run state when Phase 21 lands | PROPOSED — NOT IMPLEMENTED |
| 5 | Personal story state | `StoryRuntime` (per player) | Player-scoped; persistent per player | Private | Never replicated by default (frozen: "never shared"); any future disclosure requires an explicit, validated, authorized publication rule — none exists today (see §8) | Per-player; no cross-player conflicts possible | Local as today | IMPLEMENTED (offline, Phase 20) |
| 6 | Personal knowledge | `KnowledgeStore` + `KnowledgeService` | Player-scoped; persistent per player | Private | Never replicated by default; interpretation is a per-player view; any future disclosure requires an explicit publication rule — none exists today (see §8) | Grants deterministic on catalog+store | Local as today | IMPLEMENTED (Phase 12) |
| 7 | World chronicle / world facts | World-simulation (proposed domain capability) | Server per shard; persistent | Public within shard | To shard members per authz | Single tick writer; events revisioned | Local world events as today | PROPOSED — NOT IMPLEMENTED (presentation chronicle UI exists; not a facts system) |
| 8 | Sect/faction/organization | `SectService` / `FactionService` (roster-wins) | Server per shard; persistent | Public (declared) | Declared relations public; standings per authz | Deterministic rules, no RNG; governance events revisioned | Local as today | IMPLEMENTED (offline) |
| 9 | Relationship / social graph | `RelationshipService` (one graph) | Server per shard; persistent | Per-edge authz (private ↔ public) | Only edges the recipient may know | Single mutation path; symmetric canonical ordering | Local as today | IMPLEMENTED |
| 10 | Combat outcomes | Combat domain (server in target) | Server per instance/shard; event-sourced | Participants + authorized observers | Outcomes, not inputs | Command intent + server resolves (documented design) | Local as today | IMPLEMENTED (offline) |
| 11 | Inventory / currency / items | `InventoryState` (+ `InventoryRuntime` in gameplay; server validates in target) | Server; persistent per character | Private to owner | To owner; trade views per authz (no trade designed) | Server validates every mutation | Local as today | IMPLEMENTED (offline) |
| 12 | Cultivation progression | `ProgressionService` (sole XP mutator) | Server; persistent per character | Private to owner | To owner | Single mutator (structural test enforced) | Local as today | IMPLEMENTED |
| 13 | Instance results | Instance host (proposed) | Server; written to ledger + allow-listed events at close | Members, then via §7/§14 | Results to members; close-out events to shard | Close-out exactly once | Local when Phase 21 lands | PROPOSED — NOT IMPLEMENTED |
| 14 | Reward ledger / claims | `RewardLedger` + `RewardService` | Server; persistent, append-only | Private per claimant | Grant receipts to claimant | Idempotent by `reward_id`; duplicates silently survivable | Local as today | IMPLEMENTED (Phase 19) |
| 15 | World simulation state | World-simulation (tick, RNG streams) | Server per shard; persistent | Per-LOD authz | Results, not the sim itself ("clients receive results") | Integer ticks; seeded streams; owner-only mutation | Local as today | IMPLEMENTED (offline, Phase 08) |
| 16 | Presentation state | Client | Client-local | — | **Never replicated** (frozen) | N/A | As today | IMPLEMENTED |

**Second-source-of-truth audit (PROPOSAL — NOT FROZEN, enforced by the table):**
knowledge has one collection (`KnowledgeStore`); sect membership has one source
(roster); relationships have one graph; rewards have one ledger; each row has one
owner. The table introduces no duplicate stores.

---

## 5. Success criteria — how the architecture satisfies them

| Criterion | Satisfied by |
|---|---|
| Develop and test gameplay locally without a live server | §2.2: same domain rules run locally; the current offline build is the admin-mode executable |
| Same domain invariants in offline tests and online production | §1: one rule set; authority/transport differ, rules don't (**CANON** D-056) |
| Clients cannot directly mutate protected shared state | §2.1: intent-only clients; server validates everything; forbidden outcome-assertion shapes |
| Private story/knowledge isolated unless an explicit publication rule allows | §4 rows 5–6: never replicated; §2.1: replication exposes only authorized info |
| Authoritative sect/faction, economy, combat, instance, reward outcomes | §4 rows 8, 10–14: explicit server-side owners |
| Online transport + production persistence without rewriting domain rules | §1 objective; §3: domain independent of transport/DB; persistence boundaries follow existing owner partitions |
| Test authority, idempotency, concurrency, persistence boundaries without presentation | §2.1 idempotency precedents (`RewardLedger`, `command_id`); §3 module boundaries; server build drops presentation (**CANON** D-056: dedicated server has no presentation) |
| Admin test data and privileges isolated from production | §2.2 isolation requirements; §3: disposable local test data |

---

## 6. Open questions for the owner (genuinely requiring owner/product decision)

1. Account-to-character cardinality (one account, how many characters?).
2. Shard-transfer policy and cross-shard policy (can a character move shards? what travels?).
3. Admin permission hierarchy (who may use Admin Offline Test Mode capabilities, and through what trusted boundary?).
4. Formal adoption of the multiplayer-first direction: `docs/DECISIONS.md` entries and updates to the frozen Stage-1 framing in `.kiro/steering/01-product.md` / `MULTIPLAYER_PLAN.md` (§0 tension).
5. Production persistence technology choices (deferred until Phase 33+; the modular-monolith boundary map in §3 is the decision that matters now).

---

## 7. Stop gate

- Documentation only. No application code changed, no networking implemented, no
  admin authorization system designed, no canon edits, no C2, no Phase 21/22.
- Working tree: this file is untracked (`?? docs/proposals/`); nothing else modified.
- No tests or CI claimed beyond the verified source SHA/CI in the header.
- **Final status: READY FOR OWNER REVIEW.**
- **STOP.**

---

## 8. Final review addendum (C1-R3) — both proposals audited together

This addendum reviews `PROPOSAL_SHARED_WORLD_STORY_MODEL.md` (state scope,
ownership, visibility, publication) and this document (authority, execution,
deployment, persistence) as one coherent model. Companion: the story-model doc.
`AETHERIA_PRE21_PROMPT_C1_SHARED_WORLD_AUTHORITY.md` was searched for in the
workspace, the repo, and the home directory — **not found**; its claims are
**UNKNOWN — NOT VERIFIED**, and nothing below is inferred from it.

### 8.1 One coherent authority model — cross-proposal verification

Scope-to-category mapping (story scope → this doc's §4 rows). Verdicts: agreement
holds on all seven audit points; no second source of truth introduced.

| Story scope | §4 rows | Agreement check |
|---|---|---|
| 1 Personal canon | 5, 6 | Agree: per-player, private, server-persistent per player; publication only via explicit rule (§8.2) |
| 2 Shared world chronicle | 3, 7, 15 | Agree: per-shard, server-authoritative; chronicle is a proposed domain capability, not the existing presentation UI |
| 3 Public organization | 8 | Agree: roster-wins, declared-vs-edge split, deterministic governance path |
| 4 Pairwise/social | 9 | Agree: one graph, `RelationshipService` single mutation path; ADR-001 deferred in both |
| 5 Party/instance | 4, 13 | Agree after R3 fix: transient discarded, durable via owners (both docs now state this) |
| 6 Reward/participation | 14 | Agree: one ledger, idempotent by `reward_id`, silently survivable duplicates (both docs corrected in R2/R3) |

- Online server authority: both docs place shared-state authority on the server.
- Offline admin test isolation: defined here (§2.2); the story doc defers to it by cross-reference (added in R3).
- Domain ownership and dependency direction: unchanged — domain services own state; presentation only reads.
- No second source of truth: knowledge → `KnowledgeStore`; membership → roster; relationships → one graph; rewards → one ledger; each §4 row has exactly one owner.

### 8.2 Private state and explicit publication (PROPOSAL — NOT FROZEN)

Privacy is the default, not an absolute prohibition on future disclosure:

- Personal story and knowledge are **never replicated by default** (**CANON**: §14
  "never shared"; CL-14). This canon is unchanged.
- Any permitted future disclosure must be an **explicit, validated, authorized
  domain action** — a publication rule with a named owner, a defined recipient set,
  and a defined information subset. The receiving player learns **only** what the
  rule permits. No such rule exists today; inventing one is out of scope.
- "Never replicated" in earlier drafts meant "no automatic replication." The
  corrected wording (§4 rows 5–6) preserves the frozen default while leaving the
  publication-rule door explicitly designed, not accidentally open.

### 8.3 Transactions and idempotency audit

Labeled by build state at `ce4b94c`. A stable ID alone does not guarantee
atomicity — the consistency boundary for each operation is stated.

| Operation | Consistency boundary | State |
|---|---|---|
| Duplicate command delivery | Idempotent by stable `command_id` (derived from the thing, not a counter) | DOCUMENTED DESIGN (contract §3); nothing implemented |
| Duplicate reward grant | Idempotent by `reward_id`; `RewardLedger.claim()` silently survivable | IMPLEMENTED (Phase 19) |
| Concurrent reward claims | Same ledger; first claim wins, later claims see `ALREADY_PAID` | IMPLEMENTED |
| Multi-part reward (bag + xp + regard) | **Precedent:** `RewardOutcome` PAID / ALREADY_PAID / REFUSED / **OWED** — "Some parts are paid and recorded, at least one is not. Calling again pays only the rest." Retry pays only the unpaid parts; no part pays twice. Crash between parts resumes as OWED, not as corruption. | IMPLEMENTED (Phase 19) |
| Inventory / currency mutation | Single owner (`InventoryState`); server validates every mutation in target | IMPLEMENTED (offline); server validation PROPOSED |
| Trade / multi-owner operations | No trade designed; no multi-owner transaction exists | PROPOSED — NOT IMPLEMENTED (backlog) |
| Dungeon close-out + reward granting | Close-out exactly once; rewards via ledger; allow-listed world events | PROPOSED — NOT IMPLEMENTED (Phase 21) |
| Timeout / retry / crash / partial persistence | Retry semantics per operation above; persistence itself is design-only (Phase 23) — crash recovery across a save boundary is **not yet designed** | Partial: operation-level retry IMPLEMENTED for rewards; persistence-level recovery OPEN |

**Not prescribed:** no database, no transaction framework is specified or implemented
in this task. **Required future tests (PROPOSAL — NOT FROZEN):** duplicate command
delivery under retry; concurrent claims on the same `reward_id`; crash between
reward parts (expect OWED, then resume to PAID); close-out executed twice (expect
second to be a no-op).

### 8.4 Shard and instance authority — logical ownership, not process topology

- Ownership in §4 is **logical**: "one logical writer per shard tick," "one writer
  per instance." This does **not** assume one shard equals one process.
- Process topology, failover, shard transfer, cross-shard policy, and detailed
  recovery implementation are **left open** — current canon does not settle them,
  and this document does not invent them.
- Transient vs durable (R3 correction, applied to both docs): transient encounter
  state is discarded on instance close; durable outcomes — reward records (ledger),
  close-out events (chronicle), declared-state transitions — persist via their
  owning scopes. "Discarded on close" never meant durable outcomes.

### 8.5 Persistence architecture — boundary clarification

- "One persistence boundary per state owner" (§3) means a clear **ownership and
  migration boundary**: one schema version, one migration path, one set of
  idempotency keys per owner. It does **not** automatically require a separate
  database or service per owner — a modular monolith may host several boundaries in
  one store as long as the boundaries are explicit and independently migratable.
- Operations that may require atomicity across related state (PROPOSAL — NOT
  FROZEN, to be settled with evidence in a persistence phase): reward grant spanning
  ledger + inventory + progression + relationship regard (today handled by the
  OWED/ALREADY_PAID retry model, not by a cross-state transaction); governance
  transition spanning declared relation + edge attitudes. The target stays
  compatible with server-authoritative persistence without implementing Phase 23
  or a new persistence system now.

### 8.6 Product-direction conflict — formal adoption required

The multiplayer-first direction is owner-issued but **not yet an established
project rule**. Before it becomes one, the following are required (none done in
this task):

1. `docs/DECISIONS.md` entry adopting online multiplayer-first as product direction,
   superseding the Stage-1 offline-first framing.
2. Update `.kiro/steering/01-product.md` Stage 1/Stage 2 wording.
3. Update `docs/MULTIPLAYER_PLAN.md` stage model and non-work lists.
4. Review `docs/NARRATIVE_MASTER_PLAN.md` §14 and `docs/GAME_DESIGN_FREEZE.md` for
   wording that assumes offline-first production; update via the freeze's own
   change control.
5. This proposal itself approved by the owner (it remains PROPOSAL — NOT FROZEN).

### 8.7 Proposal consistency

- This document defines **authority, execution, deployment, and persistence
  boundaries**. The story-model document defines **state scope, ownership,
  visibility, and publication boundaries**. They cross-reference rather than
  duplicate: normative rules live in exactly one of the two documents, with the
  other pointing to it (R3 added the instance-scope cross-reference; the reward
  idempotency rule lives here in §8.3 and is cited — not restated — from the story
  doc's Scope 6).
- H21-14 remains **OPEN / OWNER REQUIRED** until the owner performs and records
  the required human playtest. H21-21 remains **CLOSED — VERIFIED AT `ce4b94c`**
  per the R1 evidence.

### 8.8 Verification performed and limitations

- Verified at `origin/main` = `ce4b94c` (ref check after fetch 2026-10-12); CI run
  38211074765 SUCCESS on that SHA.
- Read from the repo at that SHA: `reward_ledger.gd`, `reward_service.gd`,
  `reward_outcome.gd`, `progression_runtime.gd`, `knowledge_service.gd`,
  `knowledge_store.gd`, `relationship_endpoint.gd`, `character_state.gd`,
  `character_registry.gd`, `inventory_state.gd`, `SAVE_FORMAT.md`,
  `PRODUCTION_ARCHITECTURE_CONTRACT.md`, plus all 21 C1 source docs.
- **Limitations:** `AETHERIA_PRE21_PROMPT_C1_SHARED_WORLD_AUTHORITY.md` not found
  (UNKNOWN — NOT VERIFIED); `gh` CLI unavailable (CI verified via API); no code
  executed — this is a documentation audit, so implementation behavior is read
  from source, not run.
- **Not performed:** no code, canon, schema, save-format, networking, C2, Phase 21,
  or Phase 22 work. No commit, push, merge, reset, clean, or history rewrite.
  `git status` shows only `?? docs/proposals/`; `git diff` is empty.

---

## 9. Stop gate

- Documentation only. This addendum (R3) is the final permitted review action.
- **Final status: READY FOR OWNER REVIEW.**
- **STOP.** Do not continue into implementation.
