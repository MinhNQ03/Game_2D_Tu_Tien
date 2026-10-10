# Post-Phase-18 audit — player experience, world logic, quality gates

> Stage report for the targeted whole-game audit run between Phase 18 (Dialogue) and Phase 19
> (Quest). It is the first application of `docs/PLAYER_EXPERIENCE_STANDARD.md` and the live
> debt register that standard's §4 requires. **Phase 19 and later are NOT STARTED.**

## 1. Verified baseline

| | Value | How it was verified |
|---|---|---|
| Branch | `d063/phase-a` | `git status --short --branch` (local) |
| Phase-18 feature commit | `ba9e63c` | CI run 38046511848, `head_sha` equal, 13 steps `success` (GitHub API) |
| Phase-18 closure commit (audit start) | `321d2b9` | CI run 38046625731, `head_sha` equal, `success` (GitHub API) |
| Suite tally on `ba9e63c` | 983 passed, 0 failed | the runner's own CI annotation; and a local run of every gate on the same tree |
| Working tree at start | clean except untracked `CLAUDE.md` (user-owned, never staged) | `git status` |

Local runs in this session, on the tree that became `ba9e63c`: lint PASS (284 files), parse
PASS, boot smoke exit 0, 983/983, six isolated E2E PASS (app, player, world, pet, npc,
dialogue), 0 `SCRIPT ERROR:`, 0 leak lines; `tools/playtest_flow.gd -- vi` 30/30.

## 2. Evidence labels

**PLAY** — the real application with a window, captures opened and looked at ·
**PROBE** — the real application headless, driven by real semantic key events, observations
printed (a temporary script, not committed) · **E2E** — the committed isolated E2E gates ·
**TEST** — the in-runner suite · **SOURCE** — read in the code, not run · **FUTURE** — owned
by a later phase.

## 3. Baseline matrix

| System / journey | Status | Evidence | Quality | Risk |
|---|---|---|---|---|
| Boot → menu → settings (vi/en) → New Game | implemented | E2E app flow; PLAY (menu frame: "Tải game" is disabled, honestly) | good | — |
| Hub spawn, camera, hub ↔ field | implemented | E2E world flow (20 round trips); PLAY (spawn frame) | good | no stated objective at spawn (AUD-10) |
| Movement, collision, solid props | implemented | E2E walks into the stele, spring, banner; PLAY | good | — |
| Combat, enemy AI, target plaque | implemented | E2E player + world flow; PLAY (playtest fight frames) | good | **player defeat is unhandled (AUD-01)** |
| Level / XP, cultivation, knowledge | implemented | E2E world flow; TEST | good | — |
| Satchel, equipment, techniques | implemented | E2E world flow; TEST; PLAY (playtest) | good | reading panels under threat (AUD-03) |
| Companion (Hoàng Khuyển) | implemented | E2E pet flow; PLAY; PROBE | usable | **stands on the player (AUD-04)** |
| People, shop | implemented | E2E npc flow; PLAY (shop frames) | good | **shop under threat (AUD-03)** |
| Dialogue | implemented | E2E dialogue flow; PLAY vi 1280×720, en 1280×800, en 1920×1011 | good | greeting repeats (AUD-13, by D-066) |
| Sect / politics panels | implemented | TEST; PLAY (playtest sect frame) | good | **Esc with a panel open (AUD-02)** |
| Leaving a session | implemented | PROBE | poor | **one key, no confirmation (AUD-02)** |
| World-simulation line in the place plaque | implemented | PLAY | weak | reads without context (AUD-09) |
| Loot / drops, containers | NOT implemented | SOURCE (a wolf pays XP only) | n/a | owner unassigned (AUD-12) |
| Quests, story, dungeons, bosses | NOT implemented | ROADMAP | n/a | FUTURE |
| File-level save | NOT implemented | SOURCE (`to_dict` / `from_dict` only) | n/a | FUTURE (Phase 23) |

## 4. Journeys exercised

| # | Journey | Language / frame | Expected | Observed | Evidence |
|---|---|---|---|---|---|
| J1 | launch → menu → New Game → walk the hub | vi 1280×720 | spawn on open ground, landmarks legible | spawn on the plaza before the hall; stele, spring, yard and the elder all in frame | PLAY, E2E |
| J2 | approach a person → prompt → one press | vi/en | the prompt names them; one press opens one thing | holds for both people; the opening press answers nothing | E2E (mutation-checked), PLAY |
| J3 | dialogue → choose → consequence → leave | vi 720, en 800, en 1920×1011 | consequence visible; Esc returns control | regard and knowledge announced above the box; control returns | E2E, PLAY |
| J4 | scout → Trade → inspect → buy/sell → leave | vi/en | adjusted price shown; atomic trade; no stale prompt | −8% and 13 (14) shown; trades atomic | E2E, PLAY, TEST |
| J5 | befriend the hound → walk and stop | headless | it follows without covering the player | **it stops 1 px from the player** | PROBE → AUD-04 |
| J6 | open / close satchel, sect, politics panels | vi | consistent keys; Esc steps back | satchel: Esc closes it. **Sect panel: Esc ends the session** | PROBE → AUD-02 |
| J7 | a wolf reaches the player during a talk / the shop | headless | control returns before harm | talk: closed 64 frames before the first bite. **Shop: stayed modal, health 100 → 55** | PROBE → AUD-03 |
| J8 | the player is defeated | headless | a clear outcome and a way on | **nothing: phase RUNNING, no message, the body still walks** | PROBE → AUD-01 |
| J9 | language and aspect ratio | vi/en; 16:9, 16:10, 1.90:1 | layouts hold | hold after two fixes made in Phase 18 | PLAY |

## 5. Issue ledger

Status is updated by the commit that closes an entry.

### P1 — major experience defects in shipped systems

**AUD-01 — Defeat is a silent dead end.**
*Repro:* New Game → field → stand within a Vụ Lang's reach and do nothing (~15 s).
*Evidence (PROBE):* health reached 0 at frame 903; `GameState` stayed RUNNING; no notice
shown or queued; a held move key still moved the body (15.9 px in 40 frames).
*Impact:* the game's only failure state has no outcome, no message and no way forward; the
character is permanently `DEAD` in its `CharacterState` and keeps walking.
*Systems:* Player entity, WorldRuntime, HUD. *Owner:* combat / world session (shipped, Phase 09).
*Smallest fix:* a defeated player cannot act; the HUD shows a defeat box; one key returns to
the menu. *Verification:* an E2E that is really killed by a wolf. **Status: OPEN → Checkpoint 2.**

**AUD-02 — One Esc ends the session, even with a panel open, and nothing is saved.**
*Repro:* New Game → `T` (sect panel) → Esc.
*Evidence (PROBE):* phase MENU after a single press; the panel was never closed first.
*Impact:* Esc is "close" for the satchel, the shop and a conversation, so a second press — or
the same habit with another panel — destroys the whole unsaved session without a question.
*Systems:* MapBase, HUD. *Smallest fix:* Esc closes the top reading panel; with nothing open
it asks, and only a second, different key leaves. *Verification:* E2E. **Status: OPEN →
Checkpoint 2.**

**AUD-03 — The shop keeps the keys while a hostile is biting.**
*Repro:* fight a wolf without killing it, walk to Kha Thản, open his shop, let the wolf return.
*Evidence (PROBE):* shop open for 420 frames, first bite at frame 75, health 100 → 55, input
context UI_MODAL throughout. (A conversation in the same position closed at frame 5.)
*Root cause:* panels close on the HUD target plaque's "engaged" TRANSITION; a plaque that is
already showing a live target has no transition left to fire. A presentation state was
standing in for a gameplay fact.
*Smallest fix:* combat announces when a hostile turns on the player; every reading surface
yields to that, and a talk is refused while it is true. *Verification:* integration + E2E.
**Status: OPEN → Checkpoint 2.**

### P2 — usable but rough

**AUD-04 — The companion comes to rest on top of the player.**
*Evidence (PROBE):* after walking 70 frames and stopping, pet-to-player distance 1.1 px and
1.3 px (two of four directions).
*Root cause:* the brain decides every 0.2 s; between decisions `RETURN_HOME` keeps walking at
full speed, through the 22 px arrival band it is supposed to stop in.
*Smallest fix:* executing `RETURN_HOME` honours the same arrival radius the brain decides on.
*Verification:* a unit test on the component + the pet budget and E2E still green.
**Status: OPEN → Checkpoint 2.**

**AUD-06 — The hub's pickups had no recorded reason to be where they are.**
*Evidence (SOURCE, PLAY):* a pill and two bundles on the hall steps, a sword in the yard.
*Fix:* the reasons are recorded (D-067 "placement record"); the placements themselves are
sensible and unchanged. **Status: CLOSED by the documentation checkpoint.**

### P3 — risks owned by a later phase (accepted debt, §6)

AUD-07 · AUD-09 · AUD-10 · AUD-12 · AUD-13 · AUD-14 — see §6.

### Not defects (checked and dismissed)

- The pet prompt hides while an interact prompt shows: the HUD rule "one contextual verb at a
  time" (D-064), verified by test.
- A wolf pays XP and drops nothing: consistent with "not everything yields loot" (PX-3).
- "Tải game" is disabled on the menu: honest — no save exists.

## 6. Accepted debt (the register `PLAYER_EXPERIENCE_STANDARD.md` §4 requires)

| ID | Symptom / cost to the player | Why not now | Owner | Closure criterion | Makes later work harder? |
|---|---|---|---|---|---|
| AUD-07 | a defeated character has no fallen pose: the body simply stops | needs a new sheet for every humanoid; a presentation asset, not a rule | Phase 26 (Audio / VFX: "death" is in its seed list) | every humanoid profile authors a fall action and the defeat box appears after it | no |
| AUD-09 | the place plaque's world line ("Ties between people rose") states a change without saying whose or why | it needs a chronicle the player can open | Phase 20 (Story: chronicle UI) | the line names its subject, or opens a chronicle entry that does | no |
| AUD-10 | nothing states a first objective at spawn (the elder's first line and the stele are the only lead) | objectives are the quest system | Phase 19 (Quest) | a new player can state their current objective from the screen within 30 s of spawning (playtest) | no |
| AUD-12 | no loot / drop system and no owner named for one, while Phase 21 assumes "map + combat + loot" | drop rules need a reward ledger shared with quest rewards | decided at Phase 19 Gate B (quest rewards); built no later than Phase 21 | one documented owner for "what a defeat or a container yields", used by both quest rewards and drops | **yes** — two reward paths would duplicate the ledger |
| AUD-13 | a person greets the player with the same line every time; nothing is "said once" | Dialogue owns no flag (D-066) | Phase 20 (Story: `FLAG` condition / `SET_FLAG` effect) | a line can be authored to be said once, through the story service | no |
| AUD-14 | after a defeat the run ends: there is no revival, no checkpoint, no penalty design | what defeat MEANS is a design decision, and "continue" needs a save | Phase 23 (Save / Load: continue from the last save) with the rule decided at Phase 20 Gate A | the defeat box offers "continue" from a real save and the consequence of defeat is an ADR | no |
