# 04 — Coding Standards (GDScript, Godot 4.7)

> Steering: always included. Rules for writing code once gameplay work begins.

## Naming (consistent, Godot-idiomatic)

- Files & scenes: `snake_case` (`health_component.gd`, `forest_map.tscn`).
- Classes / `class_name`: `PascalCase` (`HealthComponent`).
- Functions, variables: `snake_case`.
- Private members: leading underscore (`_internal_state`).
- Constants & enums values: `UPPER_SNAKE_CASE`.
- Signals: past tense, `snake_case` (`health_changed`, `enemy_died`).
- Booleans read as predicates (`is_dead`, `can_cast`, `has_item`).

## Responsibility & size

- One class = one responsibility. Prefer small components over God Objects.
- Functions short and single-purpose. If a function needs section comments to be
  understood, split it.
- No God Object (a single node that knows about combat + inventory + save + UI).

## State

- Avoid global mutable state. Shared state goes through the documented autoloads in
  `.kiro/steering/03-architecture.md`, exposed via intent-revealing methods.
- Limit singletons; each new autoload needs a `docs/DECISIONS.md` entry.

## Data, not hard-coding

- No hard-coded gameplay data (damage, prices, XP curves, drop rates) in scripts.
  These live in Resources / config. See `docs/DATA_SCHEMA.md`.
- No magic numbers: name constants or move them to data.
- No user-facing string literals in code — route through localization
  (`.kiro/steering/07-localization.md`).

## Duplication & abstraction

- Don't copy/paste logic. Extract when the *same* logic appears a second time —
  not before (avoid premature abstraction).

## Types

- Use static types when they add clarity or catch errors
  (`func take_damage(amount: int) -> void:`). Don't fight the type system where it
  hurts readability; prefer explicit over clever.

## Error handling

- Validate inputs at boundaries (loaded data, save files, external content).
- Fail loudly in development: use `assert()` for programmer errors and
  `push_error()` / `push_warning()` for recoverable/content issues.
- Never silently swallow a failed load or a null that should never be null.

## Comments

- Comment *why*, not *what*. Self-explanatory code needs no narration.
- Keep public component contracts documented (what signals it emits, what it owns).

## Scenes & nodes

- Prefer `@export` + composition over hard `get_node("../..")` paths.
- Prefer signals/`EventBus` over cross-tree reaching.
- Avoid duplicate nodes that do the same job (see `.kiro/steering/05-performance-testing.md`).

## Formatting

- 4-space indent. UTF-8, LF line endings (matches `.editorconfig` / `.gitattributes`).
- `charset = utf-8` is required — Vietnamese text must survive round-trips.

## Definition of done (code)

Build/parse passes **and** the change satisfies `.kiro/steering/08-ai-review-protocol.md`
(dependencies, duplication, side effects, error handling, performance, regression,
tests, docs). Build passing alone is **not** done.
