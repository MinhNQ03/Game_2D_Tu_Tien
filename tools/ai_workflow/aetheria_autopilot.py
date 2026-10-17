#!/usr/bin/env python3
"""Aetheria autopilot — local supervisor for Claude Code work items.

  python3 tools/ai_workflow/aetheria_autopilot.py doctor            # verify CLI, model, tools
  python3 tools/ai_workflow/aetheria_autopilot.py dry-run --campaign F
  python3 tools/ai_workflow/aetheria_autopilot.py start --campaign F --activate --max-usd-run 40
  python3 tools/ai_workflow/aetheria_autopilot.py status | resume | stop [--now]

See tools/ai_workflow/README.md. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from autopilot import ORCHESTRATOR_VERSION, gates, knowledge, review  # noqa: E402
from autopilot.claude_runner import ClaudeRunner, Invocation  # noqa: E402
from autopilot.config import ConfigError, load_config  # noqa: E402
from autopilot.gitops import Git  # noqa: E402
from autopilot.lock import RepoLock, pid_alive  # noqa: E402
from autopilot.state import StateError, StateStore  # noqa: E402
from autopilot.supervisor import EXIT_CONFIG, RunOptions, Stop, Supervisor  # noqa: E402
from autopilot.util import atomic_write_json, now_iso  # noqa: E402
from autopilot.validation import Validator, select_checks  # noqa: E402

PROBE_TOKEN = "AUTOPILOT-PROBE-OK"


# ===== doctor =======================================================================================

def _version_tuple(v: str) -> tuple[int, ...]:
    return tuple(int(x) for x in re.findall(r"\d+", v)[:3])


def model_probe(cfg, force: bool = False) -> dict:
    """A harmless read-only call to the exact configured model; cached 12 h per CLI version."""
    cache = cfg.state_dir / "doctor_probe.json"
    cli_v = _cli_version(cfg)
    if not force and cache.exists():
        try:
            c = json.loads(cache.read_text(encoding="utf-8"))
            if (c.get("model") == cfg.model and c.get("cli_version") == cli_v and c.get("ok")
                    and time.time() - c.get("epoch", 0) < 12 * 3600):
                c["cached"] = True
                return c
        except json.JSONDecodeError:
            pass
    runner = ClaudeRunner(cfg, cfg.state_dir / "invocations")
    lim = cfg.limits["invocation"]["probe"]
    res = runner.run(Invocation(role="probe", prompt=f"Reply with exactly the text {PROBE_TOKEN} and nothing else.",
                                max_turns=lim["max_turns"], timeout_seconds=lim["timeout_seconds"], tools=[],
                                label="doctor-probe"))
    ok = res.ok and PROBE_TOKEN in res.result_text and res.models == [cfg.model]
    out = {"ok": ok, "model": cfg.model, "served_by": res.models, "failure": res.failure_kind,
           "detail": res.detail[:300], "usd_estimated": res.usd, "cli_version": cli_v, "at": now_iso(),
           "epoch": time.time(), "cached": False}
    if ok:
        cfg.state_dir.mkdir(parents=True, exist_ok=True)
        atomic_write_json(cache, out)
    return out


def _cli_version(cfg) -> str:
    b = cfg.claude_bin()
    if not b:
        return ""
    try:
        return subprocess.run([b, "--version"], capture_output=True, text=True, timeout=30).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def doctor(cfg, probe: bool = True, force_probe: bool = False) -> dict:
    rows: list[tuple[str, str, str]] = []  # (check, OK|WARN|FAIL, detail)

    def add(name, ok, detail, warn=False):
        rows.append((name, "OK" if ok else ("WARN" if warn else "FAIL"), detail))

    add("python", sys.version_info >= (3, 10), sys.version.split()[0])
    git = Git(cfg.repo, cfg.git["protected_branches"])
    try:
        branch, head = git.branch(), git.head()
        add("git", True, f"{cfg.repo} on `{branch}` at {head[:10]}")
        dirty = git.changed_paths()
        add("worktree clean", not dirty, f"{len(dirty)} uncommitted path(s) {dirty[:5]}" if dirty else "clean", warn=True)
        ign = subprocess.run(["git", "check-ignore", "-q", cfg.paths["state_dir"] + "/state.json"], cwd=cfg.repo).returncode == 0
        add("state dir ignored by git", ign or (cfg.state_dir / ".gitignore").exists(),
            "ignored" if ign else "relies on the state dir's own .gitignore")
    except Exception as e:  # noqa: BLE001
        add("git", False, str(e)[:200])
    add("config", True, f"{cfg.path.relative_to(cfg.repo)} policy {cfg.raw['policy_version']} "
        f"fingerprint {knowledge.policy_fingerprint(cfg.repo)}")
    cli = cfg.claude_bin()
    cli_v = _cli_version(cfg) if cli else ""
    min_v = cfg.raw.get("claude", {}).get("min_cli_version", "0")
    add("claude CLI", bool(cli) and _version_tuple(cli_v) >= _version_tuple(min_v), f"{cli} {cli_v} (min {min_v})")
    auth_ok, auth_detail = False, "not checked"
    if cli and not os.environ.get("AETHERIA_AUTOPILOT_CLAUDE_BIN"):
        try:
            a = json.loads(subprocess.run([cli, "auth", "status"], capture_output=True, text=True, timeout=30).stdout or "{}")
            auth_ok = bool(a.get("loggedIn"))
            auth_detail = f"loggedIn={a.get('loggedIn')} method={a.get('authMethod')} plan={a.get('subscriptionType')}"
        except (OSError, json.JSONDecodeError, subprocess.TimeoutExpired) as e:
            auth_detail = str(e)[:120]
    elif os.environ.get("AETHERIA_AUTOPILOT_CLAUDE_BIN"):
        auth_ok, auth_detail = True, "fake CLI (test mode)"
    add("claude auth", auth_ok, auth_detail)
    probe_res = None
    if probe and cli and auth_ok:
        probe_res = model_probe(cfg, force=force_probe)
        add(f"model {cfg.model}", probe_res["ok"],
            f"served_by={probe_res['served_by']} {'(cached)' if probe_res.get('cached') else ''} "
            f"{probe_res.get('failure') or ''} {probe_res.get('detail') if not probe_res['ok'] else ''}".strip())
    else:
        add(f"model {cfg.model}", False, "probe skipped" if not probe else "no CLI/auth", warn=not probe)
    gb = cfg.godot_bin()
    gv = ""
    if gb:
        try:
            gv = subprocess.run([gb, "--version"], capture_output=True, text=True, timeout=60).stdout.strip()
        except (OSError, subprocess.TimeoutExpired):
            gv = "?"
    pref = cfg.raw.get("environment", {}).get("godot_version_prefix", "")
    add("godot", bool(gb) and gv.startswith(pref), f"{gb} {gv}" if gb else "not found — Godot checks will BLOCK, never pass")
    disp = cfg.display()
    add("display (captures)", bool(disp) or os.name == "nt",
        f"{disp} ({'$DISPLAY' if os.environ.get('DISPLAY') else 'fallback, X socket present'})" if disp
        else "no display: real-window captures will BLOCK", warn=True)
    gh_ok = shutil.which("gh") is not None
    if gh_ok:
        r = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True, timeout=30)
        gh_ok = r.returncode == 0
    add("gh (PR/CI)", gh_ok, "authenticated" if gh_ok else "unavailable: CI cannot be verified", warn=True)
    try:
        rem = git.remote_branch_sha(cfg.git["remote"], "main")
        add("remote reachable", bool(rem), f"{cfg.git['remote']}/main {rem[:10] if rem else '?'}", warn=True)
    except Exception as e:  # noqa: BLE001
        add("remote reachable", False, str(e)[:120], warn=True)
    missing = [s["agent"] for s in cfg.raw.get("reviewers", {}).values()
               if not (cfg.repo / ".claude" / "agents" / f"{s['agent']}.md").exists()]
    add("reviewer agents", not missing, "all present" if not missing else f"missing {missing}")
    sp = cfg.repo / ".claude" / "settings.json"
    try:
        sj = json.loads(sp.read_text(encoding="utf-8"))
        hooks_ok = all((cfg.repo / "tools/ai_workflow/hooks" / n).exists()
                       for n in ("guard_tool.py", "post_edit_lint.py", "session_context.py"))
        add("hooks", hooks_ok and "PreToolUse" in sj.get("hooks", {}), "PreToolUse guard, PostToolUse lint, SessionStart digest")
    except (FileNotFoundError, json.JSONDecodeError) as e:
        add("hooks", False, f".claude/settings.json: {e}")
    lock = RepoLock(cfg.state_dir)
    held = lock.is_held_by_other() if cfg.state_dir.exists() else False
    add("lock", not held, f"held by {lock.read_info()}" if held else "free", warn=True)
    store = StateStore(cfg.state_dir)
    if store.exists():
        try:
            st = store.load()
            add("state", True, f"campaign {st['campaign']['id']} rev {st['revision']}")
        except StateError as e:
            add("state", False, str(e)[:200])
    b = cfg.budget
    add("budget", b.get("max_usd_per_run") is not None, "config max_usd_per_run="
        f"{b.get('max_usd_per_run')} (pass --max-usd-run to start/resume)", warn=True)
    og = [g.id for g in gates.gate_statuses(cfg) if g.open]
    add("owner gates", True, f"open: {', '.join(og) or 'none'}")
    fails = [r for r in rows if r[1] == "FAIL"]
    model_ok = bool(probe_res and probe_res["ok"])
    if not fails:
        verdict = "AUTONOMOUS_READY"
    elif model_ok or not any(r[0].startswith(("model", "claude")) for r in fails):
        verdict = "BLOCKED"
    else:
        verdict = "NATIVE_ONLY"  # the exact model is unavailable to the CLI: no autonomous runs
    return {"verdict": verdict, "rows": rows, "probe": probe_res, "orchestrator": ORCHESTRATOR_VERSION}


def print_doctor(d: dict) -> None:
    w = max(len(r[0]) for r in d["rows"])
    for name, st, detail in d["rows"]:
        print(f"  [{st:4}] {name.ljust(w)}  {detail}")
    print(f"\nverdict: {d['verdict']}")
    if d["verdict"] == "NATIVE_ONLY":
        print("  The exact model is not reachable from the local CLI: autonomous cross-invocation runs are"
              " DISABLED.\n  The native Skill + reviewer agents still work inside VS Code. Your extension settings"
              " were not touched.")


# ===== commands ====================================================================================

def run_opts(a) -> RunOptions:
    return RunOptions(max_tasks=a.max_tasks, wall_clock_minutes=a.minutes, max_usd_run=a.max_usd_run,
                      push=False if a.no_push else None, ci=False if a.no_ci else None,
                      pr=False if a.no_pr else None, allow_planner=True if a.allow_planner else None)


def preflight_for_run(cfg, skip_probe: bool) -> int | None:
    d = doctor(cfg, probe=not skip_probe)
    hard = [r for r in d["rows"] if r[1] == "FAIL"]
    if hard or (not skip_probe and d["verdict"] != "AUTONOMOUS_READY"):
        print_doctor(d)
        print("\n[autopilot] refusing to start write-capable autonomous execution (doctor failed).")
        return EXIT_CONFIG
    return None


def cmd_start(cfg, a) -> int:
    sup = Supervisor(cfg, run_opts(a))
    if not a.skip_doctor:
        rc = preflight_for_run(cfg, skip_probe=False)
        if rc is not None:
            return rc
    try:
        sup.require_budget()
        sup.init_campaign(Path(a.campaign), a.mode, a.activate)
    except Stop as s:
        print(f"[autopilot] {s.reason}: {s.detail}")
        return s.code
    if a.init_only:
        print(f"[autopilot] campaign initialised in {cfg.state_dir}; run `resume` to execute")
        return 0
    rc = sup.run()
    print_status(cfg)
    return rc


def cmd_resume(cfg, a) -> int:
    if not a.skip_doctor:
        rc = preflight_for_run(cfg, skip_probe=False)
        if rc is not None:
            return rc
    sup = Supervisor(cfg, run_opts(a))
    rc = sup.run()
    print_status(cfg)
    return rc


def cmd_stop(cfg, a) -> int:
    cfg.state_dir.mkdir(parents=True, exist_ok=True)
    (cfg.state_dir / "STOP").write_text(now_iso() + "\n", encoding="utf-8")
    info = RepoLock(cfg.state_dir).read_info() or {}
    print(f"[autopilot] STOP requested; the supervisor stops before its next stage. holder={info}")
    if a.now and info.get("pid") and not info.get("released_at") and pid_alive(int(info["pid"])):
        os.kill(int(info["pid"]), signal.SIGTERM)
        print(f"[autopilot] sent SIGTERM to {info['pid']} (it kills its Claude child and persists state)")
    return 0


def cmd_retry(cfg, a) -> int:
    store = StateStore(cfg.state_dir)
    lock = RepoLock(cfg.state_dir)
    try:
        lock.acquire("retry-cmd")
    except Exception as e:  # LockHeld
        print(f"[autopilot] cannot re-queue while a run holds the lock: {e}")
        return 3
    try:
        st = store.load()
        it = st["items"].get(a.item)
        if not it or it["status"] not in ("FAILED", "BLOCKED_OWNER"):
            print(f"[autopilot] {a.item}: only a FAILED or BLOCKED_OWNER item can be re-queued by the owner")
            return 2
        from autopilot.state import transition
        transition(st, a.item, "QUEUED", f"owner re-queued: {a.reason}", store=store,
                   review_cycle=0, fix_rounds=0, stage=None, owner_action=None, failure_signatures={})
        store.save(st)
        print(f"[autopilot] {a.item} -> QUEUED (history kept)")
        return 0
    finally:
        lock.release()


def print_status(cfg, as_json: bool = False) -> int:
    store = StateStore(cfg.state_dir)
    lock = RepoLock(cfg.state_dir)
    if not store.exists():
        print("[autopilot] no campaign state yet (start one with `start --campaign FILE`)")
        return 0
    try:
        st = store.load()
    except StateError as e:
        print(f"[autopilot] STATE INVALID: {e}\n  recovery: see README §Recovery (reconcile from git)")
        return 2
    if as_json:
        print(json.dumps(st, indent=2, ensure_ascii=False))
        return 0
    c = st["campaign"]
    held = lock.is_held_by_other()
    print(f"campaign {c['id']} ({c['mode']}{', owner-activated' if c.get('activated_by_owner') else ''}) "
          f"branch {c['branch']} base {c['base_sha'][:10]}  rev {st['revision']}  "
          f"{'RUNNING ' + str(lock.read_info()) if held else 'idle'}")
    t = st["totals"]
    print(f"totals: {t['tasks_completed']} completed, {t['invocations']} invocations, "
          f"~{t['usd_estimated']:.2f} USD (list-price estimate)")
    for iid in st["order"]:
        it = st["items"][iid]
        print(f"  {it['status']:<20} {iid:<36} stage={it.get('stage') or '-':<10} cycle={it['review_cycle']} "
              f"fix={it['fix_rounds']} ckpt={(it.get('checkpoint_sha') or '-')[:10]} "
              f"ci={(it.get('ci') or {}).get('conclusion', '-')}")
        if it.get("owner_action") and it["status"] == "BLOCKED_OWNER":
            print(f"      owner action: {it['owner_action'][:300]}")
        if it["status"] in ("FAILED", "BLOCKED_ENVIRONMENT") and it.get("stop_detail"):
            print(f"      detail: {it['stop_detail'][:300]}")
    s = st.get("stop")
    if s:
        print(f"last stop: {s['reason']} — {s['detail'][:400]}\n  at {s['at']}; item {s.get('current_item')} "
              f"stage {s.get('stage')}; resume: {s.get('resume')}")
    n = st.get("next")
    if n and n.get("item"):
        print(f"next eligible: {n['item']} (prompt {n['prompt_path']}; validation problems: {n.get('problems') or 'none'})")
    return 0


def cmd_dry_run(cfg, a) -> int:
    print(f"[dry-run] orchestrator {ORCHESTRATOR_VERSION}, model {cfg.model}, policy {cfg.raw['policy_version']}"
          f"@{knowledge.policy_fingerprint(cfg.repo)}")
    d = doctor(cfg, probe=False)
    print_doctor(d)
    git = Git(cfg.repo, cfg.git["protected_branches"])
    store = StateStore(cfg.state_dir)
    if a.campaign:
        spec = json.loads(Path(a.campaign).read_text(encoding="utf-8"))
        from autopilot.state import empty_state, new_item
        st = empty_state({"id": spec["id"], "mode": a.mode, "branch": spec.get("branch") or git.branch(),
                          "base_sha": spec.get("base_sha") or git.head(), "scopes_allowed": spec.get("scopes_allowed", [])})
        for it in spec["items"]:
            item = new_item(it)
            st["items"][item["id"]] = item
            st["order"].append(item["id"])
    elif store.exists():
        st = store.load()
    else:
        print("[dry-run] no --campaign and no state: nothing to plan")
        return 0
    sup = Supervisor(cfg, run_opts(a))
    sup.state = st
    print(f"\n[dry-run] campaign {st['campaign']['id']} on branch {st['campaign']['branch']} "
          f"(currently `{git.branch()}` at {git.head()[:10]})")
    from autopilot import prompts
    for iid in st["order"]:
        it = st["items"][iid]
        blocking = gates.blocking_gates_for(it, cfg)
        prompt = prompts.render_task_prompt(cfg, st, it, git.head(), st["campaign"]["branch"])
        probs = prompts.validate_task_prompt(cfg, st, it, prompt)
        tools, allow, deny = sup.worker_permissions(it)
        print(f"\n== {iid}: {it['title']}  [{it['status']}]")
        print(f"   depends_on={it['depends_on']} scopes={it['scopes']} gates={[g.id for g in blocking] or 'none'}")
        print(f"   prompt: {len(prompt)} chars; validation: {probs or 'OK'}")
        print(f"   worker tools={tools}\n   worker allow ({len(allow)}): {allow[:6]} …\n   worker deny ({len(deny)}): {deny[:6]} …")
        print(f"   checks (for its declared criteria): {sorted(set(it['required_checks']))}")
        print(f"   reviewers (before diff): {review.select_reviewers(cfg, it, [])}")
        argv = sup.runner.build_argv(Invocation(role="implement", prompt="<prompt>", max_turns=cfg.limits['invocation']['implement']['max_turns'],
                                                timeout_seconds=1, tools=tools, allowed_tools=allow[:3], disallowed_tools=deny[:3]))
        print(f"   argv: {' '.join(a if len(a) < 60 else a[:57] + '...' for a in argv)} (+ more allow/deny rules)")
        if a.show_prompt:
            print(prompt)
    lim = cfg.limits
    print(f"\n[dry-run] limits: {lim['max_review_fix_cycles']} fix rounds/item, {lim['max_tasks_per_run']} tasks/run, "
          f"{lim['wall_clock_minutes_per_run']} min/run, {lim['max_invocations_per_task']} calls/task, "
          f"{lim['max_invocations_per_run']} calls/run; budget run={a.max_usd_run or cfg.budget.get('max_usd_per_run')} USD")
    print("[dry-run] nothing was executed or written.")
    return 0


def cmd_checks(cfg, a) -> int:
    git = Git(cfg.repo, cfg.git["protected_branches"])
    base = a.base or "HEAD"
    changed = sorted({p for p in git.run("diff", "--name-only", "-z", base).split("\0") if p}
                     | {e.path for e in git.status() if e.code == "??"})
    ids = a.ids.split(",") if a.ids else select_checks(cfg, changed, [], final=a.all)
    if a.all:
        ids = select_checks(cfg, list({p for s in cfg.check_specs().values() for p in s.get("triggers", [])}), [], True)
    ids = ["scope_guard", "owner_gate_guard"] + [i for i in ids if i not in ("scope_guard", "owner_gate_guard")]
    print(f"[checks] {len(changed)} changed path(s) vs {base}; running: {', '.join(ids)}")
    v = Validator(cfg, cfg.state_dir / "native" / "checks")
    res = v.run(ids, git.tree_fingerprint(), {}, force=True, item={"kind": a.kind, "allowed_paths": []},
                changed=changed, diff_text=git.diff_text(base))
    bad = 0
    for cid, r in res.items():
        print(f"  {r['status']:<8} {cid:<20} rc={r.get('rc')} {r.get('duration_s', 0):.0f}s  {(r.get('reason') or r.get('summary') or '')[:150]}")
        bad += r["status"] != "PASS"
    print(f"[checks] logs: {cfg.state_dir / 'native' / 'checks'}")
    return 1 if bad else 0


def cmd_review_pack(cfg, a) -> int:
    git = Git(cfg.repo, cfg.git["protected_branches"])
    base = a.base or "HEAD"
    changed = sorted({p for p in git.run("diff", "--name-only", "-z", base).split("\0") if p}
                     | {e.path for e in git.status() if e.code == "??"})
    out = Path(a.out) if a.out else cfg.state_dir / "native" / f"review-{time.strftime('%Y%m%dT%H%M%S')}"
    review.write_pack(out, git.diff_text(base), {"note": "native session; author claims are untrusted"}, changed)
    revs = review.select_reviewers(cfg, {"reviewers": [], "acceptance_criteria": []}, changed)
    print(json.dumps({"pack": str(out), "diff": str(out / "diff.patch"), "changed": changed,
                      "reviewers": {r: cfg.raw["reviewers"][r]["agent"] for r in revs}}, indent=2))
    return 0


def cmd_gates(cfg, a) -> int:
    for g in gates.describe(cfg):
        print(f"  {'OPEN ' if g['open'] else 'clear'} {g['id']:<11} blocks {g['blocks']}  ({g['detail']})")
        if g["open"]:
            print(f"        owner action: {g['owner_action']}")
    return 0


def cmd_policy(cfg, a) -> int:
    print(f"policy_version {cfg.raw['policy_version']} fingerprint {knowledge.policy_fingerprint(cfg.repo)}")
    for p in knowledge.policy_files(cfg.repo):
        print(f"  {p.relative_to(cfg.repo)}")
    if a.history:
        git = Git(cfg.repo, cfg.git["protected_branches"])
        print(git.run("log", "--format=%h %ad %s", "--date=short", "-20", "--", *[str(p.relative_to(cfg.repo))
                                                                                   for p in knowledge.policy_files(cfg.repo)]))
        print("rollback: `git revert <policy commit>` on a feature branch, then re-run `eval` against the baseline.")
    return 0


def cmd_export_debt(cfg, a) -> int:
    st = StateStore(cfg.state_dir).load()
    md = knowledge.export_markdown(st)
    if a.out:
        Path(a.out).write_text(md, encoding="utf-8")
        print(f"[autopilot] wrote {a.out}")
    else:
        print(md)
    return 0


def cmd_eval(cfg, a) -> int:
    from autopilot import evalbench
    return evalbench.main(cfg, a)


def cmd_canary(cfg, a) -> int:
    from autopilot import canary
    return canary.main(cfg, a)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="aetheria_autopilot", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    def run_flags(p):
        p.add_argument("--max-usd-run", type=float, help="hard cap on estimated USD for this run")
        p.add_argument("--max-tasks", type=int)
        p.add_argument("--minutes", type=float, help="wall-clock budget for this run")
        p.add_argument("--no-push", action="store_true")
        p.add_argument("--no-ci", action="store_true")
        p.add_argument("--no-pr", action="store_true")
        p.add_argument("--allow-planner", action="store_true", help="let the planner add items when the queue empties")
        p.add_argument("--skip-doctor", action="store_true", help=argparse.SUPPRESS)

    p = sub.add_parser("doctor")
    p.add_argument("--no-probe", action="store_true")
    p.add_argument("--force-probe", action="store_true")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("dry-run")
    p.add_argument("--campaign")
    p.add_argument("--mode", default="production", choices=["production", "canary", "test"])
    p.add_argument("--show-prompt", action="store_true")
    run_flags(p)
    p = sub.add_parser("status")
    p.add_argument("--json", action="store_true")
    p = sub.add_parser("start")
    p.add_argument("--campaign", required=True)
    p.add_argument("--mode", default="production", choices=["production", "canary", "test"])
    p.add_argument("--activate", action="store_true", help="the owner's explicit command to run a production campaign")
    p.add_argument("--init-only", action="store_true")
    run_flags(p)
    p = sub.add_parser("resume")
    run_flags(p)
    p = sub.add_parser("stop")
    p.add_argument("--now", action="store_true", help="also SIGTERM the running supervisor")
    p = sub.add_parser("retry")
    p.add_argument("item")
    p.add_argument("--reason", default="owner retry")
    sub.add_parser("gates")
    p = sub.add_parser("checks")
    p.add_argument("--base")
    p.add_argument("--ids")
    p.add_argument("--all", action="store_true")
    p.add_argument("--kind", default="task")
    p = sub.add_parser("review-pack")
    p.add_argument("--base")
    p.add_argument("--out")
    p = sub.add_parser("policy")
    p.add_argument("--history", action="store_true")
    p = sub.add_parser("export-debt")
    p.add_argument("--out")
    p = sub.add_parser("eval")
    p.add_argument("--cases", default=str(HERE / "eval" / "cases"))
    p.add_argument("--max-usd", type=float, required=False)
    p.add_argument("--promote", action="store_true", help="record this score as the baseline if it is not worse")
    p = sub.add_parser("canary")
    p.add_argument("--max-usd-run", type=float, required=False)
    p.add_argument("--keep", action="store_true")
    p.add_argument("--worktree")
    a = ap.parse_args(argv)
    try:
        cfg = load_config()
    except ConfigError as e:
        print(f"[autopilot] CONFIG ERROR: {e}")
        return EXIT_CONFIG
    if a.cmd == "doctor":
        d = doctor(cfg, probe=not a.no_probe, force_probe=a.force_probe)
        if a.json:
            print(json.dumps(d, indent=2, default=str))
        else:
            print_doctor(d)
        return 0 if d["verdict"] == "AUTONOMOUS_READY" else 1
    handlers = {"dry-run": cmd_dry_run, "start": cmd_start, "resume": cmd_resume, "stop": cmd_stop,
                "retry": cmd_retry, "gates": cmd_gates, "checks": cmd_checks, "review-pack": cmd_review_pack,
                "policy": cmd_policy, "export-debt": cmd_export_debt, "eval": cmd_eval, "canary": cmd_canary}
    if a.cmd == "status":
        return print_status(cfg, a.json)
    return handlers[a.cmd](cfg, a)


if __name__ == "__main__":
    sys.exit(main())
