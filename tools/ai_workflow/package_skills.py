#!/usr/bin/env python3
"""Validate the project skills and package each one as a claude.ai upload ZIP.

  python3 tools/ai_workflow/package_skills.py --check          # validate only (exit 1 on a problem)
  python3 tools/ai_workflow/package_skills.py [--out DIR]      # validate, then write DIR/<name>.zip

The same `.claude/skills/<name>/` folders serve three consumers: interactive Claude Code, the
headless autopilot workers, and claude.ai (Customize > Skills > upload). claude.ai is the strict
one: the ZIP must hold the skill FOLDER at its root, the folder name must equal `name`, and
`description` is capped at 200 characters. Validating here keeps one source for all three.

The frontmatter check is deliberately narrower than YAML: one `key: value` per line, and `name` /
`description` must be one line of plain text YAML reads verbatim (starts with a letter or digit, no
'#', no ': ', no trailing ':', not a bool/null/number) or a fully quoted string. claude.ai and Claude
Code parse it as YAML, and a description YAML misreads (a comment, a null, a folded second line
past the limit) stops the skill from triggering. Stdlib only, like the supervisor. ZIPs are byte-reproducible (fixed timestamps,
sorted entries).
"""

from __future__ import annotations

import argparse
import re
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SKILLS = REPO / ".claude" / "skills"
DEFAULT_OUT = REPO / "dist" / "claude-skills"

NAME_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
NAME_MAX = 64
DESCRIPTION_MAX = 200  # claude.ai upload limit
ALLOWED_KEYS = {"name", "description", "license", "allowed-tools", "metadata", "dependencies"}
RESERVED_WORDS = ("anthropic", "claude")
ZIP_DATE = (2026, 1, 1, 0, 0, 0)


KEY_LINE = re.compile(r"^([a-z][a-z0-9-]*):(?: (.*))?$")
# A plain value YAML reads as exactly this text: starts with a letter or digit, holds no comment
# marker and no ': ', and does not end in ':'. Anything else must be quoted.
PLAIN = re.compile(r"^[A-Za-z0-9][^#\t]*$")
DOUBLE = re.compile(r'^"([^"\\]*)"$')
SINGLE = re.compile(r"^'((?:[^']|'')*)'$")
NON_TEXT = re.compile(r"^(true|false|yes|no|on|off|null|~|[-+]?(0[xob][0-9a-f_]+|[0-9][0-9a-z._:+-]*|\.(inf|nan)))$",
                      re.IGNORECASE)


def _scalar(value: str) -> str | None:
    """The text YAML would read from a one-line value, or None when it would read something else."""
    if m := DOUBLE.match(value):
        return m.group(1)
    if m := SINGLE.match(value):
        return m.group(1).replace("''", "'")
    if PLAIN.match(value) and ": " not in value and not value.endswith(":") and not NON_TEXT.match(value):
        return value
    return None


def frontmatter(text: str) -> tuple[dict[str, str], list[str]]:
    problems: list[str] = []
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, ["does not start with a '---' frontmatter block"]
    try:
        end = next(i for i, ln in enumerate(lines[1:], 1) if ln.strip() == "---")
    except StopIteration:
        return {}, ["frontmatter block is not closed with '---'"]
    fields: dict[str, str] = {}
    key = None
    for ln in lines[1:end]:
        if not ln.strip():
            continue
        if ln.startswith((" ", "\t")):
            # nested mappings are legal under `metadata`; a continuation of a text field is not
            if key in ("name", "description"):
                problems.append(f"`{key}` continues on a second line: keep it on one line")
            continue
        m = KEY_LINE.match(ln)
        if not m:
            problems.append(f"frontmatter line is not 'key: value': {ln!r}")
            key = None
            continue
        key, raw = m.group(1), (m.group(2) or "").strip()
        if key in ("name", "description"):
            value = _scalar(raw)
            if value is None:
                problems.append(f"`{key}` must be plain text on one line, or fully quoted: YAML would not read it as written")
                value = raw
            fields[key] = value
        else:
            fields[key] = raw
    return fields, problems


def validate(skill_dir: Path) -> list[str]:
    md = skill_dir / "SKILL.md"
    if not md.is_file():
        return ["missing SKILL.md"]
    fields, problems = frontmatter(md.read_text(encoding="utf-8"))
    name, desc = fields.get("name", ""), fields.get("description", "")
    if not name:
        problems.append("missing `name`")
    elif not NAME_RE.match(name) or len(name) > NAME_MAX:
        problems.append(f"`name` {name!r} must be lowercase words joined by '-', at most {NAME_MAX} chars")
    elif any(w in name for w in RESERVED_WORDS):
        problems.append(f"`name` {name!r} contains a reserved word")
    elif name != skill_dir.name:
        problems.append(f"`name` {name!r} differs from its folder {skill_dir.name!r}")
    if not desc:
        problems.append("missing `description`")
    elif len(desc) > DESCRIPTION_MAX:
        problems.append(f"`description` is {len(desc)} chars (claude.ai allows {DESCRIPTION_MAX})")
    unknown = sorted(set(fields) - ALLOWED_KEYS)
    if unknown:
        problems.append(f"unknown frontmatter keys: {', '.join(unknown)}")
    return problems


def skill_dirs(root: Path) -> list[Path]:
    return sorted(p for p in root.iterdir() if p.is_dir() and not p.name.startswith((".", "_")))


def package(skill_dir: Path, out: Path) -> Path:
    out.mkdir(parents=True, exist_ok=True)
    dest = out / f"{skill_dir.name}.zip"
    files = sorted(p for p in skill_dir.rglob("*")
                   if p.is_file() and not any(part.startswith(".") or part == "__pycache__"
                                              for part in p.relative_to(skill_dir).parts))
    with zipfile.ZipFile(dest, "w", zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            info = zipfile.ZipInfo(f"{skill_dir.name}/{f.relative_to(skill_dir).as_posix()}", ZIP_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            zf.writestr(info, f.read_bytes())
    return dest


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="validate only; write nothing")
    ap.add_argument("--skills", type=Path, default=SKILLS, help=argparse.SUPPRESS)
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    a = ap.parse_args(argv)
    if not a.skills.is_dir():
        print(f"[skills] no skill folder {a.skills}")
        return 1
    dirs = skill_dirs(a.skills)
    if not dirs:
        print(f"[skills] no skill folders under {a.skills}")
        return 1
    failed = False
    for d in dirs:
        for p in validate(d):
            failed = True
            print(f"[skills] FAIL {d.name}: {p}")
    if failed:
        return 1
    print(f"[skills] {len(dirs)} skills valid")
    if a.check:
        return 0
    a.out.mkdir(parents=True, exist_ok=True)
    (a.out / ".gdignore").touch()  # inside res:// — Godot must not import build output (L-044)
    names = {d.name for d in dirs}
    for stale in a.out.glob("*.zip"):  # a renamed or removed skill must not be uploaded again
        if stale.stem not in names:
            stale.unlink()
            print(f"[skills] removed stale {stale}")
    for d in dirs:
        print(f"[skills] wrote {package(d, a.out)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
