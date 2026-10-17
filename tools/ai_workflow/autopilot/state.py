"""Durable execution state: schema, legal transitions, atomic persistence, audit trail.

One JSON document (`state.json`) is the source of truth for the queue. Every write goes through
`StateStore.save`, which validates first, keeps the previous good revision as `state.json.bak`,
and replaces the file atomically. Every status change is appended to `audit.jsonl`.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any

from . import ORCHESTRATOR_VERSION, STATE_SCHEMA_VERSION
from .util import append_jsonl, atomic_write_json, now_iso, read_jsonl, redact_obj

QUEUED = "QUEUED"
IN_PROGRESS = "IN_PROGRESS"
REVIEW_REQUIRED = "REVIEW_REQUIRED"
FIX_REQUIRED = "FIX_REQUIRED"
VALIDATING = "VALIDATING"
READY_FOR_CHECKPOINT = "READY_FOR_CHECKPOINT"
CHECKPOINTED = "CHECKPOINTED"
BLOCKED_OWNER = "BLOCKED_OWNER"
BLOCKED_ENVIRONMENT = "BLOCKED_ENVIRONMENT"
FAILED = "FAILED"
COMPLETE = "COMPLETE"

STATUSES = (QUEUED, IN_PROGRESS, REVIEW_REQUIRED, FIX_REQUIRED, VALIDATING, READY_FOR_CHECKPOINT,
            CHECKPOINTED, BLOCKED_OWNER, BLOCKED_ENVIRONMENT, FAILED, COMPLETE)

TERMINAL = (COMPLETE,)
BLOCKED = (BLOCKED_OWNER, BLOCKED_ENVIRONMENT, FAILED)
ACTIVE = (IN_PROGRESS, REVIEW_REQUIRED, FIX_REQUIRED, VALIDATING, READY_FOR_CHECKPOINT, CHECKPOINTED)

_ANY_BLOCK = {BLOCKED_OWNER, BLOCKED_ENVIRONMENT, FAILED}
TRANSITIONS: dict[str, set[str]] = {
    QUEUED: {IN_PROGRESS} | _ANY_BLOCK,
    IN_PROGRESS: {VALIDATING, REVIEW_REQUIRED} | _ANY_BLOCK,
    VALIDATING: {REVIEW_REQUIRED, FIX_REQUIRED, READY_FOR_CHECKPOINT} | _ANY_BLOCK,
    REVIEW_REQUIRED: {FIX_REQUIRED, VALIDATING} | _ANY_BLOCK,
    FIX_REQUIRED: {IN_PROGRESS} | _ANY_BLOCK,
    READY_FOR_CHECKPOINT: {CHECKPOINTED} | _ANY_BLOCK,
    CHECKPOINTED: {COMPLETE, FIX_REQUIRED} | _ANY_BLOCK,
    # A blocked item only moves on through the supervisor's resume/retry path, which restores
    # the status recorded in `resume_status` (never a jump to COMPLETE).
    BLOCKED_OWNER: {QUEUED},
    BLOCKED_ENVIRONMENT: {QUEUED, IN_PROGRESS, VALIDATING, REVIEW_REQUIRED, FIX_REQUIRED,
                          READY_FOR_CHECKPOINT, CHECKPOINTED},
    FAILED: {QUEUED},
    COMPLETE: set(),
}

SEVERITIES = ("BLOCKER", "P1", "P2", "P3", "OUT_OF_SCOPE")


class StateError(Exception):
    pass


class TransitionError(StateError):
    pass


# --- schema -----------------------------------------------------------------------------------

def _req(cond: bool, msg: str, errors: list[str]) -> None:
    if not cond:
        errors.append(msg)


def validate_item(item: Any, errors: list[str]) -> None:
    if not isinstance(item, dict):
        errors.append("item is not an object")
        return
    iid = item.get("id", "?")
    for key, typ in (("id", str), ("title", str), ("status", str), ("acceptance_criteria", list),
                     ("required_checks", list), ("depends_on", list), ("human_gates", list),
                     ("history", list), ("review_cycle", int), ("findings", list),
                     ("invocations", list), ("allowed_paths", list), ("scopes", list)):
        _req(isinstance(item.get(key), typ), f"item {iid}: {key} must be {typ.__name__}", errors)
    _req(item.get("status") in STATUSES, f"item {iid}: unknown status {item.get('status')!r}", errors)
    for c in item.get("acceptance_criteria") or []:
        _req(isinstance(c, dict) and isinstance(c.get("id"), str) and isinstance(c.get("text"), str)
             and isinstance(c.get("evidence"), list) and c.get("evidence"),
             f"item {iid}: each acceptance criterion needs id, text and a non-empty evidence list", errors)
    for f in item.get("findings") or []:
        _req(isinstance(f, dict) and f.get("severity") in SEVERITIES,
             f"item {iid}: finding with bad severity {f.get('severity') if isinstance(f, dict) else f!r}", errors)
    st = item.get("status")
    if st in (CHECKPOINTED, COMPLETE):
        _req(isinstance(item.get("checkpoint_sha"), str) and len(item.get("checkpoint_sha") or "") >= 40,
             f"item {iid}: {st} requires a full checkpoint_sha", errors)
    if st == BLOCKED_OWNER:
        _req(bool(item.get("owner_action")), f"item {iid}: BLOCKED_OWNER requires owner_action", errors)


def validate_state(state: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(state, dict):
        return ["state is not an object"]
    _req(state.get("schema_version") == STATE_SCHEMA_VERSION,
         f"schema_version {state.get('schema_version')!r} != {STATE_SCHEMA_VERSION}", errors)
    _req(isinstance(state.get("revision"), int) and state["revision"] >= 0, "revision must be an int", errors)
    _req(isinstance(state.get("items"), dict), "items must be an object", errors)
    _req(isinstance(state.get("order"), list), "order must be a list", errors)
    camp = state.get("campaign")
    _req(isinstance(camp, dict), "campaign must be an object", errors)
    if isinstance(camp, dict):
        for k in ("id", "branch", "base_sha", "mode"):
            _req(isinstance(camp.get(k), str) and camp.get(k), f"campaign.{k} required", errors)
        _req(camp.get("mode") in ("bootstrap", "canary", "production", "test"), "campaign.mode invalid", errors)
    items = state.get("items") if isinstance(state.get("items"), dict) else {}
    order = state.get("order") if isinstance(state.get("order"), list) else []
    _req(sorted(order) == sorted(items.keys()), "order and items disagree", errors)
    for iid, item in items.items():
        validate_item(item, errors)
        if isinstance(item, dict):
            _req(item.get("id") == iid, f"item key {iid} != id {item.get('id')}", errors)
            for dep in item.get("depends_on") or []:
                _req(dep in items, f"item {iid} depends on unknown item {dep}", errors)
    cur = state.get("current_item")
    _req(cur is None or cur in items, f"current_item {cur!r} is not an item", errors)
    # dependency cycles
    if not errors:
        seen: dict[str, int] = {}

        def visit(n: str, stack: list[str]) -> None:
            if seen.get(n) == 1:
                errors.append("dependency cycle: " + " -> ".join(stack + [n]))
                return
            if seen.get(n) == 2:
                return
            seen[n] = 1
            for d in items[n].get("depends_on", []):
                visit(d, stack + [n])
            seen[n] = 2

        for n in items:
            visit(n, [])
    return errors


def new_item(spec: dict, source: str = "owner") -> dict:
    """Normalise an item spec from a campaign file or the planner into a state item."""
    item = {
        "id": spec["id"],
        "title": spec.get("title", spec["id"]),
        "kind": spec.get("kind", "task"),
        "source": source,
        "scopes": list(spec.get("scopes", [])),
        "objective": spec.get("objective", ""),
        "in_scope": list(spec.get("in_scope", [])),
        "out_of_scope": list(spec.get("out_of_scope", [])),
        "tasks": list(spec.get("tasks", [])),
        "constraints": list(spec.get("constraints", [])),
        "source_docs": list(spec.get("source_docs", [])),
        "acceptance_criteria": copy.deepcopy(spec.get("acceptance_criteria", [])),
        "required_checks": list(spec.get("required_checks", [])),
        "required_captures": copy.deepcopy(spec.get("required_captures", [])),
        "reviewers": list(spec.get("reviewers", [])),
        "allowed_paths": list(spec.get("allowed_paths", [])),
        "depends_on": list(spec.get("depends_on", [])),
        "human_gates": list(spec.get("human_gates", [])),
        "branch": spec.get("branch"),
        "extra_checks": dict(spec.get("extra_checks", {})),
        "status": QUEUED,
        "stage": None,
        "stage_started_clean": None,
        "resume_status": None,
        "base_sha": None,
        "checkpoint_sha": None,
        "checkpoints": [],
        "pushed_sha": None,
        "pr_url": None,
        "ci": None,
        "review_cycle": 0,
        "fix_rounds": 0,
        "findings": [],
        "pending_fixes": [],
        "validation": {},
        "checks_reused": [],
        "checks_rerun": [],
        "invocations": [],
        "usd_estimated": 0.0,
        "failure_signatures": {},
        "known_limitations": [],
        "owner_action": None,
        "prompt_path": None,
        "prompt_sha256": None,
        "stop_detail": None,
        "worker_report": None,
        "history": [],
        "applied_events": [],
    }
    return item


def empty_state(campaign: dict) -> dict:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "orchestrator_version": ORCHESTRATOR_VERSION,
        "revision": 0,
        "policy_version": campaign.get("policy_version", ""),
        "policy_fingerprint": campaign.get("policy_fingerprint", ""),
        "campaign": {
            "id": campaign["id"],
            "mode": campaign.get("mode", "production"),
            "source_file": campaign.get("source_file"),
            "source_sha256": campaign.get("source_sha256"),
            "activated_by_owner": bool(campaign.get("activated_by_owner")),
            "activated_at": campaign.get("activated_at"),
            "branch": campaign["branch"],
            "base_sha": campaign["base_sha"],
            "allow_planner_items": bool(campaign.get("allow_planner_items", False)),
            "scopes_allowed": list(campaign.get("scopes_allowed", [])),
        },
        "items": {},
        "order": [],
        "current_item": None,
        "run": None,
        "runs": [],
        "totals": {"usd_estimated": 0.0, "invocations": 0, "tasks_completed": 0},
        "quality_debt": [],
        "stop": None,
        "updated_at": now_iso(),
    }


# --- store ------------------------------------------------------------------------------------

class StateStore:
    def __init__(self, state_dir: Path):
        self.dir = Path(state_dir)
        self.path = self.dir / "state.json"
        self.bak = self.dir / "state.json.bak"
        self.audit = self.dir / "audit.jsonl"

    def ensure_dir(self) -> None:
        self.dir.mkdir(parents=True, exist_ok=True)
        # Keep Godot from importing anything the supervisor writes here (L-044), and keep git out.
        for name, body in ((".gdignore", ""), (".gitignore", "*\n")):
            p = self.dir / name
            if not p.exists():
                p.write_text(body, encoding="utf-8")

    def exists(self) -> bool:
        return self.path.exists() or self.bak.exists()

    def _read(self, path: Path) -> tuple[dict | None, list[str]]:
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return None, ["missing"]
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            return None, [f"malformed JSON: {e}"]
        errs = validate_state(data)
        return (data if not errs else None), errs

    def load(self) -> dict:
        """Load the newest VALID revision. Raises StateError with both diagnoses otherwise."""
        data, errs = self._read(self.path)
        if data is not None:
            return data
        bdata, berrs = self._read(self.bak)
        if bdata is not None:
            self.log("state_recovered_from_backup", {"primary_errors": errs[:10]})
            return bdata
        raise StateError(f"no valid state: state.json -> {errs[:5]}; state.json.bak -> {berrs[:5]}")

    def save(self, state: dict, expected_revision: int | None = None) -> dict:
        errs = validate_state(state)
        if errs:
            raise StateError("refusing to persist invalid state: " + "; ".join(errs[:10]))
        if expected_revision is not None and self.path.exists():
            cur, _ = self._read(self.path)
            if cur is not None and cur["revision"] != expected_revision:
                raise StateError(f"state revision moved underneath us: {cur['revision']} != {expected_revision}")
        self.ensure_dir()
        if self.path.exists():
            cur, cerrs = self._read(self.path)
            if cur is not None:  # never overwrite a good backup with a corrupt primary
                atomic_write_json(self.bak, cur)
        state["revision"] = int(state.get("revision", 0)) + 1
        state["updated_at"] = now_iso()
        atomic_write_json(self.path, state)
        return state

    def log(self, event: str, data: dict | None = None) -> None:
        self.ensure_dir()
        append_jsonl(self.audit, {"at": now_iso(), "event": event, **(redact_obj(data or {}))})

    def audit_events(self) -> list[dict]:
        return read_jsonl(self.audit)


def transition(state: dict, item_id: str, to: str, note: str = "", event_id: str | None = None,
               store: StateStore | None = None, **fields: Any) -> bool:
    """Apply one legal status change. Returns False (and changes nothing) when `event_id` was
    already applied — repeated hook or supervisor events never produce a second transition."""
    item = state["items"][item_id]
    if event_id and event_id in item["applied_events"]:
        return False
    frm = item["status"]
    if to not in STATUSES:
        raise TransitionError(f"unknown status {to}")
    if frm != to and to not in TRANSITIONS[frm]:
        raise TransitionError(f"{item_id}: illegal transition {frm} -> {to}")
    if to in (CHECKPOINTED, COMPLETE):
        sha = fields.get("checkpoint_sha", item.get("checkpoint_sha"))
        if not (isinstance(sha, str) and len(sha) >= 40):
            raise TransitionError(f"{item_id}: {to} without a verified checkpoint sha")
    if to == BLOCKED_OWNER and not (fields.get("owner_action") or item.get("owner_action")):
        raise TransitionError(f"{item_id}: BLOCKED_OWNER needs an owner_action")
    for k, v in fields.items():
        item[k] = v
    item["status"] = to
    rec = {"at": now_iso(), "from": frm, "to": to, "note": note[:500], "event_id": event_id}
    item["history"].append(rec)
    if event_id:
        item["applied_events"].append(event_id)
        item["applied_events"] = item["applied_events"][-200:]
    if store is not None:
        store.log("transition", {"item": item_id, **rec})
    return True


def set_stage(state: dict, item_id: str, stage: str | None, store: StateStore | None = None, **extra: Any) -> None:
    item = state["items"][item_id]
    item["stage"] = stage
    for k, v in extra.items():
        item[k] = v
    if store is not None:
        store.log("stage", {"item": item_id, "stage": stage, **{k: v for k, v in extra.items() if k != "worker_report"}})
