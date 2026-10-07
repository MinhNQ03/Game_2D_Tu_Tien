# D-063 Phase A — handoff (IN PROGRESS: A1, A2 checkpoints passed; A3 next)

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
