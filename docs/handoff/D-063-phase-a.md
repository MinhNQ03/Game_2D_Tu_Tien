# D-063 Phase A — handoff (IN PROGRESS: A1, A2 checkpoints passed; A3 in review)

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

### Review round 2 (2026-10-09) — in progress
- **NOT APPROVED YET** at `dd36dfa` — implementation sound, hardening required:
  - P2: prove the REAL `attack_started` → visual chain in regression (both looks), not just
    `play_action` by hand. New tests arm the real Kiếm attack and drive
    `AttackComponent.request_attack()` through the real seams; the wolf fallback is also
    proven through the signal. No test-only production shortcuts, no private-method calls.
  - P2: `slash_the_post` now FAILS LOUDLY per profile path — jian still worn, lifecycle
    entered, visual in ACTION_SLASH showing that profile's slash sheet, ≥1 captured frame
    in the slash action; otherwise `_fail()` + non-zero exit. Stale daobao comment fixed.
- Evidence at `00e84b0`:
  - Tested SHA: `00e84b05c6c20e6191cf01d730f468c5d458c15b`
  - GitHub Actions run: FILL_URL (Foundation gates (Godot 4.7) — SUCCESS, 55s)
  - Unit suite: 839/839 passed, assertion failures: 0, SCRIPT ERROR: 0, leaks: 0
    (local full-log scan of `/tmp/tests.log`)
  - E2E app / player / world: PASS / PASS / PASS (local, fresh runs)
  - Headless suite repeat: local `/tmp/tests_repeat.log` 839/839 PASS, 0 SCRIPT ERROR;
    CI headless suite 839/839 PASS
  - Captures `/tmp/motion/motion_slash_post.png` (proto) + `/tmp/motion/motion_slash_post_daobao.png`
    (daobao): visual inspection PASS — both strips show coil → cut with the blade-tracking
    trail → post hit-flash mid-cut → low-guard recovery; the daobao look is confirmed by
    the blue Thanh Vân robe, proving its own sheet/anchors/depths render in the real app.
- A3 is approved only after every acceptance gate passes on the new head.
