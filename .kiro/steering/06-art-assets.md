# 06 — Art & Assets

> Steering: always included. How assets are sourced, imported, and tracked.

## Style

- 2D top-down, pixel art / stylized. Consistent pixels-per-unit and palette.
- Renderer is `gl_compatibility` — design within its 2D feature set (confirmed in
  `project.godot`).

## Pixel-art import rules

- Textures: filtering **off** (nearest), mipmaps **off** for sprites.
- Keep a documented base tile/sprite size; don't mix incompatible pixel densities.
- Use texture atlases / sprite sheets to reduce draw calls and node count.
- Prefer `.png` for sprites; keep source (`.aseprite`/layered) out of `res://` runtime
  paths if large, or in a clearly separated source folder.

## Technical baseline (confirmed, D-022 / Phase 03; upgraded D-029)

- **Base tile size: `16px`** (`Vector2i(16, 16)`). Keep it consistent; don't mix
  incompatible pixel densities without a strong technical reason logged in `DECISIONS.md`.
- Character baseline is `16×24` (`player_proto.png` single frame + the `*_proto_idle.png`
  64×24 four-direction sheets). **The character sprite is still PROTOTYPE art** — none of the
  licence-cleared packs ships a 16×24 four-direction tu-tiên figure, so replacing it needs art
  authored to that spec (D-045).
- **The map floor is the Verdant 00 East Asian Village 16px set** (`assets/tiles/verdant/`,
  `data/maps/east_asian_tileset.tres`, D-045): 4 moss (`koke`) fills + 4 cut-stone (`ta`) fills
  + a stone-on-moss transition autotile, of which the **16 cardinal masks** are wired. This
  REPLACED the 3-tile `48×16` prototype strip (`prototype_tileset.png`, D-022/D-029) — one
  repeated grass tile over a whole map is what read as unfinished, and the floor is most of the
  screen. The old strip stays in the repo but no map references it.
  Licence: free/commercial, no attribution, **may not be resold as an asset pack** — terms in
  `assets/tiles/verdant/LICENSE.txt` and `docs/ASSET_LICENSES.md`.
- Project default texture filter is **nearest** (`project.godot`
  `rendering/textures/canvas_textures/default_texture_filter=0`); pixel-art nodes also set
  `texture_filter = 1` (nearest) locally. Mipmaps **off** on sprite/tile imports.
- Integer-friendly scaling: prefer integer scale factors; the arena/maps are authored on a
  16px grid so tile and collision edges stay aligned.
- These world/character assets are **self-made / project-owned**, reproducible via
  `tools/gen_prototype_assets.py` (a build-time tool; the game runtime does NOT depend on it).

### Current world/character art tier (D-029)

- The hub/field tileset, the player sprite, the four archetype idle sheets, and the garden
  **props** (`assets/sprites/props/` — lantern / tree / rock / planter, placed as presentation-
  only `Sprite2D` under each map's `Visual/Decor`) are at the **production-foundation** tier:
  shaded + ordered-dithered tiles and a fully-outlined, shaded top-down figure.
- They are STILL **project-owned / self-made** and will keep being upgraded in later feature
  phases (NPC, sect members, factions, merchants, combat, bosses, cultivation states) under the
  Continuous Visual Integration policy (`docs/ROADMAP.md`). **This is NOT final art.**
- The D-029 world art is NO LONGER a flat prototype — do not describe it as such. The visual
  tier ladder is: prototype → **production-foundation (current)** → feature-specific environment
  art → refinement → consolidation/polish.
- Do NOT import side-scroller terrain/characters into the top-down world; new environment/
  character art is chosen per domain and per license.

## Provenance (hard rule)

- **Every external asset must have a clear source and license.** No asset with an
  unclear or missing license enters the project.
- Each external asset is recorded in `docs/ASSET_LICENSES.md` with: name · source ·
  URL · license · asset type · where used · attribution requirement (if any).
- Attribution-required assets must have their attribution satisfied (in-game credits
  and/or `ASSET_LICENSES.md`) before release.

## Organization (proposed folder layout, created when first asset lands)

```
assets/
  sprites/     characters/ enemies/ bosses/ pets/ items/ equipment/ fx/
  tiles/       <tileset>/
  ui/          <pack>/panels/ buttons/ frames/   # [exists: ui/xianxia, D-028 live UI]
  sprites/     props/                             # [exists: garden props, D-029]
  audio/       music/ sfx/
  fonts/       # must include a font with full Vietnamese glyph coverage
```

## UI assets baseline (confirmed D-024; current set = Xianxia Pixel Pack, D-028)

- **UI is pixel art too**: nearest filter, mipmaps off, like the world art. The project
  default `rendering/textures/canvas_textures/default_texture_filter=0` (nearest) applies;
  UI `TextureRect`s also set `texture_filter = nearest` locally.
- **9-slice is mandatory for stretchable frames.** Panel/button/frame textures carry a
  documented, non-stretched border MARGIN consumed as the `StyleBoxTexture.texture_margin`
  (declared per slot in `UIPalette` — panel 17, inset 24, button 16, portrait 17 for the
  current Xianxia set). Only the center stretches, so corners stay crisp at any panel size —
  never scale a whole pixel-art frame with fractional/stretch that distorts corners.
- **`content_margin >= texture_margin`** on every framed box. The border band does not
  stretch, so a smaller content margin draws text on top of the frame art (D-034).
- **MEASURE an asset before building colour/layout on it** (D-034, L-021): pixel size, centre
  alpha (is there a fill to draw on?) and centre brightness (light or dark surface?). The
  measured numbers for the current set are recorded in `ui_palette.gd`. Two consequences worth
  knowing: `panel.png` is a LIGHT plate (brightness 230) so it must NOT sit behind this
  project's light-only text palette — `panel_stylebox()` uses the dark ink inset and the light
  plate is `accent_panel_stylebox()`; and `key_badge.png` is a HOLLOW corner ornament (centre
  alpha 0), not a keycap, so the key chip is drawn as a flat `StyleBoxFlat` until real keycap
  art exists.
- **A frame belongs in a `NinePatchRect`.** A `TextureRect` used as a fixed-size slot MUST set
  `expand_mode = EXPAND_IGNORE_SIZE`, otherwise it reports its whole texture as its minimum
  size and `custom_minimum_size` silently does nothing (D-034).
- **Integer scaling only** for pixel UI; no fractional scale that blurs edges.

### The PAINTED UI tier is a documented exception (D-044)

There are now **two** UI asset classes, and they do not share rules:
- **Pixel art** (`assets/ui/xianxia/`) — nearest filter, integer scale, everything above applies.
- **Painted** (`assets/ui/aetheria/`, self-made/project-owned) — **LINEAR** filter, and
  non-integer stretching is acceptable. Forcing nearest on a soft gradient or on fine gold
  filigree stair-steps it; the nearest/integer rule exists to protect a PIXEL GRID, and painted
  art has none. 9-slice margins still apply, to protect ornate ENDS from being stretched.

They live in separate folders with separate `UIPalette` constants **on purpose** — so the two
rule sets cannot be confused. This exception is UI-only: the world, tiles, props and character
sprites remain strictly pixel art under the rules above.

**The brightness rule binds BOTH tiers.** `SURFACE_LIGHT_BRIGHTNESS_LIMIT` (120) is not a
pixel-art rule, it is a legibility rule: any surface carrying this project's light-only text
palette must measure below it. D-034 enforced it for panels and missed the buttons, which sat at
202 for four phases. When you wire ANY new surface that carries text, measure its centre
brightness and add the assertion.
- **Single source of truth for UI tokens + asset paths**: `src/presentation/ui/ui_palette.gd`
  (colors, type scale, spacing, texture paths, per-slot 9-slice margins) → `ui_theme.gd` builds
  the shared `Theme` → `MainMenu` / `GameplayHUD` / future screens consume it. Swapping the art
  pack is editing files under `UIPalette.UI_ASSET_DIR`, not touching gameplay/UI logic.
- **UI DESIGN direction is frozen in `docs/UI_UX_BIBLE.md`** (D-039): the visual language, the
  information hierarchy (panel/typography/icon/semantic-colour/interaction states/modal + navigation
  ownership), the screen inventory, the rule that the UI must communicate the player's EXPANDING
  understanding of the world, and the first-usable-UI-per-feature-phase evolution plan. Two
  consequences for asset work: **colour is never the only carrier of meaning** (always text or icon
  too), and every layout must absorb **+40% string length** for vi↔en without clipping. This file
  stays the owner of asset/import/provenance rules; the bible owns the design direction.

### Current UI (D-028 — live)

- The **live production UI foundation** is the CC0 **Xianxia Pixel Pack** UI set under
  `assets/ui/xianxia/` (jade panel, ink inset, jade/silk buttons, rosewood portrait frame,
  corner key-badge, jade divider), wired through `UITheme`/`UIPalette`. It is **CC0 1.0** per
  the provenance record in `docs/ASSET_LICENSES.md`.
- This REPLACED (superseded) the earlier self-made prototype UI (`assets/ui/mana_soul/` +
  `tools/gen_ui_assets.py`, D-024, now retired). The current UI is **not** a self-made prototype,
  and tiopalada's "Tiny RPG - Mana Soul GUI" is **no longer an intended upgrade** — do not
  describe either that way.
- **Foozle Lucifer RPG UI** and **Tiny RPG Mana Soul GUI** remain CC0 *supporting candidates*
  only (recorded, not live). Do NOT splice multiple packs verbatim into a collage; the current
  live UI language is Xianxia.
- The Xianxia UI is a **production foundation**, still subject to incremental polish under
  Continuous Visual Integration (`docs/ROADMAP.md`); it is not frozen as final.
- **Not every slot is asset-backed any more (D-034).** The key-prompt chip is a drawn
  `StyleBoxFlat` because the pack ships no keycap (its `key_badge.png` is a hollow corner
  ornament). This is a deliberate, tested legibility trade, not an oversight; swap it back the
  day real keycap art lands. `docs/ASSET_LICENSES.md` records the asset as unused for that slot.

## Fonts & localization

- Fonts MUST cover Vietnamese diacritics and the English set. Verify glyph coverage
  before committing a font. See `.kiro/steering/07-localization.md`.

## Naming

`snake_case`, descriptive, grouped by domain (`enemy_slime_walk.png`,
`item_potion_health.png`). No spaces, no uppercase.
