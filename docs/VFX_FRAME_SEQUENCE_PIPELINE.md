# VFX Frame-Sequence Pipeline — Aetheria (D-074 art pass)

Blender-rendered transparent PNG frame sequences for qi, attack, and world-event VFX.
Blender is a BUILD tool; the game loads only PNGs + effect definitions.

## Environment (verified 2026-10-13)

| Item | Value |
|---|---|
| Blender | 5.2.2 LTS at `~/workspace/.local/blender-5.2.2-linux-x64/blender` |
| EEVEE headless | BLOCKED: `libEGL.so.1` missing, no sudo — fails with "Couldn't open libEGL.so.1" |
| EEVEE under Xvfb | WORKS: `xvfb-run -a -s "-screen 0 1280x720x24" blender -b -P …` (Mesa llvmpipe) |
| CYCLES headless | WORKS (CPU): `scene.render.engine = 'CYCLES'`, 16–24 samples, fixed seed |

**Which to use:** The character/prop pipeline (`build_actor.py`, `build_props.py`) needs
`ShaderToRGB` (EEVEE-only) for its light pass — use EEVEE under Xvfb. The VFX renderer
(`blender/build_vfx.py`) uses emission-only materials — CYCLES headless works and is simpler.

## VFX renderer: `tools/aetheria_art_pipeline/blender/build_vfx.py`

Parametric poses from the frame index (no keyframes, no RNG):
- Fixed seed (11), emission-only materials, transparent film, `Standard` view transform
- Output: `frame_00.png` … numbered PNGs + per-effect DESIGN.md
- PNGs via `tools/aetheria_art_pipeline/pixel/pngout.py` (lossless, correct alpha)

## Sequences (`assets/vfx/`, each with DESIGN.md + Godot `.import`)

| Effect | Frames | Canvas | Anchor | Description |
|---|---|---|---|---|
| `qi_gather/` | 16 | 64×64 | (32, 40) | Cyan/teal wisps spiral inward (1.5 turns) to feet point, converge, sink as white-hot core. One-shot, clean end. |
| `attack_slash/` | 12 | 96×64 | (24, 38) | Golden slash: gather (orb + ring) → arc sweeps −70°→+50° → impact (flash + 7 shards) → dissipate. Rotate node to aim. |
| `vein_erupt/` | 20 | 128×128 | (64, 92) | Before (faint glow + jade cracks) → during (9 hex crystals burst upward in light pillar) → after (embers + settling glow). Palette matches `VeinDisturbanceFeedback.QI_COLOUR`. |

## Integration

- `src/presentation/vfx/vfx_sequence_player.gd` — generic player: one-shot (`finished`
  signal) or loop, pins the documented anchor pixel at its position, `z_index = 1`,
  no `_process` when idle. Never self-triggers (gameplay authority respected).
- `VeinDisturbanceFeedback.erupt()` — plays `vein_erupt` once at the fissure; no-op on
  STEADY veins. The existing procedural beat is untouched (M-4.7 ambient scale).
- qi_gather/attack_slash wiring: see per-effect DESIGN.md files.

## Validation (all evidenced 2026-10-13)

- **Determinism:** 48/48 frames byte-identical on re-render (sha256).
- **Alpha:** all corners alpha=0, zero opaque-black pixels, clean ends.
- **Visual:** contact sheets reviewed; slash gather centroid measured at (23.5, 37.4)
  vs documented (24, 38).
- **In-game:** Xvfb captures at 1280×720 show all three playing at 1×.
- **Tests:** 10/10 (8 player + 2 erupt), lint PASS, parse PASS.

## Reproducing

```bash
# VFX sequences (CYCLES headless)
/usr/bin/python3 tools/aetheria_art_pipeline/build.py resolve vfx_qi_gather  # if needed
EGL_PLATFORM=surfaceless ~/workspace/.local/blender-5.2.2-linux-x64/blender \
  -b -P tools/aetheria_art_pipeline/blender/build_vfx.py -- qi_gather

# Character/prop pipeline (EEVEE under Xvfb)
xvfb-run -a -s "-screen 0 1280x720x24" \
  ~/workspace/.local/blender-5.2.2-linux-x64/blender \
  -b -P tools/aetheria_art_pipeline/blender/cli.py -- player_proto
/usr/bin/python3 tools/aetheria_art_pipeline/build.py pixel player_proto
```
