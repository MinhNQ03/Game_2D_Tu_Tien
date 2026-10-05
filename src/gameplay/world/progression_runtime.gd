extends Node
class_name ProgressionRuntime
## ProgressionRuntime — Aetheria gameplay (the per-session progression seam, Phase 11).
##
## It owns the three things a progression loop needs and nothing else: the authored
## `ProgressionCurveData`, the `ProgressionService` bound to it, and the subscription to
## combat's defeat announcement. It holds no progression VALUE — the authority for that is
## `CharacterState.xp` — and it resolves no hit, spawns nothing and draws nothing.
##
## A NODE UNDER `Main/Systems`, NOT AN AUTOLOAD (D-017). The autoload budget is frozen at
## five. This one is justified as a node, and the justification is lifetime: a global
## progression seam would survive a return to the menu still holding the previous run's
## service, curve and reward ledger, and still connected to a `CombatRuntime` that no longer
## exists. It is the SEVENTH sibling of `WorldRuntime` / `RelationshipRuntime` /
## `SectRuntime` / `FactionRuntime` / `WorldSimulationRuntime` / `CombatRuntime`, and it is
## registered LAST in `Main.SESSION_START_ORDER` because it READS the player's
## `CharacterState` (the world session) and LISTENS to combat (the combat session). Teardown
## is the exact reverse, so this stops listening FIRST — before the signal's emitter is torn
## down underneath it.
##
## WHY A RUNTIME AT ALL, rather than letting combat call a service. Combat announcing and
## progression listening keeps the dependency pointing the right way: `CombatRuntime` must not
## know that a level exists, must not hold a reference to the player's `CharacterState`, and
## must not own permanent character state behind a per-session system
## (`03-architecture.md`; §5 of the phase brief says the same three things). Something has to
## sit between "a creature died" and "the player's XP changed", own the curve, and decide
## which events that deserves — and that something has a session lifetime, so it is a node
## here beside its siblings rather than a free function nobody owns.
##
## FAIL CLOSED, LIKE EVERY OTHER SESSION STARTER (L-025). `start_session()` builds into LOCALS
## and commits only when every step has succeeded, so a rejected start leaves nothing
## observable: `is_session_active()` stays false, the view reads unavailable, and no signal is
## connected. There is no "warn and keep going" path — a half-built progression session is a
## game where some kills pay and others silently do not.

## XP was granted (Phase 11). Carries the amount and the identity of what paid it.
##
## A GAMEPLAY fact: no localized string, no UI data, no animation parameter
## (§7 of the phase brief). Presentation reacts by re-reading the pushed `ProgressionView`;
## a future quest/story consumer can count kills or XP from this without the progression
## service knowing either exists.
signal xp_gained(amount: int, reward_id: StringName)

## The player's level changed. ONE emission per grant, carrying the whole transition.
##
## A grant big enough to cross three thresholds emits this ONCE with `previous` three below
## `current` — not three times. The intermediate levels were never states the character was
## in: `ProgressionService.grant_xp` commits a single integer, so there is no instant at which
## the character "was" level 2 on the way to 4. Emitting a sequence would invite a listener to
## react to a state that never existed (a future "reach level 3" trigger firing mid-grant for
## a player who went 1 → 4), and the phase brief §14 requires this choice to be deliberate and
## documented. It is: one coherent transition.
signal level_changed(previous: int, current: int)

## Where the authored curve lives. A path rather than a preloaded resource, so retuning
## progression is editing content and the runtime fails LOUD if the content is missing —
## the same shape as `FactionRuntime`'s catalog path.
const CURVE_PATH := "res://data/progression/player_progression_curve.tres"

var _service: ProgressionService = null
var _character: CharacterState = null
var _combat: Node = null
var _session_active: bool = false

## Reward ids already paid, so one defeat cannot pay twice however the event arrives.
##
## THIS IS THE AUTHORITY'S GUARD, and it is the one §9 is about: duplicate protection belongs
## with the single owner of the mutation, not scattered across consumers. `CombatRuntime` also
## refuses to announce one spawn twice, which stops a double EMISSION; this stops a double
## GRANT whatever the delivery path was (a signal connected twice, a replayed event, a future
## server message arriving again).
##
## Keyed by the per-SPAWN reward id, so clearing a map and re-fighting it pays again — the ids
## are new. It grows by one entry per kill for the life of the session, which is bounded by
## how much the player actually kills and is dropped entirely on `end_session()`.
var _granted: Dictionary = {}


## Start the progression session.
##
## `character` is the player's authoritative `CharacterState` (the progression subject), and
## `combat` is the live `CombatRuntime` whose defeats fund it. Returns true only when
## progression is actually live and listening.
##
## It takes the player's state DIRECTLY rather than a character registry + resolver, unlike the
## sect and faction sessions. That is deliberate and minimal: the player is the only
## progression subject that exists, and a resolver would be generality with no second caller
## (L-005). The day NPCs level, this takes the registry — the service already works on any
## `CharacterState` and would not change.
func start_session(character: CharacterState, combat: Node) -> bool:
	if _session_active:
		push_error("[progression-rt] start_session called while a session is already active")
		return false
	if character == null:
		return _fail_start("no player CharacterState was supplied")
	if combat == null or not is_instance_valid(combat):
		return _fail_start("no CombatRuntime was supplied, so no defeat could ever fund XP")
	if not combat.has_signal("enemy_defeated"):
		return _fail_start("the supplied CombatRuntime has no 'enemy_defeated' signal")
	if not ResourceLoader.exists(CURVE_PATH):
		return _fail_start("the authored progression curve is missing: %s" % CURVE_PATH)
	var curve := load(CURVE_PATH) as ProgressionCurveData
	if curve == null:
		return _fail_start("%s did not load as a ProgressionCurveData" % CURVE_PATH)
	if not curve.is_valid():
		# The curve reports its own problems loudly; this names the consequence.
		return _fail_start("the authored progression curve '%s' is invalid"
			% String(curve.id))
	var service := ProgressionService.new(curve)
	if not service.is_ready():
		return _fail_start("the ProgressionService refused the authored curve")

	# Commit: every step succeeded, so the session becomes observable all at once.
	_service = service
	_character = character
	_combat = combat
	_granted = {}
	_session_active = true
	combat.connect("enemy_defeated", grant_for_defeat)
	return true


## Report a refused start and leave the runtime EXACTLY as it was.
##
## Nothing above assigns to a field until every check has passed, so this only has to report —
## the difference between failing closed and cleaning up after failing (L-025).
func _fail_start(reason: String) -> bool:
	push_error("[progression-rt] progression session NOT started: %s" % reason)
	return false


## End the session: stop listening, then drop everything.
##
## Disconnecting FIRST is the point. A defeat announced during teardown would otherwise be
## granted into a `CharacterState` the world session is in the middle of freeing.
## Idempotent: ending a session that never started is a no-op, which is what makes the shared
## teardown path safe to run after an aborted boot.
func end_session() -> void:
	if _combat != null and is_instance_valid(_combat) \
			and _combat.is_connected("enemy_defeated", grant_for_defeat):
		_combat.disconnect("enemy_defeated", grant_for_defeat)
	_combat = null
	_service = null
	_character = null
	_granted.clear()
	_session_active = false


func is_session_active() -> bool:
	return _session_active


## The session's progression service, or null outside a session.
func get_service() -> ProgressionService:
	return _service


## The progression subject (the player's CharacterState), or null outside a session.
func get_character() -> CharacterState:
	return _character


## How many distinct defeats have been paid this session. A read-only window for tests and the
## debug overlay, the same shape as `CombatRuntime.armed_count()`.
func granted_count() -> int:
	return _granted.size()


## A read-only snapshot for the HUD. Always a valid object; `available` is false outside a
## session, so the caller never null-checks.
func build_view() -> ProgressionView:
	if not _session_active:
		return ProgressionView.make_empty()
	return ProgressionView.make(_service, _character)


## A creature was defeated: pay for it, ONCE, and publish what changed.
##
## This is the ONLY place in the project that calls `grant_xp`, which is what makes "one
## mutation path" checkable rather than aspirational.
##
## PUBLIC, and named for its role rather than for the signal it happens to be connected to.
## Three reasons: a test can drive the idempotency ledger and the no-session guard directly
## instead of reaching for a `_`-prefixed handler across files (which the linter flags, GD002);
## "here is a defeat, handle it" is the honest shape of this runtime's inbound surface; and it
## is the exact seam a future authoritative server would call when a defeat arrives over the
## wire rather than from a local signal. It is NOT a general XP mutator — the amount comes
## from authored content and every call goes through the ledger and the service.
func grant_for_defeat(reward_id: StringName, xp_reward: int) -> void:
	if not _session_active:
		# A defeat arriving outside a session is a wiring fault (the signal should have been
		# disconnected), and paying it would write into a state nothing owns.
		push_error("[progression-rt] a defeat arrived with no active session; ignored")
		return
	var key := String(reward_id)
	if key == "":
		# FAIL CLOSED on a missing identity (D-055). The ledger is keyed by this string, so an
		# empty id is not merely "a reward with no name" — it is a key that EVERY malformed
		# defeat would share. The first one would be paid and would then occupy `""`, so the
		# ledger would report "already granted" for every later malformed defeat and the
		# duplicate-protection the ledger exists to provide would be reporting on a collision
		# rather than on an identity. Rejecting before the ledger is touched keeps the
		# contract "one distinct creature, one payment" true: no XP, no event, no entry.
		#
		# Loud rather than silent (unlike the duplicate branch below): a duplicate is normal
		# and survivable, whereas an unnamed reward means the spawn path failed to mint an id,
		# which is a wiring fault that would otherwise cost the player XP invisibly.
		push_error("[progression-rt] a defeat arrived with an EMPTY reward id; rejected "
			+ "(xp_reward=%d). Nothing was granted and the ledger was not touched." % xp_reward)
		return
	if _granted.has(key):
		# Not an error: the whole point of the ledger is that this is survivable. Silent,
		# because a duplicate that is correctly ignored is not a problem to report.
		return
	# Recorded BEFORE the grant, so a re-entrant delivery during the grant cannot slip past.
	_granted[key] = true
	var result := _service.grant_xp(_character, xp_reward)
	if not result.accepted:
		# A rejected grant is still "handled" — it must not be retried, or a creature killed
		# at the level ceiling would re-attempt on every subsequent delivery.
		return
	if result.xp_applied > 0:
		xp_gained.emit(result.xp_applied, reward_id)
	if result.leveled():
		level_changed.emit(result.level_before, result.level_after)
