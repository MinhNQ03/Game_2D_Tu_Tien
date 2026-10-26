---
name: aetheria-art-pipeline
description: Aetheria art pipeline commands and traps - Blender 5.2 to pixel sheets, props, icons, story art, VFX, pngout, determinism, captures. Use when generating or regenerating any game asset.
---

# Aetheria art pipeline — how assets are actually built

Method and taste: skill `aetheria-visual-craft` (read it first). This page is the machinery.
Owners: `docs/AETHERIA_ART_PIPELINE.md`, `docs/CHARACTER_ART_BIBLE.md`,
`tools/aetheria_art_pipeline/style/aetheria_style.yaml` (Visual DNA), `.kiro/steering/06-art-assets.md`,
`docs/ASSET_LICENSES.md`. Open owner gates ART-DIR-01/02 decide frozen art direction.

## Environment (this machine)
- System Python only: `/usr/bin/python3` (PIL + PyYAML). A venv `python3` may lack PIL.
- Blender 5.2: headless `<blender> -b -P <script> -- <args>` with the ABSOLUTE path
  (`/home/<user>/Downloads/blender-5.2.2-linux-x64/blender`; no `~` in worker commands), or
  the blender-pro MCP (its `execute_code` returns after 300 s while Blender keeps rendering:
  one or two actors per call, poll the output files; re-add pipeline dirs to `sys.path` after a
  restart).
- ~1 GB free RAM: never run a Blender render and a Godot capture matrix at the same time.

## Build commands (`tools/aetheria_art_pipeline/build.py`)
| Step | Command |
|---|---|
| actor spec | `build.py resolve <actor>` → `work/<actor>/spec.json` |
| Blender passes | `<blender> -b -P tools/aetheria_art_pipeline/blender/cli.py -- <actor>` |
| fast pose loop | `<blender> -b -P …/blender/cli.py -- --only <anim>[:<dir>] <actor>` |
| sheets | `build.py pixel <actor>` / `build.py all-pixel`; review board `build.py review <actor>` |

Speed (measured 2026-10-26, player_f_proto): a whole actor in Blender takes about 190 s, one
animation via `--only idle` about 8 s, and `pixel` about 3 s. Iterate with `--only` plus `pixel`
plus the one test, then do ONE full render before shipping. Fix the RULE (design data or
generator) that every frame comes from, never one frame by hand.
Trap: Godot tests read the IMPORTED texture. After `pixel`, run `<godot> --headless --path .
--import` before the test, or it judges the old sheet. A fix that "did nothing" may simply not
have been imported yet.
| design sheet | `build.py design-sheet <actor>` |
| icons / props | `build.py icons-spec` → Blender → `build.py icons`; same for `props-spec` / `props` |
| ambience | `build.py ambience`, `build.py ambience-check` |
| story pictures | `<blender> -b -P tools/aetheria_art_pipeline/blender/build_story_art.py -- …` → `build.py origins` (WebP) |
| VFX | `build.py vfx-spec` → `<blender> -b -P tools/aetheria_art_pipeline/blender/build_vfx.py -- …` → `build.py vfx [effect]` |
| floors | `designs/maps/<map>.yaml` → `world/ground.py` → `world/sync_scene.py` |

## Laws of the pipeline
Fail the build: adjacent frames and facings must differ (`verify_animates`); the profile check
`anchor_offset = (0, 48 - feet_row)`. Measured by validators you must run: `validate/style_check.py
sheet` (height, colours, isolation, outline), `validate/determinism_check.py` (several hash seeds,
bytes equal — before committing regenerated art), `validate/visual_benchmark.py`. They measure;
they do not decide beauty. Required by design and review:
- Every opaque sprite pixel is one of the actor's ramp tones or the ink — never resize-and-
  pixelate. Ramps are 4 tones `[deep, shadow, base, light]`; flags `flat`, `priority`,
  `min_tone` (skin never below base), `min_coverage`.
- Cell 32×48, feet on row 43. LEFT facing renders the MIRRORED action.
- Deterministic (D-063): majority votes go through `pixelize._majority`, never `max(set(…))`.
- Every shipped PNG through `pixel/pngout.py` (lossless 8-bit palette + alpha); painted pictures
  WebP. Intermediates stay in gitignored `work/` (it has a `.gdignore`, L-044). Ship only what a
  scene loads; report the byte delta. Record provenance in `docs/ASSET_LICENSES.md`.

## Evidence an asset is ready
1. Real-window captures: `<godot> --path . --resolution 1280x720 -s res://tools/capture_ui.gd -- vi <dir>`
   (and `1280x800`, `en`); motion: `<godot> --path . --disable-vsync --max-fps 60 -s res://tools/capture_motion.gd -- <dir> [scenario] [lang]`.
   Needs `DISPLAY=:0`, no `--headless`; run in the background, one at a time, with vsync disabled
   (a hidden window crawls at ~1 fps). Never `pkill -f capture_*`.
2. Look at 1× AND magnified; faces (sculpted, not a plastic ball), hands that leave the sleeve,
   a second character different in silhouette and palette at 1×, not only a recolour.
3. A short effect is proven by a strip / frame sequence, not one screenshot (L-037, L-045).
4. Before/after from the same tool and camera, numbers re-measured.

## Experiments (`CHARTER.md` §4)
A new method (higher resolution, generative-assisted, ComfyUI, hybrid) is a bounded experiment:
baseline → 2–3 materially different candidates → judged in game → adopted into `build.py` only
with evidence, recipe and licence recorded. External image services: no proprietary project
material without authorization; outputs need provenance before they ship.
