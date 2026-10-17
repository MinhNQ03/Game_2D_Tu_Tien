#!/usr/bin/env python3
"""SessionStart context: a three-line digest of the autopilot state and the open owner gates, so a
native (VS Code) session knows what the supervisor is doing. Read-only and silent on any error."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
sys.path.insert(0, str(HERE.parents[1]))


def main() -> int:
    try:
        json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        pass
    if os.environ.get("AETHERIA_AUTOPILOT_ROLE"):
        return 0  # supervisor-launched workers get their context from the prompt
    try:
        from autopilot.config import load_config
        from autopilot import gates
        cfg = load_config(Path(os.environ.get("CLAUDE_PROJECT_DIR") or HERE.parents[3]))
        og = [g.id for g in gates.gate_statuses(cfg) if g.open]
        lines = [f"[aetheria-autopilot] open owner gates: {', '.join(og) or 'none'} "
                 "(never close or bypass them; see tools/ai_workflow/README.md)"]
        sp = cfg.state_dir / "state.json"
        if sp.exists():
            st = json.loads(sp.read_text(encoding="utf-8"))
            cur = st.get("current_item")
            stop = st.get("stop") or {}
            lines.append(f"[aetheria-autopilot] campaign {st['campaign']['id']} on {st['campaign']['branch']}: "
                         f"current={cur} stop={stop.get('reason')}")
        print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                                 "additionalContext": "\n".join(lines)}}))
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
