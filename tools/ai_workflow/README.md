# Aetheria autopilot — operations manual

A local supervisor that drives Aetheria work items through **implement → validate → independent
review → fix → fresh re-review → final validation → checkpoint → push/CI → next task**, using
separate headless Claude Code CLI invocations of **one configured model** (`claude-opus-5-5`).

The supervisor (Python, stdlib only) owns the loop, the queue, the branch, the budgets and every
stop condition. A Claude invocation is a worker; its prose is never the source of truth. What is
checked: exit codes, the JSON envelope, `modelUsage` (the model that actually served the call),
structured output, real check logs, git refs and checkpoint contents.

> **Status:** CURRENT (policy 1.0.0). Not a phase; it changes no gameplay. It never closes an
> owner gate (H21-14, ART-DIR-01, ART-DIR-02) and never merges, force-pushes or touches `main`.

## 1. Two modes, one logic

| | Mode A — native (VS Code session) | Mode B — supervisor (terminal) |
|---|---|---|
| Entry | skill `aetheria-work-item` | `python3 tools/ai_workflow/aetheria_autopilot.py` |
| Reviewers | `.claude/agents/aetheria-*-reviewer.md` via the Agent tool | the same files' bodies, fresh `claude -p` per review |
| Checks | `aetheria_autopilot.py checks` | the same `Validator` |
| Review pack | `aetheria_autopilot.py review-pack` | the same `review.write_pack` |
| Guard | `.claude/settings.json` hooks | the same hooks + a narrow CLI allowlist |

## 2. Quick start (VS Code integrated terminal)

```bash
python3 tools/ai_workflow/aetheria_autopilot.py doctor          # CLI, auth, exact-model probe, Godot, gh, hooks
python3 tools/ai_workflow/aetheria_autopilot.py dry-run --campaign tools/ai_workflow/campaigns/ui-readability-2026-10.json
# the owner's explicit command to run a production campaign:
python3 tools/ai_workflow/aetheria_autopilot.py start --campaign tools/ai_workflow/campaigns/ui-readability-2026-10.json --activate --max-usd-run 40
python3 tools/ai_workflow/aetheria_autopilot.py status
python3 tools/ai_workflow/aetheria_autopilot.py resume --max-usd-run 40   # after any stop
python3 tools/ai_workflow/aetheria_autopilot.py stop [--now]
```

Windows: the same commands with `py -3`; the lock uses `msvcrt`. Captures need a display
(`$DISPLAY`, or `environment.display_fallback` when its X socket exists).

## 3. Configuration — one file

`tools/ai_workflow/autopilot_config.json` (validated on load):
- `model` — the ONE model id. Every invocation passes `--model` with it and pins Claude Code's
  auxiliary model slots to it; a call served by any other model is a `model_mismatch` stop.
- `limits` — 3 fix rounds per item (each verified by a fresh review, so ≤ 4 reviews), 10 tasks
  per run, 240 min per run (no new stage under 25 min left), 24 calls per item and 90 per run
  (the full loop is 1 + 4 x reviewers + 3 calls: 20 with four triggered reviewers, 24 with five —
  exactly the cap, so any retry stops it — 28 with six; such an item stops `invocation_budget_task`), 1 identical-
  failure retry, bounded CI polling, per-role `max_turns`/timeout (verified flags of CLI 2.1.291).
- `budget` — USD caps per task/run/campaign. A billable run REQUIRES a run cap
  (`--max-usd-run`). The figure is the CLI's `total_cost_usd`: a **list-price estimate**; on a
  subscription it is not what is billed. Parallel reviewers split the remaining cap.
- `permissions` — the worker's tool set, Bash allowlist and denylist (no commit/push/reset/
  clean/checkout/stash/rm/curl/gh/claude). Writes are path-scoped: `Edit(./<allowed>)`. The task
  prompt names the exact allowlisted check commands (absolute Godot path, no `timeout`/`~`), so a
  worker runs its tests before reporting instead of costing a fix round; up to 4 reviewers run
  in parallel and split the remaining USD cap.
- `checks` — the real project gates (lint, catalogs, docs, Godot import/parse/boot/suite, the
  eight E2E flows) with CI's `SCRIPT ERROR` and leak patterns; selected by changed paths.
- `reviewers` — ten specialists, triggered by paths; architecture and QA always run.
- `owner_gates` — read from the COMMITTED handoff documents; an uncommitted edit closes nothing.

## 4. State, statuses, lifecycle

Runtime state lives in `.aetheria-autopilot/` (git-ignored, Godot-ignored): `state.json` (+ the
previous good revision `state.json.bak`), `audit.jsonl`, `invocations/` (envelopes, redacted
prompts), `prompts/`, `items/<id>/checks/*.log`, `items/<id>/review-cN/`, `reports/<id>.md`,
`captures/`. Every write validates the schema and replaces the file atomically.

`QUEUED → IN_PROGRESS → VALIDATING → REVIEW_REQUIRED → (FIX_REQUIRED → IN_PROGRESS → …) →
VALIDATING(final) → READY_FOR_CHECKPOINT → CHECKPOINTED → COMPLETE`, plus `BLOCKED_OWNER`,
`BLOCKED_ENVIRONMENT`, `FAILED`. Illegal transitions raise; every transition carries an event id
so a replayed event never applies twice.

A work item passes only when every mandatory acceptance criterion traces to evidence
(`check:<id>` PASS, `review:<reviewer>` met, `artifact:<glob>`, `owner:<gate>` closed), no
BLOCKER/P1 is open, and every required check passed in the final, forced re-run. A BLOCKED check
(no Godot, no display) is never PASS. Unsupported findings (a file or line that does not exist)
are recorded but never drive a rewrite; a DISPUTED finding goes to a fresh reviewer.

Checkpoint commits stage the exact changed paths (verified against the index) and carry trailers
`Autopilot-Item`, `Autopilot-Checkpoint` (idempotency token), `Autopilot-Policy`
(version@fingerprint), `Autopilot-Model`. Push only branches matching `git.push_branch_patterns`,
never with force; CI is polled on the exact SHA; a draft PR is created/updated when `gh` works.

## 5. Next task

After a COMPLETE item the supervisor renders the next eligible item's 13-section prompt from the
item, the live source documents, the open gates and the prior checkpoints, then validates it
(sections present, dependencies COMPLETE, no open gate on its scope, no forbidden claim such as
"H21-14 is closed", known checks/reviewers, not a duplicate) before launching it. When the owner's
queue is exhausted and the campaign allows it, a read-only planner proposes ONE item inside the
accepted scopes; it is validated the same way and rejected (FAILED, never run) otherwise.

## 6. Stops and recovery

| Stop reason | What to do |
|---|---|
| `queue_complete` | nothing |
| `task_budget`, `wall_clock_budget`, `usd_budget`, `invocation_budget_*` | `resume` |
| `no_eligible_work_blocked` | read `status`: owner actions are listed verbatim |
| `item_failed` | read `reports/<id>.md`; fix the cause or `retry <id> --reason …` |
| `environment_*` | fix the environment (`doctor`), then `resume` |
| `environment_remote_unavailable`, `environment_remote_unverifiable` | the remote heads could not be read: a network failure or stall after 3 attempts (3 s, 10 s apart; HTTP aborts under 1 KB/s for 60 s), or at once for a refused credential / missing repository (`…_unverifiable`). The item is `BLOCKED_ENVIRONMENT` with its work kept; nothing is adopted from an unread remote. `resume` once it is readable. If it happened after a worker call, that call's spend is recorded, its result is not adopted, and the next run first proves the remote heads unchanged; if any head moved it stops `worker_wrote_git` naming the refs — an owner decision: check those refs (`git ls-remote origin`); only the owner may clear `remote_unverified` in the state, the supervisor never does |
| `unowned_changes` | the worktree holds changes no active item owns — preserved; commit or move them |
| `branch_mismatch`, `base_not_ancestor`, `checkpoint_missing` | git and state disagree; nothing was changed — reconcile by hand |
| `policy_changed_mid_run` | validate the policy change (tests + `eval`), commit it, `resume` |
| `interrupted`, `stop_requested` | `resume` |

On every start/resume the supervisor reconciles before writing: branch and base ancestry, a
checkpoint commit present in git but not in state (adopted, never duplicated), a crash between
`git add` and `git commit` (committed once), an invocation that never finished (its stage reruns
with "continue from the partial work"), checkpoints that are not in history (blocked). If
`state.json` is corrupt it uses `state.json.bak`; if both are, it refuses to run.

Owner edits made while a run is stopped are refused on resume (the tree must equal the one the
supervisor last recorded: at the stop, at a worker's end, or after checks). One window remains: a
HARD crash while a worker is mid-call — then nobody can tell the worker's partial work from an
edit made before resume, so the dirty paths are adopted and listed in the resume note. Do not
edit the worktree of a crashed run; inspect `git status` and `status` first.

The lock is an OS lock on an open descriptor: a crashed supervisor cannot leave a lock behind.
While a run holds it, the edit guard refuses edits from interactive sessions in this worktree.

## 7. Learning without retraining

No model weights change. Findings, fixer prevention rules and recurrences go to a versioned
quality-debt ledger (`export-debt`). A change to reviewer/agent policy is a `kind: policy` item and
is checkpointed only when `eval` (seeded-defect + clean cases in `eval/cases/`) scores at least the
recorded baseline; every checkpoint names its policy fingerprint; rollback is `git revert`.

## 8. Testing the orchestrator

`python3 -m unittest discover -s tools/ai_workflow/tests -t tools/ai_workflow` (138 tests) — scripted CLI
(`tests/fake_claude.py`, never presented as a real model), throwaway repos with a bare local
remote. Covers: rejection→fix→re-review→checkpoint→push→next task; cycle limit; owner gates (and a
worker trying to close one); SIGTERM mid-implementation + resume; concurrent supervisor refused;
crash after commit / between add and commit; corrupt state; untrusted checkpoint claims; unowned
changes; branch mismatch; activation; budget required; scope guard; Godot or display missing;
push failure without retry then recovery; task/USD/clock/call budgets; model mismatch,
unavailable model, missing CLI, doctor NATIVE_ONLY; unsupported/disputed/re-raised findings;
criteria without evidence; identical failure re-classified; planner accept/reject; CI failure →
second checkpoint, CI timeout; policy edit mid-run; the policy benchmark gate; git allowlist; lock
crash safety; hook guard decisions and idempotency; runner outcomes and timeout kill; the git
invariant per snapshot key (HEAD, refs, index, remote, .git and global config, evidence files);
reviewers that touch the tree; owner retry; a commit on top of a checkpoint is never pushed.
Every regression test added after an independent review was mutation-checked (red without its fix).
`test_skill_pack.py`: every project skill is uploadable to claude.ai (frontmatter agrees with
PyYAML), the index names every skill, ZIPs are byte-reproducible, the prompts name the pack.

**Skill pack.** `.claude/skills/` serves interactive sessions, workers and claude.ai; every file in
it is policy (fingerprinted). `python3 tools/ai_workflow/package_skills.py` validates and writes
the claude.ai upload ZIPs (`docs/AETHERIA_SKILL_PACK.md`).

`canary --max-usd-run N` runs the REAL CLI and model in a separate worktree on a local
`autopilot/canary-*` branch (nothing pushed) and verifies rejection → fix → re-review →
checkpoint, then an interruption and resume, from state, audit log and git history.

## 9. CodeGraph — NO-GO (measured 2026-10-17)

`@colbymchenry/codegraph` 1.6.2 (MIT; local SQLite index; telemetry on by default, disabled for the
test) was run on a scratch copy of `src/` (231 `.gd` files) plus 16 Python files as a control:
**0 GDScript files indexed**, 16/16 Python files indexed (383 nodes); `query DialoguePanel` found
nothing where `grep` finds 7 referencing files. Its documented 34 languages do not include
GDScript, `.tscn` or `.tres`. Godot-aware inspection (GodotLens LSP, `tools/code_intel.py`, grep)
stays authoritative (`docs/GDSCRIPT_CODE_INTELLIGENCE.md`). Revisit only if GDScript support ships.

## 10. Known limitations

- Same-model reviewers are independent contexts, not independent judgement; deterministic checks
  and human gates remain the authority. Subjective look and fun are owner gates.
- Cost figures are estimates; on a subscription the binding limit is the plan's usage window.
  Verified 2026-10-17: a canary hit "You've hit your session limit · resets 8:10pm"; the run
  stopped as `rate_limited` with its state intact and `resume` after the reset finished it with
  one commit per item. A campaign therefore spans several `resume`s on a Pro plan.
- Mode A (an interactive VS Code session): the reviewer agents run `claude-opus-5-5` (verified),
  but Claude Code's own background chores use Haiku unless `ANTHROPIC_DEFAULT_HAIKU_MODEL` /
  `ANTHROPIC_SMALL_FAST_MODEL` are set in your environment; Mode B always pins them.
- A worker may run project tools, and a tool it writes could in principle restore credentials
  from its own environment and push. The defences are layered, not a sandbox: the CLI allowlist,
  the edit guard, a worker environment WITHOUT git credentials (tokens and SSH agent removed, no
  global git config, no credential helper), and a before/after snapshot of local refs, the index,
  `.git` config/hooks, user git config (with includes), the remote heads and the evidence files
  that stops the run on any change. One key is left out of the `.git/config` digest: a single-line
  `vscode-merge-base` inside a `[branch "…"]` section, which VS Code's git extension writes on
  its own and git never reads (any other key, a continued value or that key elsewhere still
  stops the run). Detection is after the fact; for an OS boundary run the
  supervisor as a separate user or in a container.
- The edit guard is a second layer; the first is the CLI permission allowlist (`dontAsk` denies
  anything not pre-approved). Shell redirection to a path is checked heuristically.
