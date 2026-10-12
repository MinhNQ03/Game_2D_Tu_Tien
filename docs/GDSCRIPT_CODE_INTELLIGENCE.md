# GDScript Code Intelligence — Aetheria

**What this is.** The supported workflow for an AI coding agent to navigate the
GDScript codebase with engine-verified answers: find definitions, true
references (not comment matches), signatures, signal connections, and
change impact. Verified 2026-10-12 on Godot 4.7.2 + this repository.

## Primary: GodotLens MCP

[GodotLens](https://github.com/pzalutski-pixel/godotlens-mcp) (Apache 2.0,
supports Godot 4.6+) connects an MCP client to Godot's own language server.
It is the only option that gives **engine-verified** answers.

### Setup

1. Install: `pip install --break-system-packages godotlens-mcp`
   (or `npx -y godotlens-mcp`; v1.1.1 verified reachable 2026-10-12).
2. Keep one headless editor running in the background:
   ```
   ~/workspace/.local/bin/Godot_v4.7.2-stable_linux.x86_64 --headless \
     --path /home/hatch/workspace/repos/game-exp \
     --editor --lsp-port 6005 --dap-port 6006
   ```
   Wait for `ss -ltn | grep 6005`. First boot ~45s (import); later boots reuse cache.
3. MCP config:
   ```json
   {"mcpServers":{"godotlens":{"command":"godotlens-mcp","env":{
     "GODOT_BIN":"/home/hatch/workspace/.local/bin/Godot_v4.7.2-stable_linux.x86_64",
     "GODOT_PROJECT_ROOT":"/home/hatch/workspace/repos/game-exp",
     "GODOT_LSP_PORT":"6005","GODOT_DAP_PORT":"6006"}}}}
   ```
4. Smoke test: `gdscript_status` → `gdscript_hover` on a known symbol.

### Agent loop

Understand (`gdscript_find` / `references` / `hover`) → write →
`gdscript_validate` **before** writing to disk → `gdscript_sync_file` →
verify (`diagnostics`, `scene_validate`).

### Limitations (observed, not guessed)

- LSP reads `.gd` only. Signal handlers wired in `.tscn [connection]`
  sections need `scene_validate`, not `references`.
- Autoload names and input actions are bare strings; not validated.
- `references` is expensive on 4.6+ (~4s on this 365-file repo);
  use `references_in_file` when the file is known.
- LSP does not watch the filesystem: call `gdscript_sync_file` after every edit.
- A result with `verified:false` and empty diagnostics is **not** "clean".
- Godot 4.7 reports `workspaceSymbolProvider: false`: no native
  project-wide symbol search; `gdscript_find` uses a bounded heuristic
  (`GODOT_FIND_FILE_LIMIT=60`).

## Fallback: ripgrep patterns (no engine)

When the editor is not running. Fast but semantically blind.

```bash
rg -n -g "*.gd" "^class_name (\w+)"        # class_name → file
rg -n -w "symbol_name" --glob "*.gd"       # references (INCLUDES comments — filter by eye)
```

Caveat (measured): `rg -w is_collected` gave 22 hits, 2 of them comments;
the LSP gave 9 true code hits. Never count a comment as a caller.

## What was verified

2026-10-12, VM (no GPU), Godot 4.7.2 stable official:
- Editor headless boot with `--lsp-port 6005 --dap-port 6006`: LISTEN confirmed.
- Raw LSP handshake via Python socket: `initialize` → capabilities
  (`definitionProvider`/`referenceProvider`/`hoverProvider`/
  `documentSymbolProvider`: true).
- `documentSymbol` on `inventory_runtime.gd`: class `InventoryRuntime`, 49 children.
- `hover` on `is_collected`: `func is_collected(pickup_id: StringName) -> bool`.
- `references`: 9 true hits in 3.7s (rg found 22 incl. comments).
- `godotlens-mcp` 1.1.1 installs cleanly; binary at `/usr/local/bin/godotlens-mcp`.

## Integration with the development procedure

Per `.kiro/steering/08-ai-review-protocol.md`: before changing a state owner
or public method, find its callers (`references`), tests, scene/data
references and affected boundaries; after editing, re-run the relevant checks.
Use `gdscript_validate` before writing GDScript to disk.
