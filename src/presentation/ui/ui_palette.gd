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
const COLOR_ORNAMENT := Color(0.84, 0.72, 0.42, 0.62)

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
## 64, not 48: the painted plate (D-044) needs the height for its emblem to read, and since
## the D-056 UI pass the plate SHIPS at exactly 64px tall (`tools/repair_button_plate.py
## --height`), so at this height nothing is stretched vertically at all. Change the two
## together, or the emblem in the side band is squashed again.
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

## The dialogue box (Phase 18): one bounded box at the bottom centre. Wide enough for a
## three-line sentence beside the medallion and the answers; `DIALOGUE_LINE_MIN_HEIGHT` holds
## two lines of `FONT_SIZE_BODY` (the longest shipped line, in either language, wraps to two)
## so the box does not change height from line to line.
const DIALOGUE_BOX_WIDTH := 860
const DIALOGUE_CHOICE_WIDTH := 250
const DIALOGUE_LINE_MIN_HEIGHT := 46
## How far above the dialogue box the announcement band sits while a conversation is open.
const DIALOGUE_NOTICE_GAP := 8

## Height of the bottom strip RESERVED for the control prompts. No side panel may enter it.
##
## This is a layout CONTRACT, not padding. The faction panel used to be sized by its content
## and anchored from the centre, so with three factions it grew taller than the screen, pushed
## its own 9-slice frame off both edges (which is why it rendered with no visible plate) and
## buried the prompt row in the bottom-left corner. A reserved strip plus screen-anchored
## panel bounds (see `GameplayHUD`) makes that impossible by construction rather than by
## hoping content stays short.
##
## **MEASURED, 78 -> 54 (D-057).** Derived the same way as `TOP_PLAQUE_RESERVE`: the populated
## strip's height (all five prompts, in vi, the longer language) plus one `HUD_MARGIN` of
## breathing room. Moving the prompts from a framed plaque (68px) onto the quiet hint band
## (36px) made the old value 32px of DEAD playfield — reserved for nothing, keeping the side
## panels and the level-up banner higher than anything required. A reserve far larger than
## what it protects is as wrong as one that is too small, so the measuring test now bounds it
## from ABOVE as well.
const PROMPT_STRIP_RESERVE := 54

## Opacity of the HINT BAND the control prompts sit on (D-057 — the HUD weight ladder).
##
## The prompts are passive, peripheral information: a player reads them a handful of times and
## then knows the keys. They used to sit in the same ornate framed plaque as the identity and
## the place name, which gave a row of key hints the visual weight of the things the player
## actually tracks — and spent the ornament that is supposed to MEAN importance on the least
## important text on screen. They now sit on a flat translucent band with no frame.
##
## The value is a LEGIBILITY bound, not a taste. The prompt text is the light-only palette, so
## whatever shows through the band must still measure as a dark surface. Composited over PURE
## WHITE — the worst background anything could put behind it — this band stays under
## `SURFACE_LIGHT_BRIGHTNESS_LIMIT`, which makes it legal over every floor, prop and sprite the
## game has or will have, rather than over the floors somebody happened to test.
## `test_the_hint_band_is_a_legal_text_surface_over_any_background` re-derives that.
const HINT_BAND_ALPHA := 0.65

## The band's fill: the deepest ink in the palette, at `HINT_BAND_ALPHA`. An ALIAS of the
## background token, not a new colour value (the D-050 B6 rule).
const HINT_BAND_COLOR := Color(COLOR_BACKGROUND_DEEP, HINT_BAND_ALPHA)

## The share of the viewport the PERMANENT HUD may cover (D-057 — negative space).
##
## A budget, like a frame-time budget: it does not say the HUD is good, it says the HUD cannot
## quietly grow over the game. MEASURED at D-057 on a populated HUD in vi, the longer language:
## identity 282x224 + map 268x177 + prompt band 585x36 = **14.3%** of the authored 1280x720
## viewport (12.9% at 1280x800), down from **16.5%** before the prompts left their framed
## plaque. The headroom to 15% is about one more plaque row: the next permanent element has to
## be argued for (`UI_UX_BIBLE.md` §3c — every permanent element earns its space)
## rather than slipped in. Contextual surfaces (the combat target, an open side panel, the
## level-up banner) are not permanent and are governed by `PLAYFIELD_CLEAR_ZONE` instead.
const HUD_PERMANENT_AREA_BUDGET := 0.15

## The playfield centre NO HUD element may enter, as fractions of the viewport
## (x, y, width, height) — permanent or contextual (D-057 — protect the combat space).
##
## The camera follows the player, so the middle of the screen is where the character, what it
## is fighting and the effects between them actually are. The side panels are excluded by
## design: the player opens them on purpose, as a modal-weight decision to read instead of play.
const PLAYFIELD_CLEAR_ZONE := Rect2(0.25, 0.25, 0.5, 0.5)

## Side of the decorative corner ornaments in the menu composition.
const ORNAMENT_PX := 56

## Portrait slot side in the HUD identity plaque: the medallion, drawn at 1x (D-062).
const IDENTITY_PORTRAIT_PX := 96

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


# --- THE INK-LACQUER UI KIT (D-062) ---------------------------------------------
#
# The live UI foundation, and ORIGINAL Aetheria art: every texture below is generated by
# `tools/aetheria_art_pipeline/ui/ui_kit.py` from the Visual DNA
# (`tools/aetheria_art_pipeline/style/aetheria_style.yaml` §1 palette roles, §8 UI grammar) —
# dark ink-lacquer with a brushed grain and a one-pixel bevel, an antique-gold hairline set 3px
# inside the edge with NOTCHED corners, jade for interaction. It replaced BOTH earlier tiers
# (D-062 §7): the CC0 xianxia pixel pack (flat "plastic" plates) and the glossy painted plates
# (a mobile-MMO read). Neither was Aetheria; the kit is the DNA's UI sentence made literal, and
# a restyle is a re-run of the generator, never a new screen.
#
# All of it is PIXEL art: nearest filter, drawn at 1x, 9-sliced only across flat runs (a
# hairline or a gradient), so stretching can never distort an ornament.

const UI_ASSET_DIR := "res://assets/ui/aetheria_ink"

## THE text-bearing surface (64x64; 9-slice 14 on every side; centre MEASURED dark, see
## `test_text_panel_uses_the_dark_surface`). Identity, place, target, every side panel, menus.
const TEX_PLAQUE := UI_ASSET_DIR + "/plaque.png"
const PLAQUE_MARGIN := 14

## The QUIET band (96x40): no frame, a lacquer wash fading toward the playfield, a gold
## hairline above and below that fades with it. `_RIGHT` fades rightward (a strip anchored on
## the left edge), `_LEFT` leftward. 9-slice: the solid end 12px, the FADE 56px (never
## stretched, so the fade keeps its shape at any width), 6px top/bottom.
const TEX_BAND_RIGHT := UI_ASSET_DIR + "/band_right.png"
const TEX_BAND_LEFT := UI_ASSET_DIR + "/band_left.png"
const BAND_SOLID_MARGIN := 12
const BAND_FADE_MARGIN := 56
const BAND_V_MARGIN := 6

## The command plate, one DESIGNED texture per state (aetheria_style.yaml `ui.states`): normal
## (gold hairline at 72%), hover (lifted lacquer, full gold, a jade underline), focus (a jade
## inner ring + corner ticks drawn OVER the normal plate — visible with the keyboard alone),
## pressed (the plate sinks: inner shadow, gold in shadow), disabled (desaturated, grey line).
## 96x40; 9-slice 12 h / 10 v — the diamond knots at the hairline ends sit inside the h bands.
const TEX_BUTTON_NORMAL := UI_ASSET_DIR + "/button_normal.png"
const TEX_BUTTON_HOVER := UI_ASSET_DIR + "/button_hover.png"
const TEX_BUTTON_FOCUS := UI_ASSET_DIR + "/button_focus.png"
const TEX_BUTTON_PRESSED := UI_ASSET_DIR + "/button_pressed.png"
const TEX_BUTTON_DISABLED := UI_ASSET_DIR + "/button_disabled.png"
const BUTTON_SLICE_H := 12
const BUTTON_SLICE_V := 10

## The key badge: a raised lacquer keycap (lit face, dark lip) with a jade edge — the colour of
## interaction. 20x22; 9-slice 6 left/right/top, 8 bottom (the lip is never stretched).
const TEX_KEYCAP := UI_ASSET_DIR + "/keycap.png"
const KEYCAP_SLICE := 6
const KEYCAP_LIP := 8

## A meter: an inset ink WELL (24x12, slice 4) and a WHITE material mask the fill colour
## multiplies (12x12, slice 3) — a catch-light, a body, a darker base: liquid in a channel, not
## a flat bar and not a glow. The mask's 2px transparent rim keeps the well's edge visible.
const TEX_GAUGE_WELL := UI_ASSET_DIR + "/gauge_well.png"
const TEX_GAUGE_FILL := UI_ASSET_DIR + "/gauge_fill.png"
const GAUGE_WELL_SLICE := 4
const GAUGE_FILL_SLICE := 3

## Icon slots — skill, item and equipment are ONE family (aetheria_style.yaml §7): a darker
## lacquer well under a gold hairline; a technique's slot adds an inner ring in its element's
## hue. 40x40, drawn at 1x.
const TEX_SLOT := UI_ASSET_DIR + "/slot.png"
const SLOT_PX := 40
const TEX_SLOT_BY_ELEMENT := {
	&"elem_phong": UI_ASSET_DIR + "/slot_phong.png",
	&"elem_loi": UI_ASSET_DIR + "/slot_loi.png",
	&"elem_hoa": UI_ASSET_DIR + "/slot_hoa.png",
	&"elem_thuy": UI_ASSET_DIR + "/slot_thuy.png",
}

## WHITE masks the theme tints (one texture, any semantic colour): the divider (a 1px rule
## fading at both ends, a diamond knot at its centre; 96x7), the hollow frame (notched corners,
## centre alpha 0; 24x24, slice 8) and the full-screen corner fret (56x56).
const TEX_ORNAMENT_DIVIDER := UI_ASSET_DIR + "/divider.png"
const TEX_ORNAMENT_FRAME := UI_ASSET_DIR + "/frame_mask.png"
const TEX_CORNER_FRET := UI_ASSET_DIR + "/corner_fret.png"
const ORNAMENT_FRAME_MARGIN := 8

## Height the divider is drawn at: its own 7px, 1:1 (`06-art-assets.md` integer scaling).
const ORNAMENT_DIVIDER_HEIGHT := 7

## THE identity medallion: the actor's 80px pixel portrait (rendered by the art pipeline from
## the SAME model as the sprite, so face and figure can never disagree) clipped into a lacquer
## disc under an antique-gold ring. 96x96, shown at 1x.
const TEX_MEDALLION_PLAYER := UI_ASSET_DIR + "/medallion_player_proto.png"
const TEX_MEDALLION_FEMALE := UI_ASSET_DIR + "/medallion_cultivator_f_proto.png"
const MEDALLION_PX := IDENTITY_PORTRAIT_PX


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
## MEASURED on a POPULATED HUD: the identity plaque is **206** tall (portrait row with the
## name + level badge, title, health gauge, XP meter, divider, affiliation tier) and the map
## plaque **154**, so the strip is the tallest, 206, plus one `HUD_MARGIN` of breathing room
## for the frame's corner ornaments (which are drawn OUTSIDE the control's rect) = **224**.
##
## It was 212 until Phase 11 added the level/XP row, and the measuring test is what caught
## that — which is the fifth time this constant has moved and the fifth time the cause was
## content being added to a plaque. That is the intended workflow, not a failure: the number
## is not maintained by eye, it is re-derived by a test that fills every plaque through the
## public setters and fails with the measurement in its message.
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
##
## **224 -> 242 (D-056).** The sixth move, and the sixth time the cause was content growing
## inside a plaque: both meters went to the measured height of the label they print inside
## themselves (`GAUGE_HEIGHT` 14 -> 20, `XP_METER_HEIGHT` 8 -> 20), so the identity plaque grew
## 18px. Measured at the new value: identity plaque **224**, map plaque 177, plus one
## `HUD_MARGIN` of breathing room for the frame's corner ornaments (drawn OUTSIDE the control's
## rect) = **242**. That the number moved itself is the workflow working, not a failure.
##
## **D-062: unchanged.** The realm meter left the text column for a full-width row under the
## medallion row (the English realm line could not fit the column), and the title row it used
## to replace stays hidden while it shows, so the plaque still measures inside the reserve —
## re-checked by the same test, not by eye.
const TOP_PLAQUE_RESERVE := 242


## Lines the HUD's world-event hint may wrap to before it trims. The cap is what makes the
## map plaque's height BOUNDED — the event line is the only thing in a top plaque sized by a
## sentence, and an unbounded plaque makes `TOP_PLAQUE_RESERVE` above unknowable. Two lines
## absorbs the +40% vi↔en growth `docs/UI_UX_BIBLE.md` requires.
const HUD_WORLD_EVENT_MAX_LINES := 2

# --- VITALS GAUGE (Phase 09) ------------------------------------------------
#
# The first gauge in the game, and it only exists now because combat finally owns the value
# it shows. `docs/UI_UX_BIBLE.md` forbids rendering a gauge for state no system owns: a bar
# that looks right in a mock and shows nothing real in a build is worse than an absent one.

## Height of a meter that writes its value inside itself. Thin enough to read as a readout
## rather than as a panel, and an even number so the 9-slice well's border bands stay
## symmetrical.
##
## **MEASURED, not chosen (D-056).** It was 14, and a `FONT_SIZE_HINT` value label measures
## **20px** of combined minimum height — so both meters were drawing their own numbers across
## their own frames, the health gauge by 6px and the XP meter by 12px. The floor is now the
## label's real requirement, re-measured for every meter in the HUD by
## `test_every_meter_is_tall_enough_for_the_value_it_writes_inside_itself`, so a font-size
## change fails loudly instead of quietly clipping a number again.
const GAUGE_HEIGHT := 20

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

## THE STRIKE'S AIR (D-057B): the pale streaks a palm strike drives out of the striking hand.
## Near-white with a cool cast — moving AIR, not qi: a PHÀM body has no qi to show
## (`XIANXIA_IDENTITY_CONTRACT.md`), so the basic attack is drawn as force, and glow is kept
## for the realms that earn it.
const STRIKE_TRAIL := Color(0.93, 0.96, 0.95)

## The ground TELEGRAPH of a hostile swing's reach, drawn during its wind-up (D-057B): a warm
## warning red, because a telegraph exists to be read and learned once (`COMBAT_DESIGN.md` §7,
## M-6.4). The player's own swing draws none.
const TELEGRAPH_HOSTILE := Color(0.95, 0.42, 0.30)

## The contact flash where a blow lands (D-057B): near-white for a normal hit, gold for a
## critical — the same distinction the body's hit tint makes, so the two layers agree.
const IMPACT_FLASH := Color(1.0, 0.97, 0.88)
const IMPACT_FLASH_CRITICAL := Color(1.0, 0.86, 0.46)

## How long a hit flash takes to decay back to the sprite's resting colour, in seconds.
## Short: long enough to register at 60fps, short enough that two quick hits read as two hits
## rather than as one long smear. A crit holds slightly longer because it is the rarer, more
## important event.
const HIT_FLASH_SECONDS := 0.16
const HIT_FLASH_SECONDS_CRITICAL := 0.28


# --- PROGRESSION: level + XP (Phase 11) -------------------------------------
#
# The second meter in the game, and it had to be made UNMISTAKABLE from the first. The phase
# brief is explicit that XP must not be confused with HP, and the HUD puts them one above the
# other in the same plaque, so "a bar in the identity panel" could not be allowed to mean two
# things. Three properties separate them, and none of them is only colour:
#
#   * **Hue** — jade for vitals, GOLD for progression. That is not decoration, it is the
#     palette's own vocabulary: jade is interaction/vitality, gold is STRUCTURE and
#     achievement (the token comment on `GOLD_PRIMARY` already says frames, dividers, titles).
#     A tu-tiên plaque reading gold for attainment is also the right cultural register.
#   * **Weight** — the XP meter is thinner than the vitals gauge, so it reads as subordinate
#     information rather than as a second vital sign competing for the same attention.
#   * **Text** — the vitals gauge writes "18 / 60" (health now / health max); the XP meter
#     writes "20 / 45" against a LEVEL label, so the pair is read as progress-within-a-level.
#     `docs/UI_UX_BIBLE.md` §4 requires colour never to be the only carrier of meaning, and a
#     colour-blind player must still be able to tell these two apart — the thickness and the
#     adjacent level badge do that.

## Height of the XP meter. **The same as `GAUGE_HEIGHT` since D-056, and that is the fix.**
##
## It was 8 — deliberately below the vitals gauge so XP read as subordinate — and it could not
## contain its own number. A meter writes its value INSIDE itself, the label is
## `FONT_SIZE_HINT`, and a 14px label MEASURES 20px of combined minimum height: "KN 0 / 20"
## rendered with its descenders across the rail's bottom border. Found by opening a capture at
## 4x; invisible at 1x and invisible to every assertion, because the number was still *there*.
##
## So WEIGHT is retired as a carrier and the distinction rests on the two that survive
## measurement: **hue** (gold vs jade) and **text** ("KN 0 / 20" against a level badge vs
## "100 / 100"). `docs/UI_UX_BIBLE.md` §4 still holds — colour is not the only carrier, because
## the written value and the adjacent level badge carry it too. A third carrier that makes the
## number illegible is worse than two that do not.
##
## It stays a NAMED constant rather than becoming `GAUGE_HEIGHT` at the call site: the XP
## meter's height is its own decision that currently agrees, and collapsing them would hide
## the day they diverge again (for a good reason, with the label measured first).
const XP_METER_HEIGHT := GAUGE_HEIGHT

## Fill for the XP meter. An ALIAS of the gold token, not a new colour value: a second gold
## would be a second source of truth for one decision (the D-050 B6 rule).
const XP_METER_FILL := GOLD_PRIMARY

## Fill once the level is at the authored curve's ceiling — the jade "nothing left to earn"
## reading, so a maxed meter is visibly a different state from one that is merely nearly full.
const XP_METER_FILL_COMPLETE := COLOR_ACCENT

## The CULTIVATION (tu vi) meter (Phase 12): the second progression axis gets its own hue, a pale
## qi cyan — never the XP gold (the two axes must not read as one, §1 / D-054) and never the
## health jade (the plaque already stacks two bars). Its WRITTEN value names the realm, so the
## distinction does not rest on colour (`UI_UX_BIBLE.md` §4).
const CULTIVATION_METER_FILL := Color(0.52, 0.80, 0.92)
## A full step that can be broken through: the meter turns gold — attainment, the same token
## the level badge uses for "you earned this", because a breakthrough waiting IS one.
const CULTIVATION_METER_FILL_READY := GOLD_PRIMARY

## How long a transient HUD notice (knowledge learned, a refused cultivate) stays up, and how
## long the breakthrough announcement holds. A breakthrough is MACRO (M-4.7): it holds longer
## than the level-up banner, and it is bigger — but it still lives in the bottom band, never
## over the playfield centre (`UI_UX_BIBLE.md` §3c).
const HUD_NOTICE_SECONDS := 3.0
const BREAKTHROUGH_BANNER_SECONDS := 3.2
## The band is ONE slot (D-063): an interrupted notice, or the banner paused for an answer,
## comes back for what it had left — never less than this, so a resumed line can still be read.
const HUD_NOTICE_RESUME_MIN_SECONDS := 1.0
## A SAFETY GUARD, not a capacity: notices are never dropped. Real play queues a handful (two
## pickups and a stele's two lessons); a backlog past this means a producer is announcing in a
## loop, and the HUD reports it with `push_error` — loudly — while still keeping every notice.
const HUD_NOTICE_BACKLOG_GUARD := 32
## The breakthrough banner and the notice line sit one banner-row ABOVE the level-up banner, so
## a level-up landing during a breakthrough announcement can never print over it.
const ANNOUNCE_BOTTOM_INSET := LEVEL_UP_BANNER_BOTTOM_INSET + 34

## Minimum width of the level badge, so `Lv 1` and `Lv 20` do not resize the identity plaque
## as the player levels. A FLOOR, like `HUD_MAP_PANEL_WIDTH`.
const LEVEL_BADGE_MIN_WIDTH := 52

## How long the level-up celebration runs, in seconds.
##
## Long enough to be unmissable (the phase brief: a level-up must feel like an event, not a
## changed number), short enough that it never becomes something the player waits through —
## and it must not outlive a map transition, which is why the HUD's effect is cancellable and
## why this is under two seconds rather than a cinematic length.
const LEVEL_UP_SECONDS := 1.5

## How far above the BOTTOM edge the level-up announcement sits, in px.
##
## The announcement is a bottom-centre HUD element, and that is the second answer to this
## problem rather than the first. Anchoring it to the screen CENTRE printed it straight across
## the player's body, because the camera follows the player — and nudging it upwards from
## there did not fix it either: the camera is CLAMPED by the map limits, so the player's screen
## position moves, and any fixed offset from the centre only relocates the collision instead of
## removing it. Both versions were found by looking at a capture; neither was visible to a test.
##
## A band the HUD already owns is deterministic. This clears the prompt strip the prompts own
## and leaves one margin of air, so the announcement cannot collide with the player, with the
## prompts, or with a plaque — by arithmetic rather than by hoping.
const LEVEL_UP_BANNER_BOTTOM_INSET := PROMPT_STRIP_RESERVE + SPACE_LG

## Peak brightness multiplier of the level badge during the celebration.
##
## `modulate` is a MULTIPLY, so a channel above 1.0 brightens. Gold at 2.0 gain reads as the
## badge catching light without blowing out to white — the same technique and the same reason
## as `HIT_FLASH_TINT_CRITICAL`, which is also gold-based.
const LEVEL_UP_FLASH_GAIN := 2.0

## Tint a dead entity's sprite keeps, marking it as a corpse rather than a live threat.
##
## It lives HERE rather than as a `Color(...)` literal in `Enemy._on_health_died()`, which is
## where it shipped: a presentation decision hard-coded in a gameplay entity is a colour no
## palette edit can reach, and the same literal had already been copied into two tests.
##
## MEASURED — and the second value had to be corrected too, because the first correction was
## justified with an argument that did not hold. A corpse is composited as
## `sprite * tint.rgb * tint.a + floor * (1 - tint.a)`, and the real numbers are:
##
## scored against the WORST (sprite, floor-tile) pair rather than against the floor's mean:
##
## | tint | worst d_lum vs FLOOR | worst d_lum vs LIVE |
## |---|---|---|
## | `0.55, 0.55, 0.62 @ 0.75` (shipped in Phase 10) | **0.009** | 0.200 |
## | `0.62, 0.66, 0.80 @ 0.80` (first correction) | **0.014** | 0.163 |
## | `0.26, 0.34, 0.52 @ 0.80` (second correction) | **0.082** | 0.287 |
## | `0.18, 0.26, 0.44 @ 0.80` (this value) | **0.121** | 0.319 |
##
## The third value is the instructive one: it passed when scored against the floor MEAN (0.115)
## and failed at 0.082 the moment the test measured per tile, on the pale player over the
## dimmest moss fill. Averaging a background averages away the case that actually breaks.
##
## against the measured floor. `v16_ground.png` holds EIGHT fills in two families, and they are
## measured per tile rather than averaged — a corpse lands on one tile, not on the mean, and
## averaging the floor averages away the worst case:
##   * moss (tiles 0-3): luminance 0.349 · 0.305 · 0.338 · 0.338, green (r≈0.23 b≈0.21)
##   * flooded paddy (tiles 4-7): luminance 0.349 · 0.359 · 0.367 · 0.361, blue-green (b≈0.44)
## So the floor spans **0.305 to 0.367** — not the ~0.25 an earlier version of this comment
## claimed from a glance at the dark pixels. Both earlier tints land their corpse within 0.014
## luminance of the floor mean, i.e. a corpse that a greyscale view cannot see at all: the first
## correction looked better in a capture purely because it was blue against green, so the whole
## signal rested on hue. That is the failure the UI bible's "colour is never the only carrier"
## rule exists to prevent, and it was reintroduced by the change that cited the rule — and it
## would have been worst on the PADDY, where a blue corpse has no hue contrast left at all.
##
## This value carries the mark on BOTH axes: the corpse sits at least 0.12 BELOW the floor in
## luminance (a darker silhouette, which is what makes the body's shape readable) and stays
## strongly blue-shifted (blue 0.26 above red) so it reads as drained rather than as a shadow.
## Going darker rather than lighter is the counter-intuitive part: "dimmer than alive" and
## "visible against the floor" both point DOWN, because the floor is brighter than it looks.
##
## The binding constraint is the PALE player over the DIMMEST moss fill, which caps the tint's
## luminance at ~0.30; this value is 0.256. A brighter character archetype tightens that cap.
##
## `test_damage_feedback.gd` re-measures all of this from the actual PNGs, per fill tile and per
## sprite, so a brighter floor or a paler creature fails loudly instead of quietly erasing the
## corpse (L-034).
const CORPSE_TINT := Color(0.18, 0.26, 0.44, 0.80)

## Floor luminance a corpse must stand clear of, and the margins it must clear by.
##
## The floor figure is DERIVED in the test from `v16_ground.png` rather than trusted from here;
## these two margins are the contract. 0.10 is about where a luminance step stops being
## arguable at 1:1 on a 16px grid, and the live margin is larger because "this is dead" must be
## unmistakable at a glance, not merely detectable.
const CORPSE_MIN_FLOOR_CONTRAST := 0.10
const CORPSE_MIN_LIVE_CONTRAST := 0.15

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
## The one PAINTED asset left in the live UI: the menu's backdrop SCENE (behind the menu only —
## a scene, never a surface that carries text; LINEAR-filtered, see `UITheme.build_backdrop`).
const PAINTED_UI_DIR := "res://assets/ui/aetheria"
const TEX_MENU_BACKDROP := PAINTED_UI_DIR + "/backdrop/cloud_peaks.png"


## Every runtime UI texture (for the asset-contract test — all must exist + be tracked).
const UI_TEXTURES := [
	TEX_PLAQUE, TEX_BAND_RIGHT, TEX_BAND_LEFT,
	TEX_BUTTON_NORMAL, TEX_BUTTON_HOVER, TEX_BUTTON_FOCUS, TEX_BUTTON_PRESSED,
	TEX_BUTTON_DISABLED, TEX_KEYCAP, TEX_GAUGE_WELL, TEX_GAUGE_FILL, TEX_SLOT,
	TEX_ORNAMENT_DIVIDER, TEX_ORNAMENT_FRAME, TEX_CORNER_FRET,
	TEX_MEDALLION_PLAYER, TEX_MEDALLION_FEMALE, TEX_MENU_BACKDROP,
]

## Surface brightness (0-255) above which light text stops being readable, so the surface
## must NOT be used behind the light text tokens. Asserted by the UI theme test.
const SURFACE_LIGHT_BRIGHTNESS_LIMIT := 120
