# PHASE 0 EXIT CHECKLIST — Aetheria

> Gate for leaving **Phase 0 — Foundation** and starting **Phase 1 — Core**.
> Status legend: **[x]** verified · **[~]** done but verified only statically (needs the
> CI/GitHub confirmation noted) · **[ ]** not done.
>
> Honesty rule (D-009): the AI agent has **no Godot binary** in its environment and
> cannot run Godot or GitHub Actions locally. Items needing a real engine run are marked
> **[~]** and point to CI as the authoritative check. They are **not** claimed as PASS.

## Blocking checks

| # | Check | Status | Evidence / where verified |
|---|-------|--------|---------------------------|
| 1 | Project identity = `Aetheria` | [x] | `project.godot` `config/name="Aetheria"`; smoke `test_project_name_is_aetheria` |
| 2 | 2D config clean | [x] | `project.godot` reviewed; `gl_compatibility`, `canvas_items` stretch, nearest texture filter |
| 3 | No unnecessary 3D physics config | [x] | `[physics]` section removed; `grep` finds no `3d/physics_engine` (D-002) |
| 4 | Main scene declared | [x] | `application/run/main_scene="res://main.tscn"`; smoke `test_project_declares_main_scene` |
| 5 | Main scene has `Main/Systems/World/UI` | [x] | `main.tscn` reviewed; smoke `test_main_scene_enters_tree_and_is_valid` |
| 6 | Runtime headless boot passes | [~] | CI step "Runtime boot smoke" (`--quit-after 2`); **confirm green on GitHub Actions** (D-009) |
| 7 | Custom test runner passes | [~] | CI step "Headless test suite"; statically clean via GDScript diagnostics; **confirm green on CI** |
| 8 | Failure ⇒ exit code != 0 | [x] design / [~] runtime | `run_tests.gd` quits 1 on fail/empty/missing-required; harness fail-detection proven by `test_nested_discovery` + `test_runner_detects_failure`; runtime exit code **confirm on CI** |
| 9 | Nested test discovery | [x] design / [~] runtime | `_discover_tests` recursive (stack-based); `tests/unit/framework/test_nested_discovery.gd` lives 2 levels deep; **confirm it runs on CI** |
| 10 | CI present & no swallowed failures | [x] authoring / [~] first-green | `.github/workflows/ci.yml` 6 gates, `set -euo pipefail`, no `\|\| true`; **confirm first green run** |
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

**NOT YET "READY FOR PHASE 1" — the runtime/CI items are unverified from this environment.**

All design/code/doc work is complete and statically validated. The items that cannot be
marked fully verified here are the ones that require actually running Godot (**#6, #7,
#8 runtime, #9 runtime, #10 first-green**), because the agent has no Godot binary
(D-009). They are authored correctly and must be confirmed by **one green run of
`.github/workflows/ci.yml` on GitHub Actions**.

> **PHASE 0 → READY FOR PHASE 1** the moment that CI run is green. When confirmed, flip
> items #6–#10 to [x] and set this status to **READY FOR PHASE 1**. Do not start Phase 1
> before that confirmation.
