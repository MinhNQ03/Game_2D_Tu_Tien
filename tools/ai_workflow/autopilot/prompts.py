"""Task prompts: render from the item + live project documents, then validate before use."""

from __future__ import annotations

import re

from . import gates
from .state import COMPLETE
from .util import sha256_text

WORKER_SCHEMA = {
    "type": "object",
    "required": ["summary", "changed_paths", "criteria_claims", "tests_run", "known_limitations", "status"],
    "properties": {
        "status": {"type": "string", "enum": ["IMPLEMENTED", "NO_CHANGE_NEEDED", "BLOCKED"]},
        "summary": {"type": "string"},
        "changed_paths": {"type": "array", "items": {"type": "string"}},
        "criteria_claims": {"type": "array", "items": {
            "type": "object", "required": ["id", "claim"],
            "properties": {"id": {"type": "string"}, "claim": {"type": "string"}}}},
        "tests_run": {"type": "array", "items": {"type": "string"}},
        "known_limitations": {"type": "array", "items": {"type": "string"}},
        "blocker": {"type": ["string", "null"]},
        "blocker_kind": {"type": ["string", "null"], "enum": ["owner", "environment", None]},
        "finding_dispositions": {"type": "array", "items": {
            "type": "object", "required": ["finding_id", "disposition", "note"],
            "properties": {"finding_id": {"type": "string"},
                           "disposition": {"type": "string", "enum": ["FIXED", "DISPUTED", "OUT_OF_SCOPE"]},
                           "note": {"type": "string"}}}},
        "prevention": {"type": "array", "items": {"type": "string"}},
    },
}

PLANNER_SCHEMA = {
    "type": "object",
    "required": ["decision", "reason", "item"],
    "properties": {
        "decision": {"type": "string", "enum": ["PROPOSE", "NO_ELIGIBLE_WORK"]},
        "reason": {"type": "string"},
        "item": {"type": ["object", "null"], "properties": {
            "id": {"type": "string"}, "title": {"type": "string"}, "objective": {"type": "string"},
            "scopes": {"type": "array", "items": {"type": "string"}},
            "in_scope": {"type": "array", "items": {"type": "string"}},
            "out_of_scope": {"type": "array", "items": {"type": "string"}},
            "tasks": {"type": "array", "items": {"type": "string"}},
            "constraints": {"type": "array", "items": {"type": "string"}},
            "source_docs": {"type": "array", "items": {"type": "string"}},
            "depends_on": {"type": "array", "items": {"type": "string"}},
            "required_checks": {"type": "array", "items": {"type": "string"}},
            "allowed_paths": {"type": "array", "items": {"type": "string"}},
            "acceptance_criteria": {"type": "array", "items": {
                "type": "object", "required": ["id", "text", "evidence"],
                "properties": {"id": {"type": "string"}, "text": {"type": "string"},
                               "evidence": {"type": "array", "items": {"type": "string"}}}}},
        }},
    },
}


def _bullets(xs: list[str], empty: str = "- (none)") -> str:
    return "\n".join(f"- {x}" for x in xs) if xs else empty


def prior_work(state: dict, item: dict) -> str:
    rows = []
    if item.get("kind") == "policy" and (item.get("source") != "owner" or
                                         (state["campaign"].get("mode") == "production" and not state["campaign"].get("activated_by_owner"))):
        problems.append("a policy item must be authored by the owner in an activated campaign")
    for dep in item.get("depends_on", []):
        d = state["items"].get(dep)
        if d:
            rows.append(f"- `{dep}` {d['status']} at `{d.get('checkpoint_sha') or '-'}`: {d['title']}"
                        + (f" — limitations: {'; '.join(d.get('known_limitations', [])[:3])}" if d.get("known_limitations") else ""))
    done = [i for i in state["order"] if state["items"][i]["status"] == COMPLETE and i not in item.get("depends_on", [])]
    for i in done[-5:]:
        d = state["items"][i]
        rows.append(f"- `{i}` COMPLETE at `{d.get('checkpoint_sha')}`: {d['title']}")
    return "\n".join(rows) or "- (none: this is the first item of the campaign)"


def run_commands(cfg) -> str:
    """The exact command lines the worker's Bash allowlist accepts (`{godot} --headless --path . *`,
    `{godot} --path . *`, `{python} tools/*`): anything else — a `timeout` prefix, `~/…`, `godot4` —
    is denied and the check silently never runs."""
    g = cfg.godot_bin()
    py = cfg.python()
    lines = ["Exact commands (run them exactly like this: no `timeout`/`env` prefix, no `~`, no other",
             "Godot name; pipe only into grep, tail or head; the permission allowlist denies anything else):",
             f"- lint: `{py} tools/gdscript_lint.py`"]
    if g:
        lines += [f"- import (after adding a script/class): `{g} --headless --path . --import`",
                  f"- parse: `{g} --headless --path . -s res://tools/parse_check.gd`",
                  f"- one test file or several (path substrings): `{g} --headless --path . -s res://tests/run_tests.gd -- test_name_part`",
                  f"- whole suite: `{g} --headless --path . -s res://tests/run_tests.gd`",
                  f"- an E2E flow: `{g} --headless --path . -s res://tests/e2e/run_dialogue_flow.gd` (or run_<flow>_flow.gd)",
                  f"- a real-window capture (out-dir under /tmp: captures are evidence, never shipped files; "
                  f"no display means report it, do not work around it): "
                  f"`{g} --path . --resolution 1280x720 -s res://tools/capture_ui.gd -- vi /tmp/<out-dir>`"]
    else:
        lines.append("- Godot was not found on this machine: say so; do not claim Godot checks PASS")
    return "\n".join(lines)


def render_task_prompt(cfg, state: dict, item: dict, base_sha: str, branch: str) -> str:
    og = gates.open_gates(cfg)
    gate_lines = [f"{g.id} — OPEN ({g.source}); blocks {', '.join(g.blocks_scopes) or 'n/a'}. "
                  f"Do not work around it and never mark it closed." for g in og.values()]
    srcs = list(dict.fromkeys(item.get("source_docs", []) + cfg.raw.get("planner", {}).get("source_docs", [])))
    crit = "\n".join(f"- `{c['id']}` {c['text']} — evidence: {', '.join(c['evidence'])}"
                     for c in item["acceptance_criteria"])
    allowed = item.get("allowed_paths") or cfg.paths["default_allowed_write"]
    checks = item.get("required_checks", [])
    return f"""# Work item `{item['id']}` — {item['title']}

## Objective and scope
{item.get('objective') or item['title']}

## Verified base and branch policy
- Branch `{branch}`, verified base `{base_sha}`. Work only in this worktree, on this branch.
- Do NOT commit, push, switch branches, stash, reset, clean, rebase or merge. The supervisor
  checkpoints your work after independent review and validation.
- Preserve every file you did not intend to change.

## Source-of-truth documents (read the ones relevant to your change before editing)
{_bullets(srcs)}
The hierarchy in `.kiro/steering/` and `docs/PHASE_EXECUTION_PROTOCOL.md` wins over this prompt.

## Existing implementation and dependencies
Read the code you are about to touch, its callers and its tests before editing. Layer direction:
presentation → gameplay → domain → data (`.kiro/steering/03-architecture.md`).

## In scope
{_bullets(item.get('in_scope', []))}

## Out of scope
{_bullets(item.get('out_of_scope', []) + ['Phase 21 / Phase 22 work while H21-14 is open', 'changing frozen canon or an owner decision', 'editing .claude/, tools/ai_workflow/, CLAUDE.md, .kiro/settings/'])}

## Implementation tasks (in dependency order)
{_bullets(item.get('tasks', []), '- Plan the smallest correct change, then implement it.')}

## Acceptance criteria (defined before coding; each needs the named evidence)
{crit}

## Required checks
The supervisor will run: {', '.join(checks) or 'the checks triggered by your changed paths'} plus the
always-on gates. Run the relevant ones yourself BEFORE you report: a test you wrote but never ran
costs a whole fix round. A check you did not run is not PASS.
{run_commands(cfg)}

## Constraints
{_bullets(item.get('constraints', []) + ['data-driven, localised (vi + en) player-facing text; no hard-coded UI strings', 'no new autoload (budget frozen, D-017)', 'visual work follows .claude/skills/aetheria-visual-craft and is judged from real captures', 'never weaken or delete a valid test to get green'])}
Writable paths for this item: {', '.join(allowed)}

## Checkpoint and reporting
Finish with the structured report: what changed (exact paths), one claim per acceptance
criterion (what evidence shows it), tests you ran with their real results, and known limitations.
Report BLOCKED with the exact reason if the task cannot be done safely.

## Prior completed work
{prior_work(state, item)}

## Owner decisions that constrain this task
{_bullets(gate_lines, '- (no open owner gate)')}
"""


def render_fix_prompt(item: dict, task_prompt: str, findings: list[dict], failed_checks: dict, cycle: int) -> str:
    f_txt = "\n\n".join(
        f"### `{f['id']}` [{f['severity']}] {f['title']}\n- where: `{f.get('file')}`:{f.get('line')}\n"
        f"- evidence: {f['evidence']}\n- reproduce: {f['reproduction']}\n- recommended: {f['recommendation']}"
        + (f"\n- NOTE: this repeats `{f['repeat_of']}`, which an earlier fix did not resolve." if f.get("repeat_of") else "")
        for f in findings) or "(no review findings)"
    c_txt = "\n\n".join(f"### check `{cid}` FAILED — {r.get('reason')}\n```\n{(r.get('failure_excerpt') or '')[:3000]}\n```"
                        for cid, r in failed_checks.items()) or "(no failing checks)"
    return f"""# Fix round {cycle} for work item `{item['id']}`

Independent reviewers and the deterministic checks rejected the current change. Fix the ROOT
CAUSE of each item below. Do not weaken, skip or delete a valid test, rewrite an expected output
to match a bug, or silence a log line. If a finding is wrong, mark it DISPUTED and give concrete
evidence (file:line, a command and its output) — a fresh reviewer will judge your dispute.
Mark a finding OUT_OF_SCOPE only when it is truly outside this item's acceptance criteria.

## Findings
{f_txt}

## Failing checks
{c_txt}

Report a disposition for every finding id above in `finding_dispositions`, and in `prevention`
the rule or regression test that would stop this class of defect recurring.

---
The original task, unchanged, for reference:

{task_prompt}
"""


def render_planner_prompt(cfg, state: dict, last_report: str) -> str:
    og = gates.open_gates(cfg)
    queue = "\n".join(f"- `{i}` {state['items'][i]['status']}: {state['items'][i]['title']}" for i in state["order"])
    debt = "\n".join(f"- [{d.get('severity')}] {d.get('title')} ({d.get('source')})" for d in state.get("quality_debt", [])[-15:])
    return f"""# Plan the next work item for campaign `{state['campaign']['id']}`

You are the planner, READ-ONLY. Read the live documents below (do not rely on memory) and
propose at most ONE next work item that is eligible now, or answer NO_ELIGIBLE_WORK.

Live documents: {', '.join(cfg.raw.get('planner', {}).get('source_docs', []))}
Campaign scopes the owner accepted: {', '.join(state['campaign'].get('scopes_allowed') or ['(none listed)'])}

Open owner gates (they block their scopes; never propose closing, bypassing or pre-empting them):
{_bullets([f'{g.id}: blocks {g.blocks_scopes}; owner action: {g.owner_action}' for g in og.values()])}

Current queue:
{queue or '- (empty)'}

Quality-debt backlog (eligible as work only when inside the accepted scopes):
{debt or '- (empty)'}

Last checkpoint report:
{last_report or '(none)'}

Rules: follow the roadmap order and dependency matrix; never duplicate a COMPLETE item; never
invent canon or claim an owner approval; do not change roadmap statuses; prefer independent work
inside the accepted scopes when the next roadmap phase is gated. Acceptance criteria must name
evidence as `check:<id>`, `review:<reviewer>`, `artifact:<glob>` or `owner:<gate>`. Check ids:
{', '.join(sorted(cfg.check_specs()))}. Reviewers: {', '.join(sorted(cfg.raw.get('reviewers', {})))}.
"""


def validate_task_prompt(cfg, state: dict, item: dict, prompt: str) -> list[str]:
    problems = []
    for sec in cfg.raw.get("planner", {}).get("required_prompt_sections", []):
        if not re.search(rf"^## {re.escape(sec)}", prompt, flags=re.MULTILINE):
            problems.append(f"missing section: {sec}")
    if not item["acceptance_criteria"]:
        problems.append("no acceptance criteria")
    known = (set(cfg.check_specs()) | {"scope_guard", "owner_gate_guard"} | {c["id"] for c in item.get("required_captures", [])}
             | set(item.get("extra_checks") or {}))
    for c in item.get("required_checks", []):
        if c not in known:
            problems.append(f"required check {c} is not defined")
    for c in item["acceptance_criteria"]:
        for ev in c["evidence"]:
            kind, _, ref = ev.partition(":")
            if kind == "check" and ref not in known:
                problems.append(f"criterion {c['id']} names unknown check {ref}")
            if kind == "review" and ref not in cfg.raw.get("reviewers", {}):
                problems.append(f"criterion {c['id']} names unknown reviewer {ref}")
            if kind not in ("check", "review", "artifact", "owner"):
                problems.append(f"criterion {c['id']} has unknown evidence kind {kind}")
    if item.get("kind") == "policy" and (item.get("source") != "owner" or
                                         (state["campaign"].get("mode") == "production" and not state["campaign"].get("activated_by_owner"))):
        problems.append("a policy item must be authored by the owner in an activated campaign")
    for dep in item.get("depends_on", []):
        d = state["items"].get(dep)
        if d is None:
            problems.append(f"dependency {dep} does not exist")
        elif d["status"] != COMPLETE:
            problems.append(f"dependency {dep} is {d['status']}, not COMPLETE")
    own_text = " ".join([item.get("objective", ""), *item.get("tasks", []), *item.get("in_scope", []),
                         *[c["text"] for c in item["acceptance_criteria"]]])
    claims = gates.find_forbidden_claims(own_text, cfg)
    if claims:
        problems.append(f"forbidden claim(s): {claims[:3]}")
    blocking = gates.blocking_gates_for(item, cfg)
    if blocking:
        problems.append("blocked by open owner gate(s): " + ", ".join(g.id for g in blocking))
    # duplicate of completed work
    sig = _objective_sig(item)
    for oid in state["order"]:
        o = state["items"][oid]
        if oid != item["id"] and o["status"] == COMPLETE and _objective_sig(o) == sig:
            problems.append(f"duplicates completed item {oid}")
    allowed = set(cfg.raw.get("campaign_scopes_any", []))
    scopes_allowed = set(state["campaign"].get("scopes_allowed") or [])
    if item.get("source") == "planner" and scopes_allowed and not (set(item.get("scopes", [])) & (scopes_allowed | allowed)):
        problems.append(f"planner item scopes {item.get('scopes')} are outside the accepted campaign scopes")
    return problems


def _objective_sig(item: dict) -> str:
    text = (item.get("objective") or item.get("title") or "").lower()
    return sha256_text(re.sub(r"[^a-z0-9]+", " ", text).strip())[:16]
