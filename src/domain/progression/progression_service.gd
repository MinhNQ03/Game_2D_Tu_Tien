extends RefCounted
class_name ProgressionService
## ProgressionService — Aetheria domain (THE one authoritative mutator of XP and level).
##
## PURE DOMAIN: no Node, no tree, no signals, no presentation. It takes a `CharacterState` and
## an authored `ProgressionCurveData` and answers progression questions; `ProgressionRuntime`
## is the gameplay-layer owner that subscribes to combat and publishes events from the results
## this returns. That split is what keeps every rule here headless-testable
## (`05-performance-testing.md`: unit-test pure domain logic).
##
## ---------------------------------------------------------------------------
## THE AUTHORITY CONTRACT
## ---------------------------------------------------------------------------
##   STATE      `CharacterState.xp` — cumulative lifetime XP. The ONLY stored progression
##              number. There is no stored level anywhere in the project.
##   OWNER      `CharacterState` (persistent tier, serialized in `to_dict`/`from_dict`).
##   MUTATOR    **this service, and nothing else.** `grant_xp()` is the only function in the
##              repository that writes `CharacterState.xp`.
##   READERS    `ProgressionRuntime` (builds the view + events), presentation via the
##              read-only `ProgressionView` DTO. Neither ever writes.
##   EVENTS     emitted by `ProgressionRuntime` from a `ProgressionResult` — never here.
##   PERSISTENCE `CharacterState.to_dict()` / `from_dict()`; level is re-derived on load.
##   UI         reads the DTO. The HUD holds no progression truth and mutates nothing.
##
## ---------------------------------------------------------------------------
## WHY LEVEL IS DERIVED, NOT STORED
## ---------------------------------------------------------------------------
## Level is a pure function of (cumulative XP, curve), so it is computed on demand rather than
## stepped alongside the XP. The payoff is structural, not stylistic:
##
##   * **Atomicity is free.** A commit writes exactly ONE integer. There is no window in which
##     XP has been updated and level has not, so a "half-committed" progression state is not
##     something this code has to avoid — it is something it cannot express (compare L-025,
##     where a multi-field session starter had to be restructured to get the same guarantee).
##   * **Two numbers cannot disagree.** A stored level is a second source of truth that every
##     future path touching XP must remember to maintain; the first one that forgets writes a
##     save file whose level contradicts its XP. This project already removed that exact shape
##     of duplication once (D-015, sect membership) and recorded the general preference for a
##     derived value in L-032.
##   * **Monotonicity is inherent.** XP only ever increases, and the derivation is monotonic,
##     so level can never go down — no guard needed.
##
## The derivation walks at most `xp_to_next.size()` steps (about twenty), and it runs on an XP
## CHANGE, never per frame. `02-game-design.md`'s "no per-frame progression polling" is
## satisfied by construction: nothing here has a `_process`.
##
## ---------------------------------------------------------------------------
## WHAT THIS SERVICE DELIBERATELY CANNOT DO
## ---------------------------------------------------------------------------
## It exposes no content ids, no unlock list and no gate query, because **level is never an
## access condition** (C-002, `02-game-design.md`). A later system asking "may the player
## enter here" must ask the realm/knowledge/quest owner, never this. Level is also NOT cảnh
## giới (`docs/PROGRESSION_CULTIVATION_DESIGN.md` §1): Phase 12 adds the realm axis beside
## this one, and nothing here should be mistaken for it or reused as it.

var _curve: ProgressionCurveData = null


## Bind the authored curve. A null or invalid curve leaves the service NOT READY, so the
## owner fails closed instead of running a session with a progression ramp nobody authored.
## `source_curve` is named to avoid shadowing the `curve()` accessor below — GDScript reports
## a parameter shadowing a method as a warning, and this project treats warnings as errors.
func _init(source_curve: ProgressionCurveData = null) -> void:
	if source_curve == null:
		return
	if not source_curve.is_valid():
		push_error("[progression] refusing an invalid curve '%s': %s" % [
			String(source_curve.id), str(source_curve.validation_errors())])
		return
	_curve = source_curve


## True once a valid curve is bound. The owner checks this before committing to a session.
func is_ready() -> bool:
	return _curve != null


## The bound curve (read-only use: the runtime builds its view from it).
func curve() -> ProgressionCurveData:
	return _curve


## The level a character has reached, derived from their cumulative XP.
##
## Returns 0 with no curve — a deliberately impossible level, so a caller that skipped
## `is_ready()` gets an obviously-wrong number instead of a plausible `1` that would hide the
## wiring mistake.
func level_of(state: CharacterState) -> int:
	if _curve == null or state == null:
		return 0
	return _curve.level_for_xp(state.xp)


## XP earned inside the current level (the numerator of the progress meter).
func xp_into_level(state: CharacterState) -> int:
	if _curve == null or state == null:
		return 0
	return _curve.xp_into_level(state.xp)


## XP the current level costs in total (the denominator). 0 at the ceiling, where there is no
## next level to cost anything.
func xp_for_next_level(state: CharacterState) -> int:
	if _curve == null or state == null:
		return 0
	return _curve.cost_from(_curve.level_for_xp(state.xp))


## Progress toward the next level in [0, 1]; 1.0 at the ceiling (see `ProgressionCurveData`).
func progress_fraction(state: CharacterState) -> float:
	if _curve == null or state == null:
		return 0.0
	return _curve.progress_fraction(state.xp)


## Is this character at the top of the authored curve?
func is_at_ceiling(state: CharacterState) -> bool:
	if _curve == null or state == null:
		return false
	return _curve.is_ceiling(_curve.level_for_xp(state.xp))


## THE MUTATION PATH. Grant `amount` XP and report exactly what happened.
##
## Order is validate -> compute -> commit, and nothing is written until every check has
## passed, so a rejected grant leaves the character byte-identical (L-025's fail-closed shape,
## made trivial here by there being one field to write).
##
## Accepts a ZERO grant as a legal no-op (a reward of 0 is authored content, not an error) and
## REJECTS a negative one: XP is monotonic by design, and a negative grant is either a bug or
## a corrupted reward, neither of which should quietly reduce a player's progress.
##
## At the ceiling the grant is REJECTED with `REASON_AT_CEILING` rather than silently
## swallowed, so the caller can tell "there was nothing left to earn" apart from "it worked".
## Accumulating XP past the last authored level would grow a number that progresses toward
## nothing.
func grant_xp(state: CharacterState, amount: int) -> ProgressionResult:
	if state == null:
		push_error("[progression] grant_xp with a null CharacterState")
		return ProgressionResult.rejected(ProgressionResult.REASON_NO_STATE, 0, 0)
	if _curve == null:
		push_error("[progression] grant_xp with no bound curve")
		return ProgressionResult.rejected(ProgressionResult.REASON_NO_CURVE, state.xp, 0)

	var xp_before := state.xp
	var level_before := _curve.level_for_xp(xp_before)

	if amount < 0:
		push_error("[progression] refusing a negative XP grant (%d)" % amount)
		return ProgressionResult.rejected(
			ProgressionResult.REASON_NEGATIVE_AMOUNT, xp_before, level_before)
	if _curve.is_ceiling(level_before):
		# Not an error: reaching the top of the curve is a legitimate end state, so this is
		# reported rather than pushed as an error.
		return ProgressionResult.rejected(
			ProgressionResult.REASON_AT_CEILING, xp_before, level_before)

	# Compute the whole outcome before touching the state.
	var xp_after := xp_before + amount
	var level_after := _curve.level_for_xp(xp_after)

	# COMMIT — one integer, one call, through the state's own narrow setter so the clamp and
	# the invariant live with the field rather than here.
	state.set_total_xp(xp_after)

	return ProgressionResult.committed(xp_before, state.xp, level_before, level_after)
