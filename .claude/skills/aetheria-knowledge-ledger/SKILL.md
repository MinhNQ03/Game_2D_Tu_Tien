---
name: aetheria-knowledge-ledger
description: Where Aetheria learning is written so later sessions and the autopilot reuse it - lessons, decisions, performance, art experiments, debt ledger. Use after a fix, experiment or review.
---

# Aetheria knowledge ledger — learning that survives the session

No model weights change. "Learning" = a versioned, reviewable record the next invocation reads.
Use the EXISTING home for each kind of knowledge; never start a new documentation system.

## Where each finding goes
| You learned… | Write it in | Shape |
|---|---|---|
| a mistake class that could recur | `.kiro/steering/09-lessons-learned.md` | next `L-0nn`: symptom → one-line **Rule** → where fixed |
| a binding choice, a rule changed, a key renamed | `docs/DECISIONS.md` | `D-0nn` (status, date, why, what it supersedes); regenerate `docs/knowledge/DECISION_INDEX.md` via `tools/gen_decision_index.py` |
| an optimization | `docs/PERFORMANCE.md` | problem · cause · solution · impact · how measured (before/after numbers) |
| an art method tried / adopted / rejected | `docs/AETHERIA_ART_PIPELINE.md` (recipe; §13 limitations) + `docs/visual_benchmarks/` (scorecard, captures) | baseline, candidates, tool + version + settings, verdict, why |
| a contradiction between documents | `docs/CONTRADICTION_REGISTER.md` | `C-nnn` with resolution or OPEN |
| a player-visible change | `docs/CHANGELOG.md` `[Unreleased]` | date — item — what the player sees |
| a review finding, its fix and prevention | the supervisor's quality-debt ledger (automatic) | read it: `python3 tools/ai_workflow/aetheria_autopilot.py export-debt --out <file>` |
| a defect that came back | a regression test that is red on the bug first (L-046) | plus the L-entry |

A comment or doc that contradicts the code is a bug (L-014): fix it in the same change.

## Experiment record (art, pipeline, tooling)
```
Problem + evidence (numbers, capture paths) · Root-cause hypotheses · Candidates (2–3, materially
different) · Tool/model + version + config · Reproducible command · Result vs baseline (same
camera/tool, 1× in game) · Verdict: adopted / combined / rejected / deferred + why · Limits ·
Next worthwhile step
```

## Read before you start
- Scan `09-lessons-learned.md` titles for the area you are touching.
- `export-debt`: items marked `recurring` mean a workflow failure, not a one-off — fix the class.
- Prior conclusions are evidence, not dogma: re-test an inherited "cannot" before it shapes a plan
  (L-027, L-031).

## Memory vs repo
Personal, cross-project preferences may live in Claude memory; anything a headless autopilot
worker needs MUST be in the repository (workers only see the repo and `.claude/`).
