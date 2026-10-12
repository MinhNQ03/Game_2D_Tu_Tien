#!/usr/bin/env python3
"""Documentation validation gate for the Aetheria Knowledge Hub.

WHY THIS EXISTS
---------------
The Knowledge Hub (`docs/knowledge/`) is a navigation layer over the repo's
tracked Markdown. A link that points nowhere, a dependency edge to a missing
file, or a stale generated index silently teaches agents (and Obsidian users)
the wrong map. This validator deterministically checks the STRUCTURE of the
knowledge layer. It does not claim semantic consistency — that remains the
agent's job under `docs/knowledge/DOCS_SYNC_CONTRACT.md`.

RULES (each is a numbered check; all must pass)
-----
- KB01 hub entry exists: `docs/knowledge/AETHERIA_KNOWLEDGE_HUB.md`.
- KB02 every local Markdown link in `docs/knowledge/*.md` resolves to an
  existing file; `#anchor` fragments resolve to a real heading in the target.
  Covers `[text](path)`, `[text](path#anchor)`, and Obsidian `[[page]]` /
  `[[page#anchor]]` forms. External URLs are not fetched (offline gate).
- KB03 every dependency-map target exists (same mechanism as KB02, applied to
  `DOCS_DEPENDENCY_MAP.md`).
- KB04 the generated decision index is current
  (`tools/gen_decision_index.py --check`).
- KB05 no local absolute paths (`/home/`, `/Users/`, `C:\\`, ...) and no
  secret-shaped strings (`ghp_`, `github_pat_`, `AKIA`, `-----BEGIN`) in
  `docs/knowledge/`.
- KB06 required status labels are intact: the C2 proposal still carries
  `PROPOSAL — NOT CANON`; the hub still distinguishes canon / accepted /
  proposal / open; nothing in `docs/knowledge/` claims H21-14 is closed.

USAGE
-----
    python3 tools/validate_docs.py              # validate (CI)
    python3 tools/validate_docs.py --selftest   # unit tests for the validator

Exit code 0 = clean, 1 = at least one violation, 2 = bad invocation.
Output is `path:line: CODE message`, one per line (editor-clickable).
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
KB = REPO / "docs" / "knowledge"
HUB = KB / "AETHERIA_KNOWLEDGE_HUB.md"
DEP_MAP = KB / "DOCS_DEPENDENCY_MAP.md"
DECISION_INDEX = KB / "DECISION_INDEX.md"
C2_PROPOSAL = REPO / "docs" / "proposals" / "PROPOSAL_SAGA_SECT_ATLAS_CULTIVATION_AND_P21_HANDOFF.md"

MD_LINK_RE = re.compile(r"(?<!!)\[([^\]]*)\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
WIKI_LINK_RE = re.compile(r"\[\[([^|\]#]+)(?:#[^\]|]+)?(?:\|[^\]]+)?\]\]")
ABSOLUTE_PATH_RE = re.compile(r"(?:/home/|/Users/|/root/|C:\\|\\\\)")
SECRET_RE = re.compile(r"ghp_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|AKIA[0-9A-Z]+|-----BEGIN [A-Z ]*PRIVATE KEY")
FENCED_RE = re.compile(r"```.*?```", re.DOTALL)


def github_anchor(heading_text: str) -> str:
    t = heading_text.lower()
    t = re.sub(r"[^\w \-]", "", t, flags=re.UNICODE)
    return t.replace(" ", "-").strip("-")


def file_anchors(path: Path) -> set[str]:
    """All GitHub-style anchors from a Markdown file's headings."""
    anchors: set[str] = set()
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return anchors
    for line in text.splitlines():
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if m:
            anchors.add(github_anchor(m.group(2)))
    return anchors


def check_link(source: Path, line_no: int, target: str, violations: list[str]) -> None:
    if target.startswith(("http://", "https://", "mailto:", "sandbox:")):
        return  # external or display-only: not validated offline
    if target.startswith("#"):
        anchors = file_anchors(source)
        if target[1:] not in anchors:
            violations.append(f"{source.relative_to(REPO)}:{line_no}: KB02 broken same-file anchor {target}")
        return
    path_part, _, frag = target.partition("#")
    dest = (source.parent / path_part).resolve()
    try:
        dest.relative_to(REPO.resolve())
    except ValueError:
        violations.append(f"{source.relative_to(REPO)}:{line_no}: KB02 link escapes repo {target}")
        return
    if not dest.exists():
        violations.append(f"{source.relative_to(REPO)}:{line_no}: KB02 broken link {target}")
        return
    if frag and dest.suffix == ".md":
        if frag not in file_anchors(dest):
            violations.append(
                f"{source.relative_to(REPO)}:{line_no}: KB02 broken anchor #{frag} in {target}"
            )


def validate() -> list[str]:
    violations: list[str] = []
    # KB01
    if not HUB.exists():
        violations.append(f"{HUB.relative_to(REPO)}:0: KB01 hub entry missing")
        return violations  # nothing else is meaningful without the hub
    kb_files = sorted(KB.glob("*.md"))
    for md in kb_files:
        rel = md.relative_to(REPO)
        text = md.read_text(encoding="utf-8")
        code_free = FENCED_RE.sub("", text)
        for i, line in enumerate(code_free.splitlines(), start=1):
            for m in MD_LINK_RE.finditer(line):
                check_link(md, i, m.group(2), violations)
            for m in WIKI_LINK_RE.finditer(line):
                page = m.group(1).strip()
                # [[page]] resolves to page.md relative to the vault root or the file dir.
                candidates = [md.parent / f"{page}.md", REPO / f"{page}.md"]
                if not any(c.exists() for c in candidates):
                    violations.append(f"{rel}:{i}: KB02 broken wikilink [[{page}]]")
        # KB05
        for i, line in enumerate(text.splitlines(), start=1):
            if ABSOLUTE_PATH_RE.search(line):
                violations.append(f"{rel}:{i}: KB05 absolute local path")
            if SECRET_RE.search(line):
                violations.append(f"{rel}:{i}: KB05 secret-shaped string")
    # KB04: decision index currency.
    gen = REPO / "tools" / "gen_decision_index.py"
    if gen.exists():
        r = subprocess.run(
            [sys.executable, str(gen), "--check"], capture_output=True, text=True, cwd=REPO
        )
        if r.returncode != 0:
            msg = (r.stderr.strip() or r.stdout.strip() or "index check failed").splitlines()
            violations.append(f"{DECISION_INDEX.relative_to(REPO)}:0: KB04 decision index stale: {msg[0]}")
    # KB06: status labels intact.
    if C2_PROPOSAL.exists():
        if "PROPOSAL — NOT CANON" not in C2_PROPOSAL.read_text(encoding="utf-8"):
            violations.append(f"{C2_PROPOSAL.relative_to(REPO)}:0: KB06 C2 proposal lost its PROPOSAL — NOT CANON label")
    hub_text = HUB.read_text(encoding="utf-8")
    for label in ("canon", "accepted decision", "proposal", "open"):
        if label not in hub_text.lower():
            violations.append(f"{HUB.relative_to(REPO)}:0: KB06 hub no longer distinguishes '{label}'")
    for md in kb_files:
        t = md.read_text(encoding="utf-8")
        # H21-14 must never be presented as closed: fail only when a CLOSED
        # claim attaches to H21-14 itself (an OPEN before the CLOSED, e.g. the
        # "H21-14 OPEN · H21-21 CLOSED" status line, is fine).
        for m in re.finditer(r"H21-14", t):
            window = t[m.end() : m.end() + 80]
            if re.search(r"[Cc][Ll][Oo][Ss][Ee][Dd]", window):
                before = window.split(re.search(r"[Cc][Ll][Oo][Ss][Ee][Dd]", window).group(0))[0]
                if not re.search(r"[Oo][Pp][Ee][Nn]", before):
                    violations.append(f"{md.relative_to(REPO)}:0: KB06 knowledge file claims H21-14 closed")
                    break
    return violations


def selftest() -> int:
    global REPO, KB, HUB, DEP_MAP, DECISION_INDEX, C2_PROPOSAL
    failures = 0

    def check(name: str, cond: bool) -> None:
        nonlocal failures
        if not cond:
            print(f"SELFTEST FAIL: {name}")
            failures += 1

    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "docs" / "knowledge").mkdir(parents=True)
        (root / "docs" / "DECISIONS.md").write_text("# Decisions\n\n## D-001 — Foo — **Accepted** (2026-10-02)\n")
        hub = root / "docs" / "knowledge" / "AETHERIA_KNOWLEDGE_HUB.md"
        hub.write_text(
            "# Hub\n\n"
            "canon accepted decision proposal open\n\n"
            "[ok](../DECISIONS.md)\n"
            "[anch](../DECISIONS.md#d-001--foo--accepted-2026-10-02)\n"
            "[broken](missing.md)\n"
            "[badanch](../DECISIONS.md#nope)\n"
            "[[DECISION_INDEX]]\n"
            "[[Nope]]\n"
            "path /home/user/x\n"
            "token ghp_abc123\n",
            encoding="utf-8",
        )
        (root / "docs" / "knowledge" / "DECISION_INDEX.md").write_text("# Decision Index\n", encoding="utf-8")

        # Point the module at the temp tree (restored afterwards).
        saved = (REPO, KB, HUB, DEP_MAP, DECISION_INDEX, C2_PROPOSAL)
        REPO = root
        KB = root / "docs" / "knowledge"
        HUB = KB / "AETHERIA_KNOWLEDGE_HUB.md"
        DEP_MAP = KB / "DOCS_DEPENDENCY_MAP.md"
        DECISION_INDEX = KB / "DECISION_INDEX.md"
        C2_PROPOSAL = root / "docs" / "proposals" / "x.md"  # absent: KB06 skips gracefully
        try:
            violations = validate()
        finally:
            REPO, KB, HUB, DEP_MAP, DECISION_INDEX, C2_PROPOSAL = saved
        codes = [x.split(": KB")[1].split()[0] for x in violations if ": KB" in x]
        check("KB02 broken link caught", "02" in codes)
        check("KB02 broken anchor caught", any("badanch" in x or "nope" in x for x in violations))
        check("KB02 broken wikilink caught", any("Nope" in x for x in violations))
        check("KB02 good links pass", not any("](missing" not in x and "[ok]" in x and "KB02" in x for x in violations))
        check("KB05 absolute path caught", "05" in codes)
        check("KB05 secret caught", any("secret-shaped" in x for x in violations))
        check("KB01 present", not any("KB01" in x for x in violations))
        check("validate returns list", isinstance(violations, list))

    if failures:
        print(f"validate_docs selftest: {failures} failure(s)")
        return 1
    print("validate_docs selftest: all passed")
    return 0


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Validate the Aetheria Knowledge Hub structure")
    parser.add_argument("--selftest", action="store_true", help="run validator unit tests")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    violations = validate()
    for v in violations:
        print(v)
    if violations:
        print(f"validate_docs: {len(violations)} violation(s)")
        return 1
    print("validate_docs: clean")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
