# UI_UX_BIBLE — Aetheria

> **Owner of:** the visual language, the information hierarchy, HUD composition (§3c, D-057),
> the screen inventory, and the per-phase UI evolution plan.
> Token/asset implementation lives in `src/presentation/ui/ui_palette.gd` + `ui_theme.gd` (the
> single source of truth for colours, type scale, spacing, texture paths and 9-slice margins) and
> the asset rules in `.kiro/steering/06-art-assets.md`. This document owns the *design direction*;
> it changes no runtime code.

---

## 1. The existing UI is a FOUNDATION, not a ceiling

The live UI is the **ink-lacquer kit** (D-062): ORIGINAL art generated from the Visual DNA
(`tools/aetheria_art_pipeline/ui/ui_kit.py`, `docs/AETHERIA_ART_PIPELINE.md` §9) and wired through
`UIPalette` → `UITheme` → screens. It replaced the CC0 Xianxia Pixel Pack (D-028, flat "plastic"
plates) and the glossy painted plates (D-044, a mobile-MMO read). What the earlier passes learned
stays as measured invariants on the new art: dark text surfaces (D-034), Vietnamese first (D-035),
the composition of D-041, the weight ladder of D-057. Production foundation: real, shipped, tested
— and explicitly not final.

**Do not destroy it.** Phase 25 is consolidation and polish, not a rescue rewrite. Every new
screen is built on this language; if a screen needs something the language lacks, the language
gets extended (in `UIPalette`/`UITheme`), not bypassed.

## 2. The anti-pattern this document exists to prevent

```
Phase 07: placeholder → Phase 12: placeholder → Phase 19: placeholder → Phase 25: rewrite everything
```

That path guarantees a Phase-25 crisis and a game that looks unfinished for eighteen phases.
The policy instead (Continuous Visual Integration, already binding in `docs/ROADMAP.md`):

```
feature phase → the first USABLE UI for its own feature → later refinement → Phase 25 consolidation
```

Each feature phase owns the first real visual treatment of its own feature. Phase 25 then unifies
spacing, states, iconography and accessibility across screens that already work.

## 3. Visual language (frozen direction)

| Element | Direction |
|---|---|
| Surface | dark xianxia ink panels; ornate gold/jade framing via 9-slice |
| World | pixel art, nearest filter, integer scaling (`06-art-assets.md`) |
| System accent | restrained **teal/cyan** — interaction, selection, focus |
| Danger / hostility | **crimson** |
| Text | light on dark ink, with an outline for busy backgrounds (D-034) |
| Density | compact, information-dense, contextual panels |
| Input | keyboard-first desktop; semantic prompts, **never raw keycodes** |
| Language | vi + en, both first-class, no hard-coded strings |

**The measured-asset rule (L-021/D-034, binding):** before wiring any texture into a
`StyleBox`/`TextureRect`/`NinePatchRect`, measure its pixel size, centre alpha and centre
brightness. A surface that carries text must contrast with the text palette;
`content_margin >= texture_margin` on every 9-slice box — the one stated exception being the
painted button's RIGHT side, whose band is wide only so the faint cloud motif is not
stretched; there the label must clear the gold end-cap instead (D-056 review pass,
`test_painted_button_label_clears_every_ornament`). 9-slice bands are **measured on the art**
so each band holds a WHOLE ornament — a symmetric margin on asymmetric art stretches whatever
the shorter band cut in half. A frame belongs in a `NinePatchRect`; a
`TextureRect` used as a fixed-size slot must set `expand_mode = EXPAND_IGNORE_SIZE`.

## 3a. Composition rules (integrated in D-041 — binding on every new screen)

§3 froze the *palette and materials*. These are the **composition** rules, added once the
direction was actually built, because "correct tokens" turned out not to prevent an undesigned
screen: the menu used every right colour and still read as a widget floating in a void.

- **A full-screen surface is a scene, not a backdrop colour.** A screen that fills the viewport
  needs a ground, a gradient that implies a horizon, a restrained vignette, and framing — not a
  flat `ColorRect`. Build these from **code-generated `GradientTexture2D` + existing textures**
  unless real art is authored: a generated gradient costs one rasterisation and adds no
  provenance obligation (`06-art-assets.md`).
- **Gradients are the one nearest-filter exception.** A small ramp stretched full-screen bands
  under nearest, so backdrop/vignette layers use `TEXTURE_FILTER_LINEAR`. Everything else —
  panels, buttons, frames, ornaments, world art — stays nearest. Never relax it for pixel art.
- **Actions carry semantic WEIGHT, declared centrally.** A screen asks `UITheme` for
  `ROLE_PRIMARY` / `ROLE_SECONDARY` / `ROLE_DANGER`; **no screen names a colour.** One primary
  action per screen. Roles **modulate** the authored texture — never replace or distort it.
- **Crimson is reserved.** It means *leaving or destroying*. Used for ordinary emphasis it stops
  meaning anything, and the §4 rule still applies: colour is never the only carrier, so a
  destructive action also reads as destructive in its localized word.
- **A plaque with two kinds of information needs a visible tier boundary.** An ornamental rule +
  a section gap, not two more lines in the same column. The HUD identity plaque is the worked
  example: "who I am" above the rule, "who I belong to" below it.
- **Panel sizes are FLOORS, never fixed widths** (`custom_minimum_size`), and dividers expand to
  fill their parent. That is what keeps the +40% vi↔en string budget true instead of authoring
  the layout around one screenshot.
- **Never render a gauge for state no system owns yet.** No HP/mana/realm/XP bar may appear
  before the phase that owns that value. A gauge that looks right in a mock and shows nothing
  real in a build is worse than an absent one; assert its absence in a test until then.
- **Spacing comes from named layout tokens** (`HUD_MARGIN`, `SECTION_GAP`, `ROW_GAP`,
  `MENU_PANEL_WIDTH`, …), not literals. Screen-edge framing and inner padding are different
  concerns and must not share a token.
- **Composition is covered by STRUCTURAL tests.** Layout and surface pairing are invisible to
  compile, lint and type checks (L-021), so each rule above that can regress has an assertion:
  role distinctness, reserved-crimson, backdrop layering, divider stretch, margin uniformity,
  tier ordering, and no-unbound-gauges.

## 3b. Shared seams and looking at the screen (added in D-050 — binding)

§3a added composition rules. These are the rules that came out of actually **looking at the
running game** for the first time, which found nine defects in a UI that was asset-backed,
tokenised, and green on 481 tests. Nothing here is a taste judgement; each line is a defect
that shipped.

- **Construction that lives in one screen is construction the next screen does without.** Four
  pieces of the visual language are now ONE factory each in `UITheme` —
  `build_backdrop(parent)`, `menu_button(role)`, `ornament_divider()`, `scroll_body(parent)` —
  and a screen that assembles any of them itself fails a structural test. When the backdrop
  and the button lived inside `main_menu.gd`, the game's other full screen had a flat void and
  three untinted buttons: not a decision, just sixty lines nobody copied.
- **A structural guard WALKS the directory; it never lists files.** The first divider guard
  named two screens and passed while two others still had the defect it existed to catch. A
  hard-coded inventory protects only the files somebody remembered.
- **A reserve or limit constant is DERIVED from a measurement of what it reserves for, and a
  test re-measures it.** `assert_true(RESERVE > 0)` asserts that somebody thought about it.
  `TOP_PLAQUE_RESERVE` was wrong twice (104, then 174) while passing its tests.
- **Measure a POPULATED screen.** A hidden child contributes nothing to a container's minimum
  size, so a bare HUD measures plaques ~25px shorter than the ones on screen. Fill a screen
  through its PUBLIC setters before measuring it, with the **longest localized string derived
  from the authored set** — not a string somebody picked.
- **A reserve is unknowable while its subject can grow without bound.** Any label in a fixed
  region that is sized by a sentence gets `max_lines_visible` + ellipsis overrun. Growing over
  the playfield is worse than losing the tail of a passive hint.
- **A scrollbar is drawn OVER content, not beside it.** A scrolling panel reserves
  `SCROLLBAR_GUTTER` on the right, or its right-aligned value column runs underneath it.
- **State is never carried by ASCII decoration.** `> English <` is untranslatable punctuation
  wrapped around a translated name, it pushes the label off-centre, and it was the only carrier
  of the state. Use a localized template AND a role change — two carriers, per §4.
- **A screen is composed like a screen; a modal is composed like a modal.** Settings replaces
  the menu in navigation terms, so it gets its own full backdrop. Shown as a translucent
  overlay instead, the covered screen's differently-sized plaque produced a second frame around
  it and left its title and Quit label legible around the edges.
- **Look at the screenshots. Generating the evidence is not reviewing it.** `tools/capture_ui.gd`
  boots the real app in a real window and writes the real viewport for every UI state, in both
  languages, at two **aspect ratios** — not two pixel counts, since `canvas_items` + `expand`
  makes a same-aspect window a pure uniform scale. Mockups and editor screenshots do not count.
- **A tool that produces evidence fails loudly and exits non-zero when it could not reach the
  state it is about to name.** The harness verifies the active language against `Localization`
  and writes no file for a panel that did not open. A capture that quietly lies is worse than a
  missing one, because the file's whole job is to be what a human reviews.

## 3c. The HUD as presentation (D-057 — binding)

§3a composed the screens and §3b came from looking at them. These came from MEASURING how much of
the game the HUD covers — after D-057 found the whole HUD shifted by the desktop's own chrome and
the key prompts dressed in the same ornate plaque as the player's identity. This section OWNS the
HUD composition rules; `MOTION_DESIGN_CONTRACT.md` §11 owns how UI moves and records the
measurements.

- **Every permanent element earns its screen space** — by importance, frequency, context, visual
  weight, size, contrast and occupancy. "One data object = one panel" is forbidden; information
  that changes rarely or is read once is a candidate to collapse, become text-only or become
  contextual before it is a candidate for a new plaque.
- **Composition before components.** Before a HUD element is built, answer: what is the
  composition? the focal point? what must stay visible? what can disappear, collapse, become
  text-only or become contextual?
- **The weight ladder.** Ornament is how this UI says *this matters*, so it is spent only on what
  the player tracks:

  | Rung | Surface (`UITheme`) | Carries |
  |---|---|---|
  | framed plaque | `panel_stylebox()` — ink inset, gold corners | identity · place · combat target · side panels |
  | quiet band | `hint_band_stylebox()` — flat translucent ink, no frame | passive key prompts |
  | bare outlined text | the theme's label outline | transient announcements (level-up) |

  The band's alpha is a legibility bound, not a taste: over pure white it still measures under
  `SURFACE_LIGHT_BRIGHTNESS_LIMIT`, so the prompts are legal over anything the world can show.
- **Negative space, by number.** The permanent HUD covers at most
  `UIPalette.HUD_PERMANENT_AREA_BUDGET` (**15%**) of the viewport — measured **14.3%** at 1280×720
  and **12.9%** at 1280×800 at D-057, down from 16.5%. **No** HUD element, permanent or contextual,
  enters `UIPalette.PLAYFIELD_CLEAR_ZONE` — the middle 50% × 50% of the screen, where the camera
  keeps the player and the fight; the side panels are exempt because the player opens them on
  purpose. Both are re-measured on a POPULATED HUD in the longer language at both aspect ratios
  by `test_the_hud_keeps_the_playfield_centre_clear_and_inside_its_area_budget`, which WALKS the
  HUD root, so a new element is measured without anyone adding it to a list.
- **A reserve is bounded from both sides.** Too small, and the thing it protects is covered; too
  large, and it is dead playfield. `PROMPT_STRIP_RESERVE` went 78 → 54 when the prompts moved onto
  the band, and its test now bounds it from above as well as below.
- **On desktop the HUD is framed by `HUD_MARGIN` alone.** `get_display_safe_area()` on a desktop
  OS is the WORK AREA (screen minus docks and taskbars), not a notch; applied as an inset it put
  the left plaques 85px from the edge and the right ones 18px. Only a mobile notch that overlaps
  the window insets the HUD (`GameplayHUD.safe_area_insets`, tested; L-043).
- **A row states a condition, or it does not exist.** A HUD row is never left blank: a defeated
  target's plaque says *Defeated*, a live target with no rating has no rating row (§3b's
  "an empty label still occupies its row").
- **A settled HUD does no per-frame work**, asserted for the whole populated HUD tree, not only
  for each feedback node.
- **Combat takes the screen (D-057B).** The side panels are reading surfaces that cover a third
  of the playfield each. The moment a LIVE target is engaged — the transition, not each health
  update — any open side panel closes; a panel the player re-opens mid-fight stays open (a choice
  the HUD does not fight). Tested by
  `test_engaging_a_live_target_closes_the_side_panels_once`.
- **The answer to a key press is never kept waiting (D-063).** The bottom band is ONE slot shared
  by three kinds of notice and the breakthrough banner, and the caller that knows the CAUSE picks
  the kind: **ANSWER** (why the action did not happen) and **RESULT** (what it achieved) are on
  screen on the frame they are announced — ≤ 2 rendered frames and ≤ 100 ms, measured in the real
  app; **PASSIVE** (what happened around the player) waits in arrival order. Priority in the slot:
  answers/results > the breakthrough banner > passive. Whatever gives way is KEPT — an interrupted
  notice resumes, the banner pauses and resumes — except an ANSWER superseded by a newer one: a
  stale refusal is never shown again. No notice is ever dropped; a backlog past
  `HUD_NOTICE_BACKLOG_GUARD` is reported as a producer bug. A new notice must declare its kind
  (`announce` / `announce_result` / `announce_answer`); a new band element must keep the stack
  out of `PLAYFIELD_CLEAR_ZONE` (the banner and the notice cannot stack at 1280×720: 6 px over).
- **Reference boards are filtered, not adopted.** The Aetheria `09_ui_composition` board shows
  mobile-MMORPG conventions — an MP bar, a skill-icon ring, a minimap, XP toasts — that this
  bible forbids (`XIANXIA_IDENTITY_CONTRACT.md` §2.3, R-7).

## 4. Information hierarchy (frozen)

- **Panel hierarchy:** world → HUD overlay → contextual panel → modal. A modal owns input while
  open; exactly one modal owner at a time.
- **Typography:** title → subtitle → body → hint. Four steps, defined once in `UIPalette`.
- **Icon language:** one icon per concept, globally. An icon never means two things.
- **Semantic colour:** accent = interactive · crimson = danger/hostile · muted = unavailable ·
  gold = canon/authority (sect, covenant, title). Colour is **never the only** carrier of meaning
  (also text or icon) — an accessibility requirement, not a preference.
- **Interaction states:** normal · hover · focus · pressed · disabled — all five, every control.
  Keyboard focus must be as visible as mouse hover.
- **Notifications:** transient and non-blocking; anything the player must act on is a panel, not a
  toast.
- **Navigation ownership:** one owner per screen stack; no screen frees the screen that opened it
  (the D-035 settings pattern: hide, don't free).
- **Readability + localization expansion:** layouts must absorb **+40%** string length (vi↔en
  differ substantially) without clipping. Fixed-width labels are a bug.
- **Safe area / resolution:** the authored viewport is **1280×720** (`project.godot`, D-043 —
  the 1152×648 this line recorded until D-057 was Godot's implicit default, superseded there),
  with `canvas_items` + `expand` stretch; no element may depend on an exact window size. The
  *safe area* means what PHYSICALLY covers the window — a phone's notch or cutout — and never a
  desktop dock, panel or taskbar (§3c).

## 5. Screen inventory (direction only — none implemented by this document)

| Screen | Direction |
|---|---|
| Main Menu | **exists**; title, subtitle, New Game / Load / Settings / Quit |
| Settings | **exists**; language now, categories later |
| HUD | **exists**; identity, map, sect chip, semantic prompts. Grows: health/resource (P-09), realm (P-12) |
| Character | identity, stats, origin, realm, path, sect — one screen that answers "what am I?" |
| Cultivation | the realm ladder as a *ladder*; current layer, what the next one grants (not just a bar) |
| Technique | known công pháp + the **compatibility graph** — the build screen |
| Skill | loadout, costs, cooldowns, technique gates |
| Equipment / Inventory | slots + stats; inventory grid with source/sink clarity |
| Quest Journal | active/available/done, by category, with the *why* |
| Dialogue | portrait + text + choices; choices show what they are about, never a morality icon |
| Relationship | per-character the six dimensions, legibly — **not** one bar |
| Sect | **exists** (panel); grows into roster, rank, contribution, politics |
| Faction | influence and attitudes inside a sect (P-07) |
| World Map / Atlas | the expansion screen (§6) |
| Dungeon | run progress, checkpoints, modifiers |
| Crafting / Shop | recipes with prerequisites visible; prices with regional context |
| Pet | companion state |
| Party / Social | reserved for P-32+; nothing now |
| World Event | what is happening in the world without the player |
| Story Chronicle | the player's own history — the Tà Đế identity surface |

## 6. The UI must communicate world scale

The UI is part of the storytelling: what it *shows* tracks what the player **knows**.

| Stage | The UI shows |
|---|---|
| Early (Acts I–II) | character · sect · local map · current quests |
| Mid (Acts III–V) | + cultivation · techniques · relationships · faction politics · regional map |
| Late (Acts VI–X) | + world atlas (Main/Tiểu/Tàn/Hủ) · world gates · world events · **historical records** · the Tà Đế chronicle |

Worked example of the same object deepening: "Thanh Vân Tông" → "Thanh Vân Tông + your rank and
standing" → "+ its internal factions and their attitudes" → "+ its position in covenant politics
and what its archives omitted". **Same screen, progressively more truth** — which is the UI
expression of the reveal ladder (`NARRATIVE_MASTER_PLAN.md` §9).

A corollary: screens may legitimately be **locked or absent** early. A world atlas shown in Act I
spoils the scale the game spends forty hours earning.

## 7. UI evolution by phase

Each entry is the **first usable** treatment, in that feature's own phase.

| Phase | UI deliverable |
|---|---|
| 06 Sect *(done)* | menu composition + HUD identity/map plaques + sect detail panel, in the §3a language (D-041) |
| 07 Faction | faction/politics panel: influence, attitudes, stance — **built in the §3a language, no placeholder pass** |
| 09 Combat | combat HUD — target, health, resource, hit feedback, **telegraph language + VFX vocabulary** |
| 10 Enemy AI | enemy identification/threat read |
| 11 Progression | level/XP surface |
| 12 Cultivation | realm + layer surface; what the next layer grants |
| 13 Inventory | inventory grid |
| 14 Equipment | slots + stat deltas |
| 15 Skill / Technique | loadout + compatibility graph |
| 16 Pet | pet panel (where exposed) |
| 17 NPC / Shop | interaction + trade |
| 18 Dialogue | dialogue + choice presentation |
| 19 Quest | journal |
| 20 Story | chronicle / chapter surface |
| 21 Dungeon | run UI |
| 22 Boss | boss presentation (name, phases, escalation) |
| 23 Save / Load | slots |
| 24 Localization | full vi/en pass + **expansion audit** across every screen |
| 25 Consolidation | consistency · interaction states · iconography · accessibility · polish |
| 26 Audio/VFX | audio-visual feedback unification |
| 32+ | party/social presentation (only if multiplayer proceeds) |

## 8. Consistency audit (Audit T)

Can combat, cultivation, inventory, technique, sect, faction, quest, dialogue, world map, dungeon
and story all live under ONE visual language? **Yes**, because every one of them is a variation of
three primitives the foundation already has:

1. a **framed dark panel** carrying light text (the inset plate, D-034);
2. a **list/grid of entries** with icon + name + value;
3. a **contextual detail pane** for the selected entry.

The sect panel already is exactly this shape. The screens differ in *content and density*, not in
language. Risks to watch at Phase 25: density creep on the HUD, icon reuse for different
concepts, and colour-only meaning.

## 8b. Maintainability of the UI foundation (D-050 deliverable)

What it costs to change this UI, stated as facts that were CHECKED rather than as intentions.
Each claim below is either enforced by a named test or was verified by grep at the time of
writing; where something is *not* as tidy as it sounds, that is said instead of smoothed over.

**Changing the look of a thing is one edit.** The five shared seams each have exactly one
factory in `UITheme` — `build_backdrop(parent)`, `menu_button(role)`, `ornament_divider()`,
`scroll_body(parent)`, `vitals_gauge()` — and a screen that builds its own fails a structural
test that WALKS `src/presentation` (`test_d050_the_divider_comes_from_one_central_factory`,
`test_d050_the_backdrop_button_and_scroll_body_come_from_the_theme`). So restyling every
divider, every menu button or every scrolling panel in the game is a change in one function.

**No screen names a colour, and no screen names an asset path.** Verified: zero `Color(`
literals anywhere in `src/presentation` outside `ui_palette.gd`/`ui_theme.gd`, and zero
`res://assets` strings outside `ui_palette.gd`. Colour arrives as a semantic ROLE
(`ROLE_PRIMARY`/`SECONDARY`/`DANGER`) or a palette token; geometry arrives as a named layout
token. That is what makes a retheme a palette edit rather than a sweep.

**Swapping the art is one generator and one root.** `UI_ASSET_DIR` (`assets/ui/aetheria_ink`)
holds every UI texture the kit writes; the slices beside each constant are the kit's own (D-062).
A restyle is a re-run of `ui_kit.py` from a changed DNA, never a screen edit. The one painted asset
left (`PAINTED_UI_DIR`, the menu backdrop scene) is LINEAR and never carries text.

**Adding a screen inherits the foundation by construction.** Call `UITheme.build_backdrop(self)`
and `UITheme.menu_button(role)` and the screen already has the composition, the interaction
states, the focus handling and the key prompts. The settings screen is the worked example of
what happens otherwise: it predated the factories, so it shipped as a plaque on a flat void
with three untinted buttons — not a decision, just construction nobody copied.

**The limits, stated plainly:**
- A **tier added to a measured container** (the HUD plaques) requires updating
  `TOP_PLAQUE_RESERVE` *and* the test fixture that populates it. The reserve is derived from a
  measurement, not computed at runtime, so it is the one number a new tier can invalidate —
  and a hidden child measures as zero, which is how it was wrong four times (L-035).
- **Three gauges exist** (D-054): the player's health, the combat target's health, and the
  player's XP meter. The rule that permits each is unchanged — a system owns that value — and
  the gauge COUNT is still asserted, so a fourth (mana, realm progress) fails loudly until its
  phase arrives. Each gauge is named in the assertion, so swapping one for an unbacked bar
  fails even though the count would still be right.
- **TWO METERS IN ONE PLAQUE MUST DIFFER ON MORE THAN COLOUR** (D-054, binding). The XP meter
  sits directly under the health gauge — the hardest place to tell two bars apart — so it is
  separated on three INDEPENDENT channels: **hue** (gold for progression, jade for vitals, using
  the palette's existing vocabulary where gold already means structure and attainment),
  and **written text** (each writes its own numbers behind a localized caption). Colour alone
  would fail the §4 rule and fail a colour-blind player outright; the caption is what makes the
  distinction survive without it.
  **WEIGHT was a third channel and is RETIRED (D-056).** The meter was 8px against the gauge's
  14px so XP read as subordinate — and a meter writes its value INSIDE itself, where a
  `FONT_SIZE_HINT` label measures **20px**, so "XP 0 / 20" drew its descenders across the rail's
  own bottom border. Both meters now stand at the label's measured height. **A third carrier
  that makes the content illegible is worse than two that do not** — and a reserve/size that
  nobody measured against the thing it holds is the L-034 defect at a smaller scale. The general
  rule now: **a readout must be able to contain what it prints**, re-measured by
  `test_every_meter_is_tall_enough_for_the_value_it_writes_inside_itself` for every meter in the
  HUD.
- **A gauge at a terminal state must not render as its raw numbers.** At the top of the
  authored XP curve both numerator and denominator are 0, and `0 / 0` on a character who has
  earned everything is a lie — so the meter shows COMPLETE, in its own fill colour, with
  localized "max" text.
- **An announcement belongs in a band the HUD OWNS, never near the screen centre** (L-038). The
  camera follows the player, so the centre of the screen is the character; the level-up banner
  printed across them, and offsetting it upwards did not help because the camera is CLAMPED by
  the map limits and the player is not a fixed distance from the centre. It is now bottom-centre,
  inset by `PROMPT_STRIP_RESERVE + SPACE_LG`, which makes "cannot collide" arithmetic.
- **Level is not cảnh giới, and the UI must not say it is.** The progression strings use
  `Cấp / Kinh nghiệm / Thăng cấp` and are forbidden from using *tu vi*, *đột phá* or *cảnh
  giới* — asserted in both languages. The HUD is the only place the player actually looks, so
  borrowing cultivation words there would tell them the two axes are one thing (D-054).
- **The key chip is the kit's raised keycap** (D-062): solid under the glyph (measured), its lip a
  separate 9-slice band, a jade edge because a key is interaction.
- **The technique dock sits bottom-centre** (D-062): the player's hands under the player, below
  the clear zone and the announcement band; its slots are the satchel's slot family
  (`UITheme.icon_slot`) with an element ring.
- **The identity portrait is a medallion of the actor's own pipeline portrait** (D-062): the face
  in the HUD is the figure on the map, drawn 1:1, never resampled.
- **Visual regressions are caught by a human looking at `tools/capture_ui.gd` output**, AND
  scored structurally: `capture_motion golden` + `validate/visual_benchmark.py` (D-062) gives the
  golden frame an explainable score against the quality reference (never a pixel diff). "Run the
  captures and look" stays a required step of any UI change (§3b).

## 9. What this document does NOT do

No screens are implemented, no runtime UI code is changed, and no asset is added. Phase 25 is
consolidation of screens that already work — **not** a rescue rewrite (§1).
