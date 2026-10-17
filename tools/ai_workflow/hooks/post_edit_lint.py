#!/usr/bin/env python3
"""PostToolUse feedback: after an Edit/Write of a .gd file, run the project's engine-free lint on
that file and hand any finding back to Claude as context. Read-only, bounded (one file, 60 s),
never blocks and never re-triggers itself, so it cannot loop."""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0
    path = str((event.get("tool_input") or {}).get("file_path") or "")
    if not path.endswith(".gd"):
        return 0
    root = Path(os.environ.get("CLAUDE_PROJECT_DIR") or Path(__file__).resolve().parents[3])
    lint = root / "tools" / "gdscript_lint.py"
    if not lint.exists() or not Path(path).exists():
        return 0
    try:
        p = subprocess.run([sys.executable, str(lint), path], cwd=root, capture_output=True, text=True, timeout=60)
    except (subprocess.TimeoutExpired, OSError):
        return 0
    if p.returncode == 0:
        return 0
    out = (p.stdout + p.stderr).strip().splitlines()[-25:]
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": "[aetheria-lint] tools/gdscript_lint.py reports for this file (CI fails on these):\n"
                             + "\n".join(out)}}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
