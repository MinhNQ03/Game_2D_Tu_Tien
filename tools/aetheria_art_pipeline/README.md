# Aetheria art pipeline (D-062)

ONE visual DNA → many production representations. Blender is a **build** tool here; the game
only ever loads the PNG sheets and `.tres` data this pipeline writes.

```
style/aetheria_style.yaml        the Visual DNA (palette roles, light, outline, character,
                                 materials, VFX / icon / UI / world grammar, pixel adaptation)
designs/cultivator.yaml          THE canonical cultivator: body, garment cut, hair, face, cameras
designs/actors/<actor>.yaml      an actor = the cultivator + overrides + its own colour ramps
model/humanoid.py, motion.py     pure-Python geometry, rig and poses (testable without Blender)
blender/build_actor.py           runs IN Blender: meshes, armature, materials, real Actions,
                                 cameras, canonical light, passes, presentation, portrait, details
blender/aetheria_cultivator.blend  the master scene (player_proto), saved from the same code
pixel/pixelize.py                passes -> 32x48 sheets, anchors, portrait (no resize-pixelate)
pixel/pngout.py                  the one PNG writer: 8-bit palette + alpha, lossless (~half the bytes)
validate/style_check.py          measures produced art against the DNA (JSON verdict, exit code)
validate/review_sheet.py         the visual-review boards (per actor, icons)
validate/visual_benchmark.py     the structural benchmark against the quality reference
validate/determinism_check.py    every stage under several hash seeds: same bytes or exit 1
model/icons.py, model/props3d.py icon and world-prop geometry (same primitives as the cultivator)
blender/build_icons.py, build_props.py   icon / prop passes (props catch their cast shadow)
designs/icons.yaml, props.yaml   icon and prop designs (ramps in DNA roles)
designs/maps/<map>.yaml          a map's layout: regions, water blockers, props, retired decor
world/ground.py                  the floor painter -> assets/maps/<map>_ground.png + GroundLayoutData
world/sync_scene.py              writes a layout's props / painted floor into its scene
ui/ui_kit.py                     the ink-lacquer UI kit + medallions -> assets/ui/aetheria_ink/
work/                            gitignored build output (renders and passes)
```

## Build one actor

```
python3 tools/aetheria_art_pipeline/build.py resolve player_proto     # design -> work/<a>/spec.json
# in Blender (blender-pro MCP, or headless):
blender -b -P tools/aetheria_art_pipeline/blender/cli.py -- player_proto
python3 tools/aetheria_art_pipeline/build.py pixel player_proto       # sheets, anchors, portrait
python3 tools/aetheria_art_pipeline/build.py review player_proto       # work/<a>/review.png
python3 tools/aetheria_art_pipeline/validate/style_check.py sheet assets/sprites/characters/player_proto_walk.png
```

Icons, props, floors, UI (system Python unless noted):

```
python3 tools/aetheria_art_pipeline/build.py icons-spec | props-spec      # then, IN Blender:
#   build_icons.render_icons("<pipe>/work/icons/spec.json")
#   build_props.render_props("<pipe>/work/props/spec.json")
python3 tools/aetheria_art_pipeline/build.py icons | props                 # pixelize + write data
python3 tools/aetheria_art_pipeline/world/ground.py lac_ha                  # paint a floor
python3 tools/aetheria_art_pipeline/world/sync_scene.py lac_ha src/gameplay/maps/hub_map.tscn
python3 tools/aetheria_art_pipeline/ui/ui_kit.py                            # the UI kit
python3 tools/aetheria_art_pipeline/validate/visual_benchmark.py <golden_combat.png> --out <file>
```

The system Python needs PIL and PyYAML (`/usr/bin/python3` here; a virtualenv without PIL will
not do). Godot never imports this folder (`.gdignore`).

A new actor is a new `designs/actors/<id>.yaml` — never new renderer code (D-062 §18). If a
design needs something the cultivator cannot express, the CULTIVATOR grows a parameter or a
piece (`pibo`, `beard`, `cap`, `pendant`), and every actor can use it.

## Rules the code enforces

- Every opaque sprite pixel is one of the actor's ramp tones or the style ink.
- The LEFT facing renders the mirrored actions, so the striking hand is the near hand and LEFT
  is RIGHT reflected (strike height, VFX origin, anchors agree).
- Feet stand on cell row `feet_row` (43); the runtime profile must declare
  `anchor_offset = (0, 48 - feet_row)` or the build fails.
- A sheet whose adjacent frames or facings do not differ fails the build.
- Face detail (brows, almond eyes, nose, mouth, ears) is portrait LOD; the 32x48 sprite keeps a
  one-pixel eye (CHARACTER_ART_BIBLE §4).
- Only what the game LOADS ships. Portraits, passes, beauty renders and review boards stay in
  `work/` (the portrait is framed into the medallion the HUD loads; `ui_kit.MEDALLIONS` lists
  the ones a screen shows). Every shipped PNG goes through `pngout.save` — never quantized: an
  image over 256 colours is kept RGBA. `python3 pixel/pngout.py <png>...` repacks in place and
  fails if a single pixel would change.
