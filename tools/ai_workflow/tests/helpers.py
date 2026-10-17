"""Test fixtures: a throwaway git repository with a bare local remote, a reduced config, the real
reviewer agent files, and the owner-gate documents in their real shape."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
AI = HERE.parent
REAL_REPO = AI.parents[1]
sys.path.insert(0, str(AI))

FAKE = HERE / "fake_claude.py"
MODEL = "claude-opus-5-5"


def sh(cwd, *args, check=True):
    p = subprocess.run(list(args), cwd=cwd, capture_output=True, text=True)
    if check and p.returncode != 0:
        raise RuntimeError(f"{args} -> {p.returncode}: {p.stderr}")
    return p.stdout.strip()


def ok(text="ok", **kw):
    return {"structured": {"status": "IMPLEMENTED", "summary": text, "changed_paths": [], "criteria_claims": [],
                           "tests_run": [], "known_limitations": [], "blocker": None, **kw}}


def review_pass(criteria=("C1",)):
    return {"structured": {"verdict": "PASS", "summary": "fine", "inspected": ["pkg/core.py"], "findings": [],
                           "criteria": [{"id": c, "met": True, "evidence": "seen"} for c in criteria], "limitations": []}}


def review_reject(title="add() ignores negative numbers", severity="P1", file="pkg/core.py", line=1, criteria=("C1",)):
    return {"structured": {"verdict": "CHANGES_REQUIRED", "summary": "defect", "inspected": [file],
                           "findings": [{"title": title, "severity": severity, "file": file, "line": line,
                                         "evidence": "read it", "reproduction": "call add(-1, 1)",
                                         "recommendation": "handle it", "confidence": "high", "criterion": "C1"}],
                           "criteria": [{"id": c, "met": False, "evidence": "not yet"} for c in criteria],
                           "limitations": []}}


def item(iid="t1", **kw):
    base = {
        "id": iid, "title": f"Task {iid}", "objective": f"Implement {iid} in pkg",
        "scopes": ["test"], "in_scope": ["pkg/"], "tasks": ["edit pkg"],
        "acceptance_criteria": [{"id": "C1", "text": "pkg works", "evidence": ["check:unit", "review:qa"]}],
        "required_checks": ["unit"], "allowed_paths": ["pkg/**", "docs/notes/**"],
    }
    base.update(kw)
    return base


class RepoCase(unittest.TestCase):
    """Each test gets a fresh repo at self.repo on branch feat/test (pushed to a bare remote)."""

    godot = False

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="autopilot-test-"))
        self.repo = self.tmp / "repo"
        self.remote = self.tmp / "remote.git"
        self.scenario = self.tmp / "scenario.json"
        self.repo.mkdir()
        sh(self.tmp, "git", "init", "-q", "--bare", "-b", "main", str(self.remote))
        sh(self.repo, "git", "init", "-q", "-b", "main")
        sh(self.repo, "git", "config", "user.email", "t@example.com")
        sh(self.repo, "git", "config", "user.name", "Test")
        sh(self.repo, "git", "config", "commit.gpgsign", "false")
        cfg = json.loads((AI / "autopilot_config.json").read_text())
        py = sys.executable
        cfg["environment"]["python"] = py
        cfg["environment"]["godot_bin_candidates"] = ["$AETHERIA_GODOT"] + (
            [str(self.tmp / "fakegodot")] if self.godot else ["/nonexistent/godot"])
        cfg["checks"] = {
            "lint": {"cmd": ["{python}", "-c", "print('lint ok')"], "always": True, "timeout": 60},
            "unit": {"cmd": ["{python}", "-m", "unittest", "discover", "-s", "pkg", "-v"], "triggers": ["pkg/**"],
                     "require_patterns": ["\\nOK"], "timeout": 120},
            "godot_suite": {"cmd": ["{godot}", "--version"], "needs": ["godot"], "triggers": ["game/**"], "timeout": 60},
        }
        cfg["reviewers"] = {k: v for k, v in cfg["reviewers"].items() if k in ("architecture", "qa", "ui_ux")}
        cfg["reviewers"]["ui_ux"]["triggers"] = ["game/ui/**"]
        cfg["paths"]["default_allowed_write"] = ["pkg/**", "docs/**", "game/**"]
        cfg["git"].update({"push": True, "require_ci_success": False, "create_draft_pr": False,
                           "push_branch_patterns": ["feat/*"]})
        cfg["limits"]["ci_poll_interval_seconds"] = 1
        cfg["limits"]["ci_poll_timeout_seconds"] = 3
        cfg["permissions"]["max_parallel_reviewers"] = 2
        cfg["planner"]["source_docs"] = ["docs/ROADMAP.md"]
        self.cfg_raw = cfg
        self.write_config()
        (self.repo / ".claude" / "agents").mkdir(parents=True)
        for p in (REAL_REPO / ".claude" / "agents").glob("*.md"):
            shutil.copy(p, self.repo / ".claude" / "agents" / p.name)
        self.w("docs/handoff/pre-phase-21-hardening.md",
               "| H21-14 | **OPEN / OWNER REQUIRED** | the project owner | §17.6 played |\n")
        self.w("docs/handoff/experience-art-intelligence-upgrade.md",
               "| ART-DIR-01 / 02 | §3 | the owner | a decision |\n")
        self.w("docs/ROADMAP.md", "## Phase 21 — Dungeon\nNOT STARTED\n")
        self.w("pkg/core.py", "def add(a, b):\n    return a + b\n")
        self.w("pkg/test_core.py", "import unittest\nfrom core import add\n\n\nclass T(unittest.TestCase):\n"
               "    def test_add(self):\n        self.assertEqual(add(1, 2), 3)\n")
        self.w(".gitignore", "__pycache__/\n.aetheria-autopilot/\n")
        sh(self.repo, "git", "add", "-A")
        sh(self.repo, "git", "commit", "-q", "-m", "base")
        sh(self.repo, "git", "remote", "add", "origin", str(self.remote))
        sh(self.repo, "git", "push", "-q", "origin", "main")
        sh(self.repo, "git", "switch", "-q", "-c", "feat/test")
        self.base = sh(self.repo, "git", "rev-parse", "HEAD")
        if self.godot:
            g = self.tmp / "fakegodot"
            g.write_text("#!/bin/sh\necho 4.7.2.stable.fake\n")
            g.chmod(0o755)
        self.env_backup = dict(os.environ)
        os.environ["AETHERIA_AUTOPILOT_REPO"] = str(self.repo)
        os.environ["AETHERIA_AUTOPILOT_CLAUDE_BIN"] = str(FAKE)
        os.environ["FAKE_CLAUDE_SCENARIO"] = str(self.scenario)
        os.environ.pop("AETHERIA_AUTOPILOT_STATE_DIR", None)
        os.environ.pop("AETHERIA_GODOT", None)
        os.environ.pop("AETHERIA_AUTOPILOT_ROLE", None)
        os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
        self.scenario_set({})

    def tearDown(self):
        os.environ.clear()
        os.environ.update(self.env_backup)
        shutil.rmtree(self.tmp, ignore_errors=True)

    # --- helpers -------------------------------------------------------------------------------
    def w(self, rel, text):
        p = self.repo / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text)

    def write_config(self):
        p = self.repo / "tools" / "ai_workflow" / "autopilot_config.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(self.cfg_raw, indent=2))

    def scenario_set(self, scen: dict):
        self.scenario.write_text(json.dumps(scen))
        for f in ("fake_counter.json",):
            (self.tmp / f).unlink(missing_ok=True)

    def calls(self) -> list[dict]:
        p = self.tmp / "fake_calls.jsonl"
        return [json.loads(x) for x in p.read_text().splitlines()] if p.exists() else []

    def campaign(self, items, **kw) -> Path:
        c = {"id": "test-campaign", "branch": "feat/test", "items": items, **kw}
        p = self.tmp / "campaign.json"
        p.write_text(json.dumps(c))
        return p

    def cfg(self):
        from autopilot.config import load_config
        return load_config(self.repo)

    def sup(self, **opts):
        from autopilot.supervisor import RunOptions, Supervisor
        o = RunOptions(max_usd_run=opts.pop("max_usd_run", 50.0), **opts)
        return Supervisor(self.cfg(), o, github=getattr(self, "github", None))

    def start(self, items, mode="test", **opts):
        s = self.sup(**opts)
        s.init_campaign(self.campaign(items), mode, activate=(mode == "production"))
        return s, s.run()

    def state(self):
        from autopilot.state import StateStore
        return StateStore(self.repo / ".aetheria-autopilot").load()

    def commits_for(self, iid):
        out = sh(self.repo, "git", "log", "--format=%H%x00%B%x1e", f"{self.base}..HEAD")
        return [r.split("\x00")[0].strip() for r in out.split("\x1e") if f"Autopilot-Item: {iid}\n" in r]
