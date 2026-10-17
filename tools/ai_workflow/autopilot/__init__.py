"""Aetheria autopilot: a local supervisor that drives Claude Code CLI work items through
implement -> validate -> independent review -> fix -> verify -> checkpoint -> next task.

The supervisor (Python) owns the loop, the state, the branch and every stop condition. Claude
invocations are workers; their prose is never the source of truth for completion.
"""

ORCHESTRATOR_VERSION = "1.0.0"
STATE_SCHEMA_VERSION = 1
