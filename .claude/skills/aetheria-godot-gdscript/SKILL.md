---
name: aetheria-godot-gdscript
description: Godot 4.7 + GDScript facts and traps for Aetheria - exact test/parse/boot/E2E commands, .uid files, leaks, Variant inference, headless limits. Use before writing or testing any .gd/.tscn/.tres.
---

# Godot 4.7 / GDScript in Aetheria — verified facts and traps

Pinned: **Godot 4.7.2-stable** (`~/Downloads/Godot_v4.7.2-stable_linux.x86_64`, or `$AETHERIA_GODOT`;
the config accepts only a `4.7` prefix). Owners: `.kiro/steering/04-coding-standards.md`,
`05-performance-testing.md`, `docs/TEST_PLAN.md`, `docs/GDSCRIPT_CODE_INTELLIGENCE.md`. Every trap
below is a real `L-nnn` in `.kiro/steering/09-lessons-learned.md` — open it for the full story.

## Exact commands (the same ones the supervisor and CI run)
`<godot>` is the ABSOLUTE binary path. An autopilot worker copies the exact lines from its task
prompt ("Required checks" — the allowlist matches only those); a native session expands
`/home/<user>/Downloads/Godot_v4.7.2-stable_linux.x86_64` itself.
```bash
/usr/bin/python3 tools/gdscript_lint.py                            # lint (also --selftest)
<godot> --headless --path . --import                               # import (new assets, .uid)
<godot> --headless --path . -s res://tools/parse_check.gd          # every script compiles
<godot> --headless --path . --quit-after 2                         # boot
<godot> --headless --path . -s res://tests/run_tests.gd [-- <substr>]   # suite (or a subset)
<godot> --headless --path . -s res://tests/e2e/run_<flow>_flow.gd  # one E2E flow
python3 tools/ai_workflow/aetheria_autopilot.py checks             # checks your changed paths trigger
```
`checks` runs the E2E flows only when their trigger paths changed (src/data/assets/locale …);
`checks --all` runs everything.
- **Grep every log for `SCRIPT ERROR`** and leak lines. An aborted test method is reported as PASS
  (GDScript has no try/catch; the runner only counts assertions) — L-026. CI fails on it.
- E2E flows (`tests/e2e/run_*_flow.gd`) run in their OWN process, excluded from `run_tests.gd`.
- Use the exact absolute binary. Do not wrap in `timeout`, do not use `~` inside allowlisted worker
  commands, do not guess `godot4` (cost ui-01 three fix rounds).
- No Godot / no display → the check is BLOCKED, never PASS. Say so.

## Compile and type traps
- `:=` from a `-> Variant` helper → warning-as-error → the whole `class_name` fails to compile.
  Declare `var x: Variant = helper()` and cast at the typed assignment (L-020).
- "Nonexistent function X in base 'GDScript'" ⇒ the TARGET class failed to compile; fix that file.
- A field/method used on another class must be declared there; the LSP can false-positive on
  `class_name` lookups, so parse_check + a runtime test are the proof (L-018).
- `load()` succeeding ≠ usable: check `can_instantiate()` before `new()`; every runner path must
  reach `quit()` or CI hangs (L-033).
- After editing a `.gd`, GodotLens needs `gdscript_sync_file` before its answers are current.

## Files
- A new `.gd` has a generated `.gd.uid` — stage it with the script. A `.tscn`/`.tres` carries its
  uid inline — stage every `ext_resource` it references (L-008, L-015). `--import` creates the
  sidecar; the encoding is knowable, do not avoid new scripts (L-027).
- UTF-8, LF, **tab** indentation (every existing `.gd` uses tabs; `04-coding-standards.md` still
  says 4 spaces — the code wins, mixing breaks the parse). Vietnamese text must round-trip.
- Scratch files: a name matching `.gitignore` (`_*.ps1`, `_*.log`, `*_tmp.txt`) or the session
  scratchpad, outside `res://`; delete them when done (L-009).

## Tests that tell the truth
- Free every `Node`/`Object` a test creates (`add_to_tree`+`free_node`, or `free()`); only
  `RefCounted` auto-frees. One leak pins scripts and shows as several ObjectDB leaks (L-019).
- Autoloads are LIVE under `/root` in every test: unit tests use fresh `Script.new()` instances,
  never the live singletons; anything that must drive the real ones runs in its own E2E process.
  The runner's guard DETECTS contamination, it does not reset it (L-010, D-019).
- At least one test drives the REAL path (real autoloads, real boot contract) — L-006, L-011, L-017.
- Headless `-s`: Area2D `body_entered` is unreliable → emit the node's own signal to run the real
  handler. Drive semantic input for real with `Input.parse_input_event` (never call
  `_unhandled_input` directly) and poll over a bounded number of frames instead of assuming one
  frame of input-pump timing (L-016, L-017).
- Move bodies only in the fixed physics step: `await fixed_step()` before stepping anything that
  moves a body; an engine call without a delta reads a hidden clock (L-055).
- A regression test must go red on the bug before it may guard the fix (mutate once) — L-046.

## Runtime / UI traps
- `set_anchors_preset` keeps the current rect → a 0×0 root stays 0×0. Use
  `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`; assert OFFSETS, not anchors (L-028).
- A hidden child adds nothing to a container's minimum size: measure a fully populated screen
  through its public setters (L-035).
- An emit can synchronously free the emitter and re-enter the caller: finish touching the tree
  BEFORE emitting; treat every emit as a re-entry point (L-013, L-047, L-055).
- Setters store; one refresh writes, and `_ready` runs it too (L-057). No per-frame UI rebuild.
- Presentation never writes `Engine.time_scale` or the physics tick (D-057).

## Standards in one breath
snake_case files/functions, PascalCase classes, past-tense signals, `is_/can_/has_` booleans,
`_private`. No hard-coded gameplay numbers or player-facing strings (data + localization keys).
`assert()` for programmer errors, `push_error()` for content errors; never swallow a failed load.
Measure before optimizing and log it in `docs/PERFORMANCE.md` (problem · cause · fix · numbers).
