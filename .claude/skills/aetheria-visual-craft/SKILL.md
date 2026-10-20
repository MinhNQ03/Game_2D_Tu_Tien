---
name: aetheria-visual-craft
description: Method that makes Aetheria art, animation and VFX look designed - measure, compose, build from the pipeline, verify in the real window. Use before any art, map, UI-picture or VFX work.
---

# Aetheria visual craft — the working method

The rules (palette, sizes, timing, HUD limits, canon) live in their owners; this skill is the
ORDER OF WORK that has produced visible improvement here. If an owner disagrees, the owner wins.

Owners to open first: `docs/VISUAL_CRAFT_WORKFLOW.md` (the brief), `docs/AETHERIA_ART_PIPELINE.md`
(Blender → pixel; §10a story art, §10b VFX), `tools/aetheria_art_pipeline/style/aetheria_style.yaml`
(Visual DNA), `.kiro/steering/06-art-assets.md`, `docs/MOTION_DESIGN_CONTRACT.md`,
`docs/PRESENTATION_ARCHITECTURE_CONTRACT.md`, `docs/UI_UX_BIBLE.md`, `docs/ASSET_LICENSES.md`.

## 1. Measure before you touch
- Capture the REAL window first (`tools/capture_ui.gd`, `tools/capture_motion.gd`; real display,
  `DISPLAY=:0`, slow — run in the background). Never judge from an editor or a mockup.
- Put numbers on "flat": value mean / sd / p5 / p95, saturation, warm-pixel share (the DNA has a
  3–22 % band). A finding is "p95 0.67, warm 2.7 %", not "looks dull".
- Owner reference shots live in `docs/design_refs/` (gitignored, never imported). Extract the
  PRINCIPLE (focal point, value range, layering, leading lines), never the picture.

## 2. Compose, then produce
- One focal point per picture/screen; name it in the code comment of what draws it.
- Light tells the story: one warm practical source against a cool ground; mist for depth.
- Leading lines (a worn road, a runnel), masses before details (beds, groves, not sprinkles).
- Warmth and saturation are signals, not fill (DNA `accent_rule`).

## 3. Build from the pipeline, never by hand
- Characters/props: the canonical cultivator + `props3d` geometry → Blender passes → `pixelize`.
- Story pictures (painted tier, LINEAR): `blender/build_story_art.py` → `build.py origins`.
- VFX: `designs/vfx.yaml` → `blender/build_vfx.py` (intensity pass, built per time t, seeded) →
  `build.py vfx` (ramp-banded strips + `data/fx/*.tres`, validated). Played by
  `VfxSequencePlayer` on an EXISTING gameplay cue — presentation never decides timing or state.
- Floors: data in `designs/maps/<map>.yaml` → `world/ground.py` (deterministic; check two hash
  seeds give the same md5) → `world/sync_scene.py`.
- Every shipped PNG through `pixel/pngout.py`; painted pictures as WebP; record provenance.

## 4. Motion and VFX law
- Energy chain: source → gather → focus → release → travel → impact → dissipate. Frame 0 shows
  the SOURCE (an empty first frame fails the packer).
- Element hue + white core; never a second element's hue. Choose blend IN THE REAL WINDOW:
  additive burns to white on a sunlit floor (use mix there); additive is right at dusk/night.
- No permanent halos: a gather plays once per sitting; idle costs nothing (`_process` off).

## 5. Verify like a player, then like an animator
- Real window, both languages, two aspect ratios (1280×720 and 1280×800). Open every image.
- Look at 1× (can a player read it?) and magnified (pixel defects, anchors, alpha).
- Compare before/after from the same tool and camera; re-measure the numbers from step 1.
- Every invariant becomes a test; mutate the fix once to prove the test goes red.
- Write down what is still flat, with an owner. Art-direction changes to a frozen baseline
  (cell size, palette brightness) are the owner's decision: bring evidence (an in-engine A/B),
  not a silent change.
