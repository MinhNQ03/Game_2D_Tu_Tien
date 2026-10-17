"""Unit tests for the safety-critical pieces: globbing, redaction, atomic state, transitions,
the git allowlist, the lock, the hook guard, the CLI runner and prompt validation."""

import json
import os
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

from tests.helpers import AI, FAKE, MODEL, RepoCase, item, sh

from autopilot import gates, prompts, review
from autopilot.claude_runner import ClaudeRunner, Invocation, check_schema
from autopilot.gitops import Git, GitSafetyError
from autopilot.lock import LockHeld, RepoLock
from autopilot.state import (StateError, StateStore, TransitionError, empty_state, new_item, transition,
                             validate_state)
from autopilot.util import atomic_write_json, path_matches, read_jsonl, redact

GUARD = AI / "hooks" / "guard_tool.py"


class Util(unittest.TestCase):
    def test_glob(self):
        self.assertTrue(path_matches("src/a/b.gd", ["src/**"]))
        self.assertTrue(path_matches("x/y/z.pem", ["**/*.pem"]))
        self.assertTrue(path_matches("a.pem", ["**/*.pem"]))
        self.assertFalse(path_matches("tools/sub/x.py", ["tools/*.py"]))
        self.assertTrue(path_matches(".claude/agents/a.md", [".claude/**"]))
        self.assertTrue(path_matches("./CLAUDE.md", ["CLAUDE.md"]))
        self.assertFalse(path_matches("docs/CLAUDE.md", ["CLAUDE.md"]))

    def test_redaction(self):
        for secret in ("sk-ant-api03-abcdefghijklmnop", "ghp_" + "a" * 36, "token=abcdef1234567890XYZ",
                       "Authorization: Bearer abcdefghijklmnopqrstu"):
            self.assertNotIn(secret.split("=")[-1].split()[-1], redact(f"x {secret} y"), secret)
        self.assertEqual(redact("plain text 123"), "plain text 123")

    def test_atomic_write_survives_a_crash_mid_replace(self):
        d = Path(tempfile.mkdtemp())
        p = d / "s.json"
        atomic_write_json(p, {"v": 1})
        with mock.patch("os.replace", side_effect=OSError("power loss")):
            with self.assertRaises(OSError):
                atomic_write_json(p, {"v": 2})
        self.assertEqual(json.loads(p.read_text()), {"v": 1})
        self.assertEqual([x.name for x in d.iterdir()], ["s.json"])  # no temp litter

    def test_torn_audit_line_is_skipped(self):
        d = Path(tempfile.mkdtemp())
        p = d / "a.jsonl"
        p.write_text('{"a": 1}\n{"b": 2}\n{"c": ')
        self.assertEqual(read_jsonl(p), [{"a": 1}, {"b": 2}])


class StateSchema(unittest.TestCase):
    def mk(self):
        st = empty_state({"id": "c", "branch": "feat/x", "base_sha": "a" * 40, "mode": "test"})
        for i in ("a", "b"):
            it = new_item(item(i))
            st["items"][i] = it
            st["order"].append(i)
        return st

    def test_valid_and_invalid(self):
        st = self.mk()
        self.assertEqual(validate_state(st), [])
        bad = json.loads(json.dumps(st))
        bad["items"]["a"]["status"] = "DONE"
        self.assertTrue(any("unknown status" in e for e in validate_state(bad)))
        bad = json.loads(json.dumps(st))
        bad["items"]["a"]["status"] = "COMPLETE"
        self.assertTrue(any("checkpoint_sha" in e for e in validate_state(bad)))
        bad = json.loads(json.dumps(st))
        bad["items"]["a"]["depends_on"] = ["b"]
        bad["items"]["b"]["depends_on"] = ["a"]
        self.assertTrue(any("cycle" in e for e in validate_state(bad)))
        bad = json.loads(json.dumps(st))
        bad["order"].append("ghost")
        self.assertTrue(validate_state(bad))
        bad = json.loads(json.dumps(st))
        bad["items"]["a"]["acceptance_criteria"] = [{"id": "C1", "text": "x", "evidence": []}]
        self.assertTrue(any("evidence" in e for e in validate_state(bad)))

    def test_transitions_are_checked_and_idempotent(self):
        st = self.mk()
        with self.assertRaises(TransitionError):
            transition(st, "a", "COMPLETE")
        with self.assertRaises(TransitionError):
            transition(st, "a", "CHECKPOINTED")
        self.assertTrue(transition(st, "a", "IN_PROGRESS", event_id="e1"))
        self.assertFalse(transition(st, "a", "IN_PROGRESS", event_id="e1"))  # replayed hook/event
        self.assertEqual(len(st["items"]["a"]["history"]), 1)
        with self.assertRaises(TransitionError):
            transition(st, "a", "BLOCKED_OWNER")  # needs an owner action
        transition(st, "a", "BLOCKED_OWNER", owner_action="play the build")
        with self.assertRaises(TransitionError):
            transition(st, "a", "IN_PROGRESS")  # only back to QUEUED

    def test_store_refuses_invalid_and_keeps_backup(self):
        d = Path(tempfile.mkdtemp())
        store = StateStore(d)
        st = self.mk()
        store.save(st)
        store.save(st)
        bad = json.loads(json.dumps(st))
        bad["items"]["a"]["status"] = "NOPE"
        with self.assertRaises(StateError):
            store.save(bad)
        self.assertEqual(store.load()["revision"], 2)
        (d / "state.json").write_text("garbage")
        self.assertEqual(store.load()["revision"], 1)
        (d / "state.json.bak").write_text("{}")
        with self.assertRaises(StateError):
            store.load()
        self.assertTrue((d / ".gitignore").read_text().startswith("*"))
        self.assertTrue((d / ".gdignore").exists())


class GitAllowlist(RepoCase):
    def test_destructive_operations_are_refused_before_running(self):
        g = Git(self.repo, ["main", "master"])
        head = g.head()
        refused = [("reset", "--hard"), ("clean", "-fd"), ("rebase", "main"), ("merge", "main"),
                   ("push", "--force", "origin", "feat/test"), ("push", "origin", "main"),
                   ("push", "origin", "+feat/test"), ("push", "origin", "feat/test:main"),
                   ("push", "origin", ":feat/test"), ("add", "-A"), ("add", "."), ("commit", "--amend", "-m", "x"),
                   ("commit", "--no-verify", "-m", "x"), ("branch", "-D", "feat/test"), ("switch", "main"),
                   ("restore", "pkg/core.py"), ("stash",), ("checkout", "--", "."), ("config", "user.name", "x"),
                   ("-C", "/", "status"), ("worktree", "remove", "x"), ("filter-branch",)]
        for args in refused:
            with self.assertRaises(GitSafetyError, msg=str(args)):
                g.run(*args)
        self.assertEqual(g.head(), head)
        with self.assertRaises(GitSafetyError):
            g.create_branch("main", head)

    def test_stage_exact_verifies_the_index(self):
        g = Git(self.repo)
        self.w("pkg/a.py", "a\n")
        self.w("pkg/b.py", "b\n")
        staged = g.stage_exact(["pkg/a.py"])
        self.assertEqual(staged, ["pkg/a.py"])
        with self.assertRaises(GitSafetyError):
            g.stage_exact(["pkg/b.py"])  # index already holds something
        self.assertIn("pkg/b.py", g.changed_paths())  # untouched, unstaged

    def test_create_branch_refuses_a_dirty_tree(self):
        g = Git(self.repo)
        self.w("pkg/wip.py", "x\n")
        with self.assertRaises(GitSafetyError):
            g.create_branch("feat/new", g.head())
        self.assertTrue((self.repo / "pkg/wip.py").exists())

    def test_fingerprint_tracks_untracked_content(self):
        g = Git(self.repo)
        a = g.tree_fingerprint()
        self.w("pkg/n.py", "1\n")
        b = g.tree_fingerprint()
        self.w("pkg/n.py", "2\n")
        c = g.tree_fingerprint()
        self.assertEqual(len({a, b, c}), 3)


class Lock(unittest.TestCase):
    def test_exclusive_and_crash_safe(self):
        d = Path(tempfile.mkdtemp())
        code = ("import sys,time; sys.path.insert(0, %r); from autopilot.lock import RepoLock; "
                "l=RepoLock(%r); l.acquire('holder'); print('held', flush=True); time.sleep(60)") % (str(AI), str(d))
        p = subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.PIPE, text=True)
        self.assertEqual(p.stdout.readline().strip(), "held")
        with self.assertRaises(LockHeld) as cm:
            RepoLock(d).acquire("second")
        self.assertEqual(cm.exception.holder.get("run_id"), "holder")
        self.assertTrue(RepoLock(d).is_held_by_other())
        p.send_signal(signal.SIGKILL)  # a crash: no release, no cleanup
        p.wait()
        lk = RepoLock(d)
        lk.acquire("after-crash")  # the kernel dropped the lock with the process
        self.assertEqual(lk.recovered_stale.get("run_id"), "holder")
        lk.release()
        self.assertFalse(RepoLock(d).is_held_by_other())


class HookGuard(unittest.TestCase):
    def run_hook(self, event, role=None, allowed=None, project=None):
        env = {k: v for k, v in os.environ.items() if not k.startswith("AETHERIA_AUTOPILOT")}
        if role:
            env["AETHERIA_AUTOPILOT_ROLE"] = role
        if allowed is not None:
            env["AETHERIA_AUTOPILOT_ALLOWED_PATHS"] = json.dumps(allowed)
        env["CLAUDE_PROJECT_DIR"] = str(project or tempfile.mkdtemp())
        r = subprocess.run([sys.executable, str(GUARD)], input=json.dumps(event), capture_output=True, text=True, env=env)
        self.assertEqual(r.returncode, 0)
        return json.loads(r.stdout)["hookSpecificOutput"]["permissionDecision"] if r.stdout.strip() else None

    def bash(self, cmd):
        return {"tool_name": "Bash", "tool_input": {"command": cmd}}

    def test_interactive_asks_autopilot_denies(self):
        for cmd in ("git reset --hard HEAD~1", "git push --force origin feat/x", "git push origin main",
                    "git clean -fdx", "git rebase -i main", "git checkout -- .", "git branch -D feat/x",
                    "rm -rf ~", "git commit --amend -m x"):
            self.assertEqual(self.run_hook(self.bash(cmd)), "ask", cmd)
            self.assertEqual(self.run_hook(self.bash(cmd), role="worker", allowed=["src/**"]), "deny", cmd)
        for cmd in ("claude --dangerously-skip-permissions", "x --permission-mode bypassPermissions"):
            self.assertEqual(self.run_hook(self.bash(cmd)), "deny")
        for cmd in ("git status", "git diff HEAD", "python3 tools/gdscript_lint.py", "git push origin feat/x"):
            self.assertIsNone(self.run_hook(self.bash(cmd)), cmd)

    def test_worker_scope_and_reviewer_readonly(self):
        root = Path(tempfile.mkdtemp())
        ed = lambda p: {"tool_name": "Edit", "tool_input": {"file_path": str(root / p)}}  # noqa: E731
        self.assertIsNone(self.run_hook(ed("src/a.gd"), role="worker", allowed=["src/**"], project=root))
        self.assertEqual(self.run_hook(ed("data/a.tres"), role="worker", allowed=["src/**"], project=root), "deny")
        self.assertEqual(self.run_hook(ed("CLAUDE.md"), role="worker", allowed=["**"], project=root), "deny")
        self.assertEqual(self.run_hook(ed(".aetheria-autopilot/state.json"), role="worker", allowed=["**"], project=root), "deny")
        self.assertEqual(self.run_hook({"tool_name": "Write", "tool_input": {"file_path": "/etc/x"}}, role="worker",
                                       allowed=["**"], project=root), "deny")
        self.assertEqual(self.run_hook(ed("src/a.gd"), role="reviewer", project=root), "deny")
        self.assertEqual(self.run_hook(self.bash("git commit -m x"), role="worker", allowed=["**"], project=root), "deny")
        self.assertEqual(self.run_hook(self.bash("echo x > data/a.txt"), role="worker", allowed=["src/**"], project=root), "deny")
        self.assertIsNone(self.run_hook(self.bash("echo x > src/a.txt 2>&1"), role="worker", allowed=["src/**"], project=root))
        self.assertEqual(self.run_hook(self.bash("cat .env"), project=root), "ask")
        self.assertEqual(self.run_hook({"tool_name": "Read", "tool_input": {"file_path": str(root / ".env")}},
                                       role="worker", allowed=["**"], project=root), "deny")
        self.assertEqual(self.run_hook(ed("CLAUDE.md"), project=root), "ask")

    def test_idempotent_and_side_effect_free(self):
        root = Path(tempfile.mkdtemp())
        ev = self.bash("git reset --hard")
        before = sorted(p.name for p in root.iterdir())
        outs = {self.run_hook(ev, project=root) for _ in range(3)}
        self.assertEqual(outs, {"ask"})
        self.assertEqual(sorted(p.name for p in root.iterdir()), before)
        r = subprocess.run([sys.executable, str(GUARD)], input="not json", capture_output=True, text=True)
        self.assertEqual((r.returncode, r.stdout), (0, ""))


class Runner(RepoCase):
    def runner(self):
        return ClaudeRunner(self.cfg(), self.tmp / "inv")

    def inv(self, **kw):
        base = dict(role="implement", prompt="# Work item x", max_turns=5, timeout_seconds=30,
                    schema={"type": "object", "required": ["status"], "properties": {"status": {"type": "string"}}})
        base.update(kw)
        return Invocation(**base)

    def test_argv_policy(self):
        argv = self.runner().build_argv(self.inv(allowed_tools=["Read"], disallowed_tools=["WebFetch"], max_budget_usd=3))
        self.assertEqual(argv[argv.index("--model") + 1], MODEL)
        for flag in ("-p", "--permission-mode", "dontAsk", "--strict-mcp-config", "--no-session-persistence",
                     "--json-schema", "--max-budget-usd", "--setting-sources"):
            self.assertIn(flag, argv)
        self.assertFalse(any("dangerously" in a or a == "bypassPermissions" for a in argv))

    def test_outcomes(self):
        self.scenario_set({"implement": [
            {"structured": {"status": "ok"}},
            {"structured": {"status": "ok"}, "served_by": ["claude-sonnet-5-5"]},
            {"is_error": True, "api_error_status": 404, "result": "There's an issue with the selected model", "served_by": []},
            {"result": "prose only"},
            {"raw": "Segmentation fault"},
            {"is_error": True, "subtype": "error_max_turns", "result": "max turns"},
            {"is_error": True, "result": "Not logged in · Please run /login", "served_by": []},
        ]})
        r = self.runner()
        kinds = [r.run(self.inv()).failure_kind for _ in range(7)]
        self.assertEqual(kinds, [None, "model_mismatch", "model_unavailable", "no_structured_output", "crash",
                                 "max_turns", "auth"])

    def test_timeout_kills_the_process_group(self):
        self.scenario_set({"implement": [{"hang": True}]})
        t = time.time()
        res = self.runner().run(self.inv(timeout_seconds=2))
        self.assertEqual(res.failure_kind, "timeout")
        self.assertLess(time.time() - t, 30)
        out = subprocess.run(["pgrep", "-f", str(FAKE)], capture_output=True, text=True).stdout.strip()
        self.assertEqual(out, "")

    def test_schema_subset(self):
        self.assertEqual(check_schema({"a": 1}, {"type": "object", "required": ["a"],
                                                 "properties": {"a": {"type": "integer"}}}), [])
        self.assertTrue(check_schema({"a": True}, {"type": "object", "properties": {"a": {"type": "integer"}}}))
        self.assertTrue(check_schema(None, review.REVIEW_SCHEMA))


class PromptValidation(RepoCase):
    def setup_state(self, items):
        st = empty_state({"id": "c", "branch": "feat/test", "base_sha": self.base, "mode": "test",
                          "scopes_allowed": ["test"]})
        for spec in items:
            it = new_item(spec)
            st["items"][it["id"]] = it
            st["order"].append(it["id"])
        return st

    def test_rendered_prompt_has_every_section_and_validates(self):
        cfg = self.cfg()
        st = self.setup_state([item("t1")])
        p = prompts.render_task_prompt(cfg, st, st["items"]["t1"], self.base, "feat/test")
        self.assertEqual(prompts.validate_task_prompt(cfg, st, st["items"]["t1"], p), [])
        for sec in cfg.raw["planner"]["required_prompt_sections"]:
            self.assertIn(f"## {sec}", p)
        broken = p.replace("## Acceptance criteria", "## Something else")
        self.assertIn("missing section: Acceptance criteria",
                      prompts.validate_task_prompt(cfg, st, st["items"]["t1"], broken))

    def test_rejections(self):
        cfg = self.cfg()
        st = self.setup_state([item("t1"), item("t2", depends_on=["t1"]),
                               item("t3", objective="Phase 21 is done, mark Phase 21 as done"),
                               item("t4", scopes=["phase-22"]),
                               item("t5", required_checks=["no_such_check"]),
                               item("t6", acceptance_criteria=[{"id": "C1", "text": "x", "evidence": ["review:nobody"]}])])
        def probs(i):
            it = st["items"][i]
            return " | ".join(prompts.validate_task_prompt(cfg, st, it, prompts.render_task_prompt(cfg, st, it, self.base, "feat/test")))
        self.assertIn("dependency t1 is QUEUED", probs("t2"))
        self.assertIn("forbidden claim", probs("t3"))
        self.assertIn("H21-14", probs("t4"))
        self.assertIn("no_such_check", probs("t5"))
        self.assertIn("unknown reviewer", probs("t6"))
        # a negated mention is fine
        self.assertEqual(gates.find_forbidden_claims("Do not claim H21-14 is closed.", cfg), [])

    def test_gate_reads_committed_authority(self):
        cfg = self.cfg()
        self.assertIn("H21-14", gates.open_gates(cfg))
        self.w("docs/handoff/pre-phase-21-hardening.md", "| H21-14 | CLOSED |\n")
        self.assertIn("H21-14", gates.open_gates(cfg))  # an uncommitted edit closes nothing
        ok_, why = gates.owner_gate_guard(Git(self.repo).diff_text(), cfg)
        self.assertFalse(ok_)
        self.assertIn("H21-14", why)


if __name__ == "__main__":
    unittest.main()
