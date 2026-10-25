# Aesthetic vision: why Aetheria reads as "chán" and what fixes it

Source: the owner's survey of a released browser tu-tiên game (Cổ Tiên Lộ, 2026-10-21; 13 shots
and notes kept outside the repo, in `docs/design_refs/cotienlo_2026_10_21/`, gitignored). We
take PRINCIPLES only. No asset, picture, UI kit, data or line of text is copied.

## 1. Measurement (2026-10-25)

Play area only: the top 22 % and bottom 18 % of the frame (HUD, dialogue) are cut off.
Values are HSV, 0–1. "warm" is the share of pixels with saturation > 0.25, value > 0.25 and
a red-to-orange hue. "centre/all" is the luminance of the middle 40 % divided by the
luminance of the whole frame.

| Shot | v mean | v sd | p5 | p95 | sat | warm | centre/all |
|---|---|---|---|---|---|---|---|
| Aetheria hub, `vi_1280x720_05_hub_gameplay` | 0.49 | 0.13 | 0.29 | 0.70 | **0.29** | **2.0 %** | **1.20** |
| Reference, literary dialogue | 0.33 | 0.13 | 0.16 | 0.56 | 0.15 | 4.4 % | 1.35 |
| Reference, story event | 0.33 | 0.12 | 0.17 | 0.55 | 0.14 | 2.9 % | 1.35 |
| Reference, camera and follower | 0.27 | 0.12 | 0.13 | 0.50 | 0.15 | 2.6 % | 1.25 |
| Reference, character creation (painted menu) | 0.67 | 0.30 | 0.16 | 0.95 | 0.26 | 12.1 % | 1.32 |

What the numbers say:
- The gameplay difference is **mood, not brightness**. The reference play area is darker and
  has about half our saturation. Its colour lives on the actors and the FX, not on the ground.
- The reference pulls light to the centre: a falloff toward the edges plus mist. Ours is lit
  evenly from edge to edge, so no point on screen draws the eye.
- Our warm share (2.0 %) sits below the DNA band (3–22 %): there is no warm practical light.
- The painted menu tier is where the reference is bright and saturated. That matches our own
  split: painted for menus and story, muted pixel art for play.

## 2. Gap list, in order of payoff

| # | Gap in Aetheria | Principle | Where it belongs |
|---|---|---|---|
| 1 | One even mid-green ground; no mood | Presentation grade (mute the ground, edge falloff), drifting mist and motes, one warm practical per scene | presentation layer over the world; time of day and story state may drive it. Not a palette change. |
| 2 | Actors are about the same value and saturation as the floor | Actors carry the darkest darks and the cleanest accents; a soft contact shadow; name plates on NPCs who talk or give quests | sprite pipeline (values), world UI |
| 3 | The dialogue box is a generic slate panel; no speaker on screen | A material frame in Aetheria's own language, a speaker name or portrait, literary voice; the HUD gives way while someone talks | UITheme roles, dialogue view |
| 4 | Story beats change text only | Every story cue gets a visible world reaction (a ring of light, falling dust, a door closing) played by the VFX player on the existing cue | VFX pipeline (§10b) |
| 5 | FX and UI have no signature | One recognisable Aetheria motif for the frame, FX and icons | art direction; bring an A/B to the owner |
| 6 | The camera sits far out; actors are small | A camera that frames the player and the active NPC. 64×96 sprites are the ART-DIR-01 owner question. | camera; owner gate ART-DIR-01 |

## 3. What not to take from the reference
- Not its parchment, scroll or jade look, and not its "cổ" (gu) gameplay loop.
- Not a HUD or dialogue that covers half the screen. Our budget stays at HUD ≤ 15 %.
- Not progress stored only in the browser. This is a design lesson, not an art one.

## 4. Owner gates this touches
- ART-DIR-02 (world palette brightness): gap 1 MUTES the ground, which the frozen DNA already
  asks for. It is not a brighter world, so it does not need ART-DIR-02. Still show the owner a
  before and after.
- ART-DIR-01 (64×96): gap 6 may need it. Do not change the cell size; bring evidence.
