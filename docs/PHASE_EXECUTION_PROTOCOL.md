# PHASE_EXECUTION_PROTOCOL — Aetheria

> **Binding execution protocol for every Aetheria phase from Phase 10 onward.**
> `.kiro/steering/08-ai-review-protocol.md` governs *how any single change is reviewed*; this
> document governs *what it takes to finish a PHASE*. The steering file points here rather
> than restating it, so there is one checklist and not two that can drift apart.
>
> **Owner of:** the phase quality contract, the evidence each gate requires, and the rule that
> a green pipeline is not a finished phase.
> **NOT the owner of:** coding standards (`04-coding-standards.md`), the review loop for an
> individual change (`08-ai-review-protocol.md`), the CI-failure procedure
> (`10-ci-failure-protocol.md`), UI design direction (`UI_UX_BIBLE.md`), or the player-side
> rules and gates A–E (`PLAYER_EXPERIENCE_STANDARD.md` — §1c says where each one runs).

---

## 0. Why this exists

The repository is entering the content-heavy gameplay stage. Up to Phase 09 a phase could be
judged almost entirely by its tests, because almost everything it added was a rule. That is no
longer true: a phase now adds things a player *sees*, *feels* and *fights*, and none of those
are visible to an assertion.

The evidence for this is in the project's own history, not in theory:

- **D-034** shipped four simultaneous HUD defects — light text on a light plate, a hollow
  ornament used as a keycap, a 218×118 texture used as a 40×40 slot — with every test green.
- **D-050** found **nine** defects in a UI that was asset-backed, tokenised and green on 481
  tests, the first time anybody looked at a screenshot of the running game. One of them was
  that every `vi_*.png` was in English.
- **D-051** found the Phase-09 attack lifecycle to be **completely invisible to the player**:
  correct state machine, no swing, no impact, just a number changing.
- **L-036** found a solid combat target parked on the hub's main walking line, so leaving spawn
  walked you into it — on a commit already green on CI.

Every one of those passed compilation, unit tests, integration tests, E2E and CI. So:

> **A green CI is necessary and NOT sufficient. A phase is complete only when DESIGN + CODE +
> TEST + PLAYER EXPERIENCE + UI + VISUAL / PRESENTATION + PERFORMANCE + CLEANUP + DOCS all
> pass** (the nine dimensions since D-056; VISUAL / PRESENTATION is gate §7b, PERFORMANCE §10,
> DOCS §12).

### What each kind of evidence actually proves

| Evidence | Proves | Does NOT prove |
|---|---|---|
| Compile / parse | the code loads | anything about behaviour |
| **Unit tests** | the RULES are right | that anything is wired to them |
| **Integration tests** | the BOUNDARIES hold | that the real app takes that path |
| **E2E (real app, headless)** | the real FLOW works | that a human can see or understand it |
| **Real-app playtest** | the player-facing EXPERIENCE works | that it looks right |
| **Visual capture + inspection** | what is actually ON SCREEN | that it is fun |
| **Performance budget** | cost scales as the design claims | that it is fast on target hardware |

The last two rows are the ones that were missing for nine phases, and they are where the
defects above were hiding.

---

## 1. The phase quality contract

```
PRE-FLIGHT → DEPENDENCY → AUTHORITY → EXTENSIBILITY → GAMEPLAY → NARRATIVE
    → UI → PRESENTATION → REAL PLAYTEST → VISUAL QA → PERFORMANCE → CLEANUP → DOCS
    → FINAL REVIEW
```

Run them in order. Each gate below states **what it asks** and **what evidence closes it** —
a gate with no evidence is an opinion.

### 1c. The player-experience gates (D-067) — binding from Phase 19

`docs/PLAYER_EXPERIENCE_STANDARD.md` is the single owner of the player-side rules (PX-1 … PX-9)
and of five gates that cut across the chain above. They add no new chain; they say what the
existing gates must ALSO answer, and when:

| Standard gate | Runs with | What it adds to that gate |
|---|---|---|
| **A — Understand the experience** | §1 PRE-FLIGHT, before any design is fixed | the phase's Player Experience Contract (`ROADMAP.md`), the journey to success AND to cancel, and one sentence of in-world reason for every new person, creature, prop, exit, reward and panel |
| **B — Ownership and contracts** | §3 AUTHORITY | for each new piece of state: refusal, cancel, repeat, teardown and stale-state behaviour, and which outcome signal triggers feedback |
| **C — A complete vertical slice** | §5 GAMEPLAY → §7b PRESENTATION | context → action → authoritative result → feedback → tests → docs, all inside this phase |
| **D — Validate the experience** | §8 REAL PLAYTEST, §9 VISUAL QA | the negative paths, the nearest older journeys, vi/en at two aspect ratios with the real frame size reported |
| **E — Close without exporting debt** | §11 CLEANUP → §13 FINAL REVIEW | every known limitation written in the standard's §4 form in `docs/handoff/`; "polish later" is not an entry |

A phase that cannot show the evidence for a standard gate has not passed the protocol gate it
runs with.

### 1. PRE-FLIGHT — audit the repository before adding to it
Read the design docs that own the scope, and the code you are about to touch, before writing
anything. Find the stale claims FIRST: a phase that starts from an out-of-date document
inherits its errors. Record what you found rather than silently correcting it.
**Evidence:** a list of the docs/files read, and any drift found (which becomes its own
documentation fix, as D-049 and D-051 were).

### 2. DEPENDENCY — do the arrows still point downward?
`presentation → gameplay → domain → data`, with `persistence`/`infrastructure` as described in
`03-architecture.md`. **A file's layer is a claim about its dependencies, and the type names in
its signatures are the evidence.** GDScript resolves `class_name` globally, so there is no
import statement to look wrong — a domain class typed on a `Node` compiles and tests fine
(L-036). Ask: *could this run with no scene tree at all?* If not, it is not domain.
**Evidence:** grep the new files' signatures for node types; confirm no new autoload (the
budget is frozen at five, D-017).

### 3. AUTHORITY — who owns each piece of state?
Every new value has exactly one owner, and the persistent / runtime / presentation partition
holds. No system writes another system's authoritative collection (D-015); it asks that
system's service. A derived cache must be rebuilt, never serialized as truth (L-001).
**Evidence:** name the owner of each new field and which tier it is in.

### 4. EXTENSIBILITY — is the next one content?
Adding the *second* map / enemy / skill / item / quest must be **data + content**, not an edit
to core code. If a second instance would need an `if id == ...`, the design is wrong now.
**Evidence:** point at the `.tres` (or catalog row) that a second instance would be.

### 5. GAMEPLAY — what can the player do that they could not before?
Answer in one sentence, in player terms. "The system exists" is not an answer. A phase that
cannot answer this has built infrastructure and should say so plainly.
**Evidence:** the sentence, plus the playtest step that demonstrates it.

### 6. NARRATIVE / WORLD — does it belong to Aetheria?
Where the phase adds content: does it fit the frozen world, the canon vocabulary
(`02-game-design.md`), and the licence/provenance rules (`06-art-assets.md`)? A generic
fantasy creature in a tu-tiên world is a content defect even if it functions.
**Since D-057A this gate also covers how the phase LOOKS AND MOVES:** run the generic fantasy
drift gate, the believable-AND-Aetheria dual check and the Aetheria Identity Review
(`XIANXIA_IDENTITY_CONTRACT.md` §6, §7, §15). Reference boards are research, filtered by canon —
a realm name, element or tagline read off a board is never content (§2.3).
**Evidence:** the content's identity stated in Aetheria's own terms, its `ASSET_LICENSES.md`
row, and the identity review answered in prose.

### 7. UI — is the new state visible, and does it use the foundation?
Anything the player must know has to be on screen, using the D-050 shared seams
(`UI_UX_BIBLE.md` §3b/§8b) — never ad-hoc styling and never default Godot look. **Do not render
a gauge for a value no system owns** (§4): a bar that shows nothing real is worse than an
absent one. A new permanent HUD element must earn its space and keep the HUD inside its
negative-space budgets (`UI_UX_BIBLE.md` §3c) — the budget test fails if it does not.
**Evidence:** the seam used, and a capture showing it.

### 7b. PRESENTATION — what reusable capability does the phase leave behind? (D-056)

> **Every gameplay phase must leave behind at least one REUSABLE player-facing presentation
> capability when its feature has a visible gameplay consequence.**

Not a bespoke effect for one feature — a **seam the next feature reuses**. This gate exists
because a phase can pass every other gate while the result is stiff: correct damage with no
swing, a skill that is a ball appearing beside a motionless figure, a level-up that is a
different integer. `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` owns the rules; the per-phase
seeds are in `docs/ROADMAP.md`.

Three rules bind every phase from P12 on:

* **FOUNDATION FIRST, CONTENT SECOND.** The phase that introduces a *category* builds the
  reusable seam before the content explosion. First skill → skill presentation seam → second
  skill reuses it. Never: boss A bespoke, boss B bespoke, boss C copies B.
* **GAMEPLAY TIMING OWNS THE TRUTH.** An animation follows a lifecycle; it never decides
  damage, a hit, a death, XP or a cooldown. "Animation reached frame 7, therefore deal damage"
  is forbidden without an explicit, data-authored gameplay-marker contract.
* **PROVE REUSE WITH A SECOND ACTOR.** A new presentation seam is accepted when a concrete
  second consumer exercises it — different assets, different frame counts, same contract. One
  actor is a feature; two is a seam.

**Designed before it is built (D-057):** each major visual feature carries the deliberation
record (`MOTION_DESIGN_CONTRACT.md` §13) and the Reference → Original note
(`XIANXIA_IDENTITY_CONTRACT.md` §13), written before the code, and closes with the self-critique
(`MOTION_DESIGN_CONTRACT.md` §19).

**Evidence:** the capability named, the second consumer named, and a capture showing the
anticipation → action → recovery (or the equivalent beats) actually on screen. A state
variable reading `true` is not evidence that anything was drawn.

### 8. REAL PLAYTEST — drive the real app through the real input pipeline
`tools/playtest_flow.gd` boots the real game in a real window and plays it with real semantic
input. Each step declares **expected vs observed**. It must not fake player behaviour by
calling domain mutators (that is L-017: an E2E that bypasses the boundary it advertises can be
green while the boundary is broken).
**Evidence:** the playtest report, with every step `PASS` and a non-zero exit on any failure.

### 9. VISUAL QA — look at the screenshots
`tools/capture_ui.gd` writes the real viewport. **A screenshot-producing tool is not a
screenshot-reviewing tool.** The loop is:

```
RUN → CAPTURE → LOOK → IDENTIFY DEFECTS → FIX → CAPTURE AGAIN → REVIEW AGAIN
```

Generating an image and declaring success is the exact failure D-050 was created to stop. For
a UI-changing phase: **two genuinely different ASPECT RATIOS**, both languages. 1600×900 next
to 1280×720 is *not* two layout tests — with `canvas_items` + `expand` a same-aspect window is
a pure uniform scale and produces two identical images.

Report three kinds of evidence and never let one stand in for another
(`MOTION_DESIGN_CONTRACT.md` M-16.1, `XIANXIA_IDENTITY_CONTRACT.md` §11): **STATE** (a test read a
value), **PIXEL** (a capture was opened and judged — naturalness, motion, silhouette, timing,
readability, hierarchy, composition) and **REFERENCE** (the research a design came from).
**Evidence:** the defects found by looking, and the re-capture after fixing them.

### 10. PERFORMANCE — measure the claim the design makes
Find the architectural claim ("cost scales with observed actors, not the whole cast"; "an idle
attacker costs nothing") and assert it as a **relative scaling** test, which holds on any
hardware because it compares the build against itself. Add a generous absolute ceiling only to
catch an accidental quadratic — a tight millisecond budget on shared CI is a flaky test that
gets deleted rather than a guard that gets respected.
**Do not optimize before measuring**, and log any real optimization in `PERFORMANCE.md` with
before/after numbers (`05-performance-testing.md`).
**Evidence:** the printed numbers, and a `PERF-00N` entry if something was optimized.

### 11. CLEANUP — leave nothing behind
No scratch scripts, no temp captures, no committed logs, no unused asset or source-pack copies,
no dead resource references, no debug polygons, no commented-out alternates, no stale comments
describing removed architecture.
**Evidence:** `git status`, `git diff --stat`, `git diff --name-status`, each read rather than
merely run.

### 12. DOCS — synchronize everything the phase touched
`DECISIONS.md` (an ADR for anything a future reader would ask "why"), `CHANGELOG.md`,
`ROADMAP.md` status, `SYSTEM_DEPENDENCY_MATRIX.md` row, the owning design doc, `TEST_PLAN.md`
count, `ASSET_LICENSES.md`, `PERFORMANCE.md`, and a steering `L-0NN` for any recurring mistake
class. **A doc that contradicts the code is a bug** (L-014). Mark status explicitly as
CURRENT / HISTORICAL / FUTURE rather than letting a status block rot (D-049, D-051).
**Evidence:** the list of docs changed, and the status markers added.

### 13. FINAL REVIEW — the pre-completion gates, reported
Run the `08-ai-review-protocol.md` gates and **report each one by name with its result**,
including what could not be verified. Then the phase's own exit criteria. Then the player-facing
review (§3). Then the debt register: every limitation the phase knowingly leaves, in the five
fields of `PLAYER_EXPERIENCE_STANDARD.md` §4 — or the sentence "this phase leaves none".
**Evidence:** the gate-by-gate report and the register.

---

## 2. Capture and report policy

**Generated screenshots, logs and diagnostics are EPHEMERAL EVIDENCE.** They are produced,
inspected, and not committed.

- Default output is `user://` (or a git-ignored temp dir). The tools default there on purpose.
- **Do not commit a capture set.** A full matrix is ~15MB of binaries whose only job was to be
  looked at once; the harness is committed and deterministic, so anybody can regenerate it in
  one command. Repository history is not a screenshot archive.
- A screenshot may be committed **only** as an intentional design baseline, and then it must
  have a documented purpose, provenance, and a reason the harness cannot replace it. A random
  debug image never qualifies.
- Scratch files use the `_` prefix convention so `.gitignore` catches them by construction
  rather than by remembering to delete them (L-009).

---

## 3. Player-facing review (the questions tests cannot ask)

At phase close, answer in prose — not as checkboxes — and then score. Scores are a **review
aid, never a gameplay rule**.

Ask: is the new thing understandable? does it feel alive rather than scripted? can the player
predict it? is the timing readable? does the player understand *why* something happened to
them? does it feel different from the test fixture it grew out of? does success feel
meaningful? is the scene visually coherent? does the UI help or obstruct? **does it feel like
Aetheria rather than a generic Godot demo?** — and the D-057 tests: the player-experience test,
"would a player notice?" and "so what?" (`MOTION_DESIGN_CONTRACT.md` M-16.3, M-16.4, M-1.6).

Score 1–5: **UX · Visual · Readability · Performance · Maintainability**.

> **For any score ≤ 3, list concrete defects.** And do not hide a weakness behind "the next
> phase will fix it" unless that weakness is genuinely owned by that phase — say so with the
> phase number, or own it now.

---

## 4. What this document does NOT do

It does not replace the per-change review loop (`08-ai-review-protocol.md`), the CI-failure
procedure (`10-ci-failure-protocol.md`), or any design doc. It adds no gameplay rule and no
code. It is the definition of "finished", and nothing else.
