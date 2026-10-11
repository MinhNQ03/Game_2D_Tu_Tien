extends TestCase
## Drift guards over the story content that actually SHIPS (Phase 20, D-072): the catalogs
## validate, every id is stable ASCII and matches canon byte for byte, every line has both
## languages, everything named exists in its owner's content, and the authored prologue can be
## walked to where it rests down BOTH of its branches.

const STORY_PATH := "res://data/story/story_catalog.tres"
const ORIGINS_PATH := "res://data/story/origin_catalog.tres"
const KNOWLEDGE_PATH := "res://data/knowledge/knowledge_catalog.tres"
const ITEMS_PATH := "res://data/items/item_catalog.tres"
const WORLD_SIM_PATH := "res://data/worldsim/world_sim_catalog.tres"
const RELATIONSHIP_PATH := "res://data/relationship/relationship_config.tres"
const MAPS_PATH := "res://data/maps/map_catalog.tres"
const LOCALE_PATH := "res://locale/aetheria.csv"
const PLAYER_TEMPLATE := "res://data/characters/player_default.tres"

const K := StoryTriggerData.Kind


func _story() -> StoryCatalogData:
	return load(STORY_PATH) as StoryCatalogData


func _origins() -> OriginCatalogData:
	return load(ORIGINS_PATH) as OriginCatalogData


## key -> true for every key that has a non-empty string in EVERY language column.
func _translated() -> Dictionary:
	var out := {}
	var file := FileAccess.open(LOCALE_PATH, FileAccess.READ)
	var header := file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() != header.size() or row[0] == "":
			continue
		var complete := true
		for i in range(1, row.size()):
			complete = complete and row[i].strip_edges() != ""
		out[row[0]] = complete
	return out


func test_the_shipped_catalogs_are_valid() -> void:
	assert_not_null(_story(), "the story catalog loads")
	assert_not_null(_origins(), "the origin catalog loads")
	assert_eq(_story().validation_errors(), [] as Array[String], "the story validates")
	assert_eq(_origins().validation_errors(), [] as Array[String], "the origins validate")


func test_the_five_origins_match_canon_byte_for_byte() -> void:
	var expected: Array[String] = ["origin_ho_tieu", "origin_de_tu_bi_loai", "origin_lang_y",
		"origin_nghe_nhan", "origin_thu_thu"]
	var shipped: Array[String] = []
	for id in _origins().ids():
		shipped.append(String(id))
	assert_eq(shipped, expected, "exactly the five of NARRATIVE_MASTER_PLAN.md §6, in order")
	for id in shipped:
		assert_eq(id.to_utf8_buffer().size(), id.length(), "'%s' is pure ASCII" % id)
	for doc: String in ["res://docs/CANON_LEDGER.md", "res://docs/NARRATIVE_MASTER_PLAN.md"]:
		var text := FileAccess.get_file_as_string(doc)
		for id in expected:
			assert_true(text.contains("`%s`" % id), "%s names `%s` exactly" % [doc, id])
		assert_false(text.contains("origin_h" + char(0x043E)),
			"%s no longer carries the Cyrillic look-alike" % doc)


func test_every_shipped_story_id_is_stable_ascii() -> void:
	var ids: Array[StringName] = []
	var story := _story()
	for chapter in story.chapters:
		ids.append(chapter.id)
	for beat in story.all_beats():
		ids.append(beat.id)
	for flag in story.flags:
		ids.append(flag.id)
	for choice in story.choices:
		ids.append(choice.id)
		for option in choice.options:
			ids.append(option.id)
	ids.append_array(_origins().ids())
	assert_true(ids.size() >= 29, "the scan saw the content (%d ids)" % ids.size())
	for id in ids:
		assert_true(StoryIds.is_stable(id), "'%s' is a stable id" % id)


func test_every_line_the_story_shows_exists_in_both_languages() -> void:
	var translated := _translated()
	var keys := _story().text_keys()
	for origin in _origins().entries:
		keys.append_array(origin.text_keys())
	assert_true(keys.size() >= 50, "the scan saw the text (%d keys)" % keys.size())
	for key in keys:
		assert_true(translated.get(String(key), false),
			"'%s' has an English and a Vietnamese line" % key)
		assert_true(String(key) == String(key).to_upper(), "'%s' is a key, not prose" % key)


## Everything the story names in another owner's content must exist there, and a regard that
## is meant to FALL must be on a dimension that can — `trust` and `respect` stop at 0, so a
## negative move on them is a consequence nobody could ever feel.
func test_everything_the_story_names_exists_in_its_owners_content() -> void:
	var knowledge := load(KNOWLEDGE_PATH) as KnowledgeCatalogData
	var items := load(ITEMS_PATH) as ItemCatalogData
	var world_sim := load(WORLD_SIM_PATH) as WorldSimCatalog
	var maps := load(MAPS_PATH) as MapCatalog
	var relationship := load(RELATIONSHIP_PATH) as RelationshipConfigData
	var map_ids := maps.build_lookup()
	var cast := {}
	for actor in world_sim.actors:
		cast[actor.id] = true
	var floors := {}
	for dimension: Dictionary in relationship.dimensions:
		floors[dimension["id"]] = int(dimension["min"])
	var player := CharacterState.create_from_template(
		load(PLAYER_TEMPLATE) as CharacterTemplateData, &"player_test")
	var service := StoryService.new(_story(), _origins(), StoryState.new(), player,
		StoryOwners.new())
	assert_true(service.is_ready(), "the service accepts the shipped catalogs")
	var errors := service.content_errors(
		func(key: StringName) -> bool: return _translated().get(String(key), false),
		func(id: StringName) -> bool: return knowledge.has(id),
		func(id: StringName) -> CharacterState: return player if cast.has(id) else null,
		func(id: StringName) -> bool: return floors.has(id),
		func(id: StringName) -> bool: return items.entry(id) != null,
		func(id: StringName) -> bool: return map_ids.has(id))
	assert_eq(errors, [] as Array[String], "every owner can supply what the story asks for")

	var falls := 0
	for choice in _story().choices:
		for option in choice.options:
			for consequence in option.consequences:
				if consequence.kind == StoryConsequenceData.Kind.REGARD and consequence.delta < 0:
					falls += 1
					assert_true(int(floors[consequence.dimension]) < 0,
						"%s/%s lowers '%s', which can go below zero"
						% [choice.id, option.id, consequence.dimension])
	for origin in _origins().entries:
		for grant in origin.grants:
			if grant.kind == OriginGrantData.Kind.REGARD and grant.delta < 0:
				falls += 1
				assert_true(int(floors[grant.dimension]) < 0,
					"%s lowers '%s', which can go below zero" % [origin.id, grant.dimension])
	assert_true(falls >= 3, "the scan saw the falling regards (%d)" % falls)


## The authored prologue, walked to where the story rests, down both branches.
func test_the_prologue_can_be_walked_to_act_one_down_both_branches() -> void:
	var paths := {}
	for answer: StringName in [&"kept", &"told"]:
		var owners := StoryFixture.Owners.new()
		var state := StoryState.new()
		var player := CharacterState.create_from_template(
			load(PLAYER_TEMPLATE) as CharacterTemplateData, &"player_test")
		var service := StoryService.new(_story(), _origins(), state, player, owners.seams)
		assert_true(service.begin(&"origin_lang_y").ok, "the run begins")
		assert_eq(state.beat_id, &"beat_road", "on the road")
		service.note(K.SCENE_ENDED, &"any_scene")
		assert_eq(state.beat_id, &"beat_arrival", "then arriving")
		service.meet(&"actor_elder_shen")
		assert_eq(state.beat_id, &"beat_contacts", "one person met: now meet the rest")
		service.meet(&"actor_disciple_lin")
		service.meet(&"actor_scout_ko")
		assert_eq(state.beat_id, &"beat_village_business", "all three met")
		service.set_flag(&"flag_heard_village_business", 1)
		assert_eq(state.beat_id, &"beat_confidence", "the village's business was heard")
		assert_eq(service.choose(&"choice_night_stand", &"stood").reason,
			StoryService.REFUSE_WRONG_BEAT, "the Night cannot be answered before it happens")
		assert_true(service.choose(&"choice_lam_readings", answer).ok, "the first decision")
		assert_eq(state.beat_id, &"beat_warning", "the Night is now due")
		service.note(K.ARRIVED, &"map_hub")
		assert_eq(state.beat_id, &"beat_warning", "arriving in the village is not the rupture")
		service.note(K.ARRIVED, &"map_field")
		assert_eq(state.beat_id, &"beat_night", "arriving in the woods is")
		service.choose(&"choice_night_stand", &"stood")
		assert_eq(state.beat_id, &"beat_aftermath", "the morning after")
		service.set_flag(&"flag_heard_elder_account", 1)
		assert_eq(state.beat_id, &"beat_settle", "then sitting down")
		service.note(K.CULTIVATED)
		paths[answer] = state.beat_id
		assert_false(service.current_beat().terminal, "the sheet is still to be found")
		owners.known[&"know_survey_fragment"] = true
		service.refresh()
		assert_eq(state.beat_id, &"beat_leaving", "'%s' converges on leaving" % answer)
		var last := service.set_flag(&"flag_heard_road_ahead", 1)
		assert_true(last.chapter_changed, "the prologue ends")
		assert_eq(state.chapter_id, &"chapter_ke_vo_danh", "Act I begins")
		assert_true(service.current_beat().terminal, "and the story rests on a standing purpose")
		assert_ne(service.objective_key(), &"", "which is not blank (Q19-03)")
		assert_eq(state.completed_beats.size(), 11, "eleven beats were completed on the way")
	assert_eq(paths[&"kept"], &"beat_sheet_told", "having kept her confidence, she tells you")
	assert_eq(paths[&"told"], &"beat_sheet_found", "having told the elder, you find it yourself")


## THE ONE-WRITER RULE, read from the source: outside the story domain and the character's
## own serialization, nothing in `src` writes `story_flags`.
func test_nothing_but_the_story_service_writes_story_flags() -> void:
	var allowed := ["res://src/domain/story/story_service.gd",
		"res://src/domain/character/character_state.gd"]
	var writers: Array[String] = []
	var scanned := 0
	for path in _scripts("res://src"):
		scanned += 1
		if allowed.has(path):
			continue
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var code := line.split("#")[0]
			if code.contains("story_flags[") and code.contains("=") \
					or code.contains("story_flags =") or code.contains("story_flags.erase") \
					or code.contains("story_flags.clear") or code.contains("story_flags.merge"):
				writers.append("%s: %s" % [path.trim_prefix("res://"), line.strip_edges()])
	assert_true(scanned > 150, "the scan read the source (%d scripts)" % scanned)
	assert_eq(writers, [] as Array[String], "story_flags has one writer (D-072 §1)")


func _scripts(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for sub in dir.get_directories():
		out.append_array(_scripts("%s/%s" % [dir_path, sub]))
	for file in dir.get_files():
		if file.ends_with(".gd"):
			out.append("%s/%s" % [dir_path, file])
	return out
