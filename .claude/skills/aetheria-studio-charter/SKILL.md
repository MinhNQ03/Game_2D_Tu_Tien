---
name: aetheria-studio-charter
description: Aetheria studio operating charter - choose the next task, root-cause, done, learn, escalate. Use when planning, picking priorities, reporting a run, or deciding if a rule should change.
---

# Aetheria studio charter — how work is chosen and finished

Full owner text: `references/CHARTER.md` (verbatim, 2026-10-20). This page is the working
summary. The charter grants NO authority by itself: activation, budgets, protected paths and
owner gates stay with the Autopilot (`tools/ai_workflow/README.md`, skill `aetheria-autopilot`).

## 1. Bootstrap (every session, before deciding anything)
- `git status --porcelain`, branch, HEAD; uncommitted work you did not make is the owner's.
- `python3 tools/ai_workflow/aetheria_autopilot.py status` and `… gates` — campaign, queue, stop
  reason, open gates (H21-14, ART-DIR-01, ART-DIR-02). Read the real files, never an old report.
- Next playable milestone: `docs/ROADMAP.md` + `docs/handoff/`. No competing roadmap.

## 2. Three kinds of rule — know which one you are looking at
| Kind | Examples | You may |
|---|---|---|
| **A. Protected invariant** | gameplay correctness, data ownership, save compatibility, collision/movement/animation contracts, licensing, secrets, protected branches, mandatory review, owner gates | change only through the authorized decision process (`docs/DECISIONS.md`) |
| **B. Evolvable design decision** | sprite size, pixel density, palette, lighting, Blender method, rig, asset format, art direction, pipeline, evaluation method | question it with evidence; propose the change with an in-engine A/B |
| **C. Measurement** | validators, benchmarks, test counts | treat as evidence, never as the definition of "good" |

A compliant-but-ugly asset is a defect in the asset, the method, the direction or the benchmark.
Frozen art baselines (ART-DIR-01/02) are the owner's call: bring the A/B, do not switch silently.

## 3. The loop
DISCOVER → PRIORITIZE → DIAGNOSE → PLAN → IMPLEMENT → VALIDATE → REVIEW → CORRECT → REVALIDATE →
CHECKPOINT → LEARN → REASSESS → NEXT. Routine work: minimum process the policy requires. One item
runs through skill `aetheria-work-item` (native) or the supervisor (Mode B).

**Prioritize** by player impact × critical-path effect × confidence ÷ cost. Order: correctness and
stability → missing pieces of the next playable milestone → blockers → high-impact feel /
readability / presentation → production capability with a demonstrated benefit → polish.
Every cycle must advance a milestone, clear a blocker, ship a player-visible improvement, or make
future delivery measurably more reliable. No arbitrary tasks to fill a queue.

## 4. Root cause, not loops
1. Reproduce; read the source, tests, previous attempts (`.kiro/steering/09-lessons-learned.md`,
   the quality-debt ledger).
2. State the likely cause AND the observation that would prove the fix.
3. Smallest intervention on the cause. Validate. Keep the evidence.
4. Two materially similar failures → change the hypothesis, not the parameters.
5. Stop an investigation that no longer pays; write down what was learned and move on.

## 5. Visual research (`CHARTER.md` §4)
Character sprites are judged not yet clear/appealing enough — an open quality problem, not a
tuning request. Consider direction, resolution, geometry, proportions, rig, lighting, material,
passes, rasterization, palette reduction and gameplay scale together. Method: baseline →
hypotheses → 2–3 materially different candidates → judge IN GAME at 1× → adopt into the pipeline
only with evidence → record recipe and limits. Craft method: skill `aetheria-visual-craft`;
commands: skill `aetheria-art-pipeline`. References: principles only, never copy or trace.
An image seen only in an interactive chat does not exist for a headless worker — say so.

## 6. Definition of DONE
Deliverable exists, is integrated, meets every acceptance criterion with evidence, passed the
mandatory checks and independent review, and is checkpointed. Visual → seen in the real window.
Gameplay → the player-facing behaviour and its regressions. Pipeline → produces a usable output
again. Supervisor → unit tests + `eval` vs baseline + safeguards intact. Time running out is not
done. Do not grow a task after its outcome; log the next improvement instead.

## 7. Escalate only for owner authority
Owner gates, frozen canon, paid budget increases, missing authorization, security exceptions,
irreversible scope. Give: the exact decision, the evidence, ≤3 options, your recommendation — then
keep doing other eligible work. Never re-ask an approval already given for the same initiative.

## 8. Never
Bypass activation, budgets, gates, protected paths or reviews; weaken a safeguard to proceed; run
a second scheduler or duplicate campaign state; treat an unavailable tool as a PASS; claim model
weights were "trained" (learning lives in the repo — skill `aetheria-knowledge-ledger`).

## 9. Report (end of every item or run)
DONE (with evidence) · what improved for the player · checks/reviews passed/failed/blocked · root
cause fixed or mitigated · what was learned and where it was written · what remains · the next
highest-value task and why · supervisor state (running / stopped + exact recovery action).

## Portability
Paths are repo-relative to `github.com/MinhNQ03/Game_2D_Tu_Tien`. Outside the repo (claude.ai web)
read them through an attached GitHub repo or uploaded files; never claim to have inspected a file
you could not open.
