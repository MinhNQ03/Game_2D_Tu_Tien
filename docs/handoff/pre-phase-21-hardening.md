# Handoff — Post-Phase-20 experience hardening / pre-Phase-21 gate (D-073)

> **Status: IN PROGRESS — Checkpoints 1–3 built (the bridge, the choice transaction, the Night shown, the Chronicle, the cultivate rule).** This is a bounded quality pass
> between two phases. **It is not a phase.** Phase 20 (Story) is and stays **DONE** under D-072;
> Phase 21 (Dungeon) and Phase 22 (Boss) are **NOT STARTED** and nothing here builds them.
> A section marked *planned* is what Gate A decided and has not been built yet; *built* means
> it is on the branch with its tests. The status line and §12 are rewritten at close.

## 1. Baseline (verified, not assumed)

| | |
|---|---|
| Branch | `hardening/pre-phase21-experience` — the ONE branch of this task |
| Base | `4dd38ec4d35650c35f69be93c234f9db1ca1fcf6` = `origin/main` = `origin/feature/phase-20-story` at preflight (2026-10-11, after `git fetch --prune`) |
| CI on the base | run 38132418506, branch `main`, `head_sha` `4dd38ec…`, success (read back with `gh run view`) |
| Other refs at preflight | local `main` `4420eae` (8 behind `origin/main`, untouched); `origin/feature/phase-19-quest` `b768935`; `origin/d063/phase-a` `8f3ccbd`; `origin/fix/pre-phase20-readiness` `4420eae`; no tags; one workflow (`ci.yml`) |
| Phase state on the base | `ROADMAP.md`: Phase 20 DONE, Phase 21+ NOT STARTED. No dungeon / boss code or data in the tree |
| Local baseline before any edit | on the base tree: import clean; **1188 / 1188** tests, 0 `SCRIPT ERROR`, 0 leak lines (either wording); Story E2E `RESULT: PASS` |
| Real window before any edit | `tools/capture_ui.gd -- vi` at 1280×720: 36 captures, exit 0. Opened: `23_night_wave_and_wreck`, `22_night_rupture_caption`, `26_chronicle_page_2`, `26_chronicle_page_4` (what they show is in §2) |

`CLAUDE.md` is user-owned and untracked. It is never staged, moved or edited by this task.

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
| 3 | The Chronicle and the cultivate / recovery rule | *(this commit)* | recorded by the next commit |
| 4 | Full regression, the capture matrix, docs, debt register, Phase-21 handoff | | |

## 10. The Phase-21 handoff (*filled at close; the lead as designed*)

- **The lead.** The Survey Shaft (*Hầm Khảo Mạch*) in the north-east rocks of Rừng Vỡ Mạch:
  on paper sealed since winter, in fact used within days of the Night.
- **Why go in.** The rest of the survey the player holds one page of; and whatever was being
  brought out of it in crates.
- **Access.** Legible before passable (`MAP_DUNGEON_DESIGN.md` §3 rule 2): the bar is cut for
  the head of a surveyor's rod. Kept faith → Lâm Nguyệt still has a rod. Told → hers is in the
  elder's keeping. Both must reach the same door; how each gets a rod is Phase 21's to author.
- **Must reuse.** `StoryService` (beats, choices, flags), `StoryPresence`, the encounter seam
  (`StoryBeatData.encounter_*`, tagged spawn tables), `CombatRuntime.spawn_from_table`,
  `RewardLedger`, the Knowledge Core, the ambience seam (a shaft is dark by the same data), the
  Chronicle. Debts it already owns: CLV-01, NAV-01.

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
| H21-15 | after all of a person's trail lines are said they still open on the trail line with only *Speak of something else*: one wasted press per talk | an opening's conditions are AND-only; "any line left" needs an OR or a derived flag, which is a dialogue-data change with its own tests | Dialogue data; Phase 21 (the first phase that adds the next lines to these people) | a test opens each of the three with every trail flag set and lands on the hub | no |

## 14. Status

Checkpoints 0–1. **Phase 20 is DONE (D-072). This pass is IN PROGRESS. Phase 21 and Phase 22
are NOT STARTED.** No person has played the build.
