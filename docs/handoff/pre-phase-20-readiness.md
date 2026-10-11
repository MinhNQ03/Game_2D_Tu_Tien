# Handoff — Pre-Phase-20 readiness hardening (D-071)

**Not a phase.** Two findings carried out of Phase 19 are closed, plus one defect in the gates
themselves that was found while verifying them. **Phase 19 remains DONE. Phase 20 gameplay
has NOT started**: no story, origin selection, prologue, flag, quest content, loot, dungeon,
boss, save file, EventBus event or autoload was added.

## 1. Where this stands

| | |
|---|---|
| Branch | `fix/pre-phase20-readiness` (new; nothing was committed to `main`, `d063/phase-a` or `feature/phase-19-quest`; no merge, no PR, no rebase, no force-push) |
| Start | `b7689354ed8eb85bf01020600d2d864a421b91b1` — the Phase-19 tip, `origin/feature/phase-19-quest`, verified with `git ls-remote` before the first edit. `origin/main` and `origin/d063/phase-a` were both `8f3ccbdec37904ef9a6bcbd88d1a94eaa90c8c7e` at that moment |
| Ancestry | `b768935` → `f253727` → `cef225d` → `e46908d` → the commit carrying this file → the commit that records its CI run |
| Baseline before any edit | all 13 local gates PASS on `b768935`, 1064 tests (and, read later from the log's last line, the leak in §4) |
| Code commits | `f253727` (Q19-04), `cef225d` (Q19-05), `e46908d` (the leak and its gate) |
| CI | §7 |

User-owned untracked content (`CLAUDE.md`) was never staged, cleaned or rewritten.

## 2. Q19-04 — a creature came to rest behind an obstacle

### What was measured, and what it ruled out

The register's cause was "inferred from the frame, not traced". Before designing anything, a
probe drove a REAL `CombatRuntime` Vụ Lang at a REAL pine footprint (`WorldProp` +
`pine.tres`, an 11.08 × 4.62 px rectangle) with a solid target 96 px away, logging position,
post-slide velocity, brain state and collision normal per tick for 20 s (1200 ticks).

| Target's offset from the creature's row | Where it came to rest | State | Velocity | Collision | Bitten in 20 s |
|---|---|---|---|---|---|
| 0 px | x = 385.46 (its body against the trunk's west face at 394.46) | `CHASE` | `(0, 0)` | trunk, normal `(-1, 0)` | never |
| 0.01 px | x = 385.39, y → 300.0096 | `CHASE` | `(0, 0.0009)` | same | never |
| 0.5 px | x = 385.39, y → 300.4996 | `CHASE` | `(0, 0.0009)` | same | never |
| 2 px | x = 385.39, y → 301.9996 | `CHASE` | `(0, 0.0009)` | same | never |

The last three rows are what decided the design. The creature **slides toward the target's
row and stops there**: `move_and_slide` keeps the part of the velocity that lies along the
face, a pursuer's velocity points at its target, so that part shrinks to zero exactly where
the target is dead ahead through the obstacle. The stall is a **stable resting point**.

| Hypothesis (from the brief) | Verdict | Evidence |
|---|---|---|
| Collision blocks direct movement while intent stays `APPROACH` | **TRUE — the cause** | the table: `CHASE`, zero velocity, a collision every tick, gap never inside `engage_distance` (22 px), so no swing is ever decided |
| The arrangement is genuinely unreachable | **FALSE** | the target stood in open ground; the fixed creature reaches it in 1.4–1.5 s |
| Target lost / reacquired incorrectly | **FALSE** | the state never leaves `CHASE`; `has_target` stays true |
| Nondeterministic test setup | **TRUE — why it looked flaky, not why it failed** | step 19 places the player at `creature + (96, 0)`, exactly on the creature's row, after a patrol whose length depends on real-time pacing. A prop on that row → red; none → green. Staged deterministically the old code is red every time (§5) |
| A rare alignment that "favours the player" (the register's reading) | **FALSE** | not rare: an attractor. And it is an exploit — a creature that cannot reach can be killed from behind a tree |
| My own first guess: an unstable equilibrium the body escapes | **FALSE** | the sign was backwards; rows 2–4 converge instead of escaping (L-050) |

The same seam carried two other intents, and both stalled identically: `RETURN_HOME` (a
creature that could not get home stays in `RETURN` and never looks at the player again) and a
companion following its owner.

### The fix

`MovementComponent.apply_pursuit(toward, speed, delta, goal)` — the movement seam, gameplay
layer. `AIComponent` sends `APPROACH` and `RETURN_HOME` through it and faces the heading it
returns; everything else still uses `apply_intent`.

1. Nothing in the way → identical to `apply_intent`, no query.
2. A surface met squarely → take a **hand**: the side the target lies toward; on an exact
   head-on tie the constant `DETOUR_DEFAULT_HAND`. Hold it.
3. While held → one `test_move` along the straight line per tick. Blocked: walk along that
   surface on the held hand at full speed. Clear: let go.
4. The way round is itself shut → reverse once.

The pursued body is never an obstacle. A new intent drops the hand.

| Invariant | How it is kept | Guard |
|---|---|---|
| `AiBrain` pure | not edited; `git diff b768935 -- src/domain/ai` is empty | `tests/unit/ai/` unchanged and green; `test_layer_direction.gd` |
| One session tick, throttled decisions, no per-creature callback or timer | no node, timer or `_process` added | `test_ai_budget.gd` (existing four + the new one) |
| No unbounded work, no per-frame search | ≤ 1 `test_move` per creature per tick, only while a hand is held | `detour_probes()` asserted: 0 in the open, ≤ frames in a pocket, 0.90 / creature-frame in the pen |
| Authored collision and bounds obeyed | no layer, mask, shape or prop touched; movement is still `move_and_slide` | body-vs-footprint overlap < 0.1 px every frame (trunk, wall, map edge) |
| Deterministic, no `rand*` | the tie is a constant; nothing draws from a stream | two runs identical frame for frame; literal-direction unit tests |
| Reach, telegraph, leash/return, swing timing | untouched code paths, re-asserted with an obstacle on the line | leash, lost-target, flush-target and open-fight tests |
| Companion reuses it | same `AIComponent`, same seam | `test_a_companion_follows_its_owner_round_the_trunk` |

### What is NOT solved (and is pinned)

A pocket shut on both sides — one obstacle plugging a gap. The creature reverses once and
rests; it does not pace, the work stays bounded, and it still walks home when the target is
lost. Routes through concave space are navigation: **NAV-01**, owner Phase 21, in
`docs/handoff/phase-19-quest.md` §9. Also: the hand is "toward the target", not "the shorter
way" — round a wide obstacle it may take the longer side.

## 3. Q19-05 — data depended on its own domain

`src/data/worldsim/world_sim_catalog.gd` validated its calendar against
`WorldClock.MIN_UNIT`. The fact was also restated as a literal `1` in
`WorldSimulationState`.

**Ownership:** the four units are authored on the catalog, so the floor of what may be
authored is stated there, once: `WorldSimCatalog.MIN_CALENDAR_UNIT: int = 1`.
`WorldClock.MIN_UNIT` reads it; `WorldSimulationState.MIN_CALENDAR_UNIT` reads the clock's.
Domain → data only. No reverse dependency, no untyped number, no constants holder, and the
validation is not weaker.

| Contract | Guard |
|---|---|
| `src/data/worldsim/` names no class of, and loads no script from, `src/domain/worldsim/` | `test_world_simulation_data_does_not_depend_on_its_domain` |
| No lower layer loads an upper layer's script by path (the name scan ignores strings) | `test_no_lower_layer_loads_a_script_from_an_upper_layer_by_path` + its own can-fail test |
| The exception list is empty | `KNOWN_EXCEPTIONS := {}`; the general scan no longer excuses anything |
| Catalog validation, clock construction and clock hydration refuse the same calendars | `test_calendar_contract.gd`: 4 units × {-30, -1, 0, 1, 2, 30}, both boundaries |
| Zero and negative units still rejected; the clock stays node-free and deterministic | the same file; `test_world_clock.gd`, `test_world_sim_*` unchanged and green (76 worldsim unit tests, the 4 new ones included) |

**Shown red on the old implementation:** with the catalog reading `WorldClock.MIN_UNIT`
again and the clock holding its own literal, `test_layer_direction.gd` fails two tests (N1 in
§6).

## 4. Found while verifying: the leak gate could not see one leaked object

The suite's log ended with `WARNING: 1 ObjectDB instance was leaked at exit`. The gate greps
for `ObjectDB instances were leaked` — plural only — so it counted zero.

- **Not introduced here.** A clean worktree of `b768935` prints the same line (1064 tests),
  and so does the job log of CI run 38069906502 (the run that closed Phase 19), line 4930.
- **Cause:** `tests/integration/test_quest_runtime.gd` passed `Node.new()` inline to
  `start_session`; nothing could free it. Test code only — no shipped code leaks.
- **Fix:** the node is held and freed; the pattern is `ObjectDB instances? (was|were) leaked`
  in all seven places `.github/workflows/ci.yml` uses it.
- **Consequence for the record:** Phase 19's "0 leak lines" was the pattern's answer, not the
  log's. Corrected in place in `docs/handoff/phase-19-quest.md`. L-051.

This is outside the two findings in the brief. It is here because the brief's own acceptance
gate is "zero leak lines", and reporting that gate green on a pattern known to be blind would
have been false.

## 5. Real-window evidence

`tools/playtest_flow.gd`, real window, real input, one run at a time. New step
**`17b_hunt_round_obstacle`**: the creature and the player are each placed ONCE on one row,
48 px either side of the field's southern boulder (`Prop_RockS`, a 46.2 × 15.7 px
footprint), 142 px apart; then no key is pressed. Budget, from the creature's own data:
0.35 s notice + 234 px at 132 px/s + 0.26 s windup + 0.08 s active + 4 × 0.2 s decisions =
196 physics ticks.

**The final source tree** (the tree of `e46908d`; the commits after it change documentation
only). Every run: exit code 0, 0 `SCRIPT ERROR`.

| Run | Language · size | Steps | 17b: bitten after / budget (ticks) | Went round | Step 19 (natural encounter) |
|---|---|---|---|---|---|
| 1 | vi · 1280×720 | 31 / 31 | 114 / 196 | above | killed, 8 rounds |
| 2 | vi · 1280×720 | 31 / 31 | 116 / 196 | above | killed, 8 rounds |
| 3 | vi · 1280×720 | 31 / 31 | 115 / 196 | above | killed, 8 rounds |
| 4 | en · 1280×800 | 31 / 31 | 115 / 196 | above | killed, 8 rounds |
| 5 | vi · 1280×800 | 31 / 31 | 116 / 196 | above | killed, 8 rounds |
| 6 | en · 1280×720 | 31 / 31 | 115 / 196 | above | killed, 8 rounds |

Before the last source edits the same harness had already run five times on the fix
(31 / 31 each: 115, 116, 114, 115, 116 ticks), and the three forced-arrangement runs below
run it too (114, 116, 115) — fourteen runs of step 17b on the fix, none late, none red.

**Step 19 with its failing arrangement FORCED** (a scratch copy of the harness that places
the creature 48 px west of the `Prop_PineS3` trunk on a row that crosses it, so step 19's own
`+96` puts the trunk between them; creature `(422, 570)`, pine `(470, 566)`):

| Run | Code | Steps | Step 19 |
|---|---|---|---|
| 1 | fix | 31 / 31 | `hp 34 -> 0 landed=true killed=true rounds=13 timed_out=false` |
| 2 | fix | 31 / 31 | the same, 13 rounds |
| 3 | fix | 31 / 31 | the same, 13 rounds |
| — | **old pursuit code** | 29 / 31 | `final_gap_px=29 … hp 34 -> 34 landed=false killed=false rounds=386 timed_out=true` |

That last row is the original failure, character for character (`final_gap_px=29`,
`rounds=386`): 29 px is 9 + 11.08 + 9 — half a body, the trunk, half a body. It is now a
reproduction instead of a sighting.

**The committed harness on the old pursuit code** (the fix reverted in the working tree,
then restored and checksum-verified): 29 / 31 — step 17b
`bitten_after_ticks=-1 … went_round=NO off_row_px=0.0 state=CHASE final_gap_px=103`
(watched for three budgets), and step 19 timed out behind the same rock. Twice, same numbers.

Frames opened and looked at (all 1280 × 720 or 1280 × 800 PNG, sizes read from the files):

| Frame | Size | What is in it |
|---|---|---|
| `F_vi720_1/vi_1280x720_17b_hunt_round_obstacle.png` | 1280 × 720 | the Vụ Lang at the boulder's upper-left corner, drawn behind the rock (it is above the footprint), facing right — the way it is walking; the player 142 px away to the right, untouched at 100 / 100; target plaque `Vụ Lang 34 / 34` |
| `F_en800/en_1280x800_17b_hunt_round_obstacle.png` | 1280 × 800 | the same moment in English (`Mist Wolf`, `Broken-Vein Woods`), same position |
| `F_staged19_1/vi_1280x720_19_natural_encounter.png` | 1280 × 720 | the forced arrangement after the fix: the player beside the pine, plaque `Vụ Lang · Đã hạ gục · 0 / 34`, player 82 / 100, XP 30 / 45 — it came round, fought, and died |
| `OLD_staged19/vi_1280x720_19_natural_encounter.png` | 1280 × 720 | the old code in the same arrangement: the creature pressed against the west side of the trunk, the player against the east side, the trunk between them — the picture the register described |

Also read from disk: `F_vi800` and `F_en720` step-17b frames exist at 1280 × 800 and
1280 × 720. The other frames of each run were produced and not individually reviewed here;
nothing about them is claimed. Paths are under the session scratch directory
(`…/scratchpad/pt/<run>/`).

Captures are ephemeral evidence and are not committed (`PHASE_EXECUTION_PROTOCOL.md` §2).

## 6. Gates and mutations on the final tree

Local gate script, one verdict line: **`ALL 13 LOCAL GATES PASS`** — lint self-test, lint
(314 files), import, parse, boot smoke, **1090 tests passed, 0 failed, 0 `SCRIPT ERROR:`, 0
leak lines (either wording)**, and seven isolated E2E flows (app, player, world, pet, npc,
dialogue, quest), each with 0 script errors and 0 leak lines.

Measured (headless, this machine, 2026-10-11): wander budget 344 ms / 4.78 µs per creature
per frame for 40 × 1800 frames (before: 347 ms / 4.82 µs — unchanged); worst-case detour
919–936 ms / ~13 µs, 0.90 look-aheads per creature per frame, 10.0–10.2× for a 10× cast.

Mutations — each applied to the final source, the named tests run, the file restored and
its checksum verified. **24 applied, 24 red.**

| # | What was broken | Red in |
|---|---|---|
| M1 | pursuit goes back to the straight line (the old code) | 11 of 15 detour tests |
| M2 | `RETURN_HOME` not pursued | home-round-the-trunk, companion |
| M3 | the target's body counts as an obstacle met | 8 detour tests |
| M4 | the target's body counts as an obstacle ahead | rest-against-goal |
| M5 | no reversal | shut-way |
| M6 | unlimited reversals | pocket |
| M7 | hand re-chosen every tick | pocket |
| M8 | never looks ahead | 11 detour tests |
| M9 | any touch is "square" | 9 detour tests, incl. map edge |
| M10 | faces the target instead of the way it walks | measured staging |
| M11 | hand kept across intents | flush target |
| M12 | the other default hand | tie unit test |
| M13 | hand away from the target | hand unit test |
| M14 | steps through the obstacle | 11 detour tests |
| M15 | looks ahead every tick | pocket, open fight, map edge |
| P1 | two look-aheads a tick | detour budget |
| P2 | the old code in the pen | detour budget (a creature at rest) |
| N1 | **the old Q19-05 implementation** | general layer scan + worldsim pair |
| N2 | data `preload`s a domain script | path scan + worldsim pair |
| N3 | floor lowered to 0 | contract ×2 |
| N4 | the clock restates a different floor | contract ×4 |
| N5 | catalog validation weakened | contract ×2 |
| N6 | clock hydration weakened | contract ×1 |
| N7 | state fallback restated | contract ×1 |

One mutation survived its first round and changed the code rather than the count: a
half-second "remember the hand" rule could not be made to matter by any test and was removed.
One (M4) survived until a test was written at the seam itself, where it does matter.

The leak gate, checked the same way: on the saved pre-fix suite log and on the Phase-19 CI
job log the old pattern matches 0 result lines and the new one matches 1.

## 7. CI

| | |
|---|---|
| Run | **38111877656** — https://github.com/MinhNQ03/Game_2D_Tu_Tien/actions/runs/38111877656 |
| `head_sha` | `5c8c1faa232c6ce23ab372d094c275c380f72d5d` (branch `fix/pre-phase20-readiness`) — the commit that carries the three fixes and this handoff |
| Conclusion | `success` |

Every gate, read from the run's job steps, all `success`: Checkout · GDScript static lint ·
Download Godot 4.7-stable · Import project · GDScript parse check · Runtime boot smoke ·
Headless test suite · Real-application E2E · Player sandbox E2E · World/Map E2E · Pet E2E ·
NPC/Shop E2E · Dialogue E2E · Quest E2E — 14 gates.

Read from the job log itself rather than from the gate's summary (L-051):
`[tests] ran 1090 test(s): 1090 passed, 0 failed.`; **no `leaked at exit` line in either
wording** and no `resources still in use` (the Phase-19 run's log had one); no
`SCRIPT ERROR:` result line; seven `RESULT: PASS` lines for the E2E flows. The detour budget
on the runner: 1403 ms, 19.5 µs per creature per frame (ceiling 40), 10.07× for a 10× cast —
and **64 971 look-aheads, the same count as locally**, which is the determinism claim
checked on a second machine.

The commit that adds this section changes this section only. Its own run is reported in the
session's closing report, because a document cannot name the run of its own commit.

## 8. Debt after this task

| ID | Status |
|---|---|
| Q19-04 | **CLOSED** — `f253727` |
| Q19-05 | **CLOSED** — `cef225d` |
| NAV-01 | **NEW**, narrower than Q19-04: routes through concave space. Owner Phase 21 |
| Q19-03 | open, Phase 20's (the standing purpose line) — untouched |
| Q19-01, Q19-02 | open, Phase 25 — untouched |
| CLV-01 | open — shop validation was not touched |
| AUD-07, -09, -13, -14, -15 | open, as recorded |

## 9. Limits and things not done

- **No pathfinding.** See NAV-01. Deliberate.
- **The body's motion mode was not changed** (`CharacterBody2D` default). Out of scope; it
  affects the player too.
- **Step 19 keeps its natural, variable staging** by design — it is evidence about what a
  player can do. Step 17b is the deterministic one. A scratch copy of the harness that forces
  step 19's failing arrangement was run for §5 and is not in the repo.
- **Wall-clock budgets** (`test_ai_budget`, `test_combat_budget`) remain environment-sensitive
  (D-054); the new detour ceiling is ~3× its measurement for the same reason.
- **No profiler session**, as before (Phase 29).
- **Real-window runs are one machine**, 60 Hz, unlocked session.

## 10. Status

Q19-04 and Q19-05 are closed with tests that fail on the old code. **Phase 19 remains DONE;
Phase 20 gameplay has not started.**
