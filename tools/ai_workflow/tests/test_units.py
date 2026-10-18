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

from tests.helpers import AI, FAKE, MODEL, REAL_REPO as REAL, RepoCase, item, sh

from autopilot import gates, prompts, review
from autopilot.claude_runner import ClaudeRunner, Invocation, check_schema
from autopilot.gitops import (Git, GitError, GitSafetyError, RemoteReadError, RemoteUnavailable,
                              remote_error_is_transient)
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
        for t in ('{"password": "hunter2"}', '"GITHUB_TOKEN":"abcdef1234567890abcd"'):
            self.assertNotIn("hunter2" if "password" in t else "abcdef1234567890abcd", redact(t), t)
        for secret in ("DB_PASSWORD=hunter2", "password: s3cr", "GITHUB_TOKEN=abcdef1234567890abcd", "DB_PASSWORD: hunter2hunter2hunter2",
                       "AWS_SECRET_ACCESS_KEY=AbCdEfGhIjKlMnOpQrSt12"):
            self.assertNotIn(secret.split("=")[-1].split()[-1], redact(secret), secret)
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
                   ("-C", "/", "status"), ("worktree", "remove", "x"), ("filter-branch",),
                   ("push", "--forc", "origin", "feat/test"), ("push", "-uf", "origin", "feat/test"),
                   ("push", "--force-w", "origin", "feat/test"), ("commit", "--am", "-m", "x"),
                   ("fetch", "origin", "+main:main"), ("symbolic-ref", "HEAD", "refs/heads/main"),
                   ("add", "-v", "--", "pkg/core.py"), ("fetch", "--pru", "origin"), ("branch", "--del", "x"),
                   ("worktree", "add", "-B", "x", "/tmp/x", "HEAD"), ("worktree", "add", "-f", "-b", "y", "/tmp/y", "HEAD"),
                   ("worktree", "add", "-b", "main", "/tmp/z", "HEAD"), ("branch", "--set-upstream-to", "origin/main"),
                   ("push", "origin", "HEAD"), ("push", "origin", "refs/heads/main"), ("push", "origin", "@")]
        for args in refused:
            with self.assertRaises(GitSafetyError, msg=str(args)):
                g.run(*args)
        self.assertEqual(g.head(), head)
        with self.assertRaises(GitSafetyError):
            g.create_branch("main", head)

    def test_supervisor_git_never_runs_hooks(self):
        marker = self.tmp / "hook_ran"
        hook = self.repo / ".git" / "hooks" / "pre-commit"
        hook.write_text(f"#!/bin/sh\ntouch {marker}\n")
        hook.chmod(0o755)
        gcfg = self.tmp / "global.gitconfig"
        evil = self.tmp / "evilhooks"
        evil.mkdir()
        (evil / "pre-commit").write_text(f"#!/bin/sh\ntouch {marker}\n")
        (evil / "pre-commit").chmod(0o755)
        gcfg.write_text(f"[core]\n\thooksPath = {evil}\n")
        os.environ["GIT_CONFIG_GLOBAL"] = str(gcfg)
        try:
            g = Git(self.repo)
            self.w("pkg/h.py", "x = 1\n")
            g.stage_exact(["pkg/h.py"])
            g.commit("hook probe")
        finally:
            os.environ.pop("GIT_CONFIG_GLOBAL", None)
        self.assertFalse(marker.exists())
        env = Git._env()
        keys = {env[f"GIT_CONFIG_KEY_{i}"] for i in range(int(env["GIT_CONFIG_COUNT"]))}
        self.assertTrue({"core.hooksPath", "core.fsmonitor"} <= keys)

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


NET_DOWN = "fatal: unable to access 'https://github.com/o/r.git/': Could not resolve host: github.com\n"
AUTH_DENIED = "remote: Invalid username or password.\nfatal: Authentication failed for 'https://github.com/o/r.git/'\n"


def scripted_runner(git, replies):
    """Answer `git ls-remote` with the scripted (rc, stderr) replies in order; run everything else."""
    real, calls = git._runner, []

    def run(argv, env):
        if argv[1:2] == ["ls-remote"]:
            calls.append(argv)
            if replies:
                rc, err = replies.pop(0)
                if rc:
                    return rc, "", err
        return real(argv, env)
    git._runner = run
    git._sleep = lambda s: None
    return calls


class RemoteReads(RepoCase):
    def test_transient_failures_are_retried_then_answered(self):
        g = Git(self.repo)
        calls = scripted_runner(g, [(128, NET_DOWN), (128, NET_DOWN)])
        self.assertEqual(g.remote_heads("origin"), sh(self.repo, "git", "ls-remote", "--heads", "origin") + "\n")
        self.assertEqual(len(calls), 3)

    def test_backoff_between_attempts(self):
        g = Git(self.repo)
        scripted_runner(g, [(128, NET_DOWN)] * 3)
        slept = []
        g._sleep = slept.append
        with self.assertRaises(RemoteUnavailable):
            g.remote_heads("origin")
        self.assertEqual(slept, [3.0, 10.0])

    def test_a_stalled_read_is_a_retried_network_failure(self):
        g = Git(self.repo)
        real, n = g._runner, []

        def run(argv, env):
            if argv[1:2] == ["ls-remote"]:
                n.append(env.get("GIT_HTTP_LOW_SPEED_TIME"))
                raise subprocess.TimeoutExpired(argv, 600)
            return real(argv, env)
        g._runner, g._sleep = run, (lambda s: None)
        with self.assertRaises(RemoteUnavailable):
            g.remote_heads("origin")
        self.assertEqual(n, ["60"] * 3)

    def test_persistent_network_failure_raises_never_an_empty_answer(self):
        g = Git(self.repo)
        calls = scripted_runner(g, [(128, NET_DOWN)] * 6)
        with self.assertRaises(RemoteUnavailable):
            g.snapshot("origin")
        self.assertEqual(len(calls), 3)  # bounded: two retries, no more
        with self.assertRaises(RemoteUnavailable):
            g.remote_branch_sha("origin", "main")  # publish no longer reads a failure as "branch absent"

    def test_a_refused_credential_is_not_retried_and_not_called_a_network_blip(self):
        g = Git(self.repo)
        calls = scripted_runner(g, [(128, AUTH_DENIED)] * 3)
        with self.assertRaises(GitError) as cm:
            g.remote_heads("origin")
        self.assertNotIsInstance(cm.exception, RemoteUnavailable)
        self.assertIsInstance(cm.exception, RemoteReadError)
        self.assertEqual(len(calls), 1)
        self.assertFalse(remote_error_is_transient("fatal: repository 'x' not found\n"))
        self.assertFalse(remote_error_is_transient("Permission denied (publickey).\nfatal: Could not read from remote repository.\n"))
        self.assertTrue(remote_error_is_transient("ssh: connect to host github.com port 22: Connection timed out\n"))
        self.assertTrue(remote_error_is_transient("error: RPC failed; HTTP 502 curl 22 The requested URL returned error: 502\n"))


class ConfigDigest(RepoCase):
    """The worker git guard digests .git/config. VS Code's own merge-base bookkeeping is not a
    worker writing git; every key git acts on still is."""

    def _digest_after(self, *config_args):
        g = Git(self.repo)
        before = g._git_files_digest()
        sh(self.repo, "git", "config", *config_args)
        return before, g._git_files_digest()

    def test_vscode_merge_base_is_not_a_git_write(self):
        a, b = self._digest_after("branch.feat/test.vscode-merge-base", "origin/main")
        self.assertEqual(a, b)
        a, b = self._digest_after("branch.feat/test.vscode-merge-base", "origin/feat/other")  # changed value
        self.assertEqual(a, b)

    def test_the_campaign_branch_shape_seen_live(self):
        # .git/config of feat/ui-readability-autopilot on 2026-10-17: VS Code added a whole section
        cfgp = self.repo / ".git" / "config"
        g = Git(self.repo)
        before = g._git_files_digest()
        cfgp.write_text(cfgp.read_text() + '[branch "feat/ui-readability-autopilot"]\n\tvscode-merge-base = origin/main\n')
        self.assertEqual(before, g._git_files_digest())

    def test_keys_git_acts_on_still_count(self):
        for args in (("branch.feat/test.pushRemote", "evil"), ("branch.feat/test.remote", "evil"),
                     ("core.hooksPath", "/tmp/evil"), ("core.vscode-merge-base", "x"),
                     ("remote.vscode-merge-base.url", "/tmp/x")):
            a, b = self._digest_after(*args)
            self.assertNotEqual(a, b, args)

    def _same_digest_with(self, extra: bytes) -> bool:
        """Fresh baseline per case: is the digest unchanged once `extra` is appended?"""
        cfgp = self.repo / ".git" / "config"
        orig = cfgp.read_bytes()
        g = Git(self.repo)
        before = g._git_files_digest()
        cfgp.write_bytes(orig + extra)
        try:
            return before == g._git_files_digest()
        finally:
            cfgp.write_bytes(orig)

    def test_a_continued_vscode_value_is_kept(self):
        # its only body line continues onto the next line: stripping it would empty the section
        self.assertFalse(self._same_digest_with(b'[branch "feat/test"]\n\tvscode-merge-base = x\\\n'))
        # (any backslash in the value keeps the line: VS Code never writes one)

    def test_a_vscode_line_continuing_a_real_key_is_kept(self):
        cfgp = self.repo / ".git" / "config"
        orig = cfgp.read_bytes()
        cfgp.write_bytes(orig + b'[branch "feat/test"]\n\tpushRemote = origin\\\n')
        g = Git(self.repo)
        before = g._git_files_digest()
        cfgp.write_bytes(cfgp.read_bytes() + b"vscode-merge-base = evil\n")  # now part of pushRemote's value
        self.assertNotEqual(before, g._git_files_digest())

    def test_a_header_inside_a_continued_value_is_not_a_section(self):
        cfgp = self.repo / ".git" / "config"
        cfgp.write_bytes(cfgp.read_bytes() + b"[core]\n\tfoo = a\\\n")
        self.assertFalse(self._same_digest_with(b'[branch "x"]\n\tvscode-merge-base = y\n'))

    def test_headers_git_rejects_are_kept(self):
        for extra in (b'[branch "x" ]\n', b'[ branch "x"]\n\tvscode-merge-base = y\n'):
            try:
                same = self._same_digest_with(extra)
            except GitError:  # git refuses the file outright: loud, never a silent pass
                same = False
            self.assertFalse(same, extra)

    def test_inline_key_on_a_header_is_kept(self):
        self.assertFalse(self._same_digest_with(b'[branch "feat/test"] pushRemote = evil\n\tvscode-merge-base = y\n'))

    def test_a_lone_cr_cannot_swallow_the_next_section(self):
        # git reads `x\r[branch "main"]` as one value: the real section below would vanish
        cfgp = self.repo / ".git" / "config"
        orig = cfgp.read_bytes()
        g = Git(self.repo)
        sh(self.repo, "git", "config", "branch.main.merge", "refs/heads/main")
        base = cfgp.read_bytes()
        before = g._git_files_digest()
        i = base.index(b'[branch "main"]')
        cfgp.write_bytes(base[:i] + b'[branch "feat/test"]\n\tvscode-merge-base = x\r' + base[i:])
        self.assertNotEqual(before, g._git_files_digest())
        cfgp.write_bytes(orig)

    def test_crlf_vscode_section_is_ignored(self):
        self.assertTrue(self._same_digest_with(b'[branch "feat/test"]\r\n\tvscode-merge-base = origin/main\r\n'))

    def test_vscode_writing_into_an_existing_empty_header(self):
        cfgp = self.repo / ".git" / "config"
        cfgp.write_bytes(cfgp.read_bytes() + b'[branch "feat/test"]\n')
        a, b = self._digest_after("branch.feat/test.vscode-merge-base", "origin/main")
        self.assertEqual(a, b)

    def test_ancestry_checks_are_unchanged(self):
        g = Git(self.repo)
        self.w("pkg/x.py", "x\n")
        sh(self.repo, "git", "add", "pkg/x.py")
        sh(self.repo, "git", "commit", "-qm", "x")
        self.assertTrue(g.is_ancestor(self.base, g.head()))
        self.assertFalse(g.is_ancestor(g.head(), self.base))


class ShippedLimits(unittest.TestCase):
    def test_only_the_per_item_call_cap_was_raised(self):
        cfg = json.loads((AI / "autopilot_config.json").read_text())
        lim, bud = cfg["limits"], cfg["budget"]
        self.assertEqual(lim, {
            "max_review_fix_cycles": 3, "max_tasks_per_run": 10, "wall_clock_minutes_per_run": 240,
            "stop_new_stage_when_minutes_left_below": 25, "max_invocations_per_task": 24,
            "max_invocations_per_run": 90, "max_identical_failure_retries": 1,
            "max_planner_generated_items_per_run": 3, "ci_poll_timeout_seconds": 1800, "ci_poll_interval_seconds": 60,
            "invocation": {"implement": {"max_turns": 200, "timeout_seconds": 5400},
                           "fix": {"max_turns": 150, "timeout_seconds": 3600},
                           "review": {"max_turns": 80, "timeout_seconds": 1800},
                           "plan": {"max_turns": 60, "timeout_seconds": 1500},
                           "probe": {"max_turns": 1, "timeout_seconds": 180}}})
        self.assertEqual((bud["max_usd_per_task"], bud["max_usd_per_run"], bud["max_usd_per_campaign"]), (None, None, None))
        self.assertTrue(bud["require_explicit_budget_for_billable_runs"])


class WorkerRunCommands(RepoCase):
    godot = True

    def test_worker_gets_the_validation_display(self):
        os.environ["DISPLAY"] = ":77"
        s = self.sup()
        self.assertEqual(s.worker_env(new_item(item("t1")))["DISPLAY"], ":77")

    def test_no_display_is_omitted_never_blanked(self):
        os.environ.pop("DISPLAY", None)
        self.cfg_raw["environment"]["display_fallback"] = ":99"  # no X socket for :99 here
        self.write_config()
        self.assertNotIn("DISPLAY", self.sup().worker_env(new_item(item("t1"))))

    def test_every_command_the_prompt_names_is_one_the_worker_may_run(self):
        """ui-01 lost a fix round because the worker could not run Godot: its guesses (`timeout …`,
        `~/…`, `godot4`) fell outside the allowlist. The prompt now names exact commands; each must
        match a worker Bash allow pattern after the supervisor's own expansion."""
        import fnmatch
        import re as _re
        from autopilot.prompts import run_commands
        s = self.sup()
        cfg = self.cfg()
        text = run_commands(cfg)
        cmds = _re.findall(r"`([^`]+)`", text)
        cmds = [c for c in cmds if " " in c]  # every command, not only the ones that look right
        self.assertGreaterEqual(len(cmds), 7, text)
        pats = [s._expand(b) for b in cfg.raw["permissions"]["worker_bash_allow"]]
        globs = [p[:-2] + "*" if p.endswith(":*") else p for p in pats]
        for c in cmds:
            self.assertTrue(any(fnmatch.fnmatchcase(c, g) for g in globs), f"not allowlisted: {c}")
        self.assertIn(str(self.tmp / "fakegodot"), text)
        # (fnmatch is a prefix check here: the strings are fixed, so `*` matching `;` is moot)
        # the commands reach the worker: in the task prompt, and in the fix prompt built from it
        from autopilot import prompts
        from autopilot.state import empty_state, new_item
        st = empty_state({"id": "c", "branch": "feat/test", "base_sha": self.base, "mode": "test"})
        it = new_item(item("t1"))
        task = prompts.render_task_prompt(cfg, st, it, self.base, "feat/test")
        self.assertIn(text, task)
        self.assertIn(text, prompts.render_fix_prompt(it, task, [], {}, 1))
        self.assertNotIn("timeout ", text.split("\n", 2)[2])

    def test_no_godot_is_said_plainly(self):
        from autopilot.prompts import run_commands
        self.cfg_raw["environment"]["godot_bin_candidates"] = ["/nonexistent/godot"]
        self.write_config()
        self.assertIn("Godot was not found", run_commands(self.cfg()))


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
        p.stdout.close()
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
        for cmd in ("git -C . reset --hard", "git -c a=b push -f origin x", "git --no-pager -C /x clean -fd"):
            self.assertEqual(self.run_hook(self.bash(cmd)), "ask", cmd)
            self.assertEqual(self.run_hook(self.bash(cmd), role="worker", allowed=["**"]), "deny", cmd)
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


class OtherHooks(unittest.TestCase):
    def _hook(self, name, stdin, env_extra=None):
        env = {k: v for k, v in os.environ.items() if not k.startswith("AETHERIA_AUTOPILOT")}
        env.update(env_extra or {})
        return subprocess.run([sys.executable, str(AI / "hooks" / name)], input=stdin, capture_output=True,
                              text=True, env=env, timeout=120)

    def test_post_edit_lint(self):
        r = self._hook("post_edit_lint.py", "garbage")
        self.assertEqual((r.returncode, r.stdout), (0, ""))
        r = self._hook("post_edit_lint.py", json.dumps({"tool_input": {"file_path": "/tmp/x.md"}}))
        self.assertEqual((r.returncode, r.stdout), (0, ""))
        root = Path(tempfile.mkdtemp())
        (root / "tools").mkdir()
        (root / "tools" / "gdscript_lint.py").write_text("import sys\nprint('bad.gd:1: GD003 line too long')\nsys.exit(1)\n")
        gd = root / "bad.gd"
        gd.write_text("extends Node\n")
        r = self._hook("post_edit_lint.py", json.dumps({"tool_input": {"file_path": str(gd)}}), {"CLAUDE_PROJECT_DIR": str(root)})
        out = json.loads(r.stdout)["hookSpecificOutput"]
        self.assertEqual(out["hookEventName"], "PostToolUse")
        self.assertIn("GD003", out["additionalContext"])

    def test_session_context(self):
        r = self._hook("session_context.py", "{}", {"CLAUDE_PROJECT_DIR": str(REAL)})
        self.assertEqual(r.returncode, 0)
        out = json.loads(r.stdout)["hookSpecificOutput"]
        self.assertEqual(out["hookEventName"], "SessionStart")
        self.assertIn("open owner gates", out["additionalContext"])
        r = self._hook("session_context.py", "{}", {"AETHERIA_AUTOPILOT_ROLE": "worker"})
        self.assertEqual(r.stdout, "")


class CIPolling(unittest.TestCase):
    def gh(self, runs_seq):
        from autopilot.ci import GitHub
        seq = list(runs_seq)
        t = [0.0]

        def fake_gh(args, cwd, timeout=60):
            if "annotations" in args[1]:
                return 0, json.dumps([{"path": "tests/x.gd", "start_line": 3, "message": "[FAIL] boom"}]), ""
            runs = seq.pop(0) if len(seq) > 1 else seq[0]
            return 0, json.dumps({"check_runs": runs}), ""

        def sleep(s):
            t[0] += s
        return GitHub(".", "o/r", gh=fake_gh, sleep=sleep, clock=lambda: t[0])

    def run_(self, st, concl="success", ann=False):
        r = {"status": st, "conclusion": concl, "name": "Foundation gates", "html_url": "u"}
        if ann:
            r["output"] = {"annotations_url": "https://api.github.com/repos/o/r/check-runs/1/annotations"}
        return r

    def test_success_failure_timeout_none(self):
        g = self.gh([[self.run_("in_progress", None)], [self.run_("completed", "success")]])
        self.assertEqual(g.wait_for_ci("abc", 600, 10)["conclusion"], "success")
        g = self.gh([[self.run_("completed", "timed_out", ann=True)]])
        r = g.wait_for_ci("abc", 600, 10)
        self.assertEqual(r["conclusion"], "failure")
        self.assertIn("[FAIL] boom", r["annotations"][0])
        g = self.gh([[self.run_("in_progress", None)]])
        self.assertEqual(g.wait_for_ci("abc", 60, 10)["conclusion"], "timeout")
        g = self.gh([[]])
        self.assertEqual(g.wait_for_ci("abc", 60, 10)["conclusion"], "none")

    def test_gh_wrapper_refuses_writes(self):
        from autopilot.ci import _gh
        for args in (["api", "-X", "DELETE", "repos/o/r"], ["pr", "merge", "1"], ["pr", "create", "--title", "x"],
                     ["repo", "delete"]):
            with self.assertRaises(ValueError):
                _gh(args, ".")


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


class CommitMessageRedaction(RepoCase):
    def test_commit_message_layer_redacts_on_its_own(self):
        from autopilot.supervisor import RunOptions, Supervisor
        sup = Supervisor(self.cfg(), RunOptions())
        it = new_item(item("t1"))
        it["worker_report"] = {"summary": "token ghp_" + "Q" * 36}
        it["known_limitations"] = ["password=SuperSecretValue12345"]
        msg = sup.commit_message(it, "t1.0.abc")
        self.assertNotIn("Q" * 36, msg)
        self.assertNotIn("SuperSecretValue12345", msg)


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
