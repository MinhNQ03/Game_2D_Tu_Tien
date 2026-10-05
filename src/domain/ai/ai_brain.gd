extends RefCounted
class_name AiBrain
## AiBrain — Aetheria domain (one enemy's decision machine, Phase 10).
##
## The explicit state machine behind every enemy: `IDLE · PATROL · ALERT · CHASE · ATTACK ·
## RECOVER · RETURN`. Pure and node-free — it is handed a PERCEPTION of scalars and returns a
## STATE plus an INTENT, and it touches nothing. No position, no node, no health, no tree.
##
## WHY IT TAKES SCALARS AND RETURNS AN INTENT KIND rather than a direction vector. Two reasons,
## and the second is the one that matters:
##   * It is unit-testable with plain numbers. "At 300px away it gives up" is an assertion, not
##     a scene.
##   * **It is the multiplayer seam.** AI becomes `DECISION → INTENT → gameplay resolution`,
##     exactly as player input is `INPUT → INTENT → gameplay resolution`
##     (`MULTIPLAYER_PLAN.md` §3). A brain that returned world vectors would be deciding and
##     resolving at once, which is what makes an AI impossible to move server-side later.
## The component converts an intent kind into a vector using real positions; the brain never
## learns where anything is.
##
## DETERMINISM. The only nondeterministic choice is the patrol direction, drawn from an
## injected seeded `RngStream`. Same seed + same perception sequence → same behaviour, which is
## the Phase-10 requirement and the reason there is no `randf()` here.
##
## WHAT IT DOES NOT DO: it never mutates health, never computes damage, never touches quest,
## relationship, sect or faction state, and never calls a service. It answers one question —
## "what should this creature be doing?" — and the component does it.

## The states. Deliberately seven, each with a reason to exist; the first real creature uses
## all of them. Adding an eighth needs a creature that proves it is needed
## (`03-architecture.md`: no speculative generality).
enum State {
	IDLE,     ## no target, standing still — the resting state
	PATROL,   ## no target, wandering near home — makes an idle creature look alive
	ALERT,    ## just noticed a target, pausing — the TELEGRAPH that it saw you
	CHASE,    ## closing on a target
	ATTACK,   ## in range and swinging
	RECOVER,  ## backing off after a swing — the signature of this archetype
	RETURN,   ## target lost or leash exceeded, going home
}

const STATE_NAMES := [
	"IDLE", "PATROL", "ALERT", "CHASE", "ATTACK", "RECOVER", "RETURN",
]

## What the component should DO this tick. The brain's whole output vocabulary.
enum Intent {
	HOLD,          ## stand still
	WANDER,        ## drift in the brain's chosen patrol direction
	APPROACH,      ## move toward the target
	BACK_OFF,      ## move away from the target
	RETURN_HOME,   ## move toward the spawn point
	SWING,         ## request an attack (and hold position)
}

const INTENT_NAMES := [
	"HOLD", "WANDER", "APPROACH", "BACK_OFF", "RETURN_HOME", "SWING",
]

## Keys a perception dictionary must carry. A plain Dictionary rather than a class because it
## is built fresh every decision and thrown away; a Resource would be an allocation per enemy
## per decision with no behaviour to justify it.
##
##   `has_target`     bool  — a live, valid target exists
##   `target_distance` float — attacker→target distance in pixels (meaningless if no target)
##   `home_distance`  float — how far the enemy has strayed from its spawn point
##   `can_attack`     bool  — the attack component is READY (not mid-swing)
const PERCEPTION_KEYS := ["has_target", "target_distance", "home_distance", "can_attack"]

var _profile: AiProfileData = null
var _rng: RngStream = null
var _state: int = State.IDLE
## Seconds spent in the current state. The only time the brain tracks — everything else is
## derived from perception, so there is no hidden history to get out of sync.
var _elapsed: float = 0.0
## Patrol heading in radians, re-rolled from the seeded stream on entering PATROL.
var _patrol_angle: float = 0.0
## Swings completed, so a test can assert "it attacked" without listening to a signal.
var _swings: int = 0


## Bind the tuning and the seeded stream. An invalid profile or a missing stream leaves the
## brain UNARMED: it stays in IDLE and intends HOLD forever, rather than running on defaults
## that nobody authored.
func _init(profile: AiProfileData = null, rng: RngStream = null) -> void:
	if profile == null or not profile.is_valid():
		if profile != null:
			push_error("[ai] refusing an invalid AiProfileData; the brain stays unarmed")
		return
	if rng == null:
		push_error("[ai] AiBrain requires a seeded RngStream (no global rand*); unarmed")
		return
	_profile = profile
	_rng = rng


func is_armed() -> bool:
	return _profile != null and _rng != null


func state() -> int:
	return _state


func state_name() -> String:
	return STATE_NAMES[_state]


func time_in_state() -> float:
	return _elapsed


func swings() -> int:
	return _swings


## The patrol heading, in radians. The component turns this into a direction vector.
func patrol_angle() -> float:
	return _patrol_angle


## Advance the machine by `delta` and return the INTENT for this tick.
##
## `perception` is shaped by `PERCEPTION_KEYS`. A malformed perception returns `HOLD` loudly
## rather than guessing: an enemy that stands still is a visible bug; an enemy acting on
## invented perception is an invisible one.
func decide(perception: Dictionary, delta: float) -> int:
	if not is_armed():
		return Intent.HOLD
	for key in PERCEPTION_KEYS:
		if not perception.has(key):
			push_error("[ai] perception is missing '%s'; holding" % key)
			return Intent.HOLD
	_elapsed += maxf(0.0, delta)

	var has_target := bool(perception["has_target"])
	var distance := float(perception["target_distance"])
	var home := float(perception["home_distance"])
	var can_attack := bool(perception["can_attack"])

	# LEASH, checked before anything else: an enemy that has strayed too far goes home no
	# matter what it can see. Without this precedence a creature can be walked across the
	# whole map by a player who keeps backing away, and the encounter stops being local.
	if _state != State.RETURN and home > _profile.leash_radius:
		_enter(State.RETURN)
		return Intent.RETURN_HOME

	match _state:
		State.IDLE:
			if has_target and distance <= _profile.detect_radius:
				_enter(State.ALERT)
				return Intent.HOLD
			if _elapsed >= _profile.idle_seconds:
				_enter(State.PATROL)
				_roll_patrol_angle()
				return Intent.WANDER
			return Intent.HOLD

		State.PATROL:
			if has_target and distance <= _profile.detect_radius:
				_enter(State.ALERT)
				return Intent.HOLD
			if _elapsed >= _profile.patrol_seconds:
				_enter(State.IDLE)
				return Intent.HOLD
			return Intent.WANDER

		State.ALERT:
			# The pause IS the telegraph. It holds position so the player can see it noticed
			# them before it starts closing (`COMBAT_DESIGN.md` §7).
			if not has_target:
				_enter(State.RETURN)
				return Intent.RETURN_HOME
			if _elapsed >= _profile.alert_seconds:
				_enter(State.CHASE)
				return Intent.APPROACH
			return Intent.HOLD

		State.CHASE:
			if not has_target or distance > _profile.lose_interest_radius:
				_enter(State.RETURN)
				return Intent.RETURN_HOME
			if distance <= _engage_distance() and can_attack:
				_enter(State.ATTACK)
				return Intent.SWING
			return Intent.APPROACH

		State.ATTACK:
			# ATTACK is a one-tick commitment: the swing is requested and the brain moves
			# straight to RECOVER. It does NOT wait for the swing to finish, because
			# `AttackStateMachine` already owns that timing — waiting here would be a second
			# copy of the lifecycle, able to disagree with the real one.
			_swings += 1
			_enter(State.RECOVER)
			return Intent.HOLD

		State.RECOVER:
			if not has_target:
				_enter(State.RETURN)
				return Intent.RETURN_HOME
			if _elapsed >= _profile.recover_seconds:
				_enter(State.CHASE)
				return Intent.APPROACH
			# Back off only while closer than the recovery distance, so it disengages and then
			# waits rather than retreating forever. This is the archetype's signature: it does
			# not stand in your face trading hits, which is what punishes standing still.
			return Intent.BACK_OFF if distance < _profile.recover_distance else Intent.HOLD

		State.RETURN:
			# Re-acquiring on the way home is allowed, but ONLY once back inside the leash —
			# otherwise a player standing just outside it can hold the creature in a permanent
			# turn-around at the boundary.
			if has_target and distance <= _profile.detect_radius \
					and home <= _profile.leash_radius:
				_enter(State.ALERT)
				return Intent.HOLD
			if home <= HOME_ARRIVAL_PIXELS:
				_enter(State.IDLE)
				return Intent.HOLD
			return Intent.RETURN_HOME

	return Intent.HOLD


## How close it tries to get before swinging. Supplied by the component via `set_engage_distance`
## because it is a property of the CREATURE and its attack, not of the behaviour archetype.
var _engage: float = 24.0


func set_engage_distance(distance: float) -> void:
	_engage = maxf(1.0, distance)


func _engage_distance() -> float:
	return _engage


## How close to home counts as arrived. A tolerance, not a target: without one the creature
## jitters around its spawn point forever trying to land on it exactly.
const HOME_ARRIVAL_PIXELS := 8.0


func _enter(next_state: int) -> void:
	_state = next_state
	_elapsed = 0.0


## Re-roll the patrol heading from the SEEDED stream. `next_below(360)` rather than a float
## draw keeps the value integral and the stream advance identical across platforms.
func _roll_patrol_angle() -> void:
	_patrol_angle = deg_to_rad(float(_rng.next_below(360)))


## Abandon whatever it was doing and reset to IDLE.
##
## For an owner whose creature stopped being an actor — death, a map change, session teardown.
## It clears the state timer too, so a revived-by-respawn entity does not resume mid-ALERT.
func reset() -> void:
	_enter(State.IDLE)
