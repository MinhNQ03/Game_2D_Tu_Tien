# Visual benchmarks (D-062 CP11)

`aetheria_gameplay_quality_reference.png` — **REFERENCE ONLY · NON-RUNTIME · COMPOSITION /
QUALITY BENCHMARK · NOT PRODUCTION ART.** A generated gameplay mock supplied as a quality target.
It is gitignored (no recorded rights) and kept out of `res://` by `docs/.gdignore`; nothing in the
game imports it, and no production art was copied, traced, cropped or recoloured from it.

It is **not canon** and disagrees with canon in places (`XIANXIA_IDENTITY_CONTRACT.md` §2.3):
isometric projection (R-8), minimap / MP bar / skill ring / right menu column / chat (R-7, and no
multiplayer chat exists), cherry blossoms and floating cliffs as the starting world (R-9), and
"Thanh Vân Sơn" for canon "Thanh Vân Phong". The benchmark compares STRUCTURE and QUALITY, never
these features.

- `reference_annotation.json` — the reference's HUD and actor regions (measured by eye), so its
  HUD occupancy and actor scale are measured honestly.
- The scorer: `tools/aetheria_art_pipeline/validate/visual_benchmark.py` (methodology in
  `docs/AETHERIA_ART_PIPELINE.md` §Benchmark). The golden frame comes from
  `tools/capture_motion.gd -- <dir> golden` (`golden_combat.png` + `golden_combat.json`).
- `scorecard.md` / `scorecard.json` — the latest committed result.
