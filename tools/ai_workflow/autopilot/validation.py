"""Select, run and record deterministic checks.

A check is PASS only when its command ran, exited 0, printed every `require_patterns` line and
none of its `fail_patterns` (CI's SCRIPT ERROR / leak rules). A check that could not run —
no Godot, no display, a failed prerequisite — is BLOCKED, never PASS.
"""

from __future__ import annotations

import os
import re
import subprocess
import time
from pathlib import Path

from . import gates
from .util import now_iso, path_matches, redact

PASS, FAIL, BLOCKED = "PASS", "FAIL", "BLOCKED"


def select_checks(cfg, changed: list[str], required: list[str], final: bool) -> list[str]:
    specs = cfg.check_specs()
    chosen = set(required)
    for cid, spec in specs.items():
        if spec.get("always"):
            chosen.add(cid)
        elif changed and any(path_matches(p, spec.get("triggers", [])) for p in changed):
            chosen.add(cid)
    unknown = sorted(c for c in chosen if c not in specs and c not in ("scope_guard", "owner_gate_guard"))
    if unknown:
        raise KeyError(f"unknown check id(s): {unknown}")
    # prerequisites ride along
    changed_set = True
    while changed_set:
        changed_set = False
        for cid in list(chosen):
            for dep in specs.get(cid, {}).get("after", []):
                if dep not in chosen:
                    chosen.add(dep)
                    changed_set = True
    order: list[str] = []
    seen: set[str] = set()

    def visit(c: str) -> None:
        if c in seen:
            return
        seen.add(c)
        for d in specs.get(c, {}).get("after", []):
            visit(d)
        order.append(c)

    for c in sorted(chosen):
        visit(c)
    return order


def _expand(arg: str, cfg, godot: str | None) -> str:
    return (arg.replace("{python}", cfg.python()).replace("{godot}", godot or "{godot}")
            .replace("{repo}", str(cfg.repo)))


def _summarize(text: str, spec: dict) -> str:
    pat = spec.get("summary_pattern")
    if pat:
        m = re.findall(pat, text)
        if m:
            return m[-1][:300]
    tail = [ln for ln in text.strip().splitlines() if ln.strip()][-3:]
    return " | ".join(tail)[:300]


class Validator:
    def __init__(self, cfg, log_dir: Path, runner=None):
        self.cfg = cfg
        self.log_dir = Path(log_dir)
        self._run = runner or self._subprocess

    def _subprocess(self, argv: list[str], timeout: int, env: dict) -> tuple[int | None, str, bool]:
        try:
            p = subprocess.run(argv, cwd=self.cfg.repo, capture_output=True, text=True, timeout=timeout,
                               env=env, errors="replace")
            return p.returncode, (p.stdout or "") + (p.stderr or ""), False
        except subprocess.TimeoutExpired as e:
            out = (e.stdout or b"") if isinstance(e.stdout, bytes) else (e.stdout or "").encode()
            return None, out.decode("utf-8", "replace"), True
        except FileNotFoundError as e:
            return 127, f"cannot execute: {e}", False

    def run_one(self, cid: str, spec: dict, godot: str | None) -> dict:
        needs = spec.get("needs", [])
        if "godot" in needs and not godot:
            return {"status": BLOCKED, "reason": "Godot binary not found (environment.godot_bin_candidates)"}
        display = self.cfg.display() if os.name != "nt" else "nt"
        if "display" in needs and not display:
            return {"status": BLOCKED, "reason": "no display for a real-window capture ($DISPLAY unset, no X socket)"}
        seq = spec.get("cmd_sequence") or [spec["cmd"]]
        env = dict(os.environ)
        if "display" in needs and display != "nt":
            env["DISPLAY"] = display
        env.setdefault("PYTHONDONTWRITEBYTECODE", "1")
        out_all, rc_all, cmds = "", 0, []
        start = time.monotonic()
        for cmd in seq:
            argv = [_expand(a, self.cfg, godot) for a in cmd]
            cmds.append(argv)
            rc, out, timed_out = self._run(argv, int(spec.get("timeout", 900)), env)
            out_all += f"$ {' '.join(argv)}\n{out}\n[rc={rc}]\n"
            if timed_out:
                return {"status": FAIL, "rc": None, "cmd": cmds, "reason": f"timed out after {spec.get('timeout')}s",
                        "output": out_all, "duration_s": time.monotonic() - start}
            if rc != 0:
                rc_all = rc
                break
        status, reasons = PASS, []
        if rc_all != 0:
            status = FAIL
            reasons.append(f"exit code {rc_all}")
        for pat in spec.get("fail_patterns", []):
            hits = re.findall(f"^.*{pat}.*$", out_all, flags=re.MULTILINE)
            if hits:
                status = FAIL
                reasons.append(f"{len(hits)} line(s) match /{pat}/: {hits[0][:160]}")
        for pat in spec.get("require_patterns", []):
            if not re.search(pat, out_all):
                status = FAIL
                reasons.append(f"required output /{pat}/ missing")
        return {"status": status, "rc": rc_all, "cmd": cmds, "reason": "; ".join(reasons),
                "output": out_all, "duration_s": time.monotonic() - start}

    def run(self, check_ids: list[str], fingerprint: str, cache: dict, force: bool,
            item: dict | None = None, changed: list[str] | None = None, diff_text: str = "") -> dict:
        """Run `check_ids` in order. `cache` maps check id -> previous record; a PASS with the same
        fingerprint is reused unless `force`. Returns {check_id: record}."""
        specs = self.cfg.check_specs()
        godot = self.cfg.godot_bin()
        self.log_dir.mkdir(parents=True, exist_ok=True)
        results: dict[str, dict] = {}
        for cid in check_ids:
            prev = cache.get(cid)
            if (not force and prev and prev.get("status") == PASS and prev.get("fingerprint") == fingerprint):
                rec = dict(prev)
                rec["reused"] = True
                results[cid] = rec
                continue
            failed_deps = [d for d in specs.get(cid, {}).get("after", [])
                           if results.get(d, {}).get("status") != PASS]
            if failed_deps:
                results[cid] = {"status": BLOCKED, "reason": f"prerequisite(s) not PASS: {failed_deps}",
                                "fingerprint": fingerprint, "at": now_iso(), "reused": False}
                continue
            if cid == "scope_guard":
                ok, why = gates.scope_guard(changed or [], item or {}, self.cfg)
                r = {"status": PASS if ok else FAIL, "reason": why, "cmd": [["<builtin scope_guard>"]], "output": why}
            elif cid == "owner_gate_guard":
                ok, why = gates.owner_gate_guard(diff_text, self.cfg)
                r = {"status": PASS if ok else FAIL, "reason": why, "cmd": [["<builtin owner_gate_guard>"]], "output": why}
            else:
                r = self.run_one(cid, specs[cid], godot)
            out = r.pop("output", "")
            log_path = self.log_dir / f"{cid}.log"
            log_path.write_text(redact(out), encoding="utf-8")
            r.update({"fingerprint": fingerprint, "at": now_iso(), "reused": False,
                      "log": str(log_path), "summary": _summarize(out, specs.get(cid, {}))})
            if r["status"] == FAIL:
                r["failure_excerpt"] = _failure_excerpt(out)
                r["signature"] = f"{cid}:{_normalize_failure(r.get('reason', ''), out)}"
            results[cid] = r
        return results


def _failure_excerpt(out: str, n: int = 40) -> str:
    lines = out.splitlines()
    keep = [ln for ln in lines if re.search(r"FAIL|ERROR|Error|error:|Traceback|assert", ln)]
    return redact("\n".join((keep or lines)[-n:]))[:6000]


def _normalize_failure(reason: str, out: str) -> str:
    """A failure signature that ignores timings, addresses and counts of passes."""
    key = "\n".join(ln for ln in out.splitlines() if re.search(r"\[FAIL\]|SCRIPT ERROR|error|Error", ln))
    key = re.sub(r"0x[0-9a-fA-F]+|\d+(\.\d+)?\s*(ms|s)\b|\d{4}-\d\d-\d\dT[\d:]+", "#", key)
    import hashlib
    return hashlib.sha256((reason.split(":")[0] + key).encode()).hexdigest()[:12]


def summarize_results(results: dict) -> dict:
    counts = {PASS: 0, FAIL: 0, BLOCKED: 0}
    for r in results.values():
        counts[r["status"]] = counts.get(r["status"], 0) + 1
    return counts
