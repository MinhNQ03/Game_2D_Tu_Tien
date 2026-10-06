extends TestCase
## `HitReaction` — the struck body's physical response and the impact it shows (D-057B).
##
## Before it, a landed hit only flashed a colour: the number changed and nothing was pushed
## (`MOTION_DESIGN_CONTRACT.md` M-5.1). The contract under test:
##
##   * a creature RECOILS along the blow in whole pixels and returns EXACTLY to rest;
##   * a rooted object WOBBLES about its footing through its material's `lean_px`, leaning AWAY
##     from the blow first, and comes to rest at exactly zero;
##   * a critical hit shoves harder; a hit that applied nothing does nothing;
##   * the impact appears on the STRIKER's side of the body, its debris flies along the blow
##     and obeys the material (chaff falls, mist rises), lives in world space, and ends;
##   * all of it is driven by the real `HurtboxComponent.damaged` signal and moves only the
##     DRAWING — the entity never moves.
##
## Every node is freed by the test that built it (L-019).

const HurtboxScript := preload("res://src/gameplay/components/hurtbox_component.gd")
const ReactionScript := preload("res://src/presentation/combat/hit_reaction.gd")
const VisualScript := preload("res://src/presentation/characters/character_visual_component.gd")
const SwayShader := preload("res://src/presentation/ambient/pixel_sway.gdshader")
const WOLF_VISUAL := "res://data/characters/visual/mist_wolf_visual.tres"


## The minimum struck body: it can take damage and has a visual the reaction drives.
class StubBody extends Node2D:
	var hp: int = 100

	func take_damage(amount: int) -> int:
		if hp <= 0 or amount <= 0:
			return 0
		var before := hp
		hp = maxi(0, hp - amount)
		return before - hp

	func is_dead() -> bool:
		return hp <= 0


## A creature: hurtbox + runtime visual (the wolf's profile) + a RECOIL reaction.
func _creature(at: Vector2 = Vector2(200, 200)) -> StubBody:
	var body := StubBody.new()
	body.position = at
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = &"stub"
	body.add_child(hurtbox)
	var reaction: HitReaction = ReactionScript.new()
	reaction.name = "HitReaction"
	reaction.debris_gravity = -60.0
	body.add_child(reaction)
	add_to_tree(body)
	var visual: CharacterVisualComponent = VisualScript.new()
	visual.name = "CharacterVisualComponent"
	body.add_child(visual)
	assert_true(visual.setup(load(WOLF_VISUAL)), "the wolf visual binds")
	return body


## A rooted object: hurtbox + a Sprite2D "Visual" wearing the sway material + PIVOT_WOBBLE.
func _post() -> StubBody:
	var body := StubBody.new()
	body.position = Vector2(300, 300)
	var sprite := Sprite2D.new()
	sprite.name = "Visual"
	var material := ShaderMaterial.new()
	material.shader = SwayShader
	sprite.material = material
	body.add_child(sprite)
	var hurtbox: HurtboxComponent = HurtboxScript.new()
	hurtbox.name = "HurtboxComponent"
	hurtbox.entity_id = &"post"
	body.add_child(hurtbox)
	var reaction: HitReaction = ReactionScript.new()
	reaction.name = "HitReaction"
	reaction.response = HitReaction.Response.PIVOT_WOBBLE
	reaction.debris_gravity = 320.0
	body.add_child(reaction)
	add_to_tree(body)
	return body


func _reaction(body: Node) -> HitReaction:
	return body.get_node("HitReaction") as HitReaction


func _hurtbox(body: Node) -> HurtboxComponent:
	return body.get_node("HurtboxComponent") as HurtboxComponent


func _visual(body: Node) -> CharacterVisualComponent:
	return body.get_node("CharacterVisualComponent") as CharacterVisualComponent


func _lean(body: Node) -> float:
	var material := (body.get_node("Visual") as Sprite2D).material as ShaderMaterial
	var value: Variant = material.get_shader_parameter(&"lean_px")
	return float(value) if value != null else 0.0


# === RECOIL ===================================================================

## The shove lands along the blow, in whole pixels, and the body returns EXACTLY to rest. The
## entity itself never moves: only the drawing does.
func test_a_creature_recoils_along_the_blow_and_returns_exactly() -> void:
	var body := _creature()
	var reaction := _reaction(body)
	var start := body.position
	_hurtbox(body).apply_hit(5, false, Vector2.RIGHT)
	assert_true(reaction.is_reacting(), "a landed hit starts the reaction")
	reaction.advance(reaction.recoil_seconds * HitReaction.SHOVE_SHARE)
	var peak := _visual(body).sprite_offset()
	assert_eq(peak, Vector2(roundf(reaction.recoil_px), 0.0),
		"at the end of the shove the body is pushed recoil_px along the blow (%s)" % str(peak))
	assert_eq(peak, peak.round(), "in whole pixels: a sub-pixel offset shimmers on pixel art")
	reaction.advance(reaction.recoil_seconds)
	assert_eq(_visual(body).sprite_offset(), Vector2.ZERO, "and back EXACTLY to its footing")
	assert_false(reaction.is_reacting(), "the reaction is over")
	assert_eq(body.position, start, "the ENTITY never moved — gameplay position is untouched")
	free_node(body)


## Pushed from the other side, it goes the other way: the direction is the blow's.
func test_the_recoil_follows_the_push_direction() -> void:
	var body := _creature()
	var reaction := _reaction(body)
	_hurtbox(body).apply_hit(5, false, Vector2.UP)
	reaction.advance(reaction.recoil_seconds * HitReaction.SHOVE_SHARE)
	assert_true(_visual(body).sprite_offset().y < 0.0, "a blow travelling UP shoves the body up")
	assert_eq(_visual(body).sprite_offset().x, 0.0, "and not sideways")
	free_node(body)


## A critical hit shoves harder; a hit that applied nothing does nothing.
func test_critical_shoves_harder_and_nothing_applied_is_no_reaction() -> void:
	var normal := _creature()
	var critical := _creature(Vector2(400, 200))
	_hurtbox(normal).apply_hit(5, false, Vector2.RIGHT)
	_hurtbox(critical).apply_hit(5, true, Vector2.RIGHT)
	var t := _reaction(normal).recoil_seconds * HitReaction.SHOVE_SHARE
	_reaction(normal).advance(t)
	_reaction(critical).advance(t)
	assert_true(_visual(critical).sprite_offset().x > _visual(normal).sprite_offset().x,
		"a critical hit shoves further (%s vs %s)" % [str(_visual(critical).sprite_offset()),
			str(_visual(normal).sprite_offset())])

	var dead := _creature(Vector2(600, 200))
	(dead as StubBody).hp = 0
	_hurtbox(dead).apply_hit(5, false, Vector2.RIGHT)
	assert_false(_reaction(dead).is_reacting(), "a hit that applied 0 does not react")
	assert_false(_reaction(dead).is_showing_impact(), "and shows no impact")
	free_node(normal)
	free_node(critical)
	free_node(dead)


# === PIVOT_WOBBLE =============================================================

## A rooted post LEANS away from the blow about its footing, rocks, and comes to rest at exactly
## zero lean.
func test_a_rooted_object_wobbles_away_from_the_blow_and_settles() -> void:
	var body := _post()
	var reaction := _reaction(body)
	_hurtbox(body).apply_hit(5, false, Vector2.RIGHT)
	assert_eq(_lean(body), 0.0, "it starts upright: a pushed post does not teleport")
	reaction.advance(0.25 / reaction.wobble_hz)  # a quarter period: the first lean's peak
	assert_true(_lean(body) > 1.0, "struck from the left, it leans RIGHT first (%f)" % _lean(body))
	var signs := {}
	for _i in 40:
		reaction.advance(0.02)
		if absf(_lean(body)) > 0.2:
			signs[signf(_lean(body))] = true
	assert_eq(signs.size(), 2, "it ROCKS back past upright: a damped oscillation, not a lean")
	reaction.advance(reaction.wobble_seconds)
	assert_eq(_lean(body), 0.0, "and comes to rest at exactly zero")
	free_node(body)


## Struck from the right it leans the other way.
func test_the_wobble_direction_follows_the_blow() -> void:
	var body := _post()
	var reaction := _reaction(body)
	_hurtbox(body).apply_hit(5, false, Vector2.LEFT)
	reaction.advance(0.25 / reaction.wobble_hz)
	assert_true(_lean(body) < -1.0, "struck from the right, it leans LEFT (%f)" % _lean(body))
	free_node(body)


# === The impact ===============================================================

## The impact sits on the striker's side of the body, its debris flies ALONG the blow, and it
## lives in world space: the body moving afterwards does not drag the debris with it.
func test_the_impact_is_on_the_striker_side_and_its_debris_follows_the_blow() -> void:
	var body := _creature()
	var reaction := _reaction(body)
	var core := body.global_position + _visual(body).anchor_point(
		CharacterVisualProfileData.POINT_CORE)
	_hurtbox(body).apply_hit(5, false, Vector2.RIGHT)
	assert_true(reaction.is_showing_impact(), "the impact shows at once")
	assert_true(reaction.impact_point().x < core.x,
		"struck from the left, the contact is LEFT of the core (%s vs %s)"
			% [str(reaction.impact_point()), str(core)])
	reaction.advance(0.08)
	var along := 0
	var segments := reaction.debris_segments()
	for segment in segments:
		if (segment[1] - reaction.impact_point()).x > 0.0:
			along += 1
	assert_true(along >= segments.size() - 1,
		"all but the back-splash flies along the blow (%d of %d)" % [along, segments.size()])
	var before: Array[PackedVector2Array] = reaction.debris_segments()
	body.position += Vector2(40, 0)
	assert_eq(reaction.debris_segments(), before,
		"debris that has left the body does not follow it (world space)")
	assert_true(reaction.top_level, "the impact is top-level: not tinted by the body's flash")
	reaction.advance(HitReaction.IMPACT_SECONDS_CRITICAL)
	assert_false(reaction.is_showing_impact(), "and it ends")
	assert_true(reaction.debris_segments().is_empty(), "leaving nothing behind")
	free_node(body)


## The MATERIAL decides where debris goes: straw chaff falls, mist rises.
func test_debris_obeys_the_struck_material() -> void:
	var post := _post()
	var wolf := _creature()
	_hurtbox(post).apply_hit(5, false, Vector2.RIGHT)
	_hurtbox(wolf).apply_hit(5, false, Vector2.RIGHT)
	var post_start := _mean_y(_reaction(post).debris_segments())
	var wolf_start := _mean_y(_reaction(wolf).debris_segments())
	_reaction(post).advance(0.15)
	_reaction(wolf).advance(0.15)
	assert_true(_mean_y(_reaction(post).debris_segments()) - post_start > 2.0,
		"straw chaff FALLS (gravity > 0)")
	assert_true(_mean_y(_reaction(wolf).debris_segments()) - wolf_start
		< _mean_y(_reaction(post).debris_segments()) - post_start,
		"mist does not fall like straw (gravity < 0)")
	free_node(post)
	free_node(wolf)


## Two hits in a row do not throw the identical spray (bounded, deterministic variation).
func test_consecutive_impacts_vary_deterministically() -> void:
	var a := _creature()
	var b := _creature(Vector2(500, 200))
	var first: Array = []
	var second: Array = []
	for body in [a, b]:
		# Sampled late in the flight, where a 7° turn is whole pixels apart.
		_hurtbox(body).apply_hit(5, false, Vector2.RIGHT)
		_reaction(body).advance(0.15)
		var one := _relative(_reaction(body))
		_reaction(body).advance(1.0)
		_hurtbox(body).apply_hit(5, false, Vector2.RIGHT)
		_reaction(body).advance(0.15)
		var two := _relative(_reaction(body))
		first.append(one)
		second.append(two)
	assert_ne(first[0], second[0], "the second hit's spray is turned from the first's")
	assert_eq(first[0], first[1], "and the n-th hit is the same on every body: no RNG")
	assert_eq(second[0], second[1], "(second hit too)")
	free_node(a)
	free_node(b)


func _relative(reaction: HitReaction) -> Array:
	var out: Array = []
	for segment in reaction.debris_segments():
		out.append(segment[1] - reaction.impact_point())
	return out


func _mean_y(segments: Array[PackedVector2Array]) -> float:
	if segments.is_empty():
		return 0.0
	var total := 0.0
	for segment in segments:
		total += segment[1].y
	return total / float(segments.size())
