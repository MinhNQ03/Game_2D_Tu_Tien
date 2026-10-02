# 08 — AI Review Protocol

> Steering: always included. The mandatory checklist Kiro (and any AI contributor)
> runs for **every** code change in this project. This governs how AI works here.

## Before writing code (every change)

1. **Read the architecture** — `.kiro/steering/03-architecture.md` and
   `docs/ARCHITECTURE.md`. Confirm which layer the change belongs in.
2. **Read the flow** — `docs/GAME_FLOW.md`. Understand how the touched system fits the
   whole game flow and what it depends on / feeds.

## While writing code

3. **Check dependencies** — does the change respect layer direction? No upward
   dependency (domain → presentation), no forbidden boundary crossing.
4. **Check duplicated logic** — is this logic already implemented elsewhere? Reuse or
   extract instead of copy/paste.
5. **Check side effects** — what signals fire, what global/autoload state mutates, what
   else reacts? Are those intended?
6. **Check error handling** — inputs validated at boundaries; failures loud in dev; no
   silently swallowed nulls/load failures.
7. **Check performance** — any new `_process`/`_physics_process` load, per-frame
   allocation, hot-path object creation, redundant signals, duplicate nodes? Measure if
   non-trivial; log per `docs/PERFORMANCE.md`.

## After writing code

8. **Check regression** — what existing behavior could this break? Run smoke + related
   tests. Convert any found regression into a permanent test.
9. **Check tests** — high-risk areas (damage, combat, inventory, progression, XP,
   level, cultivation, skill, quest, save/load, localization, map transitions) must have
   or get tests. See `docs/TEST_PLAN.md`.
10. **Update related documentation** — `GAME_FLOW`, `ARCHITECTURE`, `DATA_SCHEMA`,
    `SAVE_FORMAT`, `DECISIONS`, `CHANGELOG`, `PERFORMANCE`, `DEBUGGING` as applicable.

## Hard rule

> **"Build passes" is NOT sufficient to call a feature done.**

A green compile/parse only means the code loads. Done requires: correct layer, no
duplication, intended side effects, real error handling, acceptable (measured)
performance, no regressions, tests for high-risk logic passing, and docs updated.

## Reporting

When finishing a unit of work, report against this checklist: what was verified, what
could not be verified, and any open risks. Do not overstate confidence. Do not proceed
to the next step/feature unless asked.

## Extensibility gate

Before merging a system touch, confirm the extensibility rule still holds: can we still
add a map / chapter / quest / enemy / boss / pet / skill / item / cultivation tier as
*data + content* without editing core code? If this change broke that, flag it in
`docs/DECISIONS.md`.
