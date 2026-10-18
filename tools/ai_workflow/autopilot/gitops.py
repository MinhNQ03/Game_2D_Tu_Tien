"""Git access for the supervisor, behind an allowlist.

Every git command the supervisor runs goes through `Git.run`, which refuses anything outside a
small allowlist BEFORE executing it: no reset, clean, rebase, merge, restore, stash, amend,
force-push, branch deletion, or push to a protected branch. The supervisor stages only explicit
paths and verifies the index afterwards.
"""

from __future__ import annotations

import fnmatch
import hashlib
import os
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


class GitSafetyError(Exception):
    """A git operation was refused by policy (never executed)."""


class GitError(Exception):
    def __init__(self, args: list[str], rc: int, out: str, err: str):
        self.args_ = args
        self.rc = rc
        self.out = out
        self.err = err
        super().__init__(f"git {' '.join(args)} failed rc={rc}: {err.strip()[:400]}")


class RemoteReadError(GitError):
    """Reading the remote heads failed (refused, missing, or unreachable): nothing about the
    remote is known, so callers must block on the environment, never assume."""


class RemoteUnavailable(RemoteReadError):
    """The remote could not be read after the bounded retries, for a transient (network) reason."""


# a refused credential or a missing repository is a real answer, not a network blip: never retried
_REMOTE_DENIED = re.compile(r"(?i)authentication failed|permission denied|repository not found|"
                            r"does not appear to be a git repository|returned error: 40[134]|"
                            r"could not read username|terminal prompts disabled|invalid username or password")
_REMOTE_TRANSIENT = re.compile(r"(?i)could not resolve host|temporary failure in name resolution|"
                               r"name or service not known|connection (timed out|refused|reset)|"
                               r"operation timed out|timed out after|network is unreachable|no route to host|"
                               r"failed to connect|the remote end hung up|early eof|unexpected disconnect|"
                               r"kex_exchange_identification|connection closed by|"
                               r"gnutls|ssl_(read|connect|error)|tls connection|rpc failed|"
                               r"returned error: (408|429|5\d\d)|http (408|429|5\d\d)")


def remote_error_is_transient(stderr: str) -> bool:
    return bool(_REMOTE_TRANSIENT.search(stderr)) and not _REMOTE_DENIED.search(stderr)


# VS Code's git extension records `branch.<name>.vscode-merge-base` in .git/config whenever it sees
# a branch; git itself never reads that key. Only that exact single-line key inside a plain
# [branch "..."] section is left out of the config digest — any other key, a continued value, or
# the same key elsewhere still counts.
_BRANCH_SECTION = re.compile(rb'^[ \t]*\[branch[ \t]+"[^"\\\r\n]*"\][ \t]*\r?\n?\Z', re.I)  # git's own form
_SECTION = re.compile(rb"^[ \t]*\[")
# a CR is allowed only right before the final LF: git reads a lone CR as part of the value
_VSCODE_MERGE_BASE = re.compile(rb'^[ \t]*vscode-merge-base[ \t]*=[^\\\r\n"]*\r?\n?\Z', re.I)


def _continues(line: bytes) -> bool:
    """True when `line` ends with an unescaped backslash: git joins the next line onto its value."""
    body = line.rstrip(b"\r\n")
    return (len(body) - len(body.rstrip(b"\\"))) % 2 == 1


def config_bytes_for_digest(data: bytes) -> bytes:
    """The config bytes minus those VS Code lines. A [branch "..."] section left with no other
    line (VS Code creates one for an unpushed branch; git leaves empty ones behind) is dropped
    whole — a section without keys is inert. A line that continues the previous line's value is
    never dropped."""
    sections: list[list[bytes]] = [[]]
    for line in re.split(rb"(?<=\n)", data):  # LF only, as git does (never splitlines: it splits on CR)
        if not line:
            continue
        if _SECTION.match(line) and not (sections[-1] and _continues(sections[-1][-1])):
            sections.append([line])
        else:
            sections[-1].append(line)
    out: list[bytes] = []
    for sec in sections:
        if sec and _BRANCH_SECTION.match(sec[0]):
            body = [ln for i, ln in enumerate(sec[1:], start=1)
                    if not (_VSCODE_MERGE_BASE.match(ln) and not _continues(sec[i - 1]))]
            if not any(ln.strip() for ln in body):
                continue
            sec = sec[:1] + body
        out.extend(sec)
    return b"".join(out)


READ_ONLY = {"status", "rev-parse", "log", "diff", "show", "ls-files", "ls-remote", "merge-base",
             "cat-file", "rev-list", "for-each-ref", "check-ignore", "symbolic-ref", "hash-object",
             "worktree", "config", "branch", "fetch", "write-tree", "diff-index", "var"}
WRITE = {"switch", "add", "commit", "push"}

_FORBIDDEN_FLAGS = {
    "commit": {"--amend", "--no-verify", "-n", "--fixup", "--squash", "--allow-empty"},
    "push": {"--force", "-f", "--force-with-lease", "--force-if-includes", "--delete", "-d",
             "--mirror", "--all", "--tags", "--prune", "--no-verify"},
    "add": {"-A", "--all", ".", "-u", "--update", "-f", "--force", "--ignore-removal", "-p", "--patch"},
    "branch": {"-d", "-D", "--delete", "-m", "-M", "--move", "-c", "-C", "--copy", "-f", "--force"},
    "switch": {"--discard-changes", "-f", "--force", "-C", "--force-create", "--orphan"},
    "worktree": {"remove", "prune", "move"},
    "config": {"--unset", "--unset-all", "--add", "--replace-all", "--remove-section", "--rename-section"},
    "fetch": {"--prune", "-p", "--prune-tags", "--force", "-f"},
}


@dataclass
class StatusEntry:
    code: str
    path: str


# Write subcommands accept EXACTLY these options (anything else, including abbreviations such as
# `--forc` or bundles such as `-uf`, is refused).
_WRITE_FLAGS = {
    "push": {"--porcelain", "-u", "--set-upstream"},
    "commit": {"-q", "--quiet", "-m", "-F"},
    "add": set(),
    "switch": {"-c", "-q"},
}


def _expand_flags(args: list[str]) -> list[str]:
    """Split bundled short flags (`-uf` -> `-u`, `-f`) so each is judged on its own."""
    out = []
    for a in args:
        if a == "--":
            break
        if len(a) > 2 and a.startswith("-") and not a.startswith("--") and a[1:].isalpha():
            out += [f"-{c}" for c in a[1:]]
        else:
            out.append(a)
    return out


def _safe_args(args: list[str], protected: list[str]) -> None:
    if not args:
        raise GitSafetyError("empty git command")
    # Global options before the subcommand could redirect the repo; none are allowed.
    sub = args[0]
    if sub.startswith("-"):
        raise GitSafetyError(f"global git options are not allowed: {args[0]}")
    if sub not in READ_ONLY and sub not in WRITE:
        raise GitSafetyError(f"git {sub} is not on the supervisor allowlist")
    bad = _FORBIDDEN_FLAGS.get(sub, set())
    flags = _expand_flags(args[1:])
    if sub in _WRITE_FLAGS:
        allowed = _WRITE_FLAGS[sub]
        skip_next = False
        for a in flags:
            if skip_next:
                skip_next = False
                continue
            if a.startswith("-"):
                if a.split("=")[0] not in allowed:
                    raise GitSafetyError(f"git {sub} {a} is not an allowed option")
                skip_next = a in ("-m", "-F", "-c")  # the option's value is not a flag
    for a in flags:
        name = a.split("=")[0]
        if a in bad or name in bad:
            raise GitSafetyError(f"git {sub} {a} is refused by policy")
        if name.startswith("--") and len(name) > 3 and any(f.startswith(name) for f in bad if f.startswith("--")):
            raise GitSafetyError(f"git {sub} {a} abbreviates a refused option")
    positional = [a for a in args[1:] if not a.startswith("-")]
    if sub == "fetch" and any(":" in a or a.startswith("+") for a in positional):
        raise GitSafetyError("git fetch with a refspec is refused (it could move local refs)")
    if sub == "symbolic-ref" and len(positional) > 1:
        raise GitSafetyError("git symbolic-ref may only read")
    if sub == "worktree":
        if not args[1:] or args[1] == "list":
            pass
        elif args[1] == "add":
            rest = args[2:]
            if len(rest) != 4 or rest[0] != "-b":
                raise GitSafetyError("git worktree add must be `add -b <new-branch> <path> <sha>`")
            if any(fnmatch.fnmatchcase(rest[1], p) for p in protected):
                raise GitSafetyError(f"refusing a worktree branch named like a protected branch: {rest[1]}")
        else:
            raise GitSafetyError(f"git worktree {args[1]} is refused")
    if sub == "branch" and any(a not in ("--show-current", "--list") for a in args[1:]):
        raise GitSafetyError("git branch may only show the current branch or list")
    if sub == "config" and len([a for a in args[1:] if not a.startswith("-")]) > 1 and "--get" not in args:
        raise GitSafetyError("git config may only read values")
    if sub == "branch" and any(not a.startswith("-") for a in args[1:]):
        raise GitSafetyError("git branch may only list (use switch -c to create)")
    if sub == "switch":
        if "-c" not in args:
            raise GitSafetyError("git switch is only allowed as `switch -c <new> <sha>`")
    if sub == "add" and "--" not in args:
        raise GitSafetyError("git add requires explicit paths after `--`")
    if sub == "push":
        positional = [a for a in args[1:] if not a.startswith("-")]
        if len(positional) != 2:
            raise GitSafetyError("git push must name exactly <remote> <branch>")
        ref = positional[1]
        if ref == "HEAD" or ref.startswith("refs/") or ref.startswith("@"):
            raise GitSafetyError(f"git push must name a plain branch, not {ref!r}")
        if ":" in ref or ref.startswith("+"):
            raise GitSafetyError(f"refspec {ref!r} is refused (no renames, deletes or forced refs)")
        if any(fnmatch.fnmatchcase(ref, p) for p in protected):
            raise GitSafetyError(f"pushing protected branch {ref!r} is refused")


class Git:
    def __init__(self, repo: Path, protected_branches: list[str] | None = None, runner=None):
        self.repo = Path(repo)
        self.protected = list(protected_branches or ["main", "master"])
        self._runner = runner or self._default_runner
        self.log: list[dict] = []
        self.remote_retry_delays: tuple[float, ...] = (3.0, 10.0)  # sleeps between the 3 attempts
        self._sleep = time.sleep

    @staticmethod
    def _env() -> dict:
        """The supervisor's git never runs repository or user hooks and never asks for input:
        a hook or fsmonitor planted by a worker cannot execute inside a checkpoint or a push."""
        env = dict(os.environ)
        env["GIT_TERMINAL_PROMPT"] = "0"
        env["LC_ALL"] = "C"
        overrides = [("core.hooksPath", os.devnull), ("core.fsmonitor", "false"),
                     ("commit.gpgSign", "false")]
        n = int(env.get("GIT_CONFIG_COUNT", "0") or 0)
        for i, (k, v) in enumerate(overrides, start=n):
            env[f"GIT_CONFIG_KEY_{i}"] = k
            env[f"GIT_CONFIG_VALUE_{i}"] = v
        env["GIT_CONFIG_COUNT"] = str(n + len(overrides))
        return env

    def _default_runner(self, argv: list[str], env: dict) -> tuple[int, str, str]:
        p = subprocess.run(argv, cwd=self.repo, capture_output=True, text=True, env=env, timeout=600)
        return p.returncode, p.stdout, p.stderr

    def run(self, *args: str, check: bool = True) -> str:
        argl = list(args)
        _safe_args(argl, self.protected)
        rc, out, err = self._runner(["git", *argl], self._env())
        self.log.append({"cmd": ["git", *argl], "rc": rc})
        if check and rc != 0:
            raise GitError(argl, rc, out, err)
        return out

    # --- queries ---------------------------------------------------------------------------
    def branch(self) -> str:
        return self.run("branch", "--show-current").strip()

    def head(self) -> str:
        return self.run("rev-parse", "HEAD").strip()

    def resolve(self, ref: str) -> str | None:
        out = self.run("rev-parse", "--verify", "--quiet", ref + "^{commit}", check=False).strip()
        return out or None

    def is_ancestor(self, a: str, b: str) -> bool:
        argv = ["merge-base", "--is-ancestor", a, b]
        _safe_args(argv, self.protected)
        rc, _, _ = self._runner(["git", *argv], self._env())
        return rc == 0

    def status(self) -> list[StatusEntry]:
        out = self.run("status", "--porcelain=v1", "-z", "--untracked-files=all")
        entries: list[StatusEntry] = []
        parts = out.split("\0")
        i = 0
        while i < len(parts):
            rec = parts[i]
            if not rec:
                i += 1
                continue
            code, path = rec[:2], rec[3:]
            entries.append(StatusEntry(code, path))
            if code[0] in "RC":  # rename/copy: the next field is the source path
                i += 1
            i += 1
        return entries

    def is_clean(self) -> bool:
        return not self.status()

    def changed_paths(self) -> list[str]:
        return sorted({e.path for e in self.status()})

    def staged_paths(self) -> list[str]:
        out = self.run("diff", "--cached", "--name-only", "-z")
        return sorted(p for p in out.split("\0") if p)

    def diff_text(self, base: str | None = None, max_bytes: int = 2_000_000) -> str:
        """Diff of the working tree (tracked) against `base` (default HEAD), plus untracked files."""
        args = ["diff", "--no-color", "--no-ext-diff", base or "HEAD"]
        text = self.run(*args)
        untracked = [e.path for e in self.status() if e.code == "??"]
        for p in untracked:
            fp = self.repo / p
            try:
                if fp.stat().st_size > 200_000:
                    text += f"\n--- /dev/null\n+++ b/{p}\n(untracked file, {fp.stat().st_size} bytes, not inlined)\n"
                    continue
                body = fp.read_text(encoding="utf-8")
                text += f"\ndiff --git a/{p} b/{p}\nnew file (untracked)\n--- /dev/null\n+++ b/{p}\n"
                text += "".join("+" + ln + "\n" for ln in body.splitlines())
            except (UnicodeDecodeError, OSError):
                text += f"\n(untracked binary file {p})\n"
        if len(text) > max_bytes:
            text = text[:max_bytes] + "\n[diff truncated]\n"
        return text

    def tree_fingerprint(self) -> str:
        """Content fingerprint of HEAD + the bytes of every changed path in the working tree.
        Independent of the index: staging a file (or a crash between add and commit) does not
        change it, only content does."""
        h = hashlib.sha256()
        h.update(self.head().encode())
        for e in sorted(self.status(), key=lambda e: e.path):
            fp = self.repo / e.path
            h.update(b"\0" + e.path.encode() + b"\0")
            try:
                h.update(fp.read_bytes() if fp.is_file() else b"<dir>")
            except FileNotFoundError:
                h.update(b"<deleted>")
            except OSError:
                h.update(b"<unreadable>")
        return h.hexdigest()

    def snapshot(self, remote: str | None = None) -> dict:
        """Everything a worker must not change in git: HEAD, branch, every local ref (heads, tags,
        remotes, stash), the index, and the files that make git run code or change behaviour
        (config, hooks, info/attributes, info/exclude). With `remote`, also the remote heads."""
        snap = {"head": self.head(), "branch": self.branch(),
                "refs": self.run("for-each-ref", "--format=%(refname) %(objectname)"),
                "staged": self.staged_paths(), "gitfiles": self._git_files_digest()}
        if remote:
            snap["remote"] = self.remote_heads(remote)
        return snap

    def remote_heads(self, remote: str, *refs: str) -> str:
        """`git ls-remote --heads`, retried only for a transient network failure. Raises
        RemoteUnavailable when every attempt failed that way, GitError at once for anything else;
        it never returns a partial or empty answer for a failed read."""
        argv = ["ls-remote", "--heads", remote, *refs]
        _safe_args(argv, self.protected)
        attempts = len(self.remote_retry_delays) + 1
        env = {**self._env(), "GIT_HTTP_LOW_SPEED_LIMIT": "1000", "GIT_HTTP_LOW_SPEED_TIME": "60"}
        for n in range(attempts):
            try:
                rc, out, err = self._runner(["git", *argv], env)
            except subprocess.TimeoutExpired as e:  # a stalled connection is a network failure
                rc, out, err = 124, "", f"timed out after {e.timeout} s"
            self.log.append({"cmd": ["git", *argv], "rc": rc, "attempt": n + 1})
            if rc == 0:
                return out
            if not remote_error_is_transient(err):
                raise RemoteReadError(argv, rc, out, err)
            if n + 1 < attempts:
                self._sleep(self.remote_retry_delays[n])
        raise RemoteUnavailable(argv, rc, out, f"remote unreachable after {attempts} attempts: {err}")

    def _git_files_digest(self) -> str:
        h = hashlib.sha256()
        dirs = {self.run("rev-parse", "--git-common-dir").strip(), self.run("rev-parse", "--git-dir").strip()}
        for d in sorted(dirs):
            base = Path(d) if Path(d).is_absolute() else self.repo / d
            for rel in ("config", "info/attributes", "info/exclude", "config.worktree"):
                f = base / rel
                h.update(f"{f}\0".encode())
                data = f.read_bytes() if f.is_file() else b"<none>"
                h.update(config_bytes_for_digest(data) if rel == "config" else data)
            hooks = base / "hooks"
            if hooks.is_dir():
                for f in sorted(hooks.iterdir()):
                    if f.is_file():
                        h.update(f"{f.name}:{f.stat().st_mode}\0".encode())
                        h.update(f.read_bytes())
        # user-level git config too, following include/includeIf: a worker could otherwise plant
        # core.hooksPath globally or in an included file
        xdg = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
        files = {Path(os.path.expanduser("~/.gitconfig")), Path(xdg) / "git" / "config"}
        if os.environ.get("GIT_CONFIG_GLOBAL"):
            files.add(Path(os.environ["GIT_CONFIG_GLOBAL"]))
        rc, out, _ = self._runner(["git", "config", "--global", "--list", "--show-origin", "--includes"], self._env())
        h.update(out.encode("utf-8", "replace"))
        for line in out.splitlines():
            if line.startswith("file:"):
                files.add(Path(line[5:].split("\t", 1)[0]))
        for f in sorted(files):
            h.update(f"{f}\0".encode())
            try:
                h.update(f.read_bytes() if f.is_file() else b"<none>")
            except OSError:
                h.update(b"<unreadable>")
        return h.hexdigest()

    def worktree_matches_index(self, paths: list[str]) -> bool:
        """True when the working tree holds exactly what is staged for `paths` (no later edit)."""
        return not self.run("diff", "--name-only", "-z", "--", *paths).strip("\0") and not [
            e for e in self.status() if e.code == "??" and e.path in paths]

    def commits_with_trailer(self, key: str, value: str, rev_range: str = "HEAD", limit: int = 200) -> list[str]:
        out = self.run("log", f"-{limit}", "--format=%H%x00%B%x1e", rev_range)
        hits = []
        for rec in out.split("\x1e"):
            rec = rec.strip("\n")
            if not rec:
                continue
            sha, _, body = rec.partition("\x00")
            for line in body.splitlines():
                if line.strip() == f"{key}: {value}":
                    hits.append(sha.strip())
                    break
        return hits

    def remote_branch_sha(self, remote: str, branch: str) -> str | None:
        out = self.remote_heads(remote, f"refs/heads/{branch}")
        for line in out.splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1] == f"refs/heads/{branch}":
                return parts[0]
        return None

    # --- writes ------------------------------------------------------------------------------
    def create_branch(self, name: str, sha: str) -> None:
        if any(fnmatch.fnmatchcase(name, p) for p in self.protected):
            raise GitSafetyError(f"refusing to create protected branch name {name!r}")
        if self.resolve(f"refs/heads/{name}"):
            raise GitSafetyError(f"branch {name!r} already exists; refusing to reuse it implicitly")
        if not self.is_clean():
            raise GitSafetyError("refusing to switch branches with uncommitted changes")
        self.run("switch", "-c", name, sha)

    def stage_exact(self, paths: list[str]) -> list[str]:
        if not paths:
            raise GitSafetyError("nothing to stage")
        pre = self.staged_paths()
        if pre:
            raise GitSafetyError(f"index already has staged paths not staged by the supervisor: {pre[:10]}")
        self.run("add", "--", *paths)
        staged = self.staged_paths()
        if sorted(staged) != sorted(set(paths)):
            raise GitSafetyError(f"staged set differs from the intended set: staged={staged[:20]} intended={paths[:20]}")
        return staged

    def commit(self, message: str) -> str:
        self.run("commit", "-q", "-m", message)
        return self.head()

    def push(self, remote: str, branch: str, set_upstream: bool) -> None:
        if branch != self.branch():
            raise GitSafetyError(f"refusing to push {branch!r}: it is not the checked-out branch")
        args = ["push", "--porcelain"]
        if set_upstream:
            args.append("-u")
        self.run(*args, remote, branch)
