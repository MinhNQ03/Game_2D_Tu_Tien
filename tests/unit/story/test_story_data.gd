extends TestCase
## Unit tests for the story DATA (Phase 20, D-072): stable ids, the closed sets, and the
## catalog's whole-graph checks. Every negative case departs from the valid fixture in exactly
## one place (L-024), and typed locals are assigned to typed exports (L-026).

const K := StoryTriggerData.Kind
const C := StoryConditionData.Kind


func _has(errors: Array[String], fragment: String) -> bool:
	for error in errors:
		if error.contains(fragment):
			return true
	return false


# === Ids ====================================================================

func test_a_stable_id_is_lower_case_ascii_with_a_letter_first() -> void:
	for good: StringName in [&"origin_ho_tieu", &"beat_road", &"a", &"flag_2"]:
		assert_true(StoryIds.is_stable(good), "'%s' is stable" % good)
	for bad: StringName in [&"", &"Origin", &"2_beat", &"_x", &"beat road", &"beat-road",
			&"mạch"]:
		assert_false(StoryIds.is_stable(bad), "'%s' is not stable" % bad)


## THE DEFECT THIS RULE EXISTS FOR: the canon ledger spelt the id with a Cyrillic `о`.
func test_the_confusable_cyrillic_o_is_refused() -> void:
	var cyrillic := StringName("origin_h" + char(0x043E) + "_tieu")
	assert_eq(String(cyrillic).length(), "origin_ho_tieu".length(), "it LOOKS the same length")
	assert_ne(cyrillic, &"origin_ho_tieu", "and compares unequal")
	assert_false(StoryIds.is_stable(cyrillic), "so it is not a stable id")
	assert_true(StoryIds.problem("origin", cyrillic).contains("not lower-case ASCII"),
		"and the reason says why")


# === The closed sets ========================================================

func test_a_flag_declares_an_id_a_type_and_a_purpose() -> void:
	assert_eq(StoryFixture.flag(&"f").validation_errors(), [] as Array[String], "valid")
	var nameless := StoryFixture.flag(&"")
	assert_true(_has(nameless.validation_errors(), "no id"), "an id is required")
	var silent := StoryFixture.flag(&"f")
	silent.purpose = " "
	assert_true(_has(silent.validation_errors(), "no purpose"), "and a purpose")
	var empty_count := StoryFixture.flag(&"f", StoryFlagData.Kind.INT, 0)
	assert_true(_has(empty_count.validation_errors(), "could hold nothing"),
		"an INT flag must be able to hold something")
	assert_eq(StoryFixture.flag(&"f").ceiling(), 1, "a BOOL reads 0 or 1")
	assert_eq(StoryFixture.flag(&"f", StoryFlagData.Kind.INT, 4).ceiling(), 4, "an INT its max")


func test_a_condition_uses_only_its_own_payload() -> void:
	assert_eq(StoryFixture.condition(C.FLAG, &"f").validation_errors(), [] as Array[String])
	assert_eq(StoryFixture.condition(C.CHOICE, &"c", &"o").validation_errors(),
		[] as Array[String])
	assert_true(_has(StoryFixture.condition(C.CHOICE, &"c").validation_errors(), "no option"),
		"a CHOICE condition names an option")
	assert_true(_has(StoryFixture.condition(C.KNOWS, &"").validation_errors(),
		"names nothing"), "a condition names something")
	var mixed := StoryFixture.condition(C.ORIGIN, &"origin_lang_y")
	mixed.flag_id = &"f"
	assert_true(_has(mixed.validation_errors(), "payload of another kind"), "no stray payload")
	assert_true(_has(StoryFixture.condition(C.FLAG, &"f", &"", 0).validation_errors(),
		"always true"), "'at least 0' is not a condition")


func test_conditions_that_cannot_both_hold_are_detected() -> void:
	var a := StoryFixture.condition(C.ORIGIN, &"origin_lang_y")
	var b := StoryFixture.condition(C.ORIGIN, &"origin_thu_thu")
	assert_true(a.contradicts(b), "two different Origins")
	assert_false(a.contradicts(StoryFixture.condition(C.ORIGIN, &"origin_lang_y")), "same one")
	var left := StoryFixture.condition(C.CHOICE, &"c", &"left")
	assert_true(left.contradicts(StoryFixture.condition(C.CHOICE, &"c", &"right")),
		"two answers to one choice")
	assert_true(left.contradicts(StoryFixture.condition(C.CHOICE, &"c", &"left", 1, true)),
		"an answer and its negation")
	var at_least_two := StoryFixture.condition(C.FLAG, &"f", &"", 2)
	var below_two := StoryFixture.condition(C.FLAG, &"f", &"", 2, true)
	var below_three := StoryFixture.condition(C.FLAG, &"f", &"", 3, true)
	assert_true(at_least_two.contradicts(below_two), "at least 2 and below 2")
	assert_false(at_least_two.contradicts(below_three), "at least 2 and below 3 is exactly 2")
	var contradictory: Array[StoryConditionData] = [a, b]
	assert_true(_has(StoryFixture.branch(&"x", contradictory).validation_errors(),
		"can never both hold"), "and a branch requiring both is reported")


func test_a_consequence_uses_only_its_own_payload_and_is_bounded() -> void:
	assert_eq(StoryFixture.regard(&"a", &"trust", 10).validation_errors(), [] as Array[String])
	assert_true(_has(StoryFixture.regard(&"a", &"trust", 0).validation_errors(),
		"changes nothing"), "a zero move is not a consequence")
	assert_true(_has(StoryFixture.regard(&"a", &"trust", 51).validation_errors(),
		"exceeds the ceiling"), "one decision does not carry someone end to end")
	var stray := StoryFixture.set_flag(&"f")
	stray.delta = 3
	assert_true(_has(stray.validation_errors(), "does not use"), "no stray payload")
	var twice: Array[StoryConsequenceData] = [
		StoryFixture.regard(&"a", &"trust", 5), StoryFixture.regard(&"a", &"trust", -5)]
	assert_true(_has(StoryFixture.option(&"o", twice).validation_errors(), "two consequences"),
		"two consequences of one answer may not write the same value")


func test_a_trigger_is_an_event_or_a_state_and_names_what_it_waits_for() -> void:
	assert_true(StoryFixture.trigger(K.SCENE_ENDED).is_event(), "a scene ending is an event")
	assert_true(StoryFixture.trigger(K.ARRIVED, &"map_x").is_event(), "so is an arrival")
	assert_true(StoryFixture.trigger(K.CULTIVATED).is_event(), "and a cultivation session")
	for kind: int in [K.FLAG, K.MET, K.CHOICE, K.KNOWS]:
		assert_false(StoryFixture.trigger(kind, &"x").is_event(), "kind %d is a state" % kind)
	assert_true(_has(StoryFixture.trigger(K.ARRIVED).validation_errors(), "names nothing"),
		"an arrival names a map")
	var people: Array[StringName] = [&"a", &"b"]
	assert_eq(StoryFixture.trigger(K.MET, &"", 2, people).validation_errors(),
		[] as Array[String], "two of two people")
	assert_true(_has(StoryFixture.trigger(K.MET, &"", 3, people).validation_errors(),
		"3 of 2"), "more people than are listed can never be met")
	var twins: Array[StringName] = [&"a", &"a"]
	assert_true(_has(StoryFixture.trigger(K.MET, &"", 1, twins).validation_errors(), "twice"),
		"nobody is listed twice")


func test_a_beat_has_an_objective_a_trigger_and_a_way_on() -> void:
	var no_conditions: Array[StoryConditionData] = []
	var on: Array[StoryBranchData] = [StoryFixture.branch(&"next", no_conditions)]
	var good := StoryFixture.beat(&"b", StoryFixture.trigger(K.CULTIVATED), on)
	assert_eq(good.validation_errors(), [] as Array[String], "valid")
	var blank := StoryFixture.beat(&"b", StoryFixture.trigger(K.CULTIVATED), on)
	blank.objective_key = &""
	assert_true(_has(blank.validation_errors(), "purpose line would be blank"),
		"a beat with no objective would blank the purpose line (Q19-03)")
	var stuck := StoryFixture.beat(&"b", null, on)
	assert_true(_has(stuck.validation_errors(), "nothing could ever complete it"), "no trigger")
	var dead_end: Array[StoryBranchData] = []
	assert_true(_has(StoryFixture.beat(&"b", StoryFixture.trigger(K.CULTIVATED), dead_end)
		.validation_errors(), "no way on"), "no branch")
	var only_if: Array[StoryConditionData] = [StoryFixture.condition(C.FLAG, &"f")]
	var conditional: Array[StoryBranchData] = [StoryFixture.branch(&"next", only_if)]
	assert_true(_has(StoryFixture.beat(&"b", StoryFixture.trigger(K.CULTIVATED), conditional)
		.validation_errors(), "could lead nowhere"), "the last branch must be unconditional")
	var shadowed: Array[StoryBranchData] = [StoryFixture.branch(&"next", no_conditions),
		StoryFixture.branch(&"other", no_conditions)]
	assert_true(_has(StoryFixture.beat(&"b", StoryFixture.trigger(K.CULTIVATED), shadowed)
		.validation_errors(), "can never be taken"), "a branch after an unconditional one")
	var terminal := StoryFixture.rest(&"r")
	assert_eq(terminal.validation_errors(), [] as Array[String], "a terminal beat is valid")
	terminal.trigger = StoryFixture.trigger(K.CULTIVATED)
	assert_true(_has(terminal.validation_errors(), "is terminal but"), "and waits for nothing")


func test_a_choice_offers_at_least_two_distinct_answers() -> void:
	var one: Array[StoryOptionData] = [StoryFixture.option(&"only")]
	assert_true(_has(StoryFixture.choice(&"c", &"", one).validation_errors(),
		"at least two"), "one answer is not a choice")
	var twins: Array[StoryOptionData] = [StoryFixture.option(&"x"), StoryFixture.option(&"x")]
	assert_true(_has(StoryFixture.choice(&"c", &"", twins).validation_errors(),
		"duplicate option"), "answers are distinct")


# === The catalog ============================================================

func test_the_fixture_catalog_is_valid() -> void:
	var catalog := StoryFixture.catalog()
	assert_eq(catalog.validation_errors(), [] as Array[String], "the fixture validates")
	assert_eq(catalog.all_beats().size(), 7, "and carries its beats")
	assert_eq(catalog.chapter_of(&"rest").id, &"chapter_two", "a beat knows its chapter")


func test_duplicate_and_null_entries_are_reported() -> void:
	var catalog := StoryFixture.catalog()
	catalog.chapters[1].beats[0].id = &"a"
	assert_true(_has(catalog.validation_errors(), "duplicate beat id 'a'"), "duplicate beat")
	catalog = StoryFixture.catalog()
	catalog.flags.append(StoryFixture.flag(&"f_heard"))
	assert_true(_has(catalog.validation_errors(), "duplicate flag id"), "duplicate flag")
	catalog = StoryFixture.catalog()
	catalog.choices.append(catalog.choices[0])
	assert_true(_has(catalog.validation_errors(), "duplicate choice id"), "duplicate choice")
	catalog = StoryFixture.catalog()
	catalog.chapters.append(null)
	assert_true(_has(catalog.validation_errors(), "is null"), "a null chapter")
	catalog = StoryFixture.catalog()
	catalog.chapters[1].id = &"chapter_one"
	assert_true(_has(catalog.validation_errors(), "duplicate chapter id"), "duplicate chapter")


func test_dangling_references_are_reported() -> void:
	var catalog := StoryFixture.catalog()
	catalog.start_beat_id = &"nowhere"
	assert_true(_has(catalog.validation_errors(), "is not a beat"), "a start that is no beat")
	catalog = StoryFixture.catalog()
	catalog.chapters[0].beats[0].branches[0].next_beat_id = &"nowhere"
	assert_true(_has(catalog.validation_errors(), "which is not a beat"), "a dangling next")
	catalog = StoryFixture.catalog()
	catalog.chapters[0].beats[0].trigger.subject_id = &"f_undeclared"
	assert_true(_has(catalog.validation_errors(), "is not declared"), "an undeclared flag")
	catalog = StoryFixture.catalog()
	catalog.chapters[0].beats[1].trigger.subject_id = &"c_unknown"
	assert_true(_has(catalog.validation_errors(), "is not a choice"), "an unknown choice")
	catalog = StoryFixture.catalog()
	catalog.chapters[0].beats[2].branches[0].conditions[0].option_id = &"sideways"
	assert_true(_has(catalog.validation_errors(), "has no option 'sideways'"),
		"a branch on an answer the choice does not offer")
	catalog = StoryFixture.catalog()
	catalog.choices[0].beat_id = &"nowhere"
	assert_true(_has(catalog.validation_errors(), "may be answered during"), "a choice's beat")
	catalog = StoryFixture.catalog()
	catalog.choices[0].options[1].consequences[2].value = 9
	assert_true(_has(catalog.validation_errors(), "it holds at most 3"),
		"a flag asked to hold more than it can")


func test_an_unreachable_beat_a_dead_end_and_a_loop_are_reported() -> void:
	var no_conditions: Array[StoryConditionData] = []
	var catalog := StoryFixture.catalog()
	var orphan_on: Array[StoryBranchData] = [StoryFixture.branch(&"rest", no_conditions)]
	catalog.chapters[0].beats.append(StoryFixture.beat(&"orphan",
		StoryFixture.trigger(K.CULTIVATED), orphan_on))
	assert_true(_has(catalog.validation_errors(), "'orphan' cannot be reached"),
		"content no run can ever see")

	catalog = StoryFixture.catalog()
	catalog.chapters[1].beats[0].terminal = false
	assert_true(_has(catalog.validation_errors(), "nothing could ever complete it")
		or _has(catalog.validation_errors(), "nowhere to rest"),
		"a story with nowhere to rest")

	# A loop that leaves every beat reachable and able to rest: e may go back to a, or on.
	catalog = StoryFixture.catalog()
	var if_heard: Array[StoryConditionData] = [StoryFixture.condition(C.FLAG, &"f_count")]
	catalog.chapters[0].beats[5].branches.insert(0, StoryFixture.branch(&"a", if_heard))
	var errors := catalog.validation_errors()
	assert_true(_has(errors, "can lead back to itself"),
		"a loop: a beat is entered once, got %s" % str(errors))


func test_a_beat_may_not_reveal_more_than_its_chapter_allows() -> void:
	var catalog := StoryFixture.catalog()
	catalog.chapters[0].beats[3].reveal_layer = 4
	assert_true(_has(catalog.validation_errors(), "touches reveal layer 4"),
		"the prologue cannot say what Act IV earns (D-072 §5)")


# === Origins ================================================================

func test_the_origin_catalog_is_exactly_the_five_frozen_ids() -> void:
	var origins := StoryFixture.origins()
	assert_eq(origins.validation_errors(), [] as Array[String], "the fixture validates")
	assert_eq(origins.ids(), OriginCatalogData.FROZEN_IDS, "in canon order")
	origins.entries.remove_at(4)
	assert_true(_has(origins.validation_errors(), "'origin_thu_thu' is missing"), "one missing")
	origins = StoryFixture.origins()
	origins.entries.append(StoryFixture.origin(&"origin_chosen_one"))
	assert_true(_has(origins.validation_errors(), "not one of the five frozen"), "a sixth")
	origins = StoryFixture.origins()
	origins.entries[0].id = StringName("origin_h" + char(0x043E) + "_tieu")
	var errors := origins.validation_errors()
	assert_true(_has(errors, "not lower-case ASCII"), "the confusable id is refused")
	assert_true(_has(errors, "'origin_ho_tieu' is missing"), "and does not count as the real one")


func test_an_origin_grant_is_small_reasoned_and_single_purpose() -> void:
	assert_eq(StoryFixture.grant_item(&"item_x", 2).validation_errors(), [] as Array[String])
	assert_true(_has(StoryFixture.grant_item(&"item_x", 4).validation_errors(), "outside 1..3"),
		"an Origin hands over a little kit, not a stack")
	assert_true(_has(StoryFixture.grant_regard(&"a", &"trust", 25).validation_errors(),
		"outside 1..20"), "a first impression, not a history")
	var silent := StoryFixture.grant_knowledge(&"know_x")
	silent.reason = ""
	assert_true(_has(silent.validation_errors(), "no reason"), "every grant says why")
	var twice: Array[OriginGrantData] = [StoryFixture.grant_item(&"item_x", 1),
		StoryFixture.grant_item(&"item_x", 2)]
	assert_true(_has(StoryFixture.origin(&"origin_lang_y", twice).validation_errors(),
		"two grants write"), "one grant per thing")
