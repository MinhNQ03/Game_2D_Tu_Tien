# Obsidian Setup — Aetheria Knowledge Hub

## Why Obsidian fits this project

The repository already stores knowledge as plain-text Markdown under version
control. Obsidian's four strengths map directly onto that:

1. **Local-first, no lock-in.** Obsidian reads the repo's `.md` files in place —
   the vault *is* the working tree. If Obsidian vanished tomorrow, every note
   remains readable in any editor and every change remains in git history.
   Nothing is uploaded anywhere; no second database to diverge.
2. **Bidirectional linking.** Standard relative links like
   `[Canon Ledger](../CANON_LEDGER.md)` already work; Obsidian adds **backlinks** (who links here?) and the **graph view**,
   which is how an agent-or-human discovers "which systems depend on this rule"
   without grepping. The [dependency map](DOCS_DEPENDENCY_MAP.md) is the
   curated version of what the graph shows organically.
3. **Ecosystem, used sparingly.** Core features (search, backlinks, graph,
   outline) cover the hub's needs. Community plugins are optional and
   per-user — never required for the hub to work, never committed to the repo.
4. **Speed.** File-local Markdown means instant search over 6,000+ lines of
   `DECISIONS.md` and the full canon set, offline.

**Vision for an online xianxia game:** Aetheria's knowledge has a long half-life
— ten acts, nine reveal layers, sect politics, and a multiplayer target that
spans phases 32–34. The failure mode is not "forgot a fact" but "changed a
system without seeing its dependents" (the exact class the
[DOCS_SYNC_CONTRACT.md](DOCS_SYNC_CONTRACT.md) exists to prevent). Obsidian
makes the *connections* visible: canon → decisions → systems → phases → gates.
Effect: fewer contradiction bugs (L-014 class), faster onboarding for new
agents, and a review surface where the owner can *see* what a proposal touches
before accepting it. Benefit: the project's scarcest resource — owner review
attention — is spent on decisions, not on rediscovering context.

## Opening the vault (owner does this once)

1. Install Obsidian (https://obsidian.md).
2. **Open folder as vault** → select the repository root
   (the folder containing `docs/`, `.kiro/`, `project.godot`).
3. Recommended core settings (all local, none committed):
   - *Files & Links*: default location for new notes — same folder as current file
     is fine; the hub itself creates no notes.
   - *Core plugins*: enable **Backlinks**, **Outline**, **Search**.
4. Open [AETHERIA_KNOWLEDGE_HUB.md](AETHERIA_KNOWLEDGE_HUB.md) and pin it
   (`Ctrl/Cmd+Shift+P` → "Pin").

**What is ready natively, no plugins:** full-text search (`Ctrl/Cmd+Shift+F`),
backlinks pane (every page shows who links to it), local graph (`Ctrl/Cmd+G`
on a page), global graph (command palette → "Open graph view"), following
`../` relative links, and the decision index as a searchable table.

**What is intentionally not committed:** `.obsidian/` workspace state
(hotkeys, themes, plugin data) is personal configuration. The repo stays
clean; any developer's Obsidian works the same against the same Markdown.

## Optional: AI read/write integration (owner decision, not required)

The repo's coding agents already work directly on tracked files — no REST/MCP
layer is needed for the hub to function. If you want Obsidian itself to be
drivable by an agent:

1. Install the community **obsidian-local-rest-api** plugin (via Obsidian's
   Community Plugins browser — a manual UI step the agent cannot do for you).
2. Bind it to **localhost only**; require the API key on every call.
3. **Never commit the API key**, a token, or any credential — keep it in the
   local Obsidian config (uncommitted) or a local secret store.
4. An MCP wrapper (e.g. an Obsidian MCP server) can then expose vault search
   to agents — useful only if you want agents to query Obsidian instead of
   reading the repo files directly, which they already can.

**Implemented by the agent:** this document, the hub pages, the validator.
**Requires the owner:** installing Obsidian, opening the vault, any plugin
install, any API key creation. Nothing here phones home.

## Safe Git workflow with an Obsidian vault open

Remote changes are **not** auto-pulled into the vault:

```bash
git fetch --all --prune
git status --short          # read it: any local edits?
git stash list              # any stashed work?
# only then:
git pull --ff-only          # never overwrite uncommitted work
```

- Obsidian reflects saved local files through its normal file watching —
  no action needed after a pull.
- **No auto-commit / auto-push is configured or wanted.** Knowledge changes go
  through the same review as code changes ([DOCS_SYNC_CONTRACT.md](DOCS_SYNC_CONTRACT.md)).
- If Obsidian shows a file as externally modified while you have unsaved
  edits, let Obsidian keep your version, then reconcile with git.

## Limitations (honest)

- Obsidian shows **files**, not **truth**: a green graph does not mean the
  prose agrees. Semantic review is the agent's job (sync contract, step 8).
- The graph is only as good as the links: new docs should link their owner
  and dependents (the validator checks hub links resolve, not that every
  possible link exists).
- Generated files (`DECISION_INDEX.md`) refresh via the generator, not via
  Obsidian — rerun `python3 tools/gen_decision_index.py` after editing
  `docs/DECISIONS.md`.
