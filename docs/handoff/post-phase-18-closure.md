# Post-Phase-18 closure verification — evidence, targeted fixes, Phase-19 readiness

> Stage report for the bounded verification run between the post-Phase-18 audit
> (`post-phase-18-audit.md`, D-067 / D-068) and Phase 19. Decisions: D-069. Lesson: L-047.
> **Phase 19 gameplay has NOT started.** No quest, story flag, loot table, dungeon, boss,
> save file or network code was added.

## 1. Baseline and result

| | Value | How it was verified in THIS run |
|---|---|---|
| Starting SHA | `f3fe408` on `main` and `d063/phase-a` (identical) | `git rev-parse HEAD origin/main origin/d063/phase-a` |
| Starting CI | run 38061347311, `success`, `head_sha` = `f3fe408` | `gh run list` |
| Baseline suite, re-run locally on `f3fe408` | 986 passed, 0 failed, 0 `SCRIPT ERROR:`, 0 leak lines | the runner's own tally (not the earlier report's) |
| Working branch | `d063/phase-a` (`main` untouched; no merge, no force-push) | `git status --short --branch` |
| Working tree | clean except untracked, user-owned `CLAUDE.md` (never staged) | `git status` |

Commits of this task, in order (the final SHA and its exact-SHA CI run are recorded in
`ROADMAP.md`'s status block by the closing commit, as every phase closure does):

| Commit | What | Why |
|---|---|---|
| `22c3508` | `fix(dialogue)`: speaker validation + re-entrant close | Finding C; a reproduced crash (§3) |
| `fb902c4` | `docs(closure)`: GAME_FLOW status, Phase-19 persistence boundary | Findings A and D |
| `bef8a4b` | `fix(hud)`: prompt strip under shop / satchel | a PX-4 defect found in a capture (Finding B) |
| the docs commit | D-069, L-047, TEST_PLAN, this file | closure |

## 2. Evidence labels

**SOURCE** read in the code · **TEST** the in-runner suite · **E2E** the six committed
isolated flows · **PLAY** the real application in a real window (`DISPLAY=:0`, 1920×1080
desktop), the PNG opened and looked at.

## 3. Findings

### Source-confirmed issues (fixed)

**CL-C — a dialogue speaker was never validated (SOURCE → TEST).**
`DialogueService.content_errors` checked knowledge ids, dimensions, thresholds, shops and
translations, and not `speaker_id`. Because `DialogueRuntime.talk` finds a conversation by
the character addressed, an orphaned speaker was silent, unreachable content. No equivalent
runtime guard existed; the only check was a test over the shipped catalog.
*Fix:* a registry-resolver seam on `content_errors`; `DialogueRuntime.start_session` fails
closed on an unregistered speaker and on a world with no registry. Registration is asked —
not a body in the current map (D-069 §1).

**CL-R — a listener that ends the conversation crashed the runtime (TEST, reproduced first).**
`_follow` read `_dialogue` after emitting `choice_made`; `talk` entered the first line after
emitting `dialogue_opened`. A listener that closes the conversation in response left a
`SCRIPT ERROR` (`.node()` on null) and a stale cursor. Not reachable through a shipped
listener today; it is the documented behaviour of a surface yielding to a threat, and the
first thing a quest listener would do. *Fix:* the order of events is unchanged; after each
emit the runtime checks it is still in the conversation it was moving (D-069 §2).
`_follow`'s order (announce → close → open the shop) was otherwise found correct and kept: a
handoff the shop refuses closes the conversation, opens nothing, and is answered by
`NpcRuntime` — now pinned by a test.

### Visual-evidence gap (closed) and the defect it exposed

**CL-B — PX-5 asked for four language / size combinations; three had been recorded.**
All four are now captured on the final tree and opened (§5).

**CL-S — the prompt strip lied under the shop and the satchel (PLAY → SOURCE → TEST).**
Seen in the shop-handoff frame: "J Attack · T Sect · Y Politics · Esc Menu" beside the shop's
own "Esc Leave", in a UI_MODAL context where none of the four acts. *Fix:* the strip stands
down under every modal surface (D-069 §3). Re-captured: gone under the shop and the satchel.
Severity P2 (usable, contradictory key labels), fixed because it was small and safe.

### Documentation drift (corrected)

- `GAME_FLOW.md` §1: cảnh giới / tu luyện tagged `[FUTURE, Phase 12]` and "only the first axis
  exists today", against the same file's status block and §3.8 (live since Phase 12, D-058).
- `GAME_FLOW.md` §1: `LOAD GAME → resume at saved state` drawn unmarked; §3.2 described a load
  path as if it ran. File-level save is Phase 23; `main_menu.gd` disables the entry.
- `GAME_FLOW.md` §3.1 "RNG is planned" (it is live as `RngService` since Phase 08); §3.5
  listed EventBus gameplay events that do not exist (`event_bus.gd` has five signals: boot,
  three scene-transition, language); the Phase-05 note said the relationship graph "has no
  gameplay surface yet"; §4 called `SaveService` "always available".
- `ROADMAP.md` Phase 19: "serialize mid-quest" versus the contract's "save files (23)" non-goal
  — reconciled where the phase is defined (D-069 §4); the matrix Quest row and `SAVE_FORMAT.md`
  point at it.

### Checked, no issue found

| Contract | Evidence |
|---|---|
| D-066: Dialogue owns no persistent state, only the open cursor | SOURCE (`DialogueRuntime` fields; no `to_dict`); TEST asserts it has no save boundary |
| Catalog is typed and fails closed on bad graphs, duplicates, dangling nodes, unknown payloads | SOURCE; TEST `test_dialogue_domain.gd` (structural + owner halves) |
| `KNOWS` / relationship conditions ask their owners; a stale or ineligible choice is refused with no partial mutation | SOURCE (`choose` re-validates before any effect); TEST |
| One typed effect per choice, applied by its owner; the shop handoff closes Dialogue first | SOURCE; TEST (order of `dialogue_closed` / `shop_opened`) |
| Reach and current-map presence stay `NpcRuntime`'s | SOURCE (`engage`, `reach_refusal`); TEST |
| Teardown: `DialogueRuntime` is started last and ended first; connections dropped | SOURCE (`SESSION_START_ORDER`); TEST; E2E step 15 |
| One press, one action; Esc steps back; a threat closes reading / trading surfaces | E2E dialogue steps 3–6, NPC steps 9–11, world step 7 |
| Refusals follow the authoritative result | SOURCE; TEST |
| Five autoloads, no new one | SOURCE (`project.godot`) |

## 4. Gates run on the final source tree (local, this run)

| Gate | Result |
|---|---|
| `tools/gdscript_lint.py --selftest` | PASS |
| `tools/gdscript_lint.py` | PASS — 286 files clean |
| `--import` | exit 0 |
| `tools/parse_check.gd` | PASS |
| boot smoke (`--quit-after 2`) | exit 0, 0 `SCRIPT ERROR:` |
| `tests/run_tests.gd` | **992 passed, 0 failed**, 0 `SCRIPT ERROR:`, 0 leak lines (986 + 6 new) |
| E2E app / player / world / pet / npc / dialogue | six PASS, each 0 `SCRIPT ERROR:`, 0 leak lines |
| `tools/playtest_flow.gd -- vi` at 1280×720 | 30 / 30 steps, 0 errors |
| `tools/playtest_flow.gd -- en` at 1280×800 | 30 / 30 steps, 0 errors |

Mutations: seven applied, seven red (D-069 "Evidence"); each was reverted and the diff checked.

## 5. Visual evidence (PLAY)

**Convention.** Captures are local, ephemeral evidence and are NOT committed
(`tools/playtest_flow.gd` header; `PHASE_EXECUTION_PROTOCOL.md` §2). They were written under
the session scratch directory `…/scratchpad/final/<scenario>_<lang>_<size>/` and are
reproduced exactly by:

```
DISPLAY=:0 $G --path . --resolution <1280x720|1280x800> \
    -s res://tools/capture_motion.gd -- <dir> <dialogue|session|shop> <vi|en>
DISPLAY=:0 $G --path . --resolution <size> -s res://tools/capture_ui.gd -- <vi|en> <dir>
```

Pixel sizes below were read from the written PNG files (PIL), not from the request. Neither
size was clamped on this 1920×1080 desktop. No 1920-wide capture was taken in this run.

**The Phase-18 dialogue box — 14 full frames per combination, all opened** (the two elder
greetings, his unread / choices / approve / teach / leave-selected lines; the scout's greet,
hub with four answers, price, pleased; the prompt before, the HUD after, the shop handoff):

| Language | Requested | File size written | Frames | Result |
|---|---|---|---|---|
| `vi` | 1280×720 | 1280×720 | 14 | PASS |
| `en` | 1280×720 | 1280×720 | 14 | PASS |
| `vi` | 1280×800 | 1280×800 | 14 | PASS |
| `en` | 1280×800 | 1280×800 | 14 | PASS |

What was looked for, and seen, in every combination:
- **No clipping or overlap.** The longest lines wrap to two rows inside the box (the elder's
  precept, the scout's "pleased" line) with the key line still below them; four answers fit
  the answer column; the longest English answer ("Press him to lower his prices") is whole.
- **Vietnamese diacritics** are legible at 1× ("Thẩm Bất Kỳ", "Trưởng lão Thanh Đài",
  "nghiêm nghị", "Kể điều bia Lạc Hà ghi").
- **Focus** is a framed row with a ▸ marker — on the first answer by default and on the
  second after one `move_down`; never colour alone.
- **Portrait, name, title and mood** are all present; mood is a word ("stern", "cởi mở") as
  well as the name-plate colour.
- **The two parties are not covered**: the box sits on the bottom edge; the elder, the player
  and the hound stand mid-screen.
- **The announcement band** ("Learned: …", "Ko Than thinks better of you (affinity +40).")
  rides just above the box and never across it; the prompt strip is hidden while the box is up.
- **Margins** are the same in all four (box x 212 → 1068, 18 px above the bottom edge).
- **Close / back:** the key line names both keys ("E Nói · Esc Rời đi"); Esc returning control
  is asserted by E2E dialogue step 6, not inferred from a frame.

**Surfaces the audit changed (`session` scenario, four combinations, all opened):**

| Surface | Result |
|---|---|
| Leave question | box below the screen centre, title + two-line body + "E … · Esc …", strip hidden — PASS ×4 |
| Defeat box | "Ngươi đã gục ngã" / "You have fallen"; the body wraps to two rows in `vi`, one in `en`; one key; the fallen figure in the corpse tint is above the box, not under it — PASS ×4 |
| Companion spacing | the hound stands beside / behind its owner, both fully visible — PASS ×4 |

**Shop and satchel after the strip fix** (`dialogue` handoff frame ×4; `shop` scenario and
`capture_ui` at `vi` 1280×720 and `en` 1280×800, opened): the strip is gone; the only key
line on screen is the surface's own ("E Trade one · A/D Buy/Sell · Esc Leave", "E Dùng · I
Đóng"); −8% and `13 (14)` show after the pleased line; a refused purchase says why in words
and in the band.

## 6. Unresolved debt (the register `PLAYER_EXPERIENCE_STANDARD.md` §4 requires)

The entries of `post-phase-18-audit.md` §6 stand unchanged. One is added:

| ID | Symptom / cost to the player | Why not now | Owner | Closure criterion | Makes later work harder? |
|---|---|---|---|---|---|
| CLV-01 | none today — `ShopData.keeper_id` is not validated against the character registry, so a shop authored for a keeper who does not exist would start cleanly and simply never be reachable | `NpcRuntime` realizes map-only characters lazily INSIDE its own `start_session`, after its content checks: validating keepers needs a decision about when a keeper must exist, and it is Phase-17 content validation outside this task's bounded scope | `NpcRuntime` (Phase 17 owner); taken with the first phase that adds a shop (no later than Phase 21) | `NpcRuntime.start_session` refuses a shop whose keeper does not resolve in the registry, with a test that fails without the check | no — one check, same seam as D-069 §1 |

A content constraint, not a debt: a dialogue speaker must be registered when the dialogue
session starts (in practice: a world-simulation cast member). D-069 §1 and `DATA_SCHEMA.md`.

## 7. Readiness for Phase 19

- The baseline documents no longer contradict the code on what is live, on loading, or on
  what "serialize mid-quest" permits.
- A quest listener may connect to `DialogueRuntime.choice_made` and close the conversation
  from it without breaking the runtime.
- A new `DialogueEffectData` kind for offers / turn-ins extends a validator that now covers
  every id a conversation names AND the id it is found by.
- Constraints already recorded stay binding: one reward ledger named at Gate B (AUD-12); the
  journal is a reading panel or registers like the other modal surfaces (AUD-15) — and, since
  this task, any modal surface also hides the prompt strip through `_refresh_focus`.

**Phase 19 (Quest) and every later phase are NOT STARTED.**
