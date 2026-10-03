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

## Technical baseline (confirmed, D-022 / Phase 03)

- **Base tile size: `16px`** (`Vector2i(16, 16)`). Keep it consistent; don't mix
  incompatible pixel densities without a strong technical reason logged in `DECISIONS.md`.
- Prototype player sprite is `16×24` (`player_proto.png`); prototype tileset is a `48×16`
  strip of three 16px tiles (grass / path / wall), `prototype_tileset.png`.
- Project default texture filter is **nearest** (`project.godot`
  `rendering/textures/canvas_textures/default_texture_filter=0`); pixel-art nodes also set
  `texture_filter = 1` (nearest) locally. Mipmaps **off** on sprite/tile imports.
- Integer-friendly scaling: prefer integer scale factors; the arena/maps are authored on a
  16px grid so tile and collision edges stay aligned.
- Prototype assets are **self-made / project-owned**, reproducible via
  `tools/gen_prototype_assets.py` (a build-time tool; the game runtime does NOT depend on
  it). They are PROTOTYPE art — a real art pass replaces them later.

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
  ui/
  audio/       music/ sfx/
  fonts/       # must include a font with full Vietnamese glyph coverage
```

## Fonts & localization

- Fonts MUST cover Vietnamese diacritics and the English set. Verify glyph coverage
  before committing a font. See `.kiro/steering/07-localization.md`.

## Naming

`snake_case`, descriptive, grouped by domain (`enemy_slime_walk.png`,
`item_potion_health.png`). No spaces, no uppercase.
