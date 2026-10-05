# UI_UX_BIBLE — Aetheria

> **Owner of:** the visual language, the information hierarchy, the screen inventory, and the
> per-phase UI evolution plan.
> Token/asset implementation lives in `src/presentation/ui/ui_palette.gd` + `ui_theme.gd` (the
> single source of truth for colours, type scale, spacing, texture paths and 9-slice margins) and
> the asset rules in `.kiro/steering/06-art-assets.md`. This document owns the *design direction*;
> it changes no runtime code.

---

## 1. The existing UI is a FOUNDATION, not a ceiling

The live UI is the CC0 **Xianxia Pixel Pack** set wired through `UIPalette` → `UITheme` (D-028),
hardened for legibility from *measured* asset pixels (D-034), with Vietnamese as the default
language (D-035), and **composed** to this document's visual direction in D-041. It is
**production foundation**: real, shipped, tested — and explicitly not final.

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
`content_margin >= texture_margin` on every 9-slice box; a frame belongs in a `NinePatchRect`; a
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
- **Safe area / resolution:** declared base viewport (1152×648, D-034) with `canvas_items`
  stretch; no element may depend on an exact window size.

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

## 9. What this document does NOT do

No screens are implemented, no runtime UI code is changed, and no asset is added. Phase 25 is
consolidation of screens that already work — **not** a rescue rewrite (§1).
