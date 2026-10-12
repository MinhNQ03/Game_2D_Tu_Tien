# Handoff — Post-Phase-20 experience hardening / pre-Phase-21 gate (D-073)

> **Status: DONE — all five checkpoints built, every local gate green, the capture matrix
> opened.** This was a bounded quality pass between two phases. **It is not a phase.**
> Phase 20 (Story) is and stays **DONE** under D-072; Phase 21 (Dungeon) and Phase 22 (Boss)
> are **NOT STARTED** and nothing here builds them. **No person has played this build** —
> see H21-14 and the checklist in §11.
>
> **Integration, as it stands (corrected by the follow-up, §15).** When this pass closed the
> branch was pushed and unmerged and `origin/main` was still its base, `4dd38ec`. The owner
> then fast-forwarded `main`: `main` and `hardening/pre-phase21-experience` are both
> `4358c78d6d29fec259d342b1005ba627bcc0a34d` (CI run 38149535941 on `main`, success, checked
> with `gh` after a fresh fetch on 2026-10-11). `4dd38ec` remains the historical BASE of the
> pass. A follow-up close-out on `hardening/pre-phase21-closeout` continues from `4358c78`
> and is recorded in §15.
>
> **Current state (dated addendum, 2026-10-12 — see §1a and §16).** `4358c78` is no longer
> where `main` is. Read §1a for what the refs point to now; the paragraph above is kept as the
> record of 2026-10-11.

## 1. Baseline (verified, not assumed)

| | |
|---|---|
| Branch | `hardening/pre-phase21-experience` — the ONE branch of this task |
| Base (HISTORICAL: true at this pass's preflight, not now) | `4dd38ec4d35650c35f69be93c234f9db1ca1fcf6` = `origin/main` = `origin/feature/phase-20-story` at preflight (2026-10-11, after `git fetch --prune`). `main` has since been fast-forwarded to `4358c78` |
| CI on the base | run 38132418506, branch `main`, `head_sha` `4dd38ec…`, success (read back with `gh run view`) |
| Other refs at preflight | local `main` `4420eae` (8 behind `origin/main`, untouched); `origin/feature/phase-19-quest` `b768935`; `origin/d063/phase-a` `8f3ccbd`; `origin/fix/pre-phase20-readiness` `4420eae`; no tags; one workflow (`ci.yml`) |
| Phase state on the base | `ROADMAP.md`: Phase 20 DONE, Phase 21+ NOT STARTED. No dungeon / boss code or data in the tree |
| Local baseline before any edit | on the base tree: import clean; **1188 / 1188** tests, 0 `SCRIPT ERROR`, 0 leak lines (either wording); Story E2E `RESULT: PASS` |
| Real window before any edit | `tools/capture_ui.gd -- vi` at 1280×720: 36 captures, exit 0. Opened: `23_night_wave_and_wreck`, `22_night_rupture_caption`, `26_chronicle_page_2`, `26_chronicle_page_4` (what they show is in §2) |

`CLAUDE.md` is user-owned and untracked. It is never staged, moved or edited by this task.

### 1a. Current state — addendum of 2026-10-12 (the table above is history and is not edited)

Read back with `git fetch --all --prune`, `git rev-parse` and `gh run list` on 2026-10-12,
at the preflight of Gate A (§16):

| Ref | Points to | Against `main` |
|---|---|---|
| `origin/main` | `33919f9e41996393aec91df2dc124cb8fa2bda04` | — |
| `origin/hardening/pre-phase21-closeout` | `33919f9e41996393aec91df2dc124cb8fa2bda04` | equal (the owner fast-forwarded `main` to the close-out's tip; no merge commit) |
| `origin/hardening/pre-phase21-experience` | `4358c78d6d29fec259d342b1005ba627bcc0a34d` | behind: an ancestor of `main`, not a base for new work |
| `hardening/pre-phase21-gate-a` | branched from `33919f9` for §16 | ahead by §16's commits; **not merged** — merging is the owner's |

CI on `main` at `33919f9`: run **38198759321**, event `push`, success. (The close-out branch's
own run on the same SHA: 38197905280, success.) `4dd38ec` stays the historical base of the
first pass and `4358c78` the historical tip of that pass and base of the close-out.

## 2. Findings (what was looked at, and what it costs the player)

Severity per `PLAYER_EXPERIENCE_STANDARD.md` §5. "Seen" means a capture of the real window
was opened, or the code path was read and is cited; nothing below is taken from a report.

| ID | Sev | What is wrong | Evidence | Player cost | Owner | Closes at |
|---|---|---|---|---|---|---|
| H21-01 | **P1** | Act I begins with *Find the true vein survey* and no person, place or key in the game advances it | `beat_standing` is `terminal`; no dialogue line, source or quest reads it | "now what?" one minute after the prologue's best scene: a dead end | Story content | CP1 |
| H21-02 | **P1** | A story choice can be half-applied: `StoryService.choose` checks only that an owner seam EXISTS, appends the choice, then carries consequences out and merely logs a refusal | `story_service.gd` 287–294 on the base | a decision recorded with one of its two regards unmoved; a retry is refused as "already chosen" | `StoryService` / `StoryOwners` | CP1 |
| H21-03 | **P1** | The Night is daylight. `23_night_wave_and_wreck`: a green sunlit wood, HUD line "Sống sót qua đêm trong rừng" | capture opened | the game's inciting event is asserted by a caption and contradicted by the picture | presentation | CP2 |
| H21-04 | P2 | The "abandoned cart, crates split" is the upright cart with its load roped down | same capture: wheels on, tarpaulin tied, crates whole | evidence the story says exists is not on screen | art pipeline + map | CP2 |
| H21-05 | P2 | The Night's creatures are pixel-identical to the woods' own wolves | same capture; `spawn_table_field_night` reuses `enemy_mist_wolf` and its profile | "they are not themselves" cannot be seen | art + spawn-table data | CP2 |
| H21-06 | P2 | The removed survey stake leaves nothing: the scene says "the hole has been raked over", the ground is unchanged | `field_map.tscn` — `SurveyStake` only disappears | a claim the map does not show (PX-7) | art + map | CP2 |
| H21-07 | P2 | People page: `Thiện cảm -10 · Tin cậy 0 · Kính trọng 0` for three people in a panel two-thirds empty | `26_chronicle_page_4` opened | numbers with no scale and no cause; the choice that moved them is not connected to them | Chronicle | CP3 |
| H21-08 | P2 | "Who you were" shows only the Origin. Level, body, realm, equipment, techniques and companion are scattered or nowhere | `26_chronicle_page_2` opened | no single place to read one's own character | Chronicle | CP3 |
| H21-09 | P2 | The story page shows the newest six records; older ones cannot be reached | `ChroniclePanel.MAX_RECORDS = 6` | the book forgets the beginning as the story grows | Chronicle | CP3 |
| H21-10 | P2 | The Chronicle's key is printed only inside the Chronicle | prompt strip has no row for it (measured full in Phase 19) | a book nobody knows they own | HUD / story | CP3 |
| H21-11 | P2 | What an Origin alone noticed about the carter's load is said once and kept nowhere | `flag_te_origin_said` has no reader but the dialogue gate | the run's most personal clue cannot be re-read | Story view / Chronicle | CP3 |
| H21-12 | P1? | Pressing `cultivate` while a swing recovers: `_try_sit` starts the sitting, the same tick's `_interruption()` ends it as `attacked`. Whether a recovery can stay unfinished across a scene / map change was never measured | `cultivation_runtime.gd` 286–322 read; E2E 8f waits for `READY` | a key press that appears to do nothing (PX-4: nothing fails silently) | Cultivation / Combat | CP3 — **reproduce first** |
| H21-13 | P3 | Status drift: the Phase-20 handoff's header says `IN PROGRESS` and its tables say *planned*; `GAME_FLOW.md` (two places), `SYSTEM_DEPENDENCY_MATRIX.md` (Story row) and D-072's status line still describe a phase under way | read | the next reader starts from a false state | docs | **CP0 (this commit)** |
| H21-14 | — | Nobody but tools has played beats 3–12 | Phase-20 handoff §11 | "engaging" is unproven | the project owner | **stays open** — §11 gives the checklist |

Scope rule applied: P1 in shipped systems are fixed; P2 are fixed because the brief names each
of them and each is small and owned by a shipped system; nothing is pulled forward from
Phase 21+.

## 3. Gate A — what the player knows when the prologue ends

Every statement the opening makes is one of four kinds. A contradiction between two rows is
intended only where the last column says so.

| Kind | Statement | Where the player gets it | Contradicts (on purpose) |
|---|---|---|---|
| **FACT** (seen) | The vein under Rừng Vỡ Mạch broke at night; the wolves that drank from it went mad | the Night, played | — |
| **FACT** | A cart was left in the woods with its crates split, and what spilled was not pine | the wreck and what lies by it | the carter's "Pine." |
| **FACT** | A survey stake stood in the clearing before the Night and is gone the morning after; the ground was raked | the map, before and after | the elder's "there was never a stake" |
| **FACT** | A torn survey sheet, in a surveyor's hand: readings that fall season after season, and beside them the figure sent up — *level* | `know_survey_fragment` | the outpost's book |
| **CLAIM** — Thẩm Bất Kỳ | Heterodox cultivators broke the vein; "you will say the same" | `DLG_SHEN_NIGHT` | nothing the player holds proves or disproves it |
| **CLAIM** — Thẩm Bất Kỳ | "There was never a stake in those woods" | `DLG_SHEN_NIGHT_STAKE` | the FACT above — the elder is saying something the player watched be untrue |
| **CLAIM** — Lâm Nguyệt | The book has said *level* for six seasons and her rod disagrees; the surveyor before her was "reassigned" last winter | `DLG_LIN_MEASURE`, `DLG_LIN_CONFIDE` | the outpost's book |
| **CLAIM** — Kha Thản | Some nights he is paid to sleep soundly; this morning he wonders who was paying | `DLG_KO_CART`, `DLG_KO_NIGHT_LEFT` | — |
| **CLAIM** — Tề Mộc | "Pine." / "Ask where the crates were sent." / (to one Origin only) what that Origin noticed is a mistake | `DLG_TE_*` | the FACT of the spill; his own first claim |
| **INFERENCE** (the player's) | The outpost knew the vein was falling and reported that it was not; somebody removed the stake to hide that it was ever surveyed | — | — |
| **OPEN** | Who was drawing the vein, and for whom. What was in the crates. Where they went. Who paid the watch to sleep. Whether anyone meant it to break. Where the rest of the survey is | — | — |

**Reveal ladder.** The prologue and this bridge stay on layer 1 (*something is wrong*) with a
handle on layer 2 (*someone caused it*) that the player cannot yet turn. Nothing names the
heterodox extraction, the Vân Hải buyer, the Thiên Khế or the Tà Đế; no culprit is shown; no
character explains the lie. `NARRATIVE_MASTER_PLAN.md` §9 and D-072 §5 are unchanged.

**Who the player still is.** An ordinary, unaffiliated newcomer: no sect, no prophecy, no
reincarnation, no inherited power, no morality value, no early answer to "Tà Đế".

## 4. Gate A — the Act-I bridge (*planned*; D-073 §1)

**The gap.** The prologue hands the player a torn page and the sentence *find the true survey*.
Nothing in the game answers to it.

**What the player can do next, in one line.** Take the page to someone who might know it —
choosing WHOM is the decision — then go and look where it was written, and find the door the
book says is shut.

```
standing objective        "Ask who wrote the sheet"
choose whom               Lâm Nguyệt · Kha Thản · Thẩm Bất Kỳ   (one is the FIRST to be shown)
real input                walk, talk, pick the line
evidence or refusal       each tells a different thing; she refuses someone who told on her
owner-backed consequence  a regard moves (Relationship); a thing becomes known (Knowledge);
                          the decision is recorded once (Story)
next destination          the place the stake stood → the wheel ruts → the sealed Survey Shaft
```

### 4.1 The beats (chapter `chapter_ke_vo_danh`, Act I)

| Beat | Objective (plaque) | Completes on (read from an owner) | What the player does | Tangible result |
|---|---|---|---|---|
| `beat_whose_hand` — entered with the existing `scene_road_ahead` | Ask who wrote the sheet | `choice_sheet_shown` is recorded (Story) | shows the sheet to ONE of three people first | that person's regard moves; one piece of knowledge, different per person |
| `beat_stake_line` | Look where the stake stood | `know_stake_socket` held (Knowledge) | walks to the clearing, examines the raked socket | the stone collar is still in the ground, numbered; wheel ruts cross it, running north-east |
| `beat_ruts` | Follow the ruts north-east | `know_sealed_shaft` held (Knowledge) | follows the ruts past the wreck to the rocks, examines the door | the Survey Shaft: boarded, sealed in the outpost's wax — and the wax is days old |
| `beat_standing` (kept id; terminal) — entered with `scene_shaft_sealed` | The Survey Shaft needs a surveyor's rod | — (the story rests) | — | the lead Phase 21 opens (§10) |

`beat_standing` keeps its id (ids are permanent) and stays the story's resting beat; what
changes is that three beats now stand between the farewell and it, and its objective names a
place and a condition instead of an abstraction. A state trigger counts what was already done:
a player who examined the socket before showing the sheet to anyone passes `beat_stake_line`
the moment it is entered.

### 4.2 The one decision: who sees the sheet first (`choice_sheet_shown`)

One `STORY_CHOICE` (D-072 §7), bound to no beat (addendum C: a decision is never refused for
being early — it becomes possible the moment `know_survey_fragment` is held). It is answered
by the FIRST showing; the others can still be asked afterwards and answer in character, with
no second consequence.

| Option | Offered when (state, never a private boolean) | They say (a CLAIM) | Consequences (through owners) | Why it costs or pays |
|---|---|---|---|---|
| `lin` | she was NOT told on (`flag_lam_settled` ≠ 2) | it is the old surveyor's hand; a survey is a LINE of four stakes from the road to the place he sounded the vein; the page is from stake three | Lâm Nguyệt `trust` +10; teaches `know_surveyors_line` | she is the one person who can read it, and the one with most to lose |
| `ko` | always | on the nights he was paid to sleep, wheels passed the third stake and did not come back by the road | Kha Thản `trust` +5; teaches `know_night_wheels` | he sells what he knows; today he gives it, because he wants to know who paid him |
| `shen` | always | "That page was never written." The old shaft has been under seal since winter; nothing is there | Thẩm Bất Kỳ `affinity` −10; teaches `know_shaft_claim` | he now knows the player holds it — and in denying it he names the place |

**Refusal that is not a dead end.** A player who told the elder about Lâm Nguyệt's readings is
refused by her ("You have a sheet, and I have no rod. Show it to the one you gave my rod to.")
— nothing is recorded, and two other people remain. Declining to show anyone is not recorded
either; the objective stays, the three people stay, nothing is lost.

**Why this is not a fetch quest or "talk to three people".** One conversation is enough; the
choice is exclusive in what it costs; the three answers are three different pieces of one
picture, and two of them (the elder's "sealed since winter", the watch's "wheels that did not
come back") contradict each other until the player stands in front of the door.

**Earlier choices are read, not re-asked.** `kept` / `told` decides whether Lâm Nguyệt will
look at the page at all. `stood` / `withdrew` decides which of two lines Kha Thản gives with
the same answer. All five Origins and both looks reach the same three beats and the same door.

### 4.3 What an Origin notices (once each; all five converge)

After the door is found, ONE line opens for each Origin with the person it concerns, said
once (`flag_trail_origin_said`), changing nothing but what is on the record. Two are opened
by what the Origin KNOWS (the Knowledge Core's answer), three by who they were. *(Built in
Checkpoint 1. Gate A had two of them with Lâm Nguyệt; they were moved, because she does not
speak to someone who told on her and no Origin's line may depend on an earlier decision.)*

| Origin | Opened by | With | What only they notice (an observation, then a CLAIM in reply) |
|---|---|---|---|
| Thủ Thư Cấm Lục | `know_survey_notation` | Thẩm Bất Kỳ | the word *level* on the sheet is in a second hand — and he was told to expect someone who could see that |
| Nghệ Nhân Thất Sủng | `know_vein_stone_grades` | Kha Thản | the stones he is paid in have raw bases: nobody ever counted them |
| Hộ Tiêu Thất Bại | Origin | Kha Thản | the ruts are shallow going up and deep coming down — as on the morning the convoy was lost |
| Lang Y Du Phương | Origin | Kha Thản | the watchman's nails are clean; whatever greyed the carter's hands, the watch never handled it |
| Đệ Tử Bị Loại | Origin | Kha Thản | the cord on the seal is tied with the examiners' knot; "cord like that comes up from Cloud Vale ready-tied" |

Each is an authored consequence of a past life, not a vision; none names a culprit. Both
Origin observations (this one and the Phase-20 one about the carter's load) become READABLE:
`OriginData.observations` pairs a story flag with a record key, and the Chronicle lists the
ones whose flag is set (closes H21-11).

### 4.4 Non-deadlock rules (each gets a test)

- The sheet is knowledge, not an item: it cannot be lost, sold, dropped or crowded out by a
  full bag. Nothing in the bridge needs bag space.
- A wolf already dead, or every wolf dead, changes nothing: no bridge step counts a defeat.
- A person asked twice answers once: the choice is recorded once; later showings are plain
  lines gated by the record.
- The socket and the door are in the map from `flag_night_over` on, so either can be examined
  before its beat; the beat is then passed on entry.
- A refused choice (H21-02) leaves the conversation on the same node with a reason and can be
  retried.

### 4.5 What the bridge does NOT build

No dungeon map, room, instance or runtime; no boss; no loot or drop table; no key item; no
save, Continue or autosave; no new autoload or manager; no quest ledger, XP balance,
knowledge set or relationship score of its own; no morality value. The door does not open.

## 5. Every new thing, its reason, its owner (*built* — Checkpoint 1; the Night's rows follow in Checkpoint 2)

Placement reasons (PX-2) and traceability (id · source · cause in the world · what the player
does with it · the ONE owner of what it changes · keys · payoff or "no callback").

| Id | Kind | Belongs to | Why it is where it is | Player use | State owner | Payoff |
|---|---|---|---|---|---|---|
| `choice_sheet_shown` | story choice | the player | — | first showing of the sheet | Story (record) → Relationship, Knowledge | Phase 21: who is on the player's side at the door |
| `know_surveyors_line` | knowledge | Lâm Nguyệt's telling | she reads the hand | Chronicle; opens nothing by itself | Knowledge Core | Phase 21: stake four is the shaft |
| `know_night_wheels` | knowledge | Kha Thản's telling | he was there, asleep on purpose | Chronicle | Knowledge Core | Phase 21: the door was in use |
| `know_shaft_claim` | knowledge (a recorded CLAIM) | Thẩm Bất Kỳ's telling | he denies the page and names the place | Chronicle | Knowledge Core | contradicted at the door |
| `know_stake_socket` | knowledge (observed) | the forest floor | where the stake stood, `SurveyStake`'s own position | examined with `interact` | Knowledge Core | the direction of the ruts |
| `know_sealed_shaft` | knowledge (observed) | the outpost (its seal) | the north-east rocks: the rock region the layout already has; the ruts lead there from the wreck | examined with `interact` | Knowledge Core | the Phase-21 entrance |
| `StakeSocket` | map prop + source | the outpost's survey | exactly where `SurveyStake` stood; appears when the stake goes (`flag_night_over`) | walk up, read | — (a source grants knowledge) | — |
| `SurveyShaft` | map prop (solid) + source | the outpost; older than it | set into the NE rock face, off every road: a place meant not to be walked past | walk up, read; it does not open | — | Phase 21 replaces "read" with "enter" |
| wheel ruts | ground decal (intangible by design) | the carter's cart | from the wreck to the shaft: the load came from there | follow by eye | — | — |
| `flag_trail_origin_said` | story flag | Story | — | gates the once-only Origin line | Story (flags on the player's `CharacterState`) | — |
| `scene_shaft_sealed` | story scene | — | at the door, when it is found | read or skip | none (a scene changes nothing) | — |

Looks-usable rule: the socket and the door each carry an `interact` prompt and answer it; the
ruts are drawn flat, under the y-sorted world, with no prompt and no body
(`INTANGIBLE_BY_DESIGN`); the wreck is solid where it is drawn (§6).

**As built (Checkpoint 1) — ids, sources and keys.**

| Id | Authored in | `vi` / `en` keys | Notes |
|---|---|---|---|
| beats `beat_whose_hand`, `beat_stake_line`, `beat_ruts`; `beat_standing` (kept) | `tools/author_story_data.py` (`ACT_ONE`) → `data/story/story_catalog.tres` | `STORY_BEAT_{WHOSE_HAND,STAKE_LINE,RUTS}_{OBJECTIVE,RECORD}`; `STORY_BEAT_STANDING_OBJECTIVE` (reworded: *Find a rod for the shaft*) | every objective measured to fit the plaque's one row in both languages by the shipped test |
| `choice_sheet_shown` / `lin`, `ko`, `shen` | same (`CHOICES`), bound to `beat_whose_hand` | `STORY_CHOICE_SHEET_SHOWN[_LIN/_KO/_SHEN]` | bound to its beat on purpose: the conversations offer it only after the farewell (a flag), so the beat is entered and its scene told first |
| flags `flag_sheet_shown` (INT 1..3), `flag_{lin,ko,shen}_sheet_said`, `flag_{lin,ko,shen}_shaft_said`, `flag_trail_origin_said` | same (`FLAGS`) | — | one writer (`StoryService`), stored on the player's `CharacterState`; each gates a line said once |
| `scene_shaft_sealed` (two captions, told over the place) | same (`SCENES`) | `STORY_SCENE_SHAFT_1/2` | entry scene of `beat_standing`; `scene_road_ahead` moved to `beat_whose_hand` |
| five knowledge entries (table above) | `data/knowledge/knowledge_catalog.tres` | `KNOW_{SURVEYORS_LINE,NIGHT_WHEELS,SHAFT_CLAIM,STAKE_SOCKET,SEALED_SHAFT}_{NAME,DESC}` | three RECORD (told), two OBSERVATION (examined) |
| 20 conversation choices and 20 lines over three people | `data/dialogue/dialogue_catalog.tres` | `DLG_{LIN,KO,SHEN}_*`, `DLG_CHOICE_{SHAFT,BACK}` | a conversation OPENS on its trail line once `know_survey_fragment` is held and `flag_heard_road_ahead` is set; the hubs gained no entry (the box is measured full at five) |
| `KnowledgeSources/StakeSocket`, `KnowledgeSources/ShaftSeal` | `src/gameplay/maps/field_map.tscn` | prompt `UI_HUD_EXAMINE_ACTION` (new; the sheet under the stele used to say *Read stele*) | each appears with `flag_night_over`; examined with `interact` |
| `Prop_SurveyShaft` at (896,184); `RockNE1`, `RockNE2`, `PineE2` moved to frame it; the haul track | `designs/maps/vo_mach.yaml` → `sync_scene.py`, `ground.py` | — | see "Placement, as seen" below |

**Numbers introduced, each with its one home.**

| Value | Where it lives | Why this value | Boundary tested |
|---|---|---|---|
| first-showing regard: Lâm Nguyệt `trust` +10, Kha Thản `trust` +5, Thẩm Bất Kỳ `affinity` −10 | `tools/author_story_data.py` `CHOICES` | a confidence given (+10 to the one with most to lose, +5 to one who trades in such things) and a threat registered (−10); the fall is on the only dimension that can fall; all far inside `StoryConsequenceData.MAX_DELTA` (50) | the shipped-content scan (falling regard on a dimension that can fall); a 0 move is refused by the catalog (mutation B6) |
| `flag_sheet_shown` ceiling 3 | `FLAGS` | one value per person who can be shown it | a value above a flag's ceiling is refused (shipped test) |
| reach of the socket 20 px, of the seal 22 px | the scene | the socket is a flat mark stood ON; the seal is read from the sill, outside the door's body | `test_solid_props_never_block_the_play` (an anchor is never inside a body); E2E 8i walks into both |
| haul track width 11 px | `vo_mach.yaml` | one cart wide, visibly narrower than the 18–28 px paths: an old way, not a road | — (art) |

**Placement, as seen in the real window.** The first placement put the door at (884,128), in
the rock patch's middle. Captured at 1280×720 it was UNDER the place plaque: in the map's
top-right corner the camera stops at the edge, so the plaque covers world x 841–967, y 25–110.
Moved to the patch's south lip (896,184), the door, its seal and stake four are clear of the
HUD at both aspect ratios. The stake's socket was first drawn darker than the leaf litter and
could not be found at 1×; it is now pale turned earth ringed with dark clods.

**A risk left in on purpose.** The haul track passes the cairn where one of the woods' own
Vụ Lang lives (detect radius 170 px): reaching the door means meeting it or going round over
the open ground to the south. It is the shipped creature with its shipped telegraph, already
fought in the prologue.

## 6. Gates C–F — what each fix is held to (*planned*)

**C — the choice transaction (H21-02; D-073 §2).** First a test that injects an owner whose
SECOND consequence refuses and shows, on the base code, the choice recorded and the first
consequence applied. Then: `StoryOwners` gains two PREPARE seams (`can_teach`,
`can_move_regard`) answered by the owners' own rules; `choose` asks every prepare before it
writes anything, carries the owners' consequences out, and writes its own record and flags
LAST. A prepare that says no refuses the whole choice with a localized reason and leaves the
conversation where it was. No transaction framework, no manager; the story still never
touches another owner's fields.

**D — the Night (H21-03…06; D-073 §3).** An AMBIENCE is presentation derived from the story's
current beat (`StoryBeatData.ambience_id` → a profile in `data/world/ambience/`, generated
from new night roles in `style/aetheria_style.yaml`): a canvas tint, banded light at the
lanterns and at the broken vein, and a short transition. Nothing stores "it is night"; the
simulation clock is untouched. The wreck is a new prop built by the prop pipeline (a wheel
off, the bed down on its axle, crates split and spilled) that the story's presence selects in
the woods; the standing cart in the village is unchanged. The socket and the ruts make the
removal physical. The Night's creatures get their own sheets from the beast generator (raised
hackles — a silhouette change — and the vein's light in their flanks and eyes), named by the
ENCOUNTER's spawn table, not by the renderer; stats, AI, bite timing and hitbox are the
shipped wolf's.

**E — the Chronicle (H21-07…11; D-073 §4).** Still one read-only book fed by owners. People:
each dimension by name with a word for where it stands and its number, never summed; under a
person, the recorded decision that concerned them. Self becomes two pages — who you are (look,
Origin, what you came for, what only you noticed) and body-and-path (HP, level, XP, realm and
progress, combat stats, what is worn, techniques and their cost, the companion, the place) —
each line read from the owner that holds it. History: the first page shows the newest records
that fit; older ones are on further pages reached with the same key. The key is taught once,
by a notice the story's own once-only event raises, with the label `InputService` reports.

**F — cultivate during a swing (H21-12).** Reproduce in the real window first: one attack,
`cultivate` pressed in each phase, then at `READY`; and across a scene and a map change.
Decide from the combat and cultivation contracts whether sitting mid-swing is legal. If it is
not, the refusal is said at once in words and the next valid press sits; if a recovery can
hang, the layer that hangs is fixed. No timer, no story reach into combat.

## 7. Cross-system contracts kept (recorded for Phase 21/22)

- The player is one `CharacterState`; Origin and story state are per run and per player
  (`NARRATIVE_MASTER_PLAN.md` §14); map, world, instance and social state stay with their
  owners. No networking is added.
- A dungeon or a boss, later, is an INSTANCE or an ENCOUNTER with its own id and its own
  outcome — as the Night already is (`field_night`, per-spawn ids, the answer recorded per
  player by `choice_night_stand`). It is never a global boolean such as `boss_defeated` that
  could complete another player's story. Nothing of the kind is added here.
- Five autoloads; no global Quest / Story / Dungeon manager; `presentation → gameplay →
  domain → data`; `SESSION_START_ORDER` and the reverse-order unwind are unchanged.
- No file save, Continue or autosave before Phase 23; `to_dict` / `from_dict` stay in-memory.
- One `RewardLedger`; no drop, no second currency or XP owner.
- Catalogs fail closed on an unknown id, a dangling condition, a missing translation, owner,
  map, item or visual profile.

## 8. Evidence required before close (*planned*)

Automated: every existing gate; a red-first test for each fix; the story transaction under an
injected refusal; the bridge with real keys from the farewell to the door, both branches of
each earlier decision; all five Origins through public seams and at least one real-key opening
each; attack → cultivate in each phase; presence of the wreck, the socket and the door against
the story; the Chronicle's pages; determinism and no duplication across repeats and map
changes; malformed content; teardown; mutations counted.

Real window: `capture_ui.gd` and `playtest_flow.gd` at vi / en × 1280×720 / 1280×800, the
images OPENED and described, sizes recorded, under the scratch path, not committed.

Human: §11. A tool-driven run is not a human one, and nothing here will be called engaging
until a person has played it.

## 9. Checkpoints

| # | Scope | Commit | CI on that exact SHA |
|---|---|---|---|
| 0 | Audit, Gate A, D-073, status drift corrected. No gameplay code | `1fa3011` | 38134053360 — success, `head_sha` `1fa3011e53ddfe1fb7e88fafd24b3727a67bd71d` |
| 1 | The Act-I bridge and the choice transaction | `7f900c9` | 38135850806 — success, `head_sha` `7f900c9b075e487def943e1d07016631dbbd7f48` |
| 2 | The Night: ambience, the wreck, the socket and track, the creatures | `b857b4d` | 38146160332 — success, `head_sha` `b857b4d8187889ff9a61be11a05d295884e20186` |
| 3 | The Chronicle and the cultivate / recovery rule | `2547b4e` | 38148365891 — success, `head_sha` `2547b4efb041a317e252a93c44e04647cd4c6d27` |
| 4 | Full regression, the capture matrix, docs, debt register, Phase-21 handoff | *(this commit)* | verified with `gh` on that exact SHA and reported in the closing message; a commit cannot name its own run |

## 10. The Phase-21 handoff (what the dungeon is authored AGAINST)

**Where the player stands when Phase 21 begins.** In front of a boarded, sealed door in the
north-east rocks of Rừng Vỡ Mạch, holding one page of a survey, knowing what kind of key the
door takes, and having decided who saw the page first. The story rests on `beat_standing`
(*Tìm thước mở Hầm Khảo Mạch*). Phase 21 continues FROM that beat: its first beat is the next
entry in `ACT_ONE`, and `beat_standing` stays the story's resting beat at the end of whatever
it adds.

**The lead.** The Survey Shaft (*Hầm Khảo Mạch*, reserved id `dungeon_survey_shaft`,
`CANON_LEDGER.md` CL-11): the fourth point of the Thanh Đài survey line. On paper sealed
since winter; in fact used within days of the Night (fresh wax, wheel ruts to the sill).

**Why the player goes in (narrative).** The rest of the survey they hold one page of — the
field book the old surveyor kept where he measured, never in the hall. **Why they go in
(gameplay).** The first authored, concentrated challenge: the place the vein was actually
drawn from, where the woods' creatures are what the Night made of them.

**What the dungeon may establish, and what it may not.** It may show THAT the shaft was
worked and what was taken out (reveal layer 2: *someone caused it* — evidence, not a
confession). It may not name the Vân Hải buyer, the heterodox group, the Thiên Khế or the Tà
Đế, and it may not have a character explain the lie (`NARRATIVE_MASTER_PLAN.md` §9; D-072 §5).
What is found is INFORMATION — the survey — not power.

**Access (legible before passable — already true in the build).**

| Run | State the conditions read | How the door opens (to author) |
|---|---|---|
| kept Lâm Nguyệt's confidence | `flag_lam_settled` = 1; she has said "I still have mine… when they are gone, I go down with you" if told of the door (`flag_lin_shaft_said`) | she brings the rod: a companion-at-the-door beat, not a key item in the bag |
| told the elder | `flag_lam_settled` = 2; her rod is "in the elder's chest" | the rod must be earned back or taken — a different first beat that reaches the SAME door |
| who saw the sheet first | `choice_sheet_shown` (lin / ko / shen) | colours who is on the player's side at the door; must not gate entry |

No level gate (`MAP_DUNGEON_DESIGN.md` §3). At least one gate is the rod (item / story); a
second may be knowledge (`know_surveyors_line` / `know_sealed_shaft` are already held).

**Exit and revisit.** A way out at any time (ROADMAP Phase-21 contract); leaving mid-way is a
recorded state of the INSTANCE, not of the story. Revisit reasons to author (≥ 2,
`MAP_DUNGEON_DESIGN.md` §9): the book is found in parts; a sealed lower level that a later
realm can stand in.

**The boss (Phase 22) — narrative purpose only.** Whatever the over-drawn vein made of the
thing that lived nearest it: the Night's creatures' cue (raised hackles, the vein's light) is
the visual seed, and its defeat must have a post-boss WORLD consequence (the shaft can be
read; the outpost can no longer say it was sealed) — recorded per player.

**Contracts it must reuse, not rebuild.**

| Need | Use | Not |
|---|---|---|
| beats, choices, flags | `StoryService` via `tools/author_story_data.py`; a choice with consequences is prepared with its owners (D-073 §2) | a quest-side copy of a story flag |
| "this exists because of the story" | `StoryPresence`; layout `story_props`; `WorldItem.appears_with_flag` | a second map version |
| an encounter with an outcome | `StoryBeatData.encounter_*` + a TAGGED spawn table → `CombatRuntime.spawn_from_table`; the answer recorded by `StoryRuntime.choose` | a global `boss_defeated` / `dungeon_cleared` boolean — an outcome belongs to an INSTANCE with its own id and to the player who was in it |
| a creature seen differently | `EnemySpawnTableData.visual_profile` | a second `EnemyData` with copied rules |
| how the place is lit | `StoryBeatData.ambience_id` + a new entry under `ambience.states` in the Visual DNA (a shaft is dark by the same data) | a tint in a scene or a script |
| rewards | the ONE `RewardLedger`; drops (Phase 21 owns them) paid through it | a second XP / currency / item owner |
| what the player reads back | the Chronicle (records, people, knowledge) | a dungeon journal |
| the instance | a dungeon runtime under `Main/Systems` (ROADMAP) holding INSTANCE state | an autoload; story state in the instance |

Debts it already owns: **CLV-01**, **NAV-01** (the shaft is the first concave space a creature
must path through), and **H21-15** below.

## 11. Owner playtest checklist (to be played by a person; not done by this task)

Launch: `~/Downloads/Godot_v4.7.2-stable_linux.x86_64 --path . --resolution 1280x720` from the
repository root (no exported build exists yet). Start from New Game; no test-only shortcuts.

1. Choose each look and each Origin at least once over separate runs. Is the look recognisable
   at 1×, and is the personal problem clear without any document?
2. Cancel the identity screen, then start a run. No ghost session, no second player.
3. Walk to the first people, speak from more than one side, read the key hints, open the
   Chronicle, equip and use what the story lets you have.
4. Make each trust decision in a separate run. Can you tell what it changed? Does the next
   conversation react without asking again?
5. Notice the warning, go to the woods, weigh the danger, fight or withdraw. Can you tell the
   Night's creatures from ordinary ones, and read their attacks in that light?
6. Come back in the morning. Compare the elder's account with what the ground shows; sit and
   cultivate; find and read the sheet; and go on to the next person or place unprompted.
7. Open every Chronicle page. Did you learn its key before stumbling on it? Read the older
   records; close it while moving and while fighting. Is the HUD still uncrowded?
8. Write down: the first moment you did not know what to do; any key that seemed ignored; any
   prop that lied about being solid or about whose it was; and the moment you became curious
   about the survey. Time to first control, to first fight, to first mystery.

## 12. Evidence

### Checkpoint 4 — full regression, the real window in four combinations, close-out

**Local gates on the closing tree (all green).** `gdscript_lint` (selftest + scan, 362
files) · `author_story_data.py --check` · `build.py ambience-check` · `--import` ·
`parse_check` · boot smoke · the suite **1224 / 1224** · eight E2E flows (app, player, world,
pet, NPC, dialogue, quest, story — the story flow at 20 real-key steps). 0 `SCRIPT ERROR`,
0 leak lines in either wording, no "resources still in use", in every log.

**Real-window playtest, real keys (`tools/playtest_flow.gd`).** Two steps were added for the
bridge: `21a_bridge_shown` (walk to Lâm Nguyệt, she opens on the sheet, ONE real answer
records it, the plaque moves on) and `21b_bridge_walked` (a held move key onto the socket, a
real examine; a held move key STOPPED by the door at y 194.6 against a sill at 192.0; a real
examine; the scene; the standing purpose). The prologue before them is staged through the
story's owner and declared as a setup (each beat is driven with real keys by the Story E2E).

| Language | Window | Steps | Result |
|---|---|---|---|
| vi | 1280×720 | 38 | 38 PASS |
| en | 1280×720 | 38 | 38 PASS |
| vi | 1280×800 | 38 | 38 PASS |
| en | 1280×800 | 38 | 38 PASS |

**Capture matrix (`tools/capture_ui.gd`), generated vs opened.** Scratch path, not
committed. Every file's real dimensions were read back.

| Combination | Files | Real size | Total |
|---|---|---|---|
| vi 1280×720 | 51 | all 1280×720 | 21.2 MB (150–989 KB each) |
| en 1280×720 | 51 | all 1280×720 | 21.1 MB |
| vi 1280×800 | 48 | all 1280×800 | 22.8 MB (the taller window needs three fewer Chronicle pages) |
| en 1280×800 | 48 | all 1280×800 | 22.7 MB |

**198 generated; OPENED and judged: 31** (the rest were not looked at and are not claimed).
By the brief's eight categories:

| # | Category | Opened (combination) | Seen |
|---|---|---|---|
| 1 | New Game / identity / Origins | `04b_identity_origin_3` (en 800) | "Who are you?", two looks with sprite and medallion, five Origins, the chosen one marked ◆ and the focused one framed, problem / gives / costs at the right, nothing clipped. Unchanged by this pass; the other Origin cards and the woman's sprite were NOT re-opened |
| 2 | Arrival, people, dialogue | `32_act1_whom_to_show` (vi 720), `33_act1_she_reads_the_hand` (en 720) | Lâm Nguyệt's medallion, name, title and mood; her line in three rows inside the box; two answers; "Learned: The Surveyor's Line" above it; the plaque already reads "Look where the stake stood" |
| 3 | The trust decision, held items | — | NOT opened in this pass (unchanged since Phase 20) |
| 4 | Warning, Night, wind-up, wreck | `21_night_warning_caption` (vi 720), `22_night_rupture_caption` (vi 720), `23_night_wave_and_wreck` (vi 720, en 800); the wolf sheets at ×6 day and night | dusk, night, banded lantern pools, the vein's pool, the crested creatures next to the plain one, the wreck and its spill. The WIND-UP was seen only as sheet frames, not in the lit scene (H21-18) |
| 5 | Morning, the removed stake | `25_morning_sheet_under_the_stele` (vi 720), `34_act1_where_the_stake_stood` (vi 720) | the village as authored; the pale raked socket with its collar where the stake stood |
| 6 | Cultivation, the sheet, the farewell, the Act-I prompt | `37_act1_shaft_sealed_caption` (vi 720), `36_act1_the_survey_shaft` (vi 720, vi 800), `35_act1_wreck_and_old_track` (vi 720); the mid-swing notice read back from the HUD by the probe | the door clear of the plaque at both ratios, the track to its sill, the caption over the place, the standing purpose. The sitting itself was not captured |
| 7 | Chronicle, journal, bag, dialogue controls | `26_chronicle_page_*`: story, self, body, people (vi 720, each after each fix), body (en 720), people (en 800) | every page inside its panel, no scrollbar, one-line titles, footers with the bound key; "Affinity: cold (-10)", "Trust: a little (+15)" in English. Journal and satchel were NOT re-opened |
| 8 | Collision at altered props, combat after the book, back to menu | `21b_the_sealed_door` from the playtest (vi 720) | the player stopped at the sill with a wolf beside them and the health gauge down to 69 / 100: the door is solid, combat goes on, the strip still offers *Examine* |

**Defects found by opening images in this pass** (each fixed, each with the test it lacked):
the door under the place plaque; a socket that could not be found; the vein burnt out to
white; a charcoal coat lost in the night; half of each Chronicle page unused; a crash when
paging; a clipped last line and a scrollbar; a clipped title. None of the eight was visible
to a green suite.

**Player-facing review (protocol §3), in prose.** *Understandable?* The next thing to do is
always on the plaque and always a place or a person. *Alive rather than scripted?* The Night
now changes what is on screen in four distinct ways; the three people answer differently for
what was done to them. *Predictable?* A refusal always says why. *Why did this happen to me?*
The people page ties a number to the decision that moved it. *Does success mean something?*
The bridge ends at a locked door — honest, but not a victory. *Aetheria rather than a demo?*
A survey, a seal, a rod: the mystery is administrative, which is this world's kind.
Scores (a review aid, not a rule): UX 4 · Visual 3 · Readability 4 · Performance 4 (counted,
not profiled) · Maintainability 4. **Visual is 3**: the world's ground and trees are
unchanged, the wreck's wheel reads as a slab (H21-17), the bite's wind-up was not judged in
the night scene (H21-18), and whether any of it is ENGAGING is unknown (H21-14).

### Checkpoint 3 — the book that explains, and sitting down mid-swing (*built*)

**H21-12, measured before it was touched.** Two questions, two answers.

1. *Can a recovery hang?* The story E2E was instrumented (temporarily) to print the attack's
   state from the last wolf to the spring: it read RECOVERY at six consecutive points —
   through the morning scene, the map change and a whole conversation — with its physics
   processing ON. That is a HARNESS effect: headless, the E2E waits on process frames and
   only a handful of 60 Hz physics ticks elapse in that whole stretch, so 0.22 s of recovery
   never runs out. In the real window a swing is READY 25 ticks after the press, every time.
   **No recovery hangs; nothing in combat was changed.**
2. *What does a player get?* Real window, real keys, 60 Hz, at the Lạc Hà spring: one attack,
   then `cultivate` N physics ticks later.

   | Ticks after the attack | Attack state at the press | Before | After |
   |---|---|---|---|
   | 0–6 | WINDUP | sat, stood `attacked` the same tick, no notice | refused, *Thu chiêu xong rồi hãy tọa thiền.*, 1 frame / 20 ms |
   | 8–11 | ACTIVE | same | refused, same words, 1 frame / 17 ms |
   | 14–22 | RECOVERY | same | refused, same words, 1 frame / 18 ms |
   | 26+ | READY | sat and gathered | sat and gathered |

   For 0.4 s after every swing the key appeared to do nothing. The cultivation state machine
   already says an attack ends a sitting, so a sitting may not BEGIN inside one:
   `CultivationRuntime._try_sit` now refuses with `UI_CULTIVATE_MID_SWING` and starts
   nothing. Asked LAST, after "no method" and "too strong": a reason that will still be true
   when the swing is over is the one to hear (the world E2E held that order). The press is not
   queued; the next one sits. The E2E's wait-for-READY — which had hidden exactly this — is
   replaced by the rule itself: a real swing, a real `cultivate` inside it, the notice
   asserted, then the sitting.

**The Chronicle (H21-07 … H21-11).**

| Was | Now |
|---|---|
| `Thiện cảm -10 · Tin cậy 0 · Kính trọng 0` | per person, each dimension on its own line: *Thiện cảm: lạnh nhạt (-10)*, *Tin cậy: tin đôi chút (+15)*, *Kính trọng: chưa nể (0)* — a word for where the value stands on that dimension's own range (`RegardBands`), then the number; a rivalry, fear or debt only when it is not at its default; under the person, the recorded decision that moved their regard. Never a sum |
| "Who you were": the Origin | **Ngươi là ai** (name, Origin, the problem, what you came for, its edge and cost, *what only you noticed*) and **Thân và đạo** (health, level and XP, realm / layer / tu vi, Attack · Defense · Speed, what is worn with the item's own account of what it changes, techniques with cost and the key bound to their slot, the companion, the place) |
| newest six records, the rest unreachable | every record: the newest fill the first page, the rest are *Chặng trước đó* at the END of the book, reached with the same key |
| the key printed only inside the book | said once — *Đường ngươi đi đang được chép lại. B: mở Sổ Ký Sự.* — when the first conversation closes (the beat `beat_arrival` names the hint and the action; the label is `InputService`'s) |
| an Origin's observation said once and lost | on the *Ngươi là ai* page, both of them, once their flags are set |

*One feed per fact.* Story, Origin, knowledge, people and the three combat stats arrive in
`ChronicleView` from `WorldRuntime` (the stats from the player's own `StatsComponent`).
Health, level, realm, bag, techniques, companion and place are the views the HUD is ALREADY
handed by their owners, passed on to the panel by the HUD's own setters; nothing is asked
twice and nothing is computed in the panel. The people page follows
`RelationshipService.relationship_changed` itself, so a regard moved by a conversation or a
quest shows without the story moving. The book offers no action on anything it lists.

*Pages are packed, not cut.* A block (a person, a record) is never split; blocks are packed
into as many pages as the room needs, measured with the font and the Label's own line
spacing. A closed book lays nothing out.

**Three defects the real window showed and no test had.**
1. *Half the room unused.* The first capture had "Thân và đạo" as four lines over a page
   two-thirds empty, on 14 pages: the room was estimated with a title measured before it had
   a width (an autowrap label then reports a column one letter wide).
2. **A crash (signal 11).** Turning pages in the real application aborted the process. The
   panel rebuilt its labels inside `resized` — which the engine emits while it is still
   sorting containers — and a title that wrapped on some pages changed the body's height
   from page to page, so every turn re-packed the book. The title is one fixed line now and a
   re-measure is deferred until the layout pass has finished. Headless tests never lay out a
   real frame and never saw it.
3. *A clipped last line and a scrollbar.* The estimate left out the Label's `line_spacing`
   (3 px per wrapped row); the layout test passed because it used the same wrong estimate.
   It now compares what the ENGINE laid out (`rendered_height`) with the room, page by page.

**Tests.** Suite **1224** (was 1216): the Chronicle file is 10 tests (was 3) — pages in
order; regard in words and why; a dimension never set is not listed; body and path from the
owners' views (and NOT the bag); a 42-record history paged whole, newest first, every page
fitting AS LAID OUT at 1280×720 and 1280×800 in vi and en, every title on one line; a page
uses its room; a closed book is not rebuilt; an empty book shows no raw key; the bands follow
each dimension's range and all 30 are named in both languages. +1 cultivation (mid-swing in
each of the three phases; the next press sits; an attack still ends a sitting). Story E2E:
the hint (8a: not before, not over a line, said when she finishes, opens nothing, takes no
key), the mid-swing rule (8f), every page read with one real key per page and the people
page following the graph (8g). All eight E2E flows pass; 0 `SCRIPT ERROR`; 0 leak lines.

**Mutations: 18 applied, 18 red — after one survived.** K14 (*the people page is stale after
a change outside the story*) was ALIVE: the E2E now moves a regard through the relationship
owner and reads the book.

| # | What was broken | Red in |
|---|---|---|
| F1 / F2 | sitting mid-swing allowed again / refused without a word | cultivation |
| F3 | an attack no longer ends a sitting | cultivation |
| F4 | mid-swing asked before the lasting reasons | World E2E |
| K1 | the people page sums the dimensions | chronicle |
| K2 | a regard as a bare number | chronicle ×2 |
| K3 | no decision under a person | chronicle |
| K4 | older records dropped instead of paged | chronicle |
| K5 | line spacing left out of the height | chronicle (as laid out) |
| K6 | a closed book rebuilt on every change | chronicle |
| K7 | the whole bag listed as worn | chronicle |
| K8 | the room estimated at half | chronicle |
| K9 | what the Origin noticed is not kept | Story E2E 8g |
| K10 | a signed band read like an unsigned one | chronicle ×2 |
| K11 / K12 / K13 | the hint never said / said over a line / names a hard-coded letter | Story E2E 8a |
| K14 | the people page stale after a change outside the story | Story E2E 8g |

**Real window (opened and looked at, 1280×720 vi; scratch path, not committed).**

| Frame | What is in it |
|---|---|
| `26_chronicle_page_01_story` | *Đường đã qua*: the chapter, *Trước mắt: …* in jade, the two decisions marked ◆, then records newest first; no scrollbar, the last line whole, footer *B Trang sau · Esc Đóng · 1/10* |
| `26_chronicle_page_02_self` | *Ngươi là ai*: Lữ khách / Hộ Tiêu Thất Bại, the problem in three lines, *Điều ngươi tìm: …* in jade |
| `26_chronicle_page_04_body` | *Thân và đạo*: Sinh lực 100 / 100 · Cấp 1 · kinh nghiệm 0 / 20 · Hậu Thiên tầng 1 · tu vi 0 / 40 · **Công 20 · Thủ 9 · Tốc độ 180** · *Đang mang trên người*: Đạo bào Thanh Vân with "Thủ +4" · *Công pháp*: Thanh Phong Chưởng · 10 khí · phím 1; Lôi Chỉ · 16 khí · phím 2 |
| `26_chronicle_page_07_people` | *Người đã gặp*: Thẩm Bất Kỳ — *Thiện cảm: lạnh nhạt (-10)*, *Tin cậy: chưa tin (0)*, *Kính trọng: chưa nể (0)*; Lâm Nguyệt — *dửng dưng (0)*, *tin đôi chút (+15)*, *chưa nể (0)*, and under her *◆ Ngươi giữ kín việc Lâm Nguyệt tự ý đo mạch.* Two people to a page, each a tight group |

Not yet done at this checkpoint: en and 1280×800 in the real window (Checkpoint 4).

### Checkpoint 2 — the Night is shown (*built*)

**What a player sees now, stage by stage** (H21-03 … H21-06):

| Stage | Before this pass | Now | Derived from |
|---|---|---|---|
| warning (village) | daylight, a caption | the village at DUSK: a warm-grey, dimmer playfield; the east road's lanterns lit and guttering | `beat_warning.ambience_id = dusk` |
| arrival in the woods | daylight | the player walks in at dusk and the dark comes down over 0.9 s as the rupture is told | `beat_night.ambience_id = night` |
| the wave | grey wolves in a sunlit wood | NIGHT: a cool, value-compressed wood; warm banded pools at the treeline lanterns; the broken vein lit in qi, flaring once as the wave comes and pushing the grass flat in a ring; the Night's two creatures with a dark crest of raised hackles and the vein's light in flank and eye, beside the woods' own plain wolf | the same beat; `spawn_table_field_night.visual_profile`; `pulse_ambience` when the encounter begins |
| the wreck | the cart standing, load roped | the cart on one wheel, the other lying off, a crate burst, pale shards of vein stone on the ground | story presence → the `cart_wreck` prop |
| morning | daylight, the stake gone, nothing where it stood | the maps as authored again; a raked socket with its stone collar where the stake stood | `beat_aftermath.ambience_id = ""`; `StakeSocket` presence |

**Ownership.** Nothing stores "it is night". `StoryService.ambience_id()` reads the current
beat; `WorldRuntime` hands it to the map where it already applies story presence; the map's
`Visual/Ambience` (`MapAmbience`, presentation) wears it. The simulation's calendar is not
read or written. Colours live only in `style/aetheria_style.yaml` (roles `dusk_air`,
`night_air`, `lantern_glow`, and `qi`) and are written into `data/ambience/*.tres` by
`build.py ambience`; no gameplay, domain or story file names a colour. The Night's creatures
are `enemy_mist_wolf` — one `EnemyData`, its stats, AI, bite, telegraph and hitbox — under a
look that the ENCOUNTER's spawn table names; no code branches on a creature's id.

**Readability, held as a rule.** The tint is a `CanvasModulate` (a multiply of the world
canvas; the HUD is its own layer and is untouched). A profile whose mean tint level is under
0.42 is refused by the generator AND by `MapAmbience`; night is 0.59. Light is banded (three
flat rings). The creature cue is a SILHOUETTE change in all four facings (≥ 12 pixels of
outline differ per facing, asserted), so it does not depend on colour.

**Three things found by looking, not by testing.**
1. *The first vein pulse burned out to white* over about a sixth of the 1280×720 frame
   (energy 1.05 × a 2.6× flare, additive). Now 0.5 × at most 1.9×, radius 92 px: a banded
   pool that stays qi-coloured.
2. *The first vein-touched coat was charcoal* and sank into the night floor at 4× and at 1×.
   The body keeps the wolf's value now and the CREST is what is dark.
3. *The first stake socket was darker than the leaf litter* and could not be found (already
   recorded under Checkpoint 1).

**Tests.** Suite **1216** (was 1202): +9 `test_map_ambience` (day costs nothing; night tints
and lights; dusk lights lanterns and not the vein; a change in place eases and day returns
whole; an unknown ambience is not worn; a pulse flares and settles, stepped by exact deltas;
every shipped profile keeps the floor; the maps' lights are at their lanterns), +3 on the
Night's creatures (same data, registry and AI under another look; shape differs on the same
grid; a look on another grid is refused), +1 story (a beat lit by an ambience nobody made
refuses the start; dusk → night → morning follow the beats; the record stores no light), +1
map (the cart that waits is whole, the cart that was left is the wreck, never together, solid
only where drawn). Story E2E asserts dusk at 8c, night + the lit vein + the flare at 8d, day
again at 8e. All eight E2E flows pass; 0 `SCRIPT ERROR`; 0 leak lines.

**Mutations: 15 applied, 15 red — after one survived.** N14 (*the wreck is the standing cart
again*) was ALIVE on its first run: nothing pinned which prop the woods' story cart is. The
map test above was written for it; N14 and a sibling (N15, *the wreck is there before the
vein breaks*) are red against it.

| # | What was broken | Red in |
|---|---|---|
| N1 | the map is never told how it is lit | Story E2E 8c, 8d |
| N2 / N3 | the Night beat names no ambience / an unknown one is accepted | story runtime |
| N4 | night does not tint | ambience |
| N5 | lights burn by day | ambience ×3 |
| N6 | an unknown ambience darkens the map anyway | ambience |
| N7 | a pulse never settles | ambience |
| N8 | the vein is lit at dusk too | ambience |
| N9 | a profile too dark to play in is accepted | ambience ×3 |
| N10 | the rupture is not shown as the wave comes | Story E2E 8d |
| N11 / N12 | the wave wears the ordinary look / the table names none | enemy encounter |
| N13 | a look on another grid is accepted | enemy encounter |
| N14 / N15 | the wreck is the standing cart / is there before the vein breaks | map scenes |

**Real window (opened and looked at, 1280×720 vi; scratch path, not committed).**

| Frame | What is in it |
|---|---|
| `21_night_warning_caption` | the village under a dim warm-grey light, visibly duller than the morning frame of the same place; the caption band; the HUD at full brightness |
| `22_night_rupture_caption` | the treeline at night: two lanterns each in a warm pool of three rings, Kha Thản readable in the dark between them, the vein's stone lit cyan at the frame's corner |
| `23_night_wave_and_wreck` | the wave: a cool dark wood; the player's pale robe and silver hair the brightest thing in it; two wolves with spiked ruffs beside and below the player and one plain wolf up by the cairn; the wreck with its wheel off and a spill of pale shards; a soft banded pool of qi light at the vein |
| `25_morning_sheet_under_the_stele` | the village as authored, bright; the strip offers *E Xem xét* at the weighted sheet |
| wolves at ×6, day and night (composed from the shipped sheets) | row by row: plain wolf / vein-touched wolf — the crest reads as a dark saw-edge along the back in profile and as two raised wings of fur from the front and from behind |

**Not verified at this checkpoint (CHƯA VERIFY).** (1) The wolf's WIND-UP and telegraph under
the night tint were not captured as a motion strip; the bite's data is unchanged and its
telegraph is drawn in the world canvas, so it is tinted like everything else — Checkpoint 4
captures it. (2) en and 1280×800. (3) No frame-time measurement of the lights was taken.

**Cost added (counted, not profiled).** Per map: one `CanvasModulate` and 2–3
`PointLight2D` that are DISABLED by day (energy 0); one shared 96×96 gradient texture. At
dusk and at night `MapAmbience._process` runs to gutter the lanterns and pulse the vein
(a few sines); by day it is off. Three new 32×32-cell sheets (1.7–2.5 KB each), two props
(106×48, 108×63), one decal (32×18). See `PERFORMANCE.md` PERF-NOTE-21.

### Checkpoint 1 — the Act-I bridge and the choice transaction (*built*)

**H21-02, reproduced before it was fixed.** With the seam's new shape only and the OLD logic
in `choose`, five new tests were red: an owner declining the second of four consequences left
the choice recorded, the flag set to 2, the first regard moved and the knowledge taught — and
the call returned `ok`. The same held when the owner agreed and then failed, and for an
Origin's kit (the blade was handed over before a later grant was refused).

**The fix, as built (D-073 §2).** `StoryOwners.can_teach` / `can_move_regard`;
`KnowledgeService.can_grant`; `RegardRules.can_move`, which `RegardRules.move` now asks first,
so "can" and "does" are one rule. `StoryService.choose`: prepare all → the owners' regards →
their knowledge → the story's record and flags. `move_regard` returns the graph's own
`{ok, old_value, new_value}`, which is what lets a breach be undone exactly. A refused
decision reaches the player as words (`UI_STORY_REFUSED_*`), on the same line, with the answer
still on offer — before this, the HUD would have printed `story_owner_refused`.

*A like defect elsewhere?* `RewardService` was read for the same shape. It is a different,
deliberate contract: each part of a reward is claimed in the ledger as it is paid and an
unfinished reward is `OWED` and resumable. Nothing to fix there.

**H21-01: what a player can do now.** After the farewell the plaque reads *Hỏi ai đã viết mảnh
sổ*. Lâm Nguyệt, Kha Thản and Thẩm Bất Kỳ each open on the sheet. Showing it to one of them
first is recorded once and moves that person's regard and teaches one thing; the other two
then answer once, for nothing. Where the stake stood there is a raked socket to examine; an
old cart track runs from the wreck to a boarded, sealed door in the north-east rocks; examining
the door ends the bridge on *Tìm thước mở Hầm Khảo Mạch*.

**Tests.** Suite **1202** (was 1188): +5 all-or-nothing unit tests, +2 on the real owners,
+1 at the conversation, +6 on the shipped bridge content; the Origin × decision matrix grew
from 20 runs to 50 (5 Origins × (kept: 3 confidants | told: 2) × 2 Nights), each walked to
the door through the runtime's public seams. Story E2E: **20** real-key steps (was 17) —
8i (declined, shown, asked again, the socket, the door, which is solid), 8j (the door brought
back; the Origin's line once), 12 (told + withdrew: refused by her, answered by him).
All eight E2E flows pass; 0 `SCRIPT ERROR`; 0 leak lines.

**Covered by real keys:** thủ thư / woman / kept / stood / shown to Lâm Nguyệt, end to end;
hộ tiêu / man / told / withdrew / shown to Kha Thản, from Act I on (its prologue is staged
through the owner, as before). **Covered only through public seams (MỘT PHẦN):** the other
48 combinations; the three Origin lines with Kha Thản other than the one the E2E's Origin has.

**Re-pinned on the same invariant, not relaxed.** "The prologue ends in open play with a
purpose that is not blank" is now asserted at `beat_whose_hand` (E2E 8h, two unit tests): the
resting beat is three beats further on and is asserted there too.

**Mutations: 17 applied, 17 red, tree restored** (hash of `git diff` compared before and
after).

| # | What was broken | Red in |
|---|---|---|
| C1 / C2 | a regard / a grant of knowledge prepared only by "the seam exists" (the old rule) | story service ×2 |
| C3 | the choice recorded before the owners commit | story service (breach) |
| C4 | a breach does not put moved regards back | story service (breach) |
| C5 | a breach reported as success | story service (breach) |
| C6 | an Origin's grant prepared only by "the seam exists" | story service |
| C7 | the relationship owner says it can when it cannot | story runtime ×2 |
| C8 | the Knowledge Core says it can teach what it lacks | story runtime |
| C9 | a story refusal reaches the player as a raw id | dialogue runtime |
| B1 | the sheet can be shown before Act I | story runtime (50-run matrix) |
| B2 | she reads the sheet for someone who told on her | dialogue content ×2 |
| B3 | people open on the sheet before the prologue is over | dialogue content |
| B4 / B5 | an Origin's line repeats / is offered before the door | dialogue content |
| B6 | showing the sheet moves nobody's regard | the catalog refuses a zero move |
| B7 | the door's body is not where it is drawn | Story E2E 8i |
| B8 | story presence ignored | Story E2E 8a, 8d |

**Real window (opened and looked at, 1280×720 vi; scratch path, not committed).**

| Frame | What is in it |
|---|---|
| `32_act1_whom_to_show` | by the spring, Lâm Nguyệt's box: *"(Nàng nhìn tay ngươi trước khi nhìn ngươi.) Nói đi."*, two answers — *Đưa nàng xem mảnh sổ*, *Nói chuyện khác*; the plaque reads *Hỏi ai đã viết mảnh sổ* |
| `34_act1_where_the_stake_stood` | the clearing: a pale raked oval with a stone collar where the stake stood; the plaque reads *Xem chỗ cọc khảo mạch cũ* |
| `35_act1_wreck_and_old_track` | the cart on one wheel, the other lying off, a burst crate with pale shards, a narrow track leaving it east |
| `36_act1_the_survey_shaft` | a boarded door with crossed battens and a seal in a mossed outcrop, a capped stake beside it, the track ending at its sill, the player on the sill; the strip offers *E Xem xét* |
| `37_act1_shaft_sealed_caption` | the caption band over the place: *"Sổ sách ghi cánh cửa này đã đóng từ mùa đông. Sáp niêm trên nó mới được vài ngày."*; the plaque already reads *Tìm thước mở Hầm Khảo Mạch* |

Not yet done at this checkpoint: en, 1280×800, and the real-window `playtest_flow.gd` step
for the bridge (Checkpoint 4). The wreck appears here because the art was made with the
door's; the Night's LIGHT and its creatures are Checkpoint 2.

**Honest limits at this checkpoint.** (1) Once every trail line has been said, a person still
opens on their trail line with one answer (*Nói chuyện khác*); an opening cannot ask "is
anything left". (2) The wreck's standing wheel reads as a dark slab, like the whole cart's.
(3) The bridge has no failure state: it cannot be lost, only walked or not.

## 13. Debt register (`PLAYER_EXPERIENCE_STANDARD.md` §4 form)

| ID | Symptom and cost | Why not now | Owner | Closes when | Makes later work harder? |
|---|---|---|---|---|---|
| H21-14 | nobody but tools has played the opening: "engaging", pacing, attachment are UNPROVEN | it needs a person, not a tool | the project owner (checklist §11) | the owner has played it and written down the first point of confusion, any ignored key, and the three timings | yes if skipped: Phase 21 would build on an opening nobody has felt |
| H21-15 — **CLOSED** (follow-up §15.1) | after all of a person's trail lines are said they still open on the trail line with only *Nói chuyện khác*: one wasted press per talk | an opening's conditions are AND-only; "any line left" needs an OR or a derived flag — a dialogue-data change with its own tests | Dialogue data; Phase 21 (the first phase that adds the next lines to these three people) | a test opens each of the three with every trail flag set and lands on the hub | no |
| H21-16 — **CLOSED** (follow-up §15.2) | reaching the socket or the shaft's door usually meant a fight: the wolf followed the player to both (real window) | *recorded reason was wrong*: it was not "the shipped creature in its shipped territory" — the creature HAD no territory (its patrol was a random walk to its 340 px leash) | AI domain (`AiProfileData.patrol_radius`) + the field's layout | the socket, the door and a way between them are outside the wolf's reach by test, and a real-window walk shows it never notices | no |
| H21-17 — **CLOSED** (follow-up §15.2) | both carts' wheels read as dark slabs (discs seen edge-on by the top-down camera) | — | art pipeline (`props3d.cart`, `cart_wreck`) | both carts' wheels judged readable at 1× in real captures (done: village cart, wreck) | no |
| H21-18 — **CLOSED** (follow-up §15.3) | the wolf's wind-up under the night tint had been looked at in stills, not as a motion strip | — | presentation (`capture_motion.gd night_bite`, `AttackFeedback`) | the strip is opened and the tell frame named (done; and the telegraph it showed to be dimmed is fixed) | no |
| H21-19 — **CLOSED** (follow-up §15.3) | no frame-time measurement of the 2D lights | — | `tools/measure_ambience_frame_time.gd`; `docs/PERFORMANCE.md` PERF-NOTE-21 | measured numbers recorded (done: simple frame-time sampling, one machine; the engine profiler's split stays Phase 29's) | no |

| H21-20 (new, follow-up §15.6) | at 1280×720 the Chronicle runs to 10 pages and three of them hold two or three lines (3/10, 5/10, 10/10); at 1280×800 the same book is 7 pages | found in the last review; the packer keeps a block whole and breaks before it — repacking is a presentation change with its own measurements | presentation (`ChroniclePanel` paging); Phase 25, or the UI pass the owner has announced | no page of the book at 1280×720 is under a third full unless it is the last | no |
| H21-21 (new, follow-up §15.6) — **ROOT CAUSE NOT FOUND** | `test_pet_companion::test_a_kill_pays_the_enemy_reward_once_and_the_pet_its_share_once` failed ONCE on CI (run 38155239816, `a015036`, first attempt): in 2400 simulated frames the hound never resolved a swing on a wolf 60 px from its owner. The re-run of the same run on the same SHA passed; the runs before and after it passed | not reproduced: 12 isolated runs and 6 full-suite runs locally, 0 failures; locally the kill takes exactly 423 frames every time | AI / test infrastructure; Phase 21 (NAV-01 already owns creature pathing) | the failure is reproduced and explained, or the test is shown to depend on wall-clock physics stepping and is re-driven without it | **yes** — an intermittent red in the gate hides real ones |

**H21-21 — CLOSED on 2026-10-12 (Gate A, §16).** The row above is kept as it was written.
Its closing criterion was "the failure is reproduced and explained, or the test is shown to
depend on wall-clock physics stepping and is re-driven without it"; both happened.

Closed by this pass: H21-01 … H21-13. Carried unchanged with their recorded owners: Q19-01,
Q19-02, AUD-15 (Phase 25); CLV-01, NAV-01 (Phase 21); AUD-07 (Phase 26).

## 14. Status

**This pass is DONE** against its ten criteria:

1. Baseline recorded and protected (`4dd38ec`); one branch; `CLAUDE.md` never staged.
2. Phase 20 is DONE everywhere it is mentioned; this is a pre-Phase-21 gate, not a phase.
3. The prologue leads into a three-beat bridge that ends at a motivated lead; nothing is
   revealed early; no dead-end objective.
4. A story choice is all or nothing under an owner's refusal.
5. The Night is shown: light, the wreck, the socket, creatures with their own silhouette;
   bodies and interactables asserted.
6. The Chronicle explains, has a character overview from its owners, keeps every record, is
   taught once, owns nothing.
7. Sitting down mid-swing was reproduced, decided and made clear; no input is swallowed.
8. Tests, 50 mutations, all local gates and the four-combination real-window evidence are
   above; CI on the final SHA is reported in the closing message.
9. Six debts are recorded with owners (§13); no claim of human-tested fun.
10. **Phase 21 and Phase 22 have not started.** §10 is what they are authored against.

**Integration.** *As written at close:* the branch was pushed and not merged, and
`origin/main` (`4dd38ec`) was not touched by the task. *Now:* the owner has fast-forwarded
`main` to `4358c78` — the branch's tip — with no merge commit; CI run 38149535941 is green on
`main` at that SHA. Nothing was rewritten. See §15 for what was done after that.

*Update of 2026-10-12 (supersedes the "Now" above as a description of the present; that
sentence was true on 2026-10-11):* `main` has since been fast-forwarded again, to the
close-out's tip `33919f9` (CI run 38198759321, success). `4358c78` is an ancestor of `main`
and is no longer an integration point. §1a has the refs; §16 is the work done after.

**The next action is a person's, not a tool's:** play §11's checklist once. Then author the
Phase-21 Gate A against §10. (After the follow-up of §15 the gate still reads
**WAITING FOR OWNER PLAYTEST**.)

## 15. Follow-up close-out (`hardening/pre-phase21-closeout`, from `4358c78`)

> **Not a phase.** It closes the debts §13 left where a tool can close them, reviews the
> surfaces the first pass did not open, and stops before Phase 21. Status and the remaining
> debts are at the end of this section; H21-14 stays OPEN / OWNER REQUIRED throughout.

### 15.1 Checkpoint A — the commit-breach boundary, re-audited; exhausted dialogue (H21-15)

**The transaction edge (new finding, reproduced before it was fixed).** With the seam shapes
changed and the OLD sequential logic kept, two new tests were red:

| Case | What the old code left behind |
|---|---|
| an answer that teaches TWO things, the second failing at the commit | the FIRST lesson recorded on its own (`_breach` put regards back; nothing can un-teach) |
| an Origin's start, an owner breaking its word after the bag accepted the kit | the blade still in the bag and the drilled knowledge taught, with the story "not begun" — and a retry on the same owners handed over a SECOND blade |

Is a multi-lesson answer possible? Yes: `StoryOptionData` refuses only two writes to the same
target. No shipped option has two (each `choice_sheet_shown` option teaches one), and the
real `KnowledgeService.grant` cannot refuse what `can_grant` allowed — so this was not a
player-facing exploit. It was one content edit away from one.

**Closed by making the owner atomic, not by forbidding the content.**
- `KnowledgeService.grant_all(ids, source)`: checks every id with the rule `grant` refuses
  by, then records; all or none. `KnowledgeRuntime.grant_all` announces each NEW one after
  all are held. `StoryOwners.teach` is replaced by `teach_all`: the story never teaches one
  thing at a time, and asks LAST (after the regards, which can be put back exactly).
- `StoryService.begin`: items (the bag's atomic exchange) → regards → knowledge (one batch).
  On a breach the regards are put back and the items are TAKEN BACK through
  `StoryOwners.take_all` (the same exchange the other way). `begin` is whole by itself; the
  caller still discards the session.
- The story still touches no other owner's store.

Tests (+4; suite **1229**): two unit tests on the service (both-or-neither with ONE ask of
the owner; an Origin broken at the regard and at the knowledge), the real Knowledge owner's
batch (an unknown id in the MIDDLE leaves the ones before and after it unrecorded and
unannounced; what was already known is not announced again), and a `StoryRuntime` with an
injected breach over the REAL bag, Knowledge Core and graph (the blade is out of the bag
again, nothing known, no edge, no flag, nothing listening; the same rig then starts with one
blade).

**H21-15 — closed.** An opening's conditions are AND-only, so "is any line left?" is asked
as ONE OPENING PER LINE THAT CAN STILL BE SAID, each on the flags and knowledge the line
itself is gated by (Lâm Nguyệt 2, Thẩm Bất Kỳ 3, Kha Thản 6), followed by a *settled*
opening that goes straight to the person's hub. No new flag. A person opens on the sheet
only while it has an answer other than *Nói chuyện khác*; with none left they are simply
themselves again — and Lâm Nguyệt no longer falls back to "look under the stele" after the
sheet was found. Test: every Origin × kept / told × (sheet in hand, door found), each
person's lines said one by one with the opening checked before each (red on the old data:
all three opened on the trail with nothing to say). Story E2E 8j asks each of them twice
with real keys.

**Mutations: 8 applied, 8 red** (the batch records before checking · lessons one at a time
again · a broken start keeps its items · keeps its first impressions · knowledge no longer
last · no settled opening · an opening ignores "already said" · the door line opens the
trail before the door is found).

### 15.2 Checkpoint B — the wolf has a ground (H21-16); wheels that read as wheels (H21-17)

**H21-16. BUG → ROOT CAUSE → WHY THE TESTS MISSED IT → INVARIANT → TEST.**

- *Bug (real window, real keys).* Standing at the stake's socket, the clue the bridge makes
  the player examine, started a chase. Measured: socket 127 px from the wolf's spawn point,
  the wolf notices at 170.
- *First fix, and why it was not one.* The wolf was moved north (700,132), a surveyors'
  footpath was painted from the road to the door, and a test held every required thing
  170 px + 24 from the spawn point. Green. Then the real window: ten seconds at the socket
  → `ALERT → CHASE → ATTACK`, HP 100 → 46; on the footpath the player died. The wolf was
  **205 px from its den** when it noticed.
- *Root cause.* `AiBrain` PATROL was documented "wandering near home" and implemented as a
  random walk: 1.5 s legs at 53 px/s, each starting where the last ended, nothing bringing
  it back but the LEASH (340 px). A wolf's real reach was 340 + 170 = **510 px** on a
  960×576 map. No den position could have kept it off the clue; "its territory" did not
  exist as a thing the game knew.
- *Why the tests missed it.* Every AI test stepped a brain for a few decisions or placed a
  target; none let a creature alone for minutes and asked where it was. The first territory
  test measured from the spawn point — a number the creature does not keep to.
- *Fix, at the layer that owns it.* `AiProfileData.patrol_radius` (0 = none, the shipped
  ally behaviour; must be inside the leash). In PATROL, past its ground, the leg ends and it
  walks HOME (RETURN — it still notices someone on the way). `stray_radius(move_speed)` is
  the one place "how far from where it was put" is worked out: ground + one decision's
  travel, or the leash. `ai_frontier_skirmisher` authors 32 px → stray 42.6 px → reach
  212.6 px. The den is (680,76), the glade north of the wreck.
- *Not weakened.* Detect 170, lose-interest 280, leash 340, speeds, alert 0.35 s, the bite:
  unchanged. A chase still goes to the leash. The wreck (138 px from the den) and the west
  half of the old haul track are inside its notice; claw furrows and a gnawed bone
  (`WolfSign`, `Visual/Decals`, walked over) mark the two edges of that ground. The Night's
  table is its own (wolves ON the road, by the story) and untouched.

| Real window, 1280×720, real keys, origin_lang_y | wolf states seen | nearest | HP |
|---|---|---|---|
| road → socket, examine, stand 10 s | IDLE, PATROL, RETURN | 216 px | 100 → 100 |
| road → footpath → door, examine, stand 5 s | IDLE, PATROL, RETURN | 214 px | 100 → 100 |
| door → west along the haul track to the wreck | ALERT, CHASE, ATTACK, RECOVER | 16 px | 100 → 91 |

Wolf's farthest from its den while alone: 42 px (authored edge 42.6). The same walk before
the fix: `ALERT/CHASE/ATTACK` at the socket (HP 46) and death on the footpath.

Tests (+6; suite **1235**): the brain alone for ten simulated minutes stays inside
`stray_radius` and still walks its ground; the contrast (no ground → far from home, and
reports its leash); one step past the ground → RETURN, and a target on the way home still
alerts it; a ground must be inside the leash; the SHIPPED wolf on a real body at 60 fps for
five minutes (PATROL, RETURN and IDLE all seen); and the field: every spawn, the exit, Kha
Thản, the socket and the seal ≥ reach + 24 px from every den, the named safe way never
inside any reach, the wreck still inside the cairn wolf's notice. Mutations 8/8 red (no
ground check in the brain ×2 targets; no ground in the data; den back at (632,168); den
taken out of the contested way; a 64 px ground; a ground at the leash accepted; the stray
radius without its step). Playtest 38/38 in the real window; all eight E2E flows pass.

**H21-17.** Cause: each wheel was a solid disc on an axle parallel to the screen, so the
top-down camera saw its tread — a dark slab. Both carts are re-modelled in the canonical
pipeline (`model/props3d.py`): `_wheel` = rim + six spokes + hub, and the cart stands turned
34° so one wheel shows its face; the wreck's lost wheel lies spokes-up beside the canted
bed. Sprites, origins and footprints regenerated from the same model (cart 76×60, origin
(33,53), foot 48×20; wreck 110×54, origin (51,43), foot 55×23). *Opened:* the sprites at 5×
and 1×; the wreck in the field (playtest `21b_where_the_stake_stood`, and cropped 4×): a
round spoked wheel on the ground, canted bed, canvas, burst crate, pale shards; the village
cart in the real window with the player walked into it by held keys from four sides — spoked
wheel on the near end, striped canvas, shafts and yoke; the body stops the walk at
x = ±33 (foot ±24 + the player's 9) and at the foot's north and south edges, drawn in front
when south of it and behind (head showing) when north. The generic body invariants
(`test_each_body_sits_under_the_mass_that_is_drawn`, the eight-way walk) hold both. No new
test: "reads as a wheel" is a judgement, recorded here as one.

### 15.3 Checkpoint C — the bite under the Night (H21-18); the light's cost (H21-19); what lies in the world (FG-3)

**H21-18.** `tools/capture_motion.gd` gained the named scenario `night_bite`: the story is
brought to the Night through its owner (setup, as `capture_ui` does), one wolf OF THE WAVE is
chosen (wearing its table's look — the woods' two standing wolves are still there in
daylight coats, and the first run picked one of them by distance), the player is stood 64 px
in front of it, and from there the wolf acts by itself. Every rendered frame is kept from six
frames before the wind-up to four after READY; each cell carries a bar in the colour of the
attack state it was taken in, and `motion_night_bite.txt` lists every cell with its state
and the milliseconds since the wind-up began.

| | 1280×720 vi | 1280×720 en | 1280×800 vi | 1280×800 en |
|---|---|---|---|---|
| ambience / look | night / `vis_vein_wolf` | same | same | same |
| wind-up → ACTIVE | 267 ms | 268 ms | 268 ms | 267 ms |
| ACTIVE → RECOVERY | 349 ms | 349 ms | 350 ms | 349 ms |
| strip opened | yes | yes | yes | timings read; image not opened |

Authored: wind-up 0.26 s, active 0.08 s, recovery 0.34 s — **unchanged**, and what the
window shows.

*What the strip shows, frame by frame (60 fps, 16.7 ms a cell):*
- **before** (grey): the wolf stands square, head level, pale coat and dark crest clear
  against the near-black earth;
- **the tell — cells 07–09, 15–49 ms into the wind-up:** the body DROPS into a crouch (about
  3 px lower, legs shortened) and the reach arc appears on the ground; this is ~220–250 ms
  before the bite;
- through the wind-up the arc grows to full strength; at **cell 20–21 (≈ 232–249 ms)** the
  head is thrown forward and up — the lunge;
- **ACTIVE at 267 ms:** the player flashes, claw streaks on the body; RECOVERY: the wolf
  backs off.

*Finding, and fix.* In the first night strip the reach arc — the telegraph the combat
contract says "is read and learned once" — was a dim brown hair-line. Measured on the
captured pixels: its strongest pixel was (106, 57, 59) under the night against (235, 109, 77)
by day — red-over-green **49 against 126, 39%**, and it only cleared a 40-level threshold
165 ms into the 267 ms wind-up. Cause: `MapAmbience` tints by a `CanvasModulate` multiply
(night 0.45, 0.54, 0.78), and red is the channel it takes most of; the telegraph is drawn on
that canvas. A telegraph is information, not a surface the night falls on:
`AttackFeedback` now reads the map's tint ONCE as a swing begins and draws the telegraph
brighter by exactly what the tint will take (`_telegraph_colour`; channels floored at 0.2).
After: (232, 104, 75) under the night — red-over-green **128** — visible from the second
wind-up frame. Nothing else is exempted: the wolf, the player and the world stay in the
night. Test: `drawn × tint == UIPalette.TELEGRAPH_HOSTILE` under the real `night` profile,
and the authored colour with no ambience; mutations 2/2 red.

**H21-19.** `tools/measure_ambience_frame_time.gd` (new, reproducible) and
`docs/PERFORMANCE.md` PERF-NOTE-21. Simple frame-time sampling — **not the engine
profiler**: wall time between consecutive `process_frame`s, 3 rounds × 8 s per ambience per
place, interleaved, on an Intel i3-13100 / UHD Graphics 730 / Godot 4.7.2 `gl_compatibility`.
Worst case (night, all three of the woods' lights in frame): median 0.835 → 1.528 ms at
1280×720 (+0.69), 0.926 → 1.676 ms at 1280×800 (+0.75); p95 1.09 → 1.87 / 1.18 → 2.02 ms.
A light out of frame costs nothing measurable. With vsync: median 16.66 ms, p95 ≤ 16.92 ms
under every ambience. Not measured: other GPUs, the profiler's split (Phase 29), the Night
with its wave fighting.

**FG-3 — everything lying in the world, audited.** Paths read: `WorldItem`,
`InventoryRuntime` (`tick`, `give`, `take`, `exchange`, `use`, save shape), `InventoryState`,
`EquipmentRuntime.equip/unequip`, `RewardService` (bag part), `StoryRuntime._give_all /
_take_all`, `WorldRuntime._enter_map`, `StoryPresence`, `MapBase._track_knowledge_source`,
both map scenes. There are no creature drops in the game (a kill pays through the
`RewardLedger`; nothing is spawned on the ground), so there are no orphan drops to find.

| Lying there | In-world cause | There when | Taken by | Gives | Once | On re-entry |
|---|---|---|---|---|---|---|
| `pickup_hubpill1` ×2 | a healer's pills left by the spring path | always | walking onto it | 2 × Bổ Huyết Đan | `_collected` id | hidden at arrival |
| `pickup_hubmanualphong`, `pickup_hubrobe`, `pickup_hubsword` | the outpost's issue: primer, coat, blade | always drawn; HELD until `flag_outpost_issue` (the elder says so) | walking onto it after he has | the item | id | hidden at arrival |
| `pickup_fieldstone1` ×2, `pickup_fieldstone2` | stones the vein shed | always | walking onto it | Linh Thạch | id | hidden at arrival |
| `pickup_fieldpill1` | dropped on the forest road | always | walking onto it | 1 pill | id | hidden at arrival |
| `pickup_fieldmanualloi` | spilled from the carter's wreck | only once `flag_vein_broke` | walking onto it | the Thunder-Finger manual | id | hidden at arrival; absent before the Night |
| the Origin's kit | what the chosen past carried | at the start | `StoryService.begin` (one bag exchange) | per Origin | undone whole on a breach (§15.1) | — |
| quest / story rewards | a deed | on completion | `RewardService` → one bag exchange | per reward | `RewardLedger` id | — |

Four defects found, each red before it was fixed:

1. **A pickup that only partly fit was destroyed.** `tick` marked it collected as soon as
   `give` put ANY of it in the bag: five pills onto room for two → two in the bag, three
   gone for the run. Now a pickup is taken whole or left whole
   (`InventoryState.room_for`); leaving a remainder on the map node was rejected because
   the node comes back whole on re-entry — a duplicate.
2. **A full bag was said sixty times a second.** `give` emitted "bag full" every physics
   tick the player stood there (measured: 30 ticks → 30 refusals). Said once per approach.
3. **Two held things underfoot re-said one of them every tick.** The "once per approach"
   memory held ONE id; the outpost's coat and primer lie 12.8 px apart with a 14 px reach
   each, so one step stands on both — a shipped layout. The memory is now a set.
4. **A map arrived showing what was not there.** A map scene is built fresh on each entry
   with every pickup drawn; the bag's owner hid the collected ones, and the manual the
   rupture has not spilled yet, on its NEXT physics tick. Read inside `active_map_ready`
   (the entry's own call stack): `FieldManualLoi` drawn on the first visit to the woods, and
   the pill, primer, coat and blade drawn again on every return. `WorldRuntime._enter_map`
   now asks the bag before it announces the map.

Pinned without a defect: every pickup in both maps has one id, a catalogued item in a count
an empty bag takes whole, gates that are real story flags, a reason in vi and en when it is
somebody's, and no body; every `StoryPresence` in both maps, both ways — absent means not
drawn (which is what takes it off the interact key) and every shape off, present means
solid again, and with no story to ask it fails closed.

Tests (+6; suite **1241**), world E2E extended (21 arrivals looked at). Mutations 10/10
red (telegraph ×2; partial take; per-tick "bag full"; the set forgotten; `room_for` without
free slots; no ask at arrival; a removed thing keeps its body / stays drawn; a shared id).

### 15.4 Checkpoint D — every transition on the New Game path (FG-4)

Walked by the Story E2E with real keys (three runs: two Origins, both answers to the Night,
told-and-withdrew), and now JUDGED at every arrival: a deferred check from
`active_map_ready` — after every owner has wired the new map, before the frame that shows
it — holds five agreements (light = the beat's ambience; each `StoryPresence` drawn and
solid exactly when its flag says; no collected or not-yet-existing pickup drawn; the player
on a named spawn; nothing of the story's encounter in the map under a playing scene).
**9 arrivals, 0 disagreements.** Mutations 4/4 red (no light at arrival; no presence at
arrival; the bag not asked at arrival; the Night's creatures under its scene).

| Transition | Trigger → owner | Committed BEFORE anything is shown | Where the player lands | Input while it happens | Light / presence handoff | Skip · back · re-entry | If it fails |
|---|---|---|---|---|---|---|---|
| menu → identity | New Game (`ui_accept`) → `Main` | nothing: no session, no story | the identity screen | menu context; gameplay keys dead | — | Esc returns to the menu, still nothing started (E2E 3) | — |
| identity → run | Begin → `Main` starts every session in the frozen order; `StoryService.begin` | the Origin's kit (one bag exchange), regards, knowledge — or nothing at all (§15.1) | hub `spawn_default`, map covered by the vignette | a doubled confirm starts exactly ONE run (E2E 4) | hub as authored (day); presences applied at arrival | — | a breach undoes kit, regards and knowledge; the session is discarded |
| Origin vignette → arrival | advance (`interact`) or Esc → `StoryRuntime` | a scene changes nothing: no flag, no reward | unchanged | only advance / skip; movement and attack held; Esc SKIPS, never leaves (E2E 7) | — | skip lands on the same state as watching | — |
| hub ↔ woods | walk onto the exit + `interact` → `WorldRuntime._enter_map` (transactional) | the old map is announced as leaving; the player parked | the named spawn of the exit (`from_hub` / `from_field`) | router refuses a second request while one runs (20 round trips) | ambience and presence re-derived from the story at arrival; the bag asked before the map is announced (§15.3) | re-entry draws nothing already taken | router rejects → player restored to the old map at the old position |
| day → dusk (village) | `choice_lam_readings` answered → story moves to `beat_warning` | the choice: flag, regards, knowledge, all or nothing (D-073 §2) | unchanged | the card and caption are a scene | `dusk` eases in over 0.9 s where the player stands (E2E 379) | — | a refused choice leaves the beat where it was |
| dusk → the Night (woods) | entering the woods on `beat_night` | `flag_vein_broke` when the rupture scene is reached | `from_hub` | the rupture caption holds the player; **the wave spawns only after the scene ends** (E2E 8d) | the woods ARRIVE in night (no ease at a door); the vein pulses once; the wreck present, the whole cart gone | walking out IS an answer (withdrew): the encounter is left with the map and the beat moves on, so the wave is never met twice (E2E 11) | — |
| the Night → morning | last creature down, OR walking out (withdrawing is an answer) → `StoryRuntime.choose` | the outcome (stood / withdrew), once | where the player is; or hub `from_field` | — | day again: "no night is left behind" (E2E 455); `flag_vein_broke` keeps the wreck and the spilled manual | the Night cannot be replayed in a run | — |
| morning → the bridge | the elder's account, first cultivation, the sheet → `beat_whose_hand` | each as its own beat | — | a conversation is a modal context; closing returns the gameplay context (E2E 9: "no modal context survived") | the stake gone and its socket present from `know_survey_fragment` on; the shaft's seal examinable in any order | the beats complete on what is KNOWN, so a socket or door examined before anyone sent the player there is already an answer (`test_story_shipped`: "found the door before asking anyone"; in order: E2E 8i) | a refused `choice_sheet_shown` changes nothing |
| leave → menu | Esc with nothing open → the leave question → confirm | — | the menu | the question is a prompt; one press, one answer | — | Esc again stays in the run (Quest E2E 5) | sessions end in exact reverse order (E2E 9) |
| second New Game | as the first | a new story; nothing of the first survives (E2E 10) | hub `spawn_default` | — | day | — | — |

Branches covered by tests: all five Origins × kept / told × who saw the sheet first, each
person's lines to exhaustion (`test_dialogue_content`, §15.1); told-and-withdrew, refused by
Lâm Nguyệt and answered by the elder (E2E 12); socket and door pre-examined vs in order
(E2E 8i). **Not walked with real keys:** the other three Origins' full paths (they are
driven through the owners in the integration tests, and their identity screens and
vignettes are captured); a map transition attempted WHILE a conversation is open (the
conversation is modal: `interact` goes to it, and no test presses the exit under it).

### 15.5 Checkpoint E — canon audit and the way into the Survey Shaft (FG-5)

**Audit of the canonical documents.**

| Asked for | Found | Action |
|---|---|---|
| one ten-act continuity map | `NARRATIVE_MASTER_PLAN.md` §8 (ten acts, scale, core question) with §9 (the nine-layer reveal ladder, mapped onto the acts) | complete — linked, not restated |
| a capability / progression ledger | `PROGRESSION_CULTIVATION_DESIGN.md` §1 (two axes), §4 (what a realm changes), §6 (threat rating instead of a level gate), §7 (knowledge), §8 (what a technique is), §9 (master realm table), §10 (dependencies); frozen in `CANON_LEDGER.md` CL-13 / CL-14 | complete — linked |
| a clue-to-payoff ledger | **absent.** §4 names one FUTURE PAYOFF and §11 the causality rule, but nothing listed what shipped content has promised | **added as `NARRATIVE_MASTER_PLAN.md` §9a** (the single owner): 13 rows K-01…K-13, each with its in-game source, what the player holds, its reveal layer, the payoff owed and by whom. One is PAID (the stele's warning → the Night). No new lore: every payoff cites §4, §6, §9 or §10 of this handoff |

**Design note — a believable way into the Survey Shaft (not built; for Phase 21's Gate A).**

*The rule it must satisfy.* `MAP_DUNGEON_DESIGN.md` §3: level is never a gate; at least one
gate is non-numeric; legible before passable; "you may enter and die" over "you may not
enter"; an advisory threat rating in realm vocabulary (`PROGRESSION_CULTIVATION_DESIGN.md`
§6), never a `min_level`.

*What the build already gives the approach (verified in §15.2).*
- Two ways to the door, told apart on the ground: the forest road and the surveyors'
  footpath never enter the cairn wolf's reach; the old haul track does, and is marked at
  both edges by what the wolf leaves. Risk is chosen, and can be read before it is taken.
- The door says what kind of key it takes (a surveyor's rod) before it can be opened, and
  the Chronicle keeps that (`know_sealed_shaft`).
- A creature now has a ground (`patrol_radius`): "safe" and "contested" are properties of
  the map that a test holds, not accidents of a random walk.

*What Phase 21 should author, in this order.*
1. **Telegraphed risk at the sill, in the world.** The threat rating is shown where the
   player decides — at the door, in the realm vocabulary (e.g. *Phàm · cao*), with the
   Night's own signs (raised hackles, the vein's light) visible through the boards. No
   number, no level.
2. **Preparation the player can DO, each from a different kind of growth, none required:**
   - *knowledge:* what Lâm Nguyệt, Kha Thản or the elder said about the shaft changes what
     the player is warned of at the door (who saw the sheet first already differs);
   - *technique mastery:* the Wind Palm and the Thunder Finger are the answers to the
     Night's creatures; using them is what improves them, not a gate;
   - *cảnh giới / tầng:* one more deliberate cultivation step raises the body the player
     brings — advisory, as the threat rating says;
   - *combat level / EXP:* whatever the woods have already taught; never checked;
   - *supplies:* pills from the village (the shop is the sink), stones for the step.
   These four axes stay four numbers with four owners. The door reads NONE of them.
3. **The one real gate is the rod, and it is a story gate with two shapes** (§10): she
   brings it (kept), or it must be earned back (told). Both reach the same door.
4. **A fair retreat, always.** A way out from every room (the Phase-21 contract); leaving
   is a state of the INSTANCE; nothing in the story is lost by walking out, and the
   first room must be survivable long enough to turn round in (the wolf's 0.35 s alert and
   0.26 s wind-up are the model: seen, then answerable).
5. **The first room teaches the dungeon's one idea before it tests it** (§5: the gimmick is
   the acceptance test), in the light of a place that is dark by the same ambience data.

*What it must not do:* gate on level; hide the gate; make the contested track the only
way; reveal above layer 2 (§9a K-05, K-06, K-10 are what it may pay); move a story outcome
into the instance.

### 15.6 Checkpoint F — what was opened and judged (FG-2); close-out (FG-6)

**Real-window runs on the final code.** `capture_ui`: vi / en × 1280×720 / 1280×800, 0 script
errors, 51 / 51 / 48 / 48 frames (the Chronicle is 10 pages at 720 and 7 at 800).
`playtest_flow`: 38 / 38 steps in all four combinations. `capture_motion`: `night_bite` ×4,
`field_fight`, `dialogue`, `quest` (vi 720). Frames generated in the follow-up: **about 400**.

**Opened and judged (about 75 frames, most as 2×2 sheets at full size):**

| Surface | Seen |
|---|---|
| identity: five Origins, both looks (vi 720; Origin 3 en 800) | each Origin shows its problem, what it gives, what it costs; the focus ring previews while ◆ stays on what is chosen and the "chosen" line agrees; the second look changes sprite and medallion; no clipped text in either language |
| Origin vignette, steps 1–4 (vi 720) | card then three captions, step counter and key hints on every one |
| dusk card and caption, the rupture caption, the wave by the wreck, the morning card, the sheet under the stone | dusk is a visibly dimmer village; the woods at night are cool and dark with player, wolves, wreck and lantern posts all readable; the wave wears the crested look |
| satchel, equipped + dock | five rows, counts, the selected row's description and keys |
| Chronicle, all 10 pages (vi 720) + People (en 800) | story with the decision lines ("you kept quiet about…", "you withdrew…"), who you are, body and path, what you know, people with named bands and numbers and the decision that moved them, history oldest last |
| the bridge: the road-ahead card, "ask who wrote it", whom to show (vi 720, en 800), she reads the hand (vi 720, en 800), the socket, the wreck and track, the shaft, the sealed caption, the standing purpose | the purpose line changes at each step; her mood tag goes *wary → warm* after the sheet; the socket, the wreck with its spoked wheel, the claw marks at both edges of the haul track, the footpath and the boarded door are all in frame and readable |
| H21-16 / H21-17 probes | §15.2 |
| the bite under the Night, three of four strips | §15.3 |
| dialogue prompt → open with choices → closed; the quest journal | the prompt names the person; closing returns the same prompt; the journal shows objective, the alternative, and the reward |
| the sect panel | — and a wrong voice: it said *Bạn* where the whole game says *ngươi* |

**Found in the review.**
- *Fixed:* `UI_SECT_PANEL_NONE` and `UI_FACTION_PANEL_NO_SIDE` addressed the player as *Bạn*
  (2 strings against 148 uses of *ngươi*). Now *Ngươi*.
- *Recorded, H21-20:* three near-empty Chronicle pages at 1280×720.
- *Not a defect, stated:* in `capture_ui` frames 35–38 a wolf's plaque is up and the wolf
  walks into frame at the door. The capture STAGES the player at the wreck — inside the
  wolf's notice by design — before the door; the real-key walk by the safe way (§15.2) draws
  no wolf.

**Generated and NOT opened** (no claim is made about them): the full en 1280×720 and
vi 1280×800 capture sets beyond the frames above (~95 + ~45 + ~44); vignette steps 5–7;
main menu, settings, hub gameplay / HUD, faction panel; 14 of 16 dialogue frames and 17 of
18 quest frames; the en 1280×800 `night_bite` strip (its timings were read); the playtest
frames of en 720, vi 800, en 800 and the second vi 720 run; `field_fight` beyond the pixels
measured. The other three Origins' vignettes are not captured by any tool.

**Gates on the closing tree.** import · parse_check PASS · gdlint PASS (363 files) + selftest ·
`author_story_data --check` up to date · `ambience-check` up to date · **1241 / 1241** tests,
0 script errors, 0 leak lines · eight E2E flows PASS (0 script errors, 0 leak lines) ·
real window as above. Mutations in the follow-up: **30 applied, 30 red**
(A 8 · B 8 · C 10 · D 4).

**Debts after the follow-up.**

| ID | State |
|---|---|
| H21-14 | **OPEN / OWNER REQUIRED** — nobody but tools has played the opening. §11 is the checklist; launch `~/Downloads/Godot_v4.7.2-stable_linux.x86_64 --path . --resolution 1280x720`. No finding about fun, pacing or attachment is claimed anywhere in this document |
| H21-15 … H21-19 | CLOSED (§15.1–§15.3) |
| H21-20 | new, recorded (§13) |
| CLV-01, NAV-01 (Phase 21); Q19-01, Q19-02, AUD-15 (Phase 25); AUD-07 (Phase 26) | unchanged |

Additions to §11 for the owner, from what the follow-up changed: walk to the socket and to
the shaft's door by the road and the footpath (nothing should come for you), then once by
the old haul track past the claw marks (something should); fight a wolf of the Night and say
whether you saw the bite coming; fill the satchel and walk onto a pickup.

**An intermittent CI failure, not explained (H21-21).** One of the six CI runs of this
branch went red in the suite, on a test this follow-up did not touch, and green when the
same run was re-run. What was excluded: the test's logic is seeded and stepped with a fixed
delta (no RNG outside the stream, no wall clock in the test); target choice is
deterministic (`_choose_hostile`); the failure does not reproduce in 18 local runs.
What is NOT excluded, and is only a hypothesis: `MovementComponent.apply_pursuit` asks the
physics space (`test_move`), and the test drives bodies outside physics frames, so what the
space holds may depend on whether an engine physics step fell between two tests — which is
wall-clock. The patrol ground of §15.2 changed how the wolf moves in that test (it now
walks home), which may be why it surfaced now. No fix was attempted without a
reproduction.

**Gate: WAITING FOR OWNER PLAYTEST. Phase 21 and Phase 22 have not started.**

## 16. Gate A — technical state and transaction integrity (`hardening/pre-phase21-gate-a`, from `33919f9`)

> **Not a phase, and not Phase 21.** One of five bounded pre-Phase-21 gates. It explains
> H21-21, re-verifies the transaction fixes of §15.1 as a regression baseline, closes one
> invariant that audit found missing, and corrects this document's present tense (§1a, §14).
> No gameplay, content, art, UI, save or networking change. It stops here.

**Preflight (2026-10-12).** Refs as §1a. Working tree: `CLAUDE.md` and `.kiro/settings/`
untracked — neither is this task's; neither was read into a commit, edited, staged or moved.
Baseline on `33919f9` before any edit: **1241 / 1241** tests, 0 `SCRIPT ERROR` (two full
local runs).

### 16.1 H21-21 — root cause

**What the failed run shows** (job log of run 38155239816, attempt 1, `a015036`): three
assertions of the kill test failed — the wolf not dead after 2400 ticks, **0** swings
resolved by the hound, 0 defeats — and one PASSED: the owner's health was unchanged. In forty
simulated seconds neither creature hit anything. That is not a creature that lost a fight; it
is two creatures that never closed.

**Mechanism.** `_step()` calls `CombatRuntime.tick_enemies / tick_allies` and
`PetRuntime.tick` with `1/60`. Each ends in `MovementComponent.apply_intent`, which sets a
velocity and calls `CharacterBody2D.move_and_slide()`. That call takes no delta. Inside a
physics frame it integrates against the fixed physics step; **outside one it integrates
against the engine's process step** — the wall-clock length of the last rendered frame, as
the engine clamps and compensates it. The test ran between physics frames (it is driven from
the runner's `await process_frame`), so every tick of the loop moved both bodies by `speed ×
one real number`, the same number for all 2400 ticks.

**Evidence** (scratch diagnostics, not committed; the engine's `--fixed-fps N` forces the
process step to `1/N`):

| Process step | Kill after | Swings | |
|---|---|---|---|
| 200 ms | 1491 ticks | 12 | |
| 125 ms | 507 | 8 | |
| 67 ms / 33 ms | 363 | 6 | |
| 16.7 ms | 375 | 6 | |
| 2 ms | 531 | 6 | |
| 0.5 ms | 951 | 6 | |
| 0.2 ms | 1923 | 6 | |
| **0.1 ms and below** | **never (2400)** | **0** | owner's health unchanged — the CI signature, assertion for assertion |

Without `--fixed-fps`: eight isolated runs of the unmodified test took 879, 1491, 903, 879,
999, 1407, 879 and 1011 ticks (process step ≈ 0.142 s each time, the engine's clamp after a
slow first frame); two full-suite runs took 459 (process step 8.5 ms). The "423 frames every
time" recorded in §13 was the same test on another day's timing. The outcome was never
deterministic; it was inside the cap by a margin that depended on the machine.

**Stepped inside a physics frame** the same loop takes **375 ticks and 6 swings** at every
process step from 200 ms to 0.01 ms and in three runs with no forced step.

**The same sweep over whole files.** `test_pet_companion`, `test_enemy_encounter`,
`test_pet_budget`, `test_ai_budget` and `test_player_components` (51 tests) pass at a forced
process step of 0.01 ms, 0.05 ms, 2 ms, 16.7 ms and 200 ms and with none forced. On `main`
(`33919f9`) the first two files alone fail 3 tests at 0.01 ms and 2 at 200 ms.

**What was not measured.** The process step of the CI runner during attempt 1 cannot be read
back: nothing logged it. The claim is that the failure's signature is reproduced exactly by
this mechanism and by nothing else found, and that the dependence is removed — not that the
runner's number is known. The earlier hypothesis in §15.6 (the physics SPACE differing
between tests) was not what was found: no physics query differs; the integration step does.

**Fix — at the owner, not in the test's numbers.**
- `MovementComponent.apply_intent` and the knock-back in `AIComponent.tick` assert
  `MovementComponent.in_fixed_step()` before `move_and_slide()` (debug builds). The game
  already moves bodies only from `_physics_process`: all eight E2E flows and the boot smoke
  run with 0 script errors under the assert.
- `TestCase.fixed_step()`; the twenty tests in five files that stepped bodies between physics
  frames (found by counting the assert: 139 608 calls in one suite run) now enter it. No
  assertion, cap, speed, range or damage value was changed.
- Not done, on purpose: the frame cap is still 2400; nothing retries; no test was skipped.

### 16.2 Transactions — the baseline re-verified, and one missing invariant

**Re-verified by fault injection** (§15.1's fixes; R1–R7 below, all red): the knowledge batch
checks every id before it records; a broken Origin start gives its items back and its first
impressions back; a broken decision puts its regards back and writes nothing; a refused
batch is not reported as taught. The design was not redone.

**Missing invariant, found by a red test — the in-flight window.** `KnowledgeRuntime.grant_all`
emits `knowledge_gained` from inside the call, and `StoryRuntime` answers that signal with
`StoryService.refresh()`. So the story's own listener re-entered the story after the owners
had done their part and before the decision was on the record. Two tests on the unguarded
service were red: a beat waiting for the lesson its own decision teaches completed inside the
window and took the way on for "not decided" (beat `e` instead of `c`); and a write from
inside (`choose`, `begin`) recursed — 511 recorded decisions, 681 starting kits before the
stack gave out. **Reachability:** not with shipped content (probed: the one decision that
teaches, `choice_sheet_shown`, is on a beat that waits for the CHOICE; no beat waits for
knowledge a decision teaches). One content edit away, like §15.1's.

**Fix.** `StoryService._committing` across the owner commits of `begin` and `choose`; every
write is refused with `REFUSE_BUSY` for that window; the call in flight settles the story on
the whole record as its last act. Reads are not refused. D-073 addendum O.

### 16.3 Mutations — 22 applied, 21 red, 1 survived

| # | Fault injected | Result |
|---|---|---|
| M1 | the tests stop entering the fixed step (assert kept) | red — 15 072 script errors, 3 tests |
| M2 | the same AND the assert removed (the original defect) | red — the two fight traces differ; the kill test fails with the CI signature |
| M3 | the assert removed, tests still entering the step | **survived** — nothing is wrong to observe; the assert only ever fires on a caller that is itself the defect (M1) |
| M4 | `in_fixed_step()` always true | red |
| T1–T7 | each write no longer refuses while busy (`refresh`, `choose`, `set_flag`, `meet`, `note`, `begin`, `load_state`) | red ×7 |
| T8, T11 | a refused decision / a refused start leaves the story busy | red ×2 |
| T9, T10 | `choose` / `begin` never raises the guard | red ×2 |
| R1 | the batch records before every id is checked | red |
| R2, R3 | a broken start keeps its items / its first impressions | red ×2 |
| R4 | a broken decision keeps the regards it moved | red |
| R5 | a refused batch is reported as taught | red |
| R6 | the decision is recorded although an owner refused | red |
| R7 | a decision's lesson is never taught | red |

### 16.4 Evidence

| Case | Before | Test | After |
|---|---|---|---|
| H21-21 | intermittent red in CI; locally 363–1887 ticks by machine timing, never at ≤ 0.1 ms | `test_a_fight_is_the_same_whatever_the_rendered_frame_took`; the kill test itself | 375 ticks at every process step; identical traces after a short and a 160 ms frame |
| a body moved outside the fixed step | silent, wall-clock scaled | `test_the_fixed_step_is_only_inside_a_physics_frame`; the production assert | a `SCRIPT ERROR` the suite gate fails on |
| a listener moves the story inside a decision | beat `e` (not decided) instead of `c` | `test_a_listener_cannot_move_the_story_before_the_decision_is_on_the_record` | refused busy; beat `c`, completed once |
| a write from inside a decision or a start | recursion; 511 decisions / 681 kits | `test_a_listener_cannot_answer_or_write_from_inside_a_decision`, `…_begin_a_second_run_from_inside_the_first` | refused; one decision, one kit |
| the same, real owners | not tested | `test_what_hears_a_lesson_inside_a_decision_cannot_decide_again` | heard once; regard moved, decision not yet written, no way in; announced after |
| a refusal leaves the story usable | — | `test_a_refused_decision_leaves_the_story_answering` | answers again |
| multi-knowledge batch, Origin undo (§15.1) | fixed in §15.1 | the §15.1 tests, re-run under R1–R7 | still red under every fault |

**Gates on the closing tree:** lint + selftest · import · parse_check · boot smoke · the
suite · eight E2E flows — numbers in the closing message, with CI on the exact final SHA.
No real-window run was made: nothing a player sees changed (**BLOCKED as evidence of
anything visual — and none is claimed**).

### 16.5 Debts after Gate A

| ID | State | Owner | Closes when |
|---|---|---|---|
| H21-14 | **OPEN / OWNER REQUIRED** | the project owner | a person has played §11 and written down what happened |
| H21-20 | recorded, unchanged | presentation; the announced UI pass / Phase 25 | no Chronicle page at 1280×720 under a third full unless it is the last |
| H21-21 | **CLOSED** (§16.1) — with the stated limit that the CI runner's process step on the failed attempt was not recorded | — | — |
| GA-01 (new) | the fixed-step assert guards the two `move_and_slide()` call sites that exist; a third call site added later is not covered by anything automatic | gameplay; whoever adds a mover | movers go through `MovementComponent`, or the lint learns to flag a bare `move_and_slide()` |
| GA-02 (new) | other owners that emit from inside a write (Quest, Inventory, Relationship) were NOT audited for the in-flight window; the Quest runtime has its own (`test_a_listener_that_answers_again_from_inside_the_payment_is_refused`), the others have none | each runtime's owner; before the phase that first makes them call each other inside a write (Phase 21 loot / Phase 22 rewards) | each has a test in which a listener writes back from inside the announcement |
| CLV-01, NAV-01 (Phase 21); Q19-01, Q19-02, AUD-15 (Phase 25); AUD-07 (Phase 26) | unchanged | | |

**Gate A stops here. Gate B1 was not started. Phase 21 and Phase 22 have not started.**

## 17. Gate B1 — interaction, the approach, what lies in the world, story continuity (`hardening/pre-phase21-gate-b1`, from `ddde137`)

> **Not a phase.** A regression audit of what §15 closed, plus two defects it reproduced and
> fixed. No dungeon, boss, drop system, save or networking; no wolf was retuned, no layout
> moved, no dialogue rewritten. It stops here; Gate B2 was not started.

**Preflight (2026-10-12).** `origin/main` `33919f9` (CI 38198759321, success);
`origin/hardening/pre-phase21-gate-a` `ddde137` (CI 38201518810, success, attempt 1) — approved
by the owner in words and **not merged into `main`**; this branch is cut from `ddde137` so it
carries Gate A's fixes. `CLAUDE.md` and `.kiro/settings/` untracked, untouched, never staged.

*An honest note on the base.* Between the preflight read and the `git switch -c`, the checkout
had been moved to `main` (reflog: `moving from hardening/pre-phase21-gate-a to main`), so the
branch was first cut from `33919f9` and the first probes and one gate run were made on that
tree (1241 tests — the number that gave it away). The branch had no commit of its own; it
was reset to `ddde137` with the three edited files carried across, and **every result in this
section was produced again on the right base**. L-056.

### 17.1 Evidence matrix

| Case | Old behaviour | Reproducer | Fix / test | Final | Owner | Debt |
|---|---|---|---|---|---|---|
| H21-15 exhausted dialogue (CLOSED) | — | `test_someone_with_no_trail_line_left_opens_on_their_hub`; Story E2E 8j | none needed. The guard was WIDENED: it walked only `stood`; it now walks both answers to the Night — 5 Origins × kept / told × stood / withdrew × (sheet in hand, door found), every line of all three people to exhaustion | PASS, no regression | Dialogue data | — |
| H21-15 in vi and en | — | `test_every_line_the_story_shows_exists_in_both_languages`, the dialogue catalog's translation check, `test_the_box_fits_under_the_clear_zone_in_both_languages` | none | PASS (automated); the exhausted hubs were not opened as captures in this gate | Dialogue / localization | — |
| H21-16 fair approach (CLOSED) | — | `test_nothing_the_player_must_reach_in_the_woods_is_inside_a_creatures_territory`, `test_the_shipped_wolf_left_alone_stays_on_its_ground`, the four `AiBrain` ground tests | none | PASS | AI data + field layout | — |
| H21-16 tuning not changed since the fix | — | `git diff 0623ff9^ HEAD` over the AI profile, the wolf, its bite, both spawn tables, `data/stats`, `data/characters` | none | only the two recorded changes exist: `patrol_radius = 32`, den (632,168) → (680,76). Detect 170, lose 280, leash 340, speeds, alert 0.35 s, bite 0.26 / 0.08 / 0.34 s, reach 26: unchanged | AI data | — |
| H21-16 in the real window, real keys | — | a scratch walk along the test's own `SAFE_WAY_TO_THE_SHAFT` (1280×720, 60 fps) | none | road → socket, stood 10 s, examined: IDLE / PATROL / RETURN only, nearest **208 px**, HP 100. socket → footpath → door, stood 5 s: nearest **219 px**, HP 100. Wolves strayed at most **42 px** from their dens. Door → west along the haul track to the wreck: ALERT / CHASE / ATTACK / RECOVER, nearest 18 px, HP 100 → **82** — still contested, as designed | AI / layout | GB1-03 |
| FG-3 pickups: whole or not at all, refused once, two underfoot, nothing absent drawn on arrival | — | `test_a_pickup_that_does_not_all_fit_stays_whole_in_the_world`, `test_two_held_things_underfoot_are_each_said_once`, `test_a_pickup_is_collected_once_for_the_whole_run`, `test_everything_lying_in_the_world_has_one_identity_a_cause_and_no_body`, world E2E (21 arrivals), playtest `05a_pickup_state` | none | PASS | Inventory owner | — |
| FG-4 nine arrivals agree with the story | — | Story E2E `_judge_arrival` | none | PASS — 9 arrivals, 0 disagreements (the two new steps add none: a refused exit is no arrival, and step 13's arrivals are judged like the rest) | World / Story | — |
| **N1 — a way out that fails still answered the Night (NEW)** | leaving a map answered the story's encounter BEFORE the router accepted the transition. A refused transition left the player in the woods with both creatures of the wave alive, and the story at `beat_aftermath`, `withdrew` recorded, the watchman's regard already −5, day light, and the morning card playing | real app, the router made to refuse the village (its scene path pointed at a missing file), the real exit pressed | `SceneRouter.transition_refusal()` (pure; the same checks `request_transition` refuses by) and `WorldRuntime._enter_map` asks it before it leaves anything. Story E2E **11a**; two router unit tests | red → green | WorldRuntime / SceneRouter | GB1-01 |
| **N11 — the fallen "stood" (NEW)** | a thunder bolt in flight when its caster was killed landed, killed the last creature of the wave, and the story recorded `stood`, moved to the morning and opened a story card while the defeat box was up | real app: a real `skill_2` key, the caster felled with the bolt in the air | `WorldRuntime._on_encounter_enemy_defeated`: the last one down answers only for a player still standing. Story E2E **13** (and the defeat acknowledged with a real key, back to a clean menu) | red → green | WorldRuntime | GB1-02 |
| a request made inside a transition is refused | claimed in §15.4; **no test existed** (mutation B5 survived) | `test_a_transition_asked_for_inside_a_transition_is_refused` | test added | PASS; B5 now red | SceneRouter | — |
| defeat: nothing chases a corpse; the box takes the key; a new run is clean | not probed before | real app: fallen on the exit, in the Night | none needed | wolves go IDLE / PATROL / RETURN; `interact` on the exit acknowledges the defeat and does NOT change map; second run: 100 HP, `beat_arrival`, no flags, no encounter, 0 creatures | World / HUD | — |
| the exit pressed under a conversation | "no test presses the exit under it" (§15.4) | real app: talking to the elder, the exit's own signal raised, `interact` ×3 | none needed | each press advanced the conversation; the map did not change | Input contexts | GB1-04 |
| withdraw, come back, come back again | E2E 11 covered the first leaving | real app, one of the wave killed first | none needed | `withdrew` once; village in daylight; the woods afterwards hold only the two standing wolves on every visit; wreck and spilled manual stay, stake gone | World / Story | — |
| every thing the player must reach can be WALKED to | not measured | real app: a flood of the walkable ground from the spawn (the real body, `test_move`, 6 px cells; ~11 900 cells in the village, ~13 900 in the woods) in five story states | none needed | every interactable, pickup and exit present in that state has walkable ground inside its reach (nearest 2–14 px, reaches 14–30 px) | Maps | — |

### 17.2 Everything standing or lying in the two maps

Read from both scenes instantiated and listed node by node, and from the runtimes that spawn. No
creature drops exist (a kill pays through the `RewardLedger`); nothing was added.

| Thing | Kind | Why it is there | There when | Owner · identity | How it is used | Body · reach | Can it double? | Cleanup |
|---|---|---|---|---|---|---|---|---|
| houses, hall, well, rack, fence, trees, boulders, banners, lanterns, planters (34 `WorldProp` / `PropBody`) | decoration with mass | the village and the woods | always | the map scene · node name | — | solid (footprint from `PropData`); none | no: built with the scene | freed with the map |
| carter's cart (village) / cart wreck (woods) | evidence | the caravan that broke in the Night | cart until `flag_vein_broke`; wreck from it | `StoryPresence` reads the story's flag · node | looked at | solid when present, no shape when absent | no | re-derived from the flag on every arrival |
| survey stake → stake socket | evidence → clue | someone pulled the stake overnight | stake until `flag_night_over`; socket from it | `StoryPresence`; the clue is `KnowledgeSource` `source_stake_socket` | `interact` → Knowledge Core (`know_stake_socket`) | stake solid; socket reach 20 | no: knowledge is granted once | — |
| survey shaft + its seal | landmark + clue | the sealed adit (Phase 21's door) | shaft always; seal examinable from `flag_night_over` | `WorldProp`; `KnowledgeSource` `source_shaft_seal` | `interact` → `know_sealed_shaft` | solid; reach 22 (prompt from 19 px before contact) | no | reserved marker: nothing opens it in this build |
| Lạc Hà stele | clue | the village's record | always | `KnowledgeSource` | `interact` → two entries, once | solid; reach 30 | no (`05e`: read 1 frame; re-read answers "nothing new") | — |
| survey sheet under the stone | clue — **not a bag item** | hidden where she said / found | from `flag_night_over` | `KnowledgeSource` `source_survey_sheet` | `interact` → `know_survey_fragment` | the stone is solid; reach 18 | no | — |
| claw furrows, gnawed bone (`WolfSign` ×2) | decoration that warns | marks the edges of the wolf's ground | always | `Visual/Decals` | walked over | none: a ground decal, walked over (§15.2) | no | — |
| Lạc Hà spring / the broken vein | cultivation site | where qi gathers | always | `CultivationSite` | the cultivate key | spring solid; vein none | no | — |
| 9 pickups (`WorldItem`) | pickup | §15.3's table | 8 always, the thunder manual from `flag_vein_broke`; three HELD until `flag_outpost_issue` | `InventoryRuntime` · `pickup_id` | walking onto it → one bag exchange | no body; reach 14 | no: `_collected` per run; hidden before the map is announced | taken whole or left whole; nothing persists past the run |
| stray hound | interactable | a pet to befriend | until befriended | `PetRuntime` · `interaction_id` | `interact` → owned once | reach 26 | no (`REFUSE_ALREADY_OWNED`) | hidden once owned; body freed on map change and brought back on arrival |
| four people (`WorldNpc`) | interactable | the cast | by the world simulation's presence | `NpcRuntime` · character id | `interact` → conversation (modal) | solid; reach 30 | no | — |
| training post | combat target | practice | always | `CombatRuntime` registry | struck | solid | no | — |
| two standing wolves (woods) | spawned creature | the woods' own | on every arrival in the woods | `CombatRuntime` · `map__enemy__index`; reward id unique PER SPAWN | fought | body | they come back on re-entry **by design**; each spawn pays once (`RewardLedger`) | despawned on leaving |
| the Night's two (wave) | spawned creature | the rupture | once, after the rupture scene ends | `CombatRuntime` · tagged `map_field__night__…`; the story's encounter | fought, or left | body | **never twice in a run** (E2E 11; probe: three visits) | gone with the map; answered `stood` / `withdrew` once — now only by a player who left or still stands |
| the player | — | — | one per run | `WorldRuntime` | — | body | one throughout (E2E counts) | defeat ends the run at the box; a new run starts whole |

Nothing in the table is a clue stored as a bag item, decoration that is picked up, or a pickup
with two reward paths.

### 17.3 Route map — New Game to the sealed door

`menu → identity (cancel leaves nothing) → run (one, on a doubled confirm) → Origin vignette
→ arrival [village, day] → three people → trust choice (kept / told) → warning card
[village, dusk] → exit → [woods, NIGHT] rupture card → wave (only after the card) →`
**`stood`** `(last one down, player standing)` *or* **`withdrew`** `(the exit, accepted)` `→
morning card [day] → elder's account → first sitting → the sheet → farewell → Act I: whom to
show (kept: three; told: two, her refusal once) → socket → ruts → sealed door → rests.`

Side exits now pinned: **a way out the router refuses → nothing happens** (11a); **defeat at
any point → the defeat box, one key, the menu; the story answers nothing after it** (13).
Walked by the Story E2E with real keys: 25 recorded steps over three runs (two Origins; stood
and withdrew; kept and told; the third is the short run of step 13). Real window (`playtest_flow`): 38 / 38
steps at 1280×720 vi and 1280×800 en, 0 errors, frame pacing mean 16.66 ms.

**Opened and looked at (this gate, 1280×720):** the socket (player on the dark earth, prompt
*Examine*, purpose *Look where the stake stood*, the wreck with its spoked wheel and the
manual beside it in frame); the door (boarded, the wolf visible 219 px north and not
coming); the haul track (the wolf on the player by the wreck, its plaque up, HP 82, purpose
*Follow the old cart track*). **Generated and not opened:** the 80 playtest frames of the two
runs (their step observations were read; the images were not).

### 17.4 Mutations — 7 applied, 7 red (one only after its test was written)

B1 the world no longer asks before leaving · B2 the router foresees no missing scene · B3 the
fallen still answer · B4 `request_transition` skips validation · B5 no refusal inside a
transition (**survived first**: no test existed; red after one was added) · B6 an
unregistered scene foreseen as fine · B7 the last-one-down check ignores those still standing.

### 17.5 Debts after Gate B1

| ID | State | Owner | Closes when |
|---|---|---|---|
| H21-14 | **OPEN / OWNER REQUIRED** — no person has played this build | the project owner | §17.6 has been played and written down |
| H21-20 | unchanged | presentation / the UI pass | as §13 |
| GB1-01 (new) | a scene file that EXISTS and then fails to load or instantiate is refused only after the encounter was answered. Not reachable in a healthy build; the foreseeable refusals are closed | WorldRuntime; Phase 21 (the first new map transitions) | the encounter is answered after the router has accepted, or the router can stage a scene before it commits |
| GB1-02 (new, decided not a defect) | a bolt already in the air still lands, kills and pays its XP after its caster falls | Combat | only if the owner wants a fallen caster's bolts to die with them |
| GB1-03 (new) | the real-key walk of the safe way is a scratch probe, not a committed step of `playtest_flow` (which stages the socket and door by placement) | tools; Gate B2 or Phase 21 | `playtest_flow` walks the road → socket → door with held keys and reports the wolves' states |
| GB1-04 (new) | exit-under-conversation, defeat-on-the-exit and the reach flood were probed in the real app but are not committed tests (11a and 13 are) | tests; Phase 21 | each is a step of an E2E |
| GA-01, GA-02 | unchanged (§16.5) | | |
| CLV-01, NAV-01 (Phase 21); Q19-01, Q19-02, AUD-15 (Phase 25); AUD-07 (Phase 26) | unchanged | | |

### 17.6 Checklist for a person (H21-14 — NOT played by this task)

Launch `~/Downloads/Godot_v4.7.2-stable_linux.x86_64 --path . --resolution 1280x720`. New Game,
no shortcuts. Write the answers down; "nothing odd" is an answer.

1. §11's eight points, as written.
2. In the woods by day: follow the road east and the footpath up to the boarded door. Did
   anything come for you? Then go back by the old cart track past the claw marks. Did you
   understand, before it happened, that this way was dangerous?
3. At the door: how close did you have to stand before *Examine* appeared? Did it feel late?
4. During the Night, walk out through the exit. Is it clear afterwards that leaving WAS your
   answer? Go back in: is anything there that should not be, or missing that should be?
5. Let the Night kill you once. Is the defeat clear, is there exactly one thing on screen
   asking for a key, and does the next New Game start clean?
6. Talk to each of the three until they have nothing left about the sheet. Does anyone greet
   you with a line that leads nowhere? Repeat once in the other language.
7. Stand on two pickups at once with a full satchel. How many times were you told?

**Gate B1 stops here. Gate B2 was not started. Phase 21 and Phase 22 have not started.**

## 18. Gate B2 — the debts paid, the visual audit, the first step of the UI refresh (`hardening/pre-phase21-gate-b2`, from `367312d`)

> **Not a phase.** Three things the owner asked for in one message: pay every debt a tool can
> pay, run Gate B2, and — with the UI refresh now explicitly authorized — make the UI better,
> judged against six reference screenshots from other games (**analysed, not copied**; they
> are not in the repository). No dungeon, boss, drops, save or networking.

**Preflight (2026-10-12).** `origin/main` `33919f9`; Gate A `ddde137` and Gate B1 `367312d`
approved in words, **not merged into `main`**; this branch is cut from `367312d` **by SHA**
(L-056), read back after the switch. `CLAUDE.md` and `.kiro/settings/` untracked, untouched.

### 18.1 Debts

| ID | Was | Now |
|---|---|---|
| GB1-01 | a scene that exists and fails to load was refused only after the encounter was answered | **CLOSED.** `SceneRouter.transition_committing`: announced once the new scene is loaded and instantiated, before the old one is freed. `WorldRuntime` does its irreversible leaving there. Story E2E 11b (a real resource that is not a scene); a router unit test; mutation red |
| GA-01 | a third `move_and_slide()` would be guarded by nothing | **CLOSED.** Lint GD004: in `src/`, a body moved with no fixed-step assert on the two lines above. Seven selftest cases; mutation red |
| GA-02 | other owners not audited for the in-flight window | **CLOSED.** Four found, each red on a listener test before its guard: `InventoryRuntime.use` (one stone gave the whole realm step, 30 for 7), `EquipmentRuntime.equip / unequip`, `ShopService.transact` (the last sword bought twice), `DialogueRuntime.choose / advance` (a second answer accepted). Already guarded: Story, Quest, Reward. Write-then-announce (no window): Knowledge, Relationship, Progression, the bag's `give / take / exchange` |
| GB1-03 | the safe way was a scratch probe | **CLOSED.** `playtest_flow` 21c walks the test's own `SAFE_WAY_TO_THE_SHAFT` with held keys. Real window: IDLE / PATROL / RETURN only, nearest 197 px, no health lost; the haul track still draws a chase |
| GB1-04 | probes, not tests | **CLOSED.** Story E2E: the exit under a conversation; fallen on the exit (nothing hunts the body; the key changes no map); and `reach` at three points — 11, 7 and 9 things, each with walkable ground inside its reach |
| CLV-01 | a shop's keeper not validated | **CLOSED as a content rule.** Every shipped shop is kept by someone who stands in a shipped map. *The runtime check its row asked for was rejected:* a keeper who lives in another map is realized only when that map is entered, so "not in the registry at session start" is the normal state of the shipped shop |
| H21-20 | 10 Chronicle pages at 1280×720, three nearly empty | **CLOSED.** A section that ran a few lines over now shares them out (`_even_out`): no page followed by another of its section is under a third full, at both windows, in both languages; nothing split, dropped or reordered. The book is still 10 pages at 720 (8 at 800): what changed is that each reads as a page. A section whose ONE page is short holds little; that is its owner's to say |
| GB1-02 | a bolt outlives its caster | unchanged — decided, not a defect |
| H21-14 | nobody has played it | **OPEN / OWNER REQUIRED** |
| NAV-01 (Phase 21); Q19-01, Q19-02, AUD-15 (Phase 25); AUD-07 (Phase 26) | | **unchanged, and not paid here:** each needs the thing its phase builds — rooms to route through, a fifth concurrent quest, the unified modal seam. Paying them now would be building those phases |

### 18.2 Visual audit (B2)

| Item | Evidence | How it was looked at | Result |
|---|---|---|---|
| H21-17 carts | committed source `model/props3d.py` (`_wheel`: rim, six spokes, hub); `cart.png` 76×60, 16 colours; `cart_wreck.png` 110×54, 17 colours; data origins and footprints as recorded | art-sheet review at 5× and 1×; real window at 1280×720 vi and 1280×800 en for both (four frames opened as one montage). Language does not touch the geometry | PASS — no regression. Intact: a spoked wheel on the near end, bed, striped canvas, shafts. Wreck: the lost wheel spokes-up, canted bed, burst crate, pale shards. Never together: the E2E's arrival judge holds each to `flag_vein_broke` |
| H21-18 the Night's bite | `capture_motion night_bite` ×4 (vi / en × 720 / 800) | the vi 720 strip opened and read cell by cell; all four timing files read; the telegraph's strongest pixel measured in four wind-up cells of all four strips | PASS — wind-up → ACTIVE **266 ms**, → RECOVERY **349 ms** (authored 0.26 / 0.08 / 0.34 s). The tell: the crouch and the reach arc from the second wind-up cell (15 ms). Red-over-green **57** at 15 ms, **109** at 165 ms, identical in all four. The three other strips' images were not opened |
| H21-19 the light's cost | `measure_ambience_frame_time.gd`, re-run once at each window (3 × 6 s) | the two reports read | reproducible: worst case (night, three lights in frame) median **1.025 → 1.757 ms (+0.73)** at 720 and **1.086 → 1.858 ms (+0.77)** at 800, against the recorded +0.69 / +0.75. Simple frame-time sampling on one machine — **not the engine profiler**; Phase 29's |
| capture matrix | **251 frames**: `capture_ui` vi / en × 1280×720 / 1280×800 (51, 51, 49, 49; 0 script errors), `capture_motion` cultivation, dialogue, quest (5, 16, 18), `night_bite` ×4 (3 each) | a manifest (`manifest.json`: file, size, hash, group) and 19 contact sheets, in scratch. **13 sheets reviewed**; 6 not (vi 800 sheet 1, en 720 sheet 3, the four `night_bite` sheets — the vi 720 strip itself was opened). About a dozen frames and four montages opened at full size | one real defect found and fixed: the English satchel read "Travelling c…" (below) |

**Not captured by any tool, so not judged (BLOCKED):** the other three Origins' vignettes;
each person's exhausted hub as a frame (held by test, §17.1); the satchel with something
worn (the Chronicle's body page shows the same card filled).

### 18.3 The UI refresh, first step — the character is a figure

What the reference screens do that this one did not: the character stands on the sheet. Here
they existed as lines of text.

- **`CharacterCard`** (`src/presentation/character/`): the player's own sprite — the same
  `CharacterVisualComponent` the world draws with, so the garment is the garment — breathing
  at an integer scale in a well, between two slots (what is in the hand, what is on the
  back; an empty slot says what it is for) and the three numbers combat reads. It owns
  nothing: body and worn rows from `InventoryView`, numbers from `ChronicleView`. Hidden, its
  figure does not process.
- **The satchel is a sheet**: the card in a column beside the list (`SHEET_PANEL_WIDTH`, 460
  px, a named token; the panel is modal).
- **The Chronicle's body page** is headed by the same card.
- **Kept on purpose:** no minimap, no MP bar, the centre clear, the HUD inside its budget.
  The references have a minimap and an MP bar; the project's own rules forbid both and the
  owner was asked and has not changed them. The crowded-screen reference is multiplayer.

*Found by looking, and fixed:* the Chronicle's card showed the robe's name beside an empty
slot (the book feeds a card before it enters the tree); the first sheet was 496 px wide and
covered the start of a centred notice (now 460); the English caption was cut ("Travelling
c…": names now wrap, two lines at most). Each has a test.

*Honest limit.* This is one component in two places. It does not make the game look like the
references: the world's light and density, the size of the actors on screen and the look of
the other panels are untouched, and those are most of the difference.

### 18.4 Tests and mutations

Suite **1261** (was 1250). Story E2E **27** recorded steps (was 25). `playtest_flow` **39**
steps (was 38), 0 errors. Mutations **12 applied, 12 red** — one only after its test was
tightened (a clipped slot name passed a test that counted lines): the commit point, the lint
rule, the four owners' guards and one release on refusal, the keeper check, the card's
icons, its sleeping figure, the evened pages, the uncut name. *Not mutated:* the E2E's
`reach` judge (no prop was moved onto a path to see it fail).

### 18.5 Debts after Gate B2

| ID | State | Owner | Closes when |
|---|---|---|---|
| H21-14 | **OPEN / OWNER REQUIRED** | the project owner | §17.6 played and written down |
| UI-01 (new) | the refresh is one component: the other panels (sect, politics, journal, shop), the HUD's density and the world's look are as they were | presentation; the owner's next UI brief | the owner says which surface is next, with the minimap / MP-bar rule decided |
| UI-02 (new) | the satchel's own card has not been captured with something worn | tools (`capture_ui`) | a frame of the satchel taken after the robe is put on |
| B2-01 (new) | six contact sheets of the matrix not reviewed; the `reach` judge not mutation-tested; three Origins' vignettes not captured | whoever closes the matrix next | reviewed, or captured |
| GB1-02 | decided | Combat | — |
| NAV-01 (Phase 21); Q19-01, Q19-02, AUD-15 (Phase 25); AUD-07 (Phase 26) | unchanged | | |

**Gate B2 stops here. Gates C1 and C2 were not started. Phase 21 and Phase 22 have not started.**

## 19. Visual Craft Upgrade — a reusable design workflow, two proofs, the tool-closable debts (`d063/phase-a`, from `5908fb8`)

> **Not a phase.** The owner's brief: find out *why* the build reads as flat beside nine
> reference frames from other cultivation games (**analysed, never copied; not in the
> repository**), turn the answer into a method later phases can reuse, prove the method on
> two surfaces, and close what a tool can close. No palette replacement, no shader framework,
> no minimap / MP bar / chat / skill ring, no lore, no multiplayer. Phase 21 is not started.

**Preflight (2026-10-12).** `d063/phase-a` at `5908fb861afe3a69010c6493b1fc54e634ad5b00`
(= `origin/main` `0fd6adc` + one docs commit), CI green on it (run 38235777537). `CLAUDE.md`,
`.kiro/settings/` and the reference zip are untracked and were not staged.

### 19.1 Baseline — what the build was, measured before anything changed

Evidence: a fresh real-window matrix (236 frames: vi/en × 1280×720/1280×800, the five Origin
vignettes, the golden combat frame), every one of its 15 contact sheets opened; the benchmark
on the golden frame; a composed overview of the whole village.

**Strong.** One pixel density, crisp (benchmark pixel readability 100); figures separate from
the ground (character 96.5); a painted floor with organic material edges (environment 93.7);
a consistent dark-lacquer UI kit; no layout break in any of the 236 frames in either language.

**Flat, with the evidence.**

| # | Finding | Evidence | Root cause | Type |
|---|---|---|---|---|
| F1 | The frame has no value range | benchmark `contrast` 0.105 against the reference's 0.181; luminance bands `[0.02, 0.38, 0.56, 0.04, 0.0]` — 94 % of the playfield in the two middle bands | every ground material sits in the same mid-values; nothing is meant to be the lightest or the darkest | palette/lighting |
| F2 | The village has no subject | the spring that bears its name (and where the first cultivation happens) was a 52×30 px basin on the corner of the square, on the square's own flags; no line led to it | the layout was drawn *around* gameplay anchors, never *about* one | composition |
| F3 | Vegetation is sprinkled | eight trees, each alone on a lawn — against the DNA's own "vegetation clusters, never sprinkles" | props placed one by one; no ground mass under them | composition |
| F4 | On the character sheet the person is the smallest thing | figure 64×96 px in a 76 px well in a 136 px column, **8 px right of the well's middle** (measured by the new test); three stat plates with their numbers ending at x = 95 / 87 / 94 | the card was built as a list head, not as a stage | UI composition |

**Rule owners** are the table at the top of `docs/VISUAL_CRAFT_WORKFLOW.md`. **Reusable
capabilities used:** the ground painter's material kinds, layout YAML, scene sync,
`CharacterVisualComponent`, `UIPalette → UITheme`, `capture_ui` / `capture_motion`, the
benchmark. Blender was not needed (the `blender-pro` session was not running; nothing here
required a new prop).

### 19.2 The method

`docs/VISUAL_CRAFT_WORKFLOW.md` — six stages (intent, composition, reference → original,
production, motion, measure), a one-screen brief, and the nine reference analyses recorded as
principles. It owns no rule; it links to the owners. Entry points: `.kiro/steering/06-art-assets.md`
§ Visual craft, the *Visual craft review* gate in `.kiro/steering/08-ai-review-protocol.md`, the
knowledge hub §F and the dependency map.

### 19.3 Proof W1 — the Lạc Hà spring court (world composition)

```
VISUAL DESIGN BRIEF — W1 the Lạc Hà spring
Intent        : about the spring that bears the village's name; first second: "that water is the
                heart of this place"; serves the prologue (the spring "misses a beat") and the
                first deliberate cultivation
Evidence      : F2, F3 above; village overview before
Focal point   : the basin, where the west road meets the square — wins by value (the lightest
                ground with the brightest water inside the darkest ring) and by converging lines
Reading order : 1 the water  2 the court's rings  3 the runnel back to the stream / the hall
Value plan    : lightest = court paving and water; darkest = the wet ring and the undergrowth
Masses/lines  : trees gathered into groves over undergrowth; lead-in = the road's end and the
                spring's overflow runnel from the stream
Quiet area    : the square east of the court and the meadow south of it stay plain
View check    : everything added is GROUND — nothing can stand in front of an NPC or a pickup;
                the one added tree (TreeS2) stands south of the south grove, clear of the lane
References    : R1, R3, R5, R7, R9 (workflow § Reference notes)
Built from    : three new KINDS in the existing painter — `court` (stones laid in rings round
                an `ellipse`), `rill`, `lush` — and layout data; vo_mach floor and layout data
                repaint to the SAME bytes
Motion        : none — not a verified weakness (the qi well already animates on the basin)
Rules touched : canon kept (a frontier village: dressed stone and a runnel, no blossom, no
                altar); HUD untouched; no collision change (the runnel is INTANGIBLE_BY_DESIGN)
Rejected      : a great tree over the spring (R3/R7's own answer): at 30° top-down its canopy
                projects north over the west road, Lâm Nguyệt and the well
Measure       : see 19.5; tests test_the_lac_ha_spring_stands_at_the_centre_of_the_floors_
                lightest_ground, test_the_springs_runnel_is_drawn_but_never_blocks,
                test_the_hub_keeps_every_swaying_tuft_that_stands_on_turf; mutations 5/5
Still wrong   : F1 is NOT fixed by this (19.5) — VC-01
```

Three things were wrong on the way and are why the tests exist. **(a)** The first court was
*darker* than the square (paving 0.51 mean luminance against 0.54): small stones mean more
mortar, and it used the square's dark mortar. The brief said "lightest"; only measuring said
otherwise. Now 0.61–0.66 by quarter, against 0.54 (square) and 0.45 (meadow). **(b)** The scene
sync dropped six swaying grass tufts — those standing on the new undergrowth, which it did not
count as turf. **(c)** The test's first comment carried luminance figures written *before* they
were measured; they were wrong and were replaced by the measured ones (L-058).

### 19.4 Proof U1 — the satchel's figure is its subject (character/UI composition)

```
VISUAL DESIGN BRIEF — U1 the satchel sheet
Intent        : about the PERSON carrying the satchel; first second: "that is me, wearing
                this"; serves equipment (the garment worn is the garment drawn)
Evidence      : F4 above; frame 11_satchel_worn before
Focal point   : the figure — wins by scale (3x, the largest thing on the sheet) and by standing
                alone on a stage the width of the column, on a dais
Reading order : 1 the figure  2 what it wears (two slots)  3 the numbers  4 the list
Value plan    : the figure's own colours against the plate; numbers in gold on one right edge
Masses/lines  : three plates become ONE ledger; numbers align on an edge
Quiet area    : the stage round the figure holds nothing else
References    : R6, R8
Built from    : `CharacterCard` (tall mode only), two named `UIPalette` constants; the same
                views as before; the Chronicle's band is unchanged
Motion        : none added — the figure already idles; it still does not process while hidden
Rules touched : SHEET_PANEL_WIDTH kept (460 px: clear of a centred notice); modal, so the HUD
                budget does not apply; both languages
Rejected      : slots in a ring round the figure with stats on a radar (R8): needs a wider
                sheet, which would cover the centred notice the 460 px limit protects
Measure       : see 19.5; tests test_the_satchels_figure_is_the_largest_centred_and_drawn_whole,
                test_the_satchels_numbers_stand_in_one_column_with_whole_names; mutations 5/5
Still wrong   : the slots sit under the figure, not at the hand and the body — UI-01
```

### 19.5 Measured, before → after

| Measure | Before | After | How |
|---|---|---|---|
| Ground given to the spring | basin sprite only, 52×30 px on the square's flags | a 108×62 px laid court centred on the anchor (5 259 px², 2.3 % of a 640×360 view) | layout data |
| Court paving, mean luminance by quarter | — | 0.61 – 0.66; square 0.54; meadow 0.45 | the test, on the shipped texture |
| Lines that end at the spring | 0 | 2 (the west road's end, the runnel) | layout |
| Trees standing alone | 8 of 8 | 3 of 9 (three groves of two, over undergrowth) | layout |
| Swaying tufts in the hub | 27 | 27 | test |
| Figure on the sheet | 64×96 px, 8 px off-centre, 2 px outside its well | 96×144 px, centred, whole (2.25× the area) | test |
| Stat numbers' right edges (vi) | 95 / 87 / 94 px | one edge | test |
| Rows of the list visible at 1280×720 (en) | 5 | 6 | capture |
| Benchmark total (golden combat frame) | 80.6 | BENCH_TOTAL | `visual_benchmark.py` |
| Benchmark palette / lighting | 59.7 | BENCH_PALETTE | same |
| Benchmark `contrast` | 0.105 | BENCH_CONTRAST | same |
| vo_mach floor + layout data | — | byte-identical | md5 |
| lac_ha floor across hash seeds 1 / 2 / 7 | — | byte-identical | md5 |

**Read the benchmark rows honestly.** The golden frame looks at the training yard; the court is
at its edge. The frame-wide weakness F1 is essentially where it was. W1 gives *one place* a
value range; it does not give the game one. That is VC-01 below, and it needs a decision about
light, not another floor material.

Validation: PLAYTEST_LINE Frame time: FRAME_LINE

### 19.6 Debts a tool could close — closed

| ID | Was | Now |
|---|---|---|
| B2-01 | six contact sheets not reviewed; `reach` judge not mutation-tested; three Origins' vignettes not captured | **CLOSED.** All 15 sheets of the new 236-frame baseline opened (no layout break found). The `reach` judge mutated: a pickup moved inside the outpost hall → step "reach. the village, day one" FAIL, exit 1; restored. All five Origins' vignettes captured, 7 steps each (`capture_ui.gd -- <lang> <dir> vignette <origin_id>`) |
| UI-02 | the satchel never captured with something worn | **CLOSED.** Frame `11_satchel_worn` (blade and robe worn) is part of every `capture_ui` run; the blade is put back afterwards so later frames keep their numbering |

### 19.7 UI-01 — owner decision brief (nothing here is implemented)

**The rule today** (`docs/UI_UX_BIBLE.md`; CLAUDE.md §12): permanent HUD ≤ 15 % of the screen,
the centre 50 % × 50 % clear, no minimap, no MP bar, no chat, no skill ring. Every reference
frame with a HUD has a minimap; several have an MP bar.

**What the rule costs, as observed.** Nothing in the audit failed *because* of it. The
references' minimaps answer "where do I go" — which this build answers with the purpose line
and with composition (roads, the runnel). No MP bar is missed while techniques cost nothing a
bar would show.

| Option | What changes | Cost |
|---|---|---|
| **A — keep the rule (recommended)** | nothing; the next surfaces to compose are the sect / politics / journal / shop panels and the slot placement on the sheet | none |
| B — a map as a MODAL (opened, never permanent) | a new panel fed by map data | a new feed and owner; Phase 21+ content decides if it earns it |
| C — allow a permanent minimap | HUD budget and the R-7 / R-13 identity rules reopened | a design-freeze amendment; every map needs minimap art |

**Question for the owner:** A, B or C — and which surface is composed next?

### 19.8 H21-14 — still OPEN / OWNER REQUIRED

Not played by this task; no tool can close it. The checklist is §17.6. Two additions for what
changed here, and a recording template:

8. Arrive by the west road. Before reading anything: what on the screen do you look at first?
   Did the runnel and the court read as *the spring*, or as decoration? Did you try to walk
   round the runnel, or straight over it?
9. Open the satchel with the robe on, then with the blade too. Is the figure the first thing
   you see? Can you read Attack / Defense / Speed at a glance?

```
H21-14 record — date, build SHA, language, window
Step | What I did | What I expected | What happened | Odd? (y/n) | Note
```

### 19.9 Debts after this run

| ID | State | Owner | Closes when |
|---|---|---|---|
| H21-14 | **OPEN / OWNER REQUIRED** | the project owner | §17.6 + §19.8 played and written down |
| UI-01 | owner decision pending (§19.7); slots on the sheet still sit under the figure | the owner, then presentation | A / B / C answered; next surface named |
| VC-01 (new) | the frame-wide value range is unchanged (F1): `contrast` ≈ 0.11 against 0.18 | art direction (a light / time-of-day decision; global palette changes were out of this brief) | the golden frame's palette/lighting category ≥ 70 without a new shader framework, or the owner accepts the current range |
| VC-02 (new) | the forest map (`vo_mach`) has had no composition pass | whoever takes the next visual brief | a W-brief for one of its landmarks |
| NAV-01 (Phase 21); Q19-01, Q19-02, AUD-15 (Phase 25); AUD-07 (Phase 26) | unchanged | | |

C2 remains **PROPOSAL — NOT CANON**; Q-02 is unresolved; no lore, chronicle scope, multiplayer,
networking or persistence was decided or built.

**Phase 21: NO-GO.** H21-14 is open and only the owner can close it. This run stops here.
Phase 21 and Phase 22 have not started.
