# 07 — Localization

> Steering: always included. Localization is a foundation concern, not a polish task.

## Supported languages

- `vi` — Vietnamese (first-class)
- `en` — English (first-class)

Both are supported from the foundation. The architecture must allow adding a third
language later by adding data only, no code changes.

## Hard rules

- **No hard-coded user-facing text** — not in UI, not in gameplay, not in dialogue,
  not in item/skill/quest names or descriptions.
- All displayed strings are referenced by a stable **key** and resolved at runtime
  through the `Localization` service (autoload) / Godot's translation system.
- Content data (items, skills, quests, dialogue) stores **keys**, not literal strings.
  See `docs/DATA_SCHEMA.md`.

## Key convention

Namespaced, stable, `UPPER_SNAKE_CASE` after a domain prefix:

```
UI_MENU_NEW_GAME
ITEM_POTION_HEALTH_NAME
ITEM_POTION_HEALTH_DESC
SKILL_FIREBALL_NAME
QUEST_PROLOGUE_01_TITLE
DIALOGUE_ELDER_INTRO_01
REALM_FOUNDATION_NAME
```

Keys never change once shipped (changing a key is a breaking content change — log it
in `docs/DECISIONS.md`).

## Mechanism (decision, detail in docs)

- Use Godot's built-in translation (`TranslationServer` + CSV/PO) as the backing store
  where it fits, wrapped by a thin `Localization` service so call sites stay stable and
  testable. Final file format (CSV vs PO) is recorded in `docs/DECISIONS.md`.
- The `Localization` service exposes: current language, set language, and `tr(key)` /
  `tr(key, args)` with parameter substitution.

## Formatting & pluralization

- Support runtime substitution (names, numbers): e.g. `"Nhận được {amount} {item}"`.
- Avoid building sentences by string concatenation (breaks grammar across languages).
  Use parameterized templates per language.

## Fonts

- The chosen font MUST render full Vietnamese diacritics and the English set. Verify
  before committing. See `.kiro/steering/06-art-assets.md`.

## Testing

- Localization lookup is a high-risk area: tests assert every key used in content
  exists in both `vi` and `en`, and that no literal user-facing strings leak into code.
  See `docs/TEST_PLAN.md`.
