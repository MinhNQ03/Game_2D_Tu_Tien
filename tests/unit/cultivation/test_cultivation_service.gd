extends TestCase
## `CultivationService` — the cảnh giới rules (Phase 12). Exit: realm unlocks work,
## serializable, breakthrough rules tested, and a prerequisite READS the Knowledge Core.

const LADDER := "res://data/progression/realm_ladder.tres"
const CATALOG := "res://data/knowledge/knowledge_catalog.tres"


func _knowledge() -> KnowledgeService:
	return KnowledgeService.new(load(CATALOG), KnowledgeStore.new())


func _mortal() -> CharacterState:
	var state := CharacterState.new()
	state.instance_id = &"inst_test"
	state.realm_id = &"realm_pham"
	return state


func test_the_shipped_ladder_is_canon_and_valid() -> void:
	var ladder: RealmLadderData = load(LADDER)
	assert_true(ladder.is_valid(), "ladder validates: %s" % str(ladder.validation_errors()))
	assert_eq(ladder.realms.size(), 7, "seven tiers (CL-02)")
	assert_eq(ladder.first().id, &"realm_pham", "everyone starts mortal")
	assert_true(ladder.realm(&"realm_thai_thien").structural, "Thái Thiên is structural")
	var catalog: KnowledgeCatalogData = load(CATALOG)
	for realm in ladder.realms:
		for know in realm.entry_knowledge:
			assert_true(catalog.has(know), "%s requires '%s', which the catalog names"
				% [realm.id, know])


func test_every_layer_moves_a_non_damage_dimension() -> void:
	var realm: RealmData = (load(LADDER) as RealmLadderData).realm(&"realm_hau_thien").duplicate()
	assert_true(realm.is_valid(), "Hậu Thiên validates")
	realm.perception_px[4] = realm.perception_px[3]
	realm.qi_capacity[4] = realm.qi_capacity[3]
	realm.gather_efficiency[4] = realm.gather_efficiency[3]
	assert_false(realm.is_valid(), "a layer that moves nothing is refused (§3)")


func test_gathering_fills_a_step_and_never_banks_surplus() -> void:
	var service := CultivationService.new(load(LADDER), _knowledge())
	var state := _mortal()
	var cost := service.step_cost(state)
	assert_eq(cost, 30, "PHÀM's step is authored at 30")
	assert_true(service.gather(state, 12).accepted, "gathering is accepted")
	assert_eq(state.cultivation_progress, 12, "progress recorded")
	service.gather(state, 999)
	assert_eq(state.cultivation_progress, cost, "capped at the step: surplus is lost")
	var full := service.gather(state, 1)
	assert_eq(full.reason, CultivationResult.REASON_FULL, "a full step refuses more")
	assert_false(service.gather(state, -1).accepted, "a negative gather is refused")


func test_a_breakthrough_reads_the_knowledge_core() -> void:
	var knowledge := _knowledge()
	var service := CultivationService.new(load(LADDER), knowledge)
	var state := _mortal()
	assert_eq(service.breakthrough_blocker(state), CultivationResult.REASON_INSUFFICIENT,
		"an empty step cannot break through")
	service.gather(state, 30)
	var refused := service.breakthrough(state)
	assert_eq(refused.reason, CultivationResult.REASON_MISSING_KNOWLEDGE,
		"a full step without the method is WITHHELD")
	assert_eq(refused.missing, [&"know_dan_khi_quyet"] as Array[StringName], "and names what")
	assert_eq(state.realm_id, &"realm_pham", "nothing changed")
	knowledge.grant(&"know_dan_khi_quyet", &"test")
	var done := service.breakthrough(state)
	assert_true(done.changed_realm(), "with the knowledge, the realm changes")
	assert_eq([state.realm_id, state.realm_layer, state.cultivation_progress],
		[&"realm_hau_thien", 1, 0], "Hậu Thiên 1, the step spent")


func test_layers_advance_inside_a_realm_and_the_top_is_gated() -> void:
	var knowledge := _knowledge()
	knowledge.grant(&"know_dan_khi_quyet", &"t")
	var service := CultivationService.new(load(LADDER), knowledge)
	var state := _mortal()
	state.set_cultivation(&"realm_hau_thien", 1, 0)
	service.gather(state, service.step_cost(state))
	var step := service.breakthrough(state)
	assert_true(step.advanced() and not step.changed_realm(), "a layer step, not a realm step")
	assert_eq(state.realm_layer, 2, "Hậu Thiên 2")
	state.set_cultivation(&"realm_hau_thien", 9, 0)
	service.gather(state, service.step_cost(state))
	assert_eq(service.breakthrough_blocker(state), CultivationResult.REASON_MISSING_KNOWLEDGE,
		"Hậu Thiên 9 → Tiên Thiên needs knowledge no one in Lạc Hà has")


func test_capability_grows_with_the_realm() -> void:
	var service := CultivationService.new(load(LADDER), _knowledge())
	var mortal := _mortal()
	var opened := _mortal()
	opened.set_cultivation(&"realm_hau_thien", 1, 0)
	assert_eq(service.perception_px(mortal), 0.0, "a mortal senses no qi")
	assert_true(service.perception_px(opened) > 0.0, "Hậu Thiên senses qi nearby")
	assert_true(service.qi_capacity(opened) > service.qi_capacity(mortal), "and can hold qi")
	assert_true(service.meets(opened, &"realm_hau_thien", 1), "meets Hậu Thiên 1")
	assert_false(service.meets(mortal, &"realm_hau_thien", 1), "a mortal does not")
	assert_true(service.meets(opened, &"realm_pham"), "a higher realm meets a lower one")
	assert_false(service.meets(opened, &"realm_hau_thien", 3), "but not a higher layer")


func test_cultivation_serializes_with_type_checks() -> void:
	var state := _mortal()
	state.set_cultivation(&"realm_hau_thien", 4, 33)
	var copy := CharacterState.new()
	assert_true(copy.from_dict(state.to_dict()), "round trip")
	assert_eq([copy.realm_id, copy.realm_layer, copy.cultivation_progress],
		[&"realm_hau_thien", 4, 33], "realm, layer, progress survive")
	var bad := state.to_dict()
	bad["realm_layer"] = 4.0
	assert_false(CharacterState.new().from_dict(bad), "a float layer is refused (L-024)")
	bad = state.to_dict()
	bad["cultivation_progress"] = -2
	assert_false(CharacterState.new().from_dict(bad), "negative progress is refused")


## STRUCTURAL: only CharacterState and the service write a cultivation position.
func test_only_the_service_decides_a_cultivation_position() -> void:
	var offenders: Array[String] = []
	_walk("res://src", offenders)
	assert_eq(offenders, [] as Array[String],
		"only CultivationService may call set_cultivation(): %s" % str(offenders))


func _walk(dir_path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := "%s/%s" % [dir_path, entry]
		if dir.current_is_dir():
			_walk(full, out)
		elif entry.ends_with(".gd") and not full.ends_with("cultivation_service.gd") \
				and not full.ends_with("character_state.gd"):
			var text := FileAccess.get_file_as_string(full)
			if ".set_cultivation(" in text or "realm_layer =" in text \
					or "cultivation_progress =" in text:
				out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
