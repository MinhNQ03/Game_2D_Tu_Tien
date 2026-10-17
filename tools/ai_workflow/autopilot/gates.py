"""Owner gates and deterministic guards.

An owner gate is OPEN while its source document still says so. The supervisor never closes a
gate: only the owner, by changing the source document (the handoff is the authority), and the
change must not come from an autopilot checkpoint.
"""

from __future__ import annotations

import re
import subprocess
from dataclasses import dataclass
from pathlib import Path

from .util import path_matches


@dataclass
class GateStatus:
    id: str
    open: bool
    source: str
    blocks_scopes: list[str]
    owner_action: str
    detail: str


def _committed_text(cfg, rel: str) -> str:
    """The gate's authority is the COMMITTED document at HEAD: an uncommitted edit (for example a
    worker rewriting the handoff) can never close a gate. Falls back to the file outside git."""
    try:
        p = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=cfg.repo, capture_output=True, text=True, timeout=30)
        if p.returncode == 0:
            return p.stdout
    except (OSError, subprocess.TimeoutExpired):
        pass
    return (cfg.repo / rel).read_text(encoding="utf-8")


def gate_statuses(cfg) -> list[GateStatus]:
    out = []
    for g in cfg.raw.get("owner_gates", []):
        try:
            text = _committed_text(cfg, g["source"])
        except FileNotFoundError:
            # A missing authority is not evidence the gate closed; treat as OPEN.
            out.append(GateStatus(g["id"], True, g["source"], g["blocks_scopes"], g["owner_action"],
                                  "source document missing: treated as OPEN"))
            continue
        hits = re.findall(g["open_pattern"], text)
        out.append(GateStatus(g["id"], bool(hits), g["source"], g["blocks_scopes"], g["owner_action"],
                              f"{len(hits)} open marker(s) in {g['source']}"))
    return out


def open_gates(cfg) -> dict[str, GateStatus]:
    return {g.id: g for g in gate_statuses(cfg) if g.open}


def blocking_gates_for(item: dict, cfg) -> list[GateStatus]:
    """Gates that block this item: named in human_gates, or blocking one of its scopes."""
    og = open_gates(cfg)
    hit = []
    for gid in item.get("human_gates", []):
        if gid in og:
            hit.append(og[gid])
        elif gid not in {g["id"] for g in cfg.raw.get("owner_gates", [])}:
            # An item-specific human gate the config does not know (e.g. "owner-playtest-ui"):
            # nothing can satisfy it automatically, so it blocks until the owner clears it.
            hit.append(GateStatus(gid, True, "item", [], item.get("owner_action") or
                                  f"Owner must satisfy gate {gid} for {item['id']}", "item-declared human gate"))
    for g in og.values():
        if set(g.blocks_scopes) & set(item.get("scopes", [])) and g not in hit:
            hit.append(g)
    return hit


# --- deterministic guards run as checks ----------------------------------------------------------

def scope_guard(changed: list[str], item: dict, cfg) -> tuple[bool, str]:
    paths = cfg.paths
    allowed = item.get("allowed_paths") or paths["default_allowed_write"]
    problems = []
    for p in changed:
        if path_matches(p, paths["protected"]):
            problems.append(f"protected path changed: {p}")
        elif path_matches(p, paths["policy"]) and item.get("kind") != "policy":
            problems.append(f"policy path changed by a non-policy item: {p}")
        elif not path_matches(p, allowed) and not (item.get("kind") == "policy" and path_matches(p, paths["policy"])):
            problems.append(f"outside the item's allowed paths: {p}")
    if problems:
        return False, "; ".join(problems[:20])
    return True, f"{len(changed)} changed path(s) inside the allowed set"


_PHASE_STATUS_RX = re.compile(r"^[-+]\s*##\s*Phase\s+(\d+)\b(.*)$")


def owner_gate_guard(diff_text: str, cfg) -> tuple[bool, str]:
    """Refuse a diff that edits an open gate's own status line, or that marks a phase that an
    open gate blocks as started/done in docs/ROADMAP.md."""
    og = open_gates(cfg)
    problems = []
    blocked_phases = set()
    for g in og.values():
        for s in g.blocks_scopes:
            m = re.match(r"phase-(\d+)$", s)
            if m:
                blocked_phases.add(int(m.group(1)))
    current_file = None
    for line in diff_text.splitlines():
        if line.startswith("+++ b/"):
            current_file = line[6:]
            continue
        if not line.startswith(("+", "-")) or line.startswith(("+++", "---")):
            continue
        for g in og.values():
            if current_file == g.source and g.id in line and line.startswith("-") and "OPEN" in line:
                problems.append(f"{g.id}: an open-gate line in {g.source} was removed or rewritten")
        if current_file == "docs/ROADMAP.md":
            m = _PHASE_STATUS_RX.match(line)
            if m and int(m.group(1)) in blocked_phases and line.startswith("+"):
                if re.search(r"(?i)\b(done|started|in progress|closed|implemented|complete)\b", m.group(2)):
                    problems.append(f"ROADMAP marks blocked Phase {m.group(1)} as {m.group(2).strip()[:60]}")
            if line.startswith("-") and "NOT STARTED" in line and any(f"Phase {n}" in line for n in blocked_phases):
                problems.append("ROADMAP removed a NOT STARTED marker of a gate-blocked phase")
    if problems:
        return False, "; ".join(sorted(set(problems)))
    return True, f"{len(og)} open owner gate(s) untouched"


def find_forbidden_claims(text: str, cfg) -> list[str]:
    hits = []
    for pat in cfg.raw.get("planner", {}).get("forbidden_claims", []):
        for m in re.finditer(pat, text, flags=re.IGNORECASE):
            # a negated mention ("do not close H21-14", "H21-14 is not closed") is fine
            window = text[max(0, m.start() - 40):m.start()].lower()
            if any(neg in window for neg in ("not ", "never ", "no ", "n't ", "must not", "without")):
                continue
            hits.append(m.group(0))
    return hits


def describe(cfg) -> list[dict]:
    return [{"id": g.id, "open": g.open, "source": g.source, "blocks": g.blocks_scopes,
             "owner_action": g.owner_action, "detail": g.detail} for g in gate_statuses(cfg)]


def repo_rel(path: Path, repo: Path) -> str:
    try:
        return str(path.resolve().relative_to(repo.resolve()))
    except ValueError:
        return str(path)
