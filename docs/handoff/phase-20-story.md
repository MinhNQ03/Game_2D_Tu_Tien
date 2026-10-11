# Handoff — Phase 20: Story, Origins and the first playable prologue (D-072)

> **Status: IN PROGRESS.** This file is kept current at every checkpoint. A section marked
> *planned* describes what Gate A decided and has not yet been built; a section marked
> *built* is on the branch with its tests. Phase 20 is not DONE until §12 says so.
> Phase 21 (Dungeon) is NOT STARTED.

## 1. Baseline

| | |
|---|---|
| Branch | `feature/phase-20-story` (one branch for the whole phase) |
| Base | `4420eae98b4a9a9951b894f08c673247be2b001e` = `origin/main` = `origin/fix/pre-phase20-readiness` at preflight (2026-10-11) |
| Other refs at preflight | `origin/feature/phase-19-quest` `b768935`, `origin/d063/phase-a` `8f3ccbd` |
| CI on the base | run 38112355059, branch `main`, `head_sha` `4420eae`, success |
| Local baseline before any edit | `ALL 13 LOCAL GATES PASS` on `4420eae`: 1090 / 1090 tests, 0 `SCRIPT ERROR`, 0 leak lines (either wording), seven E2E flows |
| D-071 present on the base | `MovementComponent.apply_pursuit`; `KNOWN_EXCEPTIONS := {}`; the two-wording leak pattern in all seven places of `ci.yml`; the freed node in `test_quest_runtime.gd` |

`CLAUDE.md` is user-owned and untracked; it is never staged.

## 2. The player-experience contract (Gate A)

The decision record is D-072 in `docs/DECISIONS.md`; this is the short form the work is held
to.

- **Who the player is.** A nobody in the Hoang Vực frontier with one Origin-specific problem.
  No sect, no rank, no gift, no prophecy.
- **What the places are for.** Thôn Lạc Hà is a village kept by one small outpost of a great
  sect (Thanh Đài: an elder, a disciple, a paid watchman). Rừng Vỡ Mạch is the woods over a
  vein that outpost is supposed to be measuring.
- **The journey.** Identity and Origin → a vignette → arrival → three or four people →
  the village's own business → one decision about trust → the Night → creatures in the
  woods → the morning after, and something removed → sitting down to cultivate → a torn sheet
  that does not fit → a reason to go on.
- **Leaves holding:** (1) a practical goal, (2) the Origin's personal goal, (3) one person
  worth caring about, (4) an unanswered question, (5) a reason to continue.
- **Never:** an artifact, the Thiên Khế, the Tà Đế's name as an answer, a sect, a morality
  score, "you are special".

## 3. One owner per fact

| Fact | Owner (the only writer) | Read through |
|---|---|---|
| Origin of the run | `StoryService` → `StoryState.origin_id` | `StoryRuntime` view; dialogue `ORIGIN` condition |
| Chapter, beat, completed beats, choice record | `StoryService` → `StoryState` | `StoryRuntime` view |
| Story flags | `StoryService` → the player's `CharacterState.story_flags` (the ONE store) | dialogue `FLAG` condition |
| Gender, appearance | the player's `CharacterState` (built from the chosen appearance) | HUD, entity visual |
| Knowledge | `KnowledgeService` | unchanged |
| Quest phase, objectives, reward | `QuestService` / `RewardService` | unchanged |
| Regard between people | `RelationshipService` | unchanged |
| Sect / faction membership | `SectService` / `FactionService` | unchanged — the player has none |
| Bag, equipment, techniques, XP, cultivation, companion | their Phase 11–16 owners | unchanged |
| World clock and background events | `WorldSimulationService` | unchanged |
| What the Night looks like on a map | presentation, derived from `StoryState` | never stored |
| The purpose line | derived: quest → story → place | never stored |

## 4. The twelve beats (planned; updated as each is built)

| # | Master-plan beat | In this game | Completes when (read from an owner) | Owner of what changes |
|---|---|---|---|---|
| 1 | Character creation | menu → identity screen: appearance (gender), Origin; back / confirm | confirm | none until confirm; then the session start |
| 2 | Origin vignette | a short scene: place-and-time card, three or four captions, the Origin's problem | scene ended or skipped | — (the beat was committed first) |
| 3 | Frontier arrival | the player stands at the village's edge; movement prompt; "find someone from Thanh Đài" | first talk with a named person | Story |
| 4 | First social contacts | Thẩm Bất Kỳ (the hall), Lâm Nguyệt (the spring), Tề Mộc the carter (the east road); Kha Thản at the treeline is the fourth | three named people spoken to | Story (met-record) |
| 5 | First small problem | the two shipped quests, as they are: *Mạch rừng không yên*, *Thuốc cho người gác* | the player has HEARD one of them (accepted, finished or declined — any of the three) | Quest for the quests; Story only for "heard" |
| 6 | First relationship decision | Lâm Nguyệt is re-measuring the spring without leave. Keep her confidence, or tell the elder | the choice is recorded | Story (choice) → `RelationshipService` (both edges) |
| 7 | Đêm Vỡ Mạch | warning where the player stands; the rupture on their next arrival in the woods | arrival in `map_field` after the warning | Story (stage) |
| 8 | First combat / exploration | the Night's creatures near the caravan; fight, or withdraw to the village | the Night's creatures are all down, OR the player left the woods | Combat / Reward for the fight; Story for the outcome; Relationship for Kha Thản's view of it |
| 9 | First consequence | morning; the vein site changed; the survey mark gone; the elder's version | the elder has been heard | Story; Relationship |
| 10 | First cultivation step | sit at the Lạc Hà spring (the woods' vein is unsafe now) | a cultivation session yields, per `CultivationService` | Cultivation |
| 11 | First mystery | a torn survey sheet, weighted under a stone at the stele | the sheet's knowledge is held | Knowledge |
| 12 | Entry into the larger world | attention is coming to the châu; the standing Act-I purpose | last line heard; chapter → Act I | Story |

Non-deadlock rules: declining both quests still satisfies beat 5 (the player heard the
village's business and turned it down — a decision in itself). A quest finished before its
beat is acknowledged, not asked for again. If every authored wolf is already dead, the Night
brings its own (per-spawn ids; no corpse is revived or paid twice).

## 5. Cast (planned)

| Character | Exists today | Why they are here | What the player can do with them |
|---|---|---|---|
| **Thẩm Bất Kỳ**, elder of Thanh Đài | yes (hub) | the outpost that surveys the vein is his; its allocation depends on the figures | the wolves quest; the stele's record; after the Night, his account |
| **Kha Thản**, frontier scout | yes (treeline) | paid by the outpost to watch the crossing; trades what he carries | trade; the pills quest; word about the wolves |
| **Lâm Nguyệt**, inner disciple | data only (world-sim cast); not yet placed | posted to the outpost; she takes the readings | beat 6's decision; after the Night, the sheet |
| **Tề Mộc**, carter | NEW | hauling a load out by the east road before dark; the Night catches his cart in the woods | every Origin's hook into the Night; the way out of the prologue |

Each gets a full bible entry (goal, fear, secret, public and private belief, relationships,
callback) in `CONTENT_BIBLE.md` when placed (Checkpoint 3).

## 6. Traceability (an audit table; the resources remain the authority)

Filled in as content lands — one row per authored person, interactable, creature placement,
item, clue, purpose line and new number: id · source in canon or design · why it exists
here · what the player does with it · owner of what it changes · `vi` / `en` keys · payoff.

| Id | Kind | Source | Reason to exist here | Player use | State owner | Keys | Payoff |
|---|---|---|---|---|---|---|---|
| `origin_ho_tieu` … `origin_thu_thu` | Origin ×5 | master plan §6, CL-09 | the run's personal problem | chosen once at creation | Story | *(CP 2)* | long-term callback per §6 |

*(rows are added with the checkpoint that authors the thing)*

## 7. Feature-surface audit (what the player can inspect)

| Surface the opening needs | Ships today | Plan |
|---|---|---|
| Identity, level vs realm, stats | HUD plaque only (name, level, XP, realm, sect chip) | a Self page in the Chronicle |
| Bag: names, counts, effect | satchel (`inventory`) | reuse; audit its text and feedback |
| Equipment and its consequence | in the satchel | reuse; audit |
| Techniques, cost, keys | the dock | reuse; listed on the Self page |
| Cultivation status / next step | the plaque line + the spring | reuse; stated on the Self page |
| Companion | HUD line | reuse; stated on the Self page |
| Quests | the journal (`quest_journal`) | unchanged |
| What the player knows | nowhere | a Knowledge page in the Chronicle |
| The people they have met | nowhere | a People page in the Chronicle |
| Story so far, choices that mattered | nowhere | the Chronicle's first page |

One book, non-modal, on the journal's reading-panel pattern. No future tabs.

## 8. Debt

| ID | Status at Gate A |
|---|---|
| Q19-03, AUD-14, AUD-13, AUD-09 | owned by this phase; to close with evidence |
| Q19-01, Q19-02, AUD-15 | Phase 25 — untouched |
| CLV-01, NAV-01 | Phase 21 — untouched; every required prologue path is over open ground |
| AUD-07 | Phase 26 — untouched |
| Q19-04, Q19-05 | CLOSED (D-071); guards intact on the base |

## 9. Checkpoints

| # | Scope | Commit | CI run on that exact SHA |
|---|---|---|---|
| 0 | Gate A: D-072, this file, CL-09 id fix, save-format and character-system reconciliation | *(this commit)* | *(recorded by the next)* |
| 1 | Story / Origin domain and data | | |
| 2 | Real New Game, identity, Origins, the sectless start | | |
| 3 | Arrival, contacts, the small problem, the first decision | | |
| 4 | The Night, the encounter, the aftermath, cultivation, the sheet | | |
| 5 | Chronicle, purpose arbitration, the way out | | |
| 6 | Audit, real app, close-out | | |

## 10. Non-goals

A morality score · a second dialogue runner or modal framework · a new autoload or global
manager · save file, slots, autosave, Continue · loot or drops · dungeon, boss, navigation ·
a sect join · per-Origin campaigns · an audio system · anything Phase 21 owns.

## 11. Evidence

*(gate tables, mutation lists, captures with their real sizes, playtest runs and first-play
pacing are added by the checkpoints that produce them)*

## 12. Status

Gate A decided. No Story code exists yet. **Phase 20 is NOT DONE.**
