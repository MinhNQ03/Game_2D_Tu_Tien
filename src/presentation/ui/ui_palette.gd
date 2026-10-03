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

# --- Palette (prototype ink-and-jade tu-tiên tone) ---------------------------

## App background (behind the menu).
const COLOR_BACKGROUND := Color(0.07, 0.08, 0.10)

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

## Primary readable text.
const COLOR_TEXT := Color(0.92, 0.94, 0.96)

## Muted/secondary text (subtitles, hints).
const COLOR_TEXT_MUTED := Color(0.62, 0.66, 0.72)

## Disabled text.
const COLOR_TEXT_DISABLED := Color(0.42, 0.45, 0.49)

## Key-badge background (the little "E"/"Esc" chip in a hint).
const COLOR_BADGE := Color(0.17, 0.20, 0.24)


# --- Type scale --------------------------------------------------------------

const FONT_SIZE_TITLE := 48
const FONT_SIZE_SUBTITLE := 18
const FONT_SIZE_BUTTON := 22
const FONT_SIZE_BODY := 16
const FONT_SIZE_HINT := 15
const FONT_SIZE_BADGE := 14


# --- Spacing / shape ---------------------------------------------------------

const SPACE_SM := 6
const SPACE_MD := 12
const SPACE_LG := 24
const SPACE_XL := 40

## Button inner padding (horizontal, vertical).
const BUTTON_PAD_H := 28
const BUTTON_PAD_V := 10

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

const TEX_PANEL := UI_ASSET_DIR + "/panels/panel.png"
const TEX_PANEL_INSET := UI_ASSET_DIR + "/panels/panel_inset.png"
const TEX_BUTTON_NORMAL := UI_ASSET_DIR + "/buttons/button_normal.png"
const TEX_BUTTON_HOVER := UI_ASSET_DIR + "/buttons/button_hover.png"
const TEX_BUTTON_PRESSED := UI_ASSET_DIR + "/buttons/button_pressed.png"
const TEX_BUTTON_DISABLED := UI_ASSET_DIR + "/buttons/button_disabled.png"
const TEX_BUTTON_FOCUS := UI_ASSET_DIR + "/buttons/button_focus.png"
const TEX_KEY_BADGE := UI_ASSET_DIR + "/frames/key_badge.png"
const TEX_PORTRAIT_FRAME := UI_ASSET_DIR + "/frames/portrait_frame.png"
const TEX_TITLE_DIVIDER := UI_ASSET_DIR + "/frames/title_divider.png"

## Every runtime UI texture (for the asset-contract test — all must exist + be tracked).
const UI_TEXTURES := [
	TEX_PANEL, TEX_PANEL_INSET,
	TEX_BUTTON_NORMAL, TEX_BUTTON_HOVER, TEX_BUTTON_PRESSED, TEX_BUTTON_DISABLED,
	TEX_BUTTON_FOCUS, TEX_KEY_BADGE, TEX_PORTRAIT_FRAME, TEX_TITLE_DIVIDER,
]

## 9-slice border margins (px) authored into each xianxia texture (D-028). The border band of
## each PNG is NOT stretched; only the center is — pixel corners stay crisp at any size
## (`06-art-assets.md`, nine-slice rule). Margins differ per source texture, so they are
## declared per slot (read from each pack `.tres`): panels jade = 17; ink inset = 26/19;
## jade/silk buttons = L16 T14 R16 B18; the corner used as the key badge = 18.
const PANEL_MARGIN := 17            # panel.png (jade, 218x118)
const INSET_MARGIN := 24            # panel_inset.png (ink, 216x117 — authored 26/19, 24 safe)
const BUTTON_MARGIN := 16           # button_* (jade/silk, 130x54, border 16)
const KEY_BADGE_MARGIN := 18        # key_badge.png (corner, 61x61, ~18 border)
const PORTRAIT_MARGIN := 17         # portrait_frame.png (rosewood panel, 218x118)

## Kept for backward compatibility / the default `_texture_box` margin (panels/portrait).
const NINE_PATCH_MARGIN := 17
