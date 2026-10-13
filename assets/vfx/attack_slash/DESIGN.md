# attack_slash — DESIGN

Blender-rendered VFX frame sequence: a golden technique slash as a
screen-space billboard, thrown from a clear anchor point.

## Intent

A cultivator's technique (as opposed to a mortal's palm strike — `AttackFeedback`
draws air for those, and a PHÀM striker has no qi to show) gets a real energy
arc: anticipation gathers at the hand, the arc sweeps, the impact bursts into
shards, everything dissipates. Readable at 1× gameplay scale.

## Frames

12 frames @ 12 fps = 1.0 s. `frame_00.png` … `frame_11.png`, 96×64 RGBA.

| Frames | Beat (VFX grammar) | What happens |
|---|---|---|
| 0–2 | gather | gold-white orb swells at the origin; a thin ring contracts 13 → 3.5 px toward it |
| 3–7 | release → travel | the arc sweeps −70° → +50°: gold body (r 16–26) + white-hot core (r 19–24) + 2 lagging trails |
| 8–9 | impact | flash disc pops at the arc tip; 7 gold shards fly outward, spinning |
| 10–11 | dissipate | all layers fade; `frame_11` clean |

The sweep is a rising slash in local space (−70° low-right → +50° high).

## Anchor

**(24, 38)** — the gather origin = the striker's hand/weapon point. Wire: place
the `VfxSequencePlayer` so the anchor sits on the striking point (e.g. the
`palm`/`blade` anchor `AttackFeedback` already resolves), then **rotate the
player node** to the attack facing; the arc sweeps in the node's local space.

## Timing

One-shot, 12 fps. Presentation plays it on the technique's release moment;
gameplay owns the timing (VFX follows gameplay authority).

## Palette

- Arc / shards / flash: **gold `#e8a83e`** (technique-fire gold), light `#f7d774`
- Core / orb: **white-gold `#fff6e0`**
- Per the VFX grammar: the element's own hue + white core. (Antique gold
  `#c9a865` is the UI/structure gold; energy runs brighter — the user reference
  for this effect is golden energy.)

## Camera & render

Front orthographic (elevation 0°): the slash is a screen-space billboard, the
same presentation space `AttackFeedback` draws its streaks in.
CYCLES CPU, 16 samples, seed 11, transparent film, Standard view transform.
Deterministic: re-render → byte-identical PNGs (sha256-verified).

## Provenance

Built by `tools/aetheria_art_pipeline/blender/build_vfx.py`
(`build_attack_slash`), finished with `pixel/pngout.py` (lossless).
Determinism check: rendered twice, all 12 frames sha256-identical.

## Integration

`src/presentation/vfx/vfx_sequence_player.gd` with:
`sequence_dir="res://assets/vfx/attack_slash"`, `frame_count=12`, `fps=12`,
`anchor_px=(24, 38)`, one-shot. Does NOT replace `AttackFeedback` (which stays
the causal, anchor-resolved procedural swing); this is the technique-energy
layer a skill presentation adds on release.
