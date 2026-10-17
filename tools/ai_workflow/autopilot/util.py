"""Small shared helpers: time, hashing, glob matching, secret redaction, atomic writes."""

from __future__ import annotations

import datetime as _dt
import hashlib
import json
import os
import re
import tempfile
from pathlib import Path
from typing import Any, Iterable


def now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).isoformat(timespec="seconds")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


# --- glob matching ----------------------------------------------------------------------------
# Python 3.12 has no PurePath.full_match, and fnmatch lets `*` cross `/`. These patterns follow
# gitignore-ish rules: `**` spans directories, `*` and `?` stay inside one segment, and a pattern
# without a slash matches at any depth only when it starts with `**/`.

_GLOB_CACHE: dict[str, re.Pattern[str]] = {}


def _glob_to_regex(pattern: str) -> re.Pattern[str]:
    cached = _GLOB_CACHE.get(pattern)
    if cached is not None:
        return cached
    i, out = 0, []
    while i < len(pattern):
        c = pattern[i]
        if c == "*":
            if pattern[i:i + 3] == "**/":
                out.append("(?:.*/)?")
                i += 3
                continue
            if pattern[i:i + 2] == "**":
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*")
        elif c == "?":
            out.append("[^/]")
        else:
            out.append(re.escape(c))
        i += 1
    rx = re.compile("^" + "".join(out) + "$")
    _GLOB_CACHE[pattern] = rx
    return rx


def path_matches(path: str, patterns: Iterable[str]) -> bool:
    p = path.replace("\\", "/")
    while p.startswith("./"):
        p = p[2:]
    return any(_glob_to_regex(pat).match(p) for pat in patterns)


# --- secret redaction -------------------------------------------------------------------------

_SECRET_PATTERNS = [
    re.compile(r"sk-ant-[A-Za-z0-9_\-]{8,}"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{16,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)(?<![A-Za-z0-9])((?:[A-Za-z0-9]+[_-])*(?:api[_-]?key|access[_-]?key|token|secret|password|passwd|"
               r"authorization))\b(\s*[:=]\s*|\s+)['\"]?(?!\[REDACTED\])[A-Za-z0-9_\-\.=/+]{12,}['\"]?"),
    re.compile(r"(?i)bearer\s+[A-Za-z0-9_\-\.=/+]{16,}"),
    # passwords are often short: any value of 4+ characters after a password-like key
    re.compile(r"(?i)(?<![A-Za-z0-9])((?:[A-Za-z0-9]+[_-])*(?:password|passwd|pwd|secret))\b(\s*[:=]\s*)"
               r"['\"]?(?!\[REDACTED\])[^\s'\"]{4,}['\"]?"),
]


def redact(text: str) -> str:
    if not text:
        return text
    out = text
    for rx in _SECRET_PATTERNS:
        if rx.groups >= 2:
            out = rx.sub(lambda m: f"{m.group(1)}{m.group(2)}[REDACTED]", out)
        else:
            out = rx.sub("[REDACTED]", out)
    return out


def redact_obj(obj: Any) -> Any:
    if isinstance(obj, str):
        return redact(obj)
    if isinstance(obj, list):
        return [redact_obj(x) for x in obj]
    if isinstance(obj, dict):
        return {k: redact_obj(v) for k, v in obj.items()}
    return obj


# --- atomic file writes -----------------------------------------------------------------------

def atomic_write_text(path: Path, text: str) -> None:
    """Write `text` so a crash leaves either the old file or the new one, never half of one."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise
    try:  # make the rename itself durable (POSIX); harmless no-op elsewhere
        dfd = os.open(str(path.parent), os.O_RDONLY)
        try:
            os.fsync(dfd)
        finally:
            os.close(dfd)
    except (OSError, AttributeError):
        pass


def atomic_write_json(path: Path, obj: Any) -> None:
    atomic_write_text(path, json.dumps(obj, indent=2, ensure_ascii=False, sort_keys=False) + "\n")


def append_jsonl(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    line = json.dumps(redact_obj(record), ensure_ascii=False, sort_keys=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")
        fh.flush()
        os.fsync(fh.fileno())


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            # A torn final line after a crash is skipped, not fatal; earlier lines stay valid.
            continue
    return out
