# XIANXIA IDENTITY CONTRACT — Aetheria

> **Status: DESIGN CONTRACT, frozen by D-057A (2026-10-06). Documentation only** — it implements
> nothing and starts no phase. Phase 12 is NOT started.
>
> **Owner of:** what makes a feature look and behave like *Aetheria* rather than generic
> fantasy or generic xianxia; the authority of reference material; the Aetheria Xianxia
> Reference Library — its definition, path, status, known conflicts and how it is studied; the
> identity gates every major presentation feature passes.
>
> **Not owner of** (cite, do not restate): canon facts → `docs/CANON_LEDGER.md`,
> `docs/WORLD_BIBLE.md` · motion law → `docs/MOTION_DESIGN_CONTRACT.md` (D-057) · presentation
> wiring → `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` · sprite rules →
> `docs/CHARACTER_ART_BIBLE.md` · UI language → `docs/UI_UX_BIBLE.md` · asset provenance →
> `.kiro/steering/06-art-assets.md`, `docs/ASSET_LICENSES.md`.

It exists to stop two failure modes:

```
1. the AI knows how to animate,   BUT not what makes the animation feel like Aetheria
2. the AI has reference images,   BUT copies or assembles them
```

D-057 answers *is the motion believable?* This contract answers *does it belong to Aetheria?*
They are different questions (§7) and a feature must pass both.

---

## 1. Authority

### 1.1 The derivation chain — how a feature gets its look

```
AETHERIA DESIGN INTENT          .kiro/steering/01-product.md · 02-game-design.md · GAME_DESIGN_FREEZE.md
        ↓                       + canon: CANON_LEDGER.md · WORLD_BIBLE.md
AETHERIA ART BIBLE              CHARACTER_ART_BIBLE.md · .kiro/steering/06-art-assets.md
        ↓
AETHERIA UI/UX BIBLE            UI_UX_BIBLE.md
        ↓
D-057  MOTION / PRESENTATION    MOTION_DESIGN_CONTRACT.md · PRESENTATION_ARCHITECTURE_CONTRACT.md
        ↓
D-057A XIANXIA IDENTITY         this document
        ↓
AETHERIA XIANXIA REFERENCE PACK docs/design_refs/aetheria_xianxia/   (local, §2)
        ↓
FEATURE-SPECIFIC APPLICATION    the phase's own design + its Reference → Original note (§13)
```

### 1.2 The priority order when sources disagree

```
1. AETHERIA GAME / PRODUCT INTENT and CANON
2. AETHERIA ART BIBLE
3. AETHERIA UI/UX BIBLE
4. ARCHITECTURE and GAMEPLAY READABILITY
5. D-057  universal motion / presentation principles
6. D-057A Aetheria xianxia identity (this document)
7. AETHERIA XIANXIA REFERENCE PACK
8. EXTERNAL REFERENCE PACKS (Foozle, Kenney, …)
9. DECORATIVE DETAIL
```

**I-1.1 — Aetheria rules win.** Reference material never overrides gameplay readability,
performance, architecture, authoritative state ownership, the multiplayer boundary, the Art Bible
or the UI/UX Bible. A conflict is not resolved by "the reference shows it": the higher source
wins and the conflict is recorded (§2.3 is the standing record).

**I-1.2 — The pack's own manifest agrees.** `REFERENCE_MANIFEST.md` inside the pack lists five
levels (design intent > Art Bible > UI/UX Bible > this pack > external packs); the order above is
the same order with architecture/readability and the two contracts placed explicitly.

---

## 2. The Aetheria Xianxia Reference Library

### 2.1 Definition

> **`docs/design_refs/aetheria_xianxia/` is the Aetheria Xianxia Art Direction Reference
> Library**, used as VISUAL NORTH STAR and DESIGN RESEARCH MATERIAL for decisions about
> character, motion, cultivation presentation, qi, environment, sect architecture, materials,
> VFX, UI composition and camera/story moments.

| It IS | It is NOT |
|---|---|
| design research material | a production asset pack |
| a visual north star | a canonical sprite library |
| behaviour reference (how things move and react) | gameplay data |
| composition reference (how a frame is organised) | runtime content |
| a style-consistency anchor | a source of authoritative gameplay state |
| | a licence to copy anything in it |
| | **canon** — it contradicts canon in places (§2.3) |

**I-2.1 — Presence is not permission.** That an image exists in the repository tree is never a
reason to use it in production, and "it looks good" is never a reason to promote it.

### 2.2 What is actually there (inspected at D-057A, not assumed)

**Physical status.** LOCAL and UNTRACKED: `docs/design_refs/` is gitignored, so a fresh clone
has no pack and this contract's written principles are the authority there. **Never imported:**
the tracked `docs/.gdignore` keeps everything under `docs/` out of Godot's scan, import and
export — the pack was being imported as game textures until D-057 found it (guarded by
`tests/unit/framework/test_reference_library_isolation.gd`).

| File | Size | What it is |
|---|---|---|
| `AETHERIA_XIANXIA_ART_DIRECTION_MOODBOARD_01.png` | 1312×1199 | full moodboard: ten category panels, folder tree, palette, keywords |
| `AETHERIA_XIANXIA_ART_DIRECTION_MOODBOARD_02.png` | 1312×1199 | full moodboard: same ten categories, different images and sub-panels |
| `AETHERIA_XIANXIA_ART_DIRECTION_MOODBOARD_03.png` | 1312×1199 | full moodboard with Vietnamese captions; the source of the ten crops |
| `01_character/` … `10_camera_story_moments/` | one PNG each, ~263×385 | a crop of moodboard 03's matching panel |
| `README.md`, `REFERENCE_MANIFEST.md` | text | "REFERENCE ONLY", the study workflow, a 5-level authority list |
| `KIRO_D057_…_NOTE.md`, `CLAUDE_D057_…_NOTE.md` | text | integration instructions addressed to AI contributors |

Expected vs found: the structure matches the expected layout, plus the `CLAUDE_` note. The ten
crops are **low resolution** and **bleed into the neighbouring panel** at their edges (the
`04_qi_spiritual_energy` crop carries part of the cultivation panel's realm list). **Study the
matching region of the full moodboard; never treat a crop's edge as part of its category.**

The images are generated illustrations (pseudo-text, garbled glyphs and inconsistent captions
are visible), in a painterly anime style, front/side view.

### 2.3 Known conflicts with canon — the standing record

The pack is a north star for *feel*; on *facts* it is often wrong. Each line below is a trap a
future phase would otherwise walk into.

| # | The pack shows | Canon says | Owner |
|---|---|---|---|
| R-1 | Realm ladders: **Luyện Khí · Trúc Cơ · Kim Đan · Nguyên Anh · Hóa Thần · Độ Kiếp · Phi Thăng** (moodboard 03, and the edge of the `04` crop); **Foundation · Qi Refining · Core Formation · Nascent Soul · Void · True Immortal** (moodboard 02); Gathering → Transcendence (moodboard 01) | **PHÀM → HẬU THIÊN → TIÊN THIÊN → NGỰ THIÊN → TRỌNG THIÊN** (+ THÁI/VÔ THIÊN); the conventional ladder "must not appear in content" | `CANON_LEDGER.md` CL-02, C-001 |
| R-2 | Elements: Wood · Fire · Water · Metal · Earth (moodboard 02); Thanh · Hỏa · Thổ · Kim · Mộc · Âm Dương (moodboard 03) | a CLOSED set of four: **Hỏa · Thủy · Phong · Lôi** | `COMBAT_DESIGN.md` §3 |
| R-3 | Weapon types: Sword · Spear · **Fan** · Blade · Ranged | five frozen families: **Kiếm · Đao · Thương · Cung · Pháp Trượng**; no fan family | `CANON_LEDGER.md` CL-10 |
| R-4 | "Race & Type: Human · **Elf-like** · Spirit · **Beastfolk**" | no such races exist in canon; adding a species is a canon change | `CANON_LEDGER.md` change control |
| R-5 | Painterly anime illustration, slender 8-head figures, front/side view | top-down pixel art, 32×48, head ≈ 1/3 of height, nearest filter | `CHARACTER_ART_BIBLE.md` §2/§4 |
| R-6 | Saturated glow, purple/blue default, particles and halos as the power signal | VFX quality is right effect/place/time/scale, never more glow | `MOTION_DESIGN_CONTRACT.md` M-15.2 |
| R-7 | Mobile-MMORPG HUD: MP bar, skill-icon ring, minimap, "You gained 500 EXP" notification, stacked panels | no gauge for state no system owns; notifications are non-blocking; weight ladder and area budget | `UI_UX_BIBLE.md` §3a/§3c/§4 |
| R-8 | Camera "angles": isometric · three-quarter · close-up · panorama | a top-down 2D camera frames; it does not change angle | M-9.4 |
| R-9 | Floating mountains, waterfall palaces, cherry blossoms as THE world | the player starts in the **Hoang Vực** frontier — thin administration, unstable veins; that grandeur is **Thiên Nguyên Vực**, reached in Act IV and meant to feel like entering a capital | `WORLD_BIBLE.md` §4.1, §4.5 |
| R-10 | Taglines and labels: 九霄 ("Nine Heavens"), "Where mortals, spirits and the cosmos coexist", "Cultivation is becoming the highest version of oneself" | not canon text; Aetheria's one-sentence world is the Hạo Nguyên Giới covenant sentence | `WORLD_BIBLE.md` §1 |
| R-11 | Metadata: "Total Assets: 500+ images", "Version 1.0/1.1", dates in 2025 | the pack holds 13 images; its labels are illustrative, not records | §2.2 |

**I-2.2 — Words on a reference board are never content.** Labels, captions, realm names,
element names and taglines in the pack are not canon and must not reach a localization key, a
data resource or a UI string. Canon names come from `CANON_LEDGER.md` only.

---

## 3. The reference study workflow

**I-3.1 — The only accepted workflow:**

```
REFERENCE → OBSERVE → ANALYZE → EXTRACT PRINCIPLE → ABSTRACT → ADAPT TO AETHERIA
          → CHECK GAMEPLAY READABILITY → CHECK THE ART BIBLE → IMPLEMENT AN ORIGINAL RESULT
          → REAL-SCREEN QA (MOTION_DESIGN_CONTRACT.md M-11.5)
```

**Forbidden workflows:**

```
REFERENCE → COPY → ASSEMBLE
"the asset is already here" → "put it in the game because it looks good"
```

**I-3.2 — Choose references by BEHAVIOUR, not by keyword.** To design a stepping palm strike,
the useful reference is a body transferring weight, not an image tagged "xianxia attack". Real
motion, martial arts, animals, material physics, weather, water, fire, cloth, cinematic blocking,
UI motion and game animation are all valid sources (`MOTION_DESIGN_CONTRACT.md` M-2.2).

**I-3.3 — A real-world reference is stylised INTO Aetheria**, never imported raw: it teaches
motion, weight, gesture, material, light and cause/effect — and must not break the Art Bible,
the pixel density, the camera, the palette, the silhouette language or the top-down view.

---

## 4. Category guide — what each folder is for

Each entry: the design **question** the folder answers · what to **study** · how it is
**adapted** to Aetheria (grounded in canon) · what **not** to take from that board.

### 01_character — *What does an Aetheria cultivator look like?*
* **Study:** silhouette · proportion · costume language · cultivator vs NPC identity ·
  expression · stance · top-down readability.
* **Adapt:** the costume LANGUAGE already defines the cast — layered floor-length robe,
  waist-length hair, one accent per archetype from shared ramps (D-046, Art Bible §5). Status and
  path read through costume and posture, not glow. Proportion is the Art Bible's: head ≈ 1/3 of
  a 32×48 figure, so it reads from above.
* **Not:** the anime proportions, the painterly rendering, illustration poses as sprite poses,
  "Elf-like/Beastfolk" races (R-4, R-5).

### 02_martial_motion — *What logic should palm, sword and body-art movement have?*
* **Study:** stance · weight transfer · centre of mass · gesture · martial intent · weapon flow ·
  anticipation · follow-through · recovery.
* **Adapt:** the humanoid chain and its 32×48 rules (`MOTION_DESIGN_CONTRACT.md` §3). Motion
  carries doctrine: Thanh Vân Tông "tempers the heart before the blade" — economy, a settled
  stance before release, a follow-through that ends composed; heterodox and Cấm Pháp methods
  "genuinely cost the body" (`WORLD_BIBLE.md` §4.2, §8) — strain and over-extension are the
  visible price. Each weapon family moves to its role (`COMBAT_DESIGN.md` §4): Kiếm precise and
  countering, Đao committed momentum, Thương owning space, Cung keeping distance, Pháp Trượng the
  least physical.
* **Not:** trails and glow arcs as the motion (the motion is the body; a trail is secondary
  VFX) · the fan as a family (R-3) · acrobatics a top-down camera cannot show · the guard-down,
  T-pose and circle-hand shortcuts.

### 03_cultivation — *Cultivation looks still — so what should it feel like?*
* **Study:** stillness · breathing · meditation · qi awareness · qi circulation ·
  concentration · breakthrough · spiritual pressure · ceremonial rhythm.
* **Adapt:** a realm is *becoming a different kind of being* (`PROGRESSION_CULTIVATION_DESIGN.md`
  §1), and its first change is PERCEPTION — a Hậu Thiên cultivator senses qi nearby, a Tiên
  Thiên one reads its structure, a Ngự Thiên one perceives a whole site (§9 realm table). So a
  breakthrough is macro scale (M-4.7) and changes what the character perceives and radiates,
  not just a flash; and cultivation draws qi FROM the place, because qi wells up through veins
  (`WORLD_BIBLE.md` law 1).
* **Not:** the realm labels on this board (R-1) · "cultivation = generic power-up VFX" · a
  level-up that looks like a breakthrough (level is getting better at fighting; a realm is a
  different being — the two must never share a look).

### 04_qi_spiritual_energy — *How does spiritual energy move?*
* **Study:** source · movement · flow · gathering · compression · direction · interaction ·
  release · dissipation · elemental identity.
* **Adapt:** **qi is not ambient** (`WORLD_BIBLE.md` law 1): every qi visual has a source — a
  vein, a body, a technique, an artifact — and a direction; nothing sparkles from nowhere. Qi
  near a broken vein is the one place it visibly misbehaves (`CANON_LEDGER.md` CL-08, Rừng Vỡ
  Mạch) — and that behaviour may foreshadow *why the veins are failing* without answering it
  (CL-15). Elements are Hỏa · Thủy · Phong · Lôi, each with a BEHAVIOUR (Hỏa pressure, Thủy
  control, Phong mobility, Lôi interruption — `COMBAT_DESIGN.md` §3) carried by shape and motion
  as well as colour, because colour is never the only carrier (`UI_UX_BIBLE.md` §4).
* **Not:** Ngũ hành or Âm Dương as elements (R-2) · dragon forms as generic qi · glow intensity.

### 05_world_environment — *What does "life" look like in a cultivation world?*
* **Study:** biome · atmosphere · mist · mountain · forest · water · season · weather · ambient
  motion · spiritual intensity · environmental storytelling.
* **Adapt:** the game starts on the **frontier** — Thôn Lạc Hà and Rừng Vỡ Mạch in the Hoang
  Vực, where administration is thin and the veins unstable (`WORLD_BIBLE.md` §4.5, CL-11). The
  first maps read rough, lived-in and sparse; heartland grandeur is earned later, which is also
  how the UI reveals world scale (`UI_UX_BIBLE.md` §6). Ambient motion obeys M-10.1/M-10.2;
  environmental storytelling shows the veins.
* **Not:** postcard floating islands as the frontier (R-9) · synchronized animated wallpaper ·
  constant particles · cherry blossoms as a default rather than a season or region.

### 06_sect_architecture — *How does an Aetheria sect differ from a generic fantasy village?*
* **Study:** sect identity · temples · courtyards · training grounds · formation areas ·
  buildings · banners · gates · ritual spaces · spatial hierarchy.
* **Adapt:** sects are GEOGRAPHIC because a vein is territory, infrastructure and politics at
  once (`WORLD_BIBLE.md` law 1): architecture sits on the vein and expresses who may approach
  it. Thanh Vân Tông is examination-based and administered; every sect carries an internal
  disagreement (§8), which can show in who occupies which court. A frontier outpost of a larger
  power is lesser and provisional, not a palace.
* **Not:** generic Chinese decoration as identity · one palace complex reused for every sect ·
  banner colour as the only faction marker.

### 07_materials_props — *How do jade, bamboo, silk, talisman paper and stone react?*
* **Study:** wood · stone · jade · metal · cloth · silk · paper · talisman · bamboo · ceramic ·
  water · mist · earth · tools · weapons · ritual objects.
* **Adapt:** each material takes its governing law (`MOTION_DESIGN_CONTRACT.md` M-2.1): jade,
  stone, ceramic and metal are rigid — weight, pivot, a glint or a ring, no bounce; bamboo bends
  and recovers with delay; silk and cloth lag and damp; a paper talisman is light, flutters and
  burns. Material also carries culture and status — a jade token is rank and authority.
* **Not:** painterly material renders as textures; any prop on the board as a sprite.

### 08_vfx — *What causal behaviour does a spiritual effect have?*
* **Study:** spell · impact · spiritual energy · formation · environment interaction · skill
  silhouette · timing · scale · dissipation.
* **Adapt:** the energy law (source → gather → focus → release → propagate → impact →
  dissipate); an effect's silhouette must read at 1× from the top-down camera; a formation
  (trận pháp) is a ground-plane design, which suits this camera exactly; restraint is the house
  style (M-15.2).
* **Not:** "more particles / more glow / more shake = better" (R-6) · wings and halos as a
  generic power sign · purple-blue as the default colour of magic.

### 09_ui_composition — *A cultivation UI that does not cover the game — how?*
* **Study:** hierarchy · spacing · icon readability · panel weight · composition · contextual UI
  · HUD density · ornament restraint.
* **Adapt:** **WORLD FIRST, not BOX FIRST** — the weight ladder and the area/centre budgets
  (`UI_UX_BIBLE.md` §3c). The UI shows what the player KNOWS (`UI_UX_BIBLE.md` §6), and because
  records in this world are artefacts written by someone with interests (`WORLD_BIBLE.md` law 6),
  the UI is never an omniscient narrator.
* **Not:** the mobile-MMORPG conventions on this board (R-7) — an MP bar for a resource no
  system owns, a skill-icon ring, a minimap, XP toasts, stacked panels — nor cultivation words
  for level (level is not cảnh giới, asserted in both languages).

### 10_camera_story_moments — *How is an important moment revealed?*
* **Study:** framing · focus · reveal · anticipation · impact · recovery · cinematic
  composition · environmental reveal · character emphasis.
* **Adapt:** the top-down camera frames, holds, pans and times; it never changes angle (M-9.4).
  Emphasis also comes from restraint — what the HUD and the world stop doing for a beat. The
  inciting event, ĐÊM VỠ MẠCH, is presented as a world cause with actors and suppressed evidence,
  in which the player leaves with **information, not power** (CL-08).
* **Not:** isometric, three-quarter or close-up shots (R-8) · cinematic movement because it is
  pretty · a chosen-one framing of the player (`01-product.md`: not a chosen one).

---

## 5. Identity is BEHAVIOUR, not decoration

**I-5.1 — Aetheria's identity lives in how things behave.** A feature can keep its xianxia
identity with its VFX turned almost off; a feature whose identity is only its VFX has none.

| Subject | Aetheria behaviour | Source |
|---|---|---|
| **Character** | martial discipline: a settled stance before release, economy of motion, a composed recovery; heterodox power visibly costs the body | `WORLD_BIBLE.md` §4.2, §8 |
| **Cultivation** | controlled breathing, stillness, internal flow; qi drawn in from the place; a realm changes perception and presence | WB law 1, `PROGRESSION_CULTIVATION_DESIGN.md` §1/§9 |
| **Qi** | purposeful: a source, a path, a destination; never ambient sparkle; unstable only where a vein is broken | WB law 1/2, CL-08 |
| **Environment** | responds SELECTIVELY to spiritual events — near a vein, under a technique, at a breakthrough — and stays still otherwise | WB law 2, M-10.2 |
| **Sect** | architecture + symbols + behaviour: allocation made visible, hierarchy in space, an internal disagreement in who stands where | WB §8, `SOCIAL_DESIGN.md` §4 |
| **NPC** | posture + social context + world awareness: a mortal, a tán tu and an outer disciple carry themselves differently, and react to rank | `PROGRESSION_CULTIVATION_DESIGN.md` §9 (NPC reaction column) |
| **UI** | restrained information architecture; shows what the player knows; never narrates as omniscient | `UI_UX_BIBLE.md` §6, WB law 6 |
| **Story** | consequence + foreshadowing + environmental reaction; mysteries kept open until their reveal order | `NARRATIVE_MASTER_PLAN.md` §9, CL-15 |

**I-5.2 — Xianxia is not a decoration layer.** Forbidden shortcut:

```
Chinese ornament + blue glow + mist + sword trail = "xianxia"
```

Required instead: **world + material culture + behaviour + motion + spiritual logic + social
context + consequence.**

---

## 6. The generic fantasy drift gate

Every major feature is reviewed against these, in prose:

```
Does this look like a generic fantasy RPG?
Does this look like a generic MMORPG?
Does this look like mobile fantasy UI?
Does it use generic spell / VFX language?
Does it use generic medieval movement?
Does it feel disconnected from cultivation and xianxia world logic?
Does it visually belong to Aetheria?
```

**I-6.1 — A bad answer means REDESIGN.** It is never fixed by more ornament, more particles,
more glow, or more red and blue. Drift is a design problem; decoration hides it.

---

## 7. The dual check: believable AND Aetheria

Every major motion is reviewed with two separate questions:

```
A. Is the motion itself believable and readable?   (D-057 — MOTION_DESIGN_CONTRACT.md)
B. Does the motion belong to Aetheria?             (D-057A — this document)
```

**I-7.1 — A is never taken as B, nor B as A.** An animation can be *believable but generic*, or
*xianxia-looking but physically nonsensical*; both fail. The target is **BELIEVABLE + READABLE +
AETHERIA.**

---

## 8. Coherence across phases — style consistency is not visual uniformity

**I-8.1 — Different systems, same world.** P12 cultivation, P15 skills, P17 NPCs, P20 story and
P22 bosses may differ in **intensity, timing, scale, colour and motion**, and must share:
* the silhouette language (32×48 cast, readable from above, one ink, one accent);
* the material language (§4, `07`);
* the motion principles (`MOTION_DESIGN_CONTRACT.md`);
* the visual hierarchy and the weight ladder (`MOTION_DESIGN_CONTRACT.md` §6, `UI_UX_BIBLE.md` §3c);
* the behavioural identity (§5).

**I-8.2 — Consistent does not mean uniform.** A quiet mountain, a sect courtyard, a dungeon, a
battlefield and a breakthrough must NOT look alike — they share a grammar, not a look:

| Situation | Intensity | Motion | What stays shared |
|---|---|---|---|
| quiet mountain | lowest | micro ambient only | silhouette, palette ramps, ink |
| sect courtyard | low | ordered, human activity | architecture expresses hierarchy |
| dungeon | mid | sparse, threatening, telegraphed | telegraph language (global) |
| battlefield | high | dense but hierarchical | priority order (M-6.1) |
| breakthrough | macro, rare | the world responds to one body | qi has a source and a direction |

---

## 9. UI reference integration

Three UI references are on record, each with a role and a limit:

| Reference | Licence / status | What it is studied for | What is never done with it |
|---|---|---|---|
| **Foozle "Lucifer RPG UI"** (`docs/design_refs/ui/source_packs/foozle_lucifer`) | CC0 1.0 · **reference only**, not promoted (D-028, D-050) | a pixel-RPG visual vocabulary: HUD elements, buttons, icon framing, interaction states | copying its HUD; its 16×16 icon density and its western-fantasy language are why it was never promoted |
| **Kenney "Fantasy UI Borders"** (`…/source_packs/second_pack`) | CC0 1.0 · **3 files promoted** to `assets/ui/kenney_borders/` (D-050) | border construction, 9-slice thinking, windows and panels — and 1-bit MASKS tinted by palette role, which is why it won the ornament slot | copying its layouts; using more of it without the D-050 measuring workflow |
| **Aetheria `09_ui_composition`** (this pack) | reference only (§2) | composition intent: hierarchy, restraint, contextual surfaces | its mobile-MMORPG conventions (R-7) |

**I-9.1 — Abstract, never assemble.** References are abstracted into the Aetheria UI language
— the `UITheme` seams and `UIPalette` tokens (`UI_UX_BIBLE.md` §3b/§8b). Copying a Foozle HUD,
copying a Kenney layout, or mechanically combining the two is forbidden; so is any collage of
packs (`06-art-assets.md`).

---

## 10. The provenance boundary

**I-10.1 — REFERENCE-ONLY and PRODUCTION never mix.** A production asset lives under `assets/`,
has a row in `docs/ASSET_LICENSES.md` with source, licence and where it is used, and is
measured before it is wired. Reference material lives under `docs/design_refs/`, is classified
in `ASSET_LICENSES.md`'s design-reference table **as reference material**, and is never
imported (`docs/.gdignore`).

**I-10.2 — Never claim what is not recorded.** The Aetheria xianxia pack's images carry no
statement of who generated them or with which rights. The owner's D-044 confirmation covered a
different pack (the painted UI tier) and does not extend to this one. Until a provenance is
recorded, the pack is **research only** — and even then it stays reference by its own README.

**I-10.3 — Promotion means re-creation.** If a future phase wants something a reference shows,
it is re-created as original project art, or sourced from a licensed pack through the normal
asset workflow — never copied, traced or cropped from a reference
(`CHARACTER_ART_BIBLE.md` §8: no unknown-licence or unclear-rights asset ever enters the project).

---

## 11. Evidence: reference evidence is not implementation evidence

**I-11.1 — Two kinds, never confused** (alongside D-057's STATE vs PIXEL, M-16.1):

| Evidence | Proves | Never used as |
|---|---|---|
| **REFERENCE** — a board, a crop, a real-world study | design intent and its research basis | proof that anything was implemented, or implemented well |
| **IMPLEMENTATION** — a capture of the running game, a playtest report | what the game actually does and shows | design rationale ("the screenshot looks fine, so the design is right") |

---

## 12. Future phase mapping

Which categories each phase studies, the Aetheria adaptation it must make, and the trap it must
avoid. This maps the *foundation* to future phases; it implements none of them. The capabilities
each phase leaves behind are in `docs/ROADMAP.md`.

| Phase | Study | Aetheria adaptation | Trap |
|---|---|---|---|
| **P12 Cultivation** | 03 · 04 · 05 · 10 | stillness and breath; qi drawn from the place; a breakthrough changes perception (macro); the level-up shares the celebration seam at mid scale | the board's realm ladder (R-1); generic power-up VFX; a level-up that looks like a breakthrough |
| **P13 Item** | 07 · 08 · 09 | pickup/use/acquisition as micro→mid feedback; items respond as their material | loot beams and rarity explosions; "+1 item" toasts |
| **P14 Equipment** | 01 · 07 | equipment changes costume and silhouette inside the 32×48 grammar | glowing gear as the power signal |
| **P15 Skill / Technique** | 02 · 04 · 08 · 10 | ONE `CAST` action whose lifecycle has prepare → channel → release → recover; element by behaviour, shape and colour; weapon-family motion | Ngũ hành elements (R-2); the fan (R-3); "spawn a ball beside a motionless figure"; glow as quality |
| **P16 Pet** | 01 · 04 · 08 | creature law (M-3.4); a summon has a source and a cost | spirit-dragon forms as generic decoration |
| **P17 NPC** | 01 · 02 · 06 | posture + social context: a mortal, a tán tu, a disciple carry themselves differently; idle variation without sync | generic villagers; identical idles |
| **P18 Dialogue** | 01 · 09 · 10 | portrait reaction and focus with restraint | chat-bubble mobile UI; a morality icon (`UI_UX_BIBLE.md` §5) |
| **P19 Quest** | 09 · 10 | contextual progress and reward feedback | "!" markers and popups everywhere |
| **P20 Story** | 10 · 05 · 06 | ĐÊM VỠ MẠCH as a world cause; foreshadow CL-15, never answer it | a chosen-one framing; answering a mystery visually |
| **P21 Dungeon** | 05 · 06 · 08 | ruins of Cổ Tích Vực as evidence that does not fit the record; formations on the ground plane | generic dungeon tropes |
| **P22 Boss** | 02 · 08 · 10 | the global telegraph language reused; phase transition and arena reaction (`COMBAT_DESIGN.md` §8) | a bespoke VFX language per boss |

---

## 13. The Reference → Original design note (mandatory for major features)

Written with D-057's deliberation record (`MOTION_DESIGN_CONTRACT.md` §13), in the feature's
`DECISIONS.md` entry or change description:

```
Reference studied:                 <category / board region / real-world source>
Observed principle:                <what was learned — a behaviour, not a look>
Aetheria adaptation:               <how canon and the bibles change it>
Gameplay purpose:                  <why the player needs it>
What was intentionally NOT copied: <the differences that matter, incl. any §2.3 conflict avoided>
```

---

## 14. Stop condition

**I-14.1 — No reference, no invented canon.** When the pack has nothing for a future feature, do
NOT invent a canonical style. Instead:

```
identify the missing design question → locate a suitable reference → analyse its behaviour and
principle → update the Aetheria reference direction if appropriate → then design
```

D-057A itself starts no asset hunt and implements no future feature.

---

## 15. Aetheria Identity Review (run after D-057's self-critique)

```
[ ] Does this belong to the same world as the previous features?
[ ] Does it feel xianxia without relying on decoration alone?
[ ] Is the motion believable?
[ ] Is the motion readable from the actual top-down camera?
[ ] Does the material behave appropriately?
[ ] Does qi behave intentionally — a source, a path, a purpose?
[ ] Does the environment react selectively?
[ ] Is the UI restrained?
[ ] Does the HUD protect gameplay space?
[ ] Is player attention correctly prioritized?
[ ] Is there meaningful contrast between stillness and action?
[ ] Is the presentation memorable without becoming noisy?
[ ] Does the feature avoid generic-fantasy shortcuts?
[ ] Does the feature avoid mobile-RPG UI conventions?
[ ] Can the player understand what happened?
[ ] Can the player infer why it happened?
[ ] Is there meaningful consequence?
[ ] Is curiosity created by information, not random spectacle?
[ ] Could the feature be seen hundreds of times without becoming exhausting?
```

---

## 16. What this contract does NOT do

It adds no gameplay system, no autoload, no networking, no Phase 12 logic, no skill or
cultivation logic, no save change and no global manager — never `UniversalVisualManager`,
`XianxiaEffectManager`, `GlobalMotionManager` or `PresentationSingleton`. D-057's second-use rule
holds unchanged: contract first, concrete use case later. The Art Bible and the UI/UX Bible
remain authoritative (§1.2).
