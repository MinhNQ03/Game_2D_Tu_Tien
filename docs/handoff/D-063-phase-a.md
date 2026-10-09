# D-063 Phase A — handoff (A1, A2 checkpoints passed; A3 PASSED — see acceptance below)

Read this first when resuming Phase A. It is written as the stage advances and closed at sign-off.

## Repository state

- Branch `d063/phase-a` (never merged into `main`; the user merges). `main` = `77c53b9`.
- Checkpoints: **A1** `9cb268a` (immediate player feedback) — PASSED review. **A2** `3a96ebe` +
  `0a9c70a` (physical truth) — PASSED review, with the hardening below.
- Test baseline at A2: 821 headless tests, 0 SCRIPT ERROR, 3/3 E2E, playtest 29/29 (vi, en).

## Real-app environment (D-063 §4)

Intel UHD 730, Mesa 25.2.8, Godot 4.7.2 `gl_compatibility`, X11 1280×720, 60 Hz. The X session is
usually LOCKED: a vsynced window then presents at ~1 Hz, so every real-app run uses
`--disable-vsync --max-fps 60`; `tools/playtest_flow.gd` step 05a FAILS an invalid pacing.

## Carried items — to close before D-063 final

| Item | Origin | Status |
|---|---|---|
| A new ANSWER identical to one WAITING in the immediate lane returns instead of showing (the "visible on its frame" invariant) | A1 review | open — fix + regression test |
| playtest 05c/05d: pin that the setup pickups were actually collected | A1 review | open |
| `pixel/pixelize.py` → `aetheria_art.sheet` dependency (one PropData writer, wrong direction) | A2 review P2 | technical debt — move the writer to a neutral module |
| Pixelizer non-determinism (`max(set(keys))` over string keys) | A2 | FIXED (`_majority`; `validate/determinism_check.py`, 3 seeds × 99 files identical) |
| `19_natural_encounter` playtest step is timing-flaky (30-round budget vs real-time wolf) | A2 | open — harness |
| D-062 boulder / well: round art on rectangular footprints | A2 audit | known limitation |
| Notices waiting when the map changes are freed with that map's HUD | A1 | known limitation |
| Notice line contrast over light paving not verified | A1 | known limitation |

## A3 checkpoint — the sword cut (D-063 A3)

- Scope: `AttackData.body_action` (`attack`/`slash`), `ACTION_SLASH` presentation, blade drawn
  from rig anchors (palm → tip) with per-frame depth, VFX crescent from the tip trajectory,
  slash sheets for both player looks (`player_proto`, `player_daobao`). Timing 120/80/240 ms
  untouched; `CombatService`/damage authority untouched.
- Commits on `d063/phase-a`: `e8c9a53` (proto art), `dfe20c5` (runtime), `25cbf8d` (capture
  scenario), `a2145f8` (daobao art), `dd36dfa` (review hardening round 1).

### Review round 1 (2026-10-09) — resolved
- **NOT APPROVED** at `a2145f8` — GitHub Actions run `37884386946` failed the
  test-integrity gate. `test_slash_presentation.gd` called `AttackData.validation_errors()`,
  which did not exist: two test methods aborted with SCRIPT ERROR while the local runner
  still reported "833 passed". **Lesson: always scan the FULL log for SCRIPT ERROR — never
  trust `tail`.**
- Hardening (`dd36dfa`): `AttackData.validation_errors()` extracted, `is_valid()` reuses it;
  `BODY_ACTIONS` vocabulary; daobao regression tests; typo → `push_warning` + fallback;
  capture extended with the daobao strip.
- Evidence at `dd36dfa` (CI run `37888046414` — SUCCESS): unit 837/837, 0 SCRIPT ERROR,
  0 leaks (local full-log scan, 2 stable runs); E2E app/player/world 3/3; captures
  `motion_slash_post.png` + `motion_slash_post_daobao.png`, visual PASS on both profile paths.

### Review round 2 (2026-10-09) — resolved
- **NOT APPROVED YET** at `dd36dfa` — implementation sound, hardening required:
  - P2: prove the REAL `attack_started` → visual chain in regression (both looks), not just
    `play_action` by hand. New tests arm the real Kiếm attack and drive
    `AttackComponent.request_attack()` through the real seams; the wolf fallback is also
    proven through the signal. No test-only production shortcuts, no private-method calls.
  - P2: `slash_the_post` now FAILS LOUDLY per profile path — jian still worn, lifecycle
    entered, visual in ACTION_SLASH showing that profile's slash sheet, ≥1 captured frame
    in the slash action; otherwise `_fail()` + non-zero exit. Stale daobao comment fixed.
- Hardening landed as `00e84b0` (code) + `c62a321` (docs); evidence URLs filled as `b838eb2`.

### A3 FINAL ACCEPTANCE (2026-10-09) — PASS
- **Decision: A3 APPROVED.** Every acceptance gate below passed; no code defect found on
  re-validation, so no code was changed — the closure is documentation-only.
- Implementation/code-validation SHA: `00e84b05c6c20e6191cf01d730f468c5d458c15b`
  — CI run https://github.com/MinhNQ03/Game_2D_Tu_Tien/actions/runs/37889572471 (SUCCESS).
- Current branch HEAD: `39845c0bdd151063ccec71c0453123eeb9ed02af`
  — CI run https://github.com/MinhNQ03/Game_2D_Tu_Tien/actions/runs/37895099103 (SUCCESS,
  exact head_sha verified; all 13 steps green: lint, import, parse, boot smoke, headless
  suite, 3× E2E). Full CI log text was not downloadable (API 403 without admin rights);
  step-level conclusions are all `success`, and the identical gates were re-run locally
  with full-log scans (see below). (Previous HEAD `b838eb2` also CI-SUCCESS, run
  `37893656907`; all commits since `00e84b0` are documentation-only.)
- Local repeat (labelled local, Godot 4.7.2 `ed1daf0bf`, Xvfb where a display is needed):
  - Headless unit suite ×2 runs: 839/839 passed, 0 failed assertions, 0 SCRIPT ERROR
    (full-log `grep -c`), 0 leaks.
  - E2E app / player / world: PASS / PASS / PASS (fresh local runs, not quoted history).
- Real-app captures (labelled local visual evidence — inspected frame by frame, not CI
  artifacts, kept out of source control per project policy):
  - `/tmp/finalcap/motion_slash_post.png` (player_proto): PASS — gray-robed character,
    jian equipped throughout, coil → cut → recovery with no discontinuity, blade and
    crescent trail aligned on the blade-tip path, post hit-flash during the cut, pixels
    sharp, no blur/clipping/misplaced weapon.
  - `/tmp/finalcap/motion_slash_post_daobao.png` (player_daobao): PASS — blue Thanh Vân
    robe confirms the daobao look with its own slash sheet/anchors/depths; same correct
    slash beats, trail alignment and hit-flash; pixels sharp.
- Code re-validation (2026-10-09, no changes made): `AttackData.body_action` vocabulary
  `attack`/`slash` enforced via `validation_errors()`; `is_valid()` reuses it;
  `AttackComponent.arm()` fail-closed; real `request_attack()` → signal → `ACTION_SLASH`
  chain covered for both looks (3 `request_attack` call sites in
  `test_slash_presentation.gd`); Kiếm timing 0.12/0.08/0.24 s confirmed in
  `data/combat/attack_player_kiem.tres`; combat/damage authority untouched; 5 autoloads
  unchanged; no test-only production shortcuts, no private-method substitutes.
- Review history preserved: run `37884386946` (FAIL at `a2145f8`, test-integrity —
  `validation_errors()` missing) → resolved by `dd36dfa`; run `37888046414` (SUCCESS);
  run `37889572471` (SUCCESS at `00e84b0`); run `37889854742` (SUCCESS at `c62a321`).
  Failed assertions/script errors were never counted as passes.
