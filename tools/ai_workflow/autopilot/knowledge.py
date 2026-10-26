"""Project-level learning without touching model weights: a versioned quality-debt and incident
ledger, recurrence detection, and policy fingerprints so every checkpoint names the rules it ran
under (and a rollback is just `git revert` of a policy commit)."""

from __future__ import annotations

import hashlib
import re
from pathlib import Path

from .util import now_iso

LEDGER_SCHEMA = 1

POLICY_GLOBS = [
    "tools/ai_workflow/autopilot_config.json",
    "tools/ai_workflow/autopilot/*.py",
    "tools/ai_workflow/hooks/*.py",
    "tools/ai_workflow/aetheria_autopilot.py",
    ".claude/agents/*.md",
    ".claude/skills/*/SKILL.md",
    ".claude/skills/README.md",
    ".claude/skills/*/references/*.md",
    ".claude/settings.json",
]


def policy_files(repo: Path) -> list[Path]:
    files: set[Path] = set()
    for g in POLICY_GLOBS:
        files.update(p for p in repo.glob(g) if p.is_file())
    return sorted(files)


def policy_fingerprint(repo: Path) -> str:
    h = hashlib.sha256()
    for p in policy_files(repo):
        h.update(str(p.relative_to(repo)).encode())
        h.update(b"\0")
        h.update(p.read_bytes())
        h.update(b"\0")
    return h.hexdigest()[:16]


def _category(f: dict) -> str:
    words = re.sub(r"[^a-z0-9 ]+", " ", f.get("title", "").lower()).split()
    stop = {"the", "a", "an", "is", "of", "in", "to", "and", "not", "for", "on", "with", "does", "no"}
    key = " ".join(w for w in words if w not in stop)[:60]
    return f"{f.get('role', '?')}:{key}"


def record(state: dict, item_id: str, f: dict, kind: str, policy_version: str) -> dict:
    """Add a finding to the ledger (dedup by fingerprint per item); mark recurrence across items."""
    ledger = state.setdefault("quality_debt", [])
    cat = _category(f)
    for e in ledger:
        if e["fingerprint"] == f.get("fingerprint") and e["item"] == item_id:
            return e
    recurrences = sorted({e["item"] for e in ledger if e["category"] == cat and e["item"] != item_id})
    entry = {
        "schema": LEDGER_SCHEMA, "at": now_iso(), "item": item_id, "kind": kind,
        "fingerprint": f.get("fingerprint"), "category": cat, "severity": f.get("severity"),
        "title": f.get("title"), "source": f"{f.get('role')} review" if f.get("role") else f.get("source", "?"),
        "file": f.get("file"), "line": f.get("line"), "evidence": (f.get("evidence") or "")[:600],
        "prevention": f.get("prevention"), "policy_version": policy_version,
        "recurring": bool(recurrences), "seen_in": recurrences + [item_id], "status": "OPEN",
    }
    ledger.append(entry)
    if recurrences:
        for e in ledger:
            if e["category"] == cat:
                e["recurring"] = True
                e["seen_in"] = sorted(set(e.get("seen_in", [])) | {item_id})
    return entry


def classify(entry: dict) -> str:
    if entry.get("recurring") and len(entry.get("seen_in", [])) >= 2:
        return "recurring-workflow-failure"
    if entry.get("kind") == "out_of_scope":
        return "cross-phase-risk"
    return "one-off"


def export_markdown(state: dict) -> str:
    rows = ["# Autopilot quality-debt and incident ledger", "",
            f"Campaign `{state['campaign']['id']}` — exported {now_iso()}.", "",
            "| # | Severity | Class | Item | Title | Where | Prevention | Status |",
            "|---|---|---|---|---|---|---|---|"]
    for i, e in enumerate(state.get("quality_debt", []), 1):
        where = f"`{e.get('file')}:{e.get('line')}`" if e.get("file") else "—"
        rows.append(f"| {i} | {e.get('severity')} | {classify(e)} | `{e['item']}` | {str(e.get('title')).replace('|', '/')} "
                    f"| {where} | {str(e.get('prevention') or '—').replace('|', '/')} | {e.get('status')} |")
    return "\n".join(rows) + "\n"
