---
name: aetheria-work-item
description: Run one Aetheria work item natively - criteria first, implement, checks, independent reviewer agents, fix, re-review, validate, explicit-path commit. Use for any non-trivial change.
---

# Aetheria work item — the native loop

The same rules the local supervisor enforces (`tools/ai_workflow/README.md`), run by you inside
this session. The deterministic parts are the SAME commands the supervisor uses — do not re-implement
them by hand. Project rules win over this skill: `.kiro/steering/`, `docs/PHASE_EXECUTION_PROTOCOL.md`.

## 0. Preflight (before any edit)
1. `git status --porcelain` and `git branch --show-current`. Anything uncommitted that you did not
   make is the owner's: never stage, revert or overwrite it. If it overlaps your task, stop and ask.
2. `python3 tools/ai_workflow/aetheria_autopilot.py status` — if an autopilot run holds the lock,
   do not edit this worktree (the edit guard will refuse anyway).
3. `python3 tools/ai_workflow/aetheria_autopilot.py gates` — an OPEN owner gate (H21-14, ART-DIR-01/02)
   blocks its scope. Never close, bypass or pre-empt one; never write that the owner approved.
4. Read the owner docs for the area and the code you will touch, its callers and its tests.

## 1. Acceptance criteria first
Write the criteria before coding, each with the evidence that will prove it:
`check:<id>` (a configured check), `review:<reviewer>` (an agent judged it), `artifact:<glob>`,
`owner:<gate>`. Separate required deliverables from optional polish. Visual work also needs
captures (`tools/capture_ui.gd`, `tools/capture_motion.gd`, real window, vi+en, 1280×720 and 1280×800)
and follows `.claude/skills/aetheria-visual-craft`.

## 2. Implement
Smallest correct change, data-driven, localised, layer direction respected, no new autoload.

## 3. Deterministic checks
`python3 tools/ai_workflow/aetheria_autopilot.py checks` selects and runs the checks your changed
paths trigger (lint, catalogs, docs, Godot import/parse/boot/suite, the eight E2E flows) and fails
on `SCRIPT ERROR` or a leak like CI. A BLOCKED check (no Godot, no display) is not PASS — say so.

## 4. Independent review (fresh context, read-only)
1. `python3 tools/ai_workflow/aetheria_autopilot.py review-pack` writes the real diff and prints
   which reviewers your paths need.
2. Launch those agents with the Agent tool, in parallel (they are read-only):
   `aetheria-architecture-reviewer`, `aetheria-qa-reviewer`, and as triggered
   `aetheria-narrative-reviewer`, `aetheria-art-reviewer`, `aetheria-ui-ux-reviewer`,
   `aetheria-gameplay-reviewer`, `aetheria-economy-reviewer`, `aetheria-performance-reviewer`,
   `aetheria-audio-reviewer`, `aetheria-build-release-reviewer`.
   Give each: the item objective, the criteria, the pack path (`diff.patch`), the check results
   and any capture paths. Do NOT give them your conclusions as facts.
3. A finding naming a file/line that does not exist is UNSUPPORTED: record it, do not rewrite for it.

## 5. Fix and re-review — at most 3 fix rounds
Fix root causes (never weaken a valid test or rewrite an expected output to match a bug). You may
DISPUTE a finding with concrete evidence. After each fix: rerun the affected checks, then launch
NEW reviewer agents (fresh context) with the earlier findings and your dispositions. Any BLOCKER/P1
still open after round 3 → stop and report the item as FAILED with the evidence.

## 6. Final validation and decision
Rerun every required check after the last fix. Ready only when every mandatory criterion links to
evidence, no BLOCKER/P1 is open, and known limitations are written down.

## 7. Checkpoint (only if the owner's brief allows commits here)
Review `git diff` and `git status`; stage EXPLICIT paths (`git add -- <paths>`, never `-A`/`.`);
commit with a scoped message plus trailers `Autopilot-Item: <id>` and
`Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push only a feature branch; never
main, never force, never merge. Verify CI on the exact SHA before calling it CI-verified.

## 8. Report
Criteria → evidence table, checks with real exit codes, reviewers and their findings with
dispositions, limitations, and what could not be verified. A green CI is necessary, not sufficient.
