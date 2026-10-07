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
validate/style_check.py          measures produced art against the DNA (JSON verdict, exit code)
validate/review_sheet.py         the visual-review board per actor
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
