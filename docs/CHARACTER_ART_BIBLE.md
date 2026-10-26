# CHARACTER_ART_BIBLE — Aetheria

> The binding style rules for every character sprite in Aetheria, so the whole cast reads as
> ONE game — not ten asset packs glued together. Companion to `.kiro/steering/06-art-assets.md`
> (technical baseline) and `docs/CHARACTER_SYSTEM.md` (the domain side). Phase 05 (D-026)
> establishes the pipeline with self-made prototype art; a real art pass later swaps the
> textures without touching code (the look is DATA — `CharacterVisualProfileData`).

## 1. Pillars

- **Top-down, pixel art, one consistent density.** Every character shares the same pixel
  size and the same visual language (outline weight, shading, proportions).
- **Readable silhouette first.** A character must be recognizable as a dark silhouette.
  Pose and proportion carry the read; detail is secondary.
- **Data-driven, swappable.** A character's look is a `CharacterVisualProfileData` resource,
  never hard-coded in a scene. Replacing the art pack = replacing textures the profile points
  at.

## 2. Technical baseline (binding)

- **World grid: 16px** (`.kiro/steering/06-art-assets.md`, D-022). All character art is
  authored on this grid.
- **Character baseline: `32 × 48`** (one frame) — exactly 2× the original 16×24, so the figure
  is 2 tiles wide and 3 tall and every scale factor stays an integer (D-046). It grew for a
  specific reason, not for detail's sake: the cast's defining features are waist-length hair, a
  layered floor-length robe and (once a realm earns it) visible qi, and none of those survive a 6px-wide
  torso. A further size change must be logged in `DECISIONS.md`.
- **Nearest filtering, no mipmaps, integer scaling only.** No fractional/bilinear scaling
  that blurs edges. The project default texture filter is nearest; sprite nodes also set
  `texture_filter = nearest` locally. Import `compress/mode = lossless (0)`, `mipmaps = off`.
- **Sheet layout: a GRID** (D-046) — one ROW per direction (DOWN, UP, LEFT, RIGHT, top→bottom)
  × N animation COLUMNS (left→right), cell = `frame_size`. So `width = frame_size.x * frames`
  and `height = frame_size.y * 4`. **The frame count is derived from the texture width**, never
  authored, so art and data cannot drift apart. A width that is not a whole multiple of the
  frame width is rejected, not floored.
  Idle and walk are separate sheets and MAY have different frame counts (since D-057B a 6-beat
  idle breath, an 8-frame walk stride and an 8-frame attack). `idle` is required; `walk` is
  optional and falls back
  to idle — no fake animation. The previous layout was one row of 4 frames, i.e. a single pose
  per direction; combined with every profile leaving `walk_sheet` null it meant the cast never
  animated at all.
- **Animation speed is DATA**, not code: `CharacterVisualProfileData.frame_duration` seconds
  per frame, authored per archetype (an elder shuffles, a youth strides). A single-frame sheet
  must leave the component's `_process` off so a static character costs nothing per frame.
- **RIGHT is LEFT mirrored** in the generator, so the two profiles can never drift apart.
- **The outline is traced from the pixels**, not hand-drawn, so it stays correct for every pose
  and frame. A soft glow (a paper lantern's light) is drawn AFTER the outline pass and the pass
  only considers fully-opaque neighbours, so a halo is never outlined. **Qi is never baked into a
  character sheet** (D-057B): a PHÀM body has none, and when a realm earns it, it is a runtime
  effect placed on the frame's anchors — so it can appear, gather and vanish with the state.

## 3. Anchor & collision (the alignment rule)

- **Anchor at the FEET.** The sprite is drawn so the character's feet sit on the node origin
  (the component lifts a `frame_size.y`-tall sprite up by its full height, less
  `anchor_offset.y`). This makes depth-sorting and "standing on a tile" correct and consistent
  for every character. The Blender-built sheets stand their feet on **row 43** of the 48px cell
  and their profiles declare `anchor_offset = (0, 5)` (D-062): seen from 30°, a forward foot and
  the near knee of the lotus seat project below the origin and must stay inside the cell. The
  pipeline fails a build whose profile disagrees.
- **Collision footprint is INDEPENDENT of sprite height.** The body/collision shape
  represents where the character stands (roughly the feet + a small torso radius), NOT the
  full drawn height. A 24px-tall sprite does not get a 24px-tall collider — the collider is a
  small box at the feet. This keeps movement/overlap feeling grounded and lets art height vary
  (a tall elder, a short child) without changing how they navigate the 16px world.
- **Integer alignment.** Sprite position offsets are whole pixels so frames never land on a
  half-pixel (which nearest-filtering would show as a seam).

## 4. Silhouette, outline, shading

- **Silhouette:** compact, upright, head ≈ 1/3 of height for a readable top-down figure.
  Avoid thin limbs that vanish at 16px.
- **Outline:** a single-pixel dark outline on the body's left/right edges + key internal
  seams (not a full outline on every pixel — that muddies small sprites). One consistent dark
  ink color (`#14141c`-ish) across the whole cast.
- **Shading:** two-tone minimum per material (base + one shadow), light implied from
  top. Keep ramps short (2–3 steps) at this size; more steps read as noise.
- **Highlight:** sparing, 1px, only where it clarifies form (shoulder, hair edge).

### 4c. The player reads at 1× (art-01)

The protagonist is the one figure watched all game, so its four looks (`player_proto`,
`player_daobao`, `player_f_proto`, `player_f_daobao`) carry three readability rules on top of
§4, all as design data in `designs/actors/player_*.yaml` — same cell, same rig, same anchors,
same DNA:

- **Hands leave the sleeve.** A resting palm faces the body, so the front camera meets it
  edge-on; at the cultivator's thickness it lost every pixel vote to the sleeve and skirt behind
  it and the front idle showed no hand at all. The player's hands are thicker
  (`body.hand_shape: palm / palm_squash / finger_radius`); the bones do not move, so the palm
  and blade anchors are byte-identical.
- **A face, not a ball.** The face takes its skin's base AND light tone — the light where the
  top-left key lands (`highlight_at`, because a face never reaches the style's top light band) —
  and still never a tone darker than its base (`min_tone`: a shadowed chin reads as a beard) —
  not even where a bang passes in front of the cheek: in a sprite the inner-contour pass now
  stops at `min_tone` too. Her face sits under a larger bun, so her light starts a little lower
  (`highlight_at` 0.56 against his 0.6) and every breath frame keeps both tones.
  The portrait's two curtain bangs covered the cheek beside each eye at 32×48 — the face was a
  4 px slot with an eye on each hair edge — so the sprite draws one narrower bang per side set
  further out (`hair.bangs.sprite_locks`) and the portrait keeps its own
  (`hair.bangs.portrait_only`): the face opens to 6–8 px with skin on both sides of each eye.
  The sprite-LOD eye is a little larger so both eyes win their pixel. None of this reaches the
  portrait LOD: `highlight_at` is a sprite rule like `min_tone` (`pixelize.rasterize` applies it
  only outside the portrait), so the portrait's skin keeps its own tones and
  `medallion_player_proto.png` rebuilds byte-identical.
- **The second look is not a recolour.** The woman's jacket is one tone deeper than his robe
  (lilac over jade under white hair: three values to his two) and her hem flares wider (an
  A-line against his column). The jacket is a material, so its deeper ramp would also reach her
  portrait's shoulders; the HUD medallion is a UI asset outside this pass, so the material
  carries a `portrait_ramp` (the old jacket, applied by `pixelize.to_image` only to the portrait)
  and `medallion_player_f_proto.png` rebuilds byte-identical. Open follow-up: a UI item drops
  `portrait_ramp` and rebuilds that medallion, so the HUD matches the figure on the map.

`tools/aetheria_art_pipeline/validate/readability.py <actor>...` measures this on the shipped
sheets (face tones, eye pixels, hands at the rig's own palm anchors per facing, hem width,
garment values, silhouette difference between looks) and draws a 1×/8× board — with
`--before <rev>` a before/after board; `tests/unit/presentation/test_player_readability.gd`
keeps it (hands at the anchors; facing the camera two eyes, skin outside each, a face ≥ 6 px
wide on the eye row; her hem ≥ 2 px wider than his in both garments). Profile (LEFT/RIGHT)
eyes are not asserted yet: that rule needs a pixel enclosed by the face on both sides, which a
profile does not promise; whether profiles keep an eye pixel is an open measurement.
`tools/capture_player_looks.gd` shoots each look in the real hub at 1× with a ×4 crop
of the player, and with a folder of older sheets the same frame "before"
(`readability.py <looks> --before <rev> --export-before <dir>` writes that folder). From behind (UP) the body hides the hands, as it should. Whether the result is
"good enough" is the owner's call from real captures.

## 5. Palette rules

- **Shared ink + skin ramps**, per-archetype accent. All characters draw their outline from
  the same dark ink and their skin from a small shared skin ramp, so the cast is cohesive;
  each archetype gets a distinct ROBE + ACCENT color to be told apart at a glance
  (jade-blue player, rose female cultivator, grey/white elder, earthy merchant).
- **Hair / clothing** read as flat areas with one shadow step; the accent (sash/trim) is the
  one saturated note per character.
- No per-character bespoke palettes that fight the whole — a new character picks from the
  shared ramps + one accent.

## 6. Direction & animation rules

- **4 cardinal directions** of art (DOWN/UP/LEFT/RIGHT). The world has 8-way movement; the
  visual collapses a diagonal to the nearest cardinal, with **horizontal winning ties**
  (`CharacterVisualProfileData.direction_for_vector`). We do NOT fake 8 directions by
  uncontrolled flipping. (LEFT/RIGHT may be authored as mirror pairs deliberately; that is a
  content choice in the sheet, not an engine hack.)
- **Facing persists at rest:** a zero movement vector keeps the last facing, so a stopped
  character faces where it last walked rather than snapping to DOWN.
- **Animation states:** LOCOMOTION `idle` and `walk` (Phase 05), and the ACTION layer's `attack`
  sheet (D-056) — a one-shot whose frame is driven by the gameplay lifecycle, never by its own
  clock (player 8 frames, mist wolf 6 since D-057B; the column count is free, derived from the width). Other
  actions (`CAST`, `HIT`, `DEATH`, …) are reserved vocabulary
  (`PRESENTATION_ARCHITECTURE_CONTRACT.md` §5) and get a sheet only in the phase that authors the
  content using them. No off-screen/inactive animation (`.kiro/steering/05-performance-testing.md`).

### 6b. Motion at this scale (D-057)

How a figure moves is owned by `docs/MOTION_DESIGN_CONTRACT.md` §3; what this bible adds is what
that means at **32×48 seen from above**:

- **The silhouette carries the motion.** Most of the joint chain is implied, not drawn, so a key
  pose must change the silhouette enough to read at 1×, and weight shows as a 1px body shift.
- **One limb does the whole gesture, and no limb teleports** — the arm that coils is the arm that
  strikes, and it stays attached to the shoulder on every frame (both shipped once, D-056).
- **No T-pose, no circle-hand shortcut, no broken joints, no floating feet.**
- **Inspect magnified (6×–10×), then at 1× in a real capture**, before an action sheet ships.
- **Reference illustrations are not this style.** The Aetheria xianxia moodboards are painterly,
  front/side view, with slender anime proportions; they inform costume language and gesture,
  never proportion, rendering or view (`XIANXIA_IDENTITY_CONTRACT.md` §2.3 R-5, §4 `01`).

### 6c. Gait, anchors and reactions (D-057B)

- **Locomotion is a gait, not a loop.** The walk is clocked by the DISTANCE the figure moved
  (`stride_px` = ground per full cycle), so cadence follows real speed and a body blocked by a wall
  stops striding instead of treading air. It opens and closes on the profile's
  `walk_rest_columns` (feet near the idle stance): a stop lets the planted foot finish its step.
- **A 180° turn passes through the side or front facing** for a few frames; a diagonal holds the
  current facing inside a ~53° band (hysteresis), so a creature chasing on a diagonal does not
  flicker.
- **Every sheet ships with ANCHORS** (`data/characters/visual/anchors/*.tres`,
  `CharacterAnchorData`) written by the generator from the same pose that drew the frame, at the
  pixel CENTRE, relative to the feet: `palm` (the striking point — a wolf's jaw is its `palm`),
  `rear_palm`, `core`. An effect that starts from a body part asks the visual for the anchor of
  the frame being drawn; it never guesses an offset.
- **The front face ends at the chin.** Under the chin is the collar in shadow — never background
  (outlined dark it read as a chinstrap) and never hair (it read as a beard on every archetype).
- **The palm strike stands the palm UPRIGHT at the arm's tip** (heel forward, fingers up). A hand
  hanging under a level sleeve reads as a limp reach.
- **Side-view stride drives the hem**: the leading leg kicks the front of the robe out and lifts it
  while it swings, and the shoes show below the hem. At 1× the hem IS the legs.
- **A struck body reacts by its law**: a creature recoils (whole pixels, along the blow), a rooted
  object wobbles about its base (whole-pixel row shear — never a rotation, which shows mixels at
  2× zoom).

## 7. Modular layering (future)

The pipeline is designed so a later art pass can composite a character from layers (body →
clothing → hair → accessory) that all share the 32×48 cell + direction-row grid layout. Phase 05
ships flat per-archetype sheets, but the cell/layout contract is the seam a layered system
plugs into without changing `CharacterVisualComponent` or the profile contract.

## 8. Provenance (hard rule)

- Every character texture has a clear source + license recorded in `docs/ASSET_LICENSES.md`.
- Every humanoid sheet, anchor file and portrait is **self-made / project-owned** and built by
  ONE source since D-062: the Blender pipeline (`tools/aetheria_art_pipeline/`, design data per
  actor, `docs/AETHERIA_ART_PIPELINE.md`). The stdlib humanoid generator was retired so no two
  tools write the same sheet; `tools/gen_prototype_assets.py` still draws the creature and the
  older props. The runtime never depends on either.
- No screenshot/Pinterest/mirror/unknown-license/AI-of-unclear-rights asset ever enters the
  project (`.kiro/steering/06-art-assets.md`).
- **Reference libraries are research, never source art.** Everything under `docs/design_refs/` —
  including the Aetheria xianxia moodboards — is reference-only: never imported (`docs/.gdignore`),
  never traced, cropped or recoloured into a sprite. Wanting what a reference shows means
  RE-CREATING it as original art (`XIANXIA_IDENTITY_CONTRACT.md` §10). A verified CC0 base (e.g. an OpenGameArt
  "character base") may be adopted later ONLY from its official source with the license
  recorded, and only after it is normalized to this bible (density, anchor, palette) — never
  mixed in raw.

## 9. The one-sentence test

> Drop a new character next to the existing four: if it looks like it belongs in the same
> game (same density, same anchor, same ink, one accent), it passes. If it looks pasted in
> from another pack, it fails — fix the art, not the engine. And once it moves, it must move
> like the cast (`MOTION_DESIGN_CONTRACT.md` §3) and behave like Aetheria
> (`XIANXIA_IDENTITY_CONTRACT.md` §5).
