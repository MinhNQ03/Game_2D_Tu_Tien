# Aetheria skill pack — which skill for which work

Project skills for Claude Code (loaded from `.claude/skills/` by interactive sessions AND by every
headless autopilot worker, `setting_sources: project`). Each skill is METHOD plus pointers; the
owner documents it names win on any disagreement. Packaged for claude.ai by
`tools/ai_workflow/package_skills.py` (install guide: `docs/AETHERIA_SKILL_PACK.md`).

| Area of the change | Skill(s) |
|---|---|
| choosing what to do next, priorities, done, escalation, run reports | `aetheria-studio-charter` |
| one non-trivial change end to end (native session) | `aetheria-work-item` |
| running / resuming / inspecting the supervisor | `aetheria-autopilot` |
| any `.gd` / `.tscn` / `.tres`, tests, E2E | `aetheria-godot-gdscript` |
| gameplay systems, state, save, signals, data | `aetheria-architecture` |
| how art should look (method) | `aetheria-visual-craft` |
| generating assets (Blender, pixel, props, icons, story art, VFX) | `aetheria-art-pipeline` |
| screens, HUD, strings, vi/en | `aetheria-ui-localization` |
| quests, dialogue, NPCs, items, lore | `aetheria-narrative-canon` |
| recording what was learned | `aetheria-knowledge-ledger` |

Typical stacks: a UI change = work-item + ui-localization + godot-gdscript; a sprite upgrade =
charter skill §5 + visual-craft + art-pipeline + work-item; a new quest = narrative-canon +
architecture + ui-localization.

Changing any file here (a `SKILL.md`, this map, a `references/` file) changes the autopilot policy fingerprint (`autopilot/knowledge.py`): commit it
between items, never while a run is in flight, after the autopilot unit tests and `eval`.
