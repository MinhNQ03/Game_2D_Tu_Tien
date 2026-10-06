# CHANGELOG — Aetheria

All notable changes to this project are recorded here. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/); the project uses
[Semantic Versioning](https://semver.org/) once it ships builds.

Dates are ISO (YYYY-MM-DD).

## [Unreleased]

### 2026-10-06 — A HUD that frames the game, a language for motion, and the reference library put in its place (D-057, D-057A)

Foundation, not a phase: **no gameplay, no networking, no autoload, no presentation framework.
Phase 12 remains NOT STARTED.**

**What the player sees.**

- **The HUD sits in the corners again.** On a desktop with a dock or a taskbar, the whole HUD was
  pushed inward by the OS's own chrome — the left plaques 85px from the window edge, the right
  ones 18px — because the "safe area" a desktop reports is its work area, not a notch. Every edge
  is now one 18px margin; only a phone's notch insets the HUD.
- **The key prompts are quieter.** They sat in the same gold-cornered plaque as the player's
  identity; they now sit on a flat translucent band (36px instead of 68px) that stays legible over
  anything — even pure white. The side panels gained 24px, and the Vietnamese sect panel no longer
  clips its resources line at 1280×720.
- **A kill says so.** A defeated target's plaque used to keep an empty row for two and a half
  seconds; it now reads *Defeated / Đã hạ gục*.
- The permanent HUD went from **16.5% to 14.3%** of a 1280×720 screen, and a test now keeps it
  under 15% and keeps every HUD element out of the middle of the screen.

**Two contracts.**

- `docs/MOTION_DESIGN_CONTRACT.md` (**D-057**) — what good motion and feedback ARE: start from what
  is happening, never from "what animation"; classify, then apply the right governing law;
  anticipation → action → consequence → recovery; presentation never lengthens a gameplay action
  and never writes simulation time (hit-stop holds an image — guarded); a level-up is mid-scale and
  a breakthrough macro; attention hierarchy, causal curiosity, world memory, a deliberation record
  before code and a 20-question self-critique after — and an honest list of presentation debt with
  owners (the level-up's missing character response belongs to P12, where breakthrough becomes its
  second consumer).
- `docs/XIANXIA_IDENTITY_CONTRACT.md` (**D-057A**) — what makes it *Aetheria*: an authority order
  in which canon and the bibles beat any reference; a study workflow that forbids copying; a guide
  to all ten reference folders; identity derived from canon (qi wells up through veins, so it
  always has a source; a realm changes perception; orthodox motion is composed while heterodox
  power costs the body); the generic-fantasy drift gate; and the Aetheria Identity Review.

**The reference library, inspected and put in its place.** The new moodboard pack was being
imported by Godot as game textures; a tracked `docs/.gdignore` now keeps all of `docs/` out of the
engine, guarded by a test. The pack itself turned out to contradict canon eleven ways — including
the conventional realm ladder canon forbids, five-phase elements where Aetheria has four, a fan
weapon and elf-like races — all recorded so Phase 12 cannot copy them into its UI.

**Docs that had drifted:** the Art Bible's animation states, the UI Bible's viewport (1152×648 →
1280×720), two orphaned ROADMAP lines, the presentation contract's "duck-typed", the dependency
matrix's cue transport, and the design-freeze index that did not list the D-056 contracts.

716 tests (up from 704), 0 failures, 0 leaks; every new guard planted against and failing before it
was trusted; captures at vi/en × 1280×720 / 1280×800 opened; real-input playtest 22/22 in all four.

### 2026-10-06 — Production/multiplayer contract, and characters that actually move (D-056)

A foundation hardening milestone **before** Phase 12. No networking, no new gameplay system, no
domain rule changed, and **Phase 12 remains NOT STARTED**.

**Two contracts frozen.**

- `docs/PRODUCTION_ARCHITECTURE_CONTRACT.md` — build topology (client / dedicated server /
  tools), **five independent version domains** instead of one number, the **authoritative
  dedicated-server** target (which resolves the "model undecided" note that had been sitting in
  `MULTIPLAYER_PLAN.md` §6), twelve boundaries each answering the seven ownership questions, the
  command/intent shape, six distinct identities so a reconnect is expressible, the client/server
  responsibility matrix, five vendor-neutral adapter slots, and the deployment topology. Every
  section separates **TARGET** from **CURRENT**, because almost none of it is implemented and
  that is correct.
- `docs/PRESENTATION_ARCHITECTURE_CONTRACT.md` — gameplay decides WHAT, presentation decides
  HOW; three layers (locomotion / action / transient feedback) with action out-ranking
  locomotion; **gameplay timing owns the truth**; reusable semantic actions instead of
  per-character bespoke logic; the cue vocabulary; the art quality bar; and the performance and
  determinism rules.

**A real seam, not a document.** `CharacterVisualComponent` gained a semantic **ACTION layer**
(five methods, one optional `@export` on the visual profile). The trigger seam already existed
— `AttackComponent` has emitted `attack_started`/`attack_finished` and exposed `state()` /
`time_remaining()` / `attack_data()` since Phase 09 — so **no gameplay API was added and no
animation manager was created**. `drive_action(progress)` takes the progress from the lifecycle
that owns it, so the animation cannot run at a different rate from the mechanic it depicts.
**Proven on two actors:** the player (32×48, 6 frames) and the mist wolf (32×32, 4 frames),
same path, no actor branch, with a structural test asserting only one file declares the API.

**The player now visibly strikes.** A palm-thrust action sheet for all four archetypes and a
lunge for the wolf: anticipation → contact → recovery, with the qi orb travelling with the palm
and flaring at full extension. Two art passes were wrong and the second one mattered — at peak
reach the forearm teleported and left a gap to the shoulder, which at 1× read as **a floating
blue blob beside a motionless figure**, exactly the failure the contract exists to prevent.
Fixed by drawing the upper arm.

**Two defects the brief did not name.** `AttackComponent.cancel()` emits nothing and
`Enemy._on_health_died()` calls it, so an action layer waiting on `attack_finished` would
freeze a corpse mid-thrust — the action now ends on the lifecycle's *state*. And the asset
generator's degenerate-art check compares frames *wrapping round*, which would reject a
one-shot sheet that correctly returns to neutral; it gained a non-looping mode.

**Tidier HUD, measured.** `KN 0 / 20` was drawing its descenders across its own rail: a meter
prints its value inside itself, and a `FONT_SIZE_HINT` label **measures 20px** while the XP
meter was 8px and the health gauge 14px. Both meters now stand at the measured height, weight
is retired as a carrier (hue + written value remain), `TOP_PLAQUE_RESERVE` moved 224 → 242, and
a new guard re-measures every meter against the text it holds.

**`docs/design_refs/` classified, not swept:** both packs read as CC0 with licence files
present, one is the upstream source of the already-promoted Kenney ornaments, nothing in the
project references the directory — so the source packs stay local and gitignored and the
promoted subset stays tracked.

697 tests (up from 680), 0 leaks, four capture combinations opened. Continuous Visual
Integration is now a **gate** (`PHASE_EXECUTION_PROTOCOL.md` §7b) with per-phase presentation
seeds in the roadmap and the rule **foundation first, content second**.

The review pass on this work (after CI went green on `e19e795`) found:

- **The player's own swing had no proof on the real path.** The integration suite covered the
  mist wolf only. The world E2E now asserts that the real attack key put the **player's**
  sprite into its action layer and moved it through more than one frame, during the same swing
  that landed the hit. Proven non-vacuous twice: unbinding the attack source fails both
  assertions, freezing the progress at 0 fails the frame-advance one.
- **The action layer read its attack source through `call()` every frame.** Now a typed
  `AttackComponent` reference, like `AttackFeedback`'s: no dynamic dispatch on the hot path, and
  a renamed method fails at parse time. The player's visual node is also **named** now (it was
  the only anonymous one).
- **Every menu button drew a dark box, a sliced-off end and a stretched emblem.** Seen at 3× in
  a real capture: the painted plate was a raw crop with an opaque background and a truncated
  right end-cap, 9-sliced with 44px bands around a ~95px emblem, so a long label ("Tiếng Việt —
  đang dùng") was laid over it. The plate is now **derived** by
  `tools/repair_button_plate.py` (mirrored tip spliced in, background cleared, resampled once
  to exactly `BUTTON_HEIGHT`) and sliced with **measured, asymmetric** bands (68 / 97).
  Three new guards re-measure the shipped plate.
- **The runner never ran `tests/unit/framework/`.** Its exclusion list matched the folder NAME
  `framework` at any depth, so `test_nested_discovery.gd` — the proof that the runner finds
  nested tests and detects failures — had never executed. Exclusions are now full paths.
- **Two lesson numbers were used twice** (`L-038`, `L-039`); renumbered to `L-040` / `L-041`,
  with a guard that fails on a reused or out-of-order lesson number.
- **The UI capture tool failed one run in four** on a cold shader cache (a single check for the
  menu after a fixed wait); it now polls with a bound.

704 tests (697 + 2 plate guards + 3 that had never run + 2 numbering guards), 0 failures, 0
`SCRIPT ERROR:`, 0 leaks.

### 2026-10-06 — Phase-11 final hardening: guarding the property, not its spelling (D-055 follow-up)

Five findings on `ddf2276`, which was green on all ten gates and on CI. No gameplay rule
changed, no new system, no change to the XP/Level model or the D-054 budgets.

- **The XP authority guard was bypassable three ways.** Its allow-lists were BASENAMES, so a
  file named `progression_service.gd` anywhere under `src` inherited the exemption; its XP
  matcher knew `xp = …` and `set_total_xp(` but none of the dynamic routes that also work
  (`call("set_total_xp", …)`, `set("xp", v)`, `set_indexed`, `set_deferred`, `obj["xp"] = v`);
  and its `grant_xp` matcher required the literal `grant_xp(`, so **every dynamic invocation
  passed** — `call("grant_xp", …)` does not contain `grant_xp(`. Now exact repository-relative
  paths and both matchers covering the forms that actually mutate the property, with the dynamic
  patterns restricted to a method-name position so the service's own `push_error` text is not
  read as a call. Planting the two bypasses in real files: the old guard reported
  `678 passed, 0 failed`; the new one catches both and names the full path.
- **The attack-prompt tests could be satisfied by a different row.** They searched the whole
  HUD's label text, and the HUD has five badge+word rows — so a neighbour could satisfy them and
  they stayed green with the attack row's own badge blank. They now read the `AttackPrompt`
  subtree, and a new test asserts exactly one row carries the attack word and it is that row.
  Swapping the attack and menu words leaves the old tests green and makes the new ones say
  `expected AttackPrompt but got MenuPrompt`. All five rows are named now; the badge count moved
  from `>= 2 (interact + menu)` to an exact five.
- **`GAME_FLOW.md` §3.3 still called today's world "traversal only — no story, NPCs, or combat
  yet"** — three phases after combat went live. Rewritten to list what runs and to keep saying
  what does not; story, NPCs, quests and the prologue were NOT promoted to implemented.
- **The HUD docstring still advertised a two-row prompt strip** (`[E] Interact / [Esc] Menu`) and
  claimed no HP bar was shown. Now the real five rows (Attack · Interact · Sect · Politics ·
  Menu) and the real gauges, naming semantic actions rather than physical keys.
- **The playtest reported a hybrid number as setup evidence.** `placed_once_at` was measured
  after the fight, from the frozen placement point to wherever the creature had walked to —
  neither gap, under a name that claimed it was the placement. Now
  `setup{placements=1 initial_gap_px=96} movement{final_gap_px=18} attack{…}`, with `placements`
  part of the pass condition.

680 tests, 0 leaks, four screenshot combinations (vi/en × 1280×720/1280×800) opened and
inspected. Every new guard was proven to fail against the prohibited pattern.

The review pass on this work then found two defects in the fixes themselves:

- **`placements` was a fake counter.** It shipped as a literal `1`, so the `placements == 1`
  pass condition could never fail — the exact "do not fake a counter for the report" trap. Now
  incremented at the write; a planted per-swing reposition reports `placements=4` and fails the
  step.
- **The strengthened matchers compiled a regex per line.** Growing them from one pattern to six
  while compiling inside the function meant ~126,000 `RegEx` compiles per suite run across
  `src`'s 21,000 lines. Now compiled once into a lazy cache. (A test-harness fix, deliberately
  not logged as a game-runtime optimization.)

### 2026-10-05 — Phase-11 close-out hardening: the guards, and the key nobody could find (D-055)

No new gameplay. A close-out pass over Phase 11 that turned three documented claims into
enforced ones, closed one fail-open hole, fixed a player-facing defect the owner found by
playing, and resynchronised four documents that had drifted.

- **The attack had no prompt.** Phase 11 shipped a complete `kill → XP → level → feedback`
  loop in which the HUD advertised `T Sect`, `Y Politics` and `Esc Menu` — and said nothing
  about the one verb that kills creatures and earns every point of XP. The action was bound and
  fully wired; it was simply undiscoverable. **No test could see it**, because every test and
  the whole playtest harness already know the semantic action name and feed it directly — none
  of them asks "how would a player find out?". That is L-029's shape: a pipeline correct end to
  end and unreachable by the person it is for. There is now an attack prompt, leftmost in the
  strip (it is the only verb there that changes the WORLD rather than opening a panel), built
  from the shared `UIPromptRow`, with its glyph resolved through
  `InputService.get_action_display_label` so a rebind moves the prompt instead of lying. A
  structural walk of `src/presentation` now rejects `set_prompt("<literal>"`.
- **`PROMPT_STRIP_RESERVE` was finally measured.** `TOP_PLAQUE_RESERVE` has had a measuring
  test since D-050; the bottom strip never did — L-034's "a named reserve nobody measured",
  still live at the other end of the screen, in the exact phase that adds a fifth prompt to it.
  It is now measured on BOTH axes against the populated strip: height against the reserve the
  side panels and the level-up banner both inset by, and width against half the authored
  viewport, because the strip grows RIGHT from the bottom-left while the announcement is
  bottom-CENTRE and those two would eventually meet.
- **Ownership is enforced, not just described.** `ProgressionRuntime.grant_for_defeat` carried
  a docstring claiming one mutation path was "CHECKABLE rather than aspirational" while nothing
  checked it. Two structural walks of `src/` now do: only the storage boundary
  (`character_state.gd`) and the semantic authority (`progression_service.gd`) may mutate XP,
  and only `progression_runtime.gd` may call `grant_xp` — so "paid once" rests on the ledger
  rather than on every future caller remembering. The guard **caught a defect on its first
  run**: the call matcher flagged the service, because it was matching the `func grant_xp(...)`
  DECLARATION. Fixed the matcher, not the allow-list, and pinned the false positive as a test
  case — widening an allow-list to silence a guard is how a guard stops guarding.
- **An empty `reward_id` now fails closed.** The ledger is keyed by `String(reward_id)`, so an
  empty id was not merely "a reward with no name": it was a key every malformed defeat would
  SHARE. The first would have been paid and would then occupy `""`, after which the ledger would
  answer "already granted" for every later malformed defeat — duplicate-protection reporting on
  a collision instead of on an identity. Rejection happens before the ledger is touched: no XP,
  no `xp_gained`, no `level_changed`, **no entry**, and a well-formed defeat still pays
  afterwards. A NEGATIVE reward is the deliberate opposite — nothing mutates, but the defeat IS
  recorded as settled, because an identified defeat that was rejected is finished whereas an
  unidentified one was never a defeat.
- **The playtest harness now has two modes, and says which is which.** Mode A (the existing
  kill) teleports the player into reach before each swing: reproducible, and worthless as
  evidence about how the game plays — a build where the player moves at 2px/s, or where the HUD
  never names the attack key, passes it unchanged. **Mode B** places the player ONCE at 96px and
  then never repositions them: real `move_*` keys to close, the real `attack` key to swing,
  against the second authored creature while it hunts back, ending by proving the player can
  still move. It records `attack_prompt` / `attack_action` / `attack_display_key` — the resolved
  label, never the literal `J`.
- **Capture wording stopped overclaiming.** `hit-flash caught in shot=true` became
  `hit_flash_state_active_at_capture=true [STATE EVIDENCE]`, and likewise for the celebration.
  Nothing in the tool inspects an image; the old phrasing let a state observation read as pixel
  evidence, which is exactly how a visual gate gets treated as satisfied by a line of text.
- **Documentation resynchronised** (each verified against the file at HEAD, not assumed):
  `ROADMAP.md` said **"Phase 11 is NOT STARTED"** in its global status block while a section
  further down said `✅ IMPLEMENTED`; `GAME_FLOW.md` was dated "through Phase 06" and still said
  **"Combat exists only in the Phase-02 player sandbox"** three phases after combat went live,
  listed `xp_gained` as a COMBAT event (which inverts the dependency and would make combat a
  writer of permanent progression state), and drew `LEVEL UP (XP, cảnh giới / tu luyện)` as one
  box — collapsing the two axes that `PROGRESSION_CULTIVATION_DESIGN.md` §1 forbids collapsing;
  `TEST_PLAN.md` claimed "through Phase 08" and `586 tests`. The GAME_FLOW status block is now
  split explicitly into CURRENT / FUTURE / HISTORICAL, because mixing them is how it came to
  describe a sandbox that had been superseded.
- Suite **664 → 678** (+14), zero new failures. All three E2E processes pass; no `SCRIPT ERROR`,
  zero leaked ObjectDB/resources. The two wall-clock performance budgets remain environmental
  debt (D-054) and were deliberately **not** touched: loosening another phase's gate to make
  this run green would hide a real regression later.

### 2026-10-05 — Phase 11: the progression loop closes (D-054)
A kill now pays. `enemy defeat → XP → level → player feedback → keep playing` is wired end to
end and proven in the real app by real attack keys.
- **The level is DERIVED, not stored.** `CharacterState.xp` holds cumulative lifetime XP and is
  the ONLY stored progression number; `ProgressionService.level_of()` derives the level from it
  and the authored curve. A commit therefore writes ONE integer — atomicity is free rather than
  arranged — and a stored level can never end up contradicting stored XP in a save file (the
  D-015 duplication defect, avoided by construction; L-032's preference applied). Retuning the
  curve re-levels every character from their existing XP, with nothing to migrate.
- **One authority.** `ProgressionService` is the only **semantic progression mutation
  authority** — the only thing that DECIDES a new XP total, from the authored curve.
  `CharacterState.set_total_xp()` is the storage boundary that enforces the `xp >= 0` invariant
  next to the field it constrains; it is not an independent gameplay mutation path, and since
  D-055 a structural walk of `src/` fails if any other production file mutates XP. (This bullet
  originally read "the only function in the repository that writes XP", which was an overclaim:
  two functions write the field, and they do different jobs.)
  Combat ANNOUNCES (`enemy_defeated(reward_id, xp_reward)`) and does not pay: it
  holds no progression state, does not know a level exists, and never touches the player's
  `CharacterState`.
- **`ProgressionRuntime` is the seventh `Main/Systems` sibling** — a node, not an autoload (the
  budget stays at five). Registered LAST, so it is torn down FIRST and stops listening before
  its emitter and the state it grants into are freed. Verified in the real app: the observed
  teardown is `Progression → Combat → WorldSim → Faction → Sect → Relationship → World →
  GameState`.
- **The curve is content.** `ProgressionCurveData` authors incremental per-level costs; the
  maximum level is a DATA fact (`min_level + steps`), never a code constant, so extending the
  range is appending array entries. Boundary validation rejects an empty id, a non-positive
  step, a DECREASING curve (a plateau is legal) and a `min_level` below 1 — and reports every
  problem at once.
- **At the ceiling a grant is REJECTED** with a named reason rather than accumulating toward a
  level that cannot arrive, and the meter reads COMPLETE instead of `0 / 0`.
- **Multi-level gain emits ONE `level_changed`.** A grant crossing three thresholds reports
  `(1, 4)` once — the intermediate levels were never states the character was in, so a listener
  must not be able to observe them.
- **Idempotency** is keyed on a per-SPAWN reward id (`instance_id#serial`, deterministic in
  table order). Keyed on the table row alone it would have silently become a "has ever been
  killed" flag and a re-cleared field would have paid nothing — an integration test covers
  exactly that.
- **The UI**: a gold `Cấp N` badge beside the character's name and a thinner gold XP meter under
  the jade health gauge. XP is separated from HP on three independent channels — hue, weight and
  written text — because they sit one above the other in the same plaque and colour may never
  be the only carrier of meaning. `TOP_PLAQUE_RESERVE` re-derived 212 → **224** by the existing
  measuring test.
- **Vocabulary**: `Cấp / Kinh nghiệm (KN) / Thăng cấp` — never *tu vi*, *đột phá* or *cảnh
  giới*. Level is not cultivation, and the fastest way to break that rule in practice is for
  the UI to call a level-up a breakthrough. A test asserts the reserved words stay out, in both
  languages.
- **The level-up celebration** is an explicit clock with a public `advance(delta)`, not a
  `Tween` (a tween cannot be stepped headless), `_process` off when idle, cancellable, and it
  owns its transient banner so every part of the effect starts and stops in one place.
- **A visual defect found by looking at a capture, not by a test:** the banner was anchored to
  the exact screen centre — which is where the camera keeps the player — so it printed straight
  across the character's body. Nudging it up from the centre did NOT fix it, and that is the
  part worth remembering: `MapBase` clamps the camera to the map limits, so near an edge the
  player is not at the centre and not a fixed distance from it. The banner is now bottom-centre,
  inset by `PROMPT_STRIP_RESERVE + SPACE_LG`, which makes "cannot collide" arithmetic rather
  than a hope. Recorded as **L-038**.
- **Evidence.** Suite **586 → 664** tests; all three E2E processes pass, including a new
  `_prove_progression` in the world E2E that asserts the authority moved, the level derived from
  it agrees, and the HUD shows the row — after a kill driven entirely by real attack keys, with
  no `grant_xp`/`set_total_xp` shortcut anywhere in the E2E. The real-app playtest run reports
  18/18 steps, `xp 0 → 25 (level 1 → 2)`, the celebration ACTIVE at the capture boundary (a
  state observation — D-055 corrected this wording, which used to claim the effect was "caught
  in the screenshot" and so implied pixel evidence the tool never gathers), and a clean HUD
  afterwards.
- **Pre-existing technical debt recorded, not changed:** the two wall-clock performance budgets
  (`test_ai_budget`, `test_combat_budget`) fail on this development machine and pass on CI; the
  numbers swing 2–3× between runs on the same code. Loosening another phase's gate to make this
  phase's run green would hide a real regression later — see D-054 for the options.

### 2026-10-05 — Phase-10 review pass: you can now see yourself being hit (D-053)

Four defects the review pass found on a commit that was already green on all ten gates and on
CI. Two of them were found by opening the playtest captures the commit itself had produced —
generating the evidence is not reviewing it.

- **`DamageFeedback`, the pair to `AttackFeedback`.** Combat had feedback for the swing you
  MAKE and none for the hit you TAKE: your health number dropped with no mark on your
  character, and your own swing landed with no confirmation on the creature. Now a short
  decaying tint marks whatever was damaged — crimson normally, brighter gold on a crit, reading
  the `is_critical` flag `HurtboxComponent.damaged` had been carrying unread for a phase. The
  tints BRIGHTEN rather than only darken, because `modulate` is a multiply and a darkening-only
  tint is invisible on a dark creature.
- **One owner for `modulate`.** `Enemy._on_health_died()` used to set a `Color(...)` literal on
  itself: a gameplay entity authoring a presentation decision, a colour no palette edit could
  reach, and a second writer of a property the flash also wrote. The entity now only reports
  that it died; the presentation node decides what dead looks like. A test WALKS
  `src/gameplay` and fails if any file there authors a colour.
- **The corpse is visible again** — after three tries, which is the part worth remembering. The
  shipped tint and the first correction both put the corpse within 0.014 luminance of the
  floor, so a kill read as a despawn; the first correction only *looked* better because it was
  blue against green, meaning the entire signal rested on hue. The second correction passed
  against the floor's MEAN and failed at 0.082 as soon as the test measured per fill tile, on
  the pale player over the dimmest moss. A corpse now sits at least 0.12 of luminance below
  EVERY floor tile and stays blue-shifted, and the test re-measures it from the PNGs.
- **The target plaque retires.** It was documented as showing a kill "briefly" while nothing
  implemented a timeout, so it sat on `0 / 34` until the next fight. A cancellable one-shot
  timer retires it after `TARGET_PLAQUE_LINGER`; a live target cancels it, so a second creature
  keeps the panel up.
- **The playtest says what its screenshot caught.** A 0.16s flash is not evidenced by a frame
  grabbed at an arbitrary moment — on a frame-starved run the file named `08_attack` showed an
  untouched target. The report now carries `hit-flash caught in shot=true|false`, and it is
  deliberately not a pass condition.

586 tests (up from 572), 0 leaks. Every new guard was verified to fail against the pre-fix code.

### 2026-10-05 — Phase 10: deterministic data-driven enemy AI (D-052)

The field has something in it. A player walks out of the hub, meets a **Vụ Lang** (frontier
mist wolf), is noticed, chased, bitten, and can kill it — and the corpse stops being an actor.

- **`AiBrain` is pure domain**: scalars in, an INTENT out, never a vector. That makes "at 300px
  it gives up" an assertion rather than a scene, and makes AI the mirror of player input
  (`DECISION → INTENT → resolution`), which is what lets a server own it later.
- **Seven states, each earned**: IDLE · PATROL · **ALERT** (the telegraph — a pause the player
  can see) · CHASE · ATTACK · **RECOVER** (disengage and re-close, which punishes standing
  still) · RETURN. The leash outranks a visible target, and re-acquisition only happens once
  back inside it — otherwise a player can walk one creature across the map or pin it in a
  turn-around at the boundary.
- **No seventh Systems node and no per-enemy frame callback.** `CombatRuntime` spawns, ticks
  and despawns; ONE session callback drives every brain, asserted structurally as well as by
  timing, so the cost of N creatures is one measurable number. An enemy-free map stops ticking.
- **A second creature is a `.tres` + a spawn-table row.** No `if enemy_id == ...`; one
  `enemy.tscn` configured entirely by `EnemyData`, with `AiProfileData` separate so a
  behaviour archetype is shareable. Neither carries a `behaviour_type` enum.
- **Enemies have no `CharacterState`** — a beast has no realm, sect or memory, and wildlife
  does not belong in the world simulation's cast. Recorded so the next creature that DOES need
  remembering knows nothing is in its way.
- **PERF-003, found by the new budget test**: zeroing the decision accumulator discarded the
  overshoot and the cadence silently ran 8% slow (138 decisions where 150 were expected,
  because 12 frames at 60fps sum to 0.19999999999999998). The same test's long-frame sibling
  caught a second bug — the brain was advanced by the NOMINAL interval, so under 5-second
  frames its clock ran slower than the world and a creature could sit in one state
  indefinitely. 40 creatures × 1800 frames = 289 ms, 4.0 µs per enemy per frame, 10.3× scaling
  for a 10× cast.
- **The Phase-09 presentation debt is PAID** (D-051 §10b). `AttackFeedback` draws one arc
  whose radius, width and alpha distinguish WINDUP / ACTIVE / RECOVERY — no particles, no
  shader, every colour from `UIPalette`, nothing when idle. A capture confirms the swing is
  visible where before there was only a number changing.
- **A target plaque** on the D-050 seams shows the creature's name, threat rating and health.
  No level, mana or realm — nothing owns those yet. Published on engagement AND damage:
  publishing on damage alone meant the player watched a wolf close in with an empty plaque,
  which a capture caught.
- 572 tests (+35), 0 leaks. The world E2E now kills a real creature with real attack keys and
  asserts the corpse is untargetable, immobile and harmless; the playtest harness runs 14 steps
  including the whole encounter.

### 2026-10-05 — Phase 09: real-time action combat (D-007 resolved)

**D-007 is resolved as (a) REAL-TIME TOP-DOWN ACTION COMBAT**, after being Open since Phase 0.
The reasoning is in `DECISIONS.md`; in short, a top-down camera exists to present SPACE and
TIMING, and a turn-based model throws away the information the camera is there to show.

- **The attack lifecycle is a pure domain class.** `AttackStateMachine` runs
  `READY → WINDUP → ACTIVE → RECOVERY → READY` with no node dependency, so every frame-timing
  question is answered by an assertion with exact deltas instead of by watching the game. Two
  properties are guarded because both are expensive defect classes in an action model: a long
  frame passes THROUGH the hit window rather than over it (a 10-second delta still delivers the
  hit), and the window is an EDGE consumed once per swing (polling the ACTIVE state would make
  frame rate into damage).
- **Timing is CONTENT.** `AttackData` (`data/combat/attack_player_basic.tres`) authors
  windup/active/recovery, reach, arc, power and crit, so a new attack is a `.tres`.
- **Hit detection is ANALYTIC, not physics.** `CombatService` compares reach and arc against a
  session `CombatHurtboxRegistry` (in `src/gameplay/` — its API is typed on a `Node`, so
  domain would have been the wrong layer; the rules themselves stay node-free and therefore
  headless-testable); there are deliberately NO hitbox/hurtbox collision layers.
  In the headless runner an Area2D overlap does not fire reliably (L-016/L-017), so a combat
  system detecting hits that way could not be tested end to end — and the trade (a target is a
  point plus a radius) is invisible on a 16px grid. The reasoning is recorded in
  `collision_layers.gd` where the bits would have gone.
- **The damage formula stayed in one place.** `DamageRules.compute_hit()` gained
  `power_multiplier` and `critical_multiplier` as DEFAULTED parameters — the existing two-arg
  behaviour is unchanged and asserted to be — rather than letting combat multiply scalars
  itself. The service decides whether a hit crits; the formula decides how much.
- **`RngService.STREAM_COMBAT`** is the second named stream, added the day it had a consumer.
  One world seed, two independent streams: a combat roll cannot shift the simulation's
  sequence, and the test proves a filtered-out target consumes NO draw — so where the player
  stands cannot change the dice.
- **`CombatRuntime` is the sixth per-session node under `Main/Systems`**, last in
  `SESSION_START_ORDER` and therefore first in teardown, where it cancels swings in flight
  before the entities they would resolve against are freed. No new autoload (budget still 5).
- **The hub map has a real target.** A `TrainingDummy` is authored into it, because a combat
  system with nothing in the shipped world to hit is a no-op with documentation (L-029).
- **The first gauge in the game.** The HUD shows player health via `UITheme.vitals_gauge()` —
  the D-050 foundation's fifth shared seam, not ad-hoc combat styling — hidden until a real
  value arrives, and it writes the number as text as well as drawing a bar.
- **PERF-002:** the budget test found that every candidate was fully type-validated before
  being rejected by distance. Geometry now runs first: a swing against 400 entities went
  1005 ms → 334 ms for 2000 swings. The entry also records that the test's own first scaling
  claim was wrong, and why the corrected one is a better guard.
- 536 tests (+16 from Phase 08's 520), zero leaks. The world E2E now drives a REAL attack key
  through InputService → player → component → state machine → service → the target's health
  and asserts the target lost HP — the end state, not that a signal fired.

### 2026-10-05 — UI production foundation (D-050)

Presentation only — no gameplay rule, domain state, input semantic, autoload or networking
change.

Every defect below was found by **looking at screenshots of the running game**, not by a test.
A capture harness (`tools/capture_ui.gd`) now boots the real app in a real window and writes
the actual viewport for eight UI states, in both languages, at two aspect ratios.

- **Four shared seams, one factory each, in `UITheme`** — `ornament_divider()`,
  `build_backdrop()`, `menu_button(role)`, `scroll_body()`. Each has a structural guard that
  WALKS `src/presentation` instead of listing files; the first version listed two files and
  passed while two other screens still had the defect it existed to catch. The duplication's
  consequences were all visible on screen: four hand-rolled dividers at three heights, a
  settings screen that was a plaque on a flat void with three untinted buttons, and a
  scrollbar drawn over the value column in BOTH side panels.
- **`TOP_PLAQUE_RESERVE` 104 → 198, measured.** The side panels covered both top plaques. The
  value is now derived from the plaques (identity 180, map 154) and re-measured by a test that
  fills them through the HUD's public setters — a **bare** HUD measures ~25px short, because a
  hidden child contributes nothing to a container's minimum size. The world-event hint is
  capped at two lines with ellipsis, so the plaque has a maximum height at all.
- **The painted backdrop is cropped past its measured 21-column flat dead margin**, which
  `KEEP_ASPECT_COVERED` had been scaling into an ~87px bar of near-black down the left of the
  menu. A test re-derives the margin from the pixels, so a re-export fails loudly.
- **The HUD portrait is visible.** `portrait_frame.png` was measured at centre brightness 229
  in D-034 — an opaque light panel — and was nine-patched OVER the portrait, painting a cream
  plate across the face for two phases. It now uses the hollow `frame_ornate.png`.
- **Localization:** the `en` subtitle said *"A tu tiên journey"*; the active language in
  Settings was marked `> English <` (untranslatable ASCII, and the only carrier of the state)
  and is now a localized template plus the PRIMARY button role.
- **The capture harness refuses to lie:** it verifies the active language against
  `Localization` (every `vi_*.png` in the first run was in English, because boot applies the
  SAVED language) and writes no file for a panel that did not open. Exits non-zero either way.
- **Retired** `UIPalette.TEX_TITLE_DIVIDER`; `UI_TEXTURES` is 14 entries and now means every
  RUNTIME texture. `docs/ASSET_LICENSES.md` U10 is marked UNWIRED.
- Recorded as **L-034** in steering and **D-050** in `DECISIONS.md`, including what was
  deliberately NOT changed (the measured-dark painted button family stays).

### 2026-10-05 — Phase-08 documentation close-out (D-049)

Documentation only — no gameplay, scene, resource, UI-runtime, autoload or networking change.

- **`PERFORMANCE.md` had a Phase-03 status block** claiming no benchmark existed and the
  optimization log was empty on purpose. Both had been false since Phase 08: PERF-001 exists
  with before/after numbers, and the budget test runs in the suite on every CI job.
- **`TEST_PLAN.md` claimed `ran 282 test(s)` "through Phase 06"** — three phases and 195 tests
  out of date, and silent about the whole social/world substrate. Now `477`, quoted from the
  runner's own tally, with the zero-leak condition stated.
- **`DEBUGGING.md` said "no gameplay bugs yet" and "No entries yet"**, false since Phase 03.
- **The fix is structural, not a date bump:** every document that carries a status now has an
  explicit `CURRENT STATUS` heading and an explicit `HISTORICAL NOTES` heading, and the
  historical notes are **not rewritten** — they carry a standing disclaimer instead. Editing
  the old notes to match today would have destroyed the record of *why* the code is shaped as
  it is (the Phase-01 "no `_process` on the autoloads" discipline is still live) in order to
  fix a date.
- **The FAR band is now documented as CONTENT SCOPE, not a limitation** (`WORLD_SIMULATION.md`
  §2b): the implementation supports all three bands and FAR is the *default* branch; the
  shipped world cannot produce one because it has two adjacent maps; the unit tests cover all
  three against a three-map graph; **a third map must not be authored merely to make a band
  reachable.** With a forward commitment to author a meaningful FAR actor when a third
  non-adjacent map lands.
- **`DEBUGGING.md` §7 stays empty on purpose and now explains why:** incidents live as `L-0NN`
  in always-included steering plus the phase's `DECISIONS.md` entry. A third copy of a rule is
  how two of them go stale.
- Verified by a scripted audit rather than by reading. Three initial hits were **false
  positives in the audit's own regex** (passages correctly describing the historical defect,
  and the row that correctly says Knowledge is "NOT Story/Quest") — preserved, and recorded,
  because an unchecked audit manufactures work.
- **Phase 09 remains NOT STARTED**; no Phase-09 content was introduced.

### 2026-10-05 — Phase 08: the world evolves on its own, deterministically (D-048)

The world now moves while the player is elsewhere, and it moves the same way every time from
the same seed. **No new autoload** (budget still 5), no networking, no per-frame cost.

- **The deterministic RNG seam lands** (the shape D-040/C-010 froze; Phase 08 is its first real
  consumer). One world seed fans out into named streams via `RngService`/`RngStream`.
  **Stream isolation is a property of construction, not of discipline** — each stream's start is
  derived by folding its id through the mixer, so 1000 draws on the world stream move another
  stream by exactly zero values, which is asserted. The seed comes from the RUN (hashed
  `run_id`), never from the clock.
- **Our own 32-bit mixer rather than `RandomNumberGenerator`**, for one reason: the generator's
  state is part of the SAVE FORMAT, and an engine-internal state blob would tie a player's world
  to an implementation detail we cannot migrate. Weyl counter + `lowbias32`; everything masked
  to 32 bits so nothing overflows and `>>` never touches a negative value. `next_below` uses
  multiply-shift, not `%`, so modulo bias is not baked into every seeded world forever.
- **A world clock that is advanced EXPLICITLY.** No `_process`, no `_physics_process`, no
  `Timer`, no wall-clock read anywhere in the subsystem — and a test reads the SOURCE to keep it
  that way, because the cheapest way to betray this design is a `_process` that "just"
  accumulates delta. Time passes on gameplay beats (session start, arriving in a map) at authored
  tick costs. The calendar is data; the date is derived from one stored integer.
- **LOD: Near / Mid / Far, from the real map graph.** The band is derived from the player's
  position (own map → NEAR, one exit away → MID, else FAR), never authored.
- **The one decision everything else rests on: an actor's activity is DERIVED**, a pure function
  of `(tick − joined_tick, schedule)`, not stepped per tick. Stepping looks equivalent and is
  not — it would make state depend on how often an actor was stepped, and not stepping FAR
  actors is the whole saving. So FAR and NEAR compute the same answer, and a test asserts a FAR
  actor is never behind an observed one on the same routine.
- **Background characters are not nodes, in any band.** 200 actors × 300 ticks creates ZERO
  nodes, and the real application reports zero children after 20 map transitions.
- **Events mutate through the OWNING service** — `SectService.adjust_influence`,
  `FactionService.adjust_influence`, `RelationshipService.apply_delta`. The tests prove it by
  observing what only the owner does: the value stops at the owner's ceiling, and the
  relationship service wrote bounded history the simulation does not implement. **All edge
  creation happens at preparation time**, never inside a tick, and a missing owner service is a
  start failure rather than a skipped step (D-047's rule, one phase on).
- **Save-resumable, and asserted as such:** `save → load → advance K` produces the identical
  world to `advance K` on a run that never stopped. That needs four things a seed alone does not
  carry — stream positions, the pending queue, the carry-over debt, each actor's `joined_tick`.
  A pending event due at or before the restored tick is REFUSED rather than fired late or
  dropped.
- **Catch-up is bounded and loses nothing.** Overflow becomes carry-over debt drained on later
  calls, and `a + b` ticks are asserted to produce the identical world to `a+b` at once.
- **`CharacterRegistry` arrives** (the piece `CHARACTER_SYSTEM.md` §10 listed as missing), owned
  by `WorldRuntime`. It also fixed something: `Main` had been satisfying the sect and faction
  resolver seam with two closures that each knew about exactly one character — fine while the
  player was the only one, wrong the moment the world gained a cast.
- **`CharacterState.sim_state` is a derived cache** of the simulation's record, with the same
  `verify`/`sync` discipline `SectService` applies to `sect_id` (D-015). Drift is reported.
- **Content is data:** 3 routines, 3 actors (an elder, an inner disciple, a frontier scout, each
  enrolled into Thanh Vân Tông and a faction through the owning services) and 4 recurring events,
  all localized vi + en. Adding a person to the living world is a `.tres` plus a catalog line.
- **UI:** two muted lines under the HUD place name — the world date and what kind of thing last
  moved, in which direction. Not the subject's name: that needs an id→key lookup no phase can
  do yet, and printing a raw id is forbidden. No band counts or stream positions (B18).
- **PERF-001, the first entry in the optimization log** — and it exists because the budget test
  was written before the code was called done, and failed. The per-tick loop was deriving its
  observed set by sorting the WHOLE cast: `O(cast · log cast)` per tick, the exact cost LOD
  exists to remove, inside the code implementing LOD. A 10× FAR population cost 3.57× more per
  tick. An incremental index fixed it: **50 ms → 12 ms** for 200 actors × 300 ticks, scaling
  factor **3.57× → 1.0×**.
- **Fixed: the test runner hung forever on an unloadable test file.** A parse-error script still
  `load()`s as a non-null `GDScript`; calling `new()` on it is a VM error that aborts `_run`, so
  `quit()` was never reached and the process hung until the job timed out. One mistyped line cost
  a 15-minute timeout. The runner now checks `can_instantiate()` and fails in seconds, naming
  the file.
- **471 tests passed / 0 failed**, 0 leaks at exit, all 10 gates green. Every new guard was
  proven able to fail — the E2E's five world-simulation assertions all failed when the arrival
  beat was disconnected.
- **Honest limits:** the shipped two-map world has no FAR actors (hub and field are adjacent, so
  FAR arrives with the third map; all three bands are covered by unit tests); nothing renders the
  cast yet (NPC presentation is P-17); and the HUD lines have not been seen on screen.

### 2026-10-05 — Phase-07 hardening: a reversed teardown and a fail-OPEN politics mirror (D-047)

Two lifecycle/invariant holes that a green CI could not see, plus a leak it was exiting 0 on.
No new gameplay, no new scope, no new autoload, **still 10 CI gates**.

- **The normal return-to-menu tore the session down in the WRONG order.** New Game starts
  World → Relationship → Sect → Faction (dependency order); `_unwind_failed_session()` reversed
  it correctly, but `_on_return_to_menu()` was a SECOND hand-written sequence that had drifted —
  it ended **World and Relationship first**, freeing the player's `CharacterState` and dropping
  the relationship graph while the sect and faction sessions, whose state is defined in terms of
  both, were still unwinding through them. Its own comment two lines above claimed the opposite.
- **Fixed by removing the duplication, not by correcting it.** `Main.SESSION_START_ORDER` is now
  the single source of truth; `_end_session_stack()` walks it backwards then ends the `GameState`
  session (**Faction → Sect → Relationship → World → GameState**), and both entry points
  delegate to it and sequence nothing themselves. `_session_node()` resolves a name with an
  explicit `match`, so a name Main owns no node for reports loudly instead of being a silent
  no-op step.
- **The order is now OBSERVABLE:** `Main.get_last_teardown_order()` returns what the last
  teardown actually ended, in order. An invariant nothing can read back is only a comment — which
  is how this survived three phases, since "all four sessions are down afterwards" is true for
  any order.
- **`FactionService` politics mutation was fail-OPEN.** `add_alliance()`/`add_rivalry()` guarded
  the mirror with `if _relationship != null`, and `_ensure_edge()` opened with
  `if _relationship == null: return true` — so with no graph installed the mirror was skipped and
  the call **returned true**, recording a declared rivalry that no edge backed (breaking the
  frozen D-042 invariant). It was unrecoverable, not just wrong: `clear_politics()` fails closed
  on exactly that state, so the pair was stuck declared for the rest of the run.
  `apply_default_politics()` had been hardened against this in D-038; the MUTATION path was the
  door left open.
- **The identical two lines sat in `SectService._set_diplomacy()`** and are fixed the same way —
  found by looking for the defect's siblings rather than only its reported instance. Both
  services now check the graph as a PRECONDITION (before any other rule) and both `_ensure_edge`
  implementations FAIL on a null service instead of returning `true`: that `return true` *was*
  the mechanism, and leaving it would let a future caller reopen the hole.
- **The legitimate no-graph landscape is unchanged and now pinned:** a mirror-less service still
  does registration, cross-store validation, membership, leadership, influence, resources, the
  derived rules and the character cache. The fix is a precondition on the mutation, not a new
  hard dependency.
- **The suite had been LEAKING with CI green** — `17 ObjectDB instances were leaked` /
  `8 resources still in use` at shutdown, printed after the runner already exited 0. Root cause:
  a **`RefCounted` reference CYCLE** in the faction fixture (a resolver lambda capturing `self`,
  stored as a `Callable` on a service the test instance kept on a field). GDScript
  reference-counts; it does not collect cycles. An `after_each()` clears the `Callable` and the
  suite now exits with **0 leaks**, and the existing headless gate FAILS on those two lines
  exactly as it already does on `SCRIPT ERROR:`.
- **Tests:** `tests/unit/bootstrap/test_session_lifecycle.gd` (new — the order constant, its
  reversal, every ordered name being a real endable subsystem, and the structural guard that
  exactly ONE function in the bootstrap issues `call("end_session")`); the real teardown trace
  asserted in `tests/e2e/world_flow_case.gd`, which also now covers `FactionRuntime`; faction
  tests 41-43 and sect test 53 for the fail-closed mutation. **Every new guard was proven able
  to FAIL** by temporarily restoring the pre-fix code — the E2E printed the real reversed trace
  `[World, Relationship, Sect, Faction, GameState]`.
- **Process: D-009 is no longer true.** Godot 4.7-stable runs headless on this machine, so the
  whole gate set runs locally in ~3 minutes instead of costing a CI round-trip per question
  (L-031). CI remains the authority; on-screen results are still unverifiable without a
  screenshot. `ran 392 test(s): 392 passed, 0 failed`.

### 2026-10-02 — The character actually animates: 32×48 four-direction cultivator (D-046)
The owner asked why the character was still proto art after everything else got real graphics.
Reading the pipeline corrected **two of my own earlier claims**, and found the real defect.
- **The sheet carried ONE frame per direction and all four profiles left `walk_sheet` null**, so
  the character slid across the floor without ever animating. That — not the pixel count — is
  what read as lifeless, and no gate could see it: the profiles were valid, the component
  rendered, 378 tests were green.
- **Correction 1:** I had said `player.tscn` ignores the 4-direction art. Half wrong —
  `player_default.tres` sets `sprite_set_ref` and `WorldRuntime` applies it, so a real run was
  already using the directional sheet; the static `Sprite2D` is only the harness fallback.
- **Correction 2:** I had promised to import `xf_hero_swordsman_{idle,walk}`. **Measuring killed
  that plan.** The Xianxia `terrain/` is `platform_top` + `slope26/45/63_up/down`, the animation
  set is `jump`/`fall`/`dash`/`block`, and a direction-token scan across **all nine** supplied
  folders returned **zero** hits — it is a side-scrolling platformer pack. Frames are **111×81**
  (not the 79×78 I had recorded) with per-animation height changes (81 vs 86). It would have put
  a side-view, ~7-tile-wide figure into a top-down 16px game. **No top-down character exists in
  any of the nine folders.**
- **Sheet layout is now a GRID:** one row per direction × N animation columns, with the frame
  count **derived from the texture width** rather than authored twice (L-014). Idle and walk may
  differ (4-frame breath, 6-frame stride).
- **Baseline 16×24 → 32×48**, exactly 2× so the 16px grid math and integer scaling are unchanged
  (2 tiles wide, 3 tall). Reason: the measured signature of the reference art is waist-length
  white hair + a pale layered floor-length robe + a saturated qi orb, and none of those three
  survive a 6px-wide torso.
- **Palette sampled from the owner's two painted references, not invented** (L-021): male orb
  `51,153,240` / hair `208,192,192` / robe `192,192,208`→`80,96,128`; female orb `145,92,234` /
  hair `240,224,224` / robe `160,160,224`→`96,96,160`. One documented departure: the male
  reference's hair tone is nearly the same VALUE as its skin, so it became the hairline shadow
  (`hair_dk`) and the lit hair is a cooler silver — pixel art needs value separation a painted
  render gets from line work.
- **Animation clock in `CharacterVisualComponent`** at the profile's `frame_duration` (elder
  shuffles at 0.26s, player strides at 0.14s — data, not code). `_process` switches **off** for
  a single-frame sheet. `advance(delta)` is public so tests drive it deterministically.
  Switching idle↔walk resets the column, or a 6-frame index would overrun the 4-frame sheet.
- **A ragged sheet width is rejected, not floored** — `frame_count_of` returns 0 and the error
  names the reason, instead of rendering half a character.
- **The outline is traced from the pixels**, so it stays correct for every pose; the orb halo is
  drawn after the pass (which only considers fully-opaque neighbours) so a glow is never outlined.
- **`player.tscn` now agrees with the component:** feet-anchored fallback sprite and the
  collision footprint moved to the feet (18×12 at y=−6) instead of a 24×24 box straddling a
  feet-origin, which had put half the collision underground. A test pins that both visual paths
  place the feet at the same point.
- **Camera deliberately unchanged** — the derived zoom already satisfies both constraints
  (L-022: do not fiddle a camera value without evidence).
- **NOT done, with a reason:** the 30 CC0 `xf_npc_*` portraits are usable and cleared, but
  nothing renders a portrait yet; 30 textures with no consumer is what L-005 forbids.
- Art iterated **twice** after inspecting the sheets at 8× magnification: the first pass drew
  skin over the hair on every UP frame (a bare face on the character's back) and had walk deltas
  too small to tell from idle.

### 2026-10-02 — The map floor is real art now: Verdant East Asian 16px tileset (D-045)
The owner's complaint was that only the menu got real art while the **map, scenery and layout**
stayed placeholder. That was correct, and my previous claim that "the pack cannot fix the map"
was wrong — it was based on reading **one** of the **nine** asset folders supplied. The others
included a 16px tileset built for exactly this grid.
- **Researched all nine folders and recorded a licence verdict for each.** Imported: **Verdant
  00 — Series Sampler** (© Core Systems Asset Factory) — *free, commercial use permitted, no
  attribution required, may not be resold as an asset pack*; its `LICENSE.txt` is committed
  next to the art. **Rejected on provenance:** `vectoraith_..._DEMO` (16px Chinese-medieval
  buildings — a genuinely good fit, but **no licence file** and "DEMO" in the name),
  `ufefftiles_v2` and `Ancient Chinese Characters Pack 1` (**no licence file**).
  `06-art-assets.md` forbids importing an asset with unclear terms.
- **The floor was 3 tiles.** One grass, one path, one wall, stamped flat with a single straight
  stripe — a whole map drawn from one repeated tile is what read as bare, and no UI work could
  fix it because the floor is most of the screen. It is now the **East Asian Village** set:
  4 moss (`koke`) fills, 4 flooded rice-paddy (`ta`) fills, and a real paddy-on-moss autotile.
- **Terraced paddies with drawn bunds**, not a hard rectangular cut: blocks either side of a
  clear moss walkway the player can always travel, edged by the autotile's **16 cardinal masks**
  wired from coordinates read out of the pack's own `tiles.json` (not eyeballed). The remaining
  31 masks of the 47-mask set encode diagonal neighbours and stay unwired — placing them wrong
  is visible and cannot be verified here (D-009). The 16 cardinal tiles are a complete subset
  for a rectangular block.
- **CORRECTION, same day (`9ba1fdd`):** this first shipped describing `ta` as "cut stone" and
  laid it out as a stone courtyard, which rendered **a cross of open water through the village**.
  `ta` is **田, a flooded rice paddy** — measured `rgb(43,100,109)`, and the pack's readme says
  "Shrine, **Rice Paddies** & Village Houses". I read the material NAME and inferred stone
  instead of sampling the pixels. **L-021 failed in a new way:** the asset's SLOTS were measured
  correctly from `tiles.json` and its COLOUR never was — slot geometry and material identity are
  two separate facts and both must be sampled. The owner's screenshot caught it in one look,
  which is the argument for screenshots over test counts: 377 green tests cannot see a blue tile.
  Real cut stone exists in the same pack and is now measured — `v23_ground`,
  `rgb(155,143,123)`–`rgb(194,180,156)`, the "Mosaic Plaza" set — for a later courtyard pass.
- **Tile variety is DETERMINISTIC** — a per-cell integer hash, never `rand*()`, so the map
  paints identically every run (D-040 keeps the seeded RNG seam in Phase 08). The two odd
  multipliers decorrelate x from y so variants do not fall into visible diagonal stripes.
- **Generated the `.import` siblings by hand** rather than shipping half-added assets: the
  editor had not re-scanned, and L-015 requires a texture's companions to be committed with it.
  Both derivable values were derived, not guessed — the cache path's MD5 is of the resource-path
  string, and the UID uses the base-34 encoding verified in L-027.
- **Still placeholder, stated plainly:** the **player sprite** is unchanged. None of the
  licence-clean packs contains a 16×24 four-direction tu-tiên character; the Aetheria portraits
  are 310×560 illustrations with baked backgrounds. That needs authored art at the right spec,
  and no amount of importing fixes it.
- **Still not seen on screen:** Godot is not runnable here (D-009).

### 2026-10-02 — Real painted UI art, and the button legibility violation fixed (D-044)
The owner's verdict on the build was that the UI looked cheap. D-043 fixed the structural causes;
this fixes the **surfaces**. The Aetheria asset pack was confirmed by the owner as
**self-generated → project-owned**, which cleared the provenance block (`06-art-assets.md`).
- **The buttons were breaking this project's own measured rule.** `SURFACE_LIGHT_BRIGHTNESS_LIMIT`
  is **120**; `button_normal.png` measures **202** and `button_hover.png` **217**. The buttons
  have carried light text on a too-light plate since D-028, with only the text outline holding
  legibility together — D-034 found exactly this for panels, fixed it there, and **left the
  buttons out**. That, plus red silk art against an agreed jade direction, is what read as
  "plastic". The painted plate measures **29**. Tests now pin the asset path for all five states
  and pin that no per-state tint can multiply 29 back over 120.
- **A second, deliberately separate asset tier** (`assets/ui/aetheria/`): painted, **not** pixel
  art, so drawn with **LINEAR** filtering and non-integer stretching is fine — the
  nearest/integer-scale rule exists to protect a pixel grid and these have none. Pixel-art
  world/sprite/panel rules untouched; this tier is UI-only with its own folder and constants.
- **One plate, five states.** Differentiated by modulation rather than five painted files, which
  would have to stay in sync through every future art pass. 9-slice margins protect the gold ends
  (44px) and frame (14px); only the flat centre resizes. `BUTTON_HEIGHT` 48 → **64** so the
  245×90 plate is not squashed — a test asserts the unstretched bands still fit the height.
- **Role tints became restrained.** Red DANGER × teal plate = muddy brown, not "careful". DANGER
  now only darkens slightly; the signal is the crimson **label** plus the word, which also keeps
  colour from being the only carrier of meaning.
- **The menu has a painted scene** — cloud peaks over dark navy, **centred and aspect-preserved
  at ~88% screen height, not stretched**. Stretching 310×330 to fill 1280×720+ is a 4×+ upscale
  and goes soft; centring is ~1.9×. It is seamless because the art's own background navy is close
  to `COLOR_BACKGROUND_DEEP`. The code-built gradient + vignette stay underneath as a working
  fallback (guarded by a test).
- **The HUD portrait well is no longer empty** — it was a rosewood frame around nothing. Now the
  painted portrait sits UNDER the nine-patch frame so the border overlaps the picture's edge. An
  `AtlasTexture` crops the head region, because the source is a full 310×560 standing figure and
  a raw texture in a 56px square well would show the midriff.
- **Honest limits:** the **map is still bare** and this pack cannot fix it (`08_tiles/*` are
  256×256 painted; the world grid is 16px — a 256px painting cannot become a 16px tile without
  being redrawn). The **player is still the proto sprite** (the portraits are illustrations with
  baked backgrounds, not a 16×24 four-direction transparent sheet). And `main_menu.png` was **not**
  used as a background — the pack's README says the infographic crops are references, "not
  cleaned into production sprites".
- **Provenance recorded** in `ASSET_LICENSES.md` with per-file rows **and** a table of what was
  deliberately not imported, so it is not re-litigated.
- **Still not seen on screen:** Godot is not runnable here (D-009).

### 2026-10-02 — Layout defects fixed: 0×0 menu, overflowing side panels, no design resolution (D-043)
Reported from running-build screenshots. Two of the three causes were real defects, and in each
case the thing that *looked* wrong was not the cause. **Presentation + display config only** — no
domain, gameplay, data, locale or autoload change, and no new asset.
- **The main menu was rendering 0×0 in the top-left corner.** `set_anchors_preset(p,
  keep_offsets = false)` does **not** zero the offsets — it recomputes them to PRESERVE the
  control's current rect. `main_menu.tscn`'s root Control has no authored size, so the rect was
  0×0 and the call kept it 0×0 while setting full-rect anchors; the `CenterContainer` then
  centred the plaque in a 0×0 box at the origin and the four screen-corner ornaments collapsed
  onto it. The HUD was fine only because it calls the preset *before* `add_child`, where the
  parent range is 0. Fixed with `set_anchors_and_offsets_preset` in `main_menu` + `settings_menu`
  (same latent defect) and on every full-screen backdrop layer. **L-028.**
- **A side panel could outgrow the screen, lose its frame and bury the prompts.** The politics
  panel was content-sized and anchored from the centre, so three factions grew past the top AND
  bottom of the viewport — and since a 9-slice frame draws at the control's edges, those edges
  were off-screen, which is why it rendered with *no visible plate*. Side panels are now
  **bounded boxes** pinned to screen anchors on all four sides with a `ScrollContainer` inside,
  so their height is `screen − margins − reserved prompt strip` at any resolution and overflow is
  structurally impossible. `UIPalette.PROMPT_STRIP_RESERVE` makes "no panel covers the prompts"
  arithmetic rather than eyeballing. The `ScrollContainer` is explicitly `MOUSE_FILTER_STOP`
  because every other node in these panels is `IGNORE` for click-through.
- **The politics panel's information density was wrong.** It printed every faction's full
  doctrine, turning a comparison list into three paragraphs. Doctrine now shows only for the
  player's own side and whoever holds sway. A density decision, not a capacity one — scrolling
  had already fixed the overflow.
- **The project had no design resolution.** `[display]` had the right stretch mode but no
  `viewport_width/height`, so the base was Godot's implicit default and nobody had decided it.
  Set an explicit **1280×720** base and `handheld/orientation=4` (sensor landscape).
- **Mobile safe areas.** The HUD is inset by `DisplayServer.get_display_safe_area()`, re-applied
  on every viewport change, converted through the viewport/window ratio (the safe area is in
  native screen pixels while the HUD lives in the stretched canvas — without the conversion the
  inset is wrong by exactly the stretch factor on any device with a notch). No-op on desktop.
- **Measured and deliberately NOT fixed: the buttons break this project's own legibility rule.**
  `button_normal.png` centre brightness **202**, `button_hover.png` **217**, against a measured
  `SURFACE_LIGHT_BRIGHTNESS_LIMIT` of **120**. D-034 fixed exactly this for panels but left the
  buttons on the light plate, where only the text outline holds legibility together — that, plus
  the shipped art being red silk rather than jade, is the real source of the "plastic" look. The
  correct fix is swapping the button art, which is an asset change and therefore gated on
  provenance (`06-art-assets.md`). Recorded so it is not lost.
- **Still not verified visually:** Godot is not runnable here (D-009), so all of the above is
  asserted structurally and by CI. Nobody has seen the fixed build on screen.

### 2026-10-02 — Phase 07: Faction / Sect Politics (D-042)
Internal sect factions become a real core system: authoritative domain state, deterministic
politics rules, declared politics mirrored into the shared relationship graph, and the first
usable Faction UI. **No new autoload** (the D-017 budget stays at 5), no networking, no RNG.
- **New layering, mirroring the Sect system exactly:** `src/data/factions/` (`FactionGoalData`,
  `FactionTemplateData`, `FactionCatalog`) → `src/domain/faction/` (`FactionState`,
  `FactionStore`, `FactionService`) → `src/gameplay/world/faction_runtime.gd` (a Node under
  `Main/Systems`) → `src/presentation/faction/` (`SectPoliticsView`, `FactionPanel`).
- **§7's open question is PINNED: standings are relationship EDGES, not inline scalars.** The
  §7 sketch's `attitude_toward_player` / `attitudes_toward_factions` are **dropped and not
  implemented**. `affinity` and `rivalry` are two of the six frozen dimensions (CL-12), so a
  faction-side copy would be a second answer to "how does A feel about B" — the defect D-015 had
  to undo for membership. `RelationshipEndpoint` gained `Kind.FACTION` (appended; the enum int is
  never serialized, so no save shifts meaning). A test asserts the absence on the **serialized
  shape**, which is what a refactor would have to change to reintroduce the duplication.
- **The sect roster stays the single membership authority (D-015, extended verbatim).** A faction
  seat requires existing sect membership, and a character may hold **one seat per sect** — which
  is what makes `CharacterState.faction_id` a valid single value. That pre-existing, unowned
  cache slot now has exactly one writer; `verify_character_cache()` reports drift rather than
  papering over it, and `sync_character_cache()` rebuilds it FROM the rosters.
- **The C-003 guard: Phase 07 enrols NOBODY.** The authored start sect is a scaffold; making it
  an authored *faction* allegiance would hand the player a political identity they never chose.
  Factions ship leaderless and memberless and `start_session` **asserts** that as a
  post-condition. No NPC leaders were invented either (§10).
- **Deterministic rules, no RNG.** `influence_share` (integer percent, never a float),
  `dominant_faction_of` (**ties broken by lexicographically smaller id**) and `is_contested`
  (top two within `CONTESTED_MARGIN`). The tie-break is load-bearing: without it, "who leads the
  sect" could differ between runs on identical data. The seeded RNG seam remains Phase 08's
  (D-040) and was not anticipated.
- **Transactional mirror, non-destructive by contract (L-023).** Declaring politics writes the
  relationship side FIRST and checks it; an existing edge of the wrong type is **retyped in
  place**, never removed and recreated, so a rejected mutation leaves the previous edge fully
  intact — id, endpoints, flags, every dimension value and the whole history. Tests pin object
  **identity** plus the surviving dimension and history, because asserting the type alone passes
  for a replacement. `clear_politics` refuses to destroy an edge carrying a type this mirror does
  not own.
- **Fails closed everywhere:** a dangling declaration, a declaration with no graph to mirror into,
  a faction naming an unknown parent sect, a faction id colliding with a sect id, or a cross-sect
  "internal" declaration each abort rather than degrade. `FactionRuntime` builds into locals and
  commits last, so no half-session is observable (L-025). `Main` treats a faction failure as
  **FATAL** for New Game and unwinds Faction → Sect → Relationship → World → GameState → MENU.
- **Content — a real disagreement, no villain (C-005).** Three Thanh Vân Tông factions taken
  straight from the `WORLD_BIBLE` §8 canon: **Vân Đài** (LOYALIST, 45) the ceiling is the price of
  not repeating the catastrophe; **Khai Lộ** (REFORMIST, 38) institutionalists who have buried
  disciples that died of waiting; **Biên Vân** (RADICAL, 31) who work a gap in the covenant rather
  than break it. Biên Vân declares a rivalry with Vân Đài and **nothing** toward Khai Lộ — they
  share a grievance and reject each other's method, which makes them the sect's swing vote. The
  sect reads **contested** at the shipped influences.
- **First usable Faction UI, in the D-041 language** (`UI_UX_BIBLE` §3a): shared panel plate,
  ornamental rule, aligned caption/value rows. New semantic `faction_panel` action (Y), anchored
  opposite the sect panel so both can be read at once. Status is carried by **words**
  ("Contested", "Holds sway"), never colour alone. Overflow past `MAX_ROWS` is **reported**, not
  silent.
- **Process (L-027):** D-041 had rejected extracting shared UI components believing a new script
  could not get its generated `.uid` — which was blocking a whole phase and turned out to be
  false. Godot's UID text encoding is **base-34** (letters `a..y` = 0–24, digits `0..8` = 25–33,
  MSB first); a decoder **round-tripped all 96 existing `.uid` files** before a single new one was
  minted, so this was verified rather than guessed.
- **Known gap, same as D-041:** Godot is not runnable here (D-009), so **no screenshot of the new
  panel exists**. Its composition is asserted structurally and by CI; nobody has looked at it.
- **Updated:** `relationship_endpoint`, `input_service`, `project.godot` (one new input action),
  `main`, `world_runtime`, `map_base`, `gameplay_hud`, `locale/aetheria.csv`, `SECT_SYSTEM`
  (§7/§12), `WORLD_BIBLE` (§8), `ROADMAP`, `DECISIONS` (D-042), `09-lessons-learned` (L-027).

### 2026-10-02 — Production-foundation visual direction integrated into the runtime UI (D-041) — presentation only
The UI was legible (D-034 fixed that) but **undesigned**: a plaque floating on flat near-black,
four buttons of identical weight, and an identity block where "who I am" and "who I belong to"
were typographically indistinguishable. This closes the composition gap before Phase 07 adds the
first Faction UI and inherits the language. **No gameplay, domain, data, `.tres`, `project.godot`,
locale, autoload or networking change** — `src/presentation/**` and
`tests/unit/presentation/**` only.
- **The main menu is composed as a scene**, not a widget stack: deep ink ground, a vertical
  gradient **horizon**, a restrained radial vignette, four corner ornaments, then the plaque.
  Built from **code-generated `GradientTexture2D` + one existing texture** — no new asset, so no
  new provenance obligation, and no per-frame cost (a gradient rasterises once). The gradient
  layers are the only UI textures on `TEXTURE_FILTER_LINEAR`; a 16×256 ramp stretched full-screen
  would band under the project-default nearest filter. Everything else stays nearest.
- **Button weight is now semantic.** `UITheme.ROLE_PRIMARY/SECONDARY/DANGER` +
  `role_modulate()`/`role_font_color()`: the menu asks for a role and **never names a colour**.
  Roles **modulate** the authored xianxia texture instead of replacing it. `COLOR_CRIMSON` is
  **reserved** for leaving/destroying — never ordinary emphasis.
- **`key_badge.png` is used for what it actually is.** D-034 measured its centre alpha at **0**:
  it is a hollow **corner ornament**, which Phase 06 had pressed into service as a keycap (where
  it rendered glyphs as smudges). It now frames the four screen corners; the keycap stays the
  drawn `StyleBoxFlat` chip.
- **HUD plaques gained hierarchy.** The identity plaque is one unit with **two tiers** (portrait +
  name + title / ornamental rule / sect chip). The map-name plaque gained a width **floor** so it
  stops resizing per map name, and the place name was promoted to the title tone. The sect panel's
  four numeric facts became an aligned caption/value column instead of four sentences.
- **Layout tokens replaced duplicated literals**: `MENU_PANEL_WIDTH`, `MENU_BUTTON_WIDTH`,
  `BUTTON_HEIGHT`, `TITLE_GAP`, `SECTION_GAP`, `ROW_GAP`, `PANEL_GUTTER`, `HUD_MARGIN`,
  `ORNAMENT_PX`, `IDENTITY_PORTRAIT_PX`, `HUD_MAP_PANEL_WIDTH`.
- **Deliberately not done:** no HP/mana/realm/XP gauge. The reference shows them; nothing in the
  session owns those values yet, and a gauge that looks right in a mock is a lie in a build. A
  test asserts the HUD builds no `ProgressBar`/`TextureProgressBar`. No new `.gd` file either —
  the shared row/section components were rejected because a new script cannot get its generated
  `.uid` here (L-008/L-015); the row builder stays a private helper until a second panel needs it.
- **Tests added** (structural, because this class of defect is invisible to compile/lint — L-021):
  role distinctness, reserved-crimson, backdrop layering, ornament identity, layout-token
  coherence, identity-plaque tiering, map-plaque floor, divider stretch, shared HUD margin,
  no-unbound-stats, plus behaviour-survival tests on both the menu and the HUD.
- **Known gap (stated, not glossed):** the task asked for runtime screenshots. **Godot is not
  invocable on this machine (D-009)**, so none could be captured. The composition is asserted
  structurally and by CI, *not observed*. Main Menu, HUD in both maps, and the open Sect panel in
  `vi` + `en` still need a human eyeball in the editor.
- **Updated:** `ui_palette`, `ui_theme`, `main_menu`, `gameplay_hud`, `sect_panel`,
  `test_ui_theme`, `test_main_menu`, `test_gameplay_hud`, `UI_UX_BIBLE`, `ASSET_LICENSES`,
  `DECISIONS` (D-041).

### 2026-10-04 — Design dependency hardening (D-040) — documentation only
An independent review of the D-039 freeze found **two dependency defects**. Both lived in the
*edges between phases*, which is the blind spot a per-system matrix creates: every row can be
locally correct while the ordering between rows is impossible. **No gameplay code, no scenes, no
`.tres`, no locale, no runtime change, no new autoload, no phase renumbering.**
- **Knowledge Core now has a valid owner and phase (C-012).** It was listed as owned by
  Story/Quest at P-19/20 while Cultivation (P-12) and Technique (P-15) already read it — a
  backwards dependency. Fixed: **Knowledge Core lands in Phase 12** with its own owner
  (`KnowledgeStore` + `KnowledgeService`, no autoload). Cultivation/Technique/Crafting **read**;
  Dialogue/Quest/Story **grant through the service**; **nothing else may mutate the collection**.
  Story does not own knowledge and must not shadow it with flags. Phase 12 does *not* grow a story
  engine to support this — the core is a store, a service, a grant path and an event.
- **The RNG seam moved to its real first consumer (C-010).** D-039 guessed Combat (P-09) would
  introduce it, but World Simulation is **P-08** and its determinism requirement is explicit.
  Fixed: **introduced in P-08**, **stream-scoped** (one run/world seed → per-subsystem streams),
  and P-09 reuses it. Streams rather than one generator because a shared generator means an extra
  random call in combat silently shifts every later world-sim roll, and "same seed → same world"
  stops being true.
- **`SAVE_FORMAT.md` §3b (new, requirement only):** a single `rng: { seed }` is **not
  sufficient** — a save taken 40 hours in must restore how far each stream has advanced, or the
  post-load world diverges. Also: knowledge serializes as its own block, never inside `story`.
- **Audit X — dependency topology — added as a permanent gate**, with the rule *no earlier phase
  may require authoritative state owned by a later phase*. Full edge-by-edge check in
  `SYSTEM_DEPENDENCY_MATRIX.md` §4b.
- **Fixed in passing:** the World Simulation row in the dependency matrix had 14 cells in a
  15-column table (missing UI) — a D-039 table defect; a new explicit **Deterministic RNG** row
  was added alongside it.
- **Updated:** `SYSTEM_DEPENDENCY_MATRIX` (7 rows + §4b/§4c), `PROGRESSION_CULTIVATION_DESIGN`
  (+§7a), `CONTRADICTION_REGISTER` (C-010 rewritten, C-012 added, Audit X),
  `CANON_LEDGER` (CL-14 extended, CL-16 added), `SAVE_FORMAT` (+§3b), `ROADMAP`
  (Phases 08/09/12/15/17/18/19/20), `GAME_DESIGN_FREEZE` (+§7b, ownership table, debts),
  `ECONOMY_CRAFTING_DESIGN`, `GAME_FLOW`, `DECISIONS` (D-040).

### 2026-10-04 — MASTER GAME DESIGN FREEZE v2.1 (D-039) — documentation only
The world, narrative and systems design is frozen **before** the content-bearing phases begin.
**No gameplay code, no runtime behaviour change, no content/locale change, no new autoload, no
networking, no phase renumbering.** CI stays at 10 gates.
- **Thirteen documents created**, with ONE authoritative owner per rule declared in the master
  index `docs/GAME_DESIGN_FREEZE.md`: `CANON_LEDGER.md` · `CONTRADICTION_REGISTER.md` ·
  `WORLD_BIBLE.md` · `NARRATIVE_MASTER_PLAN.md` · `PROGRESSION_CULTIVATION_DESIGN.md` ·
  `COMBAT_DESIGN.md` · `ECONOMY_CRAFTING_DESIGN.md` · `SOCIAL_DESIGN.md` ·
  `MAP_DUNGEON_DESIGN.md` · `SYSTEM_DEPENDENCY_MATRIX.md` · `CONTENT_BIBLE.md` · `UI_UX_BIBLE.md`.
- **Eleven real contradictions found in the existing repo** and resolved with named owners.
  The three that mattered most: the narrative promised "no sect standing" while the build enrolled
  the player in a sect on New Game (**C-003**, premise-breaking); the realm ladder was still the
  conventional Luyện Khí/Trúc Cơ example in steering with nothing authored against it (**C-001**,
  last cheap moment to change); and maps were being gated by level against steering's own
  cảnh-giới contract (**C-002** — level is now *never* an access gate, and `MapData` may never
  gain a `min_level`).
- **New original canon:** Hạo Nguyên Giới (Main World, 5 đại vực / 12 châu), the Hải Giới and the
  Tiểu/Tàn/Hủ/Vô Giới categories, the **Thiên Khế** covenant, the historical **Tà Đế** with three
  incompatible records, **ĐÊM VỠ MẠCH** as the inciting event, a twelve-beat prologue, five
  gender-independent Origins, and the realm hierarchy **PHÀM → HẬU THIÊN → TIÊN THIÊN → NGỰ THIÊN
  → TRỌNG THIÊN** with nine meaningful layers each.
- **Identity is derived, never counted** — no `evil_score`, morality meter or alignment. "Tà Đế"
  is read from accumulated history, so a compassionate player can earn it and a ruthless one can
  avoid it.
- **Knowledge (Tri Thức) frozen as a third progression concept** alongside level and realm, and
  the three categories of "forbidden" (Ma Đạo / Tà Đạo / Cấm Pháp) kept deliberately distinct.
- **Updated:** `GAME_FLOW.md` (one status block instead of two — C-006; prologue now points at its
  spec — C-007), `NARRATIVE_DIRECTION.md` (now the short north star pointing at the long form),
  `MULTIPLAYER_PLAN.md` (+§2a the four-way narrative state split, so co-op can never destroy
  personal canon), `ROADMAP.md`, `DECISIONS.md` (D-039), steering `01-product` (the player fantasy),
  `02-game-design` (realm glossary row corrected + level-never-gates rule + six new terms),
  `06-art-assets` (UI design direction pointer).
- **Balance stays unfrozen on purpose:** XP curves, damage, drop rates, cultivation speed,
  cooldowns, threat boundaries, map sizes. Architecture first, numbers later.
- **Extensibility tested, not asserted:** the 10-quest/5-NPC/3-map/2-dungeon/2-boss/3-technique/
  2-weapon/1-sect/2-faction/1-Minor-World simulation passes as data + content scenes, with two
  recorded exceptions (a sixth weapon family, and any new element/status, are closed-set design
  changes).

### 2026-10-04 — Phase 06 follow-up: the reverse transaction + test integrity (D-038)
Four residual issues D-037's green CI could not reveal. No new scope, no new autoload, **CI
still 10 gates** (the existing suite gate was hardened, not duplicated). CI-verified green on
`1dabdba`: **`ran 282 test(s): 282 passed, 0 failed`** with **zero `SCRIPT ERROR:` lines** —
the first run where that count is trustworthy, and the number is quoted from the CI annotation
rather than counted by hand.
- **`clear_diplomacy()` is transactional.** D-037 fixed the create/retype leg but left the
  REMOVE leg inverted: both `SectState`s were cleared first and `remove_edge()`'s boolean was
  discarded, so a rejected removal left the sect state saying "no relation" while the mirrored
  edge survived (L-023's divergence, reversed). The relationship side now runs first and is
  checked. Also: a pair with nothing declared is a true no-op that never touches the graph and
  emits nothing; the two sects disagreeing fails closed; and an edge carrying a type this
  mirror does not own is **left alone** rather than destroyed.
- **Authored default diplomacy must be SYMMETRIC and non-conflicting.** `A ALLY B` with B
  silent would mirror an edge only one sect records, and `A ALLY B` + `B ENEMY A` would let
  catalog ordering pick the relationship type. Both are now catalog errors, keyed on the two
  ids **sorted** so the verdict is order-independent (asserted with the list reversed). Shipped
  Azure Cloud ↔ Crimson Flame content unaffected.
- **`SectRuntime.start_session()` requires a WORKING character resolver** when the catalog names
  a player start sect. The `SectService` "null resolver = checks disabled" contract is unchanged
  (roster-only unit tests need it); the gap was at the runtime boundary, where it silently
  skipped the existence check and the derived-cache write.
- **Test integrity: a test method that ABORTS was reported as PASS.** CI said `275 passed /
  0 failed` while the log held real `SCRIPT ERROR:` lines — seven methods had never run an
  assertion. A typed `@export` array rejects an untyped one, and that VM error aborts the
  running function, so the fixture returned `null`, the caller faulted, and `TestCase` (which
  records only *assertion* failures) reported success. Fixtures now build typed locals with
  concrete receiver types, assert themselves before asserting behaviour, and pin the reported
  REASON in every negative case. **The existing headless gate now fails on any `SCRIPT ERROR:`**
  even when the runner exits 0 (`push_error()` prints `USER ERROR:`, so deliberate fail-closed
  tests do not trip it) and emits the runner's own tally as a `::notice::` annotation so the
  documented test count can be quoted from CI instead of counted by hand (D-009). See L-026.

### 2026-10-03 — Phase 06 final hardening: fail-closed sect core (D-037)
Six failure modes a green CI cannot see, closed. No new scope, no new autoload, **CI still
10 gates**; the existing test files were expanded in place and no assertion was weakened.
CI-verified green (all 10 gates) on `5f7d0c9`; the in-runner suite is now **275 test methods
across 33 files** — 25 added by this change (+18 sect-domain, +3 sect-runtime, +3 HUD/sect
panel, +1 localization), so 250 before it.
- **Diplomacy retype is NON-DESTRUCTIVE.** `SectService._ensure_edge()` flipped ALLY→ENEMY by
  `remove_edge()` then `create_edge()`, so a rejected flip destroyed the very edge it was
  "rolling back" (and a successful one silently discarded the edge's dimensions + history).
  New `RelationshipService.set_relationship_type()` rewrites only the type in place, preserving
  id/endpoints/flags/dimensions/history; `_ensure_edge` never removes. Tests assert OBJECT
  IDENTITY + preserved state, not just the resulting type (L-023).
- **`SectRuntime.start_session()` is FAIL-CLOSED.** It used to `continue` past a sect that
  failed to register, warn when the player could not join, and report success anyway. It is now
  nine steps built into locals and committed only at the end (`_fail_start()` clears
  everything), so a failure leaves no observable session. `apply_default_diplomacy()` returns
  `bool` and fails closed on a dangling declaration or on declared diplomacy with no graph to
  mirror into — both were previously skipped in silence (L-025).
- **New Game treats relationship + sect failures as FATAL.** `_start_sect_session()` returns
  `bool`; `_unwind_failed_session()` ends **Sect → Relationship → World → GameState** (reverse
  dependency order) and returns to the menu. The forbidden state "RUNNING + world live +
  `character.sect_id` set + sect session inactive" is now unreachable and asserted so in the
  world E2E.
- **`SectState.from_dict()` validates `typeof()` before converting.** Coercions do not fail,
  they invent: `int("100")`/`int(100.0)` → `100`, `String(99)` → `"99"`, `String(null)` → `""`
  (read as "no leader"). ID-like fields must be String/StringName, count-like fields must be
  `TYPE_INT`, dictionary KEYS included. Still atomic — a rejection leaves the state
  byte-identical (L-024).
- **Rank ladder `authority` must increase STRICTLY** along the authored array order (the array
  IS the progression), so `10/20/20`, `20/10/30` and `30/20/10` are rejected.
- **`SectCatalog` validates referential integrity** of every declared ally/enemy (resolves, no
  self-reference, no duplicate, allies/enemies disjoint). A dangling id now invalidates the
  catalog instead of being silently skipped at mirror time; a drift guard reads the SHIPPED
  catalog.
- **The Sect panel shows localized resource NAMES**, never content ids: `spirit_stones` →
  `SECT_RESOURCE_SPIRIT_STONES` (a pure naming convention, not a registry), with vi+en rows for
  spirit stones / pills / manpower / blood crystals and a localized generic fallback.
- **Docs reconciled:** `ARCHITECTURE` + `GAME_FLOW` (Phase 06 CLOSED, Phase 07 NOT STARTED, sect
  membership/HUD/panel described as live), `DATA_SCHEMA` (implemented vs. design-only tiers),
  `RELATIONSHIP_SYSTEM` + `CHARACTER_SYSTEM` (no longer "design only"; the character sect fields
  documented as a derived cache), `SECT_SYSTEM` §12 (implemented vs. still-a-contract),
  `TEST_PLAN` (Phase 06 coverage + 10 gates), `ROADMAP`, `DECISIONS` (D-037), lessons
  (L-023/L-024/L-025).
- **Breaking (tests only):** `start_session(null, …)` against a catalog that declares diplomacy
  now fails; the sect runtime tests supply a real in-memory `RelationshipService` instead, and a
  new test pins the fail-closed behaviour.

### 2026-10-03 — Phase 06: Sect System (core domain + runtime + UI) (D-032)
- **Sect domain (core system, data-driven):** `SectTemplateData` + `SectRankData` (ordered
  rank ladder as content, not code) + `SectCatalog`; `SectState` (authoritative roster —
  leader/elders/disciples + rank_by_character — resources/territory/reputation/influence/
  declared allies+enemies, fail-closed `to_dict`/`from_dict`); `SectStore` (single collection
  SoT); `SectService` (the ONLY mutation path: join/leave/rank/leader/elder, resource/
  reputation/influence/territory, diplomacy, with full membership + economy invariants).
- **Membership authority = the roster (D-015):** `CharacterState.sect_id`/`sect_rank` are a
  DERIVED cache the service writes on join/leave/rank; `sync_character_cache()` rebuilds the
  cache FROM the roster (roster wins on drift). Enrolling a non-existent character is rejected
  via an injected character-resolver seam (no `/root`, no fake character).
- **Relationship mirror, transactional:** declared sect alliances/enemies are mirrored to
  symmetric Sect↔Sect edges in the existing RelationshipService (stable `sect_rel:a|b` id,
  one edge per pair). The mutation is transactional — if the relationship edge fails, the sect
  declaration rolls back so the two stores never diverge.
- **SectRuntime** (`Main/Systems`, NOT an autoload — budget stays 5): per-session owner that
  loads the catalog, registers sects, mirrors default diplomacy, enrolls the player into the
  authored start sect, survives map swaps, and ends/clears on return to menu. Wired in
  `main.gd` after the world + relationship sessions.
- **Sect UI (Continuous Visual Integration):** a compact sect chip (emblem + name + rank +
  reputation) in the GameplayHUD + a toggleable `SectPanel` (doctrine/type/tier/rank/
  reputation/influence/territory/resources) in the live Xianxia UI language, opened via the new
  semantic `sect_panel` action (display label through InputService; no raw keycode). All text
  localized (vi + en); no raw sect ids shown; a localized "no sect" empty state. A sect banner
  (emblem) decorates the hub. UI reads a read-only `SectMembershipView` DTO — no sect truth in
  presentation.
- **Content:** `sect_azure_cloud` (orthodox, player's start sect) + `sect_crimson_flame`
  (demonic, its enemy) authored as data; self-made CC0-equivalent 16×16 emblems; player
  template `default_sect_id` seeds the cache, the roster is authoritative.
- **Tests:** `tests/unit/sect/` domain (28 cases) + runtime (Node/session/survival/view),
  localization sect-key coverage (vi+en), and the world/map E2E extended to assert SectRuntime
  exists/active, player membership matches the roster, the HUD renders the sect, the panel
  toggles via REAL `sect_panel` input, membership survives 20 map round trips, and the session
  clears on return to menu. No new CI gate; 9 gates unchanged.
- **Scope:** NO Faction/Politics engine (Phase 07), World Simulation (Phase 08), Combat,
  Inventory, Save, or networking. No new autoload.
- **CI bring-up:** the first Phase-06 push (`088921a`) was CI-red — `sect_state.gd` failed to
  compile because `from_dict` inferred `Variant` locals via `:=` from a `-> Variant` helper
  (warning-as-error), so `class_name SectState` never registered and every
  `SectState.create_from_template`/`.new()` reported the misleading "base 'GDScript'". Fixed by
  typing the three staged arrays `Variant` + casting on commit (`b3c98cc`). **CLOSED: CI green
  on `b3c98cc` — all 9 gates.** See lesson L-020. (Temporary CI diagnostic from steering 10 §1.3
  was added to read the real error, then fully removed in the same fix commit.)

### 2026-10-03 — Phase 06 follow-up: engine-free lint gate, UI legibility fix, camera follow, Vietnamese default + Settings (D-033…D-036)
- **Engine-free GDScript lint gate (D-033):** new `tools/gdscript_lint.py` (pure Python, no
  dependencies, no Godot) with three zero-false-positive rules — `GD001` a local inferring
  `Variant` (the L-020 compile-breaker), `GD002` cross-file private access, `GD003` line
  budget. It self-tests (`--selftest`), runs as CI gate 2 of 10 **before** Godot is even
  downloaded, and on save checks only files git reports as changed. Fixed all 44 existing
  violations it found (28 private-access + 16 long lines).
- **`parse_check.gd` now proves a script COMPILES** (D-033): `load()` non-null +
  `can_instantiate()` + a declared `class_name` must actually be registered globally. The old
  gate only checked `load() != null`, which is why a non-compiling `SectState` passed it.
- **Hook cost cut:** the AI-review reminder moved from `PreToolUse` (which fired on *every*
  file edit and blocked the tool) to `Stop`; the dead `godot`-on-PATH parse hook was removed.
- **`SectState` private mutators became a documented public raw-writer API** (D-033):
  `write_*`/`insert_*`/`erase_*`. GDScript has no package visibility, so the old `_`-prefixed
  form forced `SectService` to violate another class's private API on every mutation. The
  single-mutation-path invariant is now held by docs + tests, not a prefix. `_edge_id` →
  `edge_id`.
- **UI legibility, from measured pixels (D-034):** the text-bearing panel now uses the DARK ink
  texture (`panel.png` measures brightness 230 — near white — behind a light-only text
  palette); content margins clear the 9-slice border; the key badge is a drawn flat chip
  because `key_badge.png` has a fully transparent centre and is a corner ornament, not a
  keycap; light text gets a dark outline; the HUD finally wears the shared theme. The empty
  "portrait" is a `NinePatchRect` and sized slots set `expand_mode`, so a 218×118 plate no
  longer reports itself as a 40×40 slot and shoves the identity panel over the name.
- **Pressing `T` works (D-034):** the Sect panel was wrapped in an empty size-0 `Control`
  carrying the grow direction — which does not propagate to children — so the panel grew
  off-screen and only a sliver of its frame showed. Anchors/growth now live on the panel.
- **Camera follows the player (D-036):** each map's `Camera2D` was a static child that nothing
  ever moved; invisible while the whole map fitted on screen, fatal once it did not. `MapBase`
  now tracks the player in `_physics_process` with position smoothing, still clamped by the
  data-driven limits. Derived zoom no longer rounds up (a needed 3.01 became 4.0 and framed far
  too close), and the hub/field maps are authored **960×576** instead of 448×288 so the view
  fits inside the map and the camera has room to travel.
- **Vietnamese is the default language + a Settings screen (D-035):** `DEFAULT_LANGUAGE = "vi"`
  with a SEPARATE `FALLBACK_LANGUAGE = "en"` (collapsing them would make a key missing its
  Vietnamese value resolve to the raw key instead of the English text that exists). The
  Settings button is enabled and opens a screen built from `available_languages()`; the choice
  persists in `user://settings.cfg` via a `SettingsStore` `RefCounted` (**no new autoload** —
  budget stays at 5). `Localization` stays deliberately disk-free so unit tests cannot leave a
  stale language behind.
- **Tests:** +4 UI-theme regression guards (dark text surface, content margin clears border,
  keycap has an opaque fill, theme carries an outline), +3 localization tests (vi default,
  default≠fallback, settings keys in both languages), new `test_settings_store.gd` (7) and
  `test_settings_menu.gd` (5), a `MapData.bounds` ↔ painted-floor drift guard, and the world
  E2E now proves the camera actually moved and stayed within limits. CI gates: 9 → 10.

### 2026-10-03 — Changelog correction: D-030 added 2 (not 4) test methods (D-031)
- Corrected the D-030 entry's test-method count to "+2 test methods" (the two
  `test_hub_decor_contract`/`test_field_decor_contract`); the other D-030 test changes were
  assertion edits, not new methods. Documentation only; no code/test change.

### 2026-10-03 — Phase 05 close-out + visual-foundation hardening (D-030)
- **Documentation drift reconciled:** ROADMAP Phase 05 now reads *all 9 gates green* (matches
  `ci.yml`, was "7"); Phase 25 renamed **"UI Consolidation / Production Polish"** (final polish,
  not where production UI begins, not a rescue rewrite). `06-art-assets.md`, `ARCHITECTURE.md`
  and `GAME_FLOW.md` updated: live UI = CC0 Xianxia (D-028, the retired `mana_soul` prototype and
  the "Mana Soul intended upgrade" wording removed), world/character art = production-foundation
  (D-029, not flat prototype, not final), Relationship core CLOSED, Phase 06 NOT STARTED.
- **Continuous Visual Integration adopted** as a binding ROADMAP policy: visuals grow per feature
  phase, replace by asset/component/theme layer (via `UITheme`/`UIPalette`), never change
  gameplay/domain truth, chosen per domain (no giant single pack, no collage); Phase 25 is the
  consolidation/polish endpoint.
- **D-029 visual contracts tested:** `test_map_scenes.gd` now guards `Visual/Decor` (≥1 nearest-
  filtered prop `Sprite2D` with a known texture at authored size — lantern 16×24, tree 32×32,
  rock/planter 16×16), that `Visual/Ground` is still the first child, and ground TileMapLayer is
  nearest-filtered. (+2 test methods; character contracts already covered.)
- **UI polish (seam-only, no new screen):** added a muted-gold `COLOR_TITLE` token for the menu
  title plaque, tightened the type scale (subtitle 18→20, hint 15→14), evened button vertical
  padding (10→12) — all through `UIPalette`/`UITheme`. No gameplay/domain change; UI-theme
  invariants (incl. title > body) stay green.

### 2026-10-03 — Production-foundation world + character art for the playable flow (D-029)
- **World tileset redrawn (in place):** `assets/tiles/prototype/prototype_tileset.png` (same
  48×16 three-column strip, same `prototype_tileset.tres` / `prototype_ground.gd`) upgraded from
  flat colour blocks to shaded, ordered-dithered tiles — mossy jade grass, warm flagstone path,
  blue-grey Chinese roof-tile wall. The hub/field no longer read as one flat green plane.
- **Character redrawn (in place):** the in-game player frame `player_proto.png` (16×24) and the
  four archetype idle sheets (`*_proto_idle.png`, 64×24) now share one drawing routine
  (`_draw_character_frame`) — a fully-outlined, shaded top-down figure (hair sheen, jaw/arm
  shadow, robe hem, per-archetype sash accent, foot contact shadow). Fixed a gap where only the
  idle sheets, not the frame `player.tscn` actually uses, had been upgraded.
- **Decorative props (new):** four self-made Chinese garden-courtyard props — `prop_lantern`
  (16×24), `prop_tree` (32×32), `prop_rock` (16×16), `prop_planter` (16×16) — placed as
  presentation-only `Sprite2D` nodes under a new `Visual/Decor` in `hub_map.tscn` /
  `field_map.tscn`, in open grass clear of the player corridor and exit zones.
- **Seam preserved:** pure presentation. No change to the TileSet resource, ground script,
  `MapData`, camera bounds, wall collision, exit zones, spawns, or any gameplay/domain/data. All
  tests (structural map test, world/player/app E2E, character-visual dims test) keep their
  contracts. Self-made/project-owned (recorded in `ASSET_LICENSES.md` P1/P2 + P14–P17 redrawn,
  P18–P21 new). Visual tier step (prototype → production foundation); Phase 06 NOT started.

### 2026-10-03 — Visual asset audit + production UI art (D-028; CC0 Xianxia UI)
- **Asset audit:** audited 5 local candidate packs for license + fit and classified each
  (recorded in `docs/ASSET_LICENSES.md`): Xianxia Pixel Pack (CC0) = APPROVED primary UI;
  Verdant 00 16×16 tiles (free commercial) = APPROVED terrain but deferred; Foozle Lucifer RPG
  UI (CC0) + Tiny RPG Mana Soul GUI (CC0) = candidate/supporting (not used, avoid collage);
  Ancient Chinese Characters Pack 1 = UNVERIFIED (no license file) → NOT imported.
- **Production UI art:** replaced the self-made prototype UI (`assets/ui/mana_soul/` +
  `tools/gen_ui_assets.py`, D-024) with the CC0 **Xianxia Pixel Pack** UI set under
  `assets/ui/xianxia/` — jade panel, ink inset, jade buttons (normal/hover/pressed), silk
  disabled/focus, rosewood portrait frame, corner key-badge, jade title divider. The menu/HUD
  now read as a wuxia dark-ink/jade game UI instead of flat prototype plates.
- **Seam preserved:** only `UIPalette` (asset dir + per-slot 9-slice margins) and `UITheme`
  (margin wiring + doc) changed; the `UITheme`/`UIPalette`/component/9-slice abstraction, slot
  names, `UI_TEXTURES` contract, and flat fallbacks are unchanged, so `MainMenu`/`GameplayHUD`
  consume the new look with no code edits. The menu background is now a flat deep-ink fill
  (the framed inset texture is not a seamless tile).
- **Scope:** UI art layer only — NO gameplay/domain change, NO new systems/screens, NO
  character/terrain change (top-down CharacterArtBible untouched; no side-view assets). No test
  count change (`test_ui_theme` asset-contract now verifies the xianxia textures). Docs synced
  (ASSET_LICENSES, ARCHITECTURE, ROADMAP). Phase 06 NOT started.

### 2026-10-03 — Phase 05 (D-026; Relationship core + early character visual pipeline + narrative anchor)
- **Relationship domain graph (core system):** added `RelationshipEndpoint` (typed
  `{kind,id}` CHARACTER|SECT), `RelationshipEdge` (id/from/to/type/dimensions/symmetric/known/
  history), `RelationshipStore` (owns edges; indexes by edge id + endpoint; symmetric canonical
  ordering; deterministic `to_dict`/fail-closed `hydrate` with index rebuild), and
  `RelationshipService` (the SINGLE mutation path: validate → clamp to config range → bounded
  history on a real change → domain signal `relationship_changed`; zero-delta no-op; missing
  edge fails loud; debt perspective flips only on a symmetric reverse query). `CharacterState`
  is deliberately NOT given a relationship dict (single source of truth).
- **Data-driven relationship tuning:** `RelationshipConfigData`
  (`data/relationship/relationship_config.tres`, 6 dimensions with the documented ranges +
  history capacity) and `RelationshipRuleData` + `RelationshipRuleCatalog`
  (`data/relationship/relationship_rules.tres`, 6 deterministic event→delta rules). No range or
  rule is a magic number in code.
- **Runtime ownership:** `RelationshipRuntime` node under `Main/Systems` (sibling of
  `WorldRuntime`, NOT an autoload) owns the per-session store+service and survives map swaps;
  started on New Game, ended on return to menu. Autoload budget unchanged (D-017).
- **Early character visual pipeline (presentation):** `CharacterVisualProfileData` +
  `CharacterVisualComponent` (4-direction sheet, nearest filter, feet-anchored, movement-driven
  facing; `MovementComponent` stays the movement authority). The Player resolves its template's
  `sprite_set_ref` into a data-driven sprite (missing/invalid → loud + static fallback). Four
  self-made prototype archetype sheets (player/female cultivator/elder/merchant) via
  `tools/gen_prototype_assets.py` + four `CharacterVisualProfileData` `.tres`. A dev-only
  `character_preview` scene (NOT the first scene). `CharacterState` still carries NO presentation
  data (tested).
- **Design anchors:** `docs/CHARACTER_ART_BIBLE.md` (16px grid, 16×24 baseline, feet anchor,
  collision independent of sprite height, palette/direction/animation rules) and
  `docs/NARRATIVE_DIRECTION.md` (original tu-tiên premise + relationship-driven first arc; no
  story engine, no copyrighted content).
- **Tests:** `tests/unit/relationship/*` (config validity; the full B–U graph matrix incl.
  symmetric/debt perspective, deterministic event→delta, serialize round-trip + fail-closed
  hydrate + index rebuild; rules), `tests/integration/test_relationship_runtime.gd`, extended
  `tests/e2e/world_flow_case.gd` (RelationshipRuntime persists across 20 map swaps, not an
  autoload, session ends on menu), and `tests/unit/presentation/test_character_visual.gd`.
- **Scope:** no NPC/Dialogue/Quest/Story/Sect/Faction/WorldSim/Combat/Inventory/Save/networking;
  no new autoload; game flow + first scene unchanged. SECT endpoints structural-only (Phase 06
  adds the real `SectState` + referential validation). Docs synced; D-026 recorded.

### 2026-10-03 — Phase 04 close-out (D-025; residual test-exit leak fixed + doc drift)
- **Residual leak root-caused and fixed.** The green headless suite still printed
  `WARNING: 5 ObjectDB instances were leaked at exit` + `ERROR: 1 resources still in use at
  exit`. A one-time `--verbose` CI diagnostic (steering 10 §1.3, commit `906e4ef`, then
  removed) named the leaked instances: 3× `Node`, 1× `GDScript`
  (`src/infrastructure/input_service.gd`), 1× `GDScriptNativeClass`. Root cause: three un-freed
  `InputService` Nodes in `tests/unit/core/test_input_display_label.gd` (an unfreed `Node`
  pins its GDScript + native class). Fixed by `svc.free()` in each of the three methods; the
  suite now exits with 0 ObjectDB leaked / 0 resources in use. No production code changed, no
  assertion lowered, D-019 isolation untouched. Added lesson **L-019**.
- **Doc drift corrected (L-014).** `ROADMAP.md` Phase 04 → **CLOSED** with evidence (`7615d88`,
  9 gates green, 163 tests). Corrected the D-024 "resource-in-use" bullet (it wrongly assumed a
  green run was leak-free). Added **D-025** to `DECISIONS.md`.
- **Scope:** close-out only — no Character/UI/Combat/Quest/Dialogue/Save/networking work; no new
  autoloads; Phase 05 (Relationship) still NOT STARTED.

### 2026-10-02 — Phase 04 reopen / UI hardening (D-024; asset-backed pixel-art UI)
- **Real pixel-art UI assets:** added `tools/gen_ui_assets.py` (pure-Python PNG writer, no
  download) producing a project-owned 9-slice UI set under `assets/ui/mana_soul/` — framed
  `panel`/`panel_inset`, button states `normal/hover/pressed/disabled/focus`, a `key_badge`
  keycap, a `portrait_frame`, and a `title_divider`. Self-made/CC0-equivalent because the
  preferred pack (tiopalada "Tiny RPG - Mana Soul GUI", CC0) is not auto-downloadable here
  (itch.io 403); recorded in `docs/ASSET_LICENSES.md` with the intended upgrade noted.
- **Asset-backed theme + components:** `UIPalette` gains the texture paths + 9-slice margins
  (single source of truth); `UITheme` now builds `StyleBoxTexture` panels/buttons/badge with
  the authored border margins (crisp corners, graceful flat fallback). New reusable
  `src/presentation/ui/components/` — `UIKeyBadge` (graphic keycap) + `UIPromptRow` (badge +
  action label).
- **Main menu redesign:** tiled pixel background + centered framed `PanelContainer`, title +
  subtitle + ornamental divider, four buttons with real states; Load Game and Settings are
  distinct disabled placeholders. Signals/localization/input-context unchanged. Added
  `UI_MENU_SETTINGS` (vi/en).
- **HUD redesign:** three framed panels — identity (portrait-frame slot + name/title from
  `CharacterState`), map name, and a control-prompt panel showing graphic `[E] Interact` /
  `[Esc] Menu` badges (via `InputService.get_action_display_label`, never raw keycodes). No
  fake HP/mana/cultivation bars (reserved for a later phase). Added `UI_HUD_INTERACT_ACTION`
  / `UI_HUD_MENU_ACTION` (vi/en). Public HUD API unchanged.
- **Map exit visual:** added a gold directional arrow ornament to the hub/field exit gates
  (still a gameplay marker; no VFX system).
- **Tests:** rewrote the UI-theme test (distinct button states, panel/badge build, PanelContainer
  panel style, **asset-contract: all 10 UI textures exist**, asset-backed `StyleBoxTexture`
  when present); rewrote the HUD prompt test (graphic badges + E/Esc/Interact/Menu, no raw
  keycode/action name, ≥2 badge panels); added a main-menu structural test (shared theme, 4
  buttons, Load Game + Settings disabled, emits intents, localized text). All existing tests
  stay green.
- **Resource-in-use warning:** investigated per steering 10 — the earlier `resources still in
  use at exit` + leaked physics body/texture came from the `default_goals` crash aborting the
  character tests before their `free_node` (fixed in D-023), not a UI leak. Documented in
  D-024; no assertions lowered.
- Docs synced: ASSET_LICENSES (UI rows + source), 06-art-assets (UI baseline), ARCHITECTURE,
  GAME_FLOW, TEST_PLAN, PERFORMANCE, ROADMAP, DECISIONS (D-024). Character core unchanged; no
  new autoloads; Phase 05 still NOT STARTED.

### 2026-10-02 — Phase 04 (D-023; Character core + early UI/presentation foundation)
- **Character core (domain + data):** added `CharacterTemplateData`
  (`src/data/characters/character_template_data.gd`, `char_*`) — the data definition with
  identity/origin/age/profession/cultivation-contract/base-stats/traits/affiliation fields +
  validation — and the player template `data/characters/player_default.tres`. Added
  `CharacterState` (`src/domain/character/character_state.gd`, `RefCounted`): the AUTHORITATIVE,
  serializable, presentation-free character instance with a life-state machine
  (ALIVE→DEAD once, DEAD terminal), current-HP authority, and persistent-tier-only
  `to_dict`/`from_dict` (boundary-validated; a SAVE SEAM — `SaveService` is still Phase 23).
- **Player is a view of one authoritative state:** `WorldRuntime` builds ONE player
  `CharacterState` (fixed `instance_id="player"`) and binds it to the persistent Player before
  it enters the tree. `StatsComponent` reads its numbers from the bound state (falls back to
  the authored `StatBlock` only when unbound); `HealthComponent` syncs HP/death back
  (`set_current_hp`/`mark_dead`). Composition kept; state NOT recreated on map swap.
- **Data-driven start map:** `MapCatalog` gains validated `start_map_id`; `WorldRuntime`
  reads it (removed the hard-coded `START_MAP_ID`).
- **Early UI/presentation foundation:** `UIPalette` design tokens + `UITheme.build()`
  (code-built shared Theme). Main-menu presentation pass (background, title/subtitle, uniform
  styled buttons, focus) — signals/localization/context unchanged. New `GameplayHUD`
  (owned by MapBase) shows the character's name/title + localized map name + control hints.
  New `InputService.get_action_display_label` resolves real key labels (interact→E,
  open_menu→Esc); the UI never reads keycodes. Shared data-driven camera zoom (2× for 16px);
  exit zones show a jade prototype gate instead of the yellow debug block.
- **Localization:** added `CHARACTER_PLAYER_NAME/TITLE/ORIGIN`, `UI_MENU_SUBTITLE`,
  `UI_HUD_INTERACT_HINT`, `UI_HUD_MENU_HINT` (vi + en).
- **Tests:** character unit (template validation, state construction/life-state/HP/round-trip),
  player↔state binding integration, UI theme + HUD structural, input-display-label, Phase-04
  localization-key coverage. The world E2E now asserts the SAME `CharacterState` instance
  across 20 round trips (not recreated on map swap). All diagnostics clean (only the known
  cross-file `class_name` LSP cache false-positives, resolved by CI `--import`).
- Docs synced: CHARACTER_SYSTEM (status §10), DATA_SCHEMA, ARCHITECTURE, GAME_FLOW, TEST_PLAN,
  PERFORMANCE, ROADMAP (Phase 04 IN PROGRESS), DECISIONS (D-023). No new autoloads; scope held.
- CI triage (steering 10): the first Phase-04 push failed the headless suite — `CharacterState`
  read `template.default_goals` which `CharacterTemplateData` never declared (parse-clean,
  runtime crash). Root-caused via a one-time `::error::` diagnostic on the gate, then fixed by
  declaring `default_goals` and adding `MapCatalog.start_map_id` coverage to the catalog unit
  test; diagnostic scaffolding removed. New lesson L-018 (parse-clean ≠ fields exist).

### 2026-10-03 — Phase 03 reopen / hardening (D-022; data-driven maps, transactional transitions, real prototype art)
- **MapData is the full source of truth:** added `scene_path`, `bounds: Rect2`,
  `default_spawn_id`, and stable exit `id`s with full validation (`scene_path` exists,
  positive bounds, unique exit ids). Added a `MapCatalog` resource
  (`src/data/maps/map_catalog.gd` + `data/maps/map_catalog.tres`) that validates unique map
  ids / scene_keys and rejects dangling exits.
- **WorldRuntime is fully data-driven:** it now holds ONLY `MAP_CATALOG_PATH`, loads +
  validates the catalog, and registers `scene_key -> scene_path` with SceneRouter. The old
  hard-coded map/scene-path list is gone — adding a map is data + scene + catalog, no core
  edit.
- **Authoritative exits:** `MapExitZone` carries only `exit_id`; MapBase resolves it to the
  `MapExit` in `MapData` and emits the destination from the DATA (removes scene↔data drift).
- **Data-driven camera + spawns:** `MapBase.apply_map_data` sets Camera2D limits from
  `MapData.bounds`; spawns resolve the `default_spawn_id`, and an explicit missing
  `entry_point` now fails LOUD (no silent fallback).
- **Transactional map transitions:** `WorldRuntime._enter_map` snapshots the player and
  rolls back on router failure (player restored to the still-alive old map, active map /
  GameState unchanged, router not stuck); on success the SAME player instance persists.
- **Real prototype pixel-art (replaces Polygon2D):** self-made `player_proto.png` (16×24) +
  `prototype_tileset.png` (48×16) generated by `tools/gen_prototype_assets.py`; Player uses a
  `Sprite2D`; maps render a `TileMapLayer` via `data/maps/prototype_tileset.tres`. Nearest
  filter, mipmaps off, 16px base tile (06-art-assets.md). Walls stay static collision.
- **E2E hardened:** `world_flow_case.gd` drives interact/open_menu through the REAL input
  pipeline (`Input.parse_input_event`, no direct `_unhandled_input`), does a real movement
  step, and runs 20 round trips with per-round invariants (same player instance, one player,
  one content scene, GameState==router, camera limits, no orphan growth). Added a router
  transactional-rollback integration test. Fixed `run_app_flow.gd` stale "prologue" wording.
- Docs synced: ARCHITECTURE current state + folder, DATA_SCHEMA, GAME_FLOW (removed "no
  gameplay yet"), PERFORMANCE, ASSET_LICENSES, 06-art-assets baseline, DECISIONS (D-021
  amended + D-022 added), lessons (L-016 refined + L-017). No new autoloads; no new scope
  beyond World/Map; Phase 04 NOT STARTED.

### 2026-10-02 — Phase 03 World / Map (traversable maps; D-003 resolved)
- **Map data model (D-021):** added `MapData` + `MapExit` Resources (`src/data/maps/`), with
  validation (`is_valid()` / `validation_errors()`), and two authored maps
  `data/maps/map_hub.tres` + `data/maps/map_field.tres`. A map references its content scene
  by a stable router `scene_key: String` (not a direct `PackedScene`), keeping `MapData` a
  pure data resource — DATA_SCHEMA synced.
- **WorldRuntime (node, not autoload):** `src/gameplay/world/world_runtime.gd` hangs under
  `Main/Systems`. It builds the map catalog, registers each `scene_key` with `SceneRouter`,
  owns ONE persistent per-session Player (parked under WorldRuntime between maps so a router
  content-swap can't free it; re-parented into each map's `PlayerHost` at a named spawn),
  and resolves `request_map_transition(to_map_id, entry_point)` through SceneRouter. The
  autoload budget stays at 5 (D-017).
- **Map scenes:** `src/gameplay/maps/hub_map.tscn` + `field_map.tscn` (`MapBase` +
  `MapExitZone`). The player stands in a `MapExitZone` and presses the semantic `interact`
  action (via `InputService`, never raw keys) to request an exit; `MapBase` emits
  `exit_requested` and WorldRuntime drives the transition. `open_menu` returns to the menu.
  Walls wired from `CollisionLayers.WORLD`. Prototype art = self-made vector placeholders
  (recorded in `ASSET_LICENSES.md`, 32px base tile); real TileSet deferred to the art pass.
- **Boot wiring:** New Game now enters the hub map via WorldRuntime (`main.gd`
  `_create_world_runtime` + `start_session`/`end_session`); the Phase-02 sandbox + Phase-01
  prologue are retained but are no longer the first scene.
- **Tests + CI:** `tests/unit/world/test_map_data.gd`, `tests/integration/test_map_transitions.gd`
  (repeated transitions, no orphan-node leak), `tests/gameplay/test_map_scenes.gd`
  (structural), and the dedicated isolated E2E `tests/e2e/run_world_flow.gd` driving the real
  New Game → hub → interact → field → back → menu flow — added as a **9th CI gate**. The
  Phase-02 player E2E now instantiates the sandbox directly (New Game no longer routes to it);
  the app-flow E2E now expects `map_hub` as the first scene.
- No new scope: no Character/Combat/AI/World-Simulation/Save/Inventory/networking, no new
  autoload, no new EventBus signal (`map_entered`/`map_exited` deferred to Quest/Story —
  L-005). D-005 / D-007 remain Open; **D-003 resolved** (option a).

### 2026-10-02 — Phase 02 Final Hardening (contract/invariant/doc consistency, no new scope)
- **Semantic-input E2E (real boundary):** the player E2E (`tests/e2e/player_flow_case.gd`)
  now drives movement and attack through the actual InputMap → `InputService` → Player
  path (`Input.action_press("move_right")` / `Input.action_press("attack")`), not direct
  `MovementComponent.apply_intent` / `resolve_player_attack()` calls. Added an input-gating
  regression (attack does NOT fire in MENU context, DOES in GAMEPLAY) and a teardown that
  releases pressed actions + asserts no orphan / no duplicate autoload / legal GameState.
- **Collision single source of truth:** Player / Training Dummy / sandbox walls now set
  `collision_layer`/`collision_mask` from `CollisionLayers.*` at runtime (Player =
  PLAYER + mask WORLD|DUMMY; Dummy = DUMMY, mask 0; walls = WORLD). Added an integration
  test that fails if the constants and runtime wiring drift.
- **MovementComponent contract:** `apply_intent(intent, speed, _delta := 0.0)` — the
  Phase-02 contract's `delta` is explicit but intentionally unused (`move_and_slide` owns
  physics integration; no `velocity * delta`). Player passes `delta`; tests updated.
- **Health death/reset invariant made consistent:** reworded from "`died` once, ever" to
  "`died` once PER LIFE (per `initialize()` cycle)", matching `TrainingDummy.reset_dummy()`
  (a new life can die again). Added regression tests (no duplicate `died` within a life;
  re-initialize → second-life death). No resurrection added.
- **Stats fail-closed:** `Player._ready()` / `TrainingDummy._ready()` now branch on
  `StatsComponent.validate()`; an invalid/missing StatBlock reports loudly and the entity
  stays inert (Player disables physics) instead of half-running. `validate()` no longer
  `assert()`-aborts (loud `push_error` + checked return is the robust fail-loud-and-closed
  contract). Added a fail-closed test.
- **Docs sync:** `01-product` core-systems phases 11–15 → 04–08; `SAVE_FORMAT` migration
  references Phase 17 → 23; `TEST_PLAN` status line updated to the post-Phase-02 reality.
- No new scope: no combat system, no AI, no Character/Save/Inventory/networking, no new
  autoload. D-003 / D-005 / D-007 remain Open. Sandbox remains the temporary Phase-02
  validation scene.

### 2026-10-02 — Phase 02 Player Core (first playable; no combat system)
- **Player entity (composition, D-020):** `CharacterBody2D` under `src/gameplay/entities/`
  composed of `StatsComponent` + `HealthComponent` + `MovementComponent`
  (`src/gameplay/components/`). No inheritance chain, no God object; `player.gd` only
  coordinates (reads semantic intent, forwards movement, exposes an attack intent). Reads no
  physical keys — input flows only through `InputService`.
- **Top-down movement:** 8-direction, diagonals normalized (not faster than cardinal),
  collision-aware via `move_and_slide`, speed from stats. `MovementComponent.apply_intent`
  is the intent boundary a future network command reuses (MP seam).
- **Stats as data:** `StatBlock` Resource (`src/data/stats/stat_block.gd`, DATA_SCHEMA §1
  field names) with authored numbers in `data/stats/player_stats.tres` /
  `training_dummy_stats.tres`. Invariants validated at the boundary.
- **Health:** enforced invariants (`0<=hp<=max`), `apply_damage`/`heal` return applied
  amount, non-positive rejected, `died` emitted exactly once, DEAD terminal (no revive).
  Direct signals to owner; no new EventBus signals.
- **Minimal damage rule (NOT a combat system):** one pure domain function
  `src/domain/combat/damage_rules.gd` — a deterministic slice of the DATA_SCHEMA §2 formula
  (no RNG/crit/resist/skill/equipment). D-007 (combat timing) stays Open.
- **Training Dummy:** `StaticBody2D` reusing the same Stats/Health components, no AI, no
  movement, `reset_dummy()`; deterministic retaliation driven by the sandbox coordinator.
- **Player Sandbox (temporary first scene):** `src/gameplay/sandbox/player_sandbox.tscn` —
  Player + Dummy + walls + camera + localized HUD. New Game now routes here
  (`FIRST_SCENE_KEY` in `main.gd`) instead of the prologue shell; documented as a Phase-02
  gameplay-validation scene that Phase 03 replaces. Coordinator owns the range check + the
  bidirectional damage exchange via the domain rule.
- **Collision layers** named constants (`src/gameplay/collision_layers.gd`).
- **Localization:** added `UI_SANDBOX_HINT` / `UI_SANDBOX_PLAYER_HP` / `UI_SANDBOX_DUMMY_HP`
  (vi + en).
- **Tests:** unit (damage rule, health invariants + death-once, movement math, stat
  validation), integration (player wiring + real-physics movement + bidirectional damage
  exchange, fresh instances), gameplay smoke (sandbox structural, no Main boot), and a
  dedicated isolated **player E2E** process (`tests/e2e/run_player_flow.gd` +
  `player_flow_case.gd`) — New Game → sandbox → move → attack → death → cleanup. CI gained an
  8th gate for it; `test_app_flow` updated to expect `player_sandbox` as the first scene.
- No combat system, no AI, no inventory/equipment/skill/cultivation, no save/load, no
  networking, no new autoloads. D-003 / D-005 / D-007 remain Open.

### 2026-10-02 — Phase 01 Test Isolation + Boot Contract Hardening (no gameplay)
- **Fixed — cross-test singleton contamination (D-019):** the previous
  `tests/integration/test_app_flow.gd` spawned duplicate `/root` autoloads and booted Main
  on the REAL `GameState` autoload, leaving it at `RUNNING`. A later in-runner boot then hit
  `illegal transition RUNNING -> INITIALIZING`. Removed that test; the real-application E2E
  now runs in its **own isolated Godot process** (`tests/e2e/run_app_flow.gd` +
  `tests/e2e/app_flow_case.gd`), using the ACTUAL project autoloads and driving the real
  `MainMenu.new_game_pressed` intent — no duplicate autoloads, nothing to contaminate.
- **Added — isolation guard in `tests/run_tests.gd`:** snapshots the shared
  `/root/GameState` phase and FAILS the suite if any test leaves it changed (detection, not
  reset). `tests/e2e/` is excluded from in-runner discovery.
- **Changed — smoke test is structural-only:** `tests/smoke/test_boot.gd` no longer boots
  Main into the shared tree; it validates the static Systems/World/UI shell without running
  the lifecycle. The real boot contract is asserted by the E2E process.
- **Changed — Main requires all 5 autoloads (D-019):** `REQUIRED_AUTOLOADS` =
  EventBus, GameState, Localization, InputService, SceneRouter. Missing any → fail loud,
  abort boot, no silent fallback. Removed the "zero autoloads = tolerate" escape.
- **Changed — Main checks every required lifecycle bool:** `begin_initialization`,
  `mark_ready`, `enter_menu`, `confirm_session_running`. A rejected `confirm_session_running`
  now unwinds to menu instead of faking RUNNING.
- **CI:** added a 7th gate running the dedicated E2E process; no swallowed exit codes.
- **Docs:** D-019 added; TEST_PLAN updated (runner has project autoloads; isolation
  boundary; E2E own process); lesson L-010 recorded. No gameplay, no networking, no Phase 02
  (Config/RNG/SaveService still deferred per D-017).

### 2026-10-02 — Phase 01 Final Hardening (close contract/test/invariant gaps, no gameplay)
- **Fixed — GameState persistence invariant (D-018):** `to_dict()` now serializes only run
  identity + location (never `session_active`, never the lifecycle phase) and returns `{}`
  when no session is active. Loading moved to `hydrate_session(data)` (data-only; does not
  drive the lifecycle) which rejects an invalid snapshot (no `run_id`) and an unsafe phase
  (only `MENU`/`READY`); `from_dict()` is now a `bool`-returning alias. This removes the
  previously-possible invalid `phase==BOOT && session_active==true` reload state.
- **Fixed — magic input ints (D-018):** added semantic `InputService.set_gameplay_context()`
  / `set_menu_context()` / `push_modal_context()`; the raw stack reset is now private
  `_reset_to()`. Menu + first scene no longer pass enum ints.
- **Fixed — input ownership (D-018):** `prologue_shell` resolves `open_menu` via
  `InputService.is_system_action_just_pressed(&"open_menu")` instead of reading the raw
  input event.
- **Fixed — boot fail-fast (D-018):** `Main` aborts boot loudly if a required core autoload
  (`GameState`/`SceneRouter`/`EventBus`) is missing in a real run (headless test harness,
  with zero autoloads, still runs the null-safe path); `_boot()` checks transition results.
- **Removed — speculative EventBus signals (D-018):** `new_game_requested`,
  `session_started`, `session_ended` (no real producer+consumer in Phase 01). Kept
  `game_booted`, the three `scene_transition_*`, and `language_changed`.
- **Tests added/updated:** GameState persistence-invariant suite; InputService semantic
  setters; SceneRouter failure/cleanup cases A–F; EventBus "holds no business state"; and a
  real end-to-end `tests/integration/test_app_flow.gd` that stands up the actual autoloads,
  instantiates `main.tscn`, drives the real `MainMenu.new_game_pressed`, and asserts a
  RUNNING session with the prologue content scene loaded (then tears down with no orphans).
- **Docs:** ROADMAP Phase 01 → CLOSED, Phase 02 NOT STARTED; corrected the one-off
  `2026-10-03` → `2026-10-02` date across docs; D-018 added. No gameplay, no networking,
  no Phase 02 work (Config/RNG/SaveService still deferred per D-017).

### 2026-10-02 — Phase 01 Core Framework (runtime skeleton, no gameplay)
- **Lifecycle + session:** `GameState` autoload — explicit lifecycle state machine
  (`BOOT→INITIALIZING→READY→MENU→STARTING_SESSION→RUNNING→TRANSITIONING/PAUSED`), runtime
  session state (run_id, current world/map/scene ids), intent-revealing methods, illegal
  transitions rejected loudly, `to_dict/from_dict` seam, no disk I/O, no presentation refs.
- **EventBus** autoload — minimal cross-system signals for Phase 1 only (boot, scene
  transition, language). Emitters never reference listeners. *(Speculative session signals
  removed in the hardening pass — see D-018.)*
- **Localization** autoload — vi/en via a CSV table (`locale/aetheria.csv`), `t()`/`t_args()`
  with `{placeholder}` substitution, `set_language/get_language`, missing-key returns the
  key + warns. Backing format decided (D-008: CSV).
- **InputService** autoload — semantic input intent over named InputMap actions + input
  gating ownership (context stack UI_MODAL > MENU > GAMEPLAY). No physical-key leakage.
- **SceneRouter** autoload — the single scene-transition entry point; swaps content under
  `Main/World`, guards duplicate/stale/invalid/leak, explicit success/failure, records
  location in GameState. Keeps map strategy open (D-003).
- **Semantic InputMap** in `project.godot`: move_up/down/left/right, interact, attack,
  skill_1..4, dodge, open_menu, pause.
- **Presentation shells:** localized main menu (New Game / Quit; Load Game disabled) and a
  non-gameplay first-scene (`prologue_shell`) proving router + gamestate + input ownership.
- **Bootstrap** `main.gd` rewired as a thin coordinator (BOOT → MENU → New Game → first
  scene) — not a God object.
- **Autoloads justified** in `DECISIONS.md` D-017 (5 autoloads; Config/RNG/SaveService
  deliberately deferred). **D-008 Accepted** (CSV).
- **Roadmap reordered** to 35 phases (00–34): Character/Relationship/Sect/Faction/World-Sim
  moved to 04–08 (before Combat 09); Save→23; Multiplayer→32–34. Phase-number references in
  `DECISIONS.md` blocking lines updated (D-003→03, D-005→23, D-007→09, D-008→01/24).
- **Tests:** `tests/unit/core/` (GameState, SceneRouter, EventBus, Localization,
  InputService) + `tests/integration/test_boot_flow.gd` (boot→menu→new game→first scene).
- No gameplay, no networking.

### 2026-10-02 — Phase 0 CLOSED (documentation close-out, no gameplay)
- **Foundation hardening verified by CI.** GitHub Actions job "Foundation gates
  (Godot 4.7)" ran on commit `651c16f` with `conclusion=success` (confirmed via the
  GitHub check-runs API).
- **Runtime boot smoke — verified by CI:** project boots `application/run/main_scene`,
  `Main._ready()` runs, clean exit (`--quit-after 2`).
- **Parse check — verified by CI:** `tools/parse_check.gd` found no GDScript parse errors.
- **Headless test suite — verified by CI:** `tests/run_tests.gd` ran green (`RESULT: PASS`).
- **Phase 0 → READY FOR PHASE 1.** `docs/PHASE_0_EXIT_CHECKLIST.md` all blocking items
  [x]; `docs/ROADMAP.md` Phase 0 marked CLOSED, Phase 1 (Core) is next and not started.
- **Docs synced to verified state:** D-012 marked Accepted & verified; D-009 clarified
  (local-agent limitation only, CI ran Godot for real); removed "pending CI"/"first green
  run" wording across ROADMAP/checklist.
- No gameplay, no Phase 1 work.

### Changed / Added — 2026-10-02 — Foundation hardening (Phase 0, no gameplay)
- **Smoke test now really boots:** `tests/smoke/test_boot.gd` adds Main to the live
  SceneTree (runs `_ready`), asserts `is_inside_tree` + Systems/World/UI + bootstrap
  self-validation, cleans up with no orphan nodes; added a negative structure test.
- **Test runner hardened:** `tests/run_tests.gd` rewritten — recursive (nested) discovery,
  deterministic order, SceneTree injection, `await` per method, non-zero exit on
  fail/empty/missing-required. `tests/framework/test_case.gd` gained SceneTree helpers.
- **Nested-discovery + fail-detection proof:** `tests/unit/framework/test_nested_discovery.gd`.
- **Project-wide parse check:** `tools/parse_check.gd` (loads every `.gd` under
  src/tests/tools; CI gate).
- **CI hardened:** `.github/workflows/ci.yml` — removed `|| true`; gates checkout → Godot
  4.7 → import → parse check → runtime boot (`--quit-after 2`) → test suite; no swallowed
  failures.
- **Hooks split (D-016):** PostFileSave runs the lightweight parse check;
  `run-full-tests-on-task.json` (PostTaskExec) runs the full suite.
- **Authority contract (D-015):** sect membership canonical source = `SectState` roster;
  `CharacterState` sect fields are a derived cache. Annotated across CHARACTER/SECT/
  DATA_SCHEMA/SAVE_FORMAT.
- **Doc consistency:** fixed stale "empty `main.tscn`"/"no scripts" (ARCHITECTURE),
  "3D physics enabled" (01-product), and "pending first green CI" (ROADMAP); logged in
  DECISIONS D-013 (items 5–7).
- **New:** `docs/PHASE_0_EXIT_CHECKLIST.md` (gates Phase 0 → READY FOR PHASE 1 on a green CI).

### Changed / Added — 2026-10-02 — Foundation review + fix (Phase 0 completion, no gameplay)
- **Project identity:** `config/name` `New_Game_Project` → `Aetheria` (D-006 Accepted).
- **2D config cleanup:** removed the `[physics]` section (3D `Jolt Physics` leftover) —
  game is 2D-only (D-002 Accepted). Added `textures/canvas_textures/default_texture_filter=0`
  (nearest, for pixel art). Set `run/main_scene="res://main.tscn"`.
- **Bootstrap:** `main.tscn` is now a real bootable scene — `Main` (`Node2D`, script
  `src/bootstrap/main.gd`) with `Systems` / `World` / `UI` children (D-010).
- **Test framework (D-004 Accepted → custom headless runner):**
  `tests/framework/test_case.gd` (`TestCase` + `assert_*`), a real `tests/run_tests.gd`
  (discovers `test_*.gd`, non-zero exit on failure), and a real smoke test
  `tests/smoke/test_boot.gd`. Removed the placeholder behavior and `smoke/.gdkeep`.
- **Core-system design (design only, no gameplay):** new docs `CHARACTER_SYSTEM.md`,
  `RELATIONSHIP_SYSTEM.md`, `SECT_SYSTEM.md`, `WORLD_SIMULATION.md`; updates to
  `GAME_FLOW`, `DATA_SCHEMA`, `MULTIPLAYER_PLAN`, `ROADMAP`, and steering 01/02/03 to make
  Character / Relationship / Sect / Faction / World-Simulation core systems (D-011).
- **CI:** added `.github/workflows/ci.yml` (checkout → Godot 4.7 → import → headless
  tests) (D-012).
- **AI review protocol:** added the `READ → PLAN → IMPLEMENT → TEST → REVIEW → DOCS` loop
  and pre-completion review gates.
- **Decisions resolved:** D-002, D-004, D-006 → Accepted; added D-009 (local Godot
  unavailable to agent), D-010, D-011, D-012, D-013 (doc-review findings).

### Known limitation — 2026-10-02
- The AI agent could not run Godot headless locally (no binary on PATH / common dirs /
  registry — D-009). All scripts validated via the GDScript language server (zero errors);
  authoritative headless run is CI. Manual command:
  `godot --headless --path . -s res://tests/run_tests.gd`.

### Added — 2026-10-02 — Project foundation (docs & process, no gameplay)
- Steering rules in `.kiro/steering/`:
  `01-product`, `02-game-design`, `03-architecture`, `04-coding-standards`,
  `05-performance-testing`, `06-art-assets`, `07-localization`,
  `08-ai-review-protocol`.
- Core docs in `docs/`:
  `GAME_FLOW` (central flow + per-system contracts), `ARCHITECTURE` (layered design),
  `ROADMAP` (22 phases, Foundation → Multiplayer preparation), `TEST_PLAN`,
  `PERFORMANCE`, `ASSET_LICENSES`, `DATA_SCHEMA`, `SAVE_FORMAT`, `MULTIPLAYER_PLAN`,
  `DECISIONS`, `DEBUGGING`, and this `CHANGELOG`.
- `tests/` scaffold: `unit/ integration/ gameplay/ smoke/ performance/`, a `README`,
  and a placeholder headless runner `run_tests.gd`.

### Noted / flagged (from repo audit) — 2026-10-02
- Project still named `New_Game_Project` (rename to `Aetheria` planned — `DECISIONS.md`
  D-006).
- 3D physics engine (`Jolt Physics`) enabled on a 2D game — flagged for cleanup
  (`DECISIONS.md` D-002).
- `icon.svg` is the stock Godot placeholder icon — `ASSET_LICENSES.md`; replace before
  release.
- Open decisions pending: test framework (D-004), map strategy (D-003), save format
  (D-005), combat timing model (D-007), localization format (D-008).

### Not done (by design, as of 2026-10-02)
- No gameplay implemented. `main.tscn` was a single empty `Node2D`.
  *(Superseded 2026-10-02: `main.tscn` is now a non-gameplay bootstrap scene — see the
  2026-10-02 entry above.)*
- No networking / multiplayer code.

---

## How to update
- Add changes under **[Unreleased]** grouped as Added / Changed / Fixed / Removed /
  Deprecated / Security.
- When a build is cut, replace **[Unreleased]** with a version + date and start a fresh
  Unreleased section.
- Keep entries short and factual; link to `DECISIONS.md` / `PERFORMANCE.md` for detail.
