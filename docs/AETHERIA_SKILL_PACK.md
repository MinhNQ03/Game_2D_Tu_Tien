# AETHERIA SKILL PACK — one set of skills for Claude Code, the autopilot and claude.ai

> **Status:** CURRENT tooling (2026-10-20). Not a phase; changes no gameplay. The skills are METHOD
> and pointers — the owner documents they name win (`docs/knowledge/AETHERIA_KNOWLEDGE_HUB.md`).
> Charter text: `.claude/skills/aetheria-studio-charter/references/CHARTER.md`.

Modelled on how a three.js skill pack is shipped for coding agents: install the skills BEFORE
giving the agent work, keep each skill small and version-pinned, carry the "known pitfalls"
that were learned the hard way, and work in stages with acceptance criteria. Here the pitfalls
are the project's own `L-nnn` lessons and the stages are the autopilot loop.

## 1. What is in the pack

Ten skills in `.claude/skills/` (map: `.claude/skills/README.md`):

| Skill | Use it for |
|---|---|
| `aetheria-studio-charter` | choosing the next task, priorities, definition of done, escalation, run reports |
| `aetheria-work-item` | one change end to end in a native session |
| `aetheria-autopilot` | operating the supervisor |
| `aetheria-godot-gdscript` | Godot 4.7.2 commands and GDScript traps |
| `aetheria-architecture` | layers, state ownership, save safety, signals, data |
| `aetheria-visual-craft` | how art is made to look designed |
| `aetheria-art-pipeline` | Blender 5.2 → pixel/props/icons/story art/VFX commands |
| `aetheria-ui-localization` | screens, HUD, vi + en |
| `aetheria-narrative-canon` | canon authority and the story depth bar |
| `aetheria-knowledge-ledger` | where learning is written |

## 2. Where they apply (one source, three consumers)

| Consumer | How it gets the skills | Action needed |
|---|---|---|
| Claude Code in this repo (VS Code / terminal) | reads `.claude/skills/` automatically | none |
| Autopilot workers (`claude -p`) | `setting_sources: project` loads the same folder; the task prompt names `.claude/skills/README.md`; the planner ranks by the charter | none |
| claude.ai (web / desktop / mobile) | uploaded ZIPs | §3 |

Any edit under `.claude/skills/` (SKILL.md, the map, `references/`) changes the autopilot policy fingerprint: commit it between items, never while
a run holds the lock, after `python3 -m unittest discover -s tools/ai_workflow/tests -t tools/ai_workflow`
and `python3 tools/ai_workflow/aetheria_autopilot.py eval --max-usd 3`.

## 3. Install on claude.ai

Prerequisite: Settings → Capabilities → **Code execution** on.

```bash
python3 tools/ai_workflow/package_skills.py           # validates, writes dist/claude-skills/<name>.zip
python3 tools/ai_workflow/package_skills.py --check   # validate only
```

Then open **claude.ai/customize/skills** → upload each ZIP → switch it on. Re-run the script and
re-upload after a skill changes (claude.ai does not read the repo). The script enforces what
claude.ai requires: the folder at the ZIP root, folder name = `name`, `description` ≤ 200
characters, and `name` / `description` written as one line that YAML reads verbatim (plain text
without `#`, `: ` or a trailing `:`, or fully quoted) — checked against PyYAML in the tests.

Skills on claude.ai know the RULES but not the live code. For real files, attach the GitHub repo
`MinhNQ03/Game_2D_Tu_Tien` to the chat or Project; the skills tell Claude never to claim it read
a file it could not open.

### Project instructions for claude.ai (paste into a Project's custom instructions)

```text
You are working on Aetheria, a Godot 4.7 2D cultivation (tu tiên) RPG — repo MinhNQ03/Game_2D_Tu_Tien.
Reply in Vietnamese; keep code, ids and file names in English.
Before any answer about this game, load the matching Aetheria skills:
- planning, priorities, "what next", reviews of progress → aetheria-studio-charter
- GDScript / scenes / tests → aetheria-godot-gdscript + aetheria-architecture
- art, sprites, maps, VFX → aetheria-visual-craft + aetheria-art-pipeline
- UI, HUD, text, vi/en → aetheria-ui-localization
- story, quests, NPCs, items → aetheria-narrative-canon
- anything learned worth keeping → aetheria-knowledge-ledger (say which repo file it belongs in)
Facts come from the attached repo files, never from memory; if a file is not available, say so.
Owner gates H21-14, ART-DIR-01 and ART-DIR-02 are the owner's: never treat them as closed.
Output that must reach the autopilot goes into a repo change (file path + exact content), because
the autopilot only reads the repository.
```

## 4. Install on another machine (Claude Code)

The pack lives in the repo, so a clone has it. To use it in a different project:

```bash
git clone --depth 1 https://github.com/MinhNQ03/Game_2D_Tu_Tien.git /tmp/aetheria
mkdir -p .claude/skills && cp -r /tmp/aetheria/.claude/skills/aetheria-* .claude/skills/
```

Copy to `~/.claude/skills/` instead to have them in every project.

## 5. Bootstrap prompt (Claude Code session or a new campaign)

```text
Load aetheria-studio-charter and follow it. Bootstrap: git status/branch/HEAD, autopilot `status`
and `gates`, docs/ROADMAP.md and docs/handoff/ for the next playable milestone. Name the three
most consequential weaknesses with evidence (file:line, capture, test log), pick the highest-value
eligible one, and run it through aetheria-work-item (or the supervisor if a campaign is active).
Report in the charter skill's §9 format. Do not start a production campaign without my --activate.
```

## 6. Limits (honest)

- The charter does not authorize work by itself; a broader continuous-improvement campaign still
  needs its own campaign file and the owner's `start --campaign … --activate`.
- claude.ai copies go stale when the repo changes; re-package after every skill commit.
- Skills cannot make headless workers see images that exist only in a chat (`CHARTER.md` §4).
