"""Launch one headless Claude Code CLI invocation and judge its result from evidence.

The invocation's prose is never trusted. What is checked: the exit code, the JSON envelope,
`is_error`, the structured output against its schema, and `modelUsage` — every model that
actually served the call must be the ONE configured model (no silent fallback).
"""

from __future__ import annotations

import json
import os
import signal
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .util import now_iso, redact, sha256_text


@dataclass
class Invocation:
    role: str                      # implement | fix | review | plan | probe
    prompt: str
    max_turns: int
    timeout_seconds: int
    schema: dict | None = None
    allowed_tools: list[str] = field(default_factory=list)
    disallowed_tools: list[str] = field(default_factory=list)
    append_system_prompt: str | None = None
    tools: list[str] | None = None  # restrict the built-in tool set (None = default set)
    max_budget_usd: float | None = None
    env: dict[str, str] = field(default_factory=dict)
    label: str = ""


@dataclass
class InvocationResult:
    ok: bool
    failure_kind: str | None
    detail: str
    rc: int | None
    session_id: str | None
    structured: Any
    result_text: str
    models: list[str]
    usd: float
    turns: int | None
    duration_s: float
    denials: list[dict]
    out_path: str
    signature: str

    def record(self) -> dict:
        return {
            "ok": self.ok, "failure_kind": self.failure_kind, "detail": redact(self.detail)[:600],
            "rc": self.rc, "session_id": self.session_id, "models": self.models,
            "usd_estimated": round(self.usd, 6), "turns": self.turns,
            "duration_s": round(self.duration_s, 1), "denials": len(self.denials),
            "denied_tools": sorted({d.get("tool_name", "?") for d in self.denials}),
            "out_path": self.out_path, "signature": self.signature,
        }


class ClaudeRunner:
    def __init__(self, cfg, out_dir: Path):
        self.cfg = cfg
        self.out_dir = Path(out_dir)
        self._children: set[subprocess.Popen] = set()
        self._lock = threading.Lock()

    # --- argv ----------------------------------------------------------------------------
    def build_argv(self, inv: Invocation) -> list[str]:
        ccfg = self.cfg.raw.get("claude", {})
        argv = [self.cfg.claude_bin() or "claude", "-p",
                "--model", self.cfg.model,
                "--output-format", "json",
                "--max-turns", str(inv.max_turns),
                "--permission-mode", "dontAsk",
                "--permission-prompts", "none"]
        if ccfg.get("setting_sources"):
            argv += ["--setting-sources", ccfg["setting_sources"]]
        if ccfg.get("strict_mcp_config", True):
            argv += ["--strict-mcp-config"]
        if not ccfg.get("session_persistence", False):
            argv += ["--no-session-persistence"]
        if inv.schema is not None:
            argv += ["--json-schema", json.dumps(inv.schema, separators=(",", ":"))]
        if inv.tools is not None:
            argv += ["--tools", ",".join(inv.tools)]
        if inv.allowed_tools:
            argv += ["--allowedTools", *inv.allowed_tools]
        if inv.disallowed_tools:
            argv += ["--disallowedTools", *inv.disallowed_tools]
        if inv.append_system_prompt:
            argv += ["--append-system-prompt", inv.append_system_prompt]
        if inv.max_budget_usd is not None:
            argv += ["--max-budget-usd", f"{max(inv.max_budget_usd, 0.01):.2f}"]
        # The prompt is sent on stdin (no ARG_MAX ceiling, never visible in `ps`).
        return argv

    def build_env(self, inv: Invocation) -> dict[str, str]:
        env = dict(os.environ)
        if self.cfg.raw.get("claude", {}).get("pin_auxiliary_models", True):
            # Claude Code uses a small model for background chores (titles, summaries). Pin every
            # such slot to the configured model so modelUsage can prove a single identity.
            for k in ("ANTHROPIC_DEFAULT_HAIKU_MODEL", "ANTHROPIC_SMALL_FAST_MODEL",
                      "CLAUDE_CODE_SUBAGENT_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL",
                      "ANTHROPIC_DEFAULT_OPUS_MODEL"):
                env[k] = self.cfg.model
        env.pop("ANTHROPIC_MODEL", None)  # --model is the one source; no ambient override
        env["AETHERIA_AUTOPILOT_ROLE"] = "reviewer" if inv.role in ("review", "plan", "probe") else "worker"
        env.update(inv.env)
        return env

    # --- run -----------------------------------------------------------------------------
    def kill_child(self) -> None:
        with self._lock:
            children = list(self._children)
        for p in children:
            _kill_group(p)

    def run(self, inv: Invocation) -> InvocationResult:
        self.out_dir.mkdir(parents=True, exist_ok=True)
        call_id = f"{time.strftime('%Y%m%dT%H%M%S')}-{inv.role}-{uuid.uuid4().hex[:6]}"
        out_path = self.out_dir / f"{call_id}.json"
        err_path = self.out_dir / f"{call_id}.stderr.txt"
        (self.out_dir / f"{call_id}.prompt.md").write_text(redact(inv.prompt), encoding="utf-8")
        start = time.monotonic()
        bin_ = self.cfg.claude_bin()
        if not bin_:
            return self._fail("cli_missing", "claude CLI not found on PATH", None, out_path, start)
        argv = self.build_argv(inv)
        try:
            with open(out_path, "wb") as out_fh, open(err_path, "wb") as err_fh:
                child = subprocess.Popen(
                    argv, cwd=self.cfg.repo, stdin=subprocess.PIPE, stdout=out_fh, stderr=err_fh,
                    env=self.build_env(inv), start_new_session=True)
                with self._lock:
                    self._children.add(child)
                try:
                    child.communicate(inv.prompt.encode("utf-8"), timeout=inv.timeout_seconds)
                except subprocess.TimeoutExpired:
                    _kill_group(child)
                    return self._fail("timeout", f"invocation exceeded {inv.timeout_seconds}s", None,
                                      out_path, start)
                finally:
                    with self._lock:
                        self._children.discard(child)
                rc = child.returncode
        except (FileNotFoundError, PermissionError, NotADirectoryError) as e:
            return self._fail("cli_missing", f"cannot execute {bin_}: {e.strerror}", None, out_path, start)
        if rc is not None and rc < 0:
            return self._fail("interrupted", f"invocation killed by signal {-rc}", rc, out_path, start)
        return self.judge(out_path, err_path, rc, inv, start)

    def _fail(self, kind: str, detail: str, rc: int | None, out_path: Path, start: float,
              **kw: Any) -> InvocationResult:
        return InvocationResult(
            ok=False, failure_kind=kind, detail=detail, rc=rc, session_id=kw.get("session_id"),
            structured=kw.get("structured"), result_text=kw.get("result_text", ""),
            models=kw.get("models", []), usd=kw.get("usd", 0.0), turns=kw.get("turns"),
            duration_s=time.monotonic() - start, denials=kw.get("denials", []),
            out_path=str(out_path), signature=sha256_text(f"{kind}|{detail[:200]}")[:16])

    def judge(self, out_path: Path, err_path: Path, rc: int | None, inv: Invocation,
              start: float) -> InvocationResult:
        raw = out_path.read_text(encoding="utf-8", errors="replace") if out_path.exists() else ""
        err = err_path.read_text(encoding="utf-8", errors="replace") if err_path.exists() else ""
        try:
            env = json.loads(raw)
            if not isinstance(env, dict):
                raise ValueError("envelope is not an object")
        except (json.JSONDecodeError, ValueError):
            kind = "auth" if _looks_like_auth(raw + err) else "crash"
            return self._fail(kind, f"no JSON result (rc={rc}): {(err or raw)[-300:]}", rc, out_path, start)
        models = sorted((env.get("modelUsage") or {}).keys())
        common = dict(session_id=env.get("session_id"), structured=env.get("structured_output"),
                      result_text=str(env.get("result") or ""), models=models,
                      usd=float(env.get("total_cost_usd") or 0.0), turns=env.get("num_turns"),
                      denials=env.get("permission_denials") or [])
        result_text = common["result_text"]
        subtype = str(env.get("subtype") or "")
        if env.get("is_error") or rc not in (0, None):
            status = env.get("api_error_status")
            if status == 404 or "issue with the selected model" in result_text:
                return self._fail("model_unavailable", result_text[:300], rc, out_path, start, **common)
            if status in (401, 403) or _looks_like_auth(result_text + err):
                return self._fail("auth", result_text[:300], rc, out_path, start, **common)
            if "max_turns" in subtype:
                return self._fail("max_turns", f"hit --max-turns {inv.max_turns}", rc, out_path, start, **common)
            if "budget" in subtype or "budget" in result_text.lower():
                return self._fail("budget_exceeded", result_text[:300], rc, out_path, start, **common)
            if status == 429 or "rate limit" in result_text.lower() or "usage limit" in result_text.lower():
                return self._fail("rate_limited", result_text[:300], rc, out_path, start, **common)
            return self._fail("cli_error", f"{subtype}: {result_text[:300]}", rc, out_path, start, **common)
        foreign = [m for m in models if m != self.cfg.model]
        if foreign or not models:
            return self._fail("model_mismatch",
                              f"served by {models or 'no model'}; configured {self.cfg.model}",
                              rc, out_path, start, **common)
        if inv.schema is not None:
            problems = check_schema(common["structured"], inv.schema)
            if problems:
                return self._fail("no_structured_output", "; ".join(problems[:5]), rc, out_path, start, **common)
        return InvocationResult(
            ok=True, failure_kind=None, detail="ok", rc=rc, duration_s=time.monotonic() - start,
            out_path=str(out_path), signature="", **common)


def _kill_group(p: subprocess.Popen) -> None:
    if p.poll() is not None:
        return
    try:
        os.killpg(p.pid, signal.SIGTERM)
        try:
            p.wait(timeout=15)
        except subprocess.TimeoutExpired:
            os.killpg(p.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError, OSError):
        pass


def _looks_like_auth(text: str) -> bool:
    t = text.lower()
    return any(s in t for s in ("not logged in", "please run /login", "invalid api key",
                                "authentication_error", "oauth token has expired", "401 unauthorized"))


# --- tiny JSON-schema subset validator (enough for our own schemas) ------------------------------

def check_schema(value: Any, schema: dict, path: str = "$") -> list[str]:
    errs: list[str] = []
    t = schema.get("type")
    types = {"object": dict, "array": list, "string": str, "integer": int, "number": (int, float),
             "boolean": bool, "null": type(None)}
    if t:
        allowed = t if isinstance(t, list) else [t]
        ok = False
        for a in allowed:
            py = types.get(a)
            if py is None:
                continue
            if a in ("integer", "number") and isinstance(value, bool):
                continue
            if isinstance(value, py):
                ok = True
        if not ok:
            return [f"{path}: expected {t}, got {type(value).__name__}"]
    if "enum" in schema and value not in schema["enum"]:
        errs.append(f"{path}: {value!r} not in {schema['enum']}")
    if isinstance(value, dict):
        for req in schema.get("required", []):
            if req not in value:
                errs.append(f"{path}: missing {req}")
        for k, sub in (schema.get("properties") or {}).items():
            if k in value:
                errs.extend(check_schema(value[k], sub, f"{path}.{k}"))
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            errs.append(f"{path}: fewer than {schema['minItems']} items")
        if "items" in schema:
            for i, v in enumerate(value):
                errs.extend(check_schema(v, schema["items"], f"{path}[{i}]"))
    if isinstance(value, str) and "minLength" in schema and len(value) < schema["minLength"]:
        errs.append(f"{path}: shorter than {schema['minLength']}")
    return errs


def stamp() -> str:
    return now_iso()
