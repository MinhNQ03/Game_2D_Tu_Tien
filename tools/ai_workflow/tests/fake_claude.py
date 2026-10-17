#!/usr/bin/env python3
"""A scripted stand-in for the Claude Code CLI, used ONLY by the orchestrator's own tests.

It never pretends a real model ran: its envelope names whatever model the scenario says, and the
tests assert the supervisor's reaction to exactly that. Scenario file (env FAKE_CLAUDE_SCENARIO):

  {"implement": [step, step, ...], "fix": [...], "review:qa": [...], "plan": [...], "probe": [...]}

The Nth call of a kind uses step N (the last step repeats). A step may hold:
  write {path: text}  delete [path]  structured {...}  result "text"  served_by [model]
  usd 0.1  is_error true  api_error_status 404  subtype "error_max_turns"  rc 1
  raw "not json"  sleep seconds  hang true
"""

import json
import os
import re
import sys
import time
from pathlib import Path


def main() -> int:
    argv = sys.argv[1:]
    if argv and argv[0] in ("--version", "-v"):
        print("2.1.291 (Claude Code) [fake]")
        return 0
    if argv[:2] == ["auth", "status"]:
        print(json.dumps({"loggedIn": True, "authMethod": "fake"}))
        return 0
    model = argv[argv.index("--model") + 1] if "--model" in argv else None
    prompt = sys.stdin.read()
    if prompt.startswith("# Work item"):
        kind = "implement"
    elif prompt.startswith("# Fix round"):
        kind = "fix"
    elif prompt.startswith("# Independent review"):
        m = re.search(r"role `([a-z_]+)`", prompt)
        kind = f"review:{m.group(1) if m else '?'}"
    elif prompt.startswith("# Plan the next"):
        kind = "plan"
    else:
        kind = "probe"
    sdir = Path(os.environ["FAKE_CLAUDE_SCENARIO"]).parent
    scen = json.loads(Path(os.environ["FAKE_CLAUDE_SCENARIO"]).read_text())
    counter_p = sdir / "fake_counter.json"
    counters = json.loads(counter_p.read_text()) if counter_p.exists() else {}
    n = counters.get(kind, 0)
    counters[kind] = n + 1
    counter_p.write_text(json.dumps(counters))
    with open(sdir / "fake_calls.jsonl", "a") as fh:
        fh.write(json.dumps({"kind": kind, "n": n, "argv": argv, "role_env": os.environ.get("AETHERIA_AUTOPILOT_ROLE"),
                             "item": os.environ.get("AETHERIA_AUTOPILOT_ITEM"),
                             "aux_model": os.environ.get("ANTHROPIC_DEFAULT_HAIKU_MODEL"),
                             "prompt_head": prompt[:300],
                             "resume_note": "interrupted attempt" in prompt,
                             "git_cred_helper": os.environ.get("GIT_CONFIG_VALUE_0"),
                             "git_askpass": os.environ.get("GIT_ASKPASS"),
                             "gh_token": os.environ.get("GH_TOKEN"),
                             "git_config_global": os.environ.get("GIT_CONFIG_GLOBAL")}) + "\n")
    steps = scen.get(kind) or scen.get(kind.split(":")[0]) or [{}]
    step = steps[min(n, len(steps) - 1)]
    for path, text in (step.get("write") or {}).items():
        p = Path.cwd() / path
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)
    for path in step.get("delete") or []:
        try:
            (Path.cwd() / path).unlink()
        except FileNotFoundError:
            pass
    for cmd in step.get("shell") or []:  # a misbehaving worker (tests of the git invariant)
        import subprocess
        subprocess.run(cmd, cwd=Path.cwd(), capture_output=True)
    if step.get("hang"):  # partial work is already on disk, like a real worker mid-task
        time.sleep(3600)
    if step.get("sleep"):
        time.sleep(step["sleep"])
    if "raw" in step:
        print(step["raw"])
        return step.get("rc", 1)
    cap = float(argv[argv.index("--max-budget-usd") + 1]) if "--max-budget-usd" in argv else None
    if cap is not None and step.get("usd", 0.01) > cap:  # the real CLI stops a call at its cap
        print(json.dumps({"type": "result", "subtype": "error_max_budget_usd", "is_error": True,
                          "total_cost_usd": cap, "result": "Exceeded USD budget", "modelUsage": {model: {}}}))
        return 1
    served = step.get("served_by", [model] if model else [])
    structured = step.get("structured")
    env = {
        "type": "result", "subtype": step.get("subtype", "success"), "is_error": bool(step.get("is_error")),
        "api_error_status": step.get("api_error_status"), "num_turns": 3, "session_id": f"fake-{kind}-{n}",
        "total_cost_usd": step.get("usd", 0.01), "result": step.get("result", json.dumps(structured) if structured else "ok"),
        "modelUsage": {m: {"costUSD": step.get("usd", 0.01)} for m in served},
        "permission_denials": step.get("denials", []),
    }
    if structured is not None:
        env["structured_output"] = structured
    print(json.dumps(env))
    return step.get("rc", 1 if step.get("is_error") else 0)


if __name__ == "__main__":
    sys.exit(main())
