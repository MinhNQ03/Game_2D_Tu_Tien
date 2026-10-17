"""GitHub integration through the `gh` CLI: exact-SHA CI status and an idempotent draft PR.

Only three gh operations are used: `gh api` GET, `gh pr list`, `gh pr create --draft`. Nothing
here can merge, close, approve or change a protected branch.
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import time


class CIUnavailable(Exception):
    pass


def _gh(args: list[str], cwd, timeout: int = 60) -> tuple[int, str, str]:
    if args[0] not in ("api", "pr", "auth"):
        raise ValueError(f"gh {args[0]} is not allowed")
    if args[0] == "api" and any(a in ("-X", "--method", "-f", "-F", "--field", "--raw-field", "--input") for a in args):
        raise ValueError("gh api is GET-only here")
    if args[0] == "pr" and args[1] not in ("list", "create", "view"):
        raise ValueError(f"gh pr {args[1]} is not allowed")
    if args[0] == "pr" and args[1] == "create" and "--draft" not in args:
        raise ValueError("only draft PRs may be created")
    exe = shutil.which("gh")
    if not exe:
        raise CIUnavailable("gh CLI not installed")
    try:
        p = subprocess.run([exe, *args], cwd=cwd, capture_output=True, text=True, timeout=timeout,
                           env={**__import__("os").environ, "GH_PROMPT_DISABLED": "1", "NO_COLOR": "1"})
    except subprocess.TimeoutExpired as e:
        raise CIUnavailable(f"gh {' '.join(args[:2])} timed out") from e
    return p.returncode, p.stdout, p.stderr


def repo_slug(remote_url: str) -> str | None:
    m = re.search(r"github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$", remote_url.strip())
    return f"{m.group(1)}/{m.group(2)}" if m else None


class GitHub:
    def __init__(self, repo_dir, slug: str | None, gh=_gh, sleep=time.sleep, clock=time.monotonic):
        self.dir = repo_dir
        self.slug = slug
        self._gh = gh
        self._sleep = sleep
        self._clock = clock

    def available(self) -> tuple[bool, str]:
        if not self.slug:
            return False, "origin is not a GitHub remote"
        try:
            rc, out, err = self._gh(["auth", "status"], self.dir)
        except CIUnavailable as e:
            return False, str(e)
        return (rc == 0), ("authenticated" if rc == 0 else (err or out).strip()[:200])

    def check_runs(self, sha: str) -> list[dict]:
        rc, out, err = self._gh(["api", f"repos/{self.slug}/commits/{sha}/check-runs?per_page=100"], self.dir)
        if rc != 0:
            raise CIUnavailable(f"check-runs query failed: {(err or out).strip()[:200]}")
        try:
            return json.loads(out).get("check_runs", [])
        except json.JSONDecodeError as e:
            raise CIUnavailable("check-runs response is not JSON") from e

    def annotations(self, run: dict) -> list[str]:
        url = run.get("output", {}).get("annotations_url", "")
        m = re.search(r"repos/.+$", url)
        if not m:
            return []
        rc, out, _ = self._gh(["api", m.group(0)], self.dir)
        if rc != 0:
            return []
        try:
            return [f"{a.get('path')}:{a.get('start_line')}: {a.get('message')}"[:400] for a in json.loads(out)]
        except (json.JSONDecodeError, TypeError):
            return []

    def wait_for_ci(self, sha: str, timeout_s: int, interval_s: int, should_stop=lambda: False) -> dict:
        """Poll until every check run on `sha` completed, the timeout passes, or a stop is asked.
        Returns {conclusion: success|failure|timeout|stopped|none, runs: [...], annotations: [...]}"""
        deadline = self._clock() + timeout_s
        seen_any = False
        while True:
            runs = self.check_runs(sha)
            if runs:
                seen_any = True
                if all(r.get("status") == "completed" for r in runs):
                    bad = [r for r in runs if r.get("conclusion") not in ("success", "skipped", "neutral")]
                    ann = []
                    for r in bad[:3]:
                        ann += self.annotations(r)
                    return {"conclusion": "failure" if bad else "success", "sha": sha,
                            "runs": [{"name": r.get("name"), "conclusion": r.get("conclusion"),
                                      "url": r.get("html_url")} for r in runs], "annotations": ann[:40]}
            if should_stop():
                return {"conclusion": "stopped", "sha": sha, "runs": [], "annotations": []}
            if self._clock() >= deadline:
                return {"conclusion": "timeout" if seen_any else "none", "sha": sha, "runs": [], "annotations": []}
            self._sleep(interval_s)

    def ensure_draft_pr(self, branch: str, base: str, title: str, body: str) -> str | None:
        rc, out, err = self._gh(["pr", "list", "--head", branch, "--state", "open", "--json", "url,isDraft"], self.dir)
        if rc == 0:
            try:
                prs = json.loads(out)
                if prs:
                    return prs[0]["url"]
            except json.JSONDecodeError:
                pass
        rc, out, err = self._gh(["pr", "create", "--draft", "--base", base, "--head", branch,
                                 "--title", title, "--body", body], self.dir, timeout=120)
        if rc != 0:
            raise CIUnavailable(f"draft PR creation failed: {(err or out).strip()[:300]}")
        m = re.search(r"https://github\.com/\S+/pull/\d+", out)
        return m.group(0) if m else out.strip()[:200]
