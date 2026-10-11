# Handoff — Post-Phase-20 experience hardening / pre-Phase-21 gate (D-073)

> **Status: IN PROGRESS — Checkpoint 0 (Gate A, docs only).** This is a bounded quality pass
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
by what the Origin KNOWS (the Knowledge Core's answer), three by who they were:

| Origin | Opened by | With | What only they notice (an observation, then a CLAIM in reply) |
|---|---|---|---|
| Thủ Thư Cấm Lục | `know_survey_notation` | Lâm Nguyệt | the word *level* on the sheet is in a second hand |
| Nghệ Nhân Thất Sủng | `know_vein_stone_grades` | Kha Thản | the stones he is paid in have raw bases: nobody ever counted them |
| Hộ Tiêu Thất Bại | Origin | Kha Thản | the ruts are deep going out and shallow coming back — as on the morning the convoy was lost |
| Lang Y Du Phương | Origin | Kha Thản | the watchman's nails are clean; whatever greyed the carter's hands, the watch never handled it |
| Đệ Tử Bị Loại | Origin | Lâm Nguyệt | the cord on the seal is tied with the knot the examiners used on the trial board |

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

## 5. Gate A — every new thing, its reason, its owner (*planned*; filled in as content lands)

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

New numbers and their one home are added to this table by the checkpoint that authors them
(the three regard moves above live in `tools/author_story_data.py`, like every other).

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
| 0 | Audit, Gate A, D-073, status drift corrected. No gameplay code | *(this commit)* | recorded by the next commit |
| 1 | The Act-I bridge and the choice transaction | | |
| 2 | The Night: ambience, the wreck, the socket and ruts, the creatures | | |
| 3 | The Chronicle and the cultivate / recovery rule | | |
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

## 12. Status

Checkpoint 0 only. Nothing player-facing has changed yet. **Phase 20 is DONE (D-072). This
pass is IN PROGRESS. Phase 21 and Phase 22 are NOT STARTED.** No person has played the build.
