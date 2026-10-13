# qi_gather — DESIGN

Blender-rendered VFX frame sequence: qi visibly flows INTO the character.

## Intent

A cultivation gathering moment needs a readable cause: cyan/teal energy wisps
spiral inward from the canvas edges toward the feet point, converge, and sink.
It must read as "energy flows INTO the character" — not a permanent halo, not
an aura that lingers. One-shot with a clean end (last frame ~empty).

## Frames

16 frames @ 12 fps = 1.33 s. `frame_00.png` … `frame_15.png`, 64×64 RGBA.

| Frames | Beat (VFX grammar) | What happens |
|---|---|---|
| 0–2 | gather | 6 wisps fade in at radius ~24 px; ground glow kindles |
| 3–10 | gather → focus | the wisp ring rotates 1.5 turns while shrinking 1.0 → 0.22; glow brightens |
| 11–13 | focus | wisps converge near the feet point and fade; glow peaks, then softens |
| 14–15 | release → dissipate | a white-hot core pops at the feet point and sinks (the "into"); all alpha → 0 |

## Anchor

**(32, 40)** — the convergence point = where the character stands (feet).
Wire: place the `VfxSequencePlayer` at the character's feet world position; the
player offsets the sprite by `(-32, -40)` so the anchor sits exactly on the feet.

## Timing

One-shot, 12 fps. Trigger from presentation when the gathering starts (e.g. the
cultivation site's gather presentation); never loops on its own.

## Palette

- Wisps / glow: **qi `#85ccea`** (style role `qi`: cultivation / linh khí)
- Core: **white `#ffffff`** (VFX grammar: the element's own hue + white core)
- Emission strengths tuned so the hue survives (nothing clips to pure white
  except the sink core).

## Camera & render

Orthographic, **30° elevation = the gameplay camera** (`build_actor`), so the
swirl lies on the ground plane like everything else in the world.
CYCLES CPU, 16 samples, seed 11, transparent film, Standard view transform.
Deterministic: re-render → byte-identical PNGs (sha256-verified, see below).

## Provenance

Built by `tools/aetheria_art_pipeline/blender/build_vfx.py` (`build_qi_gather`),
finished with `pixel/pngout.py` (lossless). Determinism check: rendered twice,
all 16 frames sha256-identical.

## Integration

`src/presentation/vfx/vfx_sequence_player.gd` with:
`sequence_dir="res://assets/vfx/qi_gather"`, `frame_count=16`, `fps=12`,
`anchor_px=(32, 40)`, one-shot. Child of the gathering character/site at the
feet position, `z_index=1` (transient VFX layer).
