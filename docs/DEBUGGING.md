# DEBUGGING — Aetheria

> A playbook for diagnosing problems in this project. Grows as real bugs are found; a
> fixed bug should leave behind a regression test (`docs/TEST_PLAN.md`) and, if it
> revealed a pattern, an entry here.
>
> **CURRENT STATUS (through Phase 11 + its D-055 close-out):** this is the method and the
> toolbox, and it is in active use — the project has diagnosed and fixed a steady stream of
> real defects (headless Area2D/input timing, a `class_name` that failed to compile and
> cascaded as "nonexistent function", a reversed session teardown, a fail-open mirror, a
> `RefCounted` reference cycle leaking the test suite, a tick loop that sorted the whole cast,
> a hydrate boundary that crashed instead of failing closed, a fail-OPEN empty reward id, and a
> gameplay action with no on-screen cue). It previously said "no gameplay bugs yet", which
> stopped being true several phases ago.
>
> **The two classes of defect the gates CANNOT see**, both now with worked examples:
> - **Anything on screen.** A headless run renders nothing, so a layout, colour or
>   discoverability defect survives a fully green pipeline. Reach for `tools/playtest_flow.gd`
>   (real app, real input, per-step expected-vs-observed) and `tools/capture_ui.gd`, then
>   **OPEN the output** — D-050, D-053, D-054 and D-055 each found defects that way, and
>   generating the evidence is not reviewing it.
> - **An invariant nothing asserts.** A rule that lives only in a docstring is a comment. When
>   a claim is worth writing down ("X is the only writer", "no file in this layer may Y"),
>   prefer a structural test that WALKS the directory (L-034) over trusting the sentence.
>
> **Where incidents are recorded:** the durable, do-not-repeat RULE goes in
> `.kiro/steering/09-lessons-learned.md` (L-0NN) and the DECISION/context goes in
> `docs/DECISIONS.md`. §7 below is deliberately NOT a third copy — see the note there.

## 1. Method (don't guess, isolate)

1. Reproduce reliably. Seed the RNG (`Config`/`RNG`) so the case is deterministic.
2. Locate the layer (`docs/ARCHITECTURE.md`): is it presentation, gameplay, domain,
   data, persistence, or infrastructure? Bugs usually live where the *rule* is, not
   where it's displayed.
3. Shrink the case to the smallest reproduction (ideally a headless unit/integration
   test).
4. Fix at the root cause, not the symptom. If two patches in a row don't work, stop and
   re-diagnose — the model of the bug is wrong.
5. Pin it: add a regression test so it can't come back.

## 2. Godot toolbox

- **Debugger → Errors/Stack** — read the actual stack; don't assume.
- **Debugger → Profiler** — frame cost (performance bugs).
- **Debugger → Monitors** — node/object/**orphan** counts, draw calls, memory.
- **Remote scene tree** (while running) — inspect live node state and signal
  connections.
- `print_debug()`, `push_warning()`, `push_error()` — loud in dev; never swallow errors.
- Run headless to isolate logic from rendering:
  `godot --headless --path . -s res://tests/run_tests.gd`.

## 3. Common classes of bug to expect (and where to look)

| Symptom | Likely cause | Where |
|---|---|---|
| Leak / rising memory after changing maps | nodes not freed, signals not disconnected | SceneRouter / map lifecycle (gameplay) |
| "Works but wrong number" in combat | formula or data, not UI | damage formula (domain) + DATA_SCHEMA |
| State lost / wrong after load | `to_dict/from_dict` mismatch or missing migration | SaveService (persistence) |
| Text shows a key or wrong language | missing/!resolved localization key | Localization + content keys |
| Non-reproducible behavior | unseeded RNG or time-based logic | RNG usage (breaks determinism) |
| Quest never completes | event not emitted / listener not connected | EventBus wiring + quest FSM |
| Signal fired twice | duplicate connection | connect site; disconnect on tree exit |

## 4. Determinism checklist (important for this project)

Because combat/progression must be deterministic (and multiplayer-ready later):
- All randomness goes through the seeded `RNG` service — no bare `randi()/randf()`.
- No gameplay logic keyed off wall-clock time or frame-rate-dependent deltas without
  care.
- Same seed + same inputs ⇒ same outcome. If not, that's a determinism bug (high
  priority).

## 5. Logging conventions

- Namespaced prefixes in logs: `[combat]`, `[save]`, `[router]`, `[loc]`, `[quest]`.
- Log *decisions and failures*, not spam. No per-frame logging in hot paths.
- A failed resource load or an unexpected null is `push_error`, never a silent skip.

## 6. When stuck

- Re-read `docs/GAME_FLOW.md` for the system's contract (input/state/processing/output).
- Write the failing case as a test first; often the act of isolating reveals the cause.
- If the fix would bend an architecture rule, that's a signal — raise it in
  `docs/DECISIONS.md` rather than quietly violating a boundary.

## 7. Bug log (append real incidents)

```
### BUG-00X — <short title> (YYYY-MM-DD)
- Symptom:
- Root cause:
- Fix:
- Regression test: tests/.../test_...gd
- Pattern worth remembering? (add to §3 if so)
```

> **This log is intentionally EMPTY, and that is not drift (D-049).**
>
> Real incidents ARE recorded — just not here. The convention that emerged in practice is:
> the durable rule lands in `.kiro/steering/09-lessons-learned.md` as `L-0NN` (which is
> always-included steering, so it is read before every change), and the context, the rejected
> alternatives and the verification land in the `docs/DECISIONS.md` entry for the phase.
>
> A `BUG-00N` entry here would be a THIRD copy of the same incident, and three copies of a
> rule is how two of them go stale. So the template above stays for the case it is genuinely
> better at — a one-off incident with a sharp reproduction that taught no transferable rule —
> and anything with a lesson in it goes to L-0NN instead. **Start here when hunting a bug;
> start at L-0NN when about to write code.**
