extends TestCase
## `AttackFeedback` v2 — the swing drawn as a causal effect (D-057B) — plus the two gameplay
## and presentation knobs D-057B added beside it: `AttackData.committed_move_scale` (a swing in
## flight roots the attacker) and `DamageFeedback.flash_strength` (a struck object warms rather
## than bleeds).
##
## The contract (`MOTION_DESIGN_CONTRACT.md` M-1.2, M-5.1, M-6.3, M-6.4):
##
##   * the RELEASE starts at the striking point of the DRAWN frame (the `palm` anchor), travels
##     along the facing, and is gone by the end of the recovery (source → release → dissipate);
##   * a HOSTILE wind-up telegraphs its reach on the ground; the player's own swing does not;
##   * a strike facing away from the viewer is drawn BEHIND the body, any other in front;
##   * everything is derived from the attack lifecycle's own time — the node keeps no clock.
##
## Driven through a REAL `AttackComponent` armed with real data, advanced with exact deltas.

const AttackDataScript := preload("res://src/data/combat/attack_data.gd")
const RngServiceScript := preload("res://src/domain/worldsim/rng_service.gd")
const FeedbackScript := preload("res://src/presentation/combat/attack_feedback.gd")
const VisualScript := preload("res://src/presentation/characters/character_visual_component.gd")
const DamageFeedbackScript := preload("res://src/presentation/combat/damage_feedback.gd")
const HurtboxScript := preload("res://src/gameplay/components/hurtbox_component.gd")
const PLAYER_VISUAL := "res://data/characters/visual/player_visual.tres"
const PLAYER_ATTACK := "res://data/combat/attack_player_basic.tres"


func _attacker(hostile: bool, facing: Vector2) -> Node2D:
	var body := Node2D.new()
	body.position = Vector2(100, 100)
	var component := AttackComponent.new()
	component.name = "AttackComponent"
	body.add_child(component)
	var feedback: AttackFeedback = FeedbackScript.new()
	feedback.name = "AttackFeedback"
	feedback.hostile = hostile
	body.add_child(feedback)
	add_to_tree(body)
	var visual: CharacterVisualComponent = VisualScript.new()
	visual.name = "CharacterVisualComponent"
	body.add_child(visual)
	assert_true(visual.setup(load(PLAYER_VISUAL)), "the player visual binds")
	var rng: RngService = RngServiceScript.new(7)
	assert_true(component.arm(load(PLAYER_ATTACK), CombatService.new(rng.stream(
		RngService.STREAM_COMBAT)), CombatHurtboxRegistry.new(), &"attacker"), "it arms")
	component.set_facing(facing)
	visual.update_facing(facing, false)
	return body


func _component(body: Node) -> AttackComponent:
	return body.get_node("AttackComponent") as AttackComponent


func _feedback(body: Node) -> AttackFeedback:
	return body.get_node("AttackFeedback") as AttackFeedback


func _visual(body: Node) -> CharacterVisualComponent:
	return body.get_node("CharacterVisualComponent") as CharacterVisualComponent


## Advance the lifecycle and the visual together, the way the engine would.
func _step(body: Node, seconds: float) -> void:
	_component(body).advance(seconds)
	_visual(body).advance(seconds)


# === The release ==============================================================

## The air leaves the DRAWN hand: the streak's tail at the start of the ACTIVE window is the
## visual's palm anchor, and its head runs along the facing.
func test_the_release_starts_at_the_drawn_palm_and_runs_along_the_facing() -> void:
	var body := _attacker(false, Vector2.RIGHT)
	var data: AttackData = load(PLAYER_ATTACK)
	assert_true(_component(body).request_attack(), "the swing starts")
	_step(body, data.windup_seconds + 0.001)  # just into ACTIVE: the release
	var sample := _feedback(body).sample()
	assert_eq(sample["state"], AttackStateMachine.State.ACTIVE, "in the hit window")
	var palm := _visual(body).anchor_point(CharacterVisualProfileData.POINT_PALM)
	assert_eq(sample["source"], palm,
		"the release starts at the palm of the frame being drawn (%s vs %s)"
			% [str(sample["source"]), str(palm)])
	_step(body, data.active_seconds * 0.6)
	var streak: PackedVector2Array = _feedback(body).sample()["streak"]
	assert_eq(streak.size(), 2, "air is moving")
	assert_true(streak[1].x > streak[0].x, "and it moves along the facing (RIGHT)")
	assert_true(streak[1].x > palm.x, "away from the hand")
	assert_true(streak[1].y > palm.y,
		"angled DOWN toward body height, not thrown level over a short creature (%s from %s)"
			% [str(streak), str(palm)])
	free_node(body)


## It dissipates: by the end of the recovery no air is drawn, and READY draws nothing.
func test_the_release_dissipates_by_the_end_of_recovery() -> void:
	var body := _attacker(false, Vector2.LEFT)
	var data: AttackData = load(PLAYER_ATTACK)
	_component(body).request_attack()
	_step(body, data.windup_seconds + data.active_seconds + data.recovery_seconds * 0.5)
	var mid: PackedVector2Array = _feedback(body).sample()["streak"]
	assert_eq(mid.size(), 2, "mid-recovery the air is still thinning out")
	_step(body, data.recovery_seconds)
	var sample := _feedback(body).sample()
	assert_eq(sample["state"], AttackStateMachine.State.READY, "the swing is over")
	assert_true((sample["streak"] as PackedVector2Array).is_empty(), "and nothing is drawn")
	assert_false(_feedback(body).is_processing(), "and the node costs nothing again")
	free_node(body)


## Facing away from the viewer the strike is drawn BEHIND the body; otherwise in front.
func test_the_strike_layers_by_facing() -> void:
	var up := _attacker(false, Vector2.UP)
	_component(up).request_attack()
	assert_eq(_feedback(up).sample()["z_index"], 0, "facing away: behind the body")
	var down := _attacker(false, Vector2.DOWN)
	_component(down).request_attack()
	assert_eq(_feedback(down).sample()["z_index"], 1, "facing the viewer: in front")
	free_node(up)
	free_node(down)


# === The telegraph ============================================================

## Only a HOSTILE wind-up telegraphs; the player's own thousandth swing does not ring its feet.
func test_only_a_hostile_windup_telegraphs() -> void:
	var own := _attacker(false, Vector2.RIGHT)
	var hostile := _attacker(true, Vector2.RIGHT)
	_component(own).request_attack()
	_component(hostile).request_attack()
	_step(own, 0.02)
	_step(hostile, 0.02)
	assert_false(_feedback(own).sample()["telegraph"], "the player's own swing: no telegraph")
	assert_true(_feedback(hostile).sample()["telegraph"], "a hostile wind-up: telegraphed")
	var data: AttackData = load(PLAYER_ATTACK)
	_step(hostile, data.windup_seconds)
	assert_false(_feedback(hostile).sample()["telegraph"],
		"and the telegraph ends when the wind-up does — it warns, it does not linger")
	free_node(own)
	free_node(hostile)


# === Commitment: a swing roots the attacker (gameplay data) ====================

## READY moves freely; a swing in flight keeps only the authored share of the speed.
func test_a_swing_in_flight_scales_movement_by_the_authored_commitment() -> void:
	var body := _attacker(false, Vector2.RIGHT)
	var data: AttackData = load(PLAYER_ATTACK)
	assert_eq(_component(body).movement_scale(), 1.0, "READY: full speed")
	_component(body).request_attack()
	assert_eq(_component(body).movement_scale(), data.committed_move_scale,
		"WINDUP: the authored commitment")
	assert_true(data.committed_move_scale < 0.5,
		"the shipped palm strike is a planted commitment (%f)" % data.committed_move_scale)
	_step(body, data.total_seconds() + 0.01)
	assert_eq(_component(body).movement_scale(), 1.0, "READY again: full speed")
	var bite: AttackData = load("res://data/combat/attack_mist_wolf_bite.tres")
	assert_eq(bite.committed_move_scale, 0.0, "the wolf's lunge is drawn in place: rooted")
	free_node(body)


## The data boundary refuses a commitment outside [0, 1].
func test_committed_move_scale_is_validated() -> void:
	var data: AttackData = (load(PLAYER_ATTACK) as AttackData).duplicate()
	data.committed_move_scale = 1.5
	assert_false(data.is_valid(), "a commitment above 1 is refused")
	data.committed_move_scale = -0.1
	assert_false(data.is_valid(), "a negative commitment is refused")
	data.committed_move_scale = 0.3
	assert_true(data.is_valid(), "and a sane one is accepted")


# === Flash strength ===========================================================

class StubBody extends Node2D:
	var hp: int = 50

	func take_damage(amount: int) -> int:
		hp -= amount
		return amount

	func is_dead() -> bool:
		return hp <= 0


## A struck object WARMS instead of turning crimson: same hue, authored strength.
func test_flash_strength_scales_the_hit_tint() -> void:
	var tints := []
	for strength in [1.0, 0.4]:
		var body := StubBody.new()
		var hurtbox: HurtboxComponent = HurtboxScript.new()
		hurtbox.name = "HurtboxComponent"
		hurtbox.entity_id = &"stub"
		body.add_child(hurtbox)
		var feedback: DamageFeedback = DamageFeedbackScript.new()
		feedback.flash_strength = strength
		body.add_child(feedback)
		add_to_tree(body)
		hurtbox.apply_hit(3, false, Vector2.RIGHT)
		tints.append(body.modulate)
		free_node(body)
	var full: Color = tints[0]
	var soft: Color = tints[1]
	assert_true(full.is_equal_approx(UIPalette.HIT_FLASH_TINT),
		"strength 1 is the full crimson flash (%s)" % full)
	assert_true(soft.r > 1.0 and soft.r < full.r, "strength 0.4 still flashes, less (%s)" % soft)
	assert_true(soft.g > full.g, "and keeps more of the object's own colour")
