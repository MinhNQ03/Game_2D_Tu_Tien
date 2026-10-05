extends RefCounted
class_name UIPalette
## UIPalette — Aetheria presentation (UI design tokens).
##
## The SINGLE SOURCE OF TRUTH for the foundation UI's colors, font sizes, and spacing
## (`08-ai-review-protocol.md` no-duplication; `04-coding-standards.md` no magic numbers).
## The main menu, HUD, and `UITheme` builder all read these tokens instead of each hard-coding
## their own hex/sizes, so a later real art pass restyles the whole UI by editing ONE file.
##
## This is a prototype/foundation palette (NOT final art), chosen for legibility of both
## Vietnamese diacritics and English in the two first-class languages (`07-localization.md`).
## It carries NO behavior — just named constants.

# --- Palette (ink-and-jade tu-tiên tone) -------------------------------------

## App background (behind the menu).
const COLOR_BACKGROUND := Color(0.07, 0.08, 0.10)

## The DEEP night-blue ground of the Aetheria visual direction (D-041). The reference art is
## not neutral black — it is a cold ink-blue, which is what makes the antique gold read as
## warm. Used as the menu backdrop base; `COLOR_BACKGROUND` stays the neutral app fill.
const COLOR_BACKGROUND_DEEP := Color(0.035, 0.047, 0.086)

## The upper band of the menu backdrop gradient — a slightly lifted blue so the composition
## has a horizon rather than a flat void (D-041 fixes "panel floating on black").
const COLOR_BACKDROP_HIGH := Color(0.075, 0.098, 0.165)

## The lower band of the menu backdrop gradient (sinks back toward the deep ground).
const COLOR_BACKDROP_LOW := Color(0.020, 0.028, 0.055)

## Vignette ink drawn at the screen edges to focus the eye on the menu. Alpha-only; it must
## stay subtle or it reads as a dirty screen.
const COLOR_VIGNETTE := Color(0.0, 0.0, 0.0, 0.55)

## Ornamental accent tint for the decorative corner pieces — antique gold at low alpha, so
## the ornaments frame the screen without competing with the title.
const COLOR_ORNAMENT := Color(0.84, 0.72, 0.42, 0.33)

## Crimson/rose — DANGER and the exit action (D-041). The one warm-cold counterpoint to jade
## in the reference. Reserved: it must never be used for ordinary emphasis, or it stops
## meaning "careful".
const COLOR_CRIMSON := Color(0.72, 0.26, 0.30)

## Crimson at hover strength.
const COLOR_CRIMSON_HOVER := Color(0.82, 0.34, 0.38)

## Panel/surface fill (menu button face, HUD plate).
const COLOR_SURFACE := Color(0.13, 0.15, 0.18)

## Surface when hovered/active.
const COLOR_SURFACE_HOVER := Color(0.19, 0.22, 0.26)

## Surface when pressed.
const COLOR_SURFACE_PRESSED := Color(0.10, 0.12, 0.14)

## Disabled surface (Load Game placeholder).
const COLOR_SURFACE_DISABLED := Color(0.11, 0.12, 0.13)

## Accent (focus ring, title underline, key-badge border) — a jade/qì green.
const COLOR_ACCENT := Color(0.36, 0.78, 0.62)

## Title treatment — a muted antique gold (tu-tiên seal/plaque tone). Warmer than the jade
## accent and clearly above body text in hierarchy; restrained, not a bright yellow (D-030).
const COLOR_TITLE := Color(0.84, 0.72, 0.42)

## Primary readable text.
const COLOR_TEXT := Color(0.92, 0.94, 0.96)

## Muted/secondary text (subtitles, hints).
const COLOR_TEXT_MUTED := Color(0.62, 0.66, 0.72)

## Disabled text.
const COLOR_TEXT_DISABLED := Color(0.42, 0.45, 0.49)

## Key-badge background (the little "E"/"Esc" chip in a hint).
const COLOR_BADGE := Color(0.17, 0.20, 0.24)

## Key-badge border (jade keycap edge).
const COLOR_BADGE_BORDER := Color(0.36, 0.78, 0.62, 0.85)

## Text outline (D-034). Every text token above is LIGHT, so a dark stroke keeps labels
## legible even where they sit over busy map art or a lighter surface. Cheap: it is a font
## property, not an extra node or draw pass.
const COLOR_TEXT_OUTLINE := Color(0.03, 0.04, 0.05, 0.9)

## Outline stroke width in px. Godot grows the glyph outline outwards by this amount, so
## keep it small - 3-4 reads as a clean 1px pixel-art stroke at our body/hint sizes.
const TEXT_OUTLINE_SIZE := 4


# --- Type scale --------------------------------------------------------------

# Type scale (D-030 polish): a clearer three-step hierarchy — a large plaque title, a
# distinct subtitle step above body, then body/hint. title > body stays invariant (tested).
const FONT_SIZE_TITLE := 48
const FONT_SIZE_SUBTITLE := 20
const FONT_SIZE_BUTTON := 22
const FONT_SIZE_BODY := 16
const FONT_SIZE_HINT := 14
const FONT_SIZE_BADGE := 14


# --- Spacing / shape ---------------------------------------------------------

const SPACE_SM := 6
const SPACE_MD := 12
const SPACE_LG := 24
const SPACE_XL := 40


# --- Layout tokens (D-041) ---------------------------------------------------
#
# Named once here instead of repeated as literals across screens. Before D-041 the menu
# panel width (360), button width (300) and HUD margins lived as magic numbers inside the
# screens, so "make the menu wider" meant hunting literals in three files
# (`04-coding-standards.md` no magic numbers).

## Menu plaque width. Wide enough for the longest localized button label plus the 9-slice
## border band on both sides, at either language.
const MENU_PANEL_WIDTH := 420

## Menu action button width inside the plaque (panel width minus the inset border + gutter).
const MENU_BUTTON_WIDTH := 332

## Uniform action-button height, so the menu column reads as one engraved stack rather than
## buttons of slightly different sizes.
##
## 64, not 48: the painted plate is 245x90 (D-044), and 332x64 keeps the drawn aspect close
## enough to the authored one that the flat centre absorbs the resize invisibly. At 48 the
## vertical 9-slice bands (14+14) would eat too much of the box and the plate would read as
## squashed.
const BUTTON_HEIGHT := 64

## Gap between the title treatment and the action column.
const TITLE_GAP := 18

## Gap between major sections inside a panel (e.g. identity → status → values).
const SECTION_GAP := 14

## Gap between value rows within one section.
const ROW_GAP := 4

## Inner gutter between a panel's frame and its content, on top of the 9-slice border.
const PANEL_GUTTER := 10

## Screen-edge margin for HUD anchors, so nothing touches the viewport edge at any
## resolution (A15 — the UI must not be authored around one screenshot size).
const HUD_MARGIN := 18

## Width of a HUD side panel (sect / politics). A FIXED width, not a floor: these panels are
## bounded boxes on the screen edges, and a content-driven width would make the two sides
## disagree and jump as content changes.
const SIDE_PANEL_WIDTH := 330

## Height of the bottom strip RESERVED for the control prompts. No side panel may enter it.
##
## This is a layout CONTRACT, not padding. The faction panel used to be sized by its content
## and anchored from the centre, so with three factions it grew taller than the screen, pushed
## its own 9-slice frame off both edges (which is why it rendered with no visible plate) and
## buried the prompt row in the bottom-left corner. A reserved strip plus screen-anchored
## panel bounds (see `GameplayHUD`) makes that impossible by construction rather than by
## hoping content stays short.
const PROMPT_STRIP_RESERVE := 78

## Side of the decorative corner ornaments in the menu composition.
const ORNAMENT_PX := 56

## Portrait slot side in the HUD identity plaque.
const IDENTITY_PORTRAIT_PX := 56

## Minimum width of the HUD map-name plaque. A FLOOR, not a fixed width: it stops the plaque
## from shrink-wrapping a two-letter map name (which read as a stray chip) and from resizing
## every time the player walks into a map with a longer name, while still growing for a long
## localized name (+40% vi/en budget, `docs/UI_UX_BIBLE.md`).
const HUD_MAP_PANEL_WIDTH := 220

## Button inner padding (horizontal, vertical). Vertical nudged up (D-030) so a 22px button
## label sits with even breathing room top/bottom instead of feeling cramped.
const BUTTON_PAD_H := 28
const BUTTON_PAD_V := 12

## Corner radius for surfaces/badges (used by the fallback flat styleboxes only).
const CORNER_RADIUS := 6

## Focus ring thickness (fallback flat focus box only).
const FOCUS_BORDER := 2


# --- UI asset textures (Xianxia Pixel Pack, CC0, D-028) -----------------------
# The 9-slice panel/button/frame PNGs from the CC0 "Xianxia Pixel Pack" UI set (jade/ink/
# silk/rosewood), recorded in `docs/ASSET_LICENSES.md`. The single source of truth for WHERE
# the UI textures live, so `UITheme` + components load one name and a later art pass swaps the
# files (or the whole folder) without touching call sites. These replaced the earlier
# self-made prototype UI (`assets/ui/mana_soul/`, retired in D-028).
# All are pixel art: nearest filter, mipmaps off (`06-art-assets.md`).

const UI_ASSET_DIR := "res://assets/ui/xianxia"

# --- Kenney Fantasy UI Borders (CC0) — the ORNAMENT family (D-050) ----------
#
# Promoted from the reference pack after the AUDIT in `tools/measure_ui_assets.py --audit`.
# Exactly three textures were promoted, not the pack (B3: no source-pack dumping).
#
# WHY THESE AND NOT THE PACK'S PANELS: every file in this family measured as a **MASK** —
# 1-bit monochrome, pure white, 18-41% coverage. That is the most valuable property in the
# whole audit. A monochrome mask is TINTABLE, so ONE texture becomes antique gold, jade or
# crimson by `modulate` alone, which means a semantic colour change is a `UIPalette` edit
# rather than new art for every state (the B8 asset-replacement test). A pre-coloured frame
# could not do that.
#
# They are ORNAMENT, never a text surface: `frame_ornate` has centre alpha 0 (there is no fill
# to put text on), so a framed panel is still the dark `panel_inset` well with this drawn
# AROUND it. Pairing a frame with the well instead of replacing the well is what keeps the
# measured legibility of the inset (centre brightness 15 — the best text surface in the repo).
const ORNAMENT_DIR := "res://assets/ui/kenney_borders"

## 192x20 monochrome rule, 41% coverage, no border band — the ornamental divider. Replaces the
## stretched jade `title_divider.png`, which rendered as a flat saturated bar and read as a
## PROGRESS BAR under the menu subtitle and in every panel header (found by looking at a real
## capture, D-050; no assertion could have seen it).
const TEX_ORNAMENT_DIVIDER := ORNAMENT_DIR + "/divider_rule.png"

## 192x28 monochrome rule whose ends fade — for a divider that must not collide with a frame.
const TEX_ORNAMENT_DIVIDER_FADE := ORNAMENT_DIR + "/divider_fade.png"

## 96x96 monochrome frame, centre alpha 0, measured border band 8px — the ornate 9-slice
## frame drawn around a dark well.
const TEX_ORNAMENT_FRAME := ORNAMENT_DIR + "/frame_ornate.png"

## 9-slice margin for `TEX_ORNAMENT_FRAME`. The border band MEASURED 8px at 96x96; the patch
## margin must be >= it or the corners stretch (`06-art-assets.md`).
const ORNAMENT_FRAME_MARGIN := 8

## Height the ornamental divider is drawn at.
##
## The source is 20px tall, so this is an EXACT 0.5 downscale. That is deliberate and it is
## the rule rather than a preference: `06-art-assets.md` requires integer-friendly scaling for
## pixel UI, and the first version of this constant was 12 — a 0.6 scale, which resamples a
## 1-bit mask onto a fractional grid and softens the very edges the mask exists to keep sharp.
## It shipped in the same commit that cited the rule. Keep this a clean 1/1 or 1/2 of 20.
const ORNAMENT_DIVIDER_HEIGHT := 10


# --- B6 SEMANTIC TOKEN ALIASES (D-050) --------------------------------------
#
# The names `docs/UI_UX_BIBLE.md` and the D-050 brief use, bound to the colours this palette
# already defines. They are ALIASES, deliberately — introducing a second set of colour values
# would create exactly the two-sources-of-truth problem this file exists to prevent. What they
# add is a vocabulary a screen can read semantically ("this is danger") instead of
# descriptively ("this is crimson"), so a future accent change is one edit here.

## Deep ink ground — the darkest surface in the language.
const INK_DEEP := COLOR_BACKGROUND_DEEP
## The standard text-bearing surface (measured brightness 15 via `panel_inset.png`).
const INK_SURFACE := COLOR_SURFACE
## A lifted surface, for a row that must read as selected/active.
const INK_SURFACE_ALT := COLOR_SURFACE_HOVER
## Antique gold — STRUCTURE and ornament: frames, dividers, titles. Never body text.
const GOLD_PRIMARY := COLOR_TITLE
## Gold at low alpha — ornament that must frame without competing.
const GOLD_SECONDARY := COLOR_ORNAMENT
## Jade — INTERACTION and positive action.
const JADE_ACCENT := COLOR_ACCENT
## Cyan-leaning interaction, for a focused/hovered interactive edge.
const CYAN_INTERACTION := COLOR_BADGE_BORDER
## Crimson — DANGER and destructive/exit actions ONLY. Never decoration.
const CRIMSON_DANGER := COLOR_CRIMSON
const TEXT_PRIMARY := COLOR_TEXT
const TEXT_SECONDARY := COLOR_TEXT_MUTED
const TEXT_MUTED := COLOR_TEXT_DISABLED
const FOCUS := COLOR_ACCENT
const DISABLED := COLOR_SURFACE_DISABLED


## Vertical strip at the TOP of the screen that the identity and map/world plaques own. A
## full-height side panel must start below it, or it covers them — which is what the sect
## panel did (found in a real capture, D-050). Reserving it in a named constant makes "a side
## panel must not cover a plaque" arithmetic rather than something to notice in a screenshot,
## exactly as `PROMPT_STRIP_RESERVE` does for the bottom prompt row.
##
## MEASURED on a POPULATED HUD: the identity plaque is **194** tall (portrait row, name,
## title, health gauge, divider, affiliation tier) and the map plaque **154**, so the strip is
## the tallest, 194, plus one `HUD_MARGIN` of breathing room for the frame's corner ornaments
## (which are drawn OUTSIDE the control's rect) = **212**.
##
## FOUR wrong values preceded it, and the pattern in them is the useful part — three of the
## four were wrong because something in a plaque was INVISIBLE at the moment of measurement:
##   * **104** — taken from the map plaque alone, so the left-hand politics panel covered the
##     identity plaque's affiliation tier by ~52px.
##   * **174** — measured on a BARE HUD. A hidden child contributes nothing to a container's
##     minimum size, and both plaques hide content until a view arrives (the affiliation tier
##     until a sect view, the world-time lines until a world-sim view).
##   * **198** — measured on a populated HUD, but Phase 09's health gauge is itself hidden
##     until a health value arrives, so it too measured as zero. The same trap, one phase later
##     and with the warning already written in the test.
##   * The first two were asserted only as "> 0" and "the HUD mentions the token", which is
##     why neither was caught by a test at all.
##
## The value is pinned by
## `test_the_reserved_top_strip_is_tall_enough_for_the_plaques_it_reserves_for`, which fills
## EVERY plaque through the HUD's public setters — including a health value, and the LONGEST
## localized world-event string derived from the authored set — before measuring. Adding a
## tier to a plaque now fails there instead of quietly reintroducing the overlap.
const TOP_PLAQUE_RESERVE := 212


## Lines the HUD's world-event hint may wrap to before it trims. The cap is what makes the
## map plaque's height BOUNDED — the event line is the only thing in a top plaque sized by a
## sentence, and an unbounded plaque makes `TOP_PLAQUE_RESERVE` above unknowable. Two lines
## absorbs the +40% vi↔en growth `docs/UI_UX_BIBLE.md` requires.
const HUD_WORLD_EVENT_MAX_LINES := 2

const TEX_PANEL := UI_ASSET_DIR + "/panels/panel.png"
const TEX_PANEL_INSET := UI_ASSET_DIR + "/panels/panel_inset.png"
const TEX_BUTTON_NORMAL := UI_ASSET_DIR + "/buttons/button_normal.png"
const TEX_BUTTON_HOVER := UI_ASSET_DIR + "/buttons/button_hover.png"
const TEX_BUTTON_PRESSED := UI_ASSET_DIR + "/buttons/button_pressed.png"
const TEX_BUTTON_DISABLED := UI_ASSET_DIR + "/buttons/button_disabled.png"
const TEX_BUTTON_FOCUS := UI_ASSET_DIR + "/buttons/button_focus.png"
const TEX_KEY_BADGE := UI_ASSET_DIR + "/frames/key_badge.png"
const TEX_PORTRAIT_FRAME := UI_ASSET_DIR + "/frames/portrait_frame.png"

# RETIRED (D-050): `frames/title_divider.png`. It had a constant here until every divider
# moved to `UITheme.ornament_divider()` + `TEX_ORNAMENT_DIVIDER`. The constant is GONE rather
# than kept-but-unused on purpose: a named path is an invitation, and the bug it caused
# (a jade fill stretched to panel width, reading as a progress bar) is exactly the kind a
# future screen would re-create by reaching for the nearest divider-shaped constant. The PNG
# stays in the pack and in `docs/ASSET_LICENSES.md` (U10) as an unwired pack file.

# --- PAINTED UI tier (Aetheria pack, project-owned, D-044) -------------------
#
# A SECOND, deliberately different asset class from the pixel-art xianxia set above, and the
# rules for it are different — so it lives in its own folder and its own constants rather than
# being mixed into `UI_ASSET_DIR`.
#
# These are painted (self-generated, project-owned — `docs/ASSET_LICENSES.md`), not pixel art.
# Consequences, which are the whole reason this is a separate tier:
#   * They are drawn with **LINEAR** filtering, not nearest. Nearest on a soft painted gradient
#     and on fine gold filigree produces stair-stepping; the "integer scale / nearest only"
#     rule in `06-art-assets.md` exists to protect PIXEL art and does not apply here.
#   * Non-integer stretching is acceptable for the same reason — there is no pixel grid to
#     break. The 9-slice margins below still protect the ornate ENDS from being distorted.
# The pixel-art world/sprite rules are untouched: this tier is UI-only.

const PAINTED_UI_DIR := "res://assets/ui/aetheria"

## The painted button plate. MEASURED: 245x90, centre brightness 29 (DARK) — which is why it
## can legally carry this project's light-only text palette, unlike the xianxia
## `button_normal.png` at 202 (see SURFACE_LIGHT_BRIGHTNESS_LIMIT below).
const TEX_BUTTON_PAINTED := PAINTED_UI_DIR + "/buttons/button_jade.png"

## A violet variant of the same plate, for a role that must read as clearly apart.
const TEX_BUTTON_PAINTED_ALT := PAINTED_UI_DIR + "/buttons/button_violet.png"

# --- VITALS GAUGE (Phase 09) ------------------------------------------------
#
# The first gauge in the game, and it only exists now because combat finally owns the value
# it shows. `docs/UI_UX_BIBLE.md` forbids rendering a gauge for state no system owns: a bar
# that looks right in a mock and shows nothing real in a build is worse than an absent one.

## Height of a vitals gauge. Thin enough to read as a readout rather than as a panel, and an
## even number so the 9-slice well's border bands stay symmetrical.
const GAUGE_HEIGHT := 14

## Fill colour for a healthy gauge. An ALIAS of the jade accent, not a new colour value —
## one more colour token would be a second source of truth for the same decision (D-050 B6).
const GAUGE_FILL := COLOR_ACCENT

## Fill colour once the gauge crosses `GAUGE_LOW_FRACTION`. Crimson is reserved for
## "leaving or destroying", and losing the last of your health qualifies.
const GAUGE_FILL_LOW := COLOR_CRIMSON_HOVER

## Fraction at or below which a gauge reads as critical. A quarter, so the warning arrives
## while the player can still act on it.
const GAUGE_LOW_FRACTION := 0.25

## Seconds the combat-target plaque stays up after the target dies (Phase 10).
##
## Long enough to read the name of what you just killed — the information is most wanted at
## exactly the moment it would otherwise vanish — and short enough that the HUD is not still
## advertising a corpse once the fight is over.
const TARGET_PLAQUE_LINGER := 2.5

## Tint an entity's sprite is multiplied by at the instant it takes damage (Phase 10).
##
## `modulate` is a MULTIPLY, so a channel above 1.0 brightens. That is deliberate and is why
## these are not plain palette colours: a tint built only from values <= 1 darkens the sprite,
## which reads clearly on the player's pale robe and almost not at all on a dark creature. The
## red channel is pushed past 1 so the flash is visible on BOTH, while the cut green and blue
## keep the crimson hue.
##
## The hue is `CRIMSON_DANGER` (0.72, 0.26, 0.30) at a gain of 3.0, written out as a literal
## because a const expression cannot read a component off another const colour. Change the
## crimson and this must be recomputed — the ratio is the thing to preserve, not the numbers.
const HIT_FLASH_TINT := Color(2.16, 0.78, 0.90)

## The same idea for a CRITICAL hit, in gold instead of crimson: `GOLD_PRIMARY`
## (0.84, 0.72, 0.42) at the same gain of 3.0. A crit already exists in shipped content (15%
## on the player's basic attack, 10% on the wolf's bite), so this is a tint real play reaches,
## not a hypothetical — and `HurtboxComponent.damaged` carries `is_critical` precisely so
## presentation can tell them apart without recomputing anything.
const HIT_FLASH_TINT_CRITICAL := Color(2.52, 2.16, 1.26)

## How long a hit flash takes to decay back to the sprite's resting colour, in seconds.
## Short: long enough to register at 60fps, short enough that two quick hits read as two hits
## rather than as one long smear. A crit holds slightly longer because it is the rarer, more
## important event.
const HIT_FLASH_SECONDS := 0.16
const HIT_FLASH_SECONDS_CRITICAL := 0.28

## Tint a dead entity's sprite keeps, marking it as a corpse rather than a live threat.
##
## It lives HERE rather than as a `Color(...)` literal in `Enemy._on_health_died()`, which is
## where it shipped: a presentation decision hard-coded in a gameplay entity is a colour no
## palette edit can reach, and the same literal had already been copied into two tests.
##
## MEASURED, not guessed. The first value — `Color(0.55, 0.55, 0.62, 0.75)` — multiplied the
## pale wolf (luminance ~0.80) down to ~0.44 and then blended a quarter of the dark grass
## (~0.25) through it, landing at ~0.36 against a ~0.25 background. Magnified it was plainly a
## wolf; at 1:1 in the playtest capture it was a dark smudge, so a kill read as a despawn while
## the HUD plaque was still naming the thing. Dimming alone cannot carry this on a dark map.
##
## So the corpse is marked by TWO signals, not one, which is also the UI bible's rule that
## colour is never the only carrier: it is DIMMER than a living entity (so it recedes) and it
## is BLUE-SHIFTED and translucent (so it reads as drained rather than as shadow). Blue is
## 0.18 above red, which survives against this map's green.
const CORPSE_TINT := Color(0.62, 0.66, 0.80, 0.80)

## Width reserved on the right of a scrolling panel so its vertical scrollbar never sits on
## the content. Godot draws the scrollbar OVER a `ScrollContainer`'s child rather than taking
## layout space from it, so without this a right-aligned value column runs underneath it and
## the last character of every number is obscured — which is how both HUD side panels
## shipped. Consumed once, by `UITheme.scroll_body()`.
const SCROLLBAR_GUTTER := 14

## Flat dead margin down the LEFT edge of the painted backdrop, in source pixels.
##
## MEASURED, per column, over the full height: columns 0-20 have a luminance range of <= 5
## levels (uniform fill, mean 21.6), column 21 is the first with real variation, and the
## painting's cliffs are fully present from column 22. Scaled to cover a 1280x720 screen
## those columns become ~87px of flat near-black down the left side, which reads as the
## backdrop having failed to load rather than as art.
##
## `UITheme.menu_backdrop()` crops it. Fixing it in the THEME rather than by re-exporting the
## PNG keeps the asset byte-identical to the file recorded in `docs/ASSET_LICENSES.md`, and
## "flat dead margin" is a property of the art that is worth stating in code where the next
## person can see the number.
const MENU_BACKDROP_DEAD_LEFT_PX := 21

## The painted menu backdrop: cloud peaks over a dark navy ground. MEASURED 310x330, and its
## own background navy is deliberately close to COLOR_BACKGROUND_DEEP so the scene can sit
## CENTRED over that fill with no visible seam — which is what lets it be shown at a modest
## ~1.9x upscale instead of being stretched 4x+ to cover a full screen and going soft.
const TEX_MENU_BACKDROP := PAINTED_UI_DIR + "/backdrop/cloud_peaks.png"

## Painted character portraits for the HUD identity plaque (310x560 / 300x560 standing
## figures — an `AtlasTexture` crops the head region, see `UITheme.portrait_texture`).
const PORTRAIT_DIR := "res://assets/sprites/characters/portraits"
const TEX_PORTRAIT_MALE := PORTRAIT_DIR + "/cultivator_male.png"
const TEX_PORTRAIT_FEMALE := PORTRAIT_DIR + "/cultivator_female.png"

## 9-slice border of the painted button plate: the gold corner filigree runs ~44px in from
## each side and the gold frame sits ~14px from the top/bottom. Those bands are NOT stretched,
## so the ornaments stay intact while the flat centre absorbs the resize.
const PAINTED_BUTTON_MARGIN_H := 44
const PAINTED_BUTTON_MARGIN_V := 14

## Text inset for the painted button. Wider than the 9-slice margin (the project's
## `content_margin >= texture_margin` rule) AND wide enough to clear the qi-swirl emblem on
## the left and the cloud motif on the right, so a label never collides with the artwork.
const PAINTED_BUTTON_PAD_H := 62
const PAINTED_BUTTON_PAD_V := 14

## Fraction of the screen height the painted backdrop scene occupies, centred. Keeps the
## upscale modest; the surrounding fill is the same navy as the art's own ground.
const MENU_BACKDROP_HEIGHT_RATIO := 0.88

## Side of the head crop taken from a standing portrait, as a fraction of its width. The
## figures are framed head-to-knee, so the top square of the image is head + shoulders.
const PORTRAIT_HEAD_CROP_RATIO := 1.0


## Every runtime UI texture (for the asset-contract test — all must exist + be tracked).
const UI_TEXTURES := [
	TEX_PANEL, TEX_PANEL_INSET,
	TEX_BUTTON_NORMAL, TEX_BUTTON_HOVER, TEX_BUTTON_PRESSED, TEX_BUTTON_DISABLED,
	TEX_BUTTON_FOCUS, TEX_KEY_BADGE, TEX_PORTRAIT_FRAME,
	TEX_BUTTON_PAINTED, TEX_BUTTON_PAINTED_ALT, TEX_MENU_BACKDROP,
	TEX_PORTRAIT_MALE, TEX_PORTRAIT_FEMALE,
]

## 9-slice border margins (px) authored into each xianxia texture (D-028). The border band of
## each PNG is NOT stretched; only the center is — pixel corners stay crisp at any size
## (`06-art-assets.md`, nine-slice rule). Margins differ per source texture, so they are
## declared per slot (read from each pack `.tres`): panels jade = 17; ink inset = 26/19;
## jade/silk buttons = L16 T14 R16 B18; the corner used as the key badge = 18.
const PANEL_MARGIN := 17            # panel.png (jade, 218x118)
const INSET_MARGIN := 24            # panel_inset.png (ink, 216x117 - authored 26/19, 24 safe)
const BUTTON_MARGIN := 16           # button_* (jade/silk, 130x54, border 16)
const KEY_BADGE_MARGIN := 18        # key_badge.png (corner ornament, 61x61) - see note below
const PORTRAIT_MARGIN := 17         # portrait_frame.png (rosewood panel, 218x118)

# --- MEASURED asset facts (D-034) --------------------------------------------
# Taken from the actual PNGs, not estimated, because two of them were being used for the
# wrong job and that is what made the Phase-06 HUD unreadable:
#   panel.png        218x118  centre brightness 230  -> a LIGHT surface
#   panel_inset.png  216x117  centre brightness  19  -> a DARK surface
#   button_normal    130x54   centre brightness 193  -> light
#   portrait_frame   218x118  centre brightness 229  -> a light PANEL, not a small frame
#   key_badge.png    61x61    centre ALPHA 0         -> hollow corner ornament, NOT a keycap
#   title_divider    136x21   centre brightness 120  -> a jade FILL (retired D-050; a fill
#                                                       stretched to panel width reads as a
#                                                       progress bar, not as a rule)
# Consequences, enforced by `UITheme`:
#   * Every text token in this file is LIGHT, so a surface that carries text must be DARK ->
#     `panel_stylebox()` uses the INSET (dark) texture. Light `panel.png` behind light text
#     is what produced "white text on a white plate".
#   * `key_badge.png` has a transparent centre, so it cannot back a key glyph; the keycap is
#     drawn as a deliberate flat chip instead (see `UITheme.badge_stylebox`).
#   * A 218x118 texture cannot be a 40x40 portrait slot; a `TextureRect` left at its default
#     `expand_mode` reports the full texture size as its minimum and blows the layout apart.

## Surface brightness (0-255) above which light text stops being readable, so the surface
## must NOT be used behind the light text tokens. Asserted by the UI theme test.
const SURFACE_LIGHT_BRIGHTNESS_LIMIT := 120

## Kept for backward compatibility / the default `_texture_box` margin (panels/portrait).
const NINE_PATCH_MARGIN := 17
