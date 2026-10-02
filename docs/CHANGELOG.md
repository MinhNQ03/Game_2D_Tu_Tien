# CHANGELOG — Aetheria

All notable changes to this project are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); the project uses
[Semantic Versioning](https://semver.org/) once it ships builds.

Dates are ISO (YYYY-MM-DD).

## [Unreleased]

### Added — 2026-10-02 — Project foundation (docs & process, no gameplay)
- Steering rules in `.kiro/steering/`:
  `01-product`, `02-game-design`, `03-architecture`, `04-coding-standards`,
  `05-performance-testing`, `06-art-assets`, `07-localization`,
  `08-ai-review-protocol`.
- Core docs in `docs/`:
  `GAME_FLOW` (central flow + per-system contracts), `ARCHITECTURE` (layered design),
  `ROADMAP` (22 phases, Foundation → Multiplayer preparation), `TEST_PLAN`,
  `PERFORMANCE`, `ASSET_LICENSES`, `DATA_SCHEMA`, `SAVE_FORMAT`, `MULTIPLAYER_PLAN`,
  `DECISIONS`, `DEBUGGING`, and this `CHANGELOG`.
- `tests/` scaffold: `unit/ integration/ gameplay/ smoke/ performance/`, a `README`,
  and a placeholder headless runner `run_tests.gd`.

### Noted / flagged (from repo audit) — 2026-10-02
- Project still named `New_Game_Project` (rename to `Aetheria` planned — `DECISIONS.md`
  D-006).
- 3D physics engine (`Jolt Physics`) enabled on a 2D game — flagged for cleanup
  (`DECISIONS.md` D-002).
- `icon.svg` is the stock Godot placeholder icon — `ASSET_LICENSES.md`; replace before
  release.
- Open decisions pending: test framework (D-004), map strategy (D-003), save format
  (D-005), combat timing model (D-007), localization format (D-008).

### Not done (by design, this step)
- No gameplay implemented. `main.tscn` remains a single empty `Node2D`.
- No networking / multiplayer code.

---

## How to update
- Add changes under **[Unreleased]** grouped as Added / Changed / Fixed / Removed /
  Deprecated / Security.
- When a build is cut, replace **[Unreleased]** with a version + date and start a fresh
  Unreleased section.
- Keep entries short and factual; link to `DECISIONS.md` / `PERFORMANCE.md` for detail.
