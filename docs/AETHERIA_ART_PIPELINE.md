# AETHERIA ART PIPELINE — Visual DNA, the Blender golden pipeline, the live UI, the benchmark

D-062. One visual DNA → many production representations: character, NPC, creature-ready rig,
icon, portrait, UI, world architecture and floor, VFX — authored as data, built in Blender, adapted
to pixel art by one adapter, measured against one benchmark. The game only ever loads PNG sheets
and `.tres` data; **Blender is a build tool, never a runtime dependency.**

Authority (D-062 §2): canon > gameplay/technical constraints > `CHARACTER_ART_BIBLE` >
`UI_UX_BIBLE` > architecture/readability > `MOTION_DESIGN_CONTRACT` > `XIANXIA_IDENTITY_CONTRACT`
> the three Aetheria moodboards (visual north star, never production art) > external references >
decoration. Reference → observe → analyse → extract principle → abstract → adapt → original;
never copy, trace, crop, recolour or assemble.

Code: `tools/aetheria_art_pipeline/` (README there for commands).

---

## 1. Style DNA — `style/aetheria_style.yaml` (style version 1.0)

The machine-readable source of truth. Every producer reads it; `validate/style_check.py` measures
art against it (JSON verdict + exit code). It defines, measurably where possible:

| Section | What it fixes | Measured by |
|---|---|---|
| palette | named colour ROLES (ink, lacquer ×4, paper, antique gold ×3, jade, qi, cinnabar, the four element hues, the Hoang Vực world roles) — a producer asks for a role, never a hex | every generator resolves roles |
| temperature | world bias COOL; warm share 3–22% of a gameplay frame; gold/element hues mark meaning only | `style_check frame`, benchmark `warm_share` |
| lighting | key from the screen's upper left (elev 55°, az 135°), fill 0.35, qi-tinted rim, 2–3 shadow steps per material, ≤6 highlight px per material per frame, contact shadow #0c1016 @ 0.38 | Blender lights, pixelizer bands |
| outline | ONE ink colour, 1px, traced from pixels after palette, never on glow; ≥85% of a silhouette border | `style_check sheet` outline coverage |
| character | 32×48 cell, height 40–47px, head ≈ 1/3 (canon R-5), ≤24 colours/frame, isolated-pixel share ≤3% (8-neighbour), value gap hair↔robe ≥0.08, silhouette/costume/hair language | `style_check sheet` |
| materials | cloth, silk, wood, lacquer, jade, metal, stone, paper, spirit — roughness/sheen/emission intent | Blender material ramps |
| vfx | source→gather→focus→release→travel→impact→dissipate; element hue + white core; peak ≤12% of the frame; idle glow ≤3% | benchmark `vfx_restraint`, `element_unity` |
| icons | one family: items are OBJECTS, techniques are SIGILS; one slot frame | icon review board |
| ui | lacquer + gold hairline inset 3px; translucency 0.78–0.94; ornament ≤7%; gold ≤10% of the HUD; five designed states; forbidden list (minimap, chat, skill ring, …); permanent area ≤15%; centre 50%×50% clear | theme tests, HUD tests, benchmark |
| world | depth layers, grounded props with contact/cast shadows, clustered vegetation, 1 art px = 1 world px, Hoang Vực = timber/slate/paddies (R-9) | map tests, benchmark |
| pixel_adaptation | render 4×, material vote per 4×4 block, authored ramps, light bands (0.16/0.40/0.84), alpha threshold 0.5, cleanup, ink after palette, anchors from bones | `pixel/pixelize.py` |

## 2. The canonical cultivator — `designs/cultivator.yaml`

ONE body, ONE 29-bone rig, ONE garment cut. Every humanoid = this + an actor file
(`designs/actors/*.yaml`) overriding palette ramps, a few proportions and pieces. Nothing in the
cultivator is a colour.

- **Proportion (canon first):** head ≈ 1/3 of the 32×48 figure (`CHARACTER_ART_BIBLE` §4, R-5).
  The moodboards' slender 8-head figures inform costume and gesture, never proportion.
- **Face (moodboard principle, adapted):** `humanoid.shape_head` sculpts the head ellipsoid into an
  oval face — a jaw narrowing to a pointed chin, cheekbones, a shallow face plane, a full skull —
  a deformation, so eyes/brows/mouth placed on the ellipsoid stay on the skin.
- **Face LOD:** the 32×48 sprite keeps a one-pixel eye (`lod: sprite`); the portrait and the
  presentation render get almond eyes (white, iris, a heavy lash line), brows, a wedge nose, a
  mouth and ears (`lod: portrait`). Detail that is noise at 32×48 is the face at 80px.
- **Hands:** a palm, four fingers, a thumb, relaxed and slightly curled; hand length ≈ 0.6 of the
  forearm; the sleeve ends at the wrist so the whole hand leaves it on every strike (it was buried
  in the sleeve at 0.38). No circle-hand shortcut (`CHARACTER_ART_BIBLE` §6b).
- **Hair:** a combed cap with strand ridges, curtain bangs from a centre part routed OUTSIDE the eye
  corners (they first covered the eyes), side locks behind the ear, a waist-length back mass that
  tapers, a bun and pin.
- **Garment:** crossed collar (left over right), bodice and a skirt that widens to the hem, the
  front hem lifted (graded through every ring below the knee) so a striding foot shows, wide
  sleeves, a sash with one broad tail. Pieces: `pendant`, `beard`, `cap`, `pibo` (the 披帛 stole).
- **Actors:** `player_proto` (white hair, grey-blue robe, jade sash), `player_daobao` (the Thanh Vân
  robe — an equipment visual is design data), `lin_yue` (Lâm Nguyệt: black hair, rose robe,
  narrower shoulders, flared hem, the stole — the second golden actor), `shen_buqi` (Thẩm Bất Kỳ:
  white topknot and beard, deep bell sleeves, ash robe, gilt sash), `ko_than` (Kha Thản: knee coat,
  trousers and boots, head-wrap, earth tones).

## 3. Blender workflow — `blender/`

Blender 5.2 via the blender-pro MCP (or headless `blender -b -P blender/cli.py -- <actor>`).

1. `build.py resolve <actor>` → `work/<actor>/spec.json` (design + actor + style).
2. `build_actor.build`: meshes from `model/humanoid.py`, the armature from `humanoid.bones`,
   weights, materials, the gameplay / presentation / portrait cameras, the canonical lights, and
   **one real Blender Action per animation plus its mirror** (constant interpolation — a sprite
   frame is a held pose).
3. `render_frames`: exact 1-sample **ID / light / depth** passes at 4× the cell, every animation ×
   four facings; anchors projected from the bones through the same camera. **LEFT renders the
   mirrored actions** — the striking hand stays the near hand, so the strike, its VFX origin and
   its anchor sit at chest height in both side facings (a pure yaw put the left-facing palm at head
   height).
4. `render_presentation` (beauty, portrait LOD, ink hull), `render_portrait`, `render_details`
   (hand close-ups) — review evidence, never game art.
5. `save` → `blender/aetheria_cultivator.blend` (the master: model, rig, 10 Actions, cameras,
   lights, materials).

**One material graph for everything:** diffuse lighting → (beauty ramp | material id | light |
depth), switched by one node-group value. Blender owns form, light and motion; the palette stays
authored. The presentation render adds an inverted-hull ink line (OFF in every gameplay pass).

## 4. Material profiles

Character materials are 4-tone ramps per actor (`[deep, shadow, base, light]`) with flags:
`highlight` (may take the light tone), `flat` (an accent takes at most two tones — a 2px sash in four
tones is noise), `priority` (wins the block vote: eyes, pins, jade), `min_tone` (skin is never
shaded below its base in a sprite — a 1px shadow on a 6px face read as a beard), `min_coverage` (an
eye needs 5 of 16 samples to own a pixel). World and prop materials (`designs/props.yaml` common):
slate roof tile, dark ridge, timber ×2, lime plaster, fieldstone ×2, door, window paper, cinnabar
lacquer (the outpost's ONE saturated accent), gilt (its name board only), bark, broadleaf leaves,
pine needles, moss, water. Foliage is darker and bluer than the meadow so canopies separate by
value.

## 5. Motion profiles — `model/motion.py`

| Animation | Frames | Law it keeps |
|---|---|---|
| idle | 6, loop | one breath: three distinct inhale beats, three exhale, hair answering a beat late (a held beat was caught by the validator as a stall) |
| walk | 8, loop | stride clocked by distance; feet by analytic two-bone IK on the ground (a planted foot never slides); arms counter the legs; hair trails |
| attack | 8 | 25% windup (weight back, hand to the hip), the hit on frame 2 (full extension, a step in), follow-through, recovery to ready |
| cast | 8 | seal at the chest, held before the face, the lead arm driven out, settle — mapped by phase quarters |
| meditate | 4 | sit, lotus, eyes closed (eye bones scale between open/closed) |

`motion.mirror(pose)` reflects a pose across the sagittal plane (S·M·S, L/R swapped) for the LEFT
facing.

## 6. Pixel pipeline — `pixel/pixelize.py`

BLENDER → controlled 1-sample passes → **rasterization** (per 4×4 block a weighted material vote;
precious materials need their coverage; only MATERIAL samples count as coverage) → **palette**
(the material's own ramp, banded on the light pass at the style's thresholds) → **cluster
correction** (4-neighbour tone speckle) → **inner contours** (depth breaks darken the far side) →
**despeckle** (8-neighbour isolation) → **ink outline** (transparent pixels touching opaque ones) →
contact shadow → **crop / anchor** (feet on row 43, bones projected, pixel centres, feet-relative)
→ **sheet** → **validators**: `aetheria_art.sheet.verify_animates` (adjacent frames and facings
must differ — fails the build), `style_check sheet` (height, colours, isolation, outline), and
the profile check (`anchor_offset = (0, 48 - feet_row)` or the build fails).

**Feet row 43:** seen from 30°, anything in front of the body projects below its own origin — a
striding toe (2–3px) and the near knee of the lotus seat (4–5px). At row 47 the toes fell out of
the cell (no step ever showed); at 45 the seated knee was cut. Profiles carry
`anchor_offset = (0, 5)`.

Every opaque sprite pixel is one of the actor's ramp tones or the ink. Not resize-and-pixelate.

## 7. Icons — `model/icons.py`, `blender/build_icons.py`, `designs/icons.yaml`

Items are objects resting on the ground plane (pill dish, spirit stone, jian, folded robe,
thread-bound manuals with the element's mark); techniques are sigils standing in the picture plane
(three crescent gusts round a calm core; a forked bolt with sparks). Same passes, light, ramps and
ink as the characters; **auto-framed** so every subject fills ~84% of its cell. 32×32 slot icons
(`ItemData.icon`, `SkillData.icon`) and 16×16 world variants (`ItemData.world_icon`, drawn by
`PickupFeedback`) — the 32px icon on the ground stood two-thirds of a person tall.

## 8. World — `world/ground.py`, `model/props3d.py`, `blender/build_props.py`, `world/sync_scene.py`

- **Layout design** (`designs/maps/<map>.yaml`): regions (polygons, paths with widths, rects) in
  world px drawn around the scene's fixed gameplay anchors; water blockers; solid props with their
  origins; decor to retire.
- **Ground painter:** organic edges (blur + noise + threshold), material-aware shading — meadow and
  forest floor in clustered drifts with tufts and rare flowers; packed earth under the turf's shadow
  lip, with pebbles; kerbed flagstones (Voronoi) with mortar, a lit bevel and moss; natural rock
  with mossy cracks; water deepening from a wet bank with a bright meniscus and ripples; a plank
  bridge; paddies with bunds and planted rows; leaf litter; the **broken vein** — fractured stone
  whose cracks seep qi (1px, the spirit material: emissive only where it carries force).
  Deterministic; writes the floor texture and `GroundLayoutData` (fill rect, paddy and water cells,
  materials, blockers).
- **Runtime:** `PaintedGround` answers the tiled floor's contract (`fill_rect`, `walkway_half_height`,
  `is_paddy_cell`, `is_flooded_cell`); `WaterBlockers` builds collision from the same blockers —
  painted water is the water that stops you; `WorldProp` draws a `PropData` sprite with its origin
  (front base centre — the line the y-sort compares) and its solid footprint; trees share one sway
  material per texture.
- **Props in Blender** at the character's pixel density (`ortho_units` per cell height) with
  **cast shadows caught on a ground plane** (reserved id 12): dwellings, the Thanh Vân outpost hall
  (cinnabar pillars, gilt board, swept eaves, tile courses and tile-ends), well, weapon rack,
  fences, broadleaf trees, pines, mossy boulders.
- **Scene sync** is idempotent: it writes every `Prop_*` from the layout, swaps a tiled Ground for
  the painted one, drops grass tufts the floor no longer has grass under, and removes unused
  resources.
- Maps: **Thôn Lạc Hà** (stream + bridge, paved square before the outpost, roads, houses, well,
  training yard, terraced paddies) and **Rừng Vỡ Mạch** (forest floor, game trail, clearing, the
  broken vein, the NE rocks, pines and boulders).

## 9. UI visual system — `ui/ui_kit.py` → `assets/ui/aetheria_ink/`

The live UI foundation (it replaced the CC0 xianxia pixel pack AND the glossy painted plates —
D-062 §7), generated from the DNA, wired `UIPalette → UITheme → screens` (no screen styles itself):

- **plaque** (text-bearing surface; measured dark centre), **band** (the quiet, frameless wash that
  fades toward the playfield), **five designed button plates** (normal · hover = lifted lacquer +
  full gold + jade underline · focus = jade ring + corner ticks drawn over normal · pressed = sunk,
  label 1px down · disabled = desaturated, legible), **keycap** (raised, jade-edged, solid under the
  glyph), **meter** (carved well + a white material fill mask the hue multiplies), **icon slots**
  (one family; an element ring for a technique), **white masks** (divider with a knot, notched
  frame, corner fret) tinted from palette tokens, **medallions** (the actor's pipeline portrait in a
  lacquer disc under a gold ring — the HUD face is the map figure).
- HUD: identity medallion + name/level/gauges + affiliation top-left; place plaque top-right; the
  technique dock bottom-centre (element-ring slots, keycaps, cooldown shade inside the well, the
  linh khí bar); prompts on the band bottom-left; announcements in the bottom band. Permanent area
  13% (budget 15%), the centre clear.
- `UITheme.icon_slot` is the one slot factory (satchel + dock); `UITheme.fill_color` the one way to
  ask a meter's hue.

## 10. Visual benchmark — `validate/visual_benchmark.py`

Structural similarity to the quality reference (`docs/visual_benchmarks/`, REFERENCE ONLY, gitignored
image + committed annotation), never pixel difference. Both images reduce to one analysis grid plus
region masks (the capture's regions come from `capture_motion golden`'s JSON — HUD rects and actor
rects of the chosen frame; the reference's from `reference_annotation.json`).

| Category (weight) | Measures |
|---|---|
| Composition (20) | HUD occupancy against the DNA band 8–15% (the reference's 24% includes forbidden features — shown, not chased), centre clear, saliency focal point, action centrality, left/right balance |
| Palette / lighting (15) | warm share, 5-band luminance hierarchy, RMS contrast, saturation |
| Environment (15) | strong-edge density, material colours ≥0.3% (one-sided up to 2×), detail rhythm (spread of detail over a 16×9 grid) |
| Character silhouette (15) | figure–ground colour distance, figure scale, ink definition, second-actor separation |
| Motion / combat (10) | visual pull inside the fight, combatant spacing, technique light landing between them |
| UI hierarchy / material (10) | HUD surface darkness, gold ≤10% (DNA), legibility spread, grouping into 4–6 plaques |
| VFX / spiritual (10) | presence (a third of the reference's spectacle is the restrained target), the ≤12% cap, element hue unity |
| Pixel readability (5) | 2×2 one-colour blocks (integer-scaled pixel art) |

Each measure scores 0–100 (similarity with a stated tolerance, or DNA compliance); categories are
means; total = Σ weight·score/100. **PASS ≥ 60 with every essential category ≥ 50.** Output:
`scorecard.json` + `scorecard.md` with both values and the reason for each measure.

**Current (golden frame, Lôi Chỉ at range in Thôn Lạc Hà): 79.4 / 100 PASS** — composition 95.7,
palette 59.4, environment 94.0, character 94.7, combat 42.1, UI 78.8, VFX 59.4, pixel 100
(`docs/visual_benchmarks/scorecard.md`; re-captured after the capture-review UX fixes — the
realm meter now spans the identity plaque). The loop that got there: the first golden frame scored
62.3 and FAILED palette at 37 (a one-band, low-contrast world) and combat at 8.6 (a melee clinch
unlike a readable duel); the world was re-lit (value range on paving, earth and meadow), the scene
re-staged as a ranged exchange, and the techniques made readable.

## 11. Provenance

All production art is ORIGINAL and recorded in `docs/ASSET_LICENSES.md` (P62*, K1–K6): source =
the pipeline code and design data in this repository, style version 1.0, generation method =
Blender passes + `pixel/pixelize.py` / `ui/ui_kit.py` / `world/ground.py`, output paths as listed.
The moodboards and the quality reference are reference only (gitignored); no pixel of them is in
any asset.

## 12. Performance review

- Textures: character sheets 4.0 MB VRAM total (27 sheets, RGBA8); the active map's floor 2.1 MB
  (960×576); world props 0.6 MB; UI kit 0.4 MB; icons < 0.1 MB. All lossless, no mipmaps (pixel
  art), nearest-filtered. Only the active map's floor is resident.
- Disk / repository: every shipped PNG is written by `pixel/pngout.py` (and the stdlib
  `raster.write_png`) as 8-bit palette + alpha — lossless, verified pixel-identical. The 93
  generated PNGs went 613 KB → 315 KB (a floor 165 KB → 84 KB, a sheet ~11.5 KB → ~5.3 KB).
  Build intermediates (portraits, passes, renders, boards) stay in the gitignored `work/`; the
  medallions, sprites and props that no scene loads (3 NPC medallions, the ring, 5 standalone
  portraits, the short fence, the stdlib broadleaf) were removed. All of `assets/` is ~0.6 MB (apparent size, `.import` files included).
- Draw: the floor is one sprite; props are one sprite + one static collider each (14 in Thôn Lạc
  Hà, 22 in Rừng Vỡ Mạch), y-sorted; tree sway is one shared shader material per texture.
- No per-frame UI rebuild: the HUD refreshes on pushes and language changes (pinned by
  `test_a_settled_hud_does_no_per_frame_work`); `CastFeedback` processes only while animating.
- Blender is not loaded by the game; the art is regenerated offline (≈2 min per actor, seconds
  per icon/prop, ~4 s per floor).

## 13. Limitations (honest)

- The mist wolf, the banners and the lantern posts are still drawn by the stdlib generator
  (`tools/aetheria_art/`) — consistent ink and density, but not yet Blender-built (the cloth and
  the paper lantern hang from the shared sway shader, tuned to those sprites). A quadruped rig is
  the next pipeline extension. The training post, the Lạc Hà stele and spring are Blender-built;
  the broken vein is painted into the forest floor.
- `PrototypeGround` remains for any map without a painted layout; both shipped maps are painted.
- Benchmark palette (≈60) stays below the other essentials: a painterly reference has bright mist
  and waterfalls a frontier village does not, and the quality rule forbids buying it with glow or
  saturation.
- Lâm Nguyệt appears in the golden scene as a placed figure; NPC presence systems are P16+.
- The menu backdrop is the one painted asset still live (behind the menu only).

## 14. Checkpoint record (D-062 §32)

| CP | Result | Evidence |
|---|---|---|
| CP0 Audit | PASS | Blender connected; UI tiers judged insufficient; benchmark conflicts R-12..R-16 recorded |
| CP1 Style DNA | PASS | `aetheria_style.yaml` + `style_check.py`; design sheet reviewed before modelling |
| CP2 Premium UI | PASS | ink kit live; five designed states; medallion; one slot family; theme tests re-pinned on measured invariants; real captures (menu, HUD, satchel, robe + dock) |
| CP3 Canonical design | PASS | `cultivator.yaml` + five actors |
| CP4 Blender model | PASS | `aetheria_cultivator.blend`: 35+ meshes, 29 bones, materials, cameras, lights, 10 Actions |
| CP5 Materials / light / camera | PASS | one material graph, canonical light, gameplay/presentation/portrait/detail cameras |
| CP6 Motion | PASS | five animations, IK feet, mirrored LEFT, validator caught and fixed a held idle beat |
| CP7 Top-down render | PASS | 30° orthographic passes at 4×; feet row fixed after the toe and knee were seen clipped |
| CP8 Pixel output | PASS | 25 sheets pass `style_check`; animate validator; anchors; profile check |
| CP9 Godot | PASS | existing `CharacterVisualProfileData`/`CharacterVisualComponent`; 795 tests, 3 E2E |
| CP10 Golden scene | PASS | Thôn Lạc Hà painted + Blender village; Rừng Vỡ Mạch; `capture_motion golden` |
| CP11 Benchmark | PASS | 79.4 / 100 (80.4 before the site props were rebuilt), every essential ≥ 50 |
| CP12 Second actor | PASS | Lâm Nguyệt (+ Thẩm Bất Kỳ, Kha Thản, the Thanh Vân robe) by design data only — no renderer change |
