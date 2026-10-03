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
- **Character baseline: `16 × 24`** (one frame). Width matches the tile; height is 1.5 tiles
  so a standing figure reads above the ground without dominating a 16px world. This is the
  Phase-05 chosen baseline (the alternative 16×32 is reserved for later "tall" archetypes —
  bosses/elders in a dramatic pass — and must be logged in `DECISIONS.md` if adopted).
- **Nearest filtering, no mipmaps, integer scaling only.** No fractional/bilinear scaling
  that blurs edges. The project default texture filter is nearest; sprite nodes also set
  `texture_filter = nearest` locally. Import `compress/mode = lossless (0)`, `mipmaps = off`.
- **Sheet layout:** one row of 4 directional frames (DOWN, UP, LEFT, RIGHT), left→right, cell
  = `frame_size`. Idle and walk are separate sheets of the same layout. (`idle` is required;
  `walk` is optional in Phase 05 and falls back to idle — no fake animation.)

## 3. Anchor & collision (the alignment rule)

- **Anchor at the FEET.** The sprite is drawn so the character's feet sit on the node origin
  (the component lifts a `frame_size.y`-tall sprite up by its full height). This makes
  depth-sorting and "standing on a tile" correct and consistent for every character.
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
- **Animation states (Phase 05):** `idle`, `walk`. `attack` and other states are DEFERRED to
  the Combat phase. No off-screen/inactive animation (`.kiro/steering/05-performance-testing.md`).

## 7. Modular layering (future)

The pipeline is designed so a later art pass can composite a character from layers (body →
clothing → hair → accessory) that all share the 16×24 cell + 4-direction layout. Phase 05
ships flat per-archetype sheets, but the cell/layout contract is the seam a layered system
plugs into without changing `CharacterVisualComponent` or the profile contract.

## 8. Provenance (hard rule)

- Every character texture has a clear source + license recorded in `docs/ASSET_LICENSES.md`.
- The Phase-05 prototype sheets are **self-made / project-owned**, reproducible via
  `tools/gen_prototype_assets.py` (pure-stdlib PNG writer; the runtime never depends on it).
  They are PROTOTYPE art — a real art pass replaces them later.
- No screenshot/Pinterest/mirror/unknown-license/AI-of-unclear-rights asset ever enters the
  project (`.kiro/steering/06-art-assets.md`). A verified CC0 base (e.g. an OpenGameArt
  "character base") may be adopted later ONLY from its official source with the license
  recorded, and only after it is normalized to this bible (density, anchor, palette) — never
  mixed in raw.

## 9. The one-sentence test

> Drop a new character next to the existing four: if it looks like it belongs in the same
> game (same density, same anchor, same ink, one accent), it passes. If it looks pasted in
> from another pack, it fails — fix the art, not the engine.
