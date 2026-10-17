"""Reviewer evaluation benchmark: seeded-defect cases (must be caught) and clean cases (must not
draw a BLOCKER/P1). A policy change to reviewer instructions is promoted only when its score is
not worse than the recorded baseline for the previous policy fingerprint.

Billable: every case is one real reviewer invocation of the configured model."""

from __future__ import annotations

import json
import re
from pathlib import Path

from . import knowledge, review
from .claude_runner import ClaudeRunner, Invocation
from .util import append_jsonl, atomic_write_json, now_iso, read_jsonl

RANK = {"BLOCKER": 4, "P1": 3, "P2": 2, "P3": 1, "OUT_OF_SCOPE": 0}


def load_cases(d: Path) -> list[dict]:
    cases = []
    for p in sorted(Path(d).glob("*.json")):
        c = json.loads(p.read_text(encoding="utf-8"))
        for k in ("id", "reviewer", "diff", "expect"):
            if k not in c:
                raise ValueError(f"{p.name}: missing {k}")
        cases.append(c)
    return cases


def score_case(case: dict, result: dict | None) -> tuple[bool, str]:
    if not result:
        return False, "no structured result"
    exp = case["expect"]
    findings = result.get("findings", [])
    if exp.get("clean"):
        bad = [f for f in findings if RANK.get(f.get("severity"), 0) >= RANK["P1"]]
        return (not bad), ("no material finding" if not bad else f"false positive: {bad[0].get('title')}")
    need = RANK[exp.get("min_severity", "P1")]
    rx = re.compile(exp["match"], re.IGNORECASE)
    for f in findings:
        text = " ".join(str(f.get(k, "")) for k in ("title", "evidence", "recommendation"))
        if RANK.get(f.get("severity"), 0) >= need and rx.search(text):
            return True, f"caught: [{f.get('severity')}] {f.get('title')}"
    return False, f"missed (needed >= {exp.get('min_severity', 'P1')} matching /{exp['match']}/)"


def case_prompt(case: dict) -> str:
    return f"""# Independent review — evaluation case `{case['id']}`

Review this change as you would a real Aetheria work item. Everything you need is inline; do not
use tools. Objective of the change: {case.get('objective', '(see diff)')}

Acceptance criteria:
{chr(10).join('- ' + c for c in case.get('criteria', [])) or '- the change does what its objective says, safely'}

Context:
{case.get('context', '(none)')}

```diff
{case['diff']}
```

Return the structured result (findings with severity, file, line, evidence, reproduction,
recommendation, confidence). Use `met: null` for criteria you cannot judge.
"""


def main(cfg, a) -> int:
    cases = load_cases(Path(a.cases))
    if a.max_usd is None:
        print("[eval] billable: pass --max-usd N (a hard cap for the whole benchmark)")
        return 6
    fp = knowledge.policy_fingerprint(cfg.repo)
    runner = ClaudeRunner(cfg, cfg.state_dir / "eval" / "invocations")
    spent, rows = 0.0, []
    for c in cases:
        remaining = a.max_usd - spent
        if remaining <= 0.05:
            print("[eval] budget exhausted; stopping (partial results are not a score)")
            return 4
        agent = cfg.raw["reviewers"][c["reviewer"]]["agent"]
        inv = Invocation(role="review", prompt=case_prompt(c), max_turns=3, timeout_seconds=600,
                         schema=review.REVIEW_SCHEMA, tools=[], append_system_prompt=review.agent_body(cfg, agent),
                         max_budget_usd=remaining, label=f"eval:{c['id']}")
        res = runner.run(inv)
        spent += res.usd
        ok, why = score_case(c, res.structured if res.ok else None)
        rows.append({"case": c["id"], "reviewer": c["reviewer"], "ok": ok, "why": why,
                     "invocation_ok": res.ok, "failure": res.failure_kind, "usd": res.usd})
        print(f"  {'PASS' if ok else 'MISS'} {c['id']:<28} {why}")
    score = sum(r["ok"] for r in rows) / len(rows) if rows else 0.0
    rec = {"at": now_iso(), "policy_fingerprint": fp, "policy_version": cfg.raw["policy_version"],
           "model": cfg.model, "score": score, "cases": rows, "usd_estimated": spent}
    d = cfg.state_dir / "eval"
    append_jsonl(d / "results.jsonl", rec)
    base_p = d / "baseline.json"
    base = json.loads(base_p.read_text(encoding="utf-8")) if base_p.exists() else None
    print(f"[eval] score {score:.2f} ({sum(r['ok'] for r in rows)}/{len(rows)}) policy {fp}; "
          f"baseline {base['score']:.2f} @ {base['policy_fingerprint']}" if base else
          f"[eval] score {score:.2f} policy {fp}; no baseline yet")
    if a.promote:
        if base is None or score >= base["score"]:
            atomic_write_json(base_p, rec)
            print("[eval] promoted as baseline")
        else:
            print("[eval] NOT promoted: worse than the baseline — keep the previous policy (git revert)")
            return 1
    return 0 if all(r["invocation_ok"] for r in rows) else 1


def latest_score(cfg, fingerprint: str) -> float | None:
    rows = [r for r in read_jsonl(cfg.state_dir / "eval" / "results.jsonl") if r.get("policy_fingerprint") == fingerprint]
    return rows[-1]["score"] if rows else None
