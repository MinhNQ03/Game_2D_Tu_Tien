extends TestCase
## Unit tests for `ProgressionRuntime` (Phase 11) — the per-session owner that turns a combat
## defeat into XP and publishes what changed.
##
## It covers the FAIL-CLOSED start (L-025: a rejected start must leave nothing observable),
## the IDEMPOTENCY ledger (§9: one defeat cannot pay twice however the event arrives), the
## EVENT semantics (one coherent `level_changed` per grant, even across several thresholds),
## and clean teardown (no connection, no state, no leak).
##
## THE EMITTER IS THE REAL `CombatRuntime` SCRIPT, instantiated but with no session started,
## and its own `enemy_defeated` signal is emitted directly. That is deliberate: a hand-written
## stub signal would let the payload drift from the real one, and this way a change to the
## signal's signature breaks these tests instead of silently passing them. It is the same
## reasoning as emitting a sensor's own signal in the world E2E (L-016).
##
## Every Node created here is freed (L-019); `CombatRuntime` and `ProgressionRuntime` both
## extend `Node`, which does not auto-release.

const RuntimeScript := preload("res://src/gameplay/world/progression_runtime.gd")
const CombatRuntimeScript := preload("res://src/gameplay/world/combat_runtime.gd")
const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")

## The runtime loads the SHIPPED curve itself (which curve is in play is content, not a
## constructor argument), so these tests read their boundaries off that curve rather than
## hard-coding them. A retuned curve then changes the numbers here automatically instead of
## silently making a "ceiling" test grant far too little and assert the wrong thing — which is
## exactly what the first version of this file did.
const CURVE_PATH := "res://data/progression/player_progression_curve.tres"


func _curve() -> ProgressionCurveData:
	return load(CURVE_PATH) as ProgressionCurveData


## XP needed to reach the first level-up on the shipped curve.
func _first_level_cost() -> int:
	var curve := _curve()
	return curve.cost_from(curve.min_level)


## XP that is certainly enough to sit at the shipped curve's ceiling.
func _ceiling_xp() -> int:
	var curve := _curve()
	return curve.cumulative_for_level(curve.max_level())

var _runtime: Node = null
var _combat: Node = null
var _character: CharacterState = null

## Signal captures.
var _xp_events: Array = []
var _level_events: Array = []


func before_each() -> void:
	_xp_events = []
	_level_events = []
	_combat = Node.new()
	_combat.name = "CombatRuntime"
	_combat.set_script(CombatRuntimeScript)
	_runtime = Node.new()
	_runtime.name = "ProgressionRuntime"
	_runtime.set_script(RuntimeScript)
	_character = _build_character()


func after_each() -> void:
	# End the session before freeing, so the disconnect path runs — and a leaked connection
	# to a freed node would be a real defect this teardown would otherwise hide.
	if _runtime != null and is_instance_valid(_runtime):
		_runtime.call("end_session")
	free_node(_runtime)
	free_node(_combat)
	_runtime = null
	_combat = null
	_character = null


func _build_character() -> CharacterState:
	var stats: StatBlock = StatBlockScript.new()
	stats.max_hp = 10
	stats.attack = 1
	stats.defense = 0
	stats.move_speed = 10.0
	var template: CharacterTemplateData = TemplateScript.new()
	template.id = &"char_test"
	template.name_key = &"NAME_TEST"
	template.base_stats = stats
	return StateScript.create_from_template(template, &"inst_test")


func _start() -> bool:
	return bool(_runtime.call("start_session", _character, _combat))


func _listen() -> void:
	_runtime.connect("xp_gained", func(amount: int, reward_id: StringName) -> void:
		_xp_events.append({"amount": amount, "id": reward_id}))
	_runtime.connect("level_changed", func(previous: int, current: int) -> void:
		_level_events.append({"previous": previous, "current": current}))


## Emit the combat runtime's OWN defeat signal, exactly as a real kill does.
func _defeat(reward_id: StringName, xp: int) -> void:
	_combat.emit_signal("enemy_defeated", reward_id, xp)


# --- Start / fail-closed -----------------------------------------------------

func test_a_valid_start_becomes_observable_all_at_once() -> void:
	assert_true(_start(), "the session starts")
	assert_true(bool(_runtime.call("is_session_active")), "and is active")
	assert_not_null(_runtime.call("get_service"), "the service is bound")
	assert_eq(_runtime.call("get_character"), _character, "and the subject is the player")
	assert_true(_combat.is_connected("enemy_defeated",
		Callable(_runtime, "grant_for_defeat")), "and it is listening to combat")


func test_a_start_without_a_character_leaves_nothing_observable() -> void:
	assert_false(bool(_runtime.call("start_session", null, _combat)),
		"a start with no progression subject is refused")
	assert_false(bool(_runtime.call("is_session_active")), "no session is active")
	assert_null(_runtime.call("get_service"), "no service was committed")
	assert_false(_combat.is_connected("enemy_defeated",
		Callable(_runtime, "grant_for_defeat")), "and nothing was connected")
	var view: ProgressionView = _runtime.call("build_view")
	assert_false(view.available, "and the view reports unavailable, so the HUD hides the row")


func test_a_start_without_a_combat_publisher_is_refused() -> void:
	assert_false(bool(_runtime.call("start_session", _character, null)),
		"with no publisher, no defeat could ever fund XP, so the session is refused")
	assert_false(bool(_runtime.call("is_session_active")), "nothing observable")


func test_a_publisher_without_the_defeat_signal_is_refused() -> void:
	# A plain Node has no `enemy_defeated`. Connecting optimistically and discovering the gap
	# at the first kill would look like a balance problem rather than a wiring failure.
	var wrong := Node.new()
	assert_false(bool(_runtime.call("start_session", _character, wrong)),
		"a publisher missing the signal is refused at start")
	assert_false(bool(_runtime.call("is_session_active")), "nothing observable")
	free_node(wrong)


func test_starting_twice_is_refused() -> void:
	assert_true(_start(), "the first start succeeds")
	assert_false(_start(), "a second start on a live session is refused")
	assert_true(bool(_runtime.call("is_session_active")),
		"and the existing session is still intact")


# --- The reward path ---------------------------------------------------------

func test_a_defeat_grants_the_authored_xp() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"wolf#1", 7)
	assert_eq(_character.xp, 7, "the player's XP is the one that moved")
	assert_eq(_xp_events.size(), 1, "one xp_gained event")
	assert_eq(_xp_events[0]["amount"], 7, "carrying the amount")
	assert_eq(_xp_events[0]["id"], &"wolf#1", "and the identity that paid it")
	assert_eq(_level_events.size(), 0, "7 XP is not a level")


func test_a_defeat_worth_nothing_emits_no_xp_event() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"critter#1", 0)
	assert_eq(_character.xp, 0, "nothing was granted")
	assert_eq(_xp_events.size(), 0,
		"and no xp_gained fires for a zero reward — an event announcing 'you gained 0' is "
		+ "noise a future quest consumer would have to filter")


func test_crossing_a_threshold_emits_exactly_one_level_change() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"wolf#1", _first_level_cost())
	assert_eq(_level_events.size(), 1, "one level_changed")
	assert_eq(_level_events[0]["previous"], 1, "from level 1")
	assert_eq(_level_events[0]["current"], 2, "to level 2")


## §14's event decision, asserted: a grant crossing three thresholds reports ONE transition.
func test_a_multi_level_defeat_reports_one_coherent_transition() -> void:
	assert_true(_start(), "session")
	_listen()
	# Enough to clear the first three authored steps in one grant.
	var curve := _curve()
	_defeat(&"boss#1", curve.cumulative_for_level(curve.min_level + 3))
	assert_eq(_level_events.size(), 1,
		"ONE level_changed, not three — the intermediate levels were never states the "
		+ "character was in, so a listener must not be able to observe them")
	assert_eq(_level_events[0]["previous"], curve.min_level,
		"the whole transition is reported at once")
	assert_eq(_level_events[0]["current"], curve.min_level + 3, "three levels in one event")


# --- Idempotency (§9) --------------------------------------------------------

func test_the_same_defeat_cannot_pay_twice() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"wolf#1", 15)
	_defeat(&"wolf#1", 15)
	_defeat(&"wolf#1", 15)
	assert_eq(_character.xp, 15,
		"three deliveries of ONE defeat grant once — the ledger is keyed by reward id")
	assert_eq(_xp_events.size(), 1, "and only one event is published")
	assert_eq(int(_runtime.call("granted_count")), 1, "one defeat is on the ledger")


func test_two_different_defeats_both_pay() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"wolf#1", 10)
	_defeat(&"wolf#2", 10)
	assert_eq(_character.xp, 20, "distinct reward ids are distinct rewards")
	assert_eq(_xp_events.size(), 2, "two events")
	assert_eq(int(_runtime.call("granted_count")), 2, "two ledger entries")


func test_a_rejected_grant_is_still_recorded_so_it_is_not_retried() -> void:
	assert_true(_start(), "session")
	# Reach the ceiling, then kill something else: the grant is rejected (nothing left to
	# earn), and the ledger must still swallow a repeat so it is not re-attempted forever.
	_defeat(&"ceiling#1", _ceiling_xp())
	assert_true(bool(_runtime.call("build_view").at_ceiling),
		"the fixture really did reach the ceiling (otherwise this tests nothing)")
	_listen()
	_defeat(&"wolf#9", 25)
	var after := _character.xp
	_defeat(&"wolf#9", 25)
	assert_eq(_character.xp, after, "a repeat of a rejected defeat changes nothing")
	assert_eq(_xp_events.size(), 0, "and publishes nothing")


# --- The view ----------------------------------------------------------------

func test_the_view_reports_the_derived_numbers() -> void:
	assert_true(_start(), "session")
	var curve := _curve()
	# One step past the first threshold, so the overflow is observable.
	_defeat(&"wolf#1", _first_level_cost() + 5)
	var view: ProgressionView = _runtime.call("build_view")
	assert_true(view.available, "the view is available inside a session")
	assert_eq(view.level, curve.min_level + 1, "one level up")
	assert_eq(view.xp_into_level, 5, "with the 5 XP of overflow banked inside it")
	assert_eq(view.xp_for_next, curve.cost_from(curve.min_level + 1),
		"against the next step's authored cost")
	assert_false(view.at_ceiling, "and not at the ceiling")
	assert_true(view.progress > 0.0 and view.progress < 1.0,
		"progress is a real fraction (%f)" % view.progress)


func test_the_view_reports_the_ceiling_as_complete() -> void:
	assert_true(_start(), "session")
	_defeat(&"ceiling#1", _ceiling_xp())
	var view: ProgressionView = _runtime.call("build_view")
	assert_true(view.at_ceiling, "at the ceiling (granted %d XP)" % _ceiling_xp())
	assert_eq(view.progress, 1.0,
		"the meter reads COMPLETE rather than 0/0, which is what the raw numbers would say")


# --- Teardown ----------------------------------------------------------------

func test_ending_a_session_disconnects_and_drops_everything() -> void:
	assert_true(_start(), "session")
	_runtime.call("end_session")
	assert_false(bool(_runtime.call("is_session_active")), "no session")
	assert_null(_runtime.call("get_service"), "no service")
	assert_null(_runtime.call("get_character"), "no subject")
	assert_false(_combat.is_connected("enemy_defeated",
		Callable(_runtime, "grant_for_defeat")),
		"and it stopped listening — a defeat announced during teardown must not be granted "
		+ "into a CharacterState the world session is freeing")
	assert_eq(int(_runtime.call("granted_count")), 0, "the ledger is dropped with the session")


func test_a_defeat_after_teardown_grants_nothing() -> void:
	assert_true(_start(), "session")
	_runtime.call("end_session")
	_listen()
	# Call the public entry point directly: the signal is disconnected, so this is the only
	# way to prove the no-session guard inside it holds. A double teardown, a replayed event,
	# or a future server message arriving late would all land here.
	_runtime.call("grant_for_defeat", &"wolf#1", 50)
	assert_eq(_character.xp, 0, "no XP was granted outside a session")
	assert_eq(_xp_events.size(), 0, "and nothing was published")


func test_ending_a_session_that_never_started_is_a_no_op() -> void:
	# The shared teardown path runs after an aborted boot, so this must be safe.
	_runtime.call("end_session")
	_runtime.call("end_session")
	assert_false(bool(_runtime.call("is_session_active")), "still no session, no error")


func test_a_restart_begins_from_the_characters_stored_xp() -> void:
	assert_true(_start(), "first session")
	_defeat(&"wolf#1", _first_level_cost() + 10)
	_runtime.call("end_session")
	assert_true(_start(), "a second session starts")
	var view: ProgressionView = _runtime.call("build_view")
	assert_eq(view.level, _curve().min_level + 1,
		"the level is re-derived from the character's persisted XP, not reset — the authority "
		+ "is the CharacterState, not the session")
	assert_eq(int(_runtime.call("granted_count")), 0,
		"but the per-session reward ledger starts empty")


# --- Reward-id identity (D-055 §10-11) ---------------------------------------
#
# The ledger is keyed by `String(reward_id)`, so the ID IS the identity of a payment. A
# malformed id is therefore not a cosmetic problem: an EMPTY one is a key that every malformed
# defeat would share, so the first would be paid and would then occupy `""` and make the ledger
# answer "already granted" for every later one. That turns duplicate-protection into a
# collision, which is the opposite of what it is for.
#
# The matrix below is the whole identity contract in one place: granted once, never twice,
# distinct ids are distinct payments, a respawn is a NEW payment, and a missing id fails closed
# without touching anything.

func test_an_empty_reward_id_is_rejected_and_grants_nothing() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"", 25)
	assert_eq(_character.xp, 0,
		"an unnamed reward pays nothing — the id is the payment's identity, and a payment "
		+ "with no identity cannot be deduplicated")
	assert_eq(_xp_events.size(), 0, "no xp_gained was published")
	assert_eq(_level_events.size(), 0, "and no level_changed")
	assert_eq(int(_runtime.call("granted_count")), 0,
		"and the ledger was NOT touched — this is the half that matters, because an entry "
		+ "under the empty key is what would poison every later malformed defeat")


## The specific failure mode the guard exists for: reject-then-accept must still work.
##
## If the empty id had been recorded, the SECOND empty defeat would be silently swallowed as a
## duplicate, and — worse — the ledger would be carrying an entry that corresponds to no
## creature. Asserting a valid defeat still pays afterwards proves the rejection left the
## ledger usable rather than merely left the counter at zero.
func test_an_empty_reward_id_does_not_poison_the_ledger() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"", 25)
	_defeat(&"", 25)
	_defeat(&"", 25)
	assert_eq(int(_runtime.call("granted_count")), 0, "three rejections, no entries")

	_defeat(&"wolf#1", 25)
	assert_eq(_character.xp, 25,
		"a well-formed defeat still pays after the rejections — the ledger was not left in a "
		+ "state where a real reward collides with a phantom one")
	assert_eq(_xp_events.size(), 1, "exactly one payment was published")
	assert_eq(int(_runtime.call("granted_count")), 1, "and exactly one entry exists")


## A respawn is a NEW payment, because the id is per SPAWN and not per spawn-table row.
##
## `CombatRuntime` mints `instance_id#serial`, so the same creature cleared twice carries two
## ids. Keying on the row id instead would have made the ledger a "has ever been killed" flag
## and a re-cleared map would pay nothing — the defect the per-spawn id was chosen to avoid.
## This is the runtime's half of that contract; `test_combat_awards_progression.gd` proves the
## minting half against real spawns.
func test_a_respawned_creature_pays_again_because_its_id_differs() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"wolf#1", 10)
	_defeat(&"wolf#1", 10)  # same spawn announced twice: one payment
	assert_eq(_character.xp, 10, "the same spawn pays once")

	_defeat(&"wolf#2", 10)  # the respawn: a new serial, so a new identity
	assert_eq(_character.xp, 20, "the respawn is a separate payment")
	assert_eq(_xp_events.size(), 2, "two payments were published")
	assert_eq(int(_runtime.call("granted_count")), 2, "two distinct entries")


## A negative reward is content corruption, not a refund.
##
## The service rejects it (`REASON_NEGATIVE_AMOUNT`), and the runtime must still record the
## defeat as handled so it is not retried on every later delivery. So the observable contract
## is: XP unchanged, nothing published, but the ledger DOES hold the entry — which is the
## opposite of the empty-id case, and the distinction is deliberate. An identified defeat that
## was rejected is settled; an unidentified one was never a defeat at all.
func test_a_negative_reward_mutates_nothing_but_is_still_settled() -> void:
	assert_true(_start(), "session")
	_listen()
	_defeat(&"wolf#1", -500)
	assert_eq(_character.xp, 0, "a negative reward never reduces the player's total")
	assert_eq(_xp_events.size(), 0, "and publishes nothing")
	assert_eq(int(_runtime.call("granted_count")), 1,
		"but the defeat is recorded as settled, so a replayed delivery does not re-attempt it")
