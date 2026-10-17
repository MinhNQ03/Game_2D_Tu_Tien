# GDScript code intelligence — how an agent finds definitions, callers and impact

**What this is.** The supported way for a coding agent (or a person) to answer "where is this
defined, who really calls it, what data names it, what breaks if I change it" in Aetheria —
asked of the engine where the engine can answer, and of the files where it cannot. Set up and
verified in the experience upgrade (2026-10-17) against Godot 4.7.2 on this machine.

**What it is not.** It is no substitute for the gates (`docs/TEST_PLAN.md`): a reference list
proves nothing about behaviour. It writes nothing into the project.

## 1. The two tools, and why two

| Question | Asked of | Tool |
|---|---|---|
| definition, real references / call sites, hover type, signature, document symbols, rename, diagnostics, engine API, completion, project config (autoloads, `class_name` globals, input actions), a scene's node tree / exported values / `[connection]`s and whether each targets a method that exists, run + debug | **Godot itself** (its language server and debug adapter) | **GodotLens MCP** (`godotlens-mcp` 1.1.1, Apache-2.0, needs Godot ≥ 4.6) |
| which `.tres`/`.tscn` names a resource, uid or id; a localization key's two strings and every place that shows it; a scene's ext_resources and whether each file exists; locale keys nothing references | **the files** (Godot's language server reads only `.gd`) | **`tools/code_intel.py`** (repository-local, stdlib, read-only, deterministic) |

Every `code_intel` hit is labelled `data`, `code`, `generator`, `comment` or `doc`, so a word in
a comment is never counted as a use, and no edge is ever invented.

**Signals in this project are wired in code**, never in a scene: no `.tscn` contains a
`[connection]` (checked 2026-10-17). So a signal's listeners are exactly the `.connect` calls the
language server finds — `gdscript_find <signal> include_references` is the complete answer, and
`scene_validate` reports `connections_checked: 0` for every scene, which is correct, not a gap.

## 2. Setup (local; nothing here is committed config)

Machine-specific paths (the Godot binary, a port) belong in the user's own MCP settings, not in
the repository.

1. Godot editor, headless, with its language server and debug adapter (keep it running):
   ```
   ~/Downloads/Godot_v4.7.2-stable_linux.x86_64 --path . --editor --headless \
       --lsp-port 6005 --dap-port 6006
   ```
   (`--import` first on a fresh checkout. The VS Code Godot extension uses 6008; set
   `GODOT_LSP_PORT` if you use that instead.)
2. The MCP server, through npx (Node ≥ 16; Node 22 here) — add to the user-scope or
   local-scope MCP config of the agent, e.g. Claude Code:
   ```
   claude mcp add godotlens --scope local \
       -e GODOT_BIN=$HOME/Downloads/Godot_v4.7.2-stable_linux.x86_64 -- npx -y godotlens-mcp
   ```
   or with pip: `pip install godotlens-mcp` and the command `godotlens-mcp`.
3. Connection check: the `gdscript_status` tool must answer
   `{"status": "connected", "message": "Connected to Godot LSP", "port": 6005}`.

**Which editor answers.** A Godot editor opened normally on the project ALSO serves the language
server on 6005. On 2026-10-17 the owner's own editor was open, so the verified queries were
answered by a Godot 4.7.2 editor on this machine — that one or the headless one started for the
check; either way the engine's language server, not a text search. If two editors compete for
the port, start the headless one with another `--lsp-port` and set `GODOT_LSP_PORT` to match.

An agent session only sees MCP servers that were configured when it started: after adding the
server, start a new session. **Verified here** by a scripted stdio MCP client (the same JSON-RPC
an agent speaks) — 36 tools listed, every query in §3 answered. An agent that cannot reach a
local MCP server (a remote/cloud agent) has only §4.

## 3. Real queries, real answers (2026-10-17, this branch)

| Query | Answer (abridged) |
|---|---|
| `gdscript_find personal_objective_key include_references` | declared `StoryService.personal_objective_key()` (story_service.gd:202); referenced by `StoryService.objective_key()` (:194), `StoryRuntime.build_view()` (story_runtime.gd:400) and two tests — the same-named view fields are listed as separate declarations, not merged |
| `gdscript_find bolt_struck include_references` (a presentation cue) | `signal bolt_struck(position)` in `SkillRuntime`; emitted twice (skill_runtime.gd:359, :365); connected/disconnected in `CastFeedback` (:94, :105); listened to by the world E2E |
| `scene_validate main.tscn hub_map.tscn field_map.tscn` | all valid, 0 problems, 0 connections (see §1) |
| `project_config` | 5 autoloads (EventBus, GameState, Localization, InputService, SceneRouter), main scene, every `class_name` global with its base |
| `code_intel.py id know_convoy_report` | 5 data hits (dialogue opening + choice + effect, the knowledge catalog, the origin's personal step) + 1 generator (`author_story_data.py`) |
| `code_intel.py key STORY_PERSONAL_HO_TIEU_1` | its en/vi strings; used only by `data/story/origin_catalog.tres` (generated) |
| `code_intel.py res res://data/fx/qi_gather.tres` | `CultivationFeedback.GATHER_PATH` and the VFX test |
| `code_intel.py scene res://src/gameplay/maps/field_map.tscn` | every ext_resource exists; 125 nodes; no scene-wired connection |

Line numbers are 1-based above; GodotLens itself speaks 0-based.

## 4. The procedure (before and after a change)

Before changing a state owner, a public method, a signal or a data id:

1. `gdscript_find <name> include_references` — every real caller; read each one.
2. For anything data names (an id, a key, a resource path): `code_intel.py id|key|res`.
3. The tests that exercise it: the `code` hits under `tests/` from either tool, then
   `-s res://tests/run_tests.gd -- <substring>`.
4. A scene you touch: `scene_validate` (GodotLens) and `code_intel.py scene`.

After the edit: `gdscript_sync_file` (so the server sees the new text), `gdscript_diagnostics`
on the touched files, the same queries again (a caller that vanished or appeared is a finding),
then the gates of `TEST_PLAN.md`.

**Fallback when GodotLens is unavailable** (no display needed, but no editor running, or a
remote agent): `python3 tools/gdscript_lint.py`, `-s res://tools/parse_check.gd`, and
`code_intel.py id <symbol>` — which is TEXTUAL for code and says so: a `code` hit is a line that
names the symbol, not a proven call. Do not report textual hits as call sites.

## 5. Limits (stated, not hidden)

- The language server reads `.gd` only; resources, scenes and the CSV are `code_intel`'s, and it
  matches text, so a key built at runtime (`"%s_NAME" % stem`) is reported by `orphans` as
  unused — a review list, never an automatic deletion.
- GodotLens needs a running editor on the project; its answers are as fresh as the files the
  editor has (sync after editing).
- The `debug_*` tools run the real game; they are evidence about behaviour only as far as a run
  is — the gates still decide.
