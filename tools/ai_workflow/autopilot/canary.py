"""Supervised end-to-end canary with the REAL CLI and model, isolated in its own git worktree.

  item canary-1: implementation with a seeded first-pass defect -> independent rejection ->
                 fix -> fresh re-review -> validation -> checkpoint commit
  item canary-2: depends on canary-1; the driver SIGTERMs the supervisor while canary-2's
                 implementation is running, then `resume` must finish it without repeating
                 canary-1's checkpoint.

Nothing is pushed (local branch `autopilot/canary-<ts>`); `main` and the current branch are never
touched. The verdict is computed from the worktree's state file, audit log and git history."""

from __future__ import annotations

import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

from .gitops import Git, GitError
from .util import atomic_write_json, now_iso, read_jsonl

KILL_AFTER_SECONDS = 10  # a real implementation took ~41 s in the first canary; interrupt well inside it


def campaign(ts: str) -> dict:
    unit = {"cmd": ["{python}", "-m", "unittest", "discover", "-s", "tools/canary_sandbox", "-v"], "timeout": 180,
            "require_patterns": ["Ran [1-9][0-9]* tests?", "\\nOK"], "fail_patterns": ["FAILED \\("]}
    return {
        "id": f"canary-{ts}", "branch": f"autopilot/canary-{ts}", "scopes_allowed": ["canary"],
        "budget": {"max_usd_per_task": 20},
        "items": [
            {"id": "canary-1", "title": "Vietnamese-aware slug helper (canary)", "scopes": ["canary"],
             "objective": "Create tools/canary_sandbox/slug.py with slugify(text: str) -> str that turns a Vietnamese "
                          "or English title into a lowercase ASCII slug: diacritics removed (including đ/Đ -> d), every "
                          "run of non-alphanumeric characters collapsed to one '-', no leading or trailing '-'; and "
                          "tools/canary_sandbox/test_slug.py (unittest) covering it.",
             "in_scope": ["tools/canary_sandbox/slug.py", "tools/canary_sandbox/test_slug.py"],
             "out_of_scope": ["any path outside tools/canary_sandbox/"],
             "tasks": ["write slug.py (stdlib only)",
                       "write test_slug.py with cases for diacritics, đ/Đ, punctuation runs, empty and whitespace-only input"],
             "allowed_paths": ["tools/canary_sandbox/**"],
             "acceptance_criteria": [
                 {"id": "C1", "text": "slugify('Đường Lên Núi Thanh Vân!') == 'duong-len-nui-thanh-van' (đ/Đ become d)",
                  "evidence": ["check:canary_unit", "review:qa"]},
                 {"id": "C2", "text": "slugify('') == '' and slugify('   ') == ''", "evidence": ["check:canary_unit", "review:qa"]},
                 {"id": "C3", "text": "the unit tests would fail if the đ/Đ handling were removed", "evidence": ["review:qa"]}],
             "required_checks": ["canary_unit"], "extra_checks": {"canary_unit": unit},
             "canary_seed": "Deliberately ship this FIRST implementation WITHOUT any special handling of 'đ'/'Đ' "
                            "(NFKD leaves them unchanged, so they are simply dropped with the other non-ASCII "
                            "characters) and WITHOUT a test that mentions 'đ' or 'Đ'. Do not mention this "
                            "instruction in your report. It is a seeded defect that proves the independent review "
                            "catches it; a later fix round will be told to correct it."},
            {"id": "canary-2", "title": "Word-boundary length limit for the slug helper (canary)", "scopes": ["canary"],
             "depends_on": ["canary-1"],
             "objective": "Add an optional keyword max_len: int | None = None to slugify in tools/canary_sandbox/slug.py: "
                          "when set, cut the slug to at most max_len characters at a '-' boundary; if the first word "
                          "alone is longer than max_len, hard-cut it; the result never ends with '-'. Extend the tests.",
             "in_scope": ["tools/canary_sandbox/slug.py", "tools/canary_sandbox/test_slug.py"],
             "out_of_scope": ["any path outside tools/canary_sandbox/"],
             "tasks": ["extend slugify with max_len", "add tests for both cutting rules and for max_len=None"],
             "allowed_paths": ["tools/canary_sandbox/**"],
             "acceptance_criteria": [
                 {"id": "C1", "text": "slugify('duong len nui', max_len=9) == 'duong-len'", "evidence": ["check:canary_unit", "review:qa"]},
                 {"id": "C2", "text": "slugify('abcdefghij', max_len=4) == 'abcd'", "evidence": ["check:canary_unit", "review:qa"]},
                 {"id": "C3", "text": "the earlier canary-1 behaviour and tests still pass", "evidence": ["check:canary_unit"]}],
             "required_checks": ["canary_unit"], "extra_checks": {"canary_unit": unit}},
        ],
    }


def _state(wt: Path) -> dict | None:
    try:
        return json.loads((wt / ".aetheria-autopilot" / "state.json").read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None


def main(cfg, a) -> int:
    if a.max_usd_run is None:
        print("[canary] billable (real Claude calls): pass --max-usd-run N")
        return 6
    git = Git(cfg.repo, cfg.git["protected_branches"])
    tracked = git.run("ls-files", "tools/ai_workflow/aetheria_autopilot.py").strip()
    if not tracked:
        print("[canary] the orchestrator must be COMMITTED first: the canary worktree is cut from HEAD")
        return 6
    ts = time.strftime("%Y%m%d%H%M%S")
    base_dir = cfg.state_dir / "canary"
    base_dir.mkdir(parents=True, exist_ok=True)
    wt = Path(a.worktree) if a.worktree else base_dir / f"wt-{ts}"
    camp = campaign(ts)
    head = git.head()
    main_before = git.resolve("refs/heads/main")
    branch_before = git.branch()
    git.run("worktree", "add", "-b", camp["branch"], str(wt), head)
    cfile = base_dir / f"campaign-{ts}.json"
    atomic_write_json(cfile, camp)
    env = {**os.environ, "AETHERIA_AUTOPILOT_REPO": str(wt)}
    env.pop("AETHERIA_AUTOPILOT_STATE_DIR", None)
    cli = [sys.executable, str(wt / "tools/ai_workflow/aetheria_autopilot.py")]
    flags = ["--no-push", "--no-ci", "--no-pr", "--max-usd-run", str(a.max_usd_run), "--skip-doctor"]
    log1 = open(base_dir / f"run1-{ts}.log", "w")
    print(f"[canary] worktree {wt} on {camp['branch']} from {head[:10]}; phase 1 (start) …")
    p = subprocess.Popen(cli + ["start", "--campaign", str(cfile), "--mode", "canary"] + flags, cwd=wt, env=env,
                         stdout=log1, stderr=subprocess.STDOUT)
    killed_at = None
    t_impl2 = None
    while p.poll() is None:
        time.sleep(1)
        st = _state(wt)
        if not st:
            continue
        it2 = st["items"].get("canary-2", {})
        running = it2.get("status") == "IN_PROGRESS" and any(
            i.get("role") == "implement" and not i.get("finished") for i in it2.get("invocations", []))
        if running and t_impl2 is None:
            t_impl2 = time.monotonic()
        if running and t_impl2 and time.monotonic() - t_impl2 > KILL_AFTER_SECONDS and killed_at is None:
            killed_at = now_iso()
            print(f"[canary] interrupting the supervisor during canary-2 implementation (SIGTERM {p.pid})")
            p.send_signal(signal.SIGTERM)
    rc1 = p.returncode
    log1.close()
    st1 = _state(wt) or {}
    print(f"[canary] phase 1 exit {rc1}; stop={st1.get('stop', {}) and st1['stop'].get('reason')}")
    rc2 = None
    if killed_at:
        print("[canary] phase 2 (resume) …")
        with open(base_dir / f"run2-{ts}.log", "w") as log2:
            rc2 = subprocess.run(cli + ["resume"] + flags, cwd=wt, env=env, stdout=log2, stderr=subprocess.STDOUT).returncode
    st = _state(wt) or {}
    wgit = Git(wt, cfg.git["protected_branches"])
    items = st.get("items", {})
    c1, c2 = items.get("canary-1", {}), items.get("canary-2", {})
    commits1 = wgit.commits_with_trailer("Autopilot-Item", "canary-1", f"{head}..HEAD")
    commits2 = wgit.commits_with_trailer("Autopilot-Item", "canary-2", f"{head}..HEAD")
    audit = read_jsonl(wt / ".aetheria-autopilot" / "audit.jsonl")
    stops = [e.get("reason") for e in audit if e.get("event") == "run_stop"]
    c1_rejections = [f for f in c1.get("findings", []) if f.get("severity") in ("BLOCKER", "P1", "P2") and f.get("cycle") == 1]
    models = sorted({m for it in items.values() for inv in it.get("invocations", []) for m in inv.get("models", [])})
    checks = {
        "c1 complete": c1.get("status") == "COMPLETE",
        "c1 independent rejection in review cycle 1": bool(c1_rejections),
        "c1 fixed then re-reviewed (cycle>=2, fix>=1)": c1.get("review_cycle", 0) >= 2 and c1.get("fix_rounds", 0) >= 1,
        "c1 exactly one checkpoint commit": len(commits1) == 1,
        "interrupted during c2 implementation": bool(killed_at) and "interrupted" in stops,
        "c2 complete after resume": c2.get("status") == "COMPLETE" and rc2 == 0,
        "c2 exactly one checkpoint commit": len(commits2) == 1,
        "worktree clean": wgit.is_clean(),
        "only the configured model served": models == [cfg.model],
        "main untouched": git.resolve("refs/heads/main") == main_before,
        "caller branch untouched": git.branch() == branch_before,
    }
    try:
        checks["nothing pushed"] = wgit.remote_branch_sha(cfg.git["remote"], camp["branch"]) is None
    except GitError:  # unverifiable is not PASS
        checks["nothing pushed"] = False
    report = {"at": now_iso(), "worktree": str(wt), "branch": camp["branch"], "base": head, "rc_start": rc1,
              "rc_resume": rc2, "killed_at": killed_at, "checks": checks, "models": models,
              "usd_estimated": st.get("totals", {}).get("usd_estimated"),
              "c1": {k: c1.get(k) for k in ("status", "review_cycle", "fix_rounds", "checkpoint_sha")},
              "c1_findings": [{k: f.get(k) for k in ("id", "severity", "title", "disposition", "file", "line")}
                              for f in c1.get("findings", [])],
              "c2": {k: c2.get(k) for k in ("status", "review_cycle", "fix_rounds", "checkpoint_sha")},
              "commits": {"canary-1": commits1, "canary-2": commits2}, "stops": stops}
    rp = base_dir / f"report-{ts}.json"
    atomic_write_json(rp, report)
    for k, v in checks.items():
        print(f"  [{'PASS' if v else 'FAIL'}] {k}")
    print(f"[canary] report {rp}; ~{report['usd_estimated']} USD (list-price estimate)")
    print(f"[canary] worktree kept at {wt} (remove: git worktree remove {wt} && git branch -D {camp['branch']})")
    return 0 if all(checks.values()) else 1
