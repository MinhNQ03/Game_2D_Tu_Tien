# PROPOSAL — NOT FROZEN: Shared-World Story Model & Political Authority (C1)

> **Status:** PROPOSAL — NOT FROZEN. Design gate only. No networking code, no server
> implementation, no canon changes applied. This document proposes; the owner disposes.
> **Not** a Phase 21/22 clearance. **Not** canon approval.

| Field | Value |
| --- | --- |
| Proposal | C1 — Shared-world story model & political authority |
| Author role | Narrative Systems Architect (AI-assisted draft) |
| Source SHA | `ce4b94c0e430cbe84182e76c198c2a6ffe470f5c` |
| Source ref | `origin/main` — verified by ref check 2026-10-12 (see Provenance below) |
| Source CI | run `38211074765` — SUCCESS, `head_sha` = `ce4b94c`, branch `main`, attempt 1 (GitHub API) |
| Date | 2026-10-12 |
| Owner for approval | Project owner (canon/design authority) |

### Provenance (verified 2026-10-12, after `git fetch --all --prune`)

- `origin/main` = `ce4b94c0e430cbe84182e76c198c2a6ffe470f5c`. The proposal's Source SHA
  was verified against the live ref; it is not an assumption.
- `origin/hardening/pre-phase21-gate-b2` = `ce4b94c0e430cbe84182e76c198c2a6ffe470f5c`
  — **identical to&#32;`origin/main`&#32;tip** at verification time. The Gate B2 branch state is
  therefore the same tree as `main`; no divergence to account for.
- This proposal file itself is **untracked in the working tree**
  (`git status --short` shows only `?? docs/proposals/`); it is not part of any git ref
  and is not content on GitHub. The working tree sits on branch `d063/phase-a`
  (HEAD `da5edc8`), which is an ancestor of `origin/main` (67 commits behind) —
  the proposal was researched against `origin/main`, not against the working tree.
- CI verified via GitHub API (not `gh` CLI, which was unavailable): run 38211074765,
  `conclusion: success`, `head_branch: main`, `run_attempt: 1`.

---

## 0. Label vocabulary used in THIS document

The repository's frozen docs do **not** use a single three-way vocabulary. They use:
`(FROZEN)` section/entry markers, `RESOLVED` / `CONTENT DEBT` / `WATCH`
(`CONTRADICTION_REGISTER.md`), `PAID` / `OPEN` (clue ledger), `TARGET` (D-056 server model).
This proposal therefore defines its own labels, used consistently below:

- **CANON** — frozen fact from `docs/CANON_LEDGER.md` (`CL-nn`), `docs/GAME_DESIGN_FREEZE.md`
  (D-039), or a `(FROZEN)` section of a master doc. Changing it requires a `docs/DECISIONS.md`
  entry. Cited with its source on every use.
- **PROPOSAL — NOT FROZEN** — a recommendation of this document. Reviewable, revisable,
  never to be treated as decided until the owner approves.
- **OPEN QUESTION** — explicitly deferred; recorded so it is not silently settled.

---

## C1.0 — Verified present state

### Canon and architecture baseline (all read from `origin/main` @ `ce4b94c`)

**CANON — narrative state split (frozen,&#32;`NARRATIVE_MASTER_PLAN.md`&#32;§14, freeze audit S):**

| State | Scope | Later |
| --- | --- | --- |
| Personal story state | per player | never shared; Player A's chapter cannot advance or erase Player B's |
| World chronicle state | per world/shard | may be shared **or instantiated per group** (deliberately open) |
| Party / instance state | temporary | co-op dungeon/boss runs |
| Social state | shared | relationships, sects, factions, guild-like structures |

Acceptance test (frozen): two players at different story points must be able to
party/dungeon/boss/loot/world-event **without either story state being forced to match**.
A design that requires synchronisation "has destroyed personal canon and must be rejected."

**CANON — server target:** authoritative dedicated server, frozen as **TARGET** by D-056
(`docs/PRODUCTION_ARCHITECTURE_CONTRACT.md`, `docs/MULTIPLAYER_PLAN.md`). Nothing is
implemented; Stage 1 adds zero networking code. Offline and online run the \*\*same domain
rules\*\*; they differ in authority and transport only. Client sends intent/commands only;
client-stated outcomes (`"I dealt 500 damage"`) are permanently forbidden shapes.

**CANON — knowledge (CL-14):** "Story does not own knowledge, Quest does not own knowledge,
and **knowledge is never a private story flag**." `KnowledgeStore` + `KnowledgeService`
own authoritative collection. Personal clues are personal state under a shared service.

**CANON — factions (CL-17):** faction standings are relationship **edges**
(`RelationshipEndpoint.Kind.FACTION`), never inline scalars. `FactionState` carries only
the **DECLARED** relation. Politics rules are deterministic with explicit tie-breaks,
**no RNG**.

**CANON — relationships (CL-12):** dimensions \`affinity · trust · respect · fear · rivalry ·
debt\`. No single relationship score, no morality bar. One relationship graph per session;
Sect↔Sect diplomacy mirrored as symmetric edges in the same graph. Directed edges are
read from the `from` endpoint's perspective; the player is a `CHARACTER` endpoint —
Player↔NPC needs no special case.

**CANON — sect (C-003, SECT\_SYSTEM):** player starts with **no sect**. Sect roster
(`leader_ref`, `elder_refs`, `disciple_refs`) is authoritative;
`CharacterState.sect_id` is a derived read cache — on disagreement the roster wins.
`SectService` / `FactionService` are the single mutation paths (runtimes under
`Main/Systems`, not autoloads).

**CANON — world simulation (Phase 08):** LOD bands derived from the map-exit graph;
no wall clock (`WorldClock` is a monotonic tick counter); seeded stream-scoped RNG;
events mutate **through the owning system only**; determinism
(`save → load → advance K` ≡ `advance K`).

**CANON — composition target:** 70–85% shared macro canon, 15–30% player-specific
variation (`NARRATIVE_MASTER_PLAN.md` §10). "No story system may ever special-case the
player out of the core systems."

### Phase status (verified from handoffs @ `ce4b94c`)

- Phase 19 (Quest): **DONE** (D-070). Phase 20 (Story): **DONE** (D-072).
- **Phase 21 (Dungeon) and Phase 22 (Boss): NOT STARTED.**
  (`pre-phase-21-hardening.md` §18.5: \*"Gate B2 stops here. Gates C1 and C2 were not
  started. Phase 21 and Phase 22 have not started."\*)
- **H21-14: OPEN / OWNER REQUIRED** — owner playtest of beats 3–12 required; closes only
  when a person has played and written down what happened.
- **H21-21: CLOSED — VERIFIED AT&#32;`ce4b94c`.** Reconciliation 2026-10-12: the C1 brief
  called it "root-cause-unresolved despite a green rerun"; the handoff at the verified
  SHA records it closed and the code evidence confirms the fix is in the tree.
- Handoff: `docs/handoff/pre-phase-21-hardening.md` §16.1 (lines 1220–1300),
    *"H21-21 — CLOSED on 2026-10-12 (Gate A, §16)"*. Root cause: `move_and_slide()`
    takes no delta — outside a physics frame it integrates against the engine's
    wall-clock process step; at ≤0.1 ms process step the pet test's 2400 ticks
    produced 0 swings (reproduced assertion-for-assertion via `--fixed-fps` sweep;
    table in §16.1). Stated limit (kept verbatim): \*"the CI runner's process step on
    the failed attempt was not recorded."\*
- Code at `ce4b94c`: `src/gameplay/components/movement_component.gd:92-93`
    (`assert(in_fixed_step(), FIXED_STEP_ONLY)` before `body.move_and_slide()`),
    `:106` (`static func in_fixed_step() -> bool`), `:56`/`:99` (H21-21 comments);
    `tests/framework/test_case.gd:72` (`func fixed_step() -> void`).
- Phase 21/22 remain NOT STARTED — H21-21's closure does not clear them.

### What the frozen docs deliberately leave open (the seams C1 must decide)

1. World chronicle "may be shared, **or instantiated per group**" — the shared-vs-instanced
   question is explicitly undecided.
2. No party/instance model exists (no dungeon-run state, participation, local objectives).
3. No reward/participation ledger exists (no authoritative reward path, eligibility,
   contribution, anti-duplication rules).
4. Player↔player relationships are representable (`CHARACTER` endpoints) but have no rules.
5. Shard identity ("per world/shard") is undefined — what a shard *is*, who owns
   world-event authority across shards.
6. Spoiler/corruption handling for cross-player scenarios is undesigned.

---

## C1.1 — Recommended narrative/world scope model

### Default proposal (PROPOSAL — NOT FROZEN)

\*\*A shared persistent world/social layer, strictly personal story and discovery, and
temporary group/instance state.\*\* Concretely, six scopes:

#### Scope 1 — Personal canon (per player, never shared, never synchronised)

- Origin, chapter/beat progress, personal choices, learned knowledge, private clue
  interpretation.
- **CANON** basis: personal story state "never shared" (§14); CL-14 (knowledge via
  `KnowledgeService`, never a private story flag).
- **PROPOSAL — NOT FROZEN:** clue *interpretation* (what the player believes a clue means)
  lives here even when the clue *fact* is shared knowledge — interpretation is a
  per-player view over shared knowledge entries, not a fork of the knowledge itself.

#### Scope 2 — Shared world chronicle (per shard, server-authoritative)

- World events and persistent world facts with explicit authority, trigger and scope.
- Terminology note: "chronicle" here means a **proposed domain capability**
  (PROPOSED — NOT IMPLEMENTED). The codebase already has presentation-layer chronicle
  UI (`src/presentation/chronicle/chronicle_panel.gd`, `chronicle_view.gd`) — a view,
  not a world-facts system. This proposal does not claim that system exists.
- **PROPOSAL — NOT FROZEN (resolving the frozen-open seam):** the chronicle is \*\*shared
  per shard\*\*, not instantiated per group. Rationale: the frozen acceptance test only
  forbids forcing *personal story* to match; a shared chronicle is what makes "world
  events" meaningful across players, and per-group instantiation would fork world facts
  (e.g. "the Azure sect fell") into incompatible truths with no merge rule. Shard =
  one authoritative world-simulation instance with its own tick counter, RNG streams,
  and event log (see §C1.2 authority table).
- **OPEN QUESTION:** shard topology — how many shards, who is placed where, cross-shard
  migration rules. Not decided here.

#### Scope 3 — Public organization state (per shard, server-authoritative)

- Official sect/faction membership (roster-wins), declared sect↔sect diplomacy,
  leadership, resources, world simulation outputs.
- **CANON** basis: roster authority (D-015), declared-vs-edge split (CL-17),
  deterministic politics.
- **PROPOSAL — NOT FROZEN:** declared diplomacy transitions require an explicit
  governance event (see C1.2); influence *attitudes* (the numeric standings on edges)
  may drift via authored sim rules, but the *declared* relation changes only through
  the governance path.

#### Scope 4 — Pairwise/social state (per shard, server-authoritative graph)

- Player↔NPC, player↔player, character↔character, sect↔sect declared relations.
- **CANON** basis: one typed graph, `RelationshipService` single mutation path,
  dimensions from the `from` perspective.
- **PROPOSAL — NOT FROZEN:** add a `PLAYER` endpoint kind alongside `CHARACTER`
  (narrow ADR below) so player↔player edges do not overload the NPC-character
  namespace, and record **viewpoint explicitly**: every edge stores whose perspective
  its dimensions represent (`from_ref`). Faction↔player and sect↔player relations must
  not be collapsed into one generic "standing" — the edge type vocabulary
  (`ALLY`, `RIVAL`, `ENEMY`, …) plus the six dimensions already prevent this; the ADR
  only adds the endpoint kind.
- **ADR-001 (proposed text, not applied):** \*"Add `RelationshipEndpoint.Kind.PLAYER`
  distinct from `CHARACTER`. Rationale: player↔player edges need lifecycle rules
  (account deletion, rename) that NPC characters do not have; overloading CHARACTER
  would let NPC-content rules accidentally apply to players. No duplicate score store:
  edges reuse the existing dimensions and `RelationshipService` mutation path."\*

#### Scope 5 — Party/instance state (temporary per run; durable outcomes persist via owners)

- Dungeon/boss run outcomes, participation, local objective states.
- **PROPOSAL — NOT FROZEN:** an instance is a bounded context with its own ID,
  member list, and objective ledger; it borrows read-only snapshots of Scopes 2–4
  at entry and writes back **only** through the reward ledger (Scope 6) and
  explicitly authored world-event proposals at exit. **Transient** encounter state
  (positions, in-fight objectives) is discarded on close and never replicated beyond
  members; **durable** outcomes (reward records in the ledger, close-out events to
  the chronicle) persist via their owning scopes. No persistent consequences except
  via Scopes 2, 3, 6. (Refined in addendum R3: not every instance is simply
  "discarded" — see `PROPOSAL_ONLINE_AUTHORITY_ARCHITECTURE.md` §8.)

#### Scope 6 — Reward/participation state (one authoritative ledger path)

- One authoritative reward ledger: eligibility, contribution, individual claims,
  anti-duplication.
- **CANON** basis: `SYSTEM_DEPENDENCY_MATRIX` names the reward ledger "the authority's
  guard against a replayed grant" with persistent IDs of every reward paid.
- **IMPLEMENTED** (Phase 19, D-070): `src/domain/reward/reward_ledger.gd` — one
  collection recording paid IDs; `claim(reward_id)` returns false for duplicates and
  refuses empty IDs loudly. Duplicate delivery is **silently survivable by design**:
  `progression_runtime.gd` — \*"A duplicate is not an error: the whole point of the
  ledger is that this is survivable. Silent, because a duplicate that is correctly
  ignored is not a problem to report."\* The anti-replay property comes from idempotent
  ignore, not from loud rejection.
- **PROPOSAL — NOT FROZEN:** every reward grant carries a stable `reward_id` derived
  from the thing (cf. `ProgressionRuntime.reward_id` pattern); contribution is recorded
  per participant per instance and resolved to eligibility by authored rules **before**
  the instance closes. Contribution weighting rules are not yet designed.

### Alternatives considered and rejected

| Alternative | Why rejected |
| --- | --- |
| Fully instanced world chronicle (per group) | Forks world facts with no merge rule; contradicts the "shared macro canon" composition target (70–85%). |
| Single global relationship score per pair | Forbidden by CL-12 ("no single relationship score"). |
| Player story flags replicated to party | Forbidden by frozen acceptance test ("must be rejected"). |
| Faction standings as inline scalars on `FactionState` | Already deliberately dropped (D-042) as second-source defect. |

---

## C1.2 — Who can change shared politics?

Authority table. **CANON** rows are frozen; **PROPOSAL** rows are this document's
recommendation. "Writer" = the only permitted mutator. All shared-scope writes are
server-authoritative in the TARGET model; offline, the local authority plays the
server's role through the same code path. (Execution, deployment, and persistence
aspects of this authority live in the companion
`PROPOSAL_ONLINE_AUTHORITY_ARCHITECTURE.md` §§1–3; this section defines scope and
ownership only, to avoid duplicated normative rules.)

| Action | Scope | Permitted writer | Validation / conditions |
| --- | --- | --- | --- |
| **CANON** Personal choice changes own relationships / quest state / eligibility | 1, 4 (own edges) | Player (via intent) | Intent re-validated by authority; cannot silently rewrite declared diplomacy |
| **CANON** NPC/sect/faction/world-sim changes common state | 2, 3 | Authored deterministic rules only | Causal prerequisites + visible evidence; no RNG in politics (CL-17) |
| **PROPOSAL** Player proposes a political shift (e.g. petition, challenge, tribute) | 3 | Player (proposal only) | Proposal is an intent with evidence attached; it does **not** mutate declared state |
| **PROPOSAL** Declared diplomacy transition (ally/rival/enemy) | 3 | Governance event only | Explicit rule with bounded conditions, deterministic resolution, and a revisioned auditable event. Illustrative options only, not pinned: a collective condition (e.g. council vote), an influence threshold with tie-break, or an authorized governance action (e.g. sect leader decision within charter) |
| **PROPOSAL** Influence/attitude drift on edges | 4 | World-sim tick rules | Authored per-event deltas; clamped; history kept; never rewrites declared relation |
| **PROPOSAL** Instance outcome proposes a world event | 5 → 2 | Instance close-out | Only events on an authored allow-list; each carries instance ID, participants, evidence |
| **PROPOSAL** Reward grant / claim | 6 | Reward ledger | Idempotent by `reward_id`; eligibility resolved before instance close |

**Event/revision identity (PROPOSAL — NOT FROZEN):** every shared-scope mutation is an
event with stable ID derived from (scope, entity, cause, tick) — never a bare counter —
so concurrent/conflicting actions are ordered deterministically and replay is
auditable. **Reversibility policy:** personal-scope writes are reversible by design;
declared-diplomacy transitions are append-only revisions (a reversal is a new
superseding event, never a rewrite of history); reward grants are never reversed,
only compensated by a new grant event.

**Concurrent/conflicting actions (PROPOSAL — NOT FROZEN):** two proposals affecting the
same declared relation in the same tick resolve by the governance rule's tie-break
(charter order, then lowest entity ID); the loser is recorded as *superseded*, visible
to its proposer, never silently dropped.

---

## C1.3 — Five mandatory cross-player scenarios

Matrix columns: **P**ersonal / **S**hared / **I**nstance-local / **R**ewarded; what each
participant knows; resolution; later replication; spoiler/corruption guard.

### (a) Two players at different chapters enter one dungeon together

|  |  |
| --- | --- |
| P | Each player's chapter/beat, quest state, knowledge — untouched, never synchronised (**CANON** acceptance test) |
| S | Dungeon's world-chronicle facts (it exists, its canonical history) |
| I | Run objectives, participation, per-member contribution |
| R | Per-player eligibility resolved from contribution + personal quest state; rewards via Scope 6 ledger |
| Knowledge | Each sees only their own quest markers; shared markers are instance objectives |
| Resolution | Instance borrows read snapshots; exit writes rewards + allow-listed event proposals only |
| Replication | Reward grants replicate; instance internals do not |
| Guard | A design requiring chapter sync "must be rejected" (**CANON**) |

### (b) Player A knows a personal clue, Player B does not; party completes a public encounter

|  |  |
| --- | --- |
| P | A's clue knowledge *and interpretation* (CL-14: via `KnowledgeService`, never a story flag); B's lack thereof |
| S | The public encounter's occurrence and outcome (chronicle) |
| I | Encounter tactics, participation |
| R | Both rewarded for the public encounter; A's clue-derived bonus (if any) is a separate personal-scope grant |
| Knowledge | B never learns A's clue from the encounter; clue sharing requires A's explicit in-fiction act |
| Resolution | Encounter resolves on shared mechanics; clue effects apply only to A's rolls/views |
| Replication | Encounter outcome replicates; clue state does not |
| Guard | Spoiler guard: shared UI never renders A's clue-gated content to B |

### (c) A player befriends an NPC who belongs to an officially hostile sect

|  |  |
| --- | --- |
| P | The friendship edge (player→NPC, directed, from player's perspective) |
| S | The sect's declared ENEMY relation (unchanged by one friendship — **CANON** CL-17 declared/edge split) |
| I | N/A (not necessarily instanced) |
| R | No reward for the friendship itself; consequences flow through sim rules |
| Knowledge | The NPC's sect knows the player by the edge; the sect's *declared* stance toward the player is a separate edge |
| Resolution | Sim rules may drift attitudes on edges (rivalry down, trust up); declared ENEMY changes only via governance (C1.2) |
| Replication | Edges replicate per the social graph |
| Guard | Personal friendship must not silently rewrite official diplomacy (**CANON** constraint from brief C1.2) |

### (d) A party defeats a boss while one player's personal story has not reached that reveal

|  |  |
| --- | --- |
| P | The unreached player's story/knowledge — the reveal is **not** granted by participation |
| S | The boss's defeat (chronicle fact) |
| I | Fight participation, contribution |
| R | All participants rewarded for the kill; story-gated rewards withheld from the unreached player until their story arrives (then granted via normal quest path, same `reward_id` namespace — no double-grant) |
| Knowledge | The unreached player sees "a great beast fell" (chronicle), not the story reveal (personal) |
| Resolution | Instance close-out proposes the chronicle event; personal reveals stay gated |
| Replication | Kill fact replicates; reveal does not |
| Guard | Anti-spoiler: presentation filters reveal-gated content per player's knowledge state |

### (e) Several players from competing sects help at a world vein crisis; one player's action alone must not dictate public diplomacy

|  |  |
| --- | --- |
| P | Each player's motives, personal quest ties to the vein |
| S | The crisis and its resolution (chronicle); sect influence deltas (sim) |
| I | Crisis instance participation per player |
| R | Contribution-weighted rewards per participant |
| Knowledge | All see the crisis; none sees others' personal stakes |
| Resolution | Individual heroic acts feed *influence/attitude* edges via sim rules; **declared** diplomacy changes only through the governance event path (C1.2) — one player's action is input, never verdict |
| Replication | Influence deltas and the crisis outcome replicate; declared relations change only on governance events |
| Guard | Anti-corruption: no single private story flag can flip a public declared relation |

---

## C1.4 — Online policy backlog (OPEN QUESTION or PROPOSAL — NOT FROZEN)

None of these are settled here. Each lists why it matters, the responsible
phase/decision owner, the risk of skipping, and what must wait for approval.

| # | Item | Status | Why it matters | Owner | Risk if skipped | Blocked until approval |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Player-founded sects | **OPEN QUESTION** | Sect is a core identity pillar; players will ask | Phase 33+ (MP foundation) / owner | Unofficial "sects" emerge as chat groups with no rules, corrupting the roster-authority model | Any sect-creation mechanic |
| 2 | Player-run leadership / governance | **OPEN QUESTION** | Declared-diplomacy governance (C1.2) needs a decider | Phase 33+ / owner | Governance path has no human counterpart; all politics stay NPC-driven | Leader election/succession mechanics |
| 3 | Unrestricted or opt-in PvP | **OPEN QUESTION** | Combat is command-intent based; PvP changes the threat model | Phase 34 (MP gameplay) / owner | Griefing vectors unexamined; reward ledger assumes cooperative contribution | Any player-targeting combat |
| 4 | Player-to-player trade / market, economic exploits | **OPEN QUESTION** | Inventory is server-validated; trade opens duplication vectors | Phase 34 / owner | Duplication bugs become economy-destroying at scale | Trade/market UI and APIs |
| 5 | Alt-character / alt-account effects | **OPEN QUESTION** | One human, many characters breaks per-character scopes | Phase 33+ / owner | Reward ledger farmed via alts; influence Sybil attacks | Cross-character aggregation of any kind |
| 6 | Endgame social competition | **OPEN QUESTION** | Sect rivalry needs a scoreboard that isn't a single score (CL-12) | Phase 34 / owner | Competition collapses to the forbidden single-score shape | Leaderboards, rankings |
| 7 | Guild-like organizations | **OPEN QUESTION** | Social state names them; no design exists | Phase 33+ / owner | Players build guilds from DMs; no moderation/authority story | Guild creation/management |
| 8 | Public event contention | **OPEN QUESTION** | World vein crises (scenario e) will be contested | Phase 34 / owner | First-come/first-served races; no fairness rule | Contended world-event mechanics |

---

## C1.5 — Deliverable, validation, and stop gate

- This file is the single review artifact, marked **PROPOSAL — NOT FROZEN** throughout.
- **No frozen body text altered.** `CANON_LEDGER.md`, architecture/production contracts,
  and all `(FROZEN)` sections are cited, never rewritten. The one schema change
  discussed (ADR-001, `PLAYER` endpoint kind) is proposed text only, not applied.
- **Document checks:** this is a docs-only change; the relevant validation is
  markdown/prose review. No GDScript changed; no test suite impact.
- **Source verification for this proposal:** `origin/main` @
  `ce4b94c0e430cbe84182e76c198c2a6ffe470f5c`, CI run `38211074765` SUCCESS.
  Research read 21 source files from this SHA via three parallel readers; repo
  working tree untouched during research (`git status --short` clean before and after).
- **Unmeasurable/unverifiable outcomes:** none claimed. Timing, performance, and
  player-experience claims are absent by design (design gate, no implementation).
- **Revise→verify cycles used:** 3 of 3 (R1: provenance repair + design review gate; R2: final consistency audit). No further cycles without owner direction.
- **Final status: READY FOR OWNER REVIEW.**
- **STOP.** Do not start C2. Do not implement networking. Do not touch `main`.
  Awaiting owner review and approval of the proposal status.

---

## C1-R1 — Design review gate (2026-10-12, revise→verify cycle 2)

All labels below remain **PROPOSAL — NOT FROZEN**. Nothing here is canon.

### R1.4 — Six-scope critique

| Scope | Purpose / owner | Canon support | New decision proposed | Benefits / risks | Offline that must stay correct | What can wait for MP | Verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 — Personal canon | Origin, chapter/beat, choices, knowledge, clue interpretation. Owner: per-player state (`StoryRuntime`, `KnowledgeService`) | §14 "never shared"; CL-14 knowledge never a story flag; frozen acceptance test | Clue *interpretation* as per-player view over shared knowledge (not a fork) | Benefit: clean spoiler boundary. Risk: if interpretation ever drives shared outcomes it leaks across the boundary | Everything — offline is already fully per-player | Nothing | **KEEP** |
| 2 — Shared world chronicle | World events + persistent facts with explicit authority/trigger/scope. Owner: world-sim (server in TARGET) | §14 "per world/shard … may be shared or instantiated per group" (deliberately open); Phase 08 determinism | **Shared per shard**, not per-group instanced (see R1.5A) | Benefit: one truth for world facts; matches 70–85% shared macro canon. Risk: shard topology undefined; absent-player catch-up unruled | Offline has exactly one world; stays fully authoritative, deterministic, no shard concept | Shard topology, placement, migration, cross-shard identity | **KEEP** the shared-per-shard default; **DEFER** shard topology (already OPEN QUESTION) |
| 3 — Public organization state | Membership (roster-wins), declared diplomacy, leadership, resources, sim outputs. Owner: `SectService` / `FactionService` | D-015 roster authority; CL-17 declared-vs-edge split, deterministic politics, no RNG | Declared diplomacy changes only via governance event; influence drift via sim rules | Benefit: auditable, no silent rewrites. Risk: governance mechanics don't exist; offline politics are NPC-driven so the path is vestigial — must not become dead code | Sect/faction systems work offline via authored content; declared changes via content, not governance UI | Governance mechanics (votes, charters) | **REVISE**: keep the *principle* as a content-authoring constraint; strip the illustrative examples (council vote, supermajority) from normative text — see R1.5C |
| 4 — Pairwise/social state | Player↔NPC, player↔player, character↔character, sect↔sect relations. Owner: `RelationshipService`, one graph | CL-12 six dimensions; one graph; directed/symmetric semantics; single mutation path | ADR-001: add `PLAYER` endpoint kind | Benefit claimed: separate player lifecycle. Risk: two namespaces for one entity; no present consumer branches on endpoint kind (see R1.5B) | Player is `CharacterState` ("player"); registry: "being the player is a fact the session holds, not a property of a row in this table" | Player↔player rules, if ever needed, ride the existing CHARACTER kind | **DEFER** ADR-001 to Phase 33+ identity work; do not add now |
| 5 — Party/instance state | Run outcomes, participation, local objectives. Owner: instance context (does not exist) | §14 "party / instance state — temporary"; dependency matrix "party/instance state" | Bounded context with ID, member list, objective ledger; read snapshots in, write back only via ledger + allow-listed proposals; transient state discarded, durable outcomes persist via owners (R3 refinement) | Benefit: isolation, no leakage into persistent truth. Risk: Phase 21/22 NOT STARTED — pre-designing instance semantics before dungeon/boss systems exist builds on guesses; the allow-list has no consumer | Phase 21 will need run state; its real shape must come from Phase 21's needs | Concrete instance-context design (ID scheme, snapshot mechanics, allow-list) | **REVISE**: keep the *isolation principle* (transient discarded, durable via owning paths); **DEFER** the concrete mechanics to Phase 21 |
| 6 — Reward/participation state | One authoritative ledger: eligibility, contribution, claims, anti-duplication. Owner: reward ledger (`RewardLedger` + `RewardService`) | Dependency matrix "the authority's guard against a replayed grant"; `reward_id` pattern | **IMPLEMENTED** (Phase 19, D-070): `claim(reward_id)` idempotent; duplicates silently survivable by design. Proposed: contribution recorded per participant, eligibility resolved before instance close | Benefit: anti-duplication, auditable. Risk: contribution weighting rules don't exist | Progression grants stay single-path offline | Contribution weighting (Phase 21/22 content) | **KEEP** |

### R1.5 — Three key decisions

#### A. Shared chronicle per shard vs instanced per group — recommendation: shared per shard (KEEP)

Default stands. Case-by-case:

- **World event persists after the party disbands** (e.g. "the vein was sealed"): must be
  chronicle-shared, or two parties produce incompatible world truths with no merge rule.
  Shared per shard handles this; per-group instancing does not.
- **Dungeon with per-group progress**: instance-local by definition (Scope 5). Sharing the
  chronicle does **not** imply sharing dungeon internals — the proposal never claims all
  dungeon facts are world facts. Only allow-listed close-out events cross the boundary.
- **Two players at different chapters**: frozen acceptance test — personal story never
  forced to match. Orthogonal to chronicle sharing.
- **One player knows a clue, the other doesn't**: CL-14 — knowledge is per-player under a
  shared service. The chronicle records that the clue *exists*; who *knows* it stays
  personal. No conflict.
- **Shard transfer / absence during an event**: the genuinely hard case. Shared per shard
  requires catch-up rules (event log replay on return; transfer = leave one shard's
  chronicle, join another's — personal state travels, chronicle does not). These rules are
  **DEFERRED** to multiplayer phases; the proposal must not pretend they exist.

#### B. ADR-001 — add `PLAYER` endpoint kind — verdict: DEFER (do not add now)

Evidence read at `ce4b94c` before deciding:

- `src/domain/relationship/relationship_endpoint.gd`: `enum Kind { CHARACTER, SECT, FACTION }`;
  `CHARACTER` = a `CharacterState.instance_id`. The header comment already handles the
  collision class: "`kind` distinguishes a Character instance from a Sect from a Faction,
  so the character instance "player" … can never collide." Serialization uses stable
  string tokens, append-only — adding a kind is technically safe.
- `src/domain/character/character_state.gd:6-7`: "The player is a Character, so the
  player's identity + stats + life state live HERE."
- `src/domain/character/character_registry.gd:25-26`: "\*\*being the player is a fact the
  session holds, not a property of a row in this table.\*\*"

Analysis:

- **Identity/lifecycle difference?** In the current model: **no**. The player is
  `CHARACTER:"player"`; player-ness is session context, not graph identity. The
  production contract's six session identities (`player_id` vs `character_id`) split
  player from character at the **session layer**, not in the relationship graph.
- **Serialization/migration**: append-only enum + token serialization is safe, but every
  existing `CHARACTER:"player"` edge would need a migration rule to `PLAYER:"player"`,
  and any lookup by `for_character("player")` would silently miss the new-kind edges —
  the exact second-namespace hazard the typed endpoint was built to prevent.
- **Consumers**: no rule today branches on "is this endpoint the player" via kind;
  dimensions and edge types carry the semantics. ADR-001 has no present consumer.
- **Verdict: DEFER** to Phase 33+ identity work, where the session-layer
  player/character split actually exists. The ADR-001 text stays in the proposal as a
  deferred option, not a recommendation. No schema or GDScript changed.

#### C. Governance of declared diplomacy — verdict: REVISE (principle kept, mechanics unpinned)

- **Kept principle (non-negotiable):** one player's private action — including a private
  story flag — can never directly flip a declared sect↔sect relation. Declared changes
  go through an explicit, auditable, deterministic governance path. This is the load-bearing
  wall of C1.2 and stays.
- **NPC/world-law governance vs player-participatory governance**: today all politics are
  NPC-driven (factions ship leaderless, Phase 07 "enrols nobody"); the governance path's
  only live consumer is authored content and sim rules. Player-participatory governance
  (votes, petitions) is an **OPEN QUESTION** (backlog #2) — the proposal must describe the
  *interface* (proposal → deterministic resolution → revisioned event) without prescribing
  the *decider*.
- **Revision made**: the C1.2 authority table's examples ("council vote threshold",
  "influence supermajority with tie-break", "lowest entity ID") were written as if decided.
  Per the repair brief they are **demoted to illustrative options**; the normative text now
  requires only: explicit rule, bounded conditions, deterministic resolution, revisioned
  auditable event, loser recorded as superseded. No specific council/supermajority/tie-break
  is pinned without design basis.
- **Offline consequence**: none — offline declared changes continue via authored content;
  the constraint binds future content authoring, not current code.
- **Determinism/audit**: retained — politics rules use no RNG (CL-17); every declared
  transition is an append-only revision (reversal = new superseding event).

### R1.6 — Architecture contradiction check (proposal vs canon, direct)

| Canon rule | Proposal position | Result |
| --- | --- | --- |
| `KnowledgeService` owns knowledge; knowledge never a private story flag (CL-14) | Scopes 1–2 keep knowledge under the service; interpretation is a view, not a fork | **Consistent** |
| No single relationship score (CL-12) | Six dimensions kept; no score introduced; backlog #6 explicitly warns against it | **Consistent** |
| `FactionState` carries only DECLARED relation; standings are edges (CL-17) | Scope 3/4 preserve the split; governance touches declared only | **Consistent** |
| Sect roster authoritative; `CharacterState.sect_id` is read cache (D-015) | Scope 3 states roster-wins | **Consistent** |
| Offline and online run the same domain rules; differ in authority/transport (D-056) | All six scopes defined as authority placements over the same rules; no "multiplayer formula" | **Consistent** |
| World-sim determinism; events mutate through owning system only (Phase 08) | Scope 2/3 keep owner-only mutation; politics no-RNG retained | **Consistent** |
| Personal/shared/instance/reward must not overlap into second sources of truth | Interpretation-as-view (not fork); instance writes back only via ledger + allow-list; reward idempotency by `reward_id` | **Consistent** — no overlap found |
| Four-way state split frozen (§14) | Six scopes are a refinement, not a replacement: personal→Scope 1, chronicle→Scope 2, party→Scope 5, social→Scopes 3+4, reward→Scope 6 (new, canon-compatible) | **Consistent** — refinement, no frozen text altered |

No contradictions found. Where the proposal previously over-specified (governance
examples, ADR-001 as recommendation, instance mechanics), R1.4–R1.5 demote or defer.

### R1.7 — Open questions actually needing the owner's decision

1. **Shard topology** (Scope 2): how many shards, placement, migration, cross-shard
   identity. Everything else in Scope 2 can stand without it.
2. **Player-participatory governance** (backlog #2): does the design ever want human
   deciders for declared diplomacy, or stay NPC/authored forever? The interface is
   specified; the decider is not.
3. **H21-14 owner playtest**: still OPEN / OWNER REQUIRED — unrelated to C1 but the
   standing gate before Phase 21.
4. **Proposal approval itself**: KEEP/REVISE/DEFER verdicts above are still
   PROPOSAL — NOT FROZEN until the owner approves.

### R1.8 — What changed in this cycle and what did not

**Changed in R1 (cycle 2):**

- Header: provenance block added — `origin/main` = `ce4b94c` verified by live ref check;
  `origin/hardening/pre-phase21-gate-b2` = same SHA (no divergence); proposal file is
  untracked working-tree content, researched against `origin/main` not the working tree;
  CI verified via GitHub API (run 38211074765, success, attempt 1).
- H21-21: brief/handoff discrepancy resolved → **CLOSED — VERIFIED AT&#32;`ce4b94c`**
  with handoff (§16.1) and code paths
  (`movement_component.gd:92-93,106`; `test_case.gd:72`) cited.
- Scope 3: governance examples demoted from normative to illustrative (R1.5C).
- Scope 4 / ADR-001: recommendation changed to **DEFER** with schema evidence (R1.5B).
- Scope 5: concrete instance mechanics **DEFERRED** to Phase 21; isolation principle kept.
- Added: R1.4 decision table, R1.5A case analysis, R1.6 contradiction check, R1.7 owner
  questions, R1.8 change list (this section).

**Changed in R3 (final online authority review addendum):**
- Scope 5: "discarded on close" refined — transient encounter state discarded,
  durable outcomes (reward records, close-out events) persist via owning scopes.
- C1.2: cross-reference added to `PROPOSAL_ONLINE_AUTHORITY_ARCHITECTURE.md` §§1–3
  for execution/deployment/persistence aspects (normative rules live in one doc).

**Changed in R2 (cycle 3, final consistency audit):**
- Scope 6: corrected the false "double-claim rejected, not silently deduped" claim.
  Verified at `ce4b94c`: `RewardLedger.claim()` is IMPLEMENTED (Phase 19, D-070) and
  duplicate delivery is **silently survivable by design** (`progression_runtime.gd`).
  The anti-replay property comes from idempotent ignore, not loud rejection. The R1.4
  Scope 6 row was carrying the same stale wording and was corrected too.
- Scope 2: terminology note added — "chronicle" here is a proposed domain capability
  (PROPOSED — NOT IMPLEMENTED); the existing `src/presentation/chronicle/` files are
  UI views, not a world-facts system.
- C1.2 authority table: governance row rewritten — examples (council vote, influence
  threshold, tie-break) demoted from normative rule to illustrative options, matching
  the R1.5C verdict already recorded (the original table still stated them as decided).

**Not changed:**

- `CANON_LEDGER.md`, any `(FROZEN)` text, `DECISIONS.md` — untouched.
- No GDScript, no schema, no networking/server/dungeon/boss code.
- No commit, no push, no merge. File remains untracked in the working tree.
- Phase 21/22 status: NOT STARTED — unchanged by this review.
- H21-14: OPEN / OWNER REQUIRED — unchanged.
- Revise→verify cycles used: **3 of 3**. No further cycles permitted without owner direction.

---

## Appendix — Source index (every claim above traces to one of these)

| # | Document | SHA read |
| --- | --- | --- |
| 1–3 | `.kiro/steering/01-product.md`, `02-game-design.md`, `03-architecture.md` | `ce4b94c` |
| 4–6 | `.kiro/steering/08-ai-review-protocol.md`, `09-lessons-learned.md`, `10-ci-failure-protocol.md` | `ce4b94c` |
| 7 | `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md` (D-056) | `ce4b94c` |
| 8 | `docs/SYSTEM_DEPENDENCY_MATRIX.md` | `ce4b94c` |
| 9 | `docs/NARRATIVE_MASTER_PLAN.md` | `ce4b94c` |
| 10 | `docs/WORLD_BIBLE.md` | `ce4b94c` |
| 11 | `docs/CANON_LEDGER.md` (D-039) | `ce4b94c` |
| 12 | `docs/CONTRADICTION_REGISTER.md` | `ce4b94c` |
| 13 | `docs/MULTIPLAYER_PLAN.md` | `ce4b94c` |
| 14 | `docs/RELATIONSHIP_SYSTEM.md` | `ce4b94c` |
| 15 | `docs/SECT_SYSTEM.md` | `ce4b94c` |
| 16 | `docs/SOCIAL_DESIGN.md` | `ce4b94c` |
| 17 | `docs/WORLD_SIMULATION.md` | `ce4b94c` |
| 18–20 | `docs/handoff/phase-19-quest.md`, `phase-20-story.md`, `pre-phase-21-hardening.md` | `ce4b94c` |
| 21–23 | `src/domain/relationship/relationship_endpoint.gd`, `src/domain/character/character_state.gd`, `src/domain/character/character_registry.gd` (R1.5B schema evidence) | `ce4b94c` |
| 24–25 | `src/gameplay/components/movement_component.gd`, `tests/framework/test_case.gd` (H21-21 fix evidence) | `ce4b94c` |
| 26–28 | `src/domain/reward/reward_ledger.gd`, `src/domain/reward/reward_service.gd`, `src/gameplay/world/progression_runtime.gd` (R2: ledger behavior — silent survivable dedup by design) | `ce4b94c` |
| 29–30 | `src/domain/knowledge/knowledge_service.gd`, `src/domain/knowledge/knowledge_store.gd` (R2: per-player authoritative collection) | `ce4b94c` |