extends TestCase
## Integration tests for `StoryRuntime` (Phase 20, D-072) on REAL owners: the Knowledge Core,
## the relationship graph and the bag each run their own session, and the story reaches them
## only through the seams it is given. The world is a stand-in for the four things the story
## asks a world for (the player's record, the registry, the map lookup, the current map) and
## the one signal it listens to. No live `/root` singleton is touched (D-019).

const StoryScript := preload("res://src/gameplay/world/story_runtime.gd")
const KnowledgeScript := preload("res://src/gameplay/world/knowledge_runtime.gd")
const CultivationScript := preload("res://src/gameplay/world/cultivation_runtime.gd")
const InventoryScript := preload("res://src/gameplay/world/inventory_runtime.gd")
const RelationshipScript := preload("res://src/gameplay/world/relationship_runtime.gd")
const RegistryScript := preload("res://src/domain/character/character_registry.gd")

const PLAYER_TEMPLATE := "res://data/characters/player_default.tres"
const SCENES_PATH := "res://data/story/story_scene_catalog.tres"
const CAST := {
	&"actor_elder_shen": "res://data/characters/npc_elder_shen.tres",
	&"actor_disciple_lin": "res://data/characters/npc_disciple_lin.tres",
	&"actor_scout_ko": "res://data/characters/npc_scout_ko.tres",
	&"actor_carter_te": "res://data/characters/npc_carter_te.tres",
}
const SHEN := &"actor_elder_shen"
const LIN := &"actor_disciple_lin"
const KO := &"actor_scout_ko"
const PLAYER := &"player"
const K := StoryTriggerData.Kind


class StubWorld extends Node:
	signal active_map_ready()
	var character: CharacterState = null
	var registry: CharacterRegistry = null
	var map_id: StringName = &"map_hub"

	func get_player_character() -> CharacterState:
		return character

	func get_character_registry() -> CharacterRegistry:
		return registry

	func get_map_lookup() -> Dictionary:
		return {&"map_hub": true, &"map_field": true}

	func get_current_map_id() -> StringName:
		return map_id

	func get_active_map() -> Node:
		return null

	func get_player() -> Node:
		return null


class Rig extends RefCounted:
	var world: StubWorld
	var knowledge: KnowledgeRuntime
	var cultivation: CultivationRuntime
	var inventory: InventoryRuntime
	var relationship: RelationshipRuntime
	var story: StoryRuntime
	var log: Array[String] = []
	## What the record said at the moment each announcement was heard.
	var committed_when_heard: Array[bool] = []

	func on_beat(beat_id: StringName) -> void:
		log.append("beat %s" % beat_id)
		committed_when_heard.append(story.get_service().state().has_completed(beat_id))

	func on_chapter(chapter_id: StringName) -> void:
		log.append("chapter %s" % chapter_id)

	func on_choice(choice_id: StringName, option_id: StringName) -> void:
		log.append("choice %s=%s" % [choice_id, option_id])
		committed_when_heard.append(
			story.get_service().state().option_of(choice_id) == option_id)


func _rig() -> Rig:
	var rig := Rig.new()
	rig.world = StubWorld.new()
	add_to_tree(rig.world)
	rig.world.character = CharacterState.create_from_template(
		load(PLAYER_TEMPLATE) as CharacterTemplateData, PLAYER)
	rig.world.registry = RegistryScript.new()
	rig.world.registry.add(rig.world.character)
	for actor_id: StringName in CAST:
		rig.world.registry.add(CharacterState.create_from_template(
			load(CAST[actor_id]) as CharacterTemplateData, actor_id))
	rig.knowledge = KnowledgeScript.new()
	add_to_tree(rig.knowledge)
	rig.knowledge.start_session()
	rig.cultivation = CultivationScript.new()
	add_to_tree(rig.cultivation)
	rig.cultivation.start_session(rig.world.character, rig.knowledge, rig.world)
	rig.inventory = InventoryScript.new()
	add_to_tree(rig.inventory)
	rig.inventory.start_session(rig.world.character, rig.world, rig.knowledge, rig.cultivation)
	rig.relationship = RelationshipScript.new()
	add_to_tree(rig.relationship)
	rig.relationship.start_session()
	rig.story = StoryScript.new()
	add_to_tree(rig.story)
	rig.story.beat_completed.connect(rig.on_beat)
	rig.story.chapter_entered.connect(rig.on_chapter)
	rig.story.choice_recorded.connect(rig.on_choice)
	return rig


func _start(rig: Rig, origin_id: StringName, scenes: StorySceneCatalogData = null) -> bool:
	return rig.story.start_session(rig.world, rig.knowledge, rig.relationship, rig.inventory,
		origin_id, null, null, scenes)


func _free(rig: Rig) -> void:
	rig.story.beat_completed.disconnect(rig.on_beat)
	rig.story.chapter_entered.disconnect(rig.on_chapter)
	rig.story.choice_recorded.disconnect(rig.on_choice)
	rig.story.end_session()
	rig.relationship.end_session()
	rig.inventory.end_session()
	rig.cultivation.end_session()
	rig.knowledge.end_session()
	for node: Node in [rig.story, rig.relationship, rig.inventory, rig.cultivation,
			rig.knowledge, rig.world]:
		free_node(node)


func _regard(rig: Rig, who: StringName, dimension: StringName) -> int:
	return RegardRules.read(rig.relationship.get_service(), rig.relationship.get_config(),
		who, PLAYER, dimension)


func _known(rig: Rig) -> Array[String]:
	var ids: Array[String] = []
	for entry in rig.knowledge.get_catalog().entries:
		if rig.knowledge.get_service().knows(entry.id):
			ids.append(String(entry.id))
	ids.sort()
	return ids


## Everything a refused start must leave untouched.
func _untouched(rig: Rig) -> bool:
	return rig.inventory.get_bag().stack_count() == 0 and _known(rig).is_empty() \
		and rig.relationship.get_store().edge_count() == 0 \
		and rig.world.character.story_flags.is_empty()


func _skip_all(rig: Rig) -> void:
	for _i in 16:
		if not rig.story.is_scene_playing():
			return
		rig.story.skip_scene()


# === Starting as each Origin ================================================

## What each Origin starts with reaches the REAL owners, exactly once, and nothing else moves.
func test_each_origin_hands_over_exactly_its_own_kit_through_the_owners() -> void:
	var expected := {
		&"origin_ho_tieu": {"items": {&"item_kiem_thanh_thiet": 1}, "known": [],
			"regard": [[SHEN, &"affinity", -10]]},
		&"origin_de_tu_bi_loai": {"items": {}, "known": ["know_dan_khi_quyet"],
			"regard": [[LIN, &"rivalry", 15]]},
		&"origin_lang_y": {"items": {&"item_bo_huyet_dan": 2}, "known": [], "regard": []},
		&"origin_nghe_nhan": {"items": {}, "known": ["know_vein_stone_grades"], "regard": []},
		&"origin_thu_thu": {"items": {}, "known": ["know_survey_notation"],
			"regard": [[SHEN, &"affinity", -15]]},
	}
	assert_eq(expected.size(), OriginCatalogData.FROZEN_IDS.size(), "all five are covered")
	for origin_id: StringName in expected:
		var rig := _rig()
		assert_true(_start(rig, origin_id), "%s: the session starts" % origin_id)
		var want: Dictionary = expected[origin_id]
		var items: Dictionary = want["items"]
		assert_eq(rig.inventory.get_bag().stack_count(), items.size(),
			"%s: the bag holds its kit and nothing else" % origin_id)
		for item_id: StringName in items:
			assert_eq(rig.inventory.count_of(item_id), items[item_id],
				"%s: %s x%d" % [origin_id, item_id, items[item_id]])
		assert_eq(_known(rig), want["known"], "%s: knows exactly this" % origin_id)
		var moved: Array = want["regard"]
		assert_eq(rig.relationship.get_store().edge_count(), moved.size(),
			"%s: %d first impression(s), no other edge" % [origin_id, moved.size()])
		for move: Array in moved:
			assert_eq(_regard(rig, move[0], move[1]), move[2],
				"%s: %s regards the player %s %d" % [origin_id, move[0], move[1], move[2]])
		assert_true(rig.story.get_service().origin_is(origin_id), "%s is the run's Origin"
			% origin_id)
		assert_eq(rig.world.character.sect_id, &"", "%s: and no sect came with it" % origin_id)
		assert_true(rig.world.character.story_flags.is_empty(), "%s: nor any flag" % origin_id)
		_free(rig)


# === Fail closed ============================================================

func test_a_session_that_cannot_begin_gives_nothing_and_listens_to_nothing() -> void:
	var rig := _rig()
	assert_false(_start(rig, &"origin_chosen_one"), "an unknown Origin does not start")
	assert_false(rig.story.is_session_active(), "no session")
	assert_null(rig.story.get_service(), "no service")
	assert_true(_untouched(rig), "and nothing was given")
	assert_eq(rig.knowledge.knowledge_gained.get_connections().size(), 0,
		"nor is the story left listening to the Knowledge Core")
	assert_eq(rig.world.active_map_ready.get_connections().size(), 0, "or to the world")

	var cyrillic := StringName("origin_h" + char(0x043E) + "_tieu")
	assert_false(_start(rig, cyrillic), "the look-alike id is not an Origin")
	assert_true(_untouched(rig), "and gives nothing")
	_free(rig)


func test_a_missing_or_inactive_dependency_refuses_the_start() -> void:
	var rig := _rig()
	assert_false(rig.story.start_session(null, rig.knowledge, rig.relationship,
		rig.inventory, &"origin_lang_y"), "no world")
	rig.inventory.end_session()
	assert_false(_start(rig, &"origin_lang_y"), "a bag whose session ended")
	assert_false(rig.story.is_session_active(), "no session")
	assert_true(_known(rig).is_empty() and rig.relationship.get_store().edge_count() == 0,
		"and nothing was given")
	_free(rig)


## ITEMS GO FIRST, as one all-or-nothing ask of the bag: a kit that does not fit must leave
## the OTHER owners untouched too (here, the elder's first impression).
func test_a_kit_that_does_not_fit_gives_nothing_to_anyone() -> void:
	var rig := _rig()
	rig.inventory.get_bag().capacity = 0
	assert_false(_start(rig, &"origin_ho_tieu"), "the blade does not fit: no start")
	assert_false(rig.story.is_session_active(), "no session")
	assert_true(_untouched(rig), "no item, no knowledge, no regard, no flag")
	assert_eq(_regard(rig, SHEN, &"affinity"), 0, "the elder's regard did not move")
	_free(rig)


func test_content_that_names_a_missing_scene_refuses_the_start() -> void:
	var rig := _rig()
	var scenes := (load(SCENES_PATH) as StorySceneCatalogData).duplicate() \
		as StorySceneCatalogData
	var kept: Array[StorySceneData] = []
	for scene in scenes.entries:
		if scene.id != &"scene_vignette_lang_y":
			kept.append(scene)
	scenes.entries = kept
	assert_false(_start(rig, &"origin_ho_tieu", scenes),
		"an Origin whose vignette does not exist stops EVERY run from starting")
	assert_true(_untouched(rig), "and nothing was given")
	_free(rig)


func test_a_second_start_is_refused_and_gives_nothing_twice() -> void:
	var rig := _rig()
	assert_true(_start(rig, &"origin_lang_y"), "started")
	assert_false(_start(rig, &"origin_lang_y"), "a session starts once")
	assert_false(_start(rig, &"origin_ho_tieu"), "and not again as someone else")
	assert_eq(rig.inventory.count_of(&"item_bo_huyet_dan"), 2, "the kit was handed over once")
	assert_eq(rig.inventory.count_of(&"item_kiem_thanh_thiet"), 0, "and no second kit")
	_free(rig)


# === Scenes change nothing ==================================================

func test_a_run_opens_on_its_origins_vignette_then_the_arrival() -> void:
	var rig := _rig()
	_start(rig, &"origin_thu_thu")
	assert_true(rig.story.is_scene_playing(), "a scene is showing")
	var view := rig.story.build_scene_view()
	assert_eq(view.scene_id, &"scene_vignette_thu_thu", "the run's own vignette")
	assert_eq(view.kind, StorySceneStepData.Kind.CARD, "which opens on where and when")
	assert_true(view.elsewhere, "and is somewhere else: the map is covered")
	assert_eq([view.step_index, view.step_count], [0, 4], "step 1 of 4")
	assert_eq(rig.story.get_service().state().beat_id, &"beat_road", "the first beat")
	for step in 3:
		rig.story.advance_scene()
		assert_eq(rig.story.build_scene_view().step_index, step + 1, "one step per request")
	rig.story.advance_scene()
	assert_eq(rig.log, ["beat beat_road"] as Array[String], "the vignette ending is the beat")
	assert_eq(rig.story.build_scene_view().scene_id, &"scene_arrival",
		"and the next beat's own scene follows")
	assert_false(rig.story.build_scene_view().elsewhere, "which is HERE: the map shows")
	_skip_all(rig)
	assert_false(rig.story.is_scene_playing(), "then the player has control")
	assert_null(rig.story.build_scene_view(), "and there is no step to show")
	assert_eq(rig.story.get_service().state().beat_id, &"beat_arrival", "on the arrival beat")
	_free(rig)


## SKIPPING IS NOT A SHORTCUT AROUND ANYTHING: watched to the end or skipped at the first
## step, the record is the same — because a scene never changed it.
func test_skipping_a_scene_leaves_exactly_the_record_that_watching_it_does() -> void:
	var records: Array[String] = []
	var owners: Array[String] = []
	for skip: bool in [false, true]:
		var rig := _rig()
		_start(rig, &"origin_ho_tieu")
		for _i in 32:
			if not rig.story.is_scene_playing():
				break
			if skip:
				rig.story.skip_scene()
			else:
				rig.story.advance_scene()
		records.append(str(rig.story.to_dict()) + str(rig.world.character.story_flags))
		owners.append(str([rig.inventory.get_bag().to_dict(), _known(rig),
			_regard(rig, SHEN, &"affinity")]))
		_free(rig)
	assert_eq(records[1], records[0], "the same story record")
	assert_eq(owners[1], owners[0], "and the same bag, knowledge and regard")


func test_scene_requests_with_no_scene_do_nothing() -> void:
	var rig := _rig()
	_start(rig, &"origin_lang_y")
	_skip_all(rig)
	var before := str(rig.story.to_dict())
	rig.story.advance_scene()
	rig.story.skip_scene()
	assert_eq(str(rig.story.to_dict()), before, "a late key press changes nothing")
	_free(rig)


# === The session tells the story what happened ===============================

func test_the_story_is_announced_after_it_is_committed() -> void:
	var rig := _rig()
	_start(rig, &"origin_lang_y")
	_skip_all(rig)
	rig.log.clear()
	rig.committed_when_heard.clear()
	rig.story.meet(SHEN)
	assert_eq(rig.log, ["beat beat_arrival"] as Array[String], "meeting someone is arriving")
	rig.story.meet(SHEN)
	assert_eq(rig.log.size(), 1, "meeting them again announces nothing")
	rig.story.meet(LIN)
	rig.story.meet(KO)
	rig.story.set_flag(&"flag_heard_village_business")
	var chosen := rig.story.choose(&"choice_lam_readings", &"kept")
	assert_true(chosen.ok, "the first decision is recorded")
	assert_eq(rig.story.choose(&"choice_lam_readings", &"told").reason,
		StoryService.REFUSE_ALREADY_CHOSEN, "once")
	assert_eq(rig.log, ["beat beat_arrival", "beat beat_contacts", "beat beat_village_business",
		"choice choice_lam_readings=kept", "beat beat_confidence"] as Array[String],
		"each step was announced, once, in order")
	assert_false(rig.committed_when_heard.has(false),
		"and every announcement was heard AFTER the record already said so")
	assert_eq(_regard(rig, LIN, &"trust"), 15, "the decision moved Lin Yue's trust, once")
	_free(rig)


func test_arriving_in_the_woods_only_matters_once_the_night_is_due() -> void:
	var rig := _rig()
	_start(rig, &"origin_lang_y")
	_skip_all(rig)
	rig.world.map_id = &"map_field"
	rig.world.active_map_ready.emit()
	assert_eq(rig.story.get_service().state().beat_id, &"beat_arrival",
		"walking into the woods on the first afternoon is not the Night")
	for who: StringName in [SHEN, LIN, KO]:
		rig.story.meet(who)
	rig.story.set_flag(&"flag_heard_village_business")
	rig.story.choose(&"choice_lam_readings", &"told")
	assert_eq(rig.story.get_service().state().beat_id, &"beat_warning", "the Night is due")
	rig.world.map_id = &"map_hub"
	rig.world.active_map_ready.emit()
	assert_eq(rig.story.get_service().state().beat_id, &"beat_warning",
		"arriving in the village is not it")
	rig.world.map_id = &"map_field"
	rig.world.active_map_ready.emit()
	assert_eq(rig.story.get_service().state().beat_id, &"beat_night", "arriving in the woods is")
	rig.world.active_map_ready.emit()
	assert_eq(rig.story.get_service().state().beat_id, &"beat_night",
		"and arriving again does not happen twice")
	_free(rig)


func test_knowledge_gained_anywhere_moves_a_beat_that_waits_for_it() -> void:
	var rig := _rig()
	_start(rig, &"origin_lang_y")
	_skip_all(rig)
	for who: StringName in [SHEN, LIN, KO]:
		rig.story.meet(who)
	rig.story.set_flag(&"flag_heard_village_business")
	rig.story.choose(&"choice_lam_readings", &"kept")
	rig.world.map_id = &"map_field"
	rig.world.active_map_ready.emit()
	rig.story.choose(&"choice_night_stand", &"withdrew")
	assert_eq(_regard(rig, KO, &"affinity"), -5, "withdrawing cost a little of the scout's regard")
	rig.story.set_flag(&"flag_heard_elder_account")
	rig.story.note_cultivated()
	assert_eq(rig.story.get_service().state().beat_id, &"beat_sheet_told",
		"having kept her confidence, Lin Yue tells you where to look")
	rig.knowledge.grant(&"know_survey_fragment", &"source_test")
	assert_eq(rig.story.get_service().state().beat_id, &"beat_leaving",
		"the Knowledge Core said so, and the story heard it")
	rig.story.set_flag(&"flag_heard_road_ahead")
	assert_true(rig.log.has("chapter chapter_ke_vo_danh"), "Act I was announced")
	assert_true(rig.story.get_service().current_beat().terminal, "and the story rests")
	assert_ne(rig.story.build_view().objective_key, &"", "with a purpose that is not blank")
	_free(rig)


# === Persistence boundary, and teardown =====================================

func test_a_mid_run_record_round_trips_through_the_runtime() -> void:
	var rig := _rig()
	_start(rig, &"origin_de_tu_bi_loai")
	_skip_all(rig)
	rig.story.meet(SHEN)
	rig.story.set_flag(&"flag_heard_village_business")
	var story := rig.story.to_dict()
	var character := rig.world.character.to_dict()
	assert_eq(story["origin_id"], "origin_de_tu_bi_loai", "the Origin is in the record")
	assert_false(story.has("flags"), "flags are not")

	var other := _rig()
	_start(other, &"origin_de_tu_bi_loai")
	_skip_all(other)
	assert_true(other.world.character.from_dict(character), "the character first")
	assert_true(other.story.from_dict(story), "then the story")
	assert_eq(str(other.story.to_dict()), str(story), "byte-stable")
	assert_eq(other.story.get_service().flag_value(&"flag_heard_village_business"), 1,
		"the flag came with the character")
	assert_eq(_regard(other, LIN, &"rivalry"), 15, "restoring did not hand the kit over again")
	var bad: Dictionary = story.duplicate(true)
	bad["origin_id"] = "origin_chosen_one"
	assert_false(other.story.from_dict(bad), "a bad record is refused")
	assert_eq(str(other.story.to_dict()), str(story), "and the good one is kept")
	_free(other)
	_free(rig)


func test_ending_the_session_stops_listening_and_is_idempotent() -> void:
	var rig := _rig()
	_start(rig, &"origin_lang_y")
	assert_eq(rig.knowledge.knowledge_gained.get_connections().size(), 1, "listening")
	assert_eq(rig.world.active_map_ready.get_connections().size(), 1, "to both")
	rig.story.end_session()
	rig.story.end_session()
	assert_false(rig.story.is_session_active(), "ended")
	assert_eq(rig.knowledge.knowledge_gained.get_connections().size(), 0, "not listening")
	assert_eq(rig.world.active_map_ready.get_connections().size(), 0, "to either")
	assert_false(rig.story.is_scene_playing(), "and no scene is left showing")
	assert_false(rig.story.meet(SHEN).ok, "nor does a late request do anything")
	assert_eq(rig.story.to_dict(), {}, "and there is no record")
	_free(rig)
