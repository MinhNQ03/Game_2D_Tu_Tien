# PHASE 0 EXIT CHECKLIST — Aetheria

> Gate for leaving **Phase 0 — Foundation** and starting **Phase 1 — Core**.
> Status legend: **[x]** verified · **[ ]** not done.
>
> **Verification source:** runtime items were verified by GitHub Actions. The CI run on
> commit `651c16f` (job "Foundation gates (Godot 4.7)") completed with
> `conclusion=success`, executing: import → GDScript parse check → runtime boot smoke →
> headless test suite on real Godot 4.7. Confirmed via the GitHub check-runs API.
> (The AI agent still cannot run Godot in its own shell — see D-009 — so engine-dependent
> items were verified *in CI*, not locally; that is the authoritative path.)

## Blocking checks

| # | Check | Status | Evidence / where verified |
|---|-------|--------|---------------------------|
| 1 | Project identity = `Aetheria` | [x] | `project.godot` `config/name="Aetheria"`; smoke `test_project_name_is_aetheria` |
| 2 | 2D config clean | [x] | `project.godot` reviewed; `gl_compatibility`, `canvas_items` stretch, nearest texture filter |
| 3 | No unnecessary 3D physics config | [x] | `[physics]` section removed; `grep` finds no `3d/physics_engine` (D-002) |
| 4 | Main scene declared | [x] | `application/run/main_scene="res://main.tscn"`; smoke `test_project_declares_main_scene` |
| 5 | Main scene has `Main/Systems/World/UI` | [x] | `main.tscn` reviewed; smoke `test_main_scene_enters_tree_and_is_valid` |
| 6 | Runtime headless boot passes | [x] | CI step "Runtime boot smoke" (`--quit-after 2`) succeeded on `651c16f` — project booted `main_scene`, `Main._ready()` ran, clean exit |
| 7 | Custom test runner passes | [x] | CI step "Headless test suite" succeeded on `651c16f`; also statically clean via GDScript diagnostics |
| 8 | Failure ⇒ exit code != 0 | [x] | `run_tests.gd` quits 1 on fail/empty/missing-required; fail-detection proven by `test_nested_discovery` + `test_runner_detects_failure`; the suite's non-zero-on-failure contract would have failed the CI job — the job passed, confirming the pass path |
| 9 | Nested test discovery | [x] | `_discover_tests` recursive (stack-based); `tests/unit/framework/test_nested_discovery.gd` (2 levels deep) ran as part of the green CI suite on `651c16f` |
| 10 | CI present & no swallowed failures | [x] | `.github/workflows/ci.yml` 6 gates, `set -euo pipefail`, no `\|\| true`; run on `651c16f` = `conclusion=success` (GitHub check-runs API) |
| 11 | No stale docs | [x] | Doc audit (D-013 items 1–7) fixed; `grep` for stale phrases clean |
| 12 | Character design docs exist | [x] | `docs/CHARACTER_SYSTEM.md` |
| 13 | Relationship design docs exist | [x] | `docs/RELATIONSHIP_SYSTEM.md` |
| 14 | Sect design docs exist | [x] | `docs/SECT_SYSTEM.md` (incl. §7 factions/politics) |
| 15 | World Simulation design docs exist | [x] | `docs/WORLD_SIMULATION.md` |
| 16 | Multiplayer seams documented | [x] | `docs/MULTIPLAYER_PLAN.md` (§2b tiers + character/sect/relationship/faction/world-event seams) |
| 17 | No networking dependency | [x] | `grep` finds no `MultiplayerAPI`/`MultiplayerSpawner`/`MultiplayerSynchronizer`/`rpc(` in code |
| 18 | Localization foundation documented | [x] | `.kiro/steering/07-localization.md`; keys-not-strings rule in `DATA_SCHEMA.md` |
| 19 | Performance/testing policy documented | [x] | `.kiro/steering/05-performance-testing.md`, `docs/PERFORMANCE.md`, `docs/TEST_PLAN.md` |
| 20 | Character/Sect authority contract decided | [x] | `docs/DECISIONS.md` **D-015** (roster = canonical; character fields = derived cache) |

## Supporting (non-blocking) checks

- [x] GDScript diagnostics clean on all code/config (`get_diagnostics`, zero errors).
- [x] Git hygiene: no `.godot/`, build output, logs, secrets committed (`.gitignore` +
  `git status` reviewed).
- [x] Kiro hooks valid JSON; matcher verified against current tool names
  (`fs_write|str_replace|fs_append` fired live this session); test split PostFileSave
  (parse) vs PostTaskExec (full suite) per D-016.
- [x] Decisions log current: D-002/D-004/D-006 Accepted; D-009..D-016 recorded.

## PHASE 0 STATUS

**READY FOR PHASE 1.**

All 20 blocking checks and the supporting checks are verified. Engine-dependent items
(#6–#10) were executed and passed by GitHub Actions on commit `651c16f`: the job
"Foundation gates (Godot 4.7)" ran import → parse check → runtime boot smoke → headless
test suite on real Godot 4.7 and completed with `conclusion=success`.

Phase 0 (Foundation) is **closed**. The next phase is **Phase 1 — Core**
(`docs/ROADMAP.md`), which is **not started** in this close-out.
