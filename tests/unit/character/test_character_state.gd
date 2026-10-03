extends TestCase
## Unit tests for CharacterState — the authoritative, serializable domain character
## (`docs/CHARACTER_SYSTEM.md` §3/§5). Covers construction from a template, the life-state
## machine (ALIVE→DEAD once, DEAD terminal), current-HP authority, and the persistent-tier
## round-trip (`to_dict`/`from_dict`). Pure domain (RefCounted): no tree, no autoloads.

const StateScript := preload("res://src/domain/character/character_state.gd")
const TemplateScript := preload("res://src/data/characters/character_template_data.gd")
const StatBlockScript := preload("res://src/data/stats/stat_block.gd")


func _template() -> Resource:
	var stats := StatBlockScript.new()
	stats.max_hp = 80
	stats.attack = 12
	stats.defense = 3
	stats.move_speed = 140.0
	var t := TemplateScript.new()
	t.id = &"char_hero"
	t.name_key = &"NAME_HERO"
	t.title_key = &"TITLE_HERO"
	t.age = 20
	t.base_stats = stats
	return t


func test_create_from_template_copies_identity_and_stats() -> void:
	var state = StateScript.create_from_template(_template(), &"inst_1")
	assert_not_null(state, "state built from a valid template")
	assert_eq(String(state.instance_id), "inst_1", "instance id set by caller")
	assert_eq(String(state.template_id), "char_hero", "template id recorded")
	assert_eq(String(state.name_key), "NAME_HERO", "name key copied")
	assert_eq(state.max_hp, 80, "max_hp seeded from StatBlock")
	assert_eq(state.attack, 12, "attack seeded from StatBlock")
	assert_eq(state.current_hp, 80, "starts at full HP")
	assert_true(state.is_alive(), "starts ALIVE")


func test_create_from_template_rejects_null_and_empty_id() -> void:
	assert_null(StateScript.create_from_template(null, &"x"), "null template rejected")
	assert_null(StateScript.create_from_template(_template(), &""), "empty instance_id rejected")


func test_stats_are_value_copies_not_shared_with_template() -> void:
	# Mutating the state's stats must NOT write back into the shared template resource.
	var template := _template()
	var state = StateScript.create_from_template(template, &"inst_1")
	state.max_hp = 5
	assert_eq(template.base_stats.max_hp, 80, "template StatBlock untouched by state mutation")


func test_mark_dead_transitions_once() -> void:
	var state = StateScript.create_from_template(_template(), &"inst_1")
	assert_true(state.mark_dead(&"slain"), "ALIVE -> DEAD succeeds")
	assert_true(state.is_dead(), "now DEAD")
	assert_eq(String(state.death_cause), "slain", "death cause recorded on transition")
	assert_eq(state.current_hp, 0, "HP zeroed on death")
	# DEAD is terminal: a second kill is rejected (no revive in Phase 04).
	assert_false(state.mark_dead(&"again"), "second mark_dead rejected")
	assert_eq(String(state.death_cause), "slain", "death cause not overwritten by rejected kill")


func test_set_current_hp_clamps() -> void:
	var state = StateScript.create_from_template(_template(), &"inst_1")
	state.set_current_hp(1000)
	assert_eq(state.current_hp, 80, "clamped to max_hp")
	state.set_current_hp(-5)
	assert_eq(state.current_hp, 0, "clamped to 0")
	assert_true(state.is_alive(), "set_current_hp alone does NOT change life_state")


func test_round_trip_preserves_persistent_state() -> void:
	var state = StateScript.create_from_template(_template(), &"inst_1")
	state.set_current_hp(40)
	state.realm_id = &"realm_qi"
	state.cultivation_progress = 7
	state.reputation = {"sect_x": 3}
	state.story_flags = {"met_elder": true}

	var dict := state.to_dict()
	var restored = StateScript.new()
	assert_true(restored.from_dict(dict), "from_dict accepts a well-formed snapshot")

	assert_eq(String(restored.instance_id), "inst_1")
	assert_eq(String(restored.template_id), "char_hero")
	assert_eq(restored.max_hp, 80)
	assert_eq(restored.current_hp, 40, "wounded HP round-trips")
	assert_eq(String(restored.realm_id), "realm_qi")
	assert_eq(restored.cultivation_progress, 7)
	assert_eq(restored.reputation.get("sect_x"), 3, "reputation round-trips")
	assert_true(bool(restored.story_flags.get("met_elder")), "story flags round-trip")
	assert_true(restored.is_alive(), "life_state round-trips")


func test_round_trip_preserves_dead_state() -> void:
	var state = StateScript.create_from_template(_template(), &"inst_1")
	state.mark_dead(&"poison")
	var restored = StateScript.new()
	assert_true(restored.from_dict(state.to_dict()))
	assert_true(restored.is_dead(), "DEAD life_state round-trips")
	assert_eq(String(restored.death_cause), "poison", "death_cause round-trips")


func test_from_dict_rejects_invalid_snapshots() -> void:
	var state = StateScript.new()
	assert_false(state.from_dict({}), "missing instance_id rejected")
	assert_false(state.from_dict({"instance_id": "x", "max_hp": 0}),
		"max_hp <= 0 rejected")
	assert_false(state.from_dict({"instance_id": "x", "max_hp": 10, "current_hp": 50}),
		"current_hp above max rejected")
	assert_false(state.from_dict({"instance_id": "x", "max_hp": 10, "life_state": 99}),
		"out-of-range life_state rejected")


## The persistent tier must not carry presentation/runtime fields (L-001 / §3). Guard that
## the serialized dict contains NO node/position/scene/sprite keys.
func test_to_dict_has_no_presentation_fields() -> void:
	var state = StateScript.create_from_template(_template(), &"inst_1")
	var dict := state.to_dict()
	for forbidden in ["node", "position", "x", "y", "scene", "sprite", "camera", "map"]:
		assert_false(dict.has(forbidden), "persistent dict must not contain '%s'" % forbidden)
