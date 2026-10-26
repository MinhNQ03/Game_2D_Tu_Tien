---
name: aetheria-autopilot
description: Operate the Aetheria autopilot supervisor - doctor, dry-run, start, status, resume, stop, retry, eval, canary. Use when asked to run, inspect, resume or stop autonomous work.
---

# Operating the Aetheria autopilot

The supervisor is `tools/ai_workflow/aetheria_autopilot.py` (manual: `tools/ai_workflow/README.md`).
It launches separate headless Claude Code invocations of the ONE configured model, owns the queue,
state, branch, budgets and stop conditions, and persists everything in `.aetheria-autopilot/`.

| Owner asks | Run |
|---|---|
| "is it ready?" | `python3 tools/ai_workflow/aetheria_autopilot.py doctor` |
| "what would it do?" | `… dry-run --campaign <file>` (executes nothing) |
| "start the campaign" | `… start --campaign <file> --activate --max-usd-run <N>` |
| "what is it doing?" | `… status` |
| "continue" | `… resume --max-usd-run <N>` |
| "stop" | `… stop` (before the next stage) or `… stop --now` |
| "try that item again" | `… retry <item> --reason "<why>"` (FAILED / BLOCKED_OWNER only) |

Rules for you, the session operating it:
- A production campaign starts ONLY on the owner's explicit command (`--activate`). Never start one
  on your own initiative, and never pass `--dangerously-skip-permissions` or edit the config to
  relax a limit or a gate.
- Do not edit the worktree while a run holds the lock; run native work in another worktree.
- Report the state from `status` and the reports in `.aetheria-autopilot/reports/`, not from memory.
- A `BLOCKED_OWNER` item names the exact owner action; relay it verbatim. Only the owner closes
  H21-14, ART-DIR-01 or ART-DIR-02, by editing and committing the source document.
