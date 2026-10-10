# PLAYER_EXPERIENCE_STANDARD — Aetheria

> **The one standard for how a feature must behave, read and fit from the PLAYER's side.**
> Binding on every phase from Phase 19 onward, and on any change to an already shipped
> player-facing system (adopted in D-067).
>
> **Owner of:** the cross-cutting experience rules (§2), the five phase gates A–E (§3), the
> no-anonymous-debt rule (§4), the review questions (§5) and the per-phase Player Experience
> Contract template (§6).
> **NOT the owner of** — it links to them and never restates them:
> the order of gates and the evidence each needs (`PHASE_EXECUTION_PROTOCOL.md`), visual and
> layout rules (`UI_UX_BIBLE.md`), motion (`MOTION_DESIGN_CONTRACT.md`), identity
> (`XIANXIA_IDENTITY_CONTRACT.md`), map and quest grammar (`MAP_DUNGEON_DESIGN.md`), content
> declarations (`CONTENT_BIBLE.md`), economy (`ECONOMY_CRAFTING_DESIGN.md`), state ownership
> (`SYSTEM_DEPENDENCY_MATRIX.md`). If a rule here and its owner disagree, the owner wins and
> this file is corrected.

---

## 1. The principle

**A feature is finished when a player can find it, understand it, use it, see what it did, and
back out of it — inside the game as it exists today.** A rule that passes its tests and fails
any of those five is unfinished work, not polish for later. Each phase makes ITS slice
coherent with the whole; it does not hand the next phase a rough edge it could have fixed.

The counterweight: this is not a licence to grow scope. A defect is fixed in the earliest phase
that owns the feature and has what the fix depends on. More content is never the fix for
unclear content.

## 2. The rules

Each rule is written so that a reviewer can answer it with evidence. The **Check** says how.

### PX-1 Whole-game coherence
Before code, state in two or three sentences: the player's situation and intent; the in-world
reason the feature exists; the journey from entry to success AND to cancel; what changes, who
owns each change, and what tells the player.
**Check:** the Gate-A note (§3) exists and names the neighbouring features that must not regress.

### PX-2 Everything placed has a reason
A person, creature, prop, exit, pickup or landmark is where it is for a reason that can be said
in one sentence in Aetheria's terms (occupation, territory, function, route, story) — never
"there was space".
- **People** stand where their role puts them, off the walking line, with every side a player
  would approach from reachable. A person's reach never swallows another interactable's.
- **Creatures** have a territory, a leash and an approach the player can read; nobody is
  spawned on a route the player must take or within detection range of a safe service.
- **Props** support function, navigation, mood or story. A prop that LOOKS usable is usable, or
  it is redrawn.
- **Exits** show where they lead and are never hidden behind collision or foreground art.
- **Spawn points** put the player on open ground, facing something legible, out of reach of
  harm, with the HUD not covering them.
- **What is drawn is what collides**: body, reach, layer order and walkable width agree with
  the art (`MAP_DUNGEON_DESIGN.md`, `UI_UX_BIBLE.md` §3c own the numbers).
**Check:** the placement reasons are written beside the content (map design file or ADR); a
real walk into each new thing with a held move key (E2E or playtest).

### PX-3 Items, rewards and loot obey the world
- A thing on the ground has a SOURCE: dropped by what was defeated, left by someone, grown,
  stored in a container, awarded, or placed for a stated story / teaching reason.
- Not everything yields loot. Most things are scenery.
- A reward fits its source, region and the player's progress; a container behaves like what it
  is (a chest is not an herb patch).
- Every pickup is reachable on foot, visibly a pickup, and resolves atomically: fully taken
  and announced by name and count, or refused with a reason and left where it was.
- One owner: the bag (`InventoryState`) for held items and funds, `ShopState` for stock, the
  reward ledger of the system that pays. No second balance, ever.
- Until file-level save exists (Phase 23) pickup state is per session, and nothing on screen
  promises otherwise.
**Check:** the source is recorded with the content; a test collects, a test refuses (full bag).

### PX-4 Interaction is predictable and forgiving
- A prompt appears only while the action is really possible, names the action (and the target
  when there is one), shows the key `InputService` reports, and disappears the moment it stops
  being true or a modal takes the keys.
- **One press, one action.** The press that opens a surface never also acts inside it. A
  surface that is modal owns the keys until it is dismissed.
- Overlapping targets resolve deterministically (nearest, then a stable tie-break).
- **Esc always steps BACK one level and never destroys progress on its own**: it closes the
  top surface; with nothing open it ASKS before leaving a session.
- Every refusal says why. Nothing fails silently.
- **Control is never withheld while the player is being harmed.** A reading or trading surface
  yields the moment a hostile turns on the player.
- Simple things stay one press; only choices with consequences get a second step.
**Check:** an E2E drives the real key for open, act, cancel and the wrong-time case; the
opening-press guard is mutation-checked.

### PX-5 The screen is organised, in both languages
One place for each kind of thing (identity, place, prompts, announcements, reading panels,
modal boxes); the most relevant information first; nothing covers the two parties to an
interaction; state is never carried by colour alone.
**Check:** captures OPENED and judged in `vi` and `en` at **1280×720** and at a second aspect
ratio (**1280×800**; a `1920×1200` request is clamped by this machine's desktop to 1920×1011 —
report the size of the file actually written). A layout test measures the element AS LAID OUT.
`UI_UX_BIBLE.md` owns the budgets.

### PX-6 Feedback is true and timely
Feedback follows the authoritative result — never before it, never without it. Direct actions
answer within 2 frames / 100 ms. Motion states intent, cause, state or danger; anything else
is removed. A placeholder is recorded as debt (§4) or it is not shipped.
**Check:** the feedback is triggered from the owner's outcome signal, not from the key press.

### PX-7 Story and systems agree
Who someone is, where they stand, what they say, sell, know and give all fit canon and the
current state of the world. A choice has a real consequence in an authoritative system, or it
is plainly expressive — never a fake one. Ordinary content differences live in data; a branch
on an id in core code needs a written reason.
**Check:** the consequence is asserted through the owner's API in a test; canon references are
cited (`CANON_LEDGER.md`).

### PX-8 It is worth doing
The player has a near-term goal and a reason to care; choices differ in outcome; routine
actions are short; danger is readable before it is punishing and there is a way to recover;
required progress is never a pixel hunt. Clarity and consequence are improved before volume.
**Check:** the Gate-D playthrough answers §5's pacing questions in prose.

### PX-9 Technique serves the experience
Deterministic, owner-respecting, data-driven, no speculative layers
(`PRODUCTION_ARCHITECTURE_CONTRACT.md`). Edge cases that a player can reach — stale plan,
empty purse, full bag, hidden choice, repeated press, teardown mid-action — are handled and
tested. The shipped path prints no script error, no leak, no missing resource.

## 3. The five gates

`PHASE_EXECUTION_PROTOCOL.md` §1c wires these into the phase contract. Scope is proportional:
a one-line change needs one line per gate.

| Gate | When | It asks | Evidence |
|---|---|---|---|
| **A — Understand the experience** | before design is fixed | PX-1's statement; why each new thing is placed where it is (PX-2/3); what could confuse; what is NOT in scope and who owns it; what will prove it | a short note in the phase's ADR or plan |
| **B — Ownership and contracts** | before state-changing code | the one owner of each new piece of state; success, refusal, cancel, repeat, teardown and stale-state behaviour; what triggers feedback; save/schema impact | the owner table (protocol §3) + matrix row |
| **C — A complete vertical slice** | while building | world/data context → player action → authoritative result → feedback → tests → docs, all in THIS phase; no backend without its UI, no UI promising what the rules lack | the slice runs in the real app |
| **D — Validate the experience** | before closure | rules, boundaries, real-input E2E, the negative paths (wrong time, cancel, refused, repeated, interrupted), the nearest older journeys still pass, vi/en at two aspect ratios, a clean log | test names, E2E steps, captures opened and described |
| **E — Close without exporting debt** | at closure | docs match the game; nothing temporary remains; every known limitation is recorded per §4; CI is green on the exact commit | the closure report |

## 4. No anonymous debt

A known defect may outlive its phase only when it is outside that phase or unsafe to fix in
it, and only when written down with ALL of:

1. the symptom and what it costs the player;
2. why it cannot be fixed safely now;
3. the owning system and phase;
4. a testable closure criterion;
5. whether leaving it makes later work harder.

"Polish later", "UI to improve" and "edge cases in a future phase" are not entries. The live
register is `docs/handoff/` (one file per audit or stage); an entry is closed by the commit
that meets its criterion.

## 5. Review questions

Asked at Gate A for what is planned and at Gate D for what was built. A real defect found in
an ALREADY SHIPPED system is logged with a severity and handled by the scope rule below.

- **Map:** can a newcomer name the route, the exits and the safe ground? Is every required
  thing approachable from a sensible side? Does the camera keep the action readable, and do
  layer order, scale and collision agree? Does the area have its own job and mood?
- **People and creatures:** why is each one here? Is its attitude readable before it acts?
  Does a companion or an enemy body block or cover what the player is doing?
- **Items and economy:** who left, made, dropped, grew or sold this? Is it reachable? Do
  quantity, value and place agree? Does each operation complete whole or not at all? Does the
  player know what changed and why something was refused?
- **Interaction and UI:** is the action obvious without permanent clutter? Is the target
  chosen predictably? Can a modal be opened by accident, or act on its opening press? Can the
  player always step back? Are price, requirement and irreversible consequence shown BEFORE
  the commitment? Do both languages fit?
- **Story:** does it respect canon and the world's state? Does the action matter somewhere
  authoritative? Is the reward earned in context?
- **Pacing:** what is the interesting decision, discovery, risk or beat? Is routine short and
  the meaningful deep? Is the danger fair and taught first? Is repetition chosen or imposed?

**Severity:** **P0** corrupts data, crashes, exploits the economy or blocks the core loop ·
**P1** a major experience defect in a shipped system (contradictory controls, lost progress,
control withheld under harm, a dead end, a misleading consequence) · **P2** usable but rough ·
**P3** a risk owned by a later phase.
**Scope rule:** fix P0; fix P1 that belongs to shipped systems; fix P2 only when small, safe
and valuable; record P3 with its owner. Never pull a later phase forward to close a finding.

## 6. The Player Experience Contract (one per phase)

Seven lines, written before the phase starts, kept in `ROADMAP.md` beside the phase:

- **Player promise** — what the player can do, understand or feel afterwards.
- **Core journey** — the shortest complete path from entry to outcome and to cancel.
- **World rule** — why and where the content appears.
- **State authority** — which existing owner holds each outcome.
- **Feedback** — what success, refusal and unavailability look like.
- **Evidence** — the tests and the in-game checks that will prove it.
- **Non-goals** — what later phases own and this one must not build.

## 7. What this document does NOT do

It adds no gameplay rule, no code and no content. It does not replace any owner document
listed at the top. It is the player-side definition of "finished".
