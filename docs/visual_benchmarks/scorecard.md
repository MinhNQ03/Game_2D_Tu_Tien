# Aetheria visual benchmark — scorecard

Capture: `golden_combat.png`  
Reference: `aetheria_gameplay_quality_reference.png` (REFERENCE ONLY — structure and quality, never pixels)

**TOTAL 79.4 / 100 — PASS** (target >= 60; essential categories >= 50)

| Category | Weight | Score | Weighted |
|---|---:|---:|---:|
| Composition *(essential)* | 20 | 96.1 | 19.2 |
| Palette / lighting *(essential)* | 15 | 59.6 | 8.9 |
| Environment *(essential)* | 15 | 94.6 | 14.2 |
| Character silhouette *(essential)* | 15 | 94.7 | 14.2 |
| Motion / combat | 10 | 40.9 | 4.1 |
| UI hierarchy / material *(essential)* | 10 | 79.9 | 8.0 |
| VFX / spiritual language | 10 | 58.1 | 5.8 |
| Pixel readability | 5 | 100.0 | 5.0 |

## Composition — 96.1

| Measure | Capture | Reference / rule | Score | Why |
|---|---|---|---:|---|
| hud_occupancy | 0.123 | 0.237 (band 0.08-0.15) | 100.0 | share of the frame the HUD takes, against the DNA's compact band (the reference's own share includes forbidden features and is shown, not chased) |
| playfield_centre_clear | 1.0 | 1.0 | 100.0 | the middle 50%x50% (where the camera keeps the player) free of HUD |
| focal_point | [0.52, 0.52] | [0.51, 0.48] | 86.0 | where the eye lands (saliency centroid) relative to the reference's |
| action_centrality | [0.49, 0.45] | [0.54, 0.48] | 98.5 | how central the actors are, compared with the reference's staging |
| left_right_balance | 0.47 | 0.48 | 96.2 | visual weight split between the halves |

## Palette / lighting — 59.6

| Measure | Capture | Reference / rule | Score | Why |
|---|---|---|---:|---|
| warm_share | 0.028 | 0.066 | 84.5 | share of warm, saturated playfield colour (lanterns, wood, fire, skin) |
| luminance_hierarchy | [0.02, 0.38, 0.56, 0.04, 0.0] | [0.1, 0.32, 0.34, 0.23, 0.01] | 52.8 | the 5-band luminance distribution (shadows -> highlights) vs the reference |
| contrast | 0.104 | 0.181 | 36.2 | RMS luminance contrast of the playfield |
| saturation | 0.343 | 0.255 | 64.8 | mean saturation of the playfield |

## Environment — 94.6

| Measure | Capture | Reference / rule | Score | Why |
|---|---|---|---:|---|
| edge_density | 0.325 | 0.351 | 92.4 | share of strong edges in the world: richness of built and grown detail |
| colour_richness | 61 | 32 | 100.0 | distinct colours each covering >= 0.3% of the playfield: at least the reference's material variety; past twice it is counted as noise |
| detail_rhythm | 0.083 | 0.077 | 91.3 | how unevenly detail is spread: quiet ground beside busy architecture |

## Character silhouette — 94.7

| Measure | Capture | Reference / rule | Score | Why |
|---|---|---|---:|---|
| figure_ground_separation | 0.164 | 0.109 | 100.0 | colour distance between the player and the world around them |
| figure_scale | 0.133 | 0.15 | 78.9 | player height as a share of the frame |
| ink_definition | 0.092 | 0.014 | 100.0 | dark (ink) pixels defining the figure, vs the reference's linework |
| second_actor_separation | 0.136 | 0.109 | 100.0 | the second actor reads against the world too |

## Motion / combat — 40.9

| Measure | Capture | Reference / rule | Score | Why |
|---|---|---|---:|---|
| combat_focus | 0.08 | 0.285 | 27.9 | share of the frame's visual pull inside the fight |
| combat_spacing | 0.108 | 0.262 | 38.7 | distance between the combatants (staging read at a glance) |
| technique_at_the_fight | 0.561 | 1.0 | 56.1 | technique light that lands between the combatants, not elsewhere |

## UI hierarchy / material — 79.9

| Measure | Capture | Reference / rule | Score | Why |
|---|---|---|---:|---|
| surface_darkness | 0.228 | 0.242 | 94.5 | HUD surfaces are dark lacquer that light text sits on, like the reference's |
| gold_restraint | 0.01 | 0.1 | 100.0 | antique gold is structure, <= 10% of the HUD (the DNA) |
| legibility_spread | 0.444 | 0.592 | 75.1 | luminance range inside the HUD (text against its surface) |
| information_grouping | 4 | 8 | 50.0 | the HUD as a few grouped plaques (the reference's 8 include forbidden features; 4-6 is the target) |

## VFX / spiritual language — 58.1

| Measure | Capture | Reference / rule | Score | Why |
|---|---|---|---:|---|
| vfx_presence | 0.0023 | 0.0505 | 12.8 | technique light on screen at the peak; a third of the reference's spectacle is the DNA's restrained target (glow is never the design) |
| vfx_restraint | 0.0023 | 0.12 | 100.0 | the DNA cap: a technique covers <= 12% of the frame |
| element_unity | 0.491 | 0.8 | 61.4 | one element, one hue family (the DNA: never a second element's hue) |

## Pixel readability — 100.0

| Measure | Capture | Reference / rule | Score | Why |
|---|---|---|---:|---|
| pixel_crispness | 0.99 | 0.5 | 100.0 | 2x2 one-colour blocks in the playfield: integer-scaled pixel art, not resampled |

