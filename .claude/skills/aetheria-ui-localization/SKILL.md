---
name: aetheria-ui-localization
description: Aetheria UI/UX and vi+en localization rules - UITheme roles, layout tokens, HUD 15% budget, centred book, text that fits, keys, two aspect ratios. Use before any screen, HUD or string change.
---

# Aetheria UI and localization — what a screen must satisfy

Owners: `docs/UI_UX_BIBLE.md` (§3a composition, §3c HUD, §8d centred book), `.kiro/steering/07-localization.md`,
`docs/MOTION_DESIGN_CONTRACT.md` §11 (UI motion), `docs/PLAYER_EXPERIENCE_STANDARD.md`.
Reviewer: `aetheria-ui-ux-reviewer`.

## Localization (vi and en are both first-class)
- No player-facing literal anywhere (UI, gameplay, dialogue, item/skill/quest data). Content
  stores KEYS: `DOMAIN_SUBJECT_DETAIL` in UPPER_SNAKE (`ITEM_POTION_HEALTH_NAME`).
- A shipped key never changes (breaking change → `docs/DECISIONS.md`).
- Parameterized templates (`"Nhận được {amount} {item}"`), never sentence concatenation.
- Every key exists in both languages; fonts render full Vietnamese diacritics.
- Budget +40 % length vi↔en: panel sizes are FLOORS (`custom_minimum_size`), never fixed widths.

## Composition (§3a, §3c)
- One focal point and ONE primary action per screen. Colours come from `UITheme` roles
  (`ROLE_PRIMARY/SECONDARY/DANGER`); no screen names a colour. Crimson = leaving/destroying only.
- Spacing from named tokens (`HUD_MARGIN`, `SECTION_GAP`, `ROW_GAP`, …), never literals.
- Nearest filter everywhere except full-screen gradients (LINEAR).
- Never draw a gauge for state no system owns yet.
- Weight ladder: framed plaque (identity, place, target) → quiet band (key prompts) → bare
  outlined text (transient). Permanent HUD ≤ `HUD_PERMANENT_AREA_BUDGET` (15 %) of the viewport.
- A HUD element sits in a band the HUD owns, never offset from the camera-followed player (L-038).
- Colour is never the only carrier (a chosen tab is lit AND gold).

## Reading surfaces (§8d centred book, `UIBookPanel`)
Sized by the viewport (0.72 width, 72 px insets), never by content; long pages scroll inside;
title + ONE close key (Esc); tabs only when >1 page; modal (UI_MODAL context, scrim, side panels
close); fonts measured by tests (title 22, rows 20, body ≥ `FONT_SIZE_BODY`). The book decides
nothing — its owner hands it pages.

## Text that fits (the defect class that kept coming back)
- "It scrolls" is not "it can be read" (L-048); a test counting lines misses a cut word (L-057).
- Dialogue: every line, speaker name and answer shown whole (ui-01).
- A player-expected action must be discoverable from the screen, not only from the test (L-039).
- Measure a fully populated screen through public setters (L-035); assert offsets (L-028).

## Evidence
Real window, BOTH languages, 1280×720 AND 1280×800:
`<godot> --path . --resolution 1280x720 -s res://tools/capture_ui.gd -- vi <dir>` (then en, 1280x800).
A capture in the other language is not a duplicate (L-057). Open every PNG before claiming it.
Structural tests guard each composition rule that can regress (role distinctness, reserved
crimson, margins, tier order, no unbound gauges).
