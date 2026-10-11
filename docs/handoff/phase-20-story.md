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
| `origin_ho_tieu` | Origin | master plan §6, CL-09 | a caravan lost under the player's guard | chosen on the identity screen | Story (`origin_id`) | `ORIGIN_HO_TIEU_*`, `STORY_SCENE_VIGNETTE_HO_TIEU_*` | who destroyed the caravan, and why the records disagree |
| `origin_de_tu_bi_loai` | Origin | §6, CL-09 | an examination failed that should not have been | 〃 | Story | `ORIGIN_DE_TU_BI_LOAI_*`, vignette | how the examination was really decided |
| `origin_lang_y` | Origin | §6, CL-09 | a patient dead of something that was not a sickness | 〃 | Story | `ORIGIN_LANG_Y_*`, vignette | the "disease" was vein corruption, and someone knew |
| `origin_nghe_nhan` | Origin | §6, CL-09 | a workshop closed by a patron's accusation | 〃 | Story | `ORIGIN_NGHE_NHAN_*`, vignette | the material should not have existed |
| `origin_thu_thu` | Origin | §6, CL-09 | a mentor vanished, the records unfinished | 〃 | Story | `ORIGIN_THU_THU_*`, vignette | the mentor was tracing an edited chronology |
| ho_tieu → `item_kiem_thanh_thiet` ×1 | Origin grant (item) | §6 "combat footing" | an escort keeps their blade | equip it from the bag (teaches equipping) | Inventory (the bag's exchange) | the item's own | the blade is the same one the yard's rack offers: no stronger kit |
| ho_tieu → Thẩm Bất Kỳ `affinity` −10 | Origin grant (regard) | §6 "a damaged name" | word of the lost caravan reached the outpost first | read in how the elder treats the player; shop/regard gates | Relationship | — | the name is cleared or confirmed in Act I |
| de_tu_bi_loai → `know_dan_khi_quyet` | Origin grant (knowledge) | §6 "formal cultivation grounding" | a candidate is drilled in the first breathing method | can cultivate without first reading the stele | Knowledge Core | `KNOW_DAN_KHI_QUYET_*` (shipped P-12) | — |
| de_tu_bi_loai → Lâm Nguyệt `rivalry` +15 | Origin grant (regard) | §6 "a rival who passed" | she passed the examination the player did not | colours her lines; the first decision is about HER | Relationship | — | the examination's truth |
| lang_y → `item_bo_huyet_dan` ×2 | Origin grant (item) | §6 "herbal knowledge" | a healer carries what they compound | heal; or hand the watch his two pills at once | Inventory | the item's own | treating the Night's casualty |
| nghe_nhan → `know_vein_stone_grades` | Origin grant (knowledge) | §6 "can read materials" | an artisan reads a stone's cut and seal | *(a line with the carter that only this knowledge opens — CP 3)* | Knowledge Core | `KNOW_VEIN_STONE_GRADES_*` | the caravan's stones are uncounted |
| thu_thu → `know_survey_notation` | Origin grant (knowledge) | §6 "literacy in records" | a keeper knows how a survey is set down | *(reads the survey mark and the sheet more fully — CP 4)* | Knowledge Core | `KNOW_SURVEY_NOTATION_*` | the two columns that should agree |
| thu_thu → Thẩm Bất Kỳ `affinity` −15 | Origin grant (regard) | §6 "watched" | the outpost was told to watch for such a person | as above | Relationship | — | who asked the outpost to watch |
| `appearance_wanderer_m` / `_f` | player look ×2 | prologue beat 1; master plan §12; `CHARACTER_ART_BIBLE` §5 | identity is the player's | chosen on the identity screen; drawn everywhere | the player's `CharacterState` (built from the look's template) | `APPEARANCE_WANDERER_*_NAME` | every Origin is open to both |
| `scene_vignette_*` ×5, `scene_arrival` | story scene | prologue beats 2–3 | where the player was, and where they now are | read (`interact`) or skipped (Esc) | none — a scene changes nothing | `STORY_SCENE_*` | — |

**Numbers introduced so far, each with its one home and its reason.**

| Value | Where it lives | Why this value | Boundary tested |
|---|---|---|---|
| Origin item grant 1..3 | `OriginGrantData.MAX_ITEMS` | "small starting resources" (§6) — a kit, not a stack | 4 is refused |
| Origin regard grant ≤ 20 either way | `OriginGrantData.MAX_REGARD` | a first impression, not a history (a dimension spans 100–200) | 25 is refused |
| a decision's regard move ≤ 50 | `StoryConsequenceData.MAX_DELTA` | the dialogue seam's own ceiling (D-066): one decision does not carry someone end to end | 51 is refused |
| the authored moves: ±10, ±15, −5 | `data/story/*.tres` (from `tools/author_story_data.py`) | a real but recoverable step on a 100-point dimension; a fall is on `affinity`, the only dimension that goes below zero | every falling regard is on a dimension that can fall |
| a scene has at most 6 steps | `StorySceneData.MAX_STEPS` | every step is a key press spent watching instead of playing | 7 is refused |
| the veil over a scene that is here: 35 % | `StoryScenePanel.VEIL_HERE` | enough to seat the band, not enough to hide who is standing where | a scene that is elsewhere is opaque (alpha 1), asserted |
| preview scale ×3 | `IdentityScreen.PREVIEW_SCALE` | pixel art is shown at an integer scale or not at all | asserted |

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
| 0 | Gate A: D-072, this file, CL-09 id fix, save-format and character-system reconciliation | `89dec88` | 38113654836 — success, `head_sha` `89dec88513e63394d1573ec263e91f2c45af7735` |
| 1 | Story / Origin domain and data | `d8edcf7` | 38114604673 — success, `head_sha` `d8edcf7…` |
| 2 | Real New Game, identity, Origins, the sectless start | `8a3bc2f` | 38117230702 — success, `head_sha` `8a3bc2f96e575827f1373835cdb54cdf4eb33365` (15 gates) |
| 3 | Arrival, contacts, the small problem, the first decision | `d676f51` | 38129290085 — success, `head_sha` `d676f51f1c62f60352d9b432c6684d652b026893` (15 gates) |
| 4 | The Night, the encounter, the aftermath, cultivation, the sheet | `7daa7f7` | 38130589579 — success, `head_sha` `7daa7f743658d55d202c6e55f0bf4c540c8f5c30` (15 gates) |
| 5 | Chronicle, purpose arbitration, the way out | *(this commit)* | *(recorded by the next)* |
| 6 | Audit, real app, close-out | | |

## 10. Non-goals

A morality score · a second dialogue runner or modal framework · a new autoload or global
manager · save file, slots, autosave, Continue · loot or drops · dungeon, boss, navigation ·
a sect join · per-Origin campaigns · an audio system · anything Phase 21 owns.

## 11. Evidence

### Checkpoint 5 — the Chronicle, the purpose line, the way out (built)

**All twelve beats are now playable end to end with real keys**, from New Game to open
Act-I play (`chapter_ke_vo_danh` / `beat_standing`).

| Rule | Owner | Proof |
|---|---|---|
| The purpose line is never blank: taken-on quest → story → quest on offer → the road | HUD, from the owners' views | `test_the_purpose_line_is_arbitrated_…`, `…always_says_what_the_player_is_about`; E2E 8a, 8h |
| Every story objective fits the plaque's one row, vi and en | content | `test_every_shipped_story_objective_fits_one_row_in_both_languages` (all 13 were too long; rewritten) |
| One book, four pages, read-only, never modal; key opens / pages / closes; Esc closes | `ChroniclePanel` + HUD | `test_chronicle.gd` (3); E2E 8g (the player walks with it open) |
| The world line names whom it is about | `WorldRuntime` → `WorldSimView` | `test_the_world_line_names_who_it_is_about` |
| The prologue hands over all five things and ends in open play | Story | E2E 8h |

Debt closed here: **Q19-03** (blank purpose line), **AUD-09** (subjectless world line),
**AUD-13** (a line said once — Checkpoint 3's `FLAG` seam, used by every once-only line).

**Honest limits.** (1) The people page shows three raw numbers per person; it does not yet
say them in words. (2) The Chronicle's key is not advertised in the prompt strip (an eighth
prompt does not fit, as Phase 19 measured); it is in the panel's own footer only, so a new
player has to find B. (3) The story page shows the newest six records; older ones are not
reachable. (4) Act I has one standing objective and nothing to do about it yet — by design
(Phase 20 stops here), but a player WILL reach "now what?".

### Checkpoint 4 — the Night, the encounter, the morning, the first sitting, the sheet (built)

**What is playable (beats 7–11), with real keys.**

| Stage | What the player sees | What changed, and who owns it |
|---|---|---|
| before | the spring, the stake in the woods, the carter waiting | — |
| warning | when Lâm Nguyệt has finished speaking: a band over the village — the spring misses a beat, the lanterns gutter, the cart has gone for its last load | nothing (a scene changes nothing) |
| event | on arrival in the woods: the rupture, told over the woods | `beat_night` is current (Story) |
| the wave | when the scene ends: two creatures of the Night, far from the entrance; the cart abandoned with its crates split, a manual on the ground | spawned by Combat through its own seam; `flag_vein_broke` (Story) |
| the answer | the last one down → *stood*; walking back out → *withdrew* | `choice_night_stand` recorded once (Story); Kha Thản's regard (Relationship); XP through the one ledger |
| aftermath | "the next morning", over a covered map; the stake is gone | `flag_night_over` 1 or 2 |
| consequence | the elder opens with his account; the watchman says one line about how the player met the Night; Lâm Nguyệt says where to look, or only that something was hidden | `flag_heard_elder_account` |
| cultivation | sitting at the spring and gathering tu vi | `CultivationService`; the story only hears `gathered` |
| mystery | a sheet weighted under a stone at the stele's foot | `know_survey_fragment` (Knowledge) |

**Fairness (AUD-14 stays honest).** The wave begins > 300 px from the entrance and only after
the scene; the exit behind the player stays open and leaving is a recorded answer, not a
failure; the creatures are the shipped mist wolf with its shipped telegraph (no new stats);
the E2E clears both with the base attack and the player alive.

**Tests.** Story E2E: 17 real-key steps (8d the rupture and the wave, 8e standing, 8f the
account / the sitting / the sheet, 11 withdrawing in a second run). Suite unchanged in count
(1182): the map invariants (`test_map_scenes`, `test_prop_bodies`) caught two real mistakes
on the way — a stake drawn off its measured origin with no body, and a weight stone standing
on its own reading spot — and both were fixed in the scene, not in the tests.

**Mutations (8, all RED, restored):** a scene opens over a conversation · the wave spawns
during the scene · leaving is no answer · clearing is no answer · presence ignored · sitting
tells nobody · the wave shares ids with the woods' wolves · the rupture flag is not raised.

**Real application.** `tools/capture_ui.gd` gained `_capture_the_night` (a capture, staged
through the story owner): six states photographed at 1280×720 vi and opened — the warning
card and caption over the village; the rupture caption over the woods with the stake standing
and Kha Thản at the treeline; the wave with the abandoned cart, its pale crates and the
spilled manual; the morning card over a covered map; the stone at the stele's foot.

**Honest limits.** (1) The "wreck" is the cart sprite standing — not visibly broken; the
caption says *abandoned*, not *overturned*, to stay true to the picture. (2) There is no
night: the woods are lit as by day, and darkness is told, not shown. (3) The Night's creatures
are the shipped wolf, unchanged — "not themselves" is said, not seen. (4) In the E2E the
player's attack was found mid-recovery on returning to the village and ended the first sitting
as *attacked*; the test now waits for READY. Whether a real player can reproduce a stuck
recovery was NOT investigated (CHƯA VERIFY). (5) That a hidden interactable is not offered is
exercised only through presence in the E2E; it has no test of its own. (6) The purpose line
and the world line are still Checkpoint 5's.

### Checkpoint 3 — arrival, the people of Lạc Hà, the village's business, whom to trust (built)

**What the owner's playtest of Checkpoint 2 said, and what was done about it** (D-072
addendum): *flat, nothing pulls* → every named person now has a goal, a fear and a secret that
shows in what they say (`CONTENT_BIBLE.md` §16), and each Origin notices one thing about the
carter's load that nobody else can; *things lie around for no reason* → the outpost's blade,
coat and primer are HELD until the elder issues them in words; *the woman's look cannot be
told apart* → re-designed by colour blocks and re-rendered.

**What is playable (beats 3–6), with real keys.** The run begins on the west road at the
bridge (`Spawns/from_road`), where the carter let the player down. Lâm Nguyệt measures the
spring; Tề Mộc waits by his cart on the east road; Thẩm Bất Kỳ stands in the plaza; Kha Thản
is at the treeline. The first talk completes *arrival*; three people met completes *contacts*;
hearing the elder's or the watchman's problem out — taken or declined — completes *the
village's business*; Lâm Nguyệt then confides, and keeping her confidence or telling the
elder is ONE recorded decision that moves two people's regard and makes the Night due.

| Rule | Owner | Proof |
|---|---|---|
| A conversation asks the story for a flag and the Origin, and hands it `SET_FLAG` / `STORY_CHOICE` | `DialogueService` asks, `StoryRuntime` writes | `test_dialogue_content.gd` (7 story-seam tests on the shipped content) |
| Story content the story does not have never starts | `DialogueService.content_errors` | `test_content_that_names_what_the_story_lacks_stops_the_session` (6 broken catalogs + no-story) |
| A first line depends on what is true (`openings`) | `DialogueService.opening_node_id` | kept / told greetings, unit + E2E step 8c |
| Talking to someone is meeting them | `DialogueRuntime.talk` → `StoryRuntime.meet` | E2E step 8a |
| What belongs to somebody is not picked up | `InventoryRuntime` (`WorldItem.held_by_flag`) | E2E step 8b: refused once, nothing taken, then issued, then taken |
| The run arrives by the road | `Main.ARRIVAL_ENTRY` → `WorldRuntime.start_session` | E2E step 8a |

**Tests.** Suite 1182 (was 1174): +7 shipped-content story-seam tests, +1 fail-closed test;
the Story E2E grew from 10 to 13 real-key steps (8a arrival and a line only this Origin gets,
8b the held blade, 8c the business and the decision). Re-pinned on the SAME invariant: the
elder's offered answers (one more: the issue), the dialogue box's largest-offer measurement
(now enumerates flag values and the one Origin a run has), the rigs that start a dialogue
session on shipped content (they now start the story it names), "someone with nothing
authored" (a test stranger: everyone shipped has a conversation now).

**Mutations (15, all RED, all restored):** FLAG condition always true · ORIGIN condition
always true · openings ignored · story effect not dispatched · story refusal swallowed ·
undeclared flag in a condition / in an effect accepted · flag threshold / value above its
ceiling accepted · unknown Origin accepted · unknown story option accepted · held pickup given
away · held refusal said every tick · talking does not meet · run starts in the plaza.

**Real application (opened and looked at).** `tools/playtest_flow.gd` gained two real-key
steps: `03e_arrival_road` and `03g_first_people` (walk to three people, ask each a real
question, take the issue). Seen in the 1280×720 Vietnamese run: the player stands on the
bridge of the west road in the woman's look (lilac jacket, jade skirt, knot — distinct from
the grey-blue man at 1×); Lâm Nguyệt in rose by the spring, the elder in grey on the plaza;
on the east road Tề Mộc in indigo with a bark-brown head-wrap beside a cart of roped crates
under a tarpaulin; his portrait and his line in the dialogue box, mood "dè chừng".

**Honest limits at this checkpoint.** (1) The purpose line still prefers a quest LEAD over
the story objective, so on arrival it reads "Gặp Trưởng lão Thẩm" — arbitration is
Checkpoint 5 (Q19-03). (2) The world line "Quan hệ giữa người với người tăng lên" still has
no subject (AUD-09, Checkpoint 5). (3) The cart's wheels are seen edge-on by the top-down
camera and read as dark slabs. (4) Tề Mộc's beard is two pixels at 1×; it reads in the
portrait, not on the sprite. (5) A story scene that becomes due while a conversation is open
(the warning, Checkpoint 4) must wait for the conversation to close — not built yet.
(6) The offering pill by the spring and the vein stones in the woods are still free
(nobody's, by design); the thunder manual in the woods has no owner yet and gets one with
the Night's wreck in Checkpoint 4.

### Checkpoint 2 — the real New Game, identity, the sectless start (built)

**What changed for the player.** New Game → *Ngươi là ai?* (a look, an Origin, what each
Origin gives and costs) → *Lên đường* → the Origin's vignette on the ink ground → the arrival
in Lạc Hà → control, as a nobody: the plaque reads *Chưa có tông môn* and the strip offers
only what a nobody can do.

**Owner changes.** `Main`: New Game opens the identity screen and starts nothing;
`_start_run(template, origin)` is the old start, taking who the player is. `WorldRuntime`
builds the player from the chosen template. `SectRuntime`: a content seam, and the player's
sect is READ from the rosters (the remembered `_player_sect_id` is gone — it would have gone
on saying "none" after a later join). `StoryRuntime`: the 18th per-session node, between
`QuestRuntime` and `DialogueRuntime`. `EquipmentData.body_visuals_by_base`: a garment per
body. HUD: one more surface (the scene band) registered the way the conversation is.

**Three defects found by running it, not by reading it.**
1. *The identity screen chose by moving the cursor.* Reaching "Set out" walked through the
   Origins below and changed the choice. The E2E's second run started as the wrong person.
   Now the cursor looks and accept chooses (L-052).
2. *A memory was shown over the village.* The 90 % veil let the plaza and the HUD show
   through in the real window. A scene that is elsewhere is now on the opaque ink ground.
3. *The menu ignored Enter after a covering screen closed* (identity and settings).

**Sectless, verified three ways.** The rosters hold no player (unit + world E2E + story
E2E); the derived cache on the character is empty; the HUD says so in words and sells no
sect key. A later join through `SectService.join_member` is followed by the runtime.

**Art.** `player_f_proto`, `player_f_daobao` (design YAML → Blender 5.2 headless → pixel):
12 sheets, 2 anchor files, 2 profiles, 1 medallion; `style_check.py sheet` passes on the
four sheets checked. Opened at ×3 beside `player_proto` and `cultivator_f_proto`: the same
wanderer (silver hair, grey-blue robe, jade sash), a narrower cut, hair up; black-haired
rose-robed Lâm Nguyệt is not mistaken for her. Honest limit: from the FRONT at 1× the two
looks differ mostly by hair and build — they read apart more clearly in profile and in the
portrait. Provenance: `ASSET_LICENSES.md` P58, P59, K9.

**Real window (opened and looked at; all 1280 × 720 PNG, vi):**

| Frame | What is in it |
|---|---|
| `cp2b/…04c_identity_look_2.png` | *Ngươi là ai?* — the woman's look on the stage with her own medallion, ◆ on the chosen look and Origin, the Origin's problem / gives / costs at the right, nothing clipped |
| `cp2b/…04e_opening_step_02.png` | the vignette on the ink painting, the band centred, no village or HUD behind it, `2 / 4`, `E Tiếp · Esc Bỏ qua` |
| `cp2a/…04e_opening_step_06.png` | the arrival over the live village, band in the lower third, HUD present, strip stood down |
| `pt/cp2_vi/…03b_identity_chosen.png` | after real keys: ◆ Lữ khách · nữ, ◆ Lang Y Du Phương, *Đã chọn: …* above the buttons, focus on *Lên đường* |
| `pt/cp2_vi/…04_hub.png` | in play as the woman's look: her portrait in the plaque, *Chưa có tông môn*, the strip shows only Attack and Menu |

`tools/playtest_flow.gd -- vi <dir>` at 1280×720: **34 / 34** (three new real-key steps for
the identity screen and the opening; every older step, including D-071's
`17b_hunt_round_obstacle`, unchanged and green).

**Mutations: 26 applied, 26 red** (20 unit / integration, 6 on the real-app E2Es).

| # | What was broken | Red in |
|---|---|---|
| R1 | the shipped start enrols the player again | sect runtime ×2 |
| R2 | the player's sect remembered, not read | sect runtime ×3 |
| R3 | confirm can fire twice | identity ×2 |
| R4 | looking chooses an Origin | identity ×2 |
| R5 | the choice marked by colour only | identity |
| R6 | skipping a scene does not end its beat | story runtime ×4 |
| R7 | the story keeps listening after its session | story runtime |
| R8 | an Origin's kit given item by item | story runtime (kit that does not fit) |
| R9 | a failed start stays wired | story runtime |
| R10 | a choice announced before it is committed | story runtime |
| R11 | a memory shown over the village | scene band |
| R12 / R13 | a scene takes no modal context / one per step | scene band |
| R14 | the strip stays up under a scene | scene band |
| R15 | the sect advertised to a nobody | HUD |
| R16 | a garment drawn on the wrong body | looks |
| R17 / R18 | two looks one body / a look that starts in a sect, accepted | looks |
| R19 | an Origin with no vignette accepted | story runtime |
| R20 | arriving anywhere is the rupture | story runtime |
| E1 | the menu loses focus after backing out | story E2E (steps 3→4) |
| E2 | Esc in a scene also asks to leave | story E2E (the run never completes) |
| E3 | an Origin's knowledge announced as just learned | story E2E step 6 |
| E4 | backing out starts a run | story E2E step 3 |
| E5 / E6 | the player is enrolled again | world E2E (30 assertions), story E2E steps 5 and 8 |

**A tooling defect, recorded because it touched content.** The mutation helper backed a file
up once per replacement, so a two-replacement mutation of ONE file saved the half-mutated
copy and "restored" to it: after R1 the sect catalog had the start sect back. It was caught
by the post-run check that the catalog still said what it should, the catalog was repaired
(its diff against the base is exactly the intended two lines), the helper now backs each file
up once, and every result produced while the catalog was wrong was re-run.

### Checkpoint 1 — the story and origin foundation (built)

**What exists.** `src/data/story/` (14 resources: ids, flags, conditions, consequences,
triggers, branches, beats, options, choices, chapters, the story catalog with its graph
checks; origin grants, origins, the origin catalog frozen to CL-09's five ids).
`src/domain/story/`: `StoryState` (strict, atomic `to_dict` / `from_dict`; no flags),
`StoryOutcome`, `StoryOwners` (the seams to knowledge, regard and the bag), `StoryService`
(the one writer). `data/story/story_catalog.tres` and `origin_catalog.tres`, generated by
`tools/author_story_data.py` (its `--check` runs in the lint gate). Text for both in
`locale/aetheria.csv`, English and Vietnamese. Three knowledge entries the story names
(`know_survey_fragment`, `know_vein_stone_grades`, `know_survey_notation`).

**What does not exist yet.** No runtime, no scene, no screen, no change to New Game. The
shipped game plays exactly as it did; nothing loads the new catalogs but their tests.

**The authored shape** (`chapter_prologue`, eleven beats that complete, then
`chapter_ke_vo_danh` with one standing beat). Beat 1 of the master plan — character creation
— is the identity screen and happens before a run exists; the record starts at beat 2.

| Beat id | Master-plan beat | Completes on |
|---|---|---|
| `beat_road` | 2 | the Origin's vignette ending |
| `beat_arrival` | 3 | one named person met |
| `beat_contacts` | 4 | three named people met |
| `beat_village_business` | 5 | `flag_heard_village_business` |
| `beat_confidence` | 6 | `choice_lam_readings` answered |
| `beat_warning` | 7 | arrival in `map_field` |
| `beat_night` | 8 | `choice_night_stand` (stood / withdrew) |
| `beat_aftermath` | 9 | `flag_heard_elder_account` |
| `beat_settle` | 10 | a cultivation session yielding |
| `beat_sheet_told` / `beat_sheet_found` | 11 | `know_survey_fragment` held — which of the two depends on beat 6's answer |
| `beat_leaving` | 12 | `flag_heard_road_ahead` |
| `beat_standing` | Act I | — (the story rests) |

**A defect the tests found in the first draft of the content.** Four authored regards were
negative moves on `trust` and `respect`, which stop at 0: consequences nobody could ever
have felt. They are on `affinity` now, and a test holds every falling regard to a dimension
that can go below zero.

**Gates on this checkpoint's tree:** see the gate table below; mutations: 23 applied, 23 red
(two survived their first round and showed two tests that could not fail — a loop whose only
symptom was an unreachable beat, and a pass-through that one pass happened to satisfy; both
tests were rewritten).

| # | What was broken | Red in |
|---|---|---|
| S1 | the story record repeats flags | no-duplication, bad-record |
| S2 | a choice recorded before its owners are checked | missing-owner |
| S3 | a choice can be answered twice | second-answer, round-trip |
| S4 | a choice answered outside its beat | wrong-beat, shipped walk |
| S5 | an Origin's kit given before the bag is asked | refused-begin |
| S6 | a run can begin twice | kit-once |
| S7 | any event completes any event beat | event-only-while-current |
| S8 | an event's subject ignored | subject, shipped walk |
| S9 | only one beat passed per call | pass-through-in-one-call |
| S10 | an undeclared flag accepted | undeclared-flag |
| S11 | a flag value unbounded | undeclared-flag |
| S12 | loading ignores the character's flags | record-beside-flags |
| S13 | an unexpected key accepted | bad-record |
| S14 | the first branch always taken | branch-and-converge ×2, shipped walk |
| S15 | meeting counted every time | meeting-once |
| D1 | a non-ASCII id accepted | ids, Cyrillic look-alike, origin catalog |
| D2 / D3 | a sixth Origin / a missing Origin accepted | origin catalog |
| D4 / D5 / D6 | an unreachable beat / a loop / a dangling next accepted | catalog graph |
| D7 / D8 | a blank objective / a conditional last branch accepted | beat |

*(gate tables, mutation lists, captures with their real sizes, playtest runs and first-play
pacing are added by the checkpoints that produce them)*

## 12. Status

Checkpoint 2 built: New Game is the identity screen, the player is a nobody with an Origin,
and the run opens on its vignette and the arrival. Beats 4–12 are not built.
**Phase 20 is NOT DONE.**
