# Aetheria — Visual Craft Workflow

**What this is.** The method for making a surface of the game *look designed*: a place in the
world, a character sheet, a panel, a moment of motion. It is a sequence of six stages with a
written output each, and a one-page brief that carries them. It exists because the build passed
every validator and still read as flat (handoff §19): nothing in the pipeline asked *what is
this picture about, and where does the eye go first.*

**What this is not.** It owns no rule. Every number, colour, size and limit lives in its owner
and is linked from here, never restated:

| Rule | Owner |
|---|---|
| Authority order, style DNA, world/UI pipeline, benchmark | `docs/AETHERIA_ART_PIPELINE.md`, `tools/aetheria_art_pipeline/style/aetheria_style.yaml` |
| Character proportions, faces, silhouettes | `docs/CHARACTER_ART_BIBLE.md` |
| Motion timing, phases, anchors | `docs/MOTION_DESIGN_CONTRACT.md` |
| HUD limits, panels, type, palette roles | `docs/UI_UX_BIBLE.md`, `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` |
| What the world may contain | `docs/CANON_LEDGER.md`, `docs/WORLD_BIBLE.md`, `docs/XIANXIA_IDENTITY_CONTRACT.md` |
| Provenance, import rules | `.kiro/steering/06-art-assets.md`, `docs/ASSET_LICENSES.md` |

If this file and an owner disagree, the owner is right and this file is fixed.

**When to use it.** Before any change a player will *see* that is more than a bug fix: a new or
reworked map area, landmark, prop cluster, panel, character presentation, or motion beat. A
change that only makes a validator pass does not need it; a change that makes a screen prettier
does.

---

## The six stages

Each stage ends in something written into the brief (§ Brief template). A stage with nothing to
write is a stage that was skipped.

### A — Intent

One sentence each:

1. **What is this surface about?** (the spring that bears a village's name; the person carrying the
   satchel) — a noun, not an adjective.
2. **What should the player do or understand in the first second?**
3. **What does it serve in the story or the loop?** If nothing, stop: decoration with no job is
   the first thing the pipeline's authority order ranks last.

Then the evidence that it currently fails: a real capture and one measurement (benchmark
category, a rect, a count). "It looks flat" is not evidence; "the spring is a 52×30 px basin
on the corner of the square and no line leads to it" is.

### B — Composition

Decide, in this order, and write each down:

1. **Focal point** — one. Where on the screen, and what makes it win: value contrast, isolation,
   converging lines, scale, or motion. Name which.
2. **Reading order** — first, second, third thing the eye lands on.
3. **Value plan** — where the lightest and darkest masses are. A frame whose values all sit in
   the middle has no focal point whatever its colours are.
4. **Masses before details** — group small things into a few shapes (a grove with undergrowth,
   not one tree to a lawn; a ledger, not three plates).
5. **Lines** — what leads in (a road, a runnel, a row of slots), and what stops the eye leaving.
6. **Quiet area** — what is deliberately left empty so the focal point can be seen. In the world
   this must include the HUD's protected centre and the walking lanes.
7. **What the 30° top-down view does to it** — height projects up-screen: a tall thing hides
   what is north of its base. Check every gameplay anchor and standing place behind it.

### C — Reference → original

For each reference used, one row:

`Reference → Observation (what is literally there) → Principle (why it works) → Abstraction
(the principle with the reference removed) → Aetheria adaptation (what we build, from our own
canon and pipeline) → Rejected (what we do not take, and why).`

The adaptation must be buildable by someone who has never seen the reference. Nothing is
copied, cropped, traced or recoloured; references stay out of the repository
(`docs/design_refs/` is ignored). A reference showing a feature (a minimap, a crowd, a skill
ring) is evidence about *composition*, never authorisation for the feature.

Worked rows from the first use are in § Reference notes.

### D — Production representation

How it is built, from what already exists:

- **World:** layout data (`designs/maps/<id>.yaml`) → the ground painter → scene sync; props are
  design data for the Blender pipeline. New look = new data or a new *kind* in the existing
  painter, with its ramp named beside the others. Never a hand-edited PNG, never a second
  renderer.
- **UI:** `UIPalette → UITheme → screen`. New constants are named in `UIPalette`; a screen
  builds no style of its own. Data arrives as a view from the owner that already has it.
- **Characters:** the game's own sprite through `CharacterVisualComponent`, at an integer scale.

State what existing files regenerate, and prove the others did not change (same bytes).

### E — Motion

Only where the surface has a verified motion weakness. Write the beat as

`CAUSE → INTENTION → STATE CHANGE → RESPONSE → CONSEQUENCE → RECOVERY`

and say which phase is missing today. Timing and anchors are the motion contract's; this stage
only decides *what the beat says*. A surface with no motion change says "none — not a verified
weakness".

### F — Review and measure

1. Real window, every language × every required size; open each image; look at 1× and enlarged.
2. Before/after side by side from the *same* tool and camera.
3. The measurements named in stage A, again. Report regressions as plainly as gains.
4. The validators the pipeline already has (style, determinism, benchmark) — never a score you
   assign yourself.
5. Every invariant the design depends on becomes a test, and each test is mutated once to prove
   it can fail.
6. What is still wrong, written down with an owner.

---

## Brief template

Copy into the handoff section (or the PR) for the change. Keep it to one screen.

```
VISUAL DESIGN BRIEF — <id> <surface>
Intent        : about <noun>; first second: <what the player understands>; serves <story/loop>
Evidence      : <capture>, <measurement>
Focal point   : <what, where> wins by <contrast | isolation | lines | scale | motion>
Reading order : 1 <…> 2 <…> 3 <…>
Value plan    : lightest <…>; darkest <…>
Masses/lines  : <groups>; lead-in <…>
Quiet area    : <what stays empty>
View check    : <what stands north of anything tall; anchors still reachable>
References    : <rows of stage C, or "none">
Built from    : <data / painter kind / UIPalette constants / view>; unchanged outputs: <…>
Motion        : <the beat, or "none — not a verified weakness">
Rules touched : <HUD / canon / performance / localisation> — <kept | owner decision needed>
Rejected      : <the obvious alternative, and why not>
Measure       : <before → after>; tests <names>; mutations <caught/applied>
Still wrong   : <item — owner>
```

---

## Reference notes

Analyses of the reference frames the owner supplied on 2026-10-12 (nine images from other
cultivation games; not in the repository). They are recorded as *principles*, so a later phase
can use them without the images.

| # | Reference (described) | Observation | Principle → abstraction | Aetheria adaptation | Rejected |
|---|---|---|---|---|---|
| R1 | Training yard of a starter village, top-down, HUD plaque + minimap + hotbar | Lanterns, a target and a banner ring one open yard; warm props on cool ground | A place is a *room*: an open floor with its purpose standing at the edges. Warm accents against a cool field pull the eye | A yard or court gets a floor material of its own and its props on the rim (the spring court, W1) | Minimap, hotbar, plaque HUD (HUD rule, UI-01) |
| R2 | Fenced herb plots in a grid | Repetition inside a border; each plot one colour mass | Repeated units read as *one* mass when bordered; variety inside, order outside | Paddies already do this; undergrowth gives trees the same massing | Farming as a feature (not in scope) |
| R3 | A giant spirit tree over a round altar with a burner and a crystal | Concentric paving, one vertical subject, everything else low | Concentric ground geometry *points*; one tall subject per frame | Rings of laid stone round the spring; the subject stays the water | A giant tree: at 30° top-down it would hide the road and the NPCs north of it |
| R4 | Rough prototype arena, one character, level label | Nothing competes with the character — and nothing supports it | Emptiness is not composition: a quiet area needs something to be quiet *around* | Used as the negative example for the meadow | — |
| R5 | Crowded hub plaza with a yin-yang floor, many nameplates | The floor motif survives the crowd because it is large, simple and high-contrast | A landmark on the *ground* stays readable under actors | The court is ground, not a prop: nobody can stand in front of it | Crowds, nameplate walls, any multiplayer feature |
| R6 | Side-view character sheet: figure, slots, stat column, tabs | Figure is the largest element; slots flank it; numbers in one aligned column | The subject is the biggest thing; equal things align on an edge | Satchel figure a scale step up on a full-width stage; stats as a ledger (U1) | Tabs, radar, power score, rarity colours |
| R7 | Wisteria spirit tree over a turquoise pond with white stone lamps | Three value bands: dark foliage frame, mid ground, bright water; light sits at the centre | Put the lightest value where the meaning is; frame it with the darkest | Pale court + bright water inside dark undergrowth | Pink blossom, turquoise (canon: a frontier village; palette roles) |
| R8 | 3D equipment screen: central character, radial slots, grid bag, category rail | Character lit on a dais; the bag is a separate, quieter region | A stage (ground + light) makes a figure a *presence*, not an icon | A dais under the figure; the list stays the quieter region | Radial slot ring, rarity glow, category rail |
| R9 | Martial hall courtyard, tiled roofs, stone terraces, depth blur, warm light | Depth from *overlap and steps*: terrace edge, stair, roof over wall | Depth is stacked edges with a lit top and a shadowed face | The court's near edge is shadowed, its far edge lit: a step, 1 px each | Depth-of-field blur, blossom, HD-2D lighting (no new shader framework) |

Three things every strong frame shared, and the build lacked: **one subject**, **a full value
range with the lightest value on the subject**, and **small things gathered into masses**.

---

## Where this is enforced

- `.kiro/steering/06-art-assets.md` § Visual craft — the entry point for any art change.
- `.kiro/steering/08-ai-review-protocol.md` — the pre-completion gate asks for the brief.
- The measurable parts are tests, not prose: see the tests named in each proof's brief
  (handoff §19). A principle that cannot be measured stays here as a review question.
