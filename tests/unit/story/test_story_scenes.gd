extends TestCase
## Story SCENES and the player's LOOKS (Phase 20, D-072 §2, §6): the scene data's own rules,
## and drift guards over what ships — every Origin's vignette, both languages, the looks the
## identity screen offers, and the garment drawn for each of them.

const StepScript := preload("res://src/data/story/story_scene_step_data.gd")
const SceneScript := preload("res://src/data/story/story_scene_data.gd")
const SceneCatalogScript := preload("res://src/data/story/story_scene_catalog_data.gd")
const AppearanceScript := preload("res://src/data/characters/player_appearance_data.gd")
const AppearanceCatalogScript := preload(
	"res://src/data/characters/player_appearance_catalog_data.gd")

const SCENES_PATH := "res://data/story/story_scene_catalog.tres"
const STORY_PATH := "res://data/story/story_catalog.tres"
const ORIGINS_PATH := "res://data/story/origin_catalog.tres"
const APPEARANCES_PATH := "res://data/characters/player_appearances.tres"
const ITEMS_PATH := "res://data/items/item_catalog.tres"
const LOCALE_PATH := "res://locale/aetheria.csv"

const S := StorySceneStepData.Kind


func _has(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if error.contains(fragment):
			return true
	return false


func _step(kind: int, text: StringName, sub: StringName = &"",
		speaker: StringName = &"") -> StorySceneStepData:
	var step: StorySceneStepData = StepScript.new()
	step.kind = kind as StorySceneStepData.Kind
	step.text_key = text
	step.sub_key = sub
	step.speaker_id = speaker
	return step


func _scene(id: StringName, steps: Array[StorySceneStepData]) -> StorySceneData:
	var scene: StorySceneData = SceneScript.new()
	scene.id = id
	scene.steps = steps
	return scene


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


# === Scene data =============================================================

func test_a_step_uses_only_what_its_kind_shows() -> void:
	assert_eq(_step(S.CARD, &"PLACE", &"TIME").validation_errors(), [] as Array[String])
	assert_eq(_step(S.CAPTION, &"TEXT").validation_errors(), [] as Array[String])
	assert_eq(_step(S.LINE, &"TEXT", &"", &"actor_a").validation_errors(), [] as Array[String])
	assert_true(_has(_step(S.CARD, &"PLACE").validation_errors(), "no time"),
		"a card says where AND when")
	assert_true(_has(_step(S.CAPTION, &"").validation_errors(), "shows no text"), "no text")
	assert_true(_has(_step(S.LINE, &"TEXT").validation_errors(), "no speaker"),
		"a line is said by someone")
	assert_true(_has(_step(S.CAPTION, &"TEXT", &"", &"actor_a").validation_errors(),
		"carries a speaker"), "narration has no speaker")


func test_a_scene_is_short_and_opens_with_its_card() -> void:
	var good: Array[StorySceneStepData] = [_step(S.CARD, &"P", &"T"), _step(S.CAPTION, &"A")]
	assert_eq(_scene(&"scene_x", good).validation_errors(), [] as Array[String], "valid")
	var empty: Array[StorySceneStepData] = []
	assert_true(_has(_scene(&"scene_x", empty).validation_errors(), "no steps"), "not empty")
	var late: Array[StorySceneStepData] = [_step(S.CAPTION, &"A"), _step(S.CARD, &"P", &"T")]
	assert_true(_has(_scene(&"scene_x", late).validation_errors(), "a card opens a scene"),
		"a card is the first step or not at all")
	var long: Array[StorySceneStepData] = []
	for i in StorySceneData.MAX_STEPS + 1:
		long.append(_step(S.CAPTION, StringName("T%d" % i)))
	assert_true(_has(_scene(&"scene_x", long).validation_errors(), "the ceiling is"),
		"the player is watching, not playing: a scene has a ceiling")
	var twins: Array[StorySceneData] = [_scene(&"scene_x", good), _scene(&"scene_x", good)]
	var catalog: StorySceneCatalogData = SceneCatalogScript.new()
	catalog.entries = twins
	assert_true(_has(catalog.validation_errors(), "duplicate scene id"), "ids are unique")


# === What ships =============================================================

func test_every_origin_has_its_own_vignette_and_every_named_scene_exists() -> void:
	var scenes := load(SCENES_PATH) as StorySceneCatalogData
	var origins := load(ORIGINS_PATH) as OriginCatalogData
	var story := load(STORY_PATH) as StoryCatalogData
	assert_eq(scenes.validation_errors(), [] as Array[String], "the shipped scenes validate")
	var vignettes := {}
	for origin in origins.entries:
		var scene := scenes.entry(origin.vignette_scene_id)
		assert_not_null(scene, "%s has a vignette that exists" % origin.id)
		if scene == null:
			continue
		assert_true(scene.elsewhere, "%s: a vignette is somewhere else" % origin.id)
		assert_eq(scene.steps[0].kind, S.CARD, "%s: it opens on where and when" % origin.id)
		assert_false(vignettes.has(scene.id), "%s: and it is its OWN, not another's"
			% origin.id)
		vignettes[scene.id] = true
	assert_eq(vignettes.size(), 5, "five Origins, five vignettes")
	var road := story.beat(&"beat_road")
	assert_true(road.plays_origin_vignette, "the first beat opens on the run's own vignette")
	var named := 0
	for beat in story.all_beats():
		if beat.entry_scene_id != &"":
			named += 1
			assert_true(scenes.has(beat.entry_scene_id),
				"%s is entered with a scene that exists" % beat.id)
	assert_true(named >= 1, "the scan saw a named scene")


func test_every_scene_line_exists_in_both_languages() -> void:
	var translated := _translated()
	var keys := (load(SCENES_PATH) as StorySceneCatalogData).text_keys()
	assert_true(keys.size() >= 25, "the scan saw the text (%d keys)" % keys.size())
	for key in keys:
		assert_true(translated.get(String(key), false),
			"'%s' has an English and a Vietnamese line" % key)


# === The looks ==============================================================

func test_every_look_offered_can_actually_be_drawn() -> void:
	var looks := load(APPEARANCES_PATH) as PlayerAppearanceCatalogData
	assert_eq(looks.validation_errors(), [] as Array[String], "the shipped looks validate")
	assert_true(looks.entries.size() >= 2, "there is a choice to make")
	var genders := {}
	var translated := _translated()
	for look in looks.entries:
		genders[look.gender()] = true
		assert_true(translated.get(String(look.name_key), false),
			"%s is named in both languages" % look.id)
		var profile := load(look.template.sprite_set_ref) as CharacterVisualProfileData
		assert_true(profile != null and profile.is_valid(), "%s: its body is a valid profile"
			% look.id)
		for sheet: String in ["idle_sheet", "walk_sheet", "attack_sheet", "meditate_sheet",
				"cast_sheet", "slash_sheet"]:
			assert_not_null(profile.get(sheet),
				"%s: can %s — a look that cannot do what the player does is not a look"
				% [look.id, sheet.trim_suffix("_sheet")])
		assert_not_null(load(look.template.portrait_ref) as Texture2D,
			"%s: has its own portrait" % look.id)
		assert_eq(look.template.default_sect_id, &"", "%s: begins with no sect" % look.id)
	assert_true(genders.has(CharacterTemplateData.Gender.MALE)
		and genders.has(CharacterTemplateData.Gender.FEMALE), "both genders are offered")


func test_two_looks_that_draw_one_body_are_not_two_looks() -> void:
	var shipped := load(APPEARANCES_PATH) as PlayerAppearanceCatalogData
	var twin: PlayerAppearanceData = AppearanceScript.new()
	twin.id = &"appearance_twin"
	twin.name_key = &"APPEARANCE_WANDERER_M_NAME"
	twin.template = shipped.entries[0].template
	var looks: Array[PlayerAppearanceData] = [shipped.entries[0], twin]
	var catalog: PlayerAppearanceCatalogData = AppearanceCatalogScript.new()
	catalog.entries = looks
	assert_true(_has(catalog.validation_errors(), "draw the same body"),
		"a selector whose options render alike is refused")
	var enrolled: PlayerAppearanceData = AppearanceScript.new()
	enrolled.id = &"appearance_enrolled"
	enrolled.name_key = &"APPEARANCE_WANDERER_M_NAME"
	enrolled.template = shipped.entries[0].template.duplicate() as CharacterTemplateData
	enrolled.template.default_sect_id = &"sect_azure_cloud"
	assert_true(_has(enrolled.validation_errors(), "no sect"),
		"a look that would start the player in a sect is refused (C-003)")


## A garment is drawn per BODY. Every look gets its own drawn robe; a body it was never drawn
## for keeps its own look instead of being redrawn as someone else.
func test_every_look_has_its_own_drawing_of_every_garment() -> void:
	var looks := load(APPEARANCES_PATH) as PlayerAppearanceCatalogData
	var items := load(ITEMS_PATH) as ItemCatalogData
	var garments := 0
	for item in items.entries:
		var equipment := item.equipment as EquipmentData
		if equipment == null or equipment.body_visuals_by_base.is_empty():
			continue
		garments += 1
		var drawn := {}
		for look in looks.entries:
			var base := load(look.template.sprite_set_ref) as CharacterVisualProfileData
			var worn := equipment.body_visual_for(base.id)
			assert_not_null(worn, "%s is drawn on %s" % [equipment.id, look.id])
			if worn == null:
				continue
			assert_ne(worn.id, base.id, "%s changes how %s looks" % [equipment.id, look.id])
			assert_false(drawn.has(worn.id), "%s: each look wears its OWN drawing"
				% equipment.id)
			drawn[worn.id] = true
			assert_not_null(worn.slash_sheet, "%s on %s can still swing a sword"
				% [equipment.id, look.id])
		assert_null(equipment.body_visual_for(&"vis_somebody_else"),
			"%s: a body it was never drawn for keeps its own look" % equipment.id)
	assert_true(garments >= 1, "the scan saw a garment")
