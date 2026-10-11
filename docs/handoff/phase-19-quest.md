# Phase 19 — Quest: closure report

> Stage report for Phase 19 (`docs/ROADMAP.md`, D-070). Gates A–E of
> `docs/PLAYER_EXPERIENCE_STANDARD.md`. **Phase 20 and every later phase are NOT STARTED.**
> No story flag, chapter, loot table, drop, dungeon, boss, save file, autoload or network code
> was added.

## 1. Baseline, branch and CI

| | Value | How it was verified in THIS run |
|---|---|---|
| Starting head | `8f3ccbd` on `main` AND `d063/phase-a` | `git ls-remote origin 'refs/heads/*'` |
| Starting CI | run 38063935548 (`main`) and 38063432098 (`d063/phase-a`), both `success` on `8f3ccbd` | `gh run list` |
| Working branch | `feature/phase-19-quest`, created from `8f3ccbd`; `main` never written to | `git status --short --branch` |
| Working tree | clean except the untracked, user-owned `CLAUDE.md` (never staged) | `git status` |

**The `main` discrepancy, reconciled.** The post-Phase-18 closure report said `main` stayed at
`f3fe408`. That was true when it was written (its last push went to `d063/phase-a` at
15:23Z). `origin/main`'s reflog then shows `update by push` to `8f3ccbd`, with its own CI run
(38063935548, 15:31Z) — a fast-forward made after that report, not by it. Both branches are
the same commit; nothing was reset or rewritten.

| Checkpoint | Commit | CI on that exact SHA |
|---|---|---|
| 0 — contract and ADR (D-070) | `735c394` | run 38065063429 — `success` |
| 1 — quest domain + the one reward ledger | `8ece8f6` | run 38065933247 — `success` |
| 2–3 — runtime, content, journal, E2E gate 14 | `8d73028` | run 38067690492 — **`failure`** (see below) |
| 4 — the experience pass + the fix for that failure | `6809a6e` | run 38069262439 — `success` |
| 5 — the layer fix and its guard | `19e49a2` | run 38069906502 — `success`: 14 steps, the runner's annotation "ran 1064 test(s): 1064 passed, 0 failed" (https://github.com/MinhNQ03/Game_2D_Tu_Tien/actions/runs/38069906502) |
| 6 — this record (documentation only) | the commit that adds this row | verified after its push; see the final report |

**The red run is this report's to own.** `8d73028` was pushed with the NPC E2E failing: that
flow pinned "Dialogue, then NPC" as the first two sessions torn down, and `QuestRuntime` now
sits between them. The local gate run before the push had failed in the same place and was
misread as "only the world flow failed". The invariant is now stated for three sessions
(Dialogue → Quest → NPC), and the local gate script ends with ONE verdict line that names
every failing gate, so a count can no longer be got wrong.

## 2. What was built

### Owners (Gate B)

| Class | Layer | Owns |
|---|---|---|
| `QuestData`, `QuestObjectiveData`, `QuestCatalogData` | data | authored requirements; nothing that changes |
| `RewardData`, `RewardItemData` | data | what a source pays; no id of its own |
| `QuestState` | domain | THE record of quest progress (`to_dict` / `from_dict`) |
| `QuestService` | domain | the only writer of `QuestState`; phases, objectives, accept / abandon / turn in |
| `RewardLedger` | domain | THE record of what has been paid (`to_dict` / `from_dict`) |
| `RewardService`, `RewardPayers`, `RewardOutcome` | domain | paying a multi-part reward once, in order, resumably |
| `RegardRules` | domain | the one statement of "X's regard for the player" (was `DialogueService`'s private rule) |
| `QuestRuntime` | gameplay (session node) | wiring, the "ready" announcement edge, the view |
| `RewardRuntime` | gameplay (session node) | holds the ledger for the session |
| `QuestJournalView` | presentation DTO | keys, numbers, phases |
| `QuestJournalPanel` | presentation | the journal; decides nothing |

Not stored anywhere else: no flag, no `CharacterState.story_flags`, no HUD boolean. READY is
derived from the Knowledge Core and the bag every time it is asked.

### State machine

```
(no record) AVAILABLE ──accept──► ACTIVE ──objectives met (derived)──► READY ──turn in──► COMPLETED
      ▲                             │  ▲                                 │
      └────────── abandon ──────────┘  └── an objective un-met again ────┘
                                              READY ──a later reward part fails──► REWARD_OWED ──turn in──► COMPLETED
```

### Session order

`World, Relationship, Sect, Faction, WorldSimulation, Combat, **Reward**, Progression,
Knowledge, Cultivation, Inventory, Equipment, Skill, Pet, Npc, **Quest**, Dialogue` — 17 nodes.
Teardown is the exact reverse: Dialogue → Quest → Npc → … → Progression → Reward → Combat → ….
Pinned by `test_session_lifecycle.gd` and by three E2E teardown traces.

## 3. The reward ledger (AUD-12, closed)

- **Owner:** `RewardLedger`, one per session, held by `RewardRuntime`. It is the only record
  of "paid".
- **Ids:** a defeat — the per-spawn id combat already mints (`map_field__enemy_mist_wolf__0#1`);
  a quest — `quest:<quest_id>`, with its parts `…/bag`, `…/xp`, `…/regard`. Empty ids are
  refused. A re-cleared map mints new ids and pays again; a quest pays once.
- **`ProgressionRuntime._granted` is gone.** The defeat guard claims in the shared ledger; a
  progression session with no ledger is refused. Its behaviour is otherwise unchanged (the
  Phase-11 suite still passes; three tests were added).
- **Transaction contract — ordered, idempotent, resumable; not a rollback:** the bag part
  first (items in and items the quest takes out, ONE `InventoryRuntime.exchange`); a refusal
  there records nothing and changes nothing; each accepted part is recorded at once; a part
  that fails after the bag moved leaves the quest `REWARD_OWED` and a retry pays only the
  unrecorded parts; a payment cannot be re-entered.
- **Proof of no loss and no duplicate:** unit (`test_reward_domain.gd`, `test_quest_domain.gd`),
  integration (`test_quest_runtime.gd`: full bag, twice-answered, re-entrant, round trip) and
  the E2E (steps 10–12): after a refused turn-in the ledger holds only the defeat; after both
  quests it holds exactly 8 ids — 1 defeat + 4 (elder: bag, xp, regard, quest) + 3 (scout:
  bag, regard, quest).
- **Phase 21:** a drop is `RewardService.deliver(<source id>, <RewardData>, {}, payers)`. No
  quest code is involved and no second ledger is needed.
- **Phase 23:** `rewards` and `quests` blocks are specified in `SAVE_FORMAT.md`. No file is
  written today.

## 4. The two quests

| | `quest_unquiet_vein` — "Mạch rừng không yên" | `quest_treeline_pills` — "Thuốc cho người gác" |
|---|---|---|
| Giver / receiver | Thẩm Bất Kỳ (hub) | Kha Thản (field) |
| Why he asks | he keeps the Terrace's precept; the stele's warning is old and Vụ Lang were seen at the vein's edge; an elder does not leave the forecourt | he cannot leave the crossing; what he sells is his wage; the village owes its watch two pills |
| Why the player | they read the stele (his existing gate) | "from Lạc Hà" — his first words — and walking back anyway |
| Dimensions | exploration + combat, OR exploration + investigation | exploration + resource management |
| Objective | ANY: defeat one Vụ Lang · know `know_vu_lang_hunting_ground` | ALL: hold 2 Bổ Huyết Đan (handed over) |
| Knowledge route | asking the scout spares the fight; the elder then concludes "there are hours to cross" — after a fight he concludes "no one crosses unarmed" | — |
| Reward and its source | 2 Bổ Huyết Đan (the hall's store), 10 XP, his respect +10 | 3 Linh Thạch (he pays what the risk is worth), his affinity +15 (his shop prices on it) |
| Placement | nothing new: every person and object already had its recorded reason (D-067) | nothing new |

The elder's pills are exactly what the scout is owed: finishing the first makes the second
ready. No arbitrage: two pills cost 6 from the scout's own stock; the errand pays 3, once.

**What the player sees:** at spawn the place plaque reads "Gặp Trưởng lão Thẩm"; the ask is
two lines and an explicit choice; taking it is announced with the journal's key; the plaque
then states the goal, then who to return to; a full satchel refuses the report in words and
the talk stays put; the reward is named part by part.

## 5. Gates run on the final source tree (local)

The gate script's verdict on the final source tree: `ALL 13 LOCAL GATES PASS` — lint
self-test, lint (312 files), import, parse, boot smoke, **1064 tests passed, 0 failed, 0
`SCRIPT ERROR:`, 0 leak lines**, and seven isolated E2E flows (app, player, world, pet, npc,
dialogue, quest), each with 0 script errors and 0 leak lines. CI adds the checkout as its
fourteenth gate.

> **Correction (2026-10-11, D-071 / L-051).** "0 leak lines" above was the leak gate's
> answer, and the gate matched only the plural wording. The suite at `19e49a2` ended with
> `WARNING: 1 ObjectDB instance was leaked at exit` — locally and in CI run 38069906502 —
> from one node a quest-runtime TEST created inline and never freed. No shipped code was
> involved and no result above changes, but the sentence was not true as written. The node
> is freed and the gate takes both wordings as of the readiness task.

Real window (`tools/playtest_flow.gd`, the older journeys): `en` 1280×800 — 30 / 30;
`vi` 1280×720 — **three runs: 29 / 30, 30 / 30, 30 / 30**. The one failed step (19, the
unassisted encounter) is debt Q19-04 below, with its frame: not a quest defect, and not
hidden behind the two runs that passed.

Mutations: 31 applied across the phase (12 reward / quest domain, 11 seam / runtime, 7
journal / purpose line, 1 layer direction), 31 red. One of them exposed a test that HUNG instead of failing; it
is now bounded (L-048).

Performance (headless, 2026-10-10): `QuestService.phase_of` 3.98 µs per call;
`eligible_choices` with quest conditions 19.57 µs per call; no quest, reward or journal node
processes; the tightest journal layout has 26 px to spare at 1280×720.

## 6. Visual evidence (PLAY)

**Convention.** Captures are local, ephemeral evidence and are not committed. Written under
the session scratch directory `…/scratchpad/q3/quest_<lang>_<size>/` by:

```
DISPLAY=:0 $G --path . --resolution <1280x720|1280x800> \
    -s res://tools/capture_motion.gd -- <dir> quest <vi|en>
```

Sizes were read from the written PNG files. Nothing was clamped on this 1920×1080 desktop.

| Language | Requested | File size written | Frames | Result |
|---|---|---|---|---|
| `vi` | 1280×720 | 1280×720 | 18 | PASS |
| `en` | 1280×720 | 1280×720 | 18 | PASS |
| `vi` | 1280×800 | 1280×800 | 18 | PASS |
| `en` | 1280×800 | 1280×800 | 18 | PASS |

The 18 frames: spawn lead · elder's reason · his ask with its two answers · accepted · journal
(quest under way) · journal after its key (next quest) · the question before giving a task
back · the scout's five answers · his ask · taken · the "ready" notice · journal (ready +
under way) · reward refused · reward paid · reward received · journal (done + ready) · the
scout paid · journal (all done).

Opened and judged, in all four combinations (full frames for vi 1280×720; 1× crops of the
plaque, the dialogue box and the journal stacked across the four for the rest):
- **The purpose line** is one row in every state and language, in body text; in the accent
  with different WORDS when a quest is ready; absent when nothing is left to be about.
- **The dialogue box:** the longest new lines wrap to two or three rows with the key line
  below them; five answers fit the scout's hub; the question before giving a task back has
  "No — see it through" under the cursor; the elder is stern (in words) when he asks it.
- **The announcement band** rides above the box: "Đã nhận việc: … (Q sổ việc)", the refusal
  "Túi đồ đã đầy — dọn chỗ rồi quay lại nhận thưởng.", "Xong việc: …", "Được trao: Bổ Huyết
  Đan ×2".
- **The journal:** no scrollbar and nothing clipped in any of the five states; the quest in
  focus is opened out, the other is two lines; states are words ("đang làm", "chờ thưa
  lại", "chưa nhận", "đã xong"); the keys line says what the key does next ("Q Việc kế · Esc
  Đóng" / "Q Đóng"); the player and the elder stay visible to its left; the prompt strip
  stays (the journal is not modal).
- **Vietnamese diacritics** legible at 1× throughout.

**Defects found by looking, and fixed** (none of them was caught by a test first):
1. *The journal hid the second quest below a fold* at 1280×720, reachable only by mouse wheel.
   → one quest opened out at a time, the journal's key steps; a guard lays the shipped quests
   out at 1280×720 in all 16 state pairs × 2 languages.
2. *That guard then passed while a frame still showed a clipped line*: it measured after two
   frames, before wrapped labels had settled, and read minimum size instead of laid-out size.
   → it now waits for a steady layout and measures what was laid out; three more rounds of
   shortening followed (the tightest case has 26 px to spare).
3. *An eighth prompt did not fit the strip* (704–738 px) — found by the layout test, not by
   eye. → the journal key is taught where a quest is taken on.

## 7. Playability, pacing and clarity (Gate D, in prose)

- **Within 30 seconds, without prior knowledge?** Yes: the plaque's third line is on screen
  from the first frame ("Gặp Trưởng lão Thẩm"), he stands 56 px from the spawn point, and his
  first line points at the stele 109 px from him. Nothing is accepted for the player and no modal opens.
- **Does he have a reason to ask, and can the player repeat it?** He keeps the precept the
  stele states; wolves at the vein's edge mean people might cross at the wrong time. The ask
  is two lines and the journal keeps the one-sentence version.
- **What, why and where?** "See if wolves hold the vein" → two ways, both named with a place
  or a person ("in the woods", "Ko Than"). The scout stands where the road enters the woods;
  the dens are off the road. No pixel hunt: nothing new was placed.
- **Survivable and legible?** The scout is 334 px from the nearest den (outside detection);
  the knowledge route never enters wolf range. The fight route is the existing encounter.
- **Do the two quests differ?** One is a question with two answers (a fight or a
  conversation) and a conclusion that depends on which; the other is a thing carried that the
  player could also swallow. Neither is a kill count.
- **Does knowledge save a different task?** Yes — asking the scout replaces the fight, and
  what was already known counts the moment the task is taken (nobody is sent to learn what
  they know).
- **What changed, what was received, what next?** "Xong việc", then each part by name; the
  plaque moves to the next thing, or goes quiet when there is none.
- **Decline, abandon, full bag, threat, Esc?** Declining changes nothing and the offer
  stands. Abandoning takes a second answer whose default keeps the quest, and says what is
  lost. A full bag refuses in words and keeps everything. A wolf turning on the player closes
  the journal with every other reading surface. Esc closes the journal, then only asks.

## 8. Docs updated

`DECISIONS.md` (D-070 + as built) · `ROADMAP.md` · `GAME_FLOW.md` (status, diagram, §3.5,
the Phase 19 note) · `SYSTEM_DEPENDENCY_MATRIX.md` (Quest, Reward ledger, Dialogue rows) ·
`DATA_SCHEMA.md` · `SAVE_FORMAT.md` (`quests`, `rewards`) · `TEST_PLAN.md` (14 gates) ·
`PERFORMANCE.md` · `UI_UX_BIBLE.md` · `CHANGELOG.md` · `09-lessons-learned.md` (L-048, L-049) ·
`post-phase-18-audit.md` (AUD-10, AUD-12 closed) · this file.

## 9. Debt (the register `PLAYER_EXPERIENCE_STANDARD.md` §4 requires)

Open entries of the earlier registers stand (AUD-07, AUD-09, AUD-13, AUD-14, AUD-15). Closed
by this phase: **AUD-10**, **AUD-12**.

| ID | Symptom / cost to the player | Why not now | Owner | Closure criterion | Makes later work harder? |
|---|---|---|---|---|---|
| CLV-01 | none today — `ShopData.keeper_id` is not validated against the character registry | Phase 19 added no shop and did not touch `NpcRuntime.start_session`'s content checks (decided at Gate A, D-070) | `NpcRuntime`; with the first phase that adds a shop, no later than Phase 21 | `NpcRuntime.start_session` refuses a shop whose keeper does not resolve, with a test that fails without the check | no |
| Q19-01 | a quest can be given back only by walking to its giver; the journal cannot do it | the journal is deliberately not modal (AUD-15: no fifth hand-copied modal), and a consequence needs a second, explicit step | Phase 25 (UI Consolidation), on the unified modal-surface seam | the journal offers "give back" behind a confirmation, through the same `QuestRuntime.abandon`, with a real-key E2E | no — the rule (`QuestService.abandon`) is already separate from where it is asked |
| Q19-02 | the journal opens ONE quest out at a time; with many quests the key steps through all of them | two quests fit; categories and paging need content that does not exist yet | Phase 25, or the first phase that ships a fifth concurrent quest | with N ≥ 5 concurrent quests the journal groups by category and any quest is reachable in ≤ 3 presses, measured by a test | no |
| Q19-04 | **CLOSED** (`f253727`, D-071). Was: a Vụ Lang chasing in a straight line stopped against a prop standing between it and the player and never went round (seen once in three `vi` 1280×720 playtest runs, step 19). Traced, not inferred: the stall is a STABLE resting point of `move_and_slide` for a pursuer — from 0, 0.01, 0.5 and 2 px off the target's row it came to rest against the trunk in `CHASE` with velocity `(0, 0)` for a whole 20 s run; `RETURN` and a companion's follow stalled the same way | — | Enemy AI; closed before Phase 20 by the readiness task | **Met.** `MovementComponent.apply_pursuit` walks round a solid thing met squarely; `tests/integration/test_enemy_detour.gd` (15: the measured staging at six offsets, every field footprint from four sides, sixteen bearings, a shut way reversed once, leash, lost target, a second creature, a companion, the open field unchanged), budget derived from the authored speed and route; playtest step `17b_hunt_round_obstacle` red on the old code and green on every run of the fix; `docs/handoff/pre-phase-20-readiness.md` | no longer — see NAV-01 for what remains |
| Q19-05 | **CLOSED** (`cef225d`, D-071). Was: `src/data/worldsim/world_sim_catalog.gd` named the domain class `WorldClock` (`MIN_UNIT`) — a data resource depending upward | — | World Simulation; closed before Phase 20 by the readiness task | **Met.** The floor is stated once, on `WorldSimCatalog.MIN_CALENDAR_UNIT`; `WorldClock` and `WorldSimulationState` read it downward; `KNOWN_EXCEPTIONS` in `test_layer_direction.gd` is empty; the guard was shown red on the old implementation; `tests/unit/worldsim/test_calendar_contract.gd` holds the catalog and the clock to the same answer for every unit and value | no |
| Q19-03 | once both quests are done the plaque's purpose line is empty: nothing states a next objective | there is no further content; inventing a line would promise something the game lacks | Phase 20 (Story: the chapter gives the standing objective) | a new session that has finished every available quest still names a next purpose from the story service | no |
| NAV-01 | a creature (or a companion) whose straight line AND both ways round the first obstacle are shut — a prop plugging a gap, a dead-end pocket — reverses once and then rests there until its target moves, is lost, or the leash calls it home. Nothing shipped has such a place on a creature's route (every footprint is convex and stands in open ground); recorded when Q19-04 was closed | routes through concave space are navigation; nothing shipped has a corridor to design it against (D-071) | the phase that first authors rooms — Phase 21 (Dungeon), before its first room ships | a creature reaches a reachable target through an authored room with at least one concave corner, by test; `test_a_pocket_shut_on_both_sides_is_rested_in_not_paced` is replaced, not deleted | no — `MovementComponent.apply_pursuit` is the one seam to replace, and `AiBrain` does not change |

## 10. Status

**Phase 19 is DONE** at `19e49a2` (CI run 38069906502, 14 gates green on that exact SHA). The
commit recording this changes documentation only. **Phase 20 and every later phase are NOT
STARTED.**

**After this handoff (2026-10-11):** Q19-04 and Q19-05 were closed by the pre-Phase-20
readiness task on `fix/pre-phase20-readiness` — `docs/handoff/pre-phase-20-readiness.md`,
D-071. That task reopened nothing above: Phase 19 remains DONE, and Phase 20 gameplay has
not started.
