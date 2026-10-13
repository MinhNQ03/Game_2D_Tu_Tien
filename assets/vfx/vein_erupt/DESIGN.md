# vein_erupt — DESIGN

Blender-rendered VFX frame sequence: the broken vein's ERUPTION event.

## Intent

`VeinDisturbanceFeedback` draws the vein's ambient *beat* (a pale ring every few
seconds — quiet by design, M-4.7). This sequence is the rare *event*: the
fissure glows, cracks open, crystal shards burst upward inside a light pillar,
then everything settles into embers. It upgrades the procedural feedback with
a real rendered event layer; the ambient beat is untouched.

## Frames

20 frames @ 12 fps = 1.67 s. `frame_00.png` … `frame_19.png`, 128×128 RGBA.

| Frames | Beat (VFX grammar) | What happens |
|---|---|---|
| 0–5 | before | ground glow breathes (faint); 4 jade cracks fade in around the fissure |
| 6–13 | during | 9 hex crystals (teal shell, white core glowing through) burst 60–88 px upward, tumbling; the light pillar (r 9, h 95) grows and blazes; ground glow flares |
| 14–19 | after | shards sink back and fade; pillar gone; 10 embers drift up and out; glow settles; `frame_19` clean |

## Anchor

**(64, 92)** — the fissure point on the ground. Wire: `VeinDisturbanceFeedback`
already sits at the site origin; its `erupt()` plays this sequence through a
`VfxSequencePlayer` child with `anchor_px=(64, 92)`, so the fissure lands on the
site's ground point.

## Timing

One-shot, 12 fps. `erupt()` is presentation-only: WHEN a disturbance event
happens is gameplay's decision; this only shows it. No-op on a STEADY site (a
steady vein does not erupt).

## Palette

- Shards / pillar / glow / embers: **qi `#85ccea`**
- Cracks: **jade `#5cc79e`**
- Cores: **white `#ffffff`** (VFX grammar: hue + white core)
- Same family as `VeinDisturbanceFeedback.QI_COLOUR` (pale jade) — the event
  and the beat are the same qi, never a second hue.

## Camera & render

Orthographic, **30° elevation = the gameplay camera**: the eruption rises along
world +Z and the glow sits on the ground plane.
CYCLES CPU, 24 samples, seed 11, transparent film, Standard view transform.
Deterministic: re-render → byte-identical PNGs (sha256-verified).

## Provenance

Built by `tools/aetheria_art_pipeline/blender/build_vfx.py`
(`build_vein_erupt`), finished with `pixel/pngout.py` (lossless).
Determinism check: rendered twice, all 20 frames sha256-identical.

## Integration

`VeinDisturbanceFeedback.erupt()` → `VfxSequencePlayer`:
`sequence_dir="res://assets/vfx/vein_erupt"`, `frame_count=20`, `fps=12`,
`anchor_px=(64, 92)`, one-shot, `z_index=1`. The ambient pulse (`advance()`)
is unchanged; the eruption is an additional layer for the disturbance event.
