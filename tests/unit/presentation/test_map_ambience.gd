extends TestCase
## Unit tests for `MapAmbience` / `AmbienceLight` / the shipped ambience profiles (D-073 §3):
## how a map is lit at an hour that is not day. Presentation only — these tests assert what
## the node SHOWS for the id it is handed; which id a beat names is the story's (asserted in
## the story tests and the Story E2E).

const AmbienceScript := preload("res://src/presentation/ambient/map_ambience.gd")
const LightScript := preload("res://src/presentation/ambient/ambience_light.gd")
const HubScene := preload("res://src/gameplay/maps/hub_map.tscn")
const FieldScene := preload("res://src/gameplay/maps/field_map.tscn")
const SHIPPED: Array[StringName] = [&"dusk", &"night"]


func _light(role: StringName) -> AmbienceLight:
	var light: AmbienceLight = LightScript.new()
	light.role = role
	return light


## A MapAmbience with one lantern and one vein, in the tree.
func _rig() -> MapAmbience:
	var ambience: MapAmbience = AmbienceScript.new()
	ambience.add_child(_light(AmbienceLight.ROLE_LANTERN))
	ambience.add_child(_light(AmbienceLight.ROLE_VEIN))
	add_to_tree(ambience)
	return ambience


func _profile(id: StringName) -> AmbienceProfileData:
	return load(MapAmbience.PROFILE_PATH % id) as AmbienceProfileData


func test_by_day_a_map_is_as_authored_and_costs_nothing() -> void:
	var ambience := _rig()
	ambience.apply(&"")
	assert_eq(ambience.tint(), Color.WHITE, "no tint: the map as it was painted")
	for light in ambience.lights():
		assert_false(light.enabled, "by day a %s lights nothing" % light.role)
	assert_false(ambience.is_processing(), "and nothing runs per frame")
	free_node(ambience)


func test_night_tints_the_playfield_and_lights_what_burns() -> void:
	var ambience := _rig()
	var night := _profile(&"night")
	ambience.apply(&"night")
	assert_eq(ambience.ambience_id(), &"night", "it wears what it was handed")
	assert_eq(ambience.tint(), night.tint, "arriving INTO a night shows it at once")
	assert_true(ambience.tint().b > ambience.tint().r, "a cool tint: the frontier's night")
	for light in ambience.lights():
		assert_true(light.enabled and light.energy > 0.0, "the %s burns" % light.role)
	assert_eq(ambience.lights()[0].color, night.lantern_color, "a lantern in its own colour")
	assert_eq(ambience.lights()[1].color, night.vein_color, "the vein in qi's")
	ambience.apply(&"")
	free_node(ambience)


func test_dusk_lights_lanterns_and_not_the_vein() -> void:
	var ambience := _rig()
	ambience.apply(&"dusk")
	assert_true(ambience.lights()[0].enabled, "lanterns are lit at dusk")
	assert_false(ambience.lights()[1].enabled, "the vein has not broken: it gives no light")
	assert_true(ambience.is_processing(), "the lanterns gutter: something is unsteady")
	free_node(ambience)


## A change while the player stands in the map eases in; going back to day ends dark and
## stops the clock.
func test_a_change_in_place_eases_and_day_returns_whole() -> void:
	var ambience := _rig()
	ambience.apply(&"")
	ambience.apply(&"dusk")
	assert_ne(ambience.tint(), _profile(&"dusk").tint, "dusk comes on; it does not snap")
	assert_true(ambience.is_processing(), "while it eases")
	ambience.apply(&"night")
	ambience.apply(&"night")  # asked twice: nothing restarts
	ambience.apply(&"")
	for _i in 240:
		if ambience.tint().is_equal_approx(Color.WHITE) and not ambience.is_processing():
			break
		await scene_tree.process_frame
	assert_true(ambience.tint().is_equal_approx(Color.WHITE), "day is the map as authored again")
	for light in ambience.lights():
		assert_false(light.enabled, "and nothing is left burning")
	assert_false(ambience.is_processing(), "and nothing is left running")
	free_node(ambience)


func test_an_ambience_nobody_authored_leaves_the_map_as_it_is() -> void:
	var ambience := _rig()
	assert_false(MapAmbience.profile_exists(&"eclipse"), "no such profile")
	ambience.apply(&"eclipse")
	assert_eq(ambience.ambience_id(), &"", "an unknown ambience is not worn")
	assert_eq(ambience.tint(), Color.WHITE, "and the map is not darkened by a guess")
	free_node(ambience)


func test_a_pulse_flares_the_vein_and_then_settles() -> void:
	var ambience := _rig()
	ambience.apply(&"night")
	var vein := ambience.lights()[1]
	var resting := _profile(&"night").vein_energy
	ambience.pulse()
	assert_true(ambience.is_pulsing(), "the vein gives way")
	ambience.advance(0.05)
	assert_true(vein.energy > resting, "its light flares above its resting strength (%.2f > %.2f)"
		% [vein.energy, resting])
	ambience.advance(MapAmbience.PULSE_SECONDS * 0.5)
	assert_true(ambience.is_pulsing(), "half way through it is still settling")
	ambience.advance(MapAmbience.PULSE_SECONDS)
	assert_false(ambience.is_pulsing(), "and it settles: an event, not a state")
	assert_true(vein.energy <= resting + 0.001,
		"back at (or under, on its slow pulse) its resting strength (%.2f)" % vein.energy)
	ambience.apply(&"")
	free_node(ambience)


func test_a_map_with_no_vein_does_not_pulse() -> void:
	var ambience: MapAmbience = AmbienceScript.new()
	ambience.add_child(_light(AmbienceLight.ROLE_LANTERN))
	add_to_tree(ambience)
	ambience.apply(&"night")
	ambience.pulse()
	assert_false(ambience.is_pulsing(), "there is nothing here to give way")
	ambience.apply(&"")
	free_node(ambience)


## READABILITY IS A RULE (D-073 §3): a tint may cool and compress the picture; it may not
## hide it. Every shipped profile keeps at least the floor of the authored brightness, and
## what it does to the game's two warning colours leaves them apart from each other.
func test_every_shipped_profile_keeps_the_playfield_readable() -> void:
	var danger := UIPalette.COLOR_CRIMSON
	var jade := UIPalette.COLOR_ACCENT
	for id in SHIPPED:
		var profile := _profile(id)
		assert_not_null(profile, "'%s' is generated" % id)
		if profile == null:
			continue
		assert_true(profile.is_valid(), "'%s' is a usable profile" % id)
		assert_eq(profile.id, id, "'%s' is named by its file" % id)
		assert_true(profile.tint_level() >= MapAmbience.MIN_TINT_LEVEL,
			"'%s' keeps %.2f of the authored brightness (floor %.2f)"
			% [id, profile.tint_level(), MapAmbience.MIN_TINT_LEVEL])
		assert_true(profile.tint.a == 1.0, "'%s' is a multiply, not a veil" % id)
		var lit_danger := danger * profile.tint
		var lit_jade := jade * profile.tint
		assert_true(lit_danger.r > lit_danger.g and lit_danger.r > lit_danger.b * 0.9,
			"'%s': the hostile red still reads as red" % id)
		assert_true(absf(lit_danger.get_luminance() - lit_jade.get_luminance()) > 0.08
			or absf(lit_danger.h - lit_jade.h) > 0.15,
			"'%s': danger and safety are still told apart" % id)


## Both shipped maps own a `Visual/Ambience` with lights where their lanterns are, and the
## woods' vein has one. A light is OFF until an ambience turns it on.
func test_the_shipped_maps_have_their_lights_where_their_lanterns_are() -> void:
	for entry in [[HubScene, "hub", 2, 0], [FieldScene, "field", 2, 1]]:
		var map: Node = (entry[0] as PackedScene).instantiate()
		var ambience := map.get_node_or_null(MapBase.AMBIENCE_PATH) as MapAmbience
		assert_not_null(ambience, "the %s has an ambience" % entry[1])
		var lanterns := 0
		var veins := 0
		for child in ambience.get_children():
			if child is AmbienceLight:
				var light := child as AmbienceLight
				if light.role == AmbienceLight.ROLE_VEIN:
					veins += 1
				else:
					lanterns += 1
					var post := map.get_node_or_null("Visual/Decor/%s" % light.name) as Node2D
					assert_not_null(post, "%s: light '%s' belongs to a lantern post"
						% [entry[1], light.name])
					if post != null:
						assert_true(light.position.distance_to(post.position) < 48.0,
							"%s: '%s' burns at its lantern" % [entry[1], light.name])
		assert_eq([lanterns, veins], [entry[2], entry[3]], "%s: lanterns and veins" % entry[1])
		map.free()
