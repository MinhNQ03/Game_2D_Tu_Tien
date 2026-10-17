#!/usr/bin/env python3
"""PreToolUse guard for Aetheria (Claude Code hook). Stateless and deterministic: the same event
always yields the same decision, and the hook never writes, commits or changes autopilot state,
so a repeated or replayed hook event cannot duplicate anything.

Roles (env AETHERIA_AUTOPILOT_ROLE):
  unset     an interactive session: destructive git and edits of owner files -> "ask";
            edits while an autopilot run holds the repository lock -> "deny"
  worker    an autopilot implementation/fix worker: writes only inside its allowed paths
  reviewer  an autopilot reviewer/planner: read-only
"""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))  # tools/ai_workflow

from autopilot.util import path_matches  # noqa: E402

PROTECTED_OWNER = ["CLAUDE.md", ".kiro/settings/**"]
SECRETS = [".env", ".env.*", "**/*.pem", "**/*.key", "**/id_rsa*", "**/credentials*", "**/.netrc",
           ".git/config"]

DESTRUCTIVE = [
    (r"\bgit\s+reset\s+(--hard|--merge|--keep)\b", "git reset discards work"),
    (r"\bgit\s+clean\b", "git clean deletes untracked files"),
    (r"\bgit\s+push\b[^\n;&|]*(\s--force\b|\s-f\b|--force-with-lease|--force-if-includes|\s--delete\b|\s-d\b|\s--mirror\b|\s\+\S)",
     "forced or deleting push"),
    (r"\bgit\s+push\b[^\n;&|]*\s(\S*:)?(main|master)\s*($|[;&|])", "push to a protected branch"),
    (r"\bgit\s+rebase\b", "history rewrite (rebase)"),
    (r"\bgit\s+(filter-branch|filter-repo|replace)\b", "history rewrite"),
    (r"\bgit\s+checkout\s+(-f\b|--\s|\.\s*($|[;&|]))", "checkout discarding changes"),
    (r"\bgit\s+restore\b", "git restore discards changes"),
    (r"\bgit\s+branch\s+(-D|--delete\s+--force|-d)\b", "branch deletion"),
    (r"\bgit\s+stash\s+(drop|clear)\b", "stash deletion"),
    (r"\bgit\s+update-ref\s+-d\b", "ref deletion"),
    (r"\bgit\s+commit\b[^\n;&|]*--amend\b", "amending a commit rewrites history"),
    (r"\bgit\s+merge\b[^\n;&|]*\b(main|master)\b", "merge involving a protected branch"),
    (r"\brm\s+-[a-zA-Z]*r[a-zA-Z]*f?\s+(/|~|\$HOME|\*|\.\s*($|[;&|])|\.\.)", "recursive delete of a broad path"),
]
ALWAYS_DENY = [
    (r"--dangerously-skip-permissions|--allow-dangerously-skip-permissions|bypassPermissions",
     "global permission bypass is never allowed"),
]
GIT_WRITE = r"\bgit\s+(add|commit|push|reset|clean|checkout|switch|restore|stash|rebase|merge|branch|tag|rm|mv|cherry-pick|revert|am|apply)\b"
REDIRECT = re.compile(r"(?<![0-9&])>{1,2}\s*([^\s;&|]+)")


_GIT_GLOBALS = re.compile(r"\bgit((?:\s+(?:(?:-C|-c|--git-dir|--work-tree|--namespace|--exec-path)(?:\s+|=)\S+"
                         r"|--no-pager|--paginate|-p|-P|--bare|--no-replace-objects|--literal-pathspecs|--no-optional-locks)))+\s+")


def normalize_git(cmd: str) -> str:
    """`git -C . -c a=b --no-pager reset --hard` -> `git reset --hard`, so global options cannot
    hide a destructive subcommand from the patterns below."""
    return _GIT_GLOBALS.sub("git ", cmd)


def repo_root() -> Path:
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    return Path(env).resolve() if env else HERE.parents[3]


_BASE: list[Path] = []  # the event's cwd (set in decide); relative paths resolve against it


def rel(path: str, root: Path) -> str | None:
    try:
        p = Path(os.path.expanduser(path))
        if not p.is_absolute():
            p = (_BASE[0] if _BASE else root) / p
        return str(p.resolve().relative_to(root))
    except (ValueError, OSError):
        return None


def autopilot_lock_active(root: Path) -> dict | None:
    state_dir = Path(os.environ.get("AETHERIA_AUTOPILOT_STATE_DIR") or root / ".aetheria-autopilot")
    info_p = state_dir / "lock.json"
    try:
        info = json.loads(info_p.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return None
    if info.get("released_at"):
        return None
    try:
        os.kill(int(info.get("pid", -1)), 0)
    except (ProcessLookupError, ValueError):
        return None
    except PermissionError:
        pass
    return info


def decide(event: dict, env: dict, root: Path) -> tuple[str | None, str]:
    _BASE[:] = [Path(event["cwd"])] if event.get("cwd") else [root]
    role = env.get("AETHERIA_AUTOPILOT_ROLE") or ""
    tool = event.get("tool_name", "")
    ti = event.get("tool_input") or {}
    strict = role in ("worker", "reviewer")

    if tool == "Bash":
        cmd = normalize_git(str(ti.get("command", "")))
        for rx, why in ALWAYS_DENY:
            if re.search(rx, cmd):
                return "deny", why
        for rx, why in DESTRUCTIVE:
            if re.search(rx, cmd):
                return ("deny" if strict else "ask"), f"{why}: needs the owner's explicit approval"
        if strict and re.search(GIT_WRITE, cmd):
            return "deny", "autopilot workers and reviewers never write to git; the supervisor checkpoints"
        if strict:
            allowed = json.loads(env.get("AETHERIA_AUTOPILOT_ALLOWED_PATHS") or "[]") if role == "worker" else []
            for target in REDIRECT.findall(cmd):
                if target in ("/dev/null", "&1", "&2") or target.startswith("/tmp/"):
                    continue
                r = rel(target, root)
                if role == "reviewer" or r is None or not path_matches(r, allowed):
                    return "deny", f"shell redirection writes {target} outside the allowed paths"
        secret_like = [s for s in SECRETS if s != ".git/config"]
        for tok in re.split(r"[\s;&|<>'\"=]+", cmd):
            if not tok or tok.startswith("-"):
                continue
            r = rel(tok, root) or tok.lstrip("./")
            if path_matches(r, secret_like) or path_matches(Path(tok).name, secret_like):
                return ("deny" if strict else "ask"), f"the command touches a credential-shaped file ({tok})"
        return None, ""

    if tool in ("Read",):
        r = rel(str(ti.get("file_path", "")), root)
        if r and path_matches(r, SECRETS) and r != ".git/config":
            return ("deny" if strict else "ask"), f"{r} may hold credentials"
        return None, ""

    if tool in ("Edit", "Write", "MultiEdit", "NotebookEdit"):
        target = str(ti.get("file_path") or ti.get("notebook_path") or "")
        r = rel(target, root)
        if role == "reviewer":
            return "deny", "reviewers are read-only"
        if role == "worker":
            if r is None:
                return "deny", f"{target} is outside the repository"
            protected = PROTECTED_OWNER + SECRETS + [".git/**", ".aetheria-autopilot/**"]
            if path_matches(r, protected):
                return "deny", f"{r} is protected (owner file, credentials, git internals or autopilot state)"
            allowed = json.loads(env.get("AETHERIA_AUTOPILOT_ALLOWED_PATHS") or "[]")
            if not path_matches(r, allowed):
                return "deny", f"{r} is outside this work item's allowed paths"
            return None, ""
        # interactive session
        lock = autopilot_lock_active(root)
        if lock and r is not None:
            return "deny", (f"autopilot run {lock.get('run_id')} (pid {lock.get('pid')}) is writing this worktree; "
                            "stop it (aetheria_autopilot.py stop) or work in another worktree")
        if r and path_matches(r, PROTECTED_OWNER):
            return "ask", f"{r} is owner-managed"
        if r and r.startswith(".git/"):
            return "deny", "editing git internals directly is never needed"
        return None, ""
    return None, ""


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0  # not our event shape: no opinion (never block on a parse problem)
    decision, reason = decide(event, dict(os.environ), repo_root())
    if decision:
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
                                                 "permissionDecision": decision,
                                                 "permissionDecisionReason": f"[aetheria-guard] {reason}"}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
