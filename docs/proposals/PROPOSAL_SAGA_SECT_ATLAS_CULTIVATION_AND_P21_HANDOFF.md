# PROPOSAL — Saga, Sect Atlas, Cultivation Loop & Phase-21/22 Handoff (C2)

> **Status: PROPOSAL — NOT CANON — OWNER REVIEW REQUIRED.**
>
> This document does not authorize Phase 21 or Phase 22 implementation. It does not approve or freeze the C1 proposals. Existing accepted decisions and frozen canon remain authoritative.

| Category | Meaning in this document |
|---|---|
| EXISTING CANON | Already established in an authoritative project source (frozen docs, `CANON_LEDGER.md`, `WORLD_BIBLE.md`, `NARRATIVE_MASTER_PLAN.md`) |
| ACCEPTED DECISION | Formally accepted direction or constraint recorded in `docs/DECISIONS.md` |
| C2 PROPOSAL | Newly recommended design in this document, requiring owner review before it becomes canon |
| OPEN QUESTION | Requires evidence, clarification, or an explicit owner decision |
| OUT OF SCOPE | Explicitly not designed, decided, or implemented by C2 |

Authored 2026-10-12 against `origin/main` @ `bbd39d6fc2b955280f77ef195234d6dc07939b6b`
(CI run 38225105400 SUCCESS). Design only. No code, no content, no assets were produced by this task.

---

## 1. Document status and non-canon warning

This is the C2 design proposal authorized by the owner on 2026-10-12: a ten-act saga blueprint, a sect atlas for Thanh Vân Tông and Xích Diễm Tông, a cultivation/progression loop, a clue-to-payoff ledger, and strictly bounded narrative handoffs to the planned Phase 21 (Dungeon) and Phase 22 (Boss) content.

What this document **is**:

- A single owner-reviewable design artifact connecting saga, sects, cultivation economy, clues, and the Survey Shaft handoff into one coherent blueprint.
- A proposal that labels every major claim with its authority level (see the table above).

What this document **is not**:

- It is not canon. Nothing in it becomes canon by being written here; canon changes require a `docs/DECISIONS.md` entry per the freeze change control (`docs/GAME_DESIGN_FREEZE.md`, "What 'frozen' means here").
- It is not an approval of either C1 proposal. The two C1 proposals remain **PROPOSAL — NOT FROZEN** per D-074's explicit wording.
- It is not a Phase 21 or Phase 22 implementation plan. Phase 21 and Phase 22 are **NOT STARTED**. C2 completion does not close H21-14 and does not authorize entering Phase 21.
- It does not change any accepted decision, frozen document, gate status, or handoff record.

**Reading rule for implementers:** when this document says "the proposal recommends X," treat X as a question the owner has not yet answered. When it says "canon establishes X," the cited source is authoritative and this document adds nothing.

---

## 2. Executive summary

Aetheria's long story is a ten-act saga about a nobody who survives a broken vein, learns that orthodox records are edited for institutional convenience, and is eventually forced to answer what the Thiên Khế — and the word "Tà Đế" — should mean. The saga's engine is a single long thread: **the suppressed survey** (K-05 → K-06 → K-10 → the surveyor's field book → "orthodox records are edited" → Acts VI–VII), planted in Act I, advanced through the Survey Shaft in Act II, and paying off into the covenant question of Act VII.

The sect atlas gives that thread its human pressure. Thanh Vân Tông's three authored factions — Vân Đài (loyalist), Khai Lộ (reformist), Biên Vân (radical) — are preserved exactly as canon; the proposal adds how the player meets them, what each wants from the player, and what cooperation or refusal costs. Xích Diễm Tông's canonical internal split (those who pay the price from their own bodies vs. those who extract it from others) is expanded into a **proposed** two-faction structure, every name and role labeled PROPOSAL until the owner approves.

The cultivation loop keeps the three existing axes distinct — Level/XP (smooth power, never gates), Cảnh giới/realm-layer (capability and access, answers "what can I do now?"), Knowledge/Tri Thức (discrete, permanent, never consumed) — and connects them to a resource economy where every currency has a sink, knowledge is the deliberate exception, and the main story is never gated behind bulk repetition.

The Phase 21 handoff defines only the narrative reason to enter the Survey Shaft, the causal clue chain, the kept/told route semantics, and the entry-state contract the future implementation must honor — no rooms, no encounters, no boss. The Phase 22 handoff defines only the narrative purpose of the post-boss consequence: the outpost can no longer say the shaft was sealed, serving the K-03 and K-04 payoff obligations — no boss identity, moves, or tuning.

Key recommendations for the owner:

1. **Adopt the kept/told definitions proposed in §15** (kept = kept Lâm Nguyệt's confidence; told = told the elder) as canon glossary, because Phase 21's entry logic depends on them and no formal definition exists today (OPEN QUESTION Q-01).
2. **Approve the Xích Diễm Tông faction proposal in §10 or replace it** — the sect cannot carry story weight in later acts while its internal split stays unauthored.
3. **Decide the sect-switching policy (§11.E) before Phase 21 content locks entry routes**, because K-13 ("who stands with the player at the door") interacts with faction standing.
4. **Run the GAME_DESIGN_FREEZE amendment** (D-074 follow-up): the frozen line "Offline is the source of truth. No networking in Stage 1." still stands verbatim alongside D-074 and will confuse every future reader until the freeze's own change control processes it.
5. **Do the H21-14 owner playtest** (§17.6 checklist). Nothing in this proposal substitutes for it, and Phase 21 must not start without it.

---

## 3. Scope and explicit non-goals

**In scope (design only):**

- Ten-act saga blueprint (Acts I–III detailed; IV–X scaffolded).
- Clue-to-payoff ledger for K-01–K-13, preserving existing IDs and meanings.
- Sect atlas: Thanh Vân Tông (canon preserved + proposal) and Xích Diễm Tông (canon split + proposed factions).
- Inter-faction relationship matrix with causal support.
- Player sect affiliation: discovery, joining, techniques, questlines, multiplayer fairness, membership lifecycle.
- Cultivation/progression loop and resource economy matrix, using the existing design docs as constraints.
- Phase 21 access/entry handoff (narrative reason, causal chain, route semantics, entry contract, continuity checks).
- Phase 22 narrative-purpose handoff (inherited pressure, clue obligations, observable consequences).
- Shared-world/state-boundary compatibility analysis against the frozen four-way split.
- Replayability design within the 70–85% / 15–30% target.
- Open-question and risk register; Phase 21 readiness dependencies; acceptance checklist.

**Explicit non-goals (OUT OF SCOPE):**

- Implementing Phase 21 or Phase 22 in any form.
- Survey Shaft interior: no room layouts, encounter catalogue, enemy rosters, puzzles, loot tables.
- Boss identity, visual/audio design, moveset, phases, tuning, arena layout.
- Production gameplay code, networking code, persistence code, tests, migration scripts, new assets.
- Production quests, dialogue batches, sect content data, or large asset batches.
- Changing any canon document, decision record, handoff, or frozen text to match this proposal.
- Closing or altering any gate (H21-14, H21-21, H21-20, B2-01, UI-01, UI-02).
- Deciding open architecture questions: transport, account-to-character cardinality, shard transfer, admin permission hierarchy, persistence technology, implementation schedule.

---

## 4. Source-of-truth and authority notes

Authority order used throughout (per the C2 brief §C2.0.3):

1. The owner's explicit C2 authorization (design only, 2026-10-12).
2. Accepted decisions in `docs/DECISIONS.md` and frozen documents (`docs/GAME_DESIGN_FREEZE.md` v2.1, D-039).
3. Canon in `docs/CANON_LEDGER.md`, `docs/NARRATIVE_MASTER_PLAN.md`, `docs/WORLD_BIBLE.md`, and approved references.
4. Phase-execution and handoff evidence (`docs/handoff/pre-phase-21-hardening.md`, `docs/PHASE_EXECUTION_PROTOCOL.md`).
5. Implemented behavior, where verified.
6. C1 proposals and other unaccepted proposals.
7. New C2 recommendations (this document).

**Material conflicts found between C1 proposals and accepted decisions:** none that rise to direct conflict. The full review is in §6. The two live risks are (a) misreading owner approval of the *direction* (D-074) as approval of the *proposal contents*, and (b) the outstanding GAME_DESIGN_FREEZE amendment. Details in §19 (R-01, R-02).

**Stale references inside the C1 documents (recorded, not fixed — fixing them would mean editing someone else's proposal):** both C1 files describe themselves as "untracked in the working tree," which was true when written but is stale since commit `7ea10e4` landed them. Their "STOP — do not start C2" gates are superseded for this task by the owner's explicit C2 design authorization, which is narrowly scoped per §C2.0 of the brief.

**Missing or ambiguous sources:**

- No formal definition of the `kept` / `told` routes exists in any canon doc (usage only, in `NARRATIVE_MASTER_PLAN.md` §9a and `CONTENT_BIBLE.md` §16). Treated as OPEN QUESTION Q-01; this proposal offers bounded definitions in §15.
- No text-skimmer rule exists in the narrative docs under that name; clue fairness exists as "A clue the player can hold is a promise" (`NARRATIVE_MASTER_PLAN.md` §9a). §14 of this proposal operationalizes it.
- The "Stage 1" phase range is never pinned; the multiplayer phases are 32–34 (`docs/ROADMAP.md`). This proposal places itself explicitly: design for the server-authoritative target, no networking implementation, compatible with Stage-1 code constraints.

---

## 5. Verified current baseline and phase/gate state

Verified 2026-10-12 against `origin/main` @ `bbd39d6` (CI run 38225105400 SUCCESS).

**Product direction (ACCEPTED DECISION, D-074):** online multiplayer-first; the production world is server-authoritative; offline play is a restricted secondary Admin Offline Test Mode; online and offline use the same domain rules (D-056 stands) and differ in authority and transport only. Explicitly not decided: C1 implementation details, account-to-character cardinality, shard transfer, admin permission hierarchy, persistence technology, transport, schedule.

**Architecture target (ACCEPTED DECISION, D-056):** the target online model is an authoritative dedicated server; clients send intents only. Contract lives in `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md`. Target, not implementation — no networking code exists.

**Phase status (EXISTING CANON, `docs/ROADMAP.md`):** Phases 00–20 DONE (Phase 20 Story DONE under D-072; post-Phase-20 hardening DONE under D-073). **Phase 21 (Dungeon) NOT STARTED. Phase 22 (Boss) NOT STARTED.** Phase 21 is defined as `DungeonData` + instance modifiers on the map/combat/loot systems, addable via data; Phase 22 as `BossData` with phases + boss AI, phases as data. The Survey Shaft's door does not open (`docs/GAME_FLOW.md`); what is behind it is Phase 21's.

**Gate status (evidence in `docs/handoff/pre-phase-21-hardening.md`):**

| Gate | Status | Close condition |
|---|---|---|
| H21-14 | **OPEN / OWNER REQUIRED** | the owner plays the §17.6 checklist and writes down what happened |
| H21-21 | **CLOSED** (Gate A, §16.1) — root cause found (`move_and_slide()` outside the fixed physics step), guard + test added; known limit: the failed CI runner's process-step value was not recorded | — |
| H21-20 | **CLOSED** (Gate B2) | — |
| B2-01 | **OPEN** — six contact sheets unreviewed; `reach` judge not mutation-tested; three Origin vignettes uncaptured | "reviewed, or captured" |
| UI-01 | **OPEN** — other panels/HUD/world visuals await the owner's UI brief | owner brief |
| UI-02 | **OPEN** — satchel card not captured while wearing an item | capture with robe worn |

**Gate statement (verbatim, handoff §18.5):** "Gate B2 stops here. Gates C1 and C2 were not started. Phase 21 and Phase 22 have not started."

**C2 completion does not change any row above.** In particular: C2 does not close H21-14, and nothing in this proposal authorizes Phase 21.

---

## 6. Canon, decision, and proposal boundaries

### 6.1 What C2 must not move (frozen / accepted)

- **Ten-act structure** (`NARRATIVE_MASTER_PLAN.md` §8): acts I–X, their titles, order, and core questions. C2 elaborates inside acts; it does not replace or renumber them. (EXISTING CANON)
- **Nine-layer reveal ladder** (§9): strictly ordered; a phase may not reveal layer N+1 to make a scene land. (EXISTING CANON)
- **CL-15 beyond layer 9** (`CANON_LEDGER.md` CL-15; NARRATIVE_MASTER_PLAN §9): five permanently open mysteries, never closed. (EXISTING CANON)
- **Four-way narrative state split** (NARRATIVE_MASTER_PLAN §14): Personal story (per player, never shared) / World chronicle (per world/shard, may be shared or instantiated) / Party-instance (temporary) / Social (shared). Frozen; the C1 six-scope model stays a proposal. (EXISTING CANON + ACCEPTED DECISION D-074 consequence)
- **Thanh Vân Tông's three factions** (`WORLD_BIBLE.md` §8; `CANON_LEDGER.md` CL-17): Vân Đài, Khai Lộ, Biên Vân — names, goals, relationships, and the contested 45/38/31 influence shape are canon. (EXISTING CANON)
- **Xích Diễm Tông's internal split** (WORLD_BIBLE §8; CL-17): the split itself is canon; its faction data is not yet authored. (EXISTING CANON)
- **Survey Shaft as lead** (CL-11): `dungeon_survey_shaft` → Hầm Khảo Mạch is "a LEAD, not a place yet"; door boarded and sealed in `map_field`; no interior canon until Phase 21 writes it. (EXISTING CANON)
- **K-series clue meanings and payoff layers** (NARRATIVE_MASTER_PLAN §9a): IDs K-01–K-13, their planted meanings, and owed payoffs are canon. New clues use a separate proposed-ID convention. (EXISTING CANON)
- **Progression axes** (`PROGRESSION_CULTIVATION_DESIGN.md`): Level/XP ≠ Cảnh giới ≠ Knowledge; "Level is NEVER an access gate" (C-002); realm steps must answer "what can I do now?" (EXISTING CANON)
- **"Offline is the source of truth. No networking in Stage 1."** (`GAME_DESIGN_FREEZE.md` §5): frozen text, not rewritten by D-074; amendment pending through the freeze's own change control. (EXISTING CANON — in tension with D-074's "do not describe Aetheria as offline-first"; see R-02)
- **D-074 product direction** (ACCEPTED DECISION): multiplayer-first, server-authoritative, Admin Offline Test Mode, same domain rules.
- **D-056 dedicated-server target** (ACCEPTED DECISION): authoritative dedicated server; clients send intents only.

### 6.2 C1 proposals: what they claim and where they stand

Both C1 proposals were reviewed claim-by-claim against the accepted decisions. Verdicts:

- **Six-scope story model** (`PROPOSAL_SHARED_WORLD_STORY_MODEL.md`): **C2 PROPOSAL-level material, not authority.** It is explicitly "a refinement, not a replacement" of the frozen four-way split. This document uses the frozen four-way split for all state classifications (§17) and does not promote the six-scope model.
- **Chronicle "shared per shard"**: decides a question §14 deliberately left open ("may be shared or instantiated"). Legitimate for a proposal; this document treats shard-vs-group chronicle scope as OPEN QUESTION Q-02 and designs the Phase 22 consequence to work under either.
- **"Privacy is the default" vs. frozen "never shared"** (personal story): in tension. This document holds the frozen line — personal story state is never shared, and no publication mechanism is proposed (§17).
- **Modular-monolith backend target** (`PROPOSAL_ONLINE_AUTHORITY_ARCHITECTURE.md`): compatible as labeled; prescribes no persistence technology and defers it past D-074's reserved questions. This document decides no backend topology.
- **Open questions correctly left open by C1** (transport, account↔character, shard transfer, admin hierarchy, persistence): this document also leaves them open (§19).

### 6.3 What this proposal adds (C2 PROPOSAL)

Act-level elaboration inside the frozen ten acts; the K-series ledger presentation (meanings unchanged); proposed Xích Diễm Tông faction names/roles; sect-affiliation mechanics; the cultivation loop narrative; Phase 21 entry handoff; Phase 22 purpose handoff; state-boundary classifications; replayability composition; the risk register. All require owner review. None is canon.

---

## 7. Ten-act saga blueprint

Authority note: act numbers, titles, order, scale, and core questions are EXISTING CANON (`NARRATIVE_MASTER_PLAN.md` §8). Everything else in this section is C2 PROPOSAL elaboration inside those acts, unless marked otherwise. Reveal-layer assignments follow the frozen ladder (§9): layers 1–3 = Acts I–III; 4–5 = IV–V; 6–8 = VI–VIII; 9 = IX–X.

The saga's engine, stated once so every act can reference it: **the suppressed survey is the long thread.** K-05 → K-06 → K-10 → the surveyor's field book (Phase 21) → "orthodox records are edited for institutional convenience" → Acts VI–VII → the Thiên Khế question. (EXISTING CANON: NARRATIVE_MASTER_PLAN §4 "FUTURE PAYOFF".)

**Saga integrity rules applied throughout (EXISTING CANON unless noted):**

- Divergence happens *inside* acts; acts converge. No parallel campaigns.
- Never reveal layer N+1 to make a scene land.
- CL-15 stays past layer 9, never closed.
- The player is not chosen and not the target; what the player gets from Đêm Vỡ Mạch is information, not power (NARRATIVE_MASTER_PLAN §4).
- There is no morality bar; identity is derived from history (NARRATIVE_DIRECTION §2).
- Every act ends in a durable consequence, not a new quest marker (C2 PROPOSAL discipline).

---

### Act I — KẺ VÔ DANH (layers 1–2)

- **Narrative purpose (EXISTING CANON):** establish the nobody's start: can I survive and matter here? One frontier châu.
- **Player's main goal (C2 PROPOSAL):** live through Đêm Vỡ Mạch, then understand what happened — the goal shifts from survival to investigation the morning after.
- **Central conflict:** the vein beneath Rừng Vỡ Mạch breaks (CL-08). Someone was drawing on it. The outpost's account and the ground disagree. Opposing interests: the elder's need for a clean story (order, the covenant reading) vs. the physical evidence (the survey line, the shaft door, the cart track).
- **Principal location/social context:** Thôn Lạc Hà (`map_hub`) and Rừng Vỡ Mạch (`map_field`).
- **What changes in the world:** Đêm Vỡ Mạch happens (K-01 PAID); the outpost begins suppressing evidence (K-04 planted, K-08 planted, K-09 planted).
- **Cultivation significance:** entry into Hậu Thiên is gated by the Knowledge Core (frozen D-040); the first realm steps teach the "what can I do now?" contract. Threat is readable in realm vocabulary from the start.
- **New clues:** K-02 through K-13 (all planted in Phase 20 / D-073; see §8).
- **Existing clues advanced:** none — this is the planting act.
- **Payoffs delivered:** K-01 (the Night itself).
- **Mysteries withheld:** who drew on the vein; what was taken from the shaft; who bought it; what the Night's creatures were.
- **Reveal layers:** 1 (something is wrong — the vein broke) and 2 (someone caused it).
- **Main choices and consequences (C2 PROPOSAL):**
  - `choice_lam_readings` — **kept** (kept Lâm Nguyệt's confidence) vs. **told** (told the elder). Proposed canon definitions (§15): kept means her readings stay her secret and the sheet is hers to give in beat 11; told means the elder knows, her rod ends up in the elder's chest, and the sheet is the player's to find. Both routes reach the same door; they differ in who stands with the player and what each NPC remembers. (K-02; must never gate Phase 21 entry — K-13 constraint.)
  - `choice_sheet_shown` (lin / ko / shen) — who saw the survey sheet first (K-13). Proposed consequence: determines who stands with the player at the shaft door and which knowledge each NPC volunteers later. Never gates entry.
  - Trust decisions (beats 3–12): each in a separate run, visible consequences, no re-asking (per the H21-14 checklist expectations).
- **Shared macro-canon:** the Night happened; the vein broke; the outpost suppresses evidence; the shaft door is boarded and sealed.
- **May vary:** Origin vignette and its trail observation (K-12); kept/told; who saw the sheet first; trust-decision outcomes; relationship deltas with the four Lạc Hà principals.
- **Prerequisites/dependencies:** none — this is the start. Depends on the shipped Phase 20 content only.
- **Why it matters:** it plants every clue the next two acts pay off, and it teaches the game's core promise: information, not power, is what the nobody gains.

### Act II — CON ĐƯỜNG TU LUYỆN (layers 2–3)

- **Narrative purpose (EXISTING CANON):** what path am I cultivating, and who taught me? A sect, a rivalry.
- **Player's main goal (C2 PROPOSAL):** choose a cultivation path and earn a sect affiliation (C-003: joining is earned, an Act-II decision made with enough information to matter) — while following the survey thread into the shaft.
- **Central conflict:** the sealed door vs. the evidence that the shaft was worked. The outpost says "sealed since winter"; the wax is fresh, the ruts reach the sill, the lock takes a surveyor's rod (K-10). Opposing interests: institutional convenience (keep the seal story) vs. the player's need to know what was taken and by whom.
- **Principal location/social context:** the sect world opens — Thanh Vân Tông becomes reachable; the frontier outpost's authority thins with distance.
- **What changes in the world:** the player enters the Survey Shaft (Phase 21 content, when implemented); the field book is recovered; the "what was taken" question is answered as evidence (K-07), not as a confession; the material (unsurveyed qi-dense stone, K-11) is identified — but the buyer is NOT (layer 3).
- **Cultivation significance:** the cultivation paths (CHÍNH ĐẠO / TÁN TU / CẤM PHÁP / THỂ TU / THẦN TU / PHÁP TU) become real choices with costs; layer 7 (ĐẠO CƠ — the personal Dao, build-defining) is on the horizon as the act's long-term cultivation goal. Sect training opens the sect-technique track (§11).
- **New clues (C2 PROPOSAL, P-series proposed IDs):** P-01 (the field book's last entry is dated after the "sealed since winter" claim); P-02 (a second rod — who else had one?); P-03 (the shaft's worked faces match the Night's vein-light).
- **Existing clues advanced/paid:** K-02 (field book — PAID by Phase 21); K-05 (the rest of the survey — PAID); K-06 (the fourth point is the shaft — PAID); K-07 (what was taken — PAID as evidence; WHO bought it stays layer 3); K-10 (the door opens — PAID); K-11 (the material — PAID; the buyer stays layer 3); K-13 (who stands at the door — PAID, never gated entry); K-09 (advanced — the removed line now has a physical context).
- **Mysteries withheld:** who bought the material (layer 3); what the Night's creatures were (K-03 → Phase 22); the full meaning of the falsified survey (layer 3, §4).
- **Reveal layers:** 2 for the shaft's contents; the act ends at the edge of layer 3 (a sect knows more than it admits).
- **Main choices and consequences (C2 PROPOSAL):**
  - Sect affiliation: Thanh Vân Tông (earned through the examination/allocation logic) vs. the tán tu road (no sect) vs. deferral. Each changes training access, technique track, faction exposure, and obligations — not raw power (see §11 guardrails).
  - Faction first contact: the player meets all three Thanh Vân factions' recruiters but belongs to none; early standing moves are small, observable, and reversible.
  - The shaft's field book: what the player does with it (hand to the sect, keep, show the outpost elder) is a personal-story decision with social-state consequences — it does not rewrite the world chronicle for other players (§17).
- **Shared macro-canon:** the shaft was entered; the field book exists; the material was unsurveyed qi-dense stone; the buyer is unknown.
- **May vary:** sect choice; faction leanings; who stood at the door; what was done with the book; cultivation path.
- **Prerequisites:** H21-14 closed (owner playtest); Phase 21 implemented. Design dependency: Q-01 (kept/told definitions) resolved.
- **Why it matters:** it converts Act I's questions into evidence, makes the affiliation decision the act's backbone, and delivers the "orthodox records are edited" beat that powers Acts VI–VII — without naming the buyer.

### Act III — QUYỀN LỰC (layer 3)

- **Narrative purpose (EXISTING CANON):** who really decides things? Sect politics, region.
- **Player's main goal (C2 PROPOSAL):** navigate Thanh Vân Tông's three-faction fight as a junior member whose shaft evidence is now a political object.
- **Central conflict:** the Cloud Terrace's allocation order vs. Khai Lộ's reform push vs. Biên Vân's frontier expeditions — with the player's field book as a token each faction wants framed differently. The sect "knows more than it admits" (layer 3): the falsified survey (§4) surfaces; the Vân Hải buyer is identified at layer 3 (K-07/K-11 owed payoff).
- **Principal location/social context:** Thanh Vân Tông's terrace, examination halls, and the frontier it argues about.
- **What changes in the world:** the post-boss world consequence lands (Phase 22, when implemented): the outpost can no longer say the shaft was sealed (K-04 PAID); the elder's word against the fresh wax resolves against him (K-08 PAID). Faction influence shifts measurably (deterministic rules: `influence_share`, `dominant_faction_of`, `is_contested`).
- **Cultivation significance:** Tiên Thiên becomes reachable — "a *real* cultivator; sects compete for you." Realm now gates authority: the player's voice in sect politics is a realm-gated capability, not a level number.
- **New clues (C2 PROPOSAL, P-series):** P-04 (the buyer's ledger references a covenant-allocation dispute); P-05 (the elder's appointment letter predates the Night).
- **Existing clues advanced/paid:** K-03 (PAID by Phase 22's boss — what the over-drawn vein made of the thing nearest it); K-04 (PAID — the consequence); K-08 (PAID — the consequence); K-07/K-11 buyer identity (PAID at layer 3, per the ledger).
- **Mysteries withheld:** why the records were falsified *as a system* (layer 4: records contradict each other); everything about the Thiên Khế.
- **Reveal layers:** 3.
- **Main choices and consequences (C2 PROPOSAL):** faction alignment hardens — the player takes a side as a gameplay act (D-042), which moves influence and closes some doors while opening others; the Biên Vân swing-vote position makes the player's choice genuinely move the sect's contested state. Cross-faction cooperation remains possible but costly.
- **Shared macro-canon:** the shaft's worked state is undeniable; the buyer was a Vân Hải trading interest; the sect's allocation fight is public.
- **May vary:** faction side; whether the player exposed or shielded the elder; buyer-handling (expose, leverage, ignore).
- **Prerequisites:** Phase 22 implemented; faction influence rules (already shipped, deterministic).
- **Why it matters:** it pays the Act I–II clue debt in full, converts evidence into politics, and hands the saga its layer-4 engine: if *these* records were edited, which others were?

### Act IV — NGŨ VỰC (layer 4)

- **Narrative purpose (EXISTING CANON):** the world is larger and its records do not agree. The Main World.
- **Player's main goal (C2 PROPOSAL):** follow the falsified survey's implications outward — different vực keep different records of the same events.
- **Central conflict:** regional record-keepers vs. each other; the player's sect affiliation colors which archives open and which close.
- **What changes:** the five vực gain distinct material and political character (regional identity is mandatory per the economy design); the suppressed-survey thread widens from one shaft to a pattern.
- **Cultivation significance:** Ngự Thiên on the horizon — "a regional power; the covenant must account for you."
- **Clue movement (C2 PROPOSAL):** P-06 (two vực' survey archives disagree on the same expedition); K-12 Origin callbacks begin resolving toward the Thiên Khế question (per §6 of the master plan).
- **Withheld:** the Thiên Khế's authorship (CL-15); why Hoang Vực veins fail now (CL-15).
- **Layers:** 4. **Choices:** which region's records to trust first; which sect relationships to spend. **Varies:** regional allies, archive access. **Prerequisites:** the Act III payoff must have landed — the player must have *seen* one falsification before doubting records in general (causal discipline: no layer-4 doubt without layer-3 evidence).

### Act V — NGOẠI GIỚI (layer 5)

- **Narrative purpose (EXISTING CANON):** cultivation itself could have been done differently. The first Tiểu Giới.
- **Player's main goal (C2 PROPOSAL):** survive a world that remembers a different version of cultivation's history — and decide what that does to the player's own path.
- **Central conflict:** the Tiểu Giới's cultivation tradition vs. the Main World's covenant orthodoxy; neither is presented as the "true" one (C-005 discipline: no good-sect/bad-sect thinking applied to worlds).
- **What changes:** the player encounters a working alternative to the realm ladder's assumptions — not a replacement ladder (canon hierarchy stands), but proof that the ladder's *interpretation* is contingent.
- **Cultivation significance:** layer 7 (ĐẠO CƠ) should by now be behind or imminent for the progressing player — the personal Dao forms here, informed by having seen cultivation done differently.
- **Clue movement:** P-07 (the Tiểu Giới's damaged record of the Thiên Khế's signing); layer 5 = different worlds remember different versions.
- **Withheld:** the Thiên Khế's truth (layer 7); the historical Tà Đế's truth (layer 8). **Layers:** 5.

### Act VI — VẾT TÍCH TÀ ĐẾ (layer 6)

- **Narrative purpose (EXISTING CANON):** who was erased, and by whom? History.
- **Player's main goal (C2 PROPOSAL):** reconstruct the erased figure from three contradictory records (Orthodox struck-out name = tyrant; Heterodox Khai Mạch Nhân = liberator; Neutral Hạ Vô Tướng, records edited afterwards — CL-07), knowing the player is NOT their reincarnation or heir.
- **Central conflict:** the institutions that benefit from the erasure vs. the evidence of it; the player's sect faction alignment determines which archives and witnesses are reachable.
- **What changes:** the suppressed-survey thread (Acts I–III) is revealed as one instance of a general institutional practice — "edited for institutional convenience" becomes a historical thesis, not just a shaft story.
- **Cultivation significance:** Cấm Pháp's true cost becomes legible as history, not just mechanics — the forbidden path's "permanent, visible, mechanical price" has a historical face.
- **Withheld:** the Thiên Khế's truth (layer 7 — next act); CL-15 (what Hạ Vô Tướng actually did at the veins stays open). **Layers:** 6.

### Act VII — THIÊN KHẾ (layer 7)

- **Narrative purpose (EXISTING CANON):** preserve, reform, destroy, or replace the covenant?
- **Player's main goal (C2 PROPOSAL):** the saga's central decision — now informed by six acts of evidence about what the covenant rations, who it serves, and what it costs. This is the act the whole suppressed-survey thread was built to serve.
- **Central conflict:** the four covenant positions, each defensible (C-005 discipline at the largest scale): preservation (Vân Đài's logic writ large), reform (Khai Lộ's), exit/frontier (Biên Vân's), and the heterodox critique (Xích Diễm's canonical doctrine: "the Thiên Khế rations cultivation to preserve the institutions that administer it").
- **What changes:** the player's stance becomes world-chronicle state (per shard) — the first act whose outcome is allowed to touch the shared chronicle, because the covenant is definitionally shared.
- **Cultivation significance:** Trọng Thiên approaches — "a world-scale actor; politics is now between peers."
- **Withheld:** the historical Tà Đế's truth (layer 8); CL-15 (who authored the Thiên Khế stays open — the act asks what to *do* with it, not who *made* it). **Layers:** 7.

### Act VIII — TRỌNG THIÊN (layer 8)

- **Narrative purpose (EXISTING CANON):** what does power at this scale owe anyone? World law.
- **Player's main goal (C2 PROPOSAL):** live with the Act VII decision at world scale — power stops being the cheap option (a Trọng Thiên actor who solves everything by violence provokes a coalition, per SOCIAL_DESIGN §8).
- **What changes:** the consequences of the covenant stance propagate through faction influence, regional politics, and world state.
- **Withheld:** the meaning of "Tà Đế" (layer 9 — the player has filled the word in by now; the question is what it means). **Layers:** 8.

### Act IX — TÀ ĐẾ (layer 9)

- **Narrative purpose (EXISTING CANON):** "what does Tà Đế mean?" — deliberately not "who"; by now the player knows who, and the open question is what the word means now that they have filled it in.
- **Player's main goal (C2 PROPOSAL):** answer the identity question the saga has been asking since Act I — with nine acts of history as the evidence. No morality bar; identity derived from history.
- **What changes:** the player's derived identity becomes the lens for the endgame; faction and sect relationships resolve along the lines the player actually walked.
- **Withheld:** CL-15 — permanently open, past layer 9, never closed. **Layers:** 9.

### Act X — ENDGAME (layer 9)

- **Narrative purpose (EXISTING CANON):** what world did I actually leave behind? Accumulated world.
- **Player's main goal (C2 PROPOSAL):** see the durable consequences — the chronicle, the sects, the regions, the people — as the sum of the player's acts, not as a reward screen.
- **What changes:** the world-chronicle records the act outcomes per the state model; personal threads (K-12 Origin callbacks) resolve into the Thiên Khế question per §6.
- **Durable consequence (C2 PROPOSAL discipline):** the endgame is a playable state of the changed world, not a cinematic — the player's sect, faction, relationships, and knowledge persist as the world's new starting conditions for whatever the live game does next.

### Saga integrity self-check (C2.12.A)

- Ten acts preserved with frozen titles/order/purpose: yes.
- Nine-layer ladder preserved, strictly ordered, no early reveals: yes — the buyer stays layer 3 (§7 Act III), CL-15 stays past 9.
- CL-15 never closed: yes — Acts VI–IX explicitly withhold each CL-15 item.
- Frozen four-way split preserved: yes — §17 classifies every major beat.
- C1 six-scope model not promoted: yes — §6.2, §17 use the frozen split.
- Vân Hải buyer not identified at layer 2: yes — material at layer 2 (Act II), buyer at layer 3 (Act III).
- K-03/K-04 meanings preserved: yes — §8 keeps the ledger's definitions verbatim.
- Shaft interior not treated as authored: yes — §15 defines entry only.
- Phase 22 boss not defined: yes — §16 defines purpose only.

---

## 8. Clue-to-payoff ledger

Authority note: clue IDs K-01–K-13, their planted meanings, and owed payoff layers are EXISTING CANON (`NARRATIVE_MASTER_PLAN.md` §9a — "the ONE place it is kept"). This section presents them with the required columns; it changes no meaning, no ID, and no layer. Ledger discipline (EXISTING CANON): "A clue the player can hold is a promise." "A clue with no owed payoff is not allowed to ship." "No phase may pay above the layer it is allowed."

Fairness rule applied to every major clue (C2 PROPOSAL, operationalizing §9a for text-skimmers): each clue carries at least one **non-prose signal** — a changed world state, object, NPC behavior, chronicle entry, faction reaction, or gameplay affordance — so a player who skips optional dialogue can still observe the clue's existence and its payoff.

### 8.1 Canon clues K-01–K-13

**K-01 — the woods' vein "does not run quietly"** | EXISTING CANON | Planted P12 (the Lạc Hà stele, `know_lac_ha_stele_record`) | Layer 1 | **PAID** — Đêm Vỡ Mạch itself (Phase 20, beat 7). No further action.

**K-02 — Lâm Nguyệt's readings do not match the hall's** | EXISTING CANON | Encountered: Phase 20, her confidence; held as `flag_lam_settled` (1 kept / 2 told) | First inference: she is either wrong or lying | Alternatives: the hall's instruments are wrong; both are right about different things | Next evidence: the shaft's field book (Phase 21) | Layer 2 | Act I→II | Status: OPEN — introduced | Payoff: the field book shows who was drawing on the vein, as evidence | Consequence: the kept/told choice colors her trust arc and who stands at the door (K-13) | Premature-reveal risk: low — the book confirms *method*, not *buyer* | Non-prose signal: her behavior toward the player changes visibly after the choice (CONTENT_BIBLE §16: different greeting for keeper vs. teller) | Source: NARRATIVE_MASTER_PLAN §9a

**K-03 — the creatures of the Night are not themselves** | EXISTING CANON | Encountered: Phase 20 / D-073 — the wave's look, the vein's light; held as seen, no knowledge entry | First inference: the Night corrupts | Alternatives: the creatures were always like this at night; the vein-light deceives | Next evidence: the shaft's boss (Phase 22) | Layer 1→2 | Act I→III | Status: OPEN — introduced | Payoff: what the over-drawn vein made of the thing nearest it | Consequence: reframes the Night from "monster attack" to "extraction damage" — the saga's first proof that the vein is a victim, not a weapon | Premature-reveal risk: medium — any Phase 21 text that calls the creatures "corrupted by drawing" pays K-03 a phase early; Phase 21 must show the *shaft*, not explain the *creatures* | Non-prose signal: the boss's visual design (Phase 22) must rhyme with the Night wave's look — recognition without exposition | Source: NARRATIVE_MASTER_PLAN §9a

**K-04 — the outpost puts away what was found after the Night** | EXISTING CANON | Encountered: Phase 20, the elder's account (beat 9); held as `flag_heard_elder_account` | First inference: the outpost is hiding something | Alternatives: standard post-disaster procedure; the elder protects the village from panic | Next evidence: the shaft's post-boss world consequence (Phase 22) | Layer 3 | Act I→III | Status: OPEN — introduced | Payoff: the outpost can no longer say the shaft was sealed; behind it, the falsified survey of §4 | Consequence: the elder's authority breaks publicly; faction influence shifts; the "edited for institutional convenience" thesis becomes actionable | Premature-reveal risk: high — the consequence must be *observable* (villagers behave differently, the seal story is contradicted by the open shaft), not a dialogue line claiming it | Non-prose signal: the shaft door stands open in the world; the elder's greet lines change; outpost NPCs reference the exposure | Source: NARRATIVE_MASTER_PLAN §9a

**K-05 — one torn page of the Terrace's survey** | EXISTING CANON | Encountered: Phase 20, under the weighted stone (beat 11); held as `know_survey_fragment` | First inference: a surveyor was here | Alternatives: the page is a plant; the survey is unrelated to the Night | Next evidence: the rest of the survey — the field book (Phase 21) | Layer 2 | Act I→II | Status: OPEN — introduced | Payoff: the field book completes the fragment | Consequence: the survey becomes a line the player can walk (K-06) | Premature-reveal risk: low | Non-prose signal: the fragment is a physical inventory item with a surveyor's hand the player can compare against the book | Source: NARRATIVE_MASTER_PLAN §9a

**K-06 — a survey is a line of four stakes; this is the old surveyor's hand** | EXISTING CANON | Encountered: D-073 — showing the sheet to Lâm Nguyệt; held as `know_surveyors_line` | First inference: the survey measured the vein | Alternatives: it measured something else (ore, water) | Next evidence: the fourth point is the shaft; his book is where he measured (Phase 21) | Layer 2 | Act I→II | Status: OPEN — introduced | Payoff: walking the line ends at the shaft door | Consequence: the shaft is no longer "a sealed door in the rocks" but "the fourth point of a measured line" — investigation becomes geometry, not rumor | Premature-reveal risk: low | Non-prose signal: the three stake positions are visible in the world; the socket where the third was pulled (K-09) is examinable | Source: NARRATIVE_MASTER_PLAN §9a

**K-07 — carts went up the track on nights the scout was paid to sleep** | EXISTING CANON | Encountered: D-073 — showing the sheet to Kha Thản; held as `know_night_wheels` | First inference: someone hauled something out at night | Alternatives: legitimate night transport; the scout lies | Next evidence: what was taken out (Phase 21, evidence not confession); WHO bought it is §4 ACTORS 2 and layer 3 | Layer 2 (what) / 3 (who) | Act I→III | Status: OPEN — introduced | Payoff: the material identified in the shaft (Phase 21); the buyer identified at layer 3 (Act III) | Consequence: the "what" makes the extraction concrete; the "who" makes it political — the two payoffs must not collapse into one scene | Premature-reveal risk: **critical** — naming the Vân Hải buyer in any Phase 21 content violates the ladder; Phase 21 shows *material*, never *ledger* | Non-prose signal: the cart track, the wreck (K-11), the pale vein-stone in split crates — all observable without dialogue | Source: NARRATIVE_MASTER_PLAN §9a

**K-08 — the elder says no such page was written and the shaft is sealed** | EXISTING CANON | Encountered: D-073 — showing the sheet to the elder; held as `know_shaft_claim` | First inference: the elder lies | Alternatives: the elder is mistaken; the page is forged | Next evidence: his word against the fresh wax on the door (Phase 22's post-boss consequence) | Layer 3 | Act I→III | Status: OPEN — introduced | Payoff: the open, worked shaft contradicts him in public | Consequence: pairs with K-04 — the elder's account and the outpost's suppression fall together | Premature-reveal risk: medium — the contradiction must be *witnessed* (door open, wax fresh), not merely asserted | Non-prose signal: the elder's claim is a chronicle entry the player can re-read against the open door | Source: NARRATIVE_MASTER_PLAN §9a

**K-09 — the third stake was pulled and the ground raked** | EXISTING CANON | Encountered: D-073 — the socket in the clearing; held as `know_stake_socket` | First inference: someone removed the survey line deliberately | Alternatives: animals, erosion, the Night itself | Next evidence: the line was removed on purpose — physical evidence for K-04 (Phase 21–22, with K-04) | Layer 2 | Act I→III | Status: OPEN — introduced | Payoff: the raked ground + the shaft's worked state = suppression, not accident | Consequence: turns K-04 from suspicion into a physical case | Premature-reveal risk: low | Non-prose signal: the socket and raked ground are examinable world objects | Source: NARRATIVE_MASTER_PLAN §9a

**K-10 — the "sealed" shaft: fresh wax, ruts to the sill, a lock that takes a surveyor's rod** | EXISTING CANON | Encountered: D-073 — the door in the NE rocks; held as `know_sealed_shaft` | First inference: the seal is recent and the shaft was worked | Alternatives: maintenance; a different surveyor | Next evidence: the door opens (rod, never a level); the shaft was worked (Phase 21) | Layer 2 | Act I→II | Status: OPEN — introduced | Payoff: entry — the lock takes the rod, and the interior confirms work | Consequence: the central gate of Phase 21; the "legible before passable" exemplar (MAP_DUNGEON_DESIGN §3) | Premature-reveal risk: low — but the door must *say what key it takes* before it opens | Non-prose signal: the door itself — wax, ruts, rod-shaped lock — is the whole clue, readable at a glance | Source: NARRATIVE_MASTER_PLAN §9a; CANON_LEDGER CL-11

**K-11 — the carter's cart, wrecked, with pale vein-stone in its split crates** | EXISTING CANON | Encountered: D-073 — the wreck in the woods; seen; the Thunder-Finger manual spilled from it | First inference: someone hauled vein-stone and crashed | Alternatives: the stone is natural; the wreck is old | Next evidence: unsurveyed qi-dense material was being hauled out — the buyer is layer 3 | Layer 2 (material) / 3 (buyer) | Act I→III | Status: OPEN — introduced | Payoff: Phase 21 (the material); layer 3 per §9 (the buyer) | Consequence: the material gives K-07's "what" a physical form; the manual is a cultivation-technique hook (Thunder-Finger) independent of the mystery | Premature-reveal risk: **critical** — same as K-07: material yes, buyer no | Non-prose signal: the wreck, the pale stone, the spilled manual — a complete wordless scene | Source: NARRATIVE_MASTER_PLAN §9a

**K-12 — each Origin's own problem, and the one thing only that Origin notices on the trail** | EXISTING CANON | Encountered: Phase 20 vignette; D-073 five Origin observations; held as `OriginData.observation_flags` | First inference: varies by Origin | Alternatives: — (personal by design) | Next evidence: §6 — each Origin's long-term callback; every personal thread resolves into the Thiên Khế question | Layer 2 | Act I→X | Status: OPEN — introduced | Payoff: per Origin, per §6 | Consequence: the personal spine of the saga; the 15–30% variation engine (§18) | Premature-reveal risk: low — personal by construction, never shared (§17) | Non-prose signal: the observation is a world detail only that Origin's vignette flags — e.g., a mark, a sound, a absence | Source: NARRATIVE_MASTER_PLAN §9a

**K-13 — who saw the sheet first** | EXISTING CANON | Encountered: D-073 — `choice_sheet_shown` (lin / ko / shen); held as the choice's record + one knowledge each | Layer: — (the ledger's layer column shows "—") | Act I→II | Status: OPEN — introduced | Payoff: who stands with the player at the door (Phase 21) | Consequence: determines companionship and information flow at entry — **must never gate entry** (ledger constraint) | Premature-reveal risk: n/a | Non-prose signal: the chosen NPC is physically present at the door | Source: NARRATIVE_MASTER_PLAN §9a

### 8.2 Proposed new clues (P-series — C2 PROPOSAL, not canon)

New clues use P-series IDs so they can never collide with the K-series. None is canon until accepted.

| ID | Clue | Planted | Layer | Owed payoff | Owner (proposed) |
|---|---|---|---|---|---|
| P-01 | the field book's last entry is dated after the "sealed since winter" claim | Phase 21 (proposed) | 2 | the seal story's timeline breaks | Phase 21 |
| P-02 | a second surveyor's rod exists — who else had one? | Phase 21 (proposed) | 2–3 | the rod's provenance; a second actor in the shaft | Phase 21 (existence) / Act III (owner) |
| P-03 | the shaft's worked faces match the Night's vein-light | Phase 21 (proposed) | 2 | the shaft and the Night share a cause | Phase 21 |
| P-04 | the buyer's ledger references a covenant-allocation dispute | Act III (proposed) | 3 | the purchase was policy, not opportunism | Act III content |
| P-05 | the elder's appointment letter predates the Night | Act III (proposed) | 3 | the suppression was prepared, not improvised | Act III content |
| P-06 | two vực' survey archives disagree on the same expedition | Act IV (proposed) | 4 | the falsification pattern generalizes | Act IV content |
| P-07 | the Tiểu Giới's damaged record of the Thiên Khế's signing | Act V (proposed) | 5 | the covenant's history has another witness | Act V content |

Each P-clue follows the ledger discipline: it ships only with a named owed payoff, an owning phase, and a non-prose signal (to be authored with the clue).

### 8.3 Continuity checks (C2.12.A)

1. Phase 21 advances the Survey Shaft mystery without revealing the Vân Hải buyer at layer 2: **held** — K-07/K-11 pay "what" in Phase 21; "who" is Act III / layer 3 only. Any Phase 21 content naming a buyer fails this check.
2. Layer 3 retains the buyer revelation: **held** — Act III pays K-07/K-11 (who).
3. Phase 21 respects the survey line, the sealed door, the rods, and what was removed: **held** — K-05/K-06/K-09/K-10 are the entry chain (§15).
4. Phase 22's post-boss consequence serves K-04 and K-03: **held** — §16 defines the consequence as exactly those payoffs.
5. CL-15 stays beyond layer 9: **held** — no P-clue touches a CL-15 question.
6. No clue is paid by an explanatory paragraph: **held** — every payoff names an observable event, object, choice, or world-state change.

---

## 9. Sect atlas: Thanh Vân Tông

Authority note: the sect's existence, its three factions' names/goals/relationships, the 45/38/31 influence shape, and "the player belongs to no faction" are EXISTING CANON (`WORLD_BIBLE.md` §8; `CANON_LEDGER.md` CL-17). Quoted canon is marked; everything else is C2 PROPOSAL.

### 9.1 Sect-level overview

- **Public doctrine and self-image (EXISTING CANON):** the orthodox sect that administers the covenant's allocation through examination. Its self-image: the reason there is still a sect to belong to — the ceiling is the price of not repeating the catastrophe.
- **Actual institutional incentives (C2 PROPOSAL, consistent with canon):** control of vein allocation is control of who cultivates; the examination system converts that control into legitimacy. The sect's primary institutional incentive is *stability of the allocation order* — every faction agrees the covenant matters; they disagree on what it requires.
- **Current strategic goals (C2 PROPOSAL):** hold the allocation system together through the post-Night scrutiny; decide what the survey falsification means before outsiders decide it for them; keep the frontier (Hoang Vực) question from splitting the sect.
- **Resources and constraints:** allocated veins, the examination apparatus, elder authority, frontier expedition funding. Constraints: the covenant itself (it cannot simply take more without re-reading the covenant); the contested internal influence (45 vs 38, Biên Vân holding the balance); the player's field book as an uncontrolled political object.
- **Relationships:** the orthodox reference sect; rival in doctrine to Xích Diễm Tông's heterodox critique; transactional with trading interests (layer 3 reveals how transactional).
- **What it knows / suspects / withholds (C2 PROPOSAL):** the leadership knows the survey was falsified (layer 3); suspects the frontier expeditions will force a covenant re-reading; withholds the full allocation records from junior disciples.
- **Treatment of people:** disciples are allocated, examined, and ranked — the sect is a bureaucracy of cultivation. Outsiders are processed through the same examination logic. Higher-realm members are heard; lower-realm members are managed. (Consistent with SOCIAL_DESIGN §8: realm gates authority.)
- **Saga role:** Acts I–III home ground and political arena; Acts IV–V the institution whose records are doubted; Acts VI–VIII one of the four covenant positions; Acts IX–X the sect the player either reforms, leaves, or inherits influence in.
- **Objective truth vs. sect belief (C2 PROPOSAL):** objectively, the allocation is a rationing system with real catastrophe-avoidance history *and* real institutional self-interest; the sect believes — in all three factions — that the covenant is the frame within which the argument happens. No faction proposes leaving the covenant's frame in Acts I–III.

### 9.2 Faction atlas (canon preserved)

**Vân Đài — the Cloud Terrace** (`faction_azure_terrace`) · LOYALIST · influence 45 · EXISTING CANON.

- Canon: "The elders who administer the examination. The ceiling is the price of not repeating the catastrophe; the allocation is not a cage, it is the reason there is still a sect to belong to. They are neither fools nor hypocrites: they know exactly what the allocation costs the young and have decided it is the lesser cost." Goals: "keep the covenant reading · keep the examination with the elders."
- **Private objective (C2 PROPOSAL):** contain the survey falsification as an outpost-level embarrassment, not a sect-level practice — the leadership's nightmare is the pattern generalizing (Act IV).
- **Resources/leverage:** the examination, elder authority, the covenant reading itself.
- **Constraints/vulnerabilities:** cannot admit the allocation harms the young without conceding Khai Lộ's premise; the fresh wax on the shaft door is a physical fact examinations cannot grade away.
- **Internal disagreements (C2 PROPOSAL):** younger Terrace administrators who have read the field book and gone quiet — loyalty to the institution vs. loyalty to its stated reasons.
- **Relationship to the protagonist (C2 PROPOSAL):** the faction of order — it offers the player legitimacy, rank, and protection in exchange for discretion about the book. Cooperation: smooth advancement, examination favor. Refusal: cold, correct, institutional — no violence, just closed doors. Exposure: the faction treats exposure as an attack on the sect and responds through the influence system, not through scripted revenge.
- **Observable evidence:** examination schedules, allocation postings, the elders' public readings of the covenant.
- **Acts where its role changes:** Act III (defends the allocation against the buyer's revelation); Act VII (the preservation position).

**Khai Lộ — Open the Road** (`faction_azure_open_road`) · REFORMIST · influence 38 · EXISTING CANON.

- Canon: "They have buried disciples who died of waiting, not of danger. Crucially they are **institutionalists**: they want the allocation re-argued through petition and re-examination, not broken — which is what makes this a quarrel between two defensible readings of one covenant rather than a rebellion against it." Goals: "widen the sect's allocation · re-read the covenant as a floor, not a ceiling."
- **Private objective (C2 PROPOSAL):** use the survey falsification as the evidentiary wedge for re-examination — not to destroy the Terrace, but to force the petition it has been blocking.
- **Resources/leverage:** the waiting disciples themselves (a constituency), petition procedure, moral clarity about the cost of waiting.
- **Constraints/vulnerabilities:** institutionalism is also a leash — they cannot use the player's book recklessly without becoming the rebellion they insist they are not; the Terrace can paint any leak as an attack.
- **Internal disagreements (C2 PROPOSAL):** the impatient young (who want the book published now) vs. the proceduralists (who want it entered as evidence at the right petition).
- **Relationship to the protagonist:** the faction of the player's grievance — it offers meaning ("your waiting was not necessary") in exchange for testimony. Cooperation: the player's evidence becomes a political instrument, with the player's name on it. Refusal: disappointment, not enmity — the faction needs witnesses, not soldiers. Exposure of *their* use of the player: they are embarrassed but not destroyed; institutionalists survive exposure better than loyalists.
- **Observable evidence:** petitions, memorials for disciples who "died of waiting," re-examination campaigns.
- **Acts where its role changes:** Act III (the reform push); Act VII (the reform position).

**Biên Vân — the Frontier Cloud** (`faction_azure_frontier`) · RADICAL · influence 31 · EXISTING CANON.

- Canon: "The third position the disagreement implies but never states: both other sides argue about how the *allocated* veins should be divided, and the Hoang Vực was never allocated. They do not break the covenant; they work a gap in it." Goals: "seek the unallocated veins · fund the frontier expeditions." Declares rivalry with the Cloud Terrace and nothing toward Khai Lộ — "the sect's genuine swing vote."
- **Private objective (C2 PROPOSAL):** make the frontier pay — literally (unallocated veins fund expeditions) and politically (a successful frontier makes the allocation argument moot). The faction's secret: some frontier "expeditions" have already found things the sect has not declared.
- **Resources/leverage:** expedition funding, frontier knowledge, the swing-vote position between 45 and 38.
- **Constraints/vulnerabilities:** the gap in the covenant is a legalism — if the Terrace re-reads the covenant to close it, the frontier becomes poaching; Khai Lộ considers the frontier a distraction from the real fight.
- **Internal disagreements (C2 PROPOSAL):** the surveyors (who want the frontier mapped and declared) vs. the extractors (who want it worked quietly first).
- **Relationship to the protagonist:** the faction of the player's competence — it offers the frontier itself: unallocated veins, real risk, no examination. Cooperation: the player becomes an expedition asset with genuine autonomy. Refusal: indifference — the frontier does not need everyone. Exposure: the most dangerous to expose, because the frontier's undeclared finds are the faction's real vulnerability.
- **Observable evidence:** expedition musters, frontier supply purchases, unallocated-vein rumors.
- **Acts where its role changes:** Act III (courted by both sides); Act IV (the frontier becomes the saga's geography); Act VII (the exit position).

### 9.3 Thanh Vân Tông technique identity (C2 PROPOSAL — structure only, no skill lists)

Per §C2.4.4.A: each joinable sect needs a distinctive skill/technique identity and progression logic, not final numbers.

- **Cultivation philosophy:** the covenant made teachable — cultivation as an administered curriculum: staged, examined, allocated. The sect teaches *reliability*: techniques that work the same way every time, in formation, under the covenant's limits.
- **Distinctive identity:** measured, examination-grade technique — forms with named standards, progression by demonstrated mastery. Intended role: the disciplined generalist — no single overwhelming trick, but no gap in the curriculum either.
- **What members learn that outsiders cannot readily access (C2 PROPOSAL):** the examination forms (allocation-gated technique instruction), formation cultivation (multi-disciple vein work), covenant-law techniques (methods that operate *within* the allocation — the sect's real secret is not power but permission).
- **What remains learnable elsewhere:** the underlying cultivation paths (CHÍNH ĐẠO is a path, not a sect monopoly); combat fundamentals; the Thunder-Finger manual from K-11 is explicitly outside the sect curriculum.
- **Costs/obligations/risks:** the examination schedule (time), the allocation ceiling (the sect's techniques assume the allocation's limits — a member who outgrows the allocation outgrows the curriculum), political visibility (a Terrace-track disciple is watched; a Biên Vân expedition member is deniable but unprotected).
- **Appeal without dominance (guardrail):** the sect is the best place to learn *reliably* and to be *legible* to the orthodox world — it is not the best place to learn quickly, secretly, or originally. A Cấm Pháp practitioner will outpace a Vân Đài disciple and pay for it; a tán tu will be free and unprotected.

---

## 10. Sect atlas: Xích Diễm Tông

Authority note: the sect's existence (heterodox, tier 3, Huyết Mạc Vực — `CANON_LEDGER.md`), its canonical doctrine ("the Thiên Khế rations cultivation to preserve the institutions that administer it; a sect that accepts rationing accepts a ceiling on its disciples' lives" — `CONTRADICTION_REGISTER.md` C-005), and its internal split ("those who pay the price from their own bodies, and those who extract it from others" — `WORLD_BIBLE.md` §8) are EXISTING CANON. The split is **not yet authored as factions** (deliberate, D-042). Every faction name, role, and relationship below is C2 PROPOSAL.

### 10.1 Sect-level overview

- **Public doctrine and self-image (EXISTING CANON per C-005):** the Thiên Khế rations cultivation to preserve the institutions that administer it; a sect that accepts rationing accepts a ceiling on its disciples' lives. Self-image: the honest sect — it says aloud what the orthodox sects price into their allocations.
- **Actual institutional incentives (C2 PROPOSAL):** the doctrine is also a recruitment engine — every disciple the orthodox allocation wastes is a potential Crimson Flame disciple. The sect's incentive is to *be right visibly*: each orthodox excess proves the doctrine.
- **Current strategic goals (C2 PROPOSAL):** survive orthodox pressure without becoming the monster the orthodox record describes; manage the internal split before it becomes a schism; position for the covenant question (Act VII), where the heterodox critique is structurally necessary.
- **Resources and constraints:** heterodox techniques (real, costly), the Huyết Mạc Vực's difficult geography (a defense), a reputation that precedes it (a cost — the orthodox record describes the extractors "as if it were the whole sect," and inside Xích Diễm "that accusation is a live political wound," WORLD_BIBLE §8). Constraint: cannot refute the orthodox record by words — only by the visible conduct of its members.
- **What it knows/suspects/withholds (C2 PROPOSAL):** knows the orthodox allocation's waste firsthand (its disciples are the wasted); suspects the covenant's administration serves administrators; withholds the true cost schedule of its own methods from recruits until they are committed.
- **Treatment of people (C2 PROPOSAL):** the sect is honest about price and ruthless about consent — it tells you what the method costs *you*, then holds you to having chosen it. Outsiders are potential recruits or potential threats, little in between. Higher-realm members are those who paid and survived — authority is scar tissue.
- **Saga role:** Acts I–III the heterodox rumor and the buyer's shadow (never the buyer — the Vân Hải interest is a trading house, not the sect); Acts IV–V the alternative the player can finally visit; Acts VI–VII the necessary critique — the covenant question needs a voice that says "rationing serves the rationers," and only Xích Diễm can say it without being dismissed as ignorant.
- **Objective truth vs. sect belief (C2 PROPOSAL):** objectively, the doctrine's economic claim is largely correct and its methods' costs are real; the sect believes its honesty about price makes it moral — which is exactly the belief the extractor faction hides behind.

### 10.2 Proposed faction structure (C2 PROPOSAL — all names and roles unapproved)

The canonical split — "those who pay the price from their own bodies, and those who extract it from others" — is expanded into two proposed factions. The proposal keeps the wound live: the orthodox accusation *is* true of one faction, which is why it wounds.

**Tự Huyết Nhất Mạch — the Self-Blood Line** · PROPOSAL.

- **Public position:** the sect's conscience — we pay our own price; our scars are our credential.
- **Private objective:** prove the doctrine can be lived without becoming monsters — and thereby seize the sect's moral leadership from the extractors.
- **Core belief/incentive:** the price is the point — a method that costs the practitioner is honest; a method that costs someone else is theft with technique.
- **Resources/leverage:** the sect's most respected veterans (survivors), the recruits the doctrine attracts, the visible proof that the orthodox record is not the whole truth.
- **Constraints/vulnerabilities:** self-payment has a ceiling — there is only so much body and soul to spend; the faction's best people burn out, which the extractors cite as proof of naivety.
- **Internal disagreements:** the ascetics (the price should be *greater* — purity through suffering) vs. the pragmatists (the price should be *sustainable* — the sect needs living veterans, not martyrs).
- **Relationship to the protagonist (C2 PROPOSAL):** the faction that tells the player the full cost schedule *before* asking for commitment — and means it. Cooperation: genuine mentorship, real techniques, real scars. Refusal: respected — the faction's whole identity is consent. Exposure: nothing to expose; the faction's defense is transparency, which is also its recruiting pitch.
- **Observable evidence:** veterans' visible costs; the faction's open cost-posting; its members' willingness to demonstrate methods on themselves.
- **Clues/layers:** connects to the Cấm Pháp cost theme (layer 2+, deepens through Act VI).

**Huyết Thực Nhất Mạch — the Blood-Harvest Line** · PROPOSAL.

- **Public position:** the sect's realists — the world already extracts from the weak; we merely direct the extraction at those who can afford it (a claim that does not survive inspection, which is the point).
- **Private objective:** power without the ceiling — the orthodox allocation rations *them*, so they take unrationed cultivation where they can, and the doctrine's language about price provides cover.
- **Core belief/incentive:** price is for other people — the faction's techniques work, the costs are real, and someone else pays them.
- **Resources/leverage:** the fastest advancement in the sect, money, the fear they inspire (useful against orthodox pressure).
- **Constraints/vulnerabilities:** the orthodox record is *about them* — every extractor excess confirms the accusation that wounds the whole sect; the Self-Blood line watches them with open hostility; their methods create victims who remember.
- **Internal disagreements:** the "taxers" (extraction directed at the deserving — orthodox agents, the rich) vs. the indiscriminate (extraction as such — the faction's accelerating moral collapse).
- **Relationship to the protagonist (C2 PROPOSAL):** the faction that offers the player *speed* — and lies about the price, or tells the truth too late. Cooperation: fast power, faster entanglement; the faction's enemies become the player's. Refusal: noted — the faction does not forgive witnesses. Exposure: the one genuinely dangerous exposure in the atlas — the extractors have the most to lose and the fewest scruples about silencing.
- **Observable evidence:** the mismatch between the faction's claimed targets and its actual victims; wealth without visible cost; the fear in its wake.
- **Clues/layers:** the faction's victims are a layer-3+ evidence trail; its methods rhyme with the Night's extraction damage (K-03) without *being* the Night's cause — a deliberate thematic echo, not a causal link (the proposal does not make Xích Diễm responsible for Đêm Vỡ Mạch).

### 10.3 Xích Diễm Tông technique identity (C2 PROPOSAL — structure only)

- **Cultivation philosophy:** price made explicit — every method states its cost, and the sect's pedagogy is the cost schedule itself. The opposite of the orthodox curriculum: not "what is permitted" but "what will it take from you."
- **Distinctive identity:** high-cost, high-yield heterodox methods — body/soul as fuel, instability as a managed resource. Intended role: the spike — overwhelming short-term capability at compounding long-term price.
- **What members learn that outsiders cannot (C2 PROPOSAL):** the true cost schedules (the orthodox world knows Cấm Pháp exists; only the sect teaches its *management*); scar-tissue techniques (methods that only work on a practitioner who has already paid); the Self-Blood line's sustainable-practice curriculum — the sect's actual treasure, and the reason the split matters.
- **Costs/obligations/risks:** permanent, visible, mechanical price (per the Cấm Pháp design rule — never just "damage ×2"); social cost (the orthodox record, the wound); the extractor faction's attention if the player looks valuable.
- **Appeal without dominance (guardrail):** the sect is the best place to learn *fast* and *honestly-priced* — it is the worst place to learn *safely* or to be *trusted* by the orthodox world. No optimal-play mandate: speed is not victory when the price compounds.

---

## 11. Inter-faction relationship matrix

Authority note: Vân Đài/Khai Lộ/Biên Vân relationships are EXISTING CANON where quoted (WORLD_BIBLE §8). All Xích Diễm rows are C2 PROPOSAL. The Vân Hải trading interest is referenced only as a layer-3 entity per the clue ledger — its identity is not designed here.

| Pair | What each wants from the other | Why it persists despite conflict | What could break it | Observable before understanding | Consequence of change |
|---|---|---|---|---|---|
| Vân Đài ↔ Khai Lộ (CANON: contested 45 vs 38) | Terrace: compliance; Khai Lộ: re-examination | both are covenant institutionalists — the fight is *inside* the frame | the field book going public (forces a binary the procedures can't contain) | petitions answered slowly; examination schedules as political signals | sect ceases to read "contested" — one faction's dominance rewrites allocation |
| Vân Đài ↔ Biên Vân (CANON: declared rivalry) | Terrace: the frontier closed; Biên Vân: the gap left open | the covenant's text genuinely doesn't cover the Hoang Vực — the rivalry is interpretive, not personal | a frontier find too big to be deniable | expedition funding vs. terrace censure in the same season | open schism or a covenant re-reading |
| Khai Lộ ↔ Biên Vân (CANON: nothing declared — open question) | Khai Lộ: frontier witnesses for the petition; Biên Vân: terrace pressure relieved | shared grievance, rejected methods — "left as an open question for gameplay to settle" | the player: the first actor positioned to broker or break them | their recruiters never contradict each other in public | a two-frontier-front against the Terrace — the sect's first realignment |
| Tự Huyết ↔ Huyết Thực (PROPOSAL) | Self-Blood: the extractors restrained; Extractors: the moralists silenced | the doctrine needs both readings to recruit — honesty *and* speed | a victim who can name the extractor line publicly | the sect's internal wound: veterans who won't share a room | schism — the orthodox record becomes true of half the sect |
| Thanh Vân (any) ↔ Xích Diễm (any) (PROPOSAL) | orthodox: containment; heterodox: recruits and vindication | mutual usefulness as the other's cautionary tale | the covenant question (Act VII) forcing a real answer instead of postures | border incidents; defectors' stories | the saga's central debate becomes a relationship instead of a rumor |
| Outpost elder ↔ any sect (PROPOSAL) | elder: the suppression to hold; sects: a quiet frontier | the outpost is small enough to be beneath notice — until the book | K-04/K-08 payoff (Phase 22 consequence) | the elder's account vs. the ground (Act I) | the frontier enters sect politics as evidence |

**Player-positioning note (C2 PROPOSAL):** the matrix is designed so the player's *first* meaningful political act — which faction's recruiter to answer, which the book to show — is taken with partial information and real stakes, and so that no choice is a trick: every faction's offer is genuine on its own terms, and every faction's price is real.

---

## 11A. Player sect affiliation (C2.4.4)

**This entire section is C2 PROPOSAL — NOT CANON until owner approval.** It is the core proposed gameplay direction for the online multiplayer experience and must be explicitly designed, not left implicit.

### A. Distinct sect identity

Joinable options proposed for the saga's span:

1. **Thanh Vân Tông** (EXISTING CANON as a sect; joinability in Act II is C2 PROPOSAL consistent with C-003/SOCIAL_DESIGN §4 "Act-II decision"). Identity: the administered curriculum — reliability, legitimacy, formation cultivation. (§9.3)
2. **Xích Diễm Tông** (EXISTING CANON as a sect; joinability is C2 PROPOSAL, available when the sect becomes reachable — Act IV at earliest, per D-042's "authored in the phase that makes the sect reachable"). Identity: price made explicit — speed, honesty about cost, scar-tissue methods. (§10.3)
3. **Tán tu — the unaffiliated road** (EXISTING CANON as a cultivation path; as the explicit opt-out it is C2 PROPOSAL). Identity: no curriculum, no ceiling, no protection — the player assembles training from knowledge, manuals (e.g., K-11's Thunder-Finger), and faction favors. Its "technique identity" is *combination*: the tán tu learns what others won't teach together.

No further joinable sect is proposed for Acts I–III. Whether the saga needs a third formal sect (e.g., a neutral trading/alliance house) is OPEN QUESTION Q-03 — the proposal's position is that two sects plus the opt-out are sufficient until Act VII's covenant positions demand institutional homes for all four stances.

For each sect, §9.3/§10.3 and the tán-tu paragraph above define: philosophy, distinctive identity, member-only vs. otherwise-learnable content, costs/obligations/risks, rank/reputation-gated access (via the existing roster-authoritative membership, D-015, and relationship-graph standings), and the no-dominance analysis.

### B. Sect-specific skill and cultivation progression

The existing axes are NOT collapsed (EXISTING CANON — PROGRESSION_CULTIVATION_DESIGN §1):

- **Level/XP** stays the smooth-power axis; sect training grants XP like any activity, never gates.
- **Cảnh giới/realm-layer** stays the capability/access axis; sect rank can *recognize* realm (a Tiên Thiên disciple is courted) but cannot *grant* it — breakthrough remains the CultivationService's decision.
- **Knowledge** stays the discrete-id axis; sects are major knowledge *sources* (examination forms, cost schedules) granted through the KnowledgeService, never as private flags.
- **Sect standing** (new axis, C2 PROPOSAL) is *access and obligation*, not power: it unlocks training, facilities, instructors, and faction eligibility; it never adds stats. Rank determines authority and technique access per the existing roster model (D-015).

Technique acquisition (C2 PROPOSAL): sect techniques are obtained by (a) meeting the knowledge prerequisite, (b) holding the rank/standing, (c) paying the training cost (time, resources, obligations), and (d) practice — "techniques are practiced, not purchased." Improvement is use-gated; constraints are the sect's philosophy (a Vân Đài disciple cannot practice extractor methods without breaking standing — the *social* consequence is the constraint, not a code lock).

### C. Sect-specific story questlines

Each joinable sect gets a proposed questline spine (beats, not scripts — no dialogue batches in this task):

**Thanh Vân Tông questline (C2 PROPOSAL):** *The Examination.* Initiation: the allocation examination — the player is measured, not chosen. Early responsibilities: vein-ledger copying, a frontier survey escort (the survey thread, again). Central disagreement: the three factions' recruiters (the player meets all three, joins none yet). Turning points: the field book surfaces inside sect politics (Act III) — which faction the player shows it to first is the questline's first irreversible-feeling choice (reversible only at real influence cost). Secrets/clues: the allocation records (layer 3), the frontier's undeclared finds (Biên Vân thread). Connection to the saga: the questline *is* the Act III political arena. Skimmer-legibility: every beat has a physical token (postings, petitions, expedition musters).

**Xích Diễm Tông questline (C2 PROPOSAL):** *The Cost Schedule.* Initiation: the sect tells the player the price *first* — the initiation is informed consent, played straight. Early responsibilities: a self-blood vigil (witness the price), then a choice of line. Central disagreement: the live wound — Tự Huyết vs. Huyết Thực. Turning points: the first time the player is asked to look away from an extraction; the first victim who names names. Secrets/clues: the true cost schedules (layer 3+), the extractor victim trail. Connection to the saga: the heterodox critique the covenant question (Act VII) requires. Skimmer-legibility: scars are visible; prices are posted; victims are encountered, not described.

**Tán tu questline (C2 PROPOSAL):** *The Unallocated.* No initiation — the absence of one is the point. Early life: manuals, favors, knowledge arbitrage (K-11's Thunder-Finger is the prototype: power without a sect's permission). Central tension: freedom vs. protection — every sect offers a door the tán tu walked past. Turning points: the first time no sect will shelter the player; the first combination no sect teaches. Connection to the saga: the control group — the saga's questions asked without institutional answers.

**State-scope discipline (§17):** questline progress is personal story state (never shared); faction-standing changes are social state (shared); the covenant stance (Act VII) is world-chronicle state (per shard). A player of another sect sees the *consequences* (changed standings, changed NPC behavior) without their own story being rewritten.

### D. Multiplayer fairness and social interaction

Designed for the D-074 direction (server-authoritative production world) without deciding open architecture (C2 PROPOSAL):

- Members of different sects meet in shared-world activities (world events, the frontier, markets) — the world is shared; the *story* is not.
- Sect activities by scope: individual (training, cultivation), party/instance (dungeon runs — the acceptance test: two players at different personal-story points party without their stories forced to match), social (faction influence, sect standing), world-chronicle (the Act VII covenant stance only).
- Cross-sect cooperation: allowed where justified — the Biên Vân expedition that hires a Self-Blood guide is the prototype; cooperation is transactional and observable, not a merged storyline.
- Sect rivalry without mandatory PvP: rivalry plays through influence, access, and economics (allocation vs. frontier; cost schedules vs. curricula) — PvP, if it ever exists, is one lane among several, and this proposal does not design it (backlog, per the C1 proposals' OPEN QUESTION list).
- Another player's quest outcome is represented as *their* story (personal) with *shared* consequences (their faction standing moved; the NPCs they wronged remember them, not you).
- Same-domain-rules in Admin Offline Test Mode: all of the above is domain logic — affiliation, standing, quest state — which runs identically offline; only authority and transport differ (D-074, D-056).

### E. Membership lifecycle and unresolved policy (options, not decisions)

- **When does sect selection become available?** Proposed: Act II, after the examination/information threshold (C-003: "with enough information to matter"). OPEN QUESTION Q-04: the exact trigger (a knowledge id? a story beat?).
- **Can players change/leave/defect later?** Options: (a) free exit, techniques kept, standing reset — favors experimentation, weakens commitment; (b) exit with cost — learned techniques stay (knowledge is permanent, CL-14) but sect-gated *instruction* and facilities are lost, standing becomes a debt edge; (c) defection to a rival — allowed once, with a story questline and permanent relationship consequences. The proposal recommends (b) as the default with (c) as designed content — but this is OPEN QUESTION Q-05.
- **Cross-sect technique learning?** Proposed: limited — manuals and favors (the tán-tu economy) can teach *forms*, but sect *instruction* (correction, progression, the cost schedule) requires standing. OPEN QUESTION Q-06.
- **Initially unavailable sects?** Xích Diễm Tông: yes — unavailable until reachable (D-042). Thanh Vân Tông: available Act II. (C2 PROPOSAL)
- **Additional sects for the long-term vision?** See Q-03 above — none proposed now; the four covenant positions (Act VII) may eventually need institutional homes, which is a later design task, not this one.

### Guardrails (mandatory constraints — each with example and failure case)

1. **No dominant mandatory sect.** *Example:* a speedrunner takes Huyết Thực methods for raw pace; a completionist takes Vân Đài for archive access; a duelist stays tán tu for combination freedom — each is the best answer to a different question. *Failure case avoided:* a sect whose techniques are numerically superior in all situations, making affiliation a solved problem rather than an identity choice.
2. **No superficial sect questlines.** *Example:* the Examination questline's turning point (who sees the field book first) changes faction influence and closes real doors. *Failure case avoided:* three questlines that differ only in NPC names and reward labels.
3. **No accidental shared-world canon fragmentation.** *Example:* the player's covenant stance (Act VII) is world-chronicle state per shard; their kept/told choice is personal and never replicated. *Failure case avoided:* Player A's book-burning erasing Player B's evidence.
4. **One connected saga.** *Example:* the Xích Diễm questline's victim trail feeds the Act VII debate without replacing the ten acts. *Failure case avoided:* a sect storyline that answers a CL-15 question or renumbers the reveal ladder.

### F. Acceptance criteria (self-check)

How a player discovers/qualifies/joins: §11A.A–B. What changes after joining: §11A.B–C. Distinctive training/techniques: §9.3/§10.3. Sect questlines: §11A.C. Connection to saga and ladder: §7 + §11A.C. Effects on progression/relationships/opportunities: §11A.B–D. Coexistence in the shared world: §11A.D + §17. Proposals vs. open questions: labeled throughout (§11A.E; §19).

---

## 12. Cultivation/progression loop

Authority note: the three axes, their rules, and the "never gate on Level" invariant are EXISTING CANON (`PROGRESSION_CULTIVATION_DESIGN.md`, C-002). The loop below is C2 PROPOSAL — a player-facing narrative over those frozen mechanics.

### 12.1 The loop, end to end

1. **Explore or complete activities.** The player works the world: combat, gathering (when implemented), quests, sect duties, investigation. This produces XP (smooth power), materials, and — critically — *information*.
2. **Acquire resources, knowledge, relationships, clues, opportunities.** The loop's real yield is heterogeneous: spirit stones *and* `know_surveyors_line` *and* a faction recruiter's regard *and* the field book. The design treats knowledge and relationships as first-class yields, not flavor.
3. **Evaluate short-term needs vs. long-term advancement.** The meaningful decision: spend stones on pills for tonight's breakthrough attempt, or save for the sect contribution that unlocks the examination forms? Burn a favor with Khai Lộ now, or hold it for the petition? The game must surface both the cost *and* the foregone alternative — "what you give up by spending it" (§13).
4. **Pay the costs and meet the prerequisites.** Cultivation is a transaction with prerequisites: the Knowledge Core for Hậu Thiên entry (frozen D-040), the breakthrough's material and knowledge costs, the sect's standing requirements. Costs are legible *before* payment (see §14).
5. **Experience the resulting power, access, risk, responsibility, or social consequence.** A realm advance answers "what can I do now that I could not before?" with a capability, not a number: a new map layer, a technique family, a sect office, an NPC who now takes the player seriously. Power *always* arrives with a social consequence — the higher the realm, the less violence is the cheap option (SOCIAL_DESIGN §8).
6. **Encounter the next constraint.** The loop's engine: each advance reveals the next gate — a knowledge id the player lacks, a faction standing too low, a price too steep, a record that contradicts. The constraint is never "more of the same number"; it is always a *different kind* of growth (knowledge, technique mastery, realm, relationships — the handoff §15.5 principle: "each from a different kind of growth").

### 12.2 The three axes, kept distinct (EXISTING CANON, restated for the loop)

| Axis | Represents | Unlocks / changes | Why it doesn't replace the others |
|---|---|---|---|
| Level/XP | fine, frequent growth from activity; level is DERIVED, never stored | smooth incremental power; **never gates anything** | generosity with levels feels good; strictness lives elsewhere |
| Cảnh giới (realm/layer) | chunky capability thresholds; PHÀM → HẬU THIÊN 1–9 → …; layer 7 = ĐẠO CƠ (personal Dao, build-defining) | capability and access: maps, techniques, sect rank, NPC reactions, economy | must answer "what can I do now?" with something other than a bigger number |
| Knowledge (Tri Thức) | discrete named ids of learned things; permanent, never consumed, may be superseded | hidden techniques, world gates, dialogue options, sect secrets, recipes, breakthrough prerequisites | without it every lock opens with power; enables "I learned something" as a progression event |

**Loop integration (C2 PROPOSAL):** the saga's acts are tuned to *which axis* each act primarily moves. Act I moves Knowledge (the clue ledger) and XP. Act II moves realm (first breakthroughs) and sect standing. Act III moves Knowledge (layer 3) and social standing. This is a pacing proposal, not a gate — the axes remain independently earnable.

### 12.3 Cultivation narrative integration

- **What progression changes about learning:** realm gates *authority* — higher-realm characters are taught things lower-realm ones are not (the sect curriculum is realm-indexed); Knowledge gates *permission* — the cost schedules, the survey archives, the covenant readings.
- **How factions treat the protagonist:** per the six relationship dimensions (CL-12) — respect moves with realm, trust with history, debt with transactions. A Tiên Thiên nobody is courted; a Hậu Thiên veteran with the field book is *listened to* — different axes, different doors.
- **Advances that create obligations:** sect rank (duties), breakthrough visibility (expectations), knowledge of the suppression (the choice of what to do with it). The proposal's rule: **every capability gain ships with at least one obligation or risk** — power without price is the design failure the Cấm Pháp rule exists to prevent.
- **Knowledge vs. relationships vs. resources vs. power:** the loop's signature trade — the field book can be *spent* (handed to a faction for standing), *kept* (personal knowledge, future leverage), or *published* (world consequence, personal danger). The same object is four different resources depending on the player's choice.
- **Milestones:** early-act (I–III): Hậu Thiên entry, first breakthroughs, ĐẠO CƠ foreshadowed. Deferred: Ngự Thiên+ capability lists (canon: "no ability list" — the proposal does not invent them), Thái/Vô Thiên (narrative purpose only, per canon).

---

## 13. Resource sources, sinks, costs, and risks

Authority note: resource definitions and the sink rule are EXISTING CANON (`ECONOMY_CRAFTING_DESIGN.md`). The matrix below restates them with the C2-required columns; abuse analysis is C2 PROPOSAL.

The one rule (EXISTING CANON): "Every currency and every resource must have at least one real SINK."

| Resource | Purpose | Sources | Sinks | Prerequisites | Scarcity assumption | Tradability / restriction | Supporting rule |
|---|---|---|---|---|---|---|---|
| Linh Thạch | main currency | combat, gathering, quests, trade | cultivation, crafting, contribution, travel, information | none (base) | heavily drained by design | player-held item stack; trade is all-or-nothing exchange, no-arbitrage bound | ECONOMY §1, §8 |
| Đan Dược | cultivation + combat consumable | alchemy, dungeons, quests | burned in use (permanent) | alchemy profession / purchase | burned by design | consumable | ECONOMY §1 |
| Linh Thảo | alchemy input | gathering, world events | alchemy | gathering access | regional (five vực have material character) | tradable | ECONOMY §3, §4 |
| Khoáng Sản | stonecutting/artificing input | gathering, dungeons | processing | gathering access | regional | tradable | ECONOMY §3, §4 |
| Monster materials | crafting input | combat | crafting, recipes | combat capability | scales with threat | tradable | ECONOMY §1 |
| Huyết Tinh | Cấm Pháp methods, heterodox crafting | heterodox sources, Huyết Mạc content | forbidden methods/crafting | heterodox access | deliberately narrow — scarcity is a social signal | black market (proscribed goods, social risk) | ECONOMY §1, §7 |
| Nhân Lực | sect operations | sect-level | sect operations | sect membership | — | **never a player currency** (canon) | ECONOMY §1 |
| Tri Thức | gating key | exploration, records, dialogue, purchase | **none — deliberate exception, never consumed** (CL-14) | varies per id | permanent by design | not a currency; granted via KnowledgeService only | ECONOMY §1; CL-14 |

**What the player gives up / what happens when lacking (C2 PROPOSAL):** spending stones on a breakthrough means forgoing the sect contribution that would have unlocked the examination forms — the game surfaces the foregone alternative at the decision point (§14). Lacking pills means attempting the breakthrough unassisted (higher risk, not a hard block — "grind is optional depth, never a toll gate on the narrative," ECONOMY §9). Lacking a knowledge id means the gate is legible but unopenable — the player knows *what* is missing (a named id), not just "too weak."

**Abuse risks (C2 PROPOSAL):**

- **Farming exploits:** the no-infinite-repeatable-high-yield-loop policy (ECONOMY §8) is the standing defense; the proposal adds that *knowledge-gated* rewards (one-time ids) are inherently farm-proof and should carry the highest-value payoffs.
- **Infinite conversion loops:** conversion has loss by canon (ECONOMY §8); the proposal notes the Huyết Tinh black market needs an explicit loss rate when implemented, or it becomes a money pump with a social-risk fig leaf.
- **Dominant strategies:** the "one sect / one resource" dominance check (§11A guardrails) applies to the economy too — if pills trivialize breakthroughs, the breakthrough *knowledge* prerequisites (not the pill drop rate) are the tuning lever, because numbers are tunable and architecture is frozen.
- **Pointless sinks:** the contribution sink must buy *observable* sect standing movement, or it is a tax — every sink needs a visible meter.
- **Progression dead ends:** the Knowledge Core's Hậu Thiên gate (frozen D-040) is the one hard block in the early game; the proposal requires its prerequisite to be discoverable in-world (a named knowledge id with a known source), never a hidden flag.

**Unresolved economy decisions (OPEN QUESTION):** gathering/profession implementation order; regional market behavior; the contribution sink's exact standing exchange rate (tunable, not canon); travel/information sink pricing.

---

## 14. Player clarity and text-skimmer requirements

No text-skimmer rule exists in the narrative docs under that name (verified across all six narrative sources). This section operationalizes the existing fairness rules — "A clue the player can hold is a promise" and "A clue with no owed payoff is not allowed to ship" (NARRATIVE_MASTER_PLAN §9a) — as C2 PROPOSAL clarity requirements.

**For every major progression gate, the player must be able to discover (C2 PROPOSAL):**

- **What is required:** a named prerequisite (knowledge id, realm, standing threshold, item) — never "come back later."
- **Why it is required:** the in-world reason, observable — the door says what key it takes (the K-10 exemplar).
- **What can be done next:** the next step is always visible, even if it is "find the surveyor's rod" rather than "have the rod."
- **Likely cost/risk:** the price is posted before payment — the Xích Diễm cost-schedule principle generalized.
- **Missing prerequisite vs. insufficient power:** the game distinguishes "you lack `know_sealed_shaft`" from "this is threat-rated Tiên Thiên and you are Hậu Thiên 3" — different problems, different UI, different advice.
- **Gate nature:** permanent (covenant law), temporary (a faction's current stance), social (standing), economic (price), knowledge-based (an id), or combat-based (a threat rating) — each with its own visual language.

**Non-prose signals (C2 PROPOSAL):** every major clue and gate ships with at least one signal from this menu: changed world state (the open door), physical object (the rod, the fragment), environmental discrepancy (fresh wax on an "old" seal), NPC behavior change (greetings that differ for keeper vs. teller), chronicle entry (re-readable evidence), faction reaction (postings, petitions), gameplay affordance (the lock's rod-shaped keyhole). §8 lists each canon clue's signal; P-clues must each name theirs when authored.

**The skimmer contract (C2 PROPOSAL):** a player who reads nothing optional must still be able to (a) find the next gate, (b) understand what kind of key it takes, (c) recognize when a payoff has happened (the world changed, not just the dialogue), and (d) never need to memorize optional text to pass a critical gate. Optional text is for *depth* — motive, history, irony — never for *permission*.

---

## 15. Phase 21 access/entry handoff — design only

Authority note: this section is **not** a Phase 21 implementation plan and is **not** Gate A of the pre-phase-21 hardening workflow. It defines what the future implementation must understand about the Survey Shaft's narrative context and entry conditions. The shaft's interior does not exist in canon (CL-11); nothing here authors it.

### 15.1 Narrative reason to investigate

The protagonist investigates the Survey Shaft because the evidence leaves no other door (C2 PROPOSAL, from the canon clue chain): the torn survey page (K-05) completes into a line of four stakes (K-06); the line's fourth point is the shaft; the shaft's door wears fresh wax and ruts to the sill while the elder says "sealed since winter" (K-10 vs. K-08); carts went up the track on nights the scout was paid to sleep (K-07); the wreck in the woods carried pale vein-stone (K-11). The investigation is not curiosity — it is the only way to answer what was taken from under the village that broke the vein.

### 15.2 Causal chain (canon clues only)

K-05 (fragment) → K-06 (the line; the old surveyor's hand) → K-10 (the fourth point; the door; the rod-shaped lock) → the rod (kept/told route, §15.4) → entry. Parallel thread: K-07 (night wheels) → K-11 (the wreck; the material) → the *motive* for entry (confirm what was hauled). K-09 (the pulled stake) corroborates suppression; K-08 (the elder's claim) is the statement the entry will test.

### 15.3 What the player knows vs. suspects before entering

**Knows (observable, canon):** the door is boarded and sealed but the wax is fresh; ruts reach the sill; the lock takes a surveyor's rod; the survey line points here; carts moved at night; the wreck carried vein-stone.

**Suspects (inference, not fact):** the shaft was worked recently; what was taken fed the Night; the elder's "sealed since winter" is false.

**Does not know (withheld):** who bought the material (layer 3); what the worked interior contains (not canon); what the Night's creatures were (K-03 → Phase 22).

### 15.4 The rods and the kept/told routes

**Canon facts:** the lock takes a surveyor's rod (K-10). Act I variant lines (CONTENT_BIBLE §16): kept → Lâm Nguyệt gives the sheet ("I still have mine. When they are gone, I go down with you."); told → she refuses once, and her rod is in the elder's chest. "The rod is the Phase-21 key in both lives."

**No formal kept/told definition exists** (OPEN QUESTION Q-01). This proposal offers bounded definitions for owner approval:

- **kept** (C2 PROPOSAL): the player kept Lâm Nguyệt's confidence — did not tell the elder her readings. Consequence: she trusts the player with the sheet; the rod comes from her hand, willingly.
- **told** (C2 PROPOSAL): the player told the elder. Consequence: the readings are institutional knowledge; her rod is in the elder's chest — the player must take it (with the elder's permission, by theft, or by the elder's own command — the *method* is the told-route's gameplay, not specified here).

**Route semantics (C2 PROPOSAL):** both routes reach the same door with a rod. They differ in *provenance* (gift vs. taken), *witness* (who stands with the player — interacts with K-13), and *social consequence* (the elder's stance toward the player). Neither route gates entry; neither route reveals the buyer.

### 15.5 Entry handoff table

| Handoff element | Current canon / decision | Proposed Phase 21 requirement | Evidence / source | Player-visible communication | Failure / ambiguity risk | Owner decision required? |
|---|---|---|---|---|---|---|
| The door | boarded, sealed; fresh wax; ruts; rod-lock (CL-11, K-10) | the door states its key before it opens (MAP_DUNGEON_DESIGN §3: legible before passable) | CANON_LEDGER CL-11; NMP §9a K-10 | the rod-shaped lock; `know_sealed_shaft` in the Chronicle | an invisible gate (bug, not mystery) | no |
| The rod | the Phase-21 key in both lives (CONTENT_BIBLE §16) | kept: gift; told: taken (method open) | CONTENT_BIBLE §16 | the handoff scene per route | Q-01 unresolved — define kept/told first | **yes — Q-01** |
| Threat | advisory threat rating in realm vocabulary, never `min_level` (MAP_DUNGEON_DESIGN §3) | telegraphed risk at the sill (e.g. *Phàm · cao*); "enter and die" preferred over "may not enter" | handoff §15.5 design note | realm-vocabulary marker at the door | tuning numbers are not canon — keep them advisory | no |
| Preparation | none required, none checked (handoff §15.5) | whatever the woods taught: knowledge, technique mastery, realm, EXP — each from a different growth kind | handoff §15.5 | the player's own inventory of growth | requiring any one kind = level-gating with extra steps | no |
| Who stands at the door | K-13: `choice_sheet_shown` (lin/ko/shen) | the chosen NPC is present; **must never gate entry** | NMP §9a K-13 | physical presence | gating entry on K-13 violates the ledger | no |
| What must not be revealed | buyer = layer 3 (K-07/K-11) | Phase 21 shows material, never ledger; no buyer name, no buyer faction | NMP §9a; §9 ladder | — | one careless line pays K-07/K-11 early | no (constraint, not decision) |
| Entry state for Phase 21 | — | the implementation receives: route (kept/told), K-13 choice, held knowledge ids, faction standings | §17 state classification | — | personal state leaking into shared state | no |

### 15.6 Access logic and the dungeon principles

The gate is a **layered gate** (MAP_DUNGEON_DESIGN §3, EXISTING CANON): Knowledge (`know_sealed_shaft`, the survey line) + Item (the rod) + Quest/story (the investigation) — with **at least one non-numeric gate** (the rod's provenance and the knowledge chain are non-numeric). Level is never a gate (C-002). The door is legible before passable. The player may enter and die.

Skimmer-legibility: the door's whole clue is visual (wax, ruts, rod-lock); the Chronicle keeps `know_sealed_shaft` re-readable; the threat marker is in realm vocabulary.

### 15.7 Continuity checks for the implementation agent

- Verify CL-11's exact wording before writing any interior content — the interior is not canon until Phase 21 writes it, and Phase 21 has not started.
- Verify K-07/K-11's layer-3 buyer constraint against the live ledger before writing any shaft text.
- Verify the kept/told definitions against Q-01's resolution — do not invent route semantics.
- The field book (K-02/K-05 payoff) is the shaft's narrative payload — its contents must advance the survey thread without naming the buyer.

---

## 16. Phase 22 narrative-purpose handoff — design only

Authority note: this section defines only the narrative *function* of the eventual Phase 22 post-boss content. No boss identity, design, moves, tuning, arena, loot, or scripting is specified — all OUT OF SCOPE.

### 16.1 Inherited narrative pressure

Phase 22 inherits: the shaft entered and its worked state documented (Phase 21); the field book in someone's hands; the elder's "sealed since winter" still officially standing; the Night's creatures still unexplained (K-03); the buyer's identity still at layer 3 (paid in Act III, which Phase 22's consequence enables but does not itself deliver).

### 16.2 The question the outcome must change

*What was the Night?* — from "a monster attack the village survived" to "extraction damage the village was subjected to." The boss is the chapter exam (MAP_DUNGEON_DESIGN §6: a boss tests mechanics introduced earlier in its chapter); its narrative function is to make K-03's payoff *observable*: what the over-drawn vein made of the thing nearest it.

### 16.3 Clue obligations

- **K-03 (EXISTING CANON):** "the creatures of the Night are not themselves" → payoff: "what the over-drawn vein made of the thing nearest it." Phase 22's boss is the payoff vehicle. The boss's design (not specified here) must visually and mechanically rhyme with the Night wave — recognition without exposition (§8.1).
- **K-04 (EXISTING CANON):** "the outpost puts away what was found after the Night" → payoff: "the outpost can no longer say the shaft was sealed." The **post-boss world consequence** is this payoff's vehicle: with the shaft open, worked, and witnessed, the suppression fails in public.
- **K-08 (EXISTING CANON):** "the elder says no such page was written and the shaft is sealed" → payoff: "his word against the fresh wax on the door." Resolved by the same consequence — the door stands open; the wax is fresh; the claim is visibly false.

### 16.4 Observable world consequence (C2 PROPOSAL)

The post-boss world change, stated as observable facts (not dialogue claims):

- The shaft door stands open; its worked state is examinable by anyone who walks up the NE rocks.
- Outpost NPC behavior changes: the suppression is no longer maintainable — guards, the elder's household, and villagers reference the exposure in greetings and routines.
- Faction influence moves: the field book's contents (in whichever faction's hands the player's Act III choice put them) become political facts; the deterministic influence rules (`influence_share`, `dominant_faction_of`, `is_contested`) reflect the shift.
- The elder's authority is broken *as an observable social fact* — his account is contradicted by the world, not by a cutscene line.

**What must persist (narrative terms):** the shaft's open/worked state; the elder's discrediting; the faction influence shift — subject to the authority model (world-chronicle state per shard, §17) and the unresolved persistence implementation (OPEN QUESTION — D-074 explicitly reserves persistence technology).

### 16.5 Effects on subsequent acts

The consequence is Act III's engine: with the suppression publicly failed, the sect-level fight over the survey's meaning (falsified records, the buyer's layer-3 reveal) can begin. Without it, Act III has no public evidence to argue over — the consequence is load-bearing for the saga, not decorative.

### 16.6 What remains unresolved / must not be revealed

- Unresolved: the buyer's identity (paid in Act III content at layer 3, enabled — not delivered — by this consequence); the full meaning of the falsified survey (layer 3–4); all CL-15 questions.
- Must not be revealed: anything above layer 3 — no Thiên Khế truth, no Tà Đế truth, no record-contradiction thesis beyond the single shaft.

### 16.7 Verification duties for the later implementation agent

- Re-read CL-11, K-03, K-04, K-08 against the *live* ledger before building — ledger rows are canon and this proposal does not amend them.
- Confirm H21-14 is closed and Phase 21 was actually implemented — this handoff assumes a shaft that exists.
- Confirm the boss tests the chapter's mechanics (MAP_DUNGEON_DESIGN §6) and produces the post-boss world consequence (CONTENT_BIBLE §12 Boss: the consequence field is required, "rejected unless present").
- Do not pay any clue above its ledger layer to make the boss fight "land."

---

## 17. Shared-world/state-boundary compatibility

Authority note: the frozen four-way split (`NARRATIVE_MASTER_PLAN.md` §14) is EXISTING CANON. The C1 six-scope model is not used here. All classifications below are C2 PROPOSAL applications of the frozen split. Open architecture questions (transport, persistence, cardinality, shards, admin hierarchy) are not decided.

### 17.1 Classification of major story events and clues

| Event / clue | Narrative scope (frozen split) | Why this scope |
|---|---|---|
| kept/told choice; clue *interpretation* | Personal story (per player, never shared) | a player's inference must never rewrite another's; spoiler guards apply |
| Clue *existence* (the door, the wreck, the fragment as world objects) | World chronicle (per world/shard) | the objects are in the shared world; every player can observe them |
| K-13: who stands at the door | Personal (whose run) + Social (the NPC's relationship edge to the player) | companionship is personal; the NPC's regard is a relationship edge |
| The shaft run itself (Phase 21) | Party/instance (temporary per run) | co-op acceptance test: different personal-story points, one run, no forced story match |
| Field book's disposition (who the player shows it to) | Personal (the decision) + Social (faction standing changes) | the choice is yours; the factions' reactions are shared |
| Post-boss consequence (K-04/K-08) | World chronicle (per shard) | the shaft stands open for every player of that shard; the elder's discrediting is a world fact |
| Faction influence shifts | Social (shared) | influence is computed over shared standing edges, deterministically |
| Sect affiliation and rank | Social (shared) | roster-authoritative (D-015); visible to other players |
| Sect questline progress | Personal story | your Examination is not everyone's |
| Act VII covenant stance | World chronicle (per shard) | the covenant is definitionally shared — the one act allowed to touch the chronicle deliberately |
| K-12 Origin callbacks | Personal story | the 15–30% variation engine; never shared |
| Reward grants | Per the Phase-19 reward ledger (authoritative, idempotent) | duplicates silently survivable by design (D-070; C1 R2 correction) |

**Cases where scope cannot be confidently determined (C2 PROPOSAL, flagged):** whether the world chronicle is per-shard-shared or per-group-instantiated (§14 left this open; C1 proposed per-shard). The Phase 22 consequence is designed to read correctly under either: "the shaft stands open" is true in every instantiation the player can visit.

### 17.2 Shared-world fairness (design-level)

- **Observable by all:** world objects (door, wreck, stakes), NPC public behavior, faction postings, the open shaft, market prices, threat markers.
- **Character-specific:** clue interpretations, kept/told, questline progress, Origin observations, personal ledger of promises kept/broken.
- **Faction outcomes without global rewrite:** influence moves through the deterministic rules over shared edges — every player sees the *same* influence shift, but each player's *standing* with the factions is their own edge. The world changes once; relationships change per player.
- **Personal account vs. objective event:** the Chronicle records *what happened* (objective, shared where chronicle-scoped); the player's *account* of what it means is personal. The UI must never present another player's interpretation as world fact.
- **Understandable difference:** when players' personal states differ, the shared world shows the *consequences* (the elder discredited, the book in Khai Lộ's hands) without asserting a single story — other players see what *is*, not what *was meant*.
- **Party/instance sharing:** within a run, the party shares tactical information (positions, threats, loot splits) — never personal story state. The loot split is per the reward ledger; the story each player tells afterward is their own.

### 17.3 Admin Offline Test Mode compatibility

All of the above is domain logic — affiliation, standing, quest state, clue ids — which runs identically offline under the same domain rules (D-074, D-056). Only authority (who validates) and transport differ. No gameplay rule in this proposal works only offline; no rule assumes networking. (C2 PROPOSAL, consistent with ACCEPTED DECISION.)

---

## 18. Replayability and meaningful variation

Target (EXISTING CANON, NARRATIVE_MASTER_PLAN §10): "**Replayability comes from composition, not from forking the campaign:** shared canon + personal Origin + relationship branches + faction branches + sect branches + optional discoveries + convergence. Target: **70–85% shared macro canon, 15–30% meaningful player-specific variation.**"

### 18.1 Stable macro-canon (the 70–85%)

The Night happened; the vein broke; the survey was falsified; the shaft was worked; the buyer was a Vân Hải interest; the outpost's suppression failed; the covenant question stands; the ten acts occur in order; the reveal ladder is never violated. No playthrough changes these.

### 18.2 Meaningful variation (the 15–30%) — each a changed experience, not a dialogue swap

| Variation source | What changes (experience, decision, relationship, access, cost, consequence) |
|---|---|
| Origin (5) | personal problem, trail observation (K-12), long-term callback resolving into the Thiên Khế question |
| kept / told | who trusts the player, how the rod is obtained, the social cost of the elder's knowledge |
| K-13 (who saw the sheet first) | who stands at the door; which knowledge each NPC volunteers |
| Sect affiliation | training access, technique track, faction exposure, obligations, questline |
| Faction side | influence moved, doors closed/opened, the Act VII position's institutional home |
| Field book disposition | which faction weaponizes the evidence; the player's name on it or not |
| Cultivation path | costs paid visibly (Cấm Pháp's price), capabilities gained, social consequences |
| Optional discoveries | P-clues, manuals (Thunder-Finger), archive access — composition, not forking |

### 18.3 What cannot change

Facts (the ledger), the ladder (no layer may move), CL-15 (never closed), the acts' order and questions, the frozen canon. A player's *interpretation* may differ; the *events* do not.

### 18.4 Branching discipline

Branches read state, never scattered booleans (NARRATIVE_DIRECTION §5). Convergence is structural: "Divergence happens *inside* acts; acts themselves converge" — the proposal's variation budget is spent inside acts, never on parallel campaigns.

---

## 19. Open questions and risk register

| ID | Question / risk | Why it matters | Current evidence | Constraints | Options / trade-offs | Blocks | Decided by | Resolving evidence |
|---|---|---|---|---|---|---|---|---|
| Q-01 | Formal kept/told definitions | Phase 21 entry logic depends on route semantics; no canon definition exists | usage only (NMP §9a; CONTENT_BIBLE §16) | must preserve "the rod is the key in both lives"; must never gate entry | adopt §15.4 definitions vs. alternative glosses | Phase 21 readiness | owner | accepted glossary entry |
| Q-02 | Chronicle scope: per-shard shared vs. per-group instantiated | determines what the Phase 22 consequence must replicate | §14 deliberately open; C1 proposed per-shard | frozen text unchanged | decide per-shard (C1) vs. per-group vs. hybrid | Phase 22 planning | owner (+ architecture) | accepted state-model decision |
| Q-03 | Third joinable sect needed? | Act VII's four covenant positions may need institutional homes | two sects + tán tu proposed (§11A) | no invented canon sects without approval | add later vs. never vs. now | neither (Act VII is distant) | owner | covenant-position design |
| Q-04 | Sect-selection trigger | "enough information to matter" needs a concrete gate | C-003; SOCIAL_DESIGN §4 | must be earned, Act II | knowledge id vs. story beat vs. standing threshold | Phase 21 readiness (entry routes interact with K-13) | owner | accepted design |
| Q-05 | Sect switching/exit/defection policy | techniques are permanent knowledge (CL-14); standing is not | D-015 roster model | cannot silently decide irreversibility | free exit / costly exit / once-only defection | Phase 21 readiness | owner | accepted policy |
| Q-06 | Cross-sect technique learning | affects the no-dominance guardrail | manuals exist (K-11 precedent) | instruction vs. forms distinction | forms via favors, instruction via standing | neither | owner | accepted policy |
| Q-07 | Transport, persistence, account↔character, shard transfer, admin hierarchy | any shared-world implementation needs them eventually | D-074 explicitly reserves all five | C2 decides none | — | neither (design only) | owner (+ phases 32–34) | architecture decisions |
| Q-08 | GAME_DESIGN_FREEZE amendment | frozen "Offline is the source of truth. No networking in Stage 1." stands alongside D-074 | D-074 consequence names it as required follow-up | freeze's own change control | amend now vs. at the multiplayer phases | neither for design; blocks code-phase clarity | owner | amended freeze text |
| Q-09 | "Stage 1" phase range | proposals must state which side of Stage 1/2 they sit on | never pinned; MP phases are 32–34 | — | pin the range | neither | owner | roadmap entry |
| R-01 | Misreading D-074 as approving the C1 proposals' contents | builders acting on unapproved architecture | D-074: proposals "remain PROPOSAL — NOT FROZEN" | — | — | neither (awareness) | — | owner statement if ambiguous |
| R-02 | D-074 vs. frozen offline-first text confusing future readers | every new reader hits the contradiction | §6.1 records the tension | freeze wins on Stage-1 code; direction wins on target | see Q-08 | neither for design | owner | Q-08 |
| R-03 | Vân Hải buyer revealed at layer 2 | ladder violation collapses the Act III engine | K-07/K-11 ledger rows | Phase 21 content review must check every shaft line | — | Phase 21 readiness | content review | ladder audit of Phase 21 content |
| R-04 | H21-14 never performed | Phase 21 would build on an unfelt opening | handoff §17.6 | agent cannot substitute | — | **Phase 21 entry** | the owner, by playing | written playtest record |
| R-05 | B2-01 debt items assumed to block Phase 21 | over-gating delays the phase; under-gating ships debt | handoff §18.5 | classify by gate protocol, not by default | six sheets (review) / reach judge (mutation test) / vignettes (capture) each classified separately | Phase 21 readiness | gate protocol + owner | §20 classification |
| R-06 | UI-01 / UI-02 assumed to block Phase 21 | same as R-05 | handoff §18.5 | UI-01 needs the owner's UI brief; UI-02 needs a capture | — | Phase 21 readiness | owner | §20 classification |
| R-07 | Huyết Tinh black-market money pump | social-risk fig leaf without a loss rate | ECONOMY §7–§8 | conversion has loss (canon) | explicit loss rate at implementation | neither (economy tuning) | implementation phase | economy review |
| R-08 | P-clue proliferation | new mysteries without owed payoffs violate the ledger discipline | §8.2 (each P-clue ships with payoff + owner) | "no owed payoff ships" (§11) | — | neither | content review | ledger audit |

---

## 20. Phase 21 readiness dependencies

C2 completion is not among them. The dependencies below are evidence-backed; C2's only contribution is naming them honestly.

**Hard gates (must close before Phase 21 starts):**

- **H21-14 — OPEN / OWNER REQUIRED.** The owner plays the §17.6 checklist and writes down what happened. No substitute exists. (R-04)
- **Q-01 resolved** (kept/told definitions) — the entry handoff's route semantics depend on it.

**Classified debts (per the gate protocol, not by default):**

- **B2-01:** six contact sheets → review debt (does not block dungeon narrative design; blocks visual sign-off of the matrix only). `reach` judge mutation test → test debt (blocks nothing in Phase 21's narrative scope; belongs to the tool's owner). Three Origin vignettes → capture debt (does not block Phase 21; the vignettes are Act I content, already shipped). **Proposed classification: non-blocking follow-ups**, each owned separately. Owner confirms.
- **UI-01:** awaits the owner's UI brief — the brief, not Phase 21, unblocks it. **Non-blocking** unless the brief redefines the dungeon-entry UI surface.
- **UI-02:** a capture task (satchel wearing the robe). **Non-blocking** for Phase 21.

**Design inputs ready:** the entry handoff (§15), the clue ledger (§8), the access principles (MAP_DUNGEON_DESIGN §3), the Phase 21 definition (ROADMAP: DungeonData + instance modifiers; rewards via the Phase-19 ledger).

**Explicitly not started:** Phase 21 implementation; Phase 22 implementation; any networking; any persistence implementation.

---

## 21. Acceptance checklist

Against C2.13:

1. Proposal exists at `docs/proposals/PROPOSAL_SAGA_SECT_ATLAS_CULTIVATION_AND_P21_HANDOFF.md`: **yes** (this file).
2. Explicitly a proposal, not canon: **yes** (§1, header).
3. Required sources inspected (10 steering docs, protocol, freeze, roadmap, game flow, decisions, narrative/canon set, progression/economy/social/sect set, dungeon doc, multiplayer plan, handoff, both C1 proposals): **yes** — five parallel readers, full reads; missing/ambiguous sources reported in §4.
4. Acts I–III detailed, IV–X scaffolded: **yes** (§7).
5. Every act has purpose, conflict, clue movement, progression significance, consequences, reveal constraints, dependencies: **yes** (§7 per-act template).
6. Clue ledger preserves IDs, connects clues to observable events and timed payoffs: **yes** (§8).
7. Both sect atlases preserve canon, new material labeled: **yes** (§9, §10).
8. Cultivation loop connects sources, sinks, costs, choices, risks, feedback, story: **yes** (§12, §13).
9. Phase 21 section limited to access/motivation/routes/entry/continuity: **yes** (§15).
10. Phase 22 section limited to narrative purpose and payoff obligations: **yes** (§16).
11. Shared-world design respects state boundaries without freezing C1: **yes** (§17).
12. Open questions explicit, not disguised as decisions: **yes** (§19).
13. Gate-status section accurate and source-backed: **yes** (§5, §20).
14. States C2 does not close H21-14 or authorize Phase 21: **yes** (§1, §5, §20).
15. No dungeon/boss implementation, code, assets, tests, migrations, or canon edits: **yes** — verified by final diff (one new file only).
16. Final diff checked for accidental changes: **yes** — `git status` shows exactly one untracked file; no other file touched.

---

## 22. Source references

**Steering:** `.kiro/steering/01-product.md` (D-074 direction) · `02-game-design.md` (glossary, two-axis contract, C-002) · `03-architecture.md` (layers, autoload budget, D-056 target) · `08-ai-review-protocol.md` (review gates) · `09-lessons-learned.md` (L-014, L-040, L-042, L-046, L-049, L-053, L-054, L-057) · `10-ci-failure-protocol.md` (diagnostic discipline).

**Governance:** `docs/PHASE_EXECUTION_PROTOCOL.md` (phase contract, nine dimensions of done) · `docs/GAME_DESIGN_FREEZE.md` v2.1 (frozen elements §5; change control) · `docs/ROADMAP.md` (phase status; Phase 21/22 definitions) · `docs/GAME_FLOW.md` (flow; "the Survey Shaft's door does not open") · `docs/DECISIONS.md` (D-039, D-056, D-064–D-074).

**Narrative/canon:** `docs/NARRATIVE_MASTER_PLAN.md` (§4 Đêm Vỡ Mạch chain; §8 ten acts; §9 ladder; §9a clue ledger; §10 replayability; §14 four-way split) · `docs/NARRATIVE_DIRECTION.md` (craft invariants) · `docs/WORLD_BIBLE.md` (§8 sects/factions) · `docs/CANON_LEDGER.md` (CL-01–CL-17) · `docs/CONTRADICTION_REGISTER.md` (C-001, C-003, C-004, C-005, C-011) · `docs/CONTENT_BIBLE.md` (§12 content contracts; §16 Lạc Hà cast).

**Systems:** `docs/PROGRESSION_CULTIVATION_DESIGN.md` (three axes; realm ladder; paths; threat rating) · `docs/ECONOMY_CRAFTING_DESIGN.md` (resources; sink rule; anti-inflation) · `docs/SOCIAL_DESIGN.md` (consequence loop; sect hard rules) · `docs/SECT_SYSTEM.md` (roster authority D-015; faction edges D-042) · `docs/RELATIONSHIP_SYSTEM.md` (six dimensions CL-12) · `docs/MAP_DUNGEON_DESIGN.md` (§3 access gating; §5 dungeon grammar; §6 bosses; §9 revisit) · `docs/MULTIPLAYER_PLAN.md` (stance; state split; non-work binding) · `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md` (D-056 dedicated-server contract; cited, not re-read in full — the contract's existence and target are the cited facts).

**Handoff:** `docs/handoff/pre-phase-21-hardening.md` (§2, §11, §13, §15.5, §15.6, §16.1, §17.6, §18.1, §18.5 — gate statuses and checklists).

**C1 proposals (reviewed, not authority):** `docs/proposals/PROPOSAL_SHARED_WORLD_STORY_MODEL.md` · `docs/proposals/PROPOSAL_ONLINE_AUTHORITY_ARCHITECTURE.md`.

---

*End of proposal. Status: PROPOSAL — NOT CANON — OWNER REVIEW REQUIRED. Phase 21 and Phase 22 are not started. No commits were made.*
