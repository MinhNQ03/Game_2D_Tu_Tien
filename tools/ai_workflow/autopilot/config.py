"""Load and validate the single autopilot configuration file."""

from __future__ import annotations

import json
import os
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Any

CONFIG_RELPATH = "tools/ai_workflow/autopilot_config.json"


class ConfigError(Exception):
    pass


def _require(cond: bool, msg: str) -> None:
    if not cond:
        raise ConfigError(msg)


def _positive_int(d: dict, key: str, where: str) -> None:
    v = d.get(key)
    _require(isinstance(v, int) and not isinstance(v, bool) and v > 0, f"{where}.{key} must be a positive integer")


def validate_config(cfg: dict) -> None:
    _require(cfg.get("schema_version") == 1, "schema_version must be 1")
    _require(isinstance(cfg.get("policy_version"), str) and cfg["policy_version"], "policy_version required")
    model = cfg.get("model")
    _require(isinstance(model, str) and model.strip() == model and model, "model must be one exact model id")
    lim = cfg.get("limits") or {}
    for k in ("max_review_fix_cycles", "max_tasks_per_run", "wall_clock_minutes_per_run",
              "max_invocations_per_task", "max_invocations_per_run", "ci_poll_timeout_seconds",
              "ci_poll_interval_seconds", "max_planner_generated_items_per_run"):
        _positive_int(lim, k, "limits")
    _require(isinstance(lim.get("max_identical_failure_retries"), int) and lim["max_identical_failure_retries"] >= 0,
             "limits.max_identical_failure_retries must be >= 0")
    _require(lim["max_review_fix_cycles"] <= 10, "limits.max_review_fix_cycles is capped at 10")
    inv = lim.get("invocation") or {}
    for role in ("implement", "fix", "review", "plan", "probe"):
        _require(role in inv, f"limits.invocation.{role} missing")
        _positive_int(inv[role], "max_turns", f"limits.invocation.{role}")
        _positive_int(inv[role], "timeout_seconds", f"limits.invocation.{role}")
    bud = cfg.get("budget") or {}
    for k in ("max_usd_per_task", "max_usd_per_run", "max_usd_per_campaign"):
        v = bud.get(k)
        _require(v is None or (isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0),
                 f"budget.{k} must be null or a positive number")
    git = cfg.get("git") or {}
    _require(isinstance(git.get("protected_branches"), list) and git["protected_branches"], "git.protected_branches")
    _require(isinstance(git.get("push_branch_patterns"), list), "git.push_branch_patterns")
    for pat in git["push_branch_patterns"]:
        _require(pat not in git["protected_branches"], f"push pattern {pat!r} names a protected branch")
    paths = cfg.get("paths") or {}
    for k in ("state_dir", "protected", "policy", "default_allowed_write"):
        _require(k in paths, f"paths.{k} missing")
    _require(".aetheria-autopilot/**" in paths["protected"] or paths["state_dir"] + "/**" in paths["protected"],
             "the state directory must be protected from worker edits")
    checks = cfg.get("checks") or {}
    _require(bool(checks), "checks must not be empty")
    for cid, spec in checks.items():
        _require(isinstance(spec, dict), f"checks.{cid} must be an object")
        _require(("cmd" in spec) or ("cmd_sequence" in spec) or ("e2e" in spec), f"checks.{cid} has no command")
        for dep in spec.get("after", []):
            _require(dep in checks, f"checks.{cid}.after names unknown check {dep}")
    for rid, spec in (cfg.get("reviewers") or {}).items():
        _require("agent" in spec, f"reviewers.{rid}.agent missing")
    for g in cfg.get("owner_gates", []):
        for k in ("id", "source", "open_pattern", "blocks_scopes", "owner_action"):
            _require(k in g, f"owner gate missing {k}")


@dataclass
class Config:
    raw: dict
    repo: Path
    path: Path

    @property
    def model(self) -> str:
        return self.raw["model"]

    @property
    def limits(self) -> dict:
        return self.raw["limits"]

    @property
    def budget(self) -> dict:
        return self.raw["budget"]

    @property
    def git(self) -> dict:
        return self.raw["git"]

    @property
    def paths(self) -> dict:
        return self.raw["paths"]

    @property
    def state_dir(self) -> Path:
        override = os.environ.get("AETHERIA_AUTOPILOT_STATE_DIR")
        return Path(override) if override else self.repo / self.paths["state_dir"]

    def python(self) -> str:
        p = self.raw.get("environment", {}).get("python") or "python3"
        if os.path.isabs(p) and os.path.exists(p):
            return p
        return shutil.which(p) or shutil.which("python3") or "python3"

    def godot_bin(self) -> str | None:
        for cand in self.raw.get("environment", {}).get("godot_bin_candidates", []):
            if cand.startswith("$"):
                cand = os.environ.get(cand[1:], "")
                if not cand:
                    continue
            cand = os.path.expanduser(cand)
            if os.sep in cand:
                if os.path.isfile(cand) and os.access(cand, os.X_OK):
                    return cand
            else:
                found = shutil.which(cand)
                if found:
                    return found
        return None

    def display(self) -> str | None:
        """The X display for real-window captures: $DISPLAY, else the configured fallback but only
        when its X socket really exists (never assume a screen)."""
        if os.environ.get("DISPLAY"):
            return os.environ["DISPLAY"]
        fb = self.raw.get("environment", {}).get("display_fallback")
        if fb and fb.startswith(":") and os.path.exists(f"/tmp/.X11-unix/X{fb[1:].split('.')[0]}"):
            return fb
        return None

    def claude_bin(self) -> str | None:
        override = os.environ.get("AETHERIA_AUTOPILOT_CLAUDE_BIN")
        if override:
            return override
        return shutil.which(self.raw.get("claude", {}).get("bin", "claude"))

    def check_specs(self) -> dict[str, dict]:
        """Expanded check specs (e2e shorthand filled from e2e_defaults)."""
        out: dict[str, dict] = {}
        defaults = self.raw.get("e2e_defaults", {})
        for cid, spec in self.raw["checks"].items():
            if "e2e" in spec and "cmd" not in spec:
                merged = json.loads(json.dumps(defaults))
                merged.update(spec)
                merged["cmd"] = [a.replace("{e2e}", spec["e2e"]) for a in defaults["cmd"]]
                out[cid] = merged
            else:
                out[cid] = spec
        return out


def find_repo_root(start: Path | None = None) -> Path:
    env = os.environ.get("AETHERIA_AUTOPILOT_REPO")
    if env:
        return Path(env).resolve()
    p = (start or Path.cwd()).resolve()
    for cand in [p, *p.parents]:
        if (cand / CONFIG_RELPATH).exists() and (cand / ".git").exists():
            return cand
    # fall back to the location of this file: tools/ai_workflow/autopilot/config.py
    return Path(__file__).resolve().parents[3]


def load_config(repo: Path | None = None, path: Path | None = None) -> Config:
    repo = (repo or find_repo_root()).resolve()
    path = path or Path(os.environ.get("AETHERIA_AUTOPILOT_CONFIG", "")) or repo / CONFIG_RELPATH
    if not path or str(path) == ".":
        path = repo / CONFIG_RELPATH
    try:
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError as e:
        raise ConfigError(f"config not found: {path}") from e
    except json.JSONDecodeError as e:
        raise ConfigError(f"config is not valid JSON: {path}: {e}") from e
    validate_config(raw)
    return Config(raw=raw, repo=repo, path=Path(path))


def deep_get(d: dict, dotted: str, default: Any = None) -> Any:
    cur: Any = d
    for part in dotted.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return default
        cur = cur[part]
    return cur
