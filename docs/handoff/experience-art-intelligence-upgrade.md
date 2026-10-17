# Handoff — Experience, art, VFX and code-intelligence upgrade (D-075)

> **Not a phase.** A cross-cutting upgrade of the opening's delivery, its pictures and effects,
> and the agent's tooling. Phase 20 stays **DONE**; Phase 21 (Dungeon) and Phase 22 (Boss) are
> **NOT STARTED** and nothing here builds them. **H21-14 stays OPEN / OWNER REQUIRED**: every
> run below is a tool; no person has played this build.

## 1. Baseline (verified 2026-10-17)

| | |
|---|---|
| Branch | `feat/experience-art-intelligence-upgrade-v2` |
| Base | `8b450acfef6b41a91336e7ed6e18738d22f609f4` = `origin/main` (CI success) — the latest state; D-074 and the two C1 proposals (still PROPOSAL — NOT FROZEN) are in it |
| Why not the named branch | `origin/feat/experience-art-intelligence-upgrade` (14 commits, 2026-10-12/13, an earlier run) carries in its history a 1.8 MB zip of other games' screenshots and the user-owned `CLAUDE.md` / `.kiro/settings/mcp.json`, in a PUBLIC repository. The owner chose a fresh branch from `main` (2026-10-17). The old branch was read for ideas, never merged or cherry-picked; it is left untouched for the owner to delete |
| Working tree | clean; `CLAUDE.md` absent; `.kiro/settings/` absent; nothing user-owned staged |
| H21-21 | CLOSED in the handoff (Gate A §16.1) — re-read, not repeated from older text |

## 2. What the player meets now (the first-playthrough path)

| Step | Before | Now |
|---|---|---|
| Identity | three columns: looks, five names, problem / gives / costs | five CARDS (picture, name, one line) to compare; the past under the cursor told in seven parts under its banner — who you were, what happened, what you want, why Lạc Hà, your first lead, where it may go, what you bring / what it costs; the subtitle says an Origin decides no sect, weapon, path or ending |
| Vignette | one caption band on the menu backdrop, ends "the road runs through the Hoang Vực" | staged over the Origin's picture with a slow drift; a fifth step says WHY the road ends at Lạc Hà |
| Arrival | purpose: "find someone to speak with" | purpose: the Origin's own lead (two steps), then the shared beat |
| The lead | an Origin line nobody pointed at | a person who RECOGNISES who the player was (the elder knows the escort's name; the watch saw the healer watching the carter's hands) — one answer, handed over as KNOWLEDGE |
| Village business | "ask what the village needs" | "earn the village's trust"; the elder: "the watch cannot leave the treeline; you have no post … and you stop being a stranger here"; the watch pays in stone and remembers who brought what he was owed |
| Chronicle | goal | goal + why you came + the open lead |

### Each Origin, traced

| Origin | Personal problem | Why Lạc Hà | Step 1 (owner · consequence) | Step 2 | Later callback |
|---|---|---|---|---|---|
| Hộ Tiêu Thất Bại | twelve wagons burned; the ledger blames the escort | the report was sealed at the Lạc Hà outpost, the convoy's last post | the elder's greeting → `shen_convoy` → `know_convoy_report`: sealed on the word of the carter who found the ashes — the one who drove them in | the carter's knots (`te_knot`) | trail: the ruts (`ko_trail_ruts`); K-14 |
| Đệ Tử Bị Loại | failed a trial they were ready for | the one who passed, Lin Yue, was posted to Lạc Hà | `lin_rival` → `know_trial_board`: she does not know why either; Qi takes crates to Cloud Vale before each trial | the carter on Cloud Vale (`te_seats`) | trail: the examiners' knot (`ko_trail_cord`); K-15 |
| Lang Y Du Phương | a patient died of no sickness | every case worked the Lạc Hà haul | the carter's hands (`te_hands`) | the watch's greeting → `ko_haul` → `know_grey_hands` | trail: the watch's clean nails (`ko_trail_nails`); K-16 |
| Nghệ Nhân Thất Sủng | a patron's stone broke in the kiln | three-notch lots come down from the Lạc Hà woods on one cart | the crate stamp (`te_mark`) | the watch's greeting → `ko_notch` → `know_three_notch` | trail: raw-based wage stones (`ko_trail_stones`); K-17 |
| Thủ Thư Cấm Lục | the mentor vanished, pages torn | the copied mark is the Lạc Hà survey's | `lin_notation` → `know_mentor_mark`: the reassigned surveyor's hand, lately on Qi's waybills | the waybill (`te_ledger`) | trail: the second hand on "level" (`shen_trail_hand`); K-18 |

All five converge on Tề Mộc's load, the cart that breaks in the Night (K-11): the shared mystery
is reached through the player's own trouble. Nothing names who burned, bought, ordered, or why
the vein fails now (layers ≤ 2; CL-15 untouched). **No dead end**: steps never block a beat;
"something else first" leaves the greeting to come back; past the arrival the shared objective
returns and the open lead stays in the Chronicle; a greeting is ordered after the Night's and the
trail's, so it never displaces them.

## 3. Art direction, measured

| Measure (real window, 1280×720) | Reference shots | Before | After |
|---|---|---|---|
| warm-pixel share | 7–22 % | 2.7 % | 3.1–3.4 % |
| value p95 | 0.82–0.86 | 0.67 | 0.68 |
| value sd | ~0.20 | 0.143 | 0.147 |

**ART-DIR-01 (owner).** In-engine A/B in the real hub: `player_proto` rendered at 64×96 (same
physical size) beside the 32×48 sprite. Finer collar, hands and hair; a 1-screen-px outline beside a
2-px world (mixed density); ~4× the sprite cost; small gain at 1×. Recommendation: keep 32×48 /
16 px; painted tier for story and menus only (the boundary this work draws).
**ART-DIR-02 (owner).** The references are brighter and more saturated than the frozen DNA allows;
the floor was improved inside the DNA. A brighter world is a DNA change.

Assets added (provenance K12, K13): five Origin WebP (26–59 KB), three VFX strips (1.0–3.9 KB).

## 4. Code intelligence

GodotLens MCP 1.1.1 against a headless Godot 4.7.2 editor (LSP 6005 / DAP 6006), exercised by a
scripted MCP client; `tools/code_intel.py` for data. Real queries and limits:
`docs/GDSCRIPT_CODE_INTELLIGENCE.md`. Configuration is local (machine paths); an agent session
sees the server only after it is configured and restarted.

## 5. Evidence

| Gate | Result |
|---|---|
| lint (`gdscript_lint.py`) | PASS, 368 files |
| catalogs (`author_story_data.py --check`), docs (`validate_docs.py`) | up to date / clean |
| headless suite | **1276 / 1276**, 0 SCRIPT ERROR (final HEAD) |
| E2E (app, player, world, pet, npc, dialogue, quest, story) | all PASS, 0 SCRIPT ERROR (story re-run after its fix) |
| mutation | the purpose-line fix reverted → `test_a_personal_step_met_without_a_beat_moving…` red |
| determinism | Lạc Hà floor: same md5 under two hash seeds |
| CI | `8c42cf7` success (run 39001863291); final SHA in §7 |

Captures opened and judged (ephemeral, not committed): identity ×5 Origins and both looks (vi
1280×720); the Origin-of-the-run vignette (5 steps) and arrival; the hub after the floor change;
the sitting with the gather (strip); the Thunder Finger strike at its landing point (strip + full
frame, before and after the blend fix); the Night frame with the rupture's tail; the 32×48 vs 64×96
A/B. The en 1280×800 matrix and the five vignettes: §7.

## 6. Debts

| ID | What | Owner | Closes when |
|---|---|---|---|
| H21-14 | nobody has played it | the owner | §17.6 / §19.8 of the pre-21 handoff, plus: did each Origin's lead make sense, and did the first hour feel like your own errand? |
| ART-DIR-01 / 02 | §3 | the owner | a decision |
| H-ART-01 | the Origin pictures are stylised dioramas, not painted illustration; interiors are low key | art | a painter's pass, or a richer prop set in `props3d` |
| H-ART-02 | the strike's forks read white-lilac (thin lines band high); the rupture column is simple | art | a second VFX pass |
| H-NAR-01 | §6's "hook into the Night" per Origin (escorting the attacked cart, treating the first casualties …) is still only in the observations | narrative | a Night-time line per Origin |
| H-UI-01 | `UI_IDENTITY_HINT` is no longer shown (the subtitle says it); key kept, unused | UI | removed in a key-cleanup pass |

## 7. Close-out

- **Final regression on the last code commit `d4b0de4`**: `--import` rc 0, `parse_check.gd` rc 0,
  1276 / 1276 tests, all eight E2E flows PASS, 0 SCRIPT ERROR anywhere; lint 368 files clean;
  `author_story_data.py --check` up to date; `validate_docs.py` clean.
- **Captures opened** (besides §5): the en 1280×800 matrix (52 frames — the identity screen for
  all five Origins, the opening, the hub) and the five Origins' vignettes (vi 1280×720, 8 frames
  each). The en matrix showed two card defects (a third tagline row cut off, a long name running
  out of its card); fixed in `d4b0de4` and pinned by a new measurement in the layout test, which
  was red before the fix. The en 1280×800 identity screen was then captured again on the fixed
  build and opened: every card shows its whole name (marked) and its line.
- **CI**: the docs commit `489463c` failed the docs gate (`[docs] SELFTEST FAIL: full
  count==74` — the decision-index selftest pinned the count, so D-075 broke it). Reproduced
  locally, root cause fixed once in `efaa21a` (the selftest now counts the file's own headings);
  CI run 39016588494 on `efaa21a`: **success**.
- **Not run here**: the owner's playtest (H21-14); a capture of the five vignettes in English;
  `visual_benchmark.py` (the before/after numbers in §3 are this run's own measure script).
