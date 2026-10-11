extends TestCase
## Unit tests for `StoryService` (Phase 20, D-072): the one writer of the story record and of
## story flags. Pure domain — a fixture catalog, a real `CharacterState`, and fake owners that
## record what they were asked.

const K := StoryTriggerData.Kind

const PLAYER_TEMPLATE := "res://data/characters/player_default.tres"


class Rig extends RefCounted:
	var service: StoryService
	var state: StoryState
	var player: CharacterState
	var owners: StoryFixture.Owners


func _rig(begin_as: StringName = &"origin_lang_y") -> Rig:
	var rig := Rig.new()
	rig.state = StoryState.new()
	rig.player = CharacterState.create_from_template(
		load(PLAYER_TEMPLATE) as CharacterTemplateData, &"player_test")
	rig.owners = StoryFixture.Owners.new()
	rig.service = StoryService.new(StoryFixture.catalog(), StoryFixture.origins(), rig.state,
		rig.player, rig.owners.seams)
	if begin_as != &"":
		assert_true(rig.service.begin(begin_as).ok, "the fixture run begins")
	return rig


## Everything a refusal must leave untouched, as one comparable value.
func _snapshot(rig: Rig) -> String:
	return str([rig.state.to_dict(), rig.player.story_flags, rig.owners.taught,
		rig.owners.regards, rig.owners.given])


# === Readiness ==============================================================

func test_an_invalid_catalog_leaves_the_service_unready() -> void:
	var broken := StoryFixture.catalog()
	broken.start_beat_id = &"nowhere"
	var player := CharacterState.create_from_template(
		load(PLAYER_TEMPLATE) as CharacterTemplateData, &"player_test")
	var service := StoryService.new(broken, StoryFixture.origins(), StoryState.new(), player,
		StoryOwners.new())
	assert_false(service.is_ready(), "an invalid catalog is refused")
	assert_eq(service.begin(&"origin_lang_y").reason, StoryService.REFUSE_NOT_READY,
		"and nothing can begin on it")
	assert_eq(service.flag_value(&"f_heard"), 0, "nor be read")


# === Beginning a run ========================================================

func test_beginning_sets_the_origin_and_enters_the_first_beat() -> void:
	var rig := _rig(&"")
	assert_false(rig.service.has_begun(), "nothing has begun")
	assert_eq(rig.service.objective_key(), &"", "so there is no objective yet")
	var outcome := rig.service.begin(&"origin_thu_thu")
	assert_true(outcome.ok, "the run begins")
	assert_true(rig.service.origin_is(&"origin_thu_thu"), "as the chosen Origin")
	assert_eq(rig.state.chapter_id, &"chapter_one", "in the first chapter")
	assert_eq(outcome.beat_id, &"a", "on the first beat")
	assert_eq(rig.service.objective_key(), &"OBJ_a", "whose objective is the purpose")
	assert_eq(rig.owners.given.size() + rig.owners.taught.size() + rig.owners.regards.size(), 0,
		"an Origin with no grants gives nothing")


func test_an_origins_kit_is_handed_over_once_through_its_owners() -> void:
	var rig := _rig(&"origin_ho_tieu")
	assert_eq(rig.owners.given, [[&"item_blade", 1]], "the item, through the bag")
	assert_eq(rig.owners.taught, [[&"know_drill", &"story:origin_ho_tieu"]],
		"the knowledge, through the Knowledge Core, with its source named")
	assert_eq(rig.owners.regards, [[&"actor_a", &"affinity", -10]],
		"the first impression, through the relationship graph")

	var before := _snapshot(rig)
	var again := rig.service.begin(&"origin_ho_tieu")
	assert_eq(again.reason, StoryService.REFUSE_ALREADY_BEGUN, "a run begins once")
	assert_eq(rig.service.begin(&"origin_lang_y").reason, StoryService.REFUSE_ALREADY_BEGUN,
		"and cannot be begun again as someone else")
	assert_eq(_snapshot(rig), before, "a second begin gives nothing twice")


func test_a_refused_begin_gives_nothing_and_begins_nothing() -> void:
	var rig := _rig(&"")
	assert_eq(rig.service.begin(&"origin_chosen_one").reason,
		StoryService.REFUSE_UNKNOWN_ORIGIN, "an unknown Origin")
	var cyrillic := StringName("origin_h" + char(0x043E) + "_tieu")
	assert_eq(rig.service.begin(cyrillic).reason, StoryService.REFUSE_UNKNOWN_ORIGIN,
		"the confusable id is not the real one")

	rig.owners.bag_has_room = false
	var before := _snapshot(rig)
	assert_eq(rig.service.begin(&"origin_ho_tieu").reason, StoryService.REFUSE_NO_ROOM,
		"a kit that does not fit")
	assert_eq(_snapshot(rig), before,
		"gave NOTHING — not the knowledge, not the regard — and began nothing")
	assert_false(rig.service.has_begun(), "the story has not begun")

	rig = _rig(&"")
	rig.owners.seams.teach = Callable()
	before = _snapshot(rig)
	assert_eq(rig.service.begin(&"origin_ho_tieu").reason, StoryService.REFUSE_OWNER,
		"an owner the kit needs is missing")
	assert_eq(_snapshot(rig), before, "and again nothing was handed over")


# === Flags: one store, one writer ===========================================

func test_flags_live_on_the_players_record_and_nowhere_else() -> void:
	var rig := _rig()
	assert_eq(rig.service.flag_value(&"f_count"), 0, "unset reads 0")
	assert_true(rig.service.set_flag(&"f_count", 2).ok, "set")
	assert_eq(rig.service.flag_value(&"f_count"), 2, "and read back")
	assert_eq(rig.player.story_flags.get("f_count"), 2, "from the player's CharacterState")
	assert_true(typeof(rig.player.story_flags["f_count"]) == TYPE_INT, "an INT is stored as int")
	assert_false(rig.state.to_dict().has("flags"),
		"the story record does NOT repeat flags (D-072 §1)")
	assert_false(str(rig.state.to_dict()).contains("f_count"), "nor mention one anywhere")
	assert_true(rig.player.to_dict()["story_flags"].has("f_count"),
		"the character's snapshot is where a flag is saved")


func test_an_undeclared_flag_or_a_value_it_cannot_hold_is_refused() -> void:
	var rig := _rig()
	var before := _snapshot(rig)
	assert_eq(rig.service.set_flag(&"f_undeclared", 1).reason,
		StoryService.REFUSE_UNKNOWN_FLAG, "an undeclared flag")
	assert_eq(rig.service.set_flag(&"f_heard", 2).reason, StoryService.REFUSE_FLAG_VALUE,
		"a BOOL holds 0 or 1")
	assert_eq(rig.service.set_flag(&"f_count", 4).reason, StoryService.REFUSE_FLAG_VALUE,
		"an INT holds up to its max")
	assert_eq(rig.service.set_flag(&"f_count", -1).reason, StoryService.REFUSE_FLAG_VALUE,
		"and never a negative")
	assert_eq(_snapshot(rig), before, "every refusal changed nothing")
	assert_eq(rig.service.flag_value(&"f_undeclared"), 0, "an undeclared flag reads 0")

	var unbegun := _rig(&"")
	assert_eq(unbegun.service.set_flag(&"f_heard", 1).reason, StoryService.REFUSE_NOT_BEGUN,
		"no flag is set before a run begins")


func test_a_bool_flag_is_stored_as_a_bool() -> void:
	var rig := _rig()
	assert_true(rig.service.set_flag(&"f_heard", 1).ok, "set")
	assert_true(typeof(rig.player.story_flags["f_heard"]) == TYPE_BOOL, "stored as bool")
	assert_eq(rig.service.flag_value(&"f_heard"), 1, "read as 1")
	assert_true(rig.service.flag_at_least(&"f_heard", 1), "which satisfies 'at least 1'")


# === Moving through beats ===================================================

func test_a_state_trigger_completes_the_beat_the_moment_it_holds() -> void:
	var rig := _rig()
	var outcome := rig.service.set_flag(&"f_heard", 1)
	assert_eq(outcome.completed, [&"a"] as Array[StringName], "the flag completed beat a")
	assert_eq(outcome.beat_id, &"b", "and the story is on b")
	assert_true(outcome.moved(), "the outcome says it moved")
	assert_true(rig.state.has_completed(&"a"), "the record keeps it")


func test_an_event_only_counts_while_its_beat_is_current() -> void:
	var rig := _rig()
	var early := rig.service.note(K.CULTIVATED)
	assert_true(early.ok, "an early event is noted")
	assert_false(early.moved(), "but beat a is not waiting for it")
	assert_eq(rig.state.beat_id, &"a", "nothing moved")

	rig.service.set_flag(&"f_heard", 1)
	rig.service.choose(&"c_side", &"left")
	assert_eq(rig.state.beat_id, &"c", "now beat c waits for a cultivation session")
	assert_false(rig.service.note(K.ARRIVED, &"map_far").moved(), "a different event: no")
	assert_true(rig.service.note(K.CULTIVATED).moved(), "the right one: yes")
	assert_eq(rig.service.note(K.FLAG, &"f_heard").reason, StoryService.REFUSE_NOT_AN_EVENT,
		"a state kind cannot be 'noted'")


func test_an_event_with_a_subject_needs_that_subject() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	rig.service.choose(&"c_side", &"left")
	rig.service.note(K.CULTIVATED)
	rig.owners.known[&"know_x"] = true
	rig.service.refresh()
	assert_eq(rig.state.beat_id, &"e", "beat e waits for an arrival in map_far")
	assert_false(rig.service.note(K.ARRIVED, &"map_near").moved(), "another map is not it")
	var arrived := rig.service.note(K.ARRIVED, &"map_far")
	assert_eq(arrived.completed, [&"e"] as Array[StringName], "the right map completes it")
	assert_true(arrived.chapter_changed, "and carries the story into the next chapter")
	assert_eq(rig.state.chapter_id, &"chapter_two", "which is now current")
	assert_eq(rig.state.completed_chapters, [&"chapter_one"] as Array[StringName],
		"the first chapter is recorded as completed")
	assert_true(rig.service.current_beat().terminal, "and the story rests")
	assert_false(rig.service.note(K.CULTIVATED).moved(), "nothing completes a resting beat")


## What the player ALREADY did counts when a beat is entered: it is not asked for again.
func test_a_beat_whose_state_already_holds_is_passed_through() -> void:
	var rig := _rig()
	rig.owners.known[&"know_x"] = true
	rig.service.set_flag(&"f_heard", 1)
	rig.service.choose(&"c_side", &"right")
	var outcome := rig.service.note(K.CULTIVATED)
	assert_eq(outcome.completed, [&"c", &"d_right"] as Array[StringName],
		"the session completed c, and d_right's knowledge was already held")
	assert_eq(outcome.beat_id, &"e", "so the story is already on e")


## Several beats in a row can already hold. All of them are passed in the ONE call that made
## the first one true — the story never rests on a beat that is already answered.
func test_every_beat_that_already_holds_is_passed_in_one_call() -> void:
	var catalog := StoryFixture.catalog()
	catalog.chapters[0].beats[1].trigger = StoryFixture.trigger(K.FLAG, &"f_count")
	catalog.chapters[0].beats[2].trigger = StoryFixture.trigger(K.KNOWS, &"know_x")
	catalog.choices[0].beat_id = &""
	var rig := _rig(&"")
	rig.service = StoryService.new(catalog, StoryFixture.origins(), rig.state, rig.player,
		rig.owners.seams)
	rig.service.begin(&"origin_lang_y")
	rig.owners.known[&"know_x"] = true
	assert_false(rig.service.set_flag(&"f_count", 1).moved(), "beat a waits for another flag")
	var outcome := rig.service.set_flag(&"f_heard", 1)
	assert_eq(outcome.completed, [&"a", &"b", &"c", &"d_right"] as Array[StringName],
		"a, then b, c and d_right, which all already held")
	assert_eq(outcome.beat_id, &"e", "resting on the first beat that is really still open")


func test_refresh_asks_the_current_beat_again_after_another_owner_changed() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	rig.service.choose(&"c_side", &"left")
	rig.service.note(K.CULTIVATED)
	assert_eq(rig.state.beat_id, &"d_left", "waiting for something to be known")
	assert_false(rig.service.refresh().moved(), "not known yet")
	rig.owners.known[&"know_x"] = true
	assert_true(rig.service.refresh().moved(), "the Knowledge Core changed; the beat completes")


func test_meeting_is_recorded_once_and_can_complete_a_beat() -> void:
	var people: Array[StringName] = [&"actor_a", &"actor_b", &"actor_c"]
	var catalog := StoryFixture.catalog()
	catalog.chapters[0].beats[0].trigger = StoryFixture.trigger(K.MET, &"", 2, people)
	var rig := _rig(&"")
	rig.service = StoryService.new(catalog, StoryFixture.origins(), rig.state, rig.player,
		rig.owners.seams)
	rig.service.begin(&"origin_lang_y")
	assert_false(rig.service.meet(&"actor_a").moved(), "one of two")
	assert_false(rig.service.meet(&"actor_a").moved(), "the same person again is still one")
	assert_eq(rig.state.met, [&"actor_a"] as Array[StringName], "recorded once")
	assert_false(rig.service.meet(&"actor_z").moved(), "someone who does not count")
	assert_true(rig.service.meet(&"actor_c").moved(), "the second of the listed people")
	assert_eq(rig.service.meet(&"").reason, StoryService.REFUSE_NOBODY, "nobody is not met")


# === Choices ================================================================

func test_a_choice_is_recorded_once_and_its_consequences_go_to_their_owners() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	var outcome := rig.service.choose(&"c_side", &"right")
	assert_true(outcome.ok, "answered")
	assert_eq([outcome.choice_id, outcome.option_id], [&"c_side", &"right"], "as asked")
	assert_eq(rig.state.option_of(&"c_side"), &"right", "the record holds the answer")
	assert_eq(rig.state.choices.size(), 1, "exactly one record")
	assert_eq(rig.owners.regards, [[&"actor_b", &"trust", 10], [&"actor_a", &"affinity", -15]],
		"both regards moved, through the relationship owner")
	assert_eq(rig.service.flag_value(&"f_count"), 2, "the flag was set, by the story itself")
	assert_eq(rig.owners.taught, [[&"know_side", &"story:c_side"]],
		"and the knowledge taught, through the Knowledge Core")
	assert_eq(outcome.completed, [&"b"] as Array[StringName], "which completed the beat")


## A repeated key, a signal delivered twice, a stale panel: all are a second `choose`.
func test_a_second_answer_is_refused_and_changes_nothing() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	rig.service.choose(&"c_side", &"left")
	var before := _snapshot(rig)
	assert_eq(rig.service.choose(&"c_side", &"left").reason,
		StoryService.REFUSE_ALREADY_CHOSEN, "the same answer again")
	assert_eq(rig.service.choose(&"c_side", &"right").reason,
		StoryService.REFUSE_ALREADY_CHOSEN, "or the other one")
	assert_eq(_snapshot(rig), before, "nothing moved, no regard was paid twice")
	assert_eq(rig.state.choices.size(), 1, "still one record")


func test_a_choice_outside_its_beat_or_unknown_is_refused_whole() -> void:
	var rig := _rig()
	var before := _snapshot(rig)
	assert_eq(rig.service.choose(&"c_side", &"left").reason, StoryService.REFUSE_WRONG_BEAT,
		"the choice belongs to beat b, and the story is on a")
	assert_eq(rig.service.choose(&"c_unknown", &"left").reason,
		StoryService.REFUSE_UNKNOWN_CHOICE, "an unknown choice")
	assert_eq(rig.service.choose(&"c_side", &"sideways").reason,
		StoryService.REFUSE_UNKNOWN_CHOICE, "an answer it does not offer")
	assert_eq(_snapshot(rig), before, "every refusal changed nothing")


## Checked BEFORE the choice is recorded: an answer whose consequence has no owner to carry
## it out must not leave a recorded decision with half its effects.
func test_a_choice_whose_owner_is_missing_is_refused_before_anything_is_written() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	rig.owners.seams.teach = Callable()
	var before := _snapshot(rig)
	assert_eq(rig.service.choose(&"c_side", &"right").reason, StoryService.REFUSE_OWNER,
		"'right' teaches something and nothing can teach")
	assert_eq(_snapshot(rig), before,
		"not recorded, no regard moved, no flag set — the first consequences did not run")
	assert_false(rig.state.has_chosen(&"c_side"), "the choice is still open")
	assert_true(rig.service.choose(&"c_side", &"left").ok, "and can still be answered")


# --- All or nothing under an owner's refusal (D-073 §2) -----------------------
#
# The fixture's `right` answer moves actor_b's trust, then actor_a's affinity, sets a flag and
# teaches something: four consequences, three owners. Each test refuses ONE of the later ones
# and requires that none of the earlier ones stands.

func test_a_later_owner_declining_refuses_the_whole_choice_before_anything_is_done() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	rig.owners.decline_regard_for = [&"actor_a"]  # the SECOND regard; the first would succeed
	var before := _snapshot(rig)
	var outcome := rig.service.choose(&"c_side", &"right")
	assert_false(outcome.ok, "refused")
	assert_eq(outcome.reason, StoryService.REFUSE_OWNER, "because an owner said it could not")
	assert_eq(_snapshot(rig), before, "no record, no flag, no regard, nothing taught")
	assert_false(rig.state.has_chosen(&"c_side"), "the decision is still open")
	assert_eq(rig.service.flag_value(&"f_count"), 0, "the flag the answer sets is unset")
	assert_eq([rig.owners.regard_calls, rig.owners.teach_calls], [0, 0],
		"nobody was asked to DO anything: every owner was asked whether it could, first")
	assert_eq(rig.state.beat_id, &"b", "and the beat that waits on the decision still waits")


func test_knowledge_that_cannot_be_taught_refuses_the_whole_choice() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	rig.owners.decline_teach = [&"know_side"]  # the LAST consequence; three would succeed
	var before := _snapshot(rig)
	assert_eq(rig.service.choose(&"c_side", &"right").reason, StoryService.REFUSE_OWNER,
		"refused whole")
	assert_eq(_snapshot(rig), before, "both regards and the flag did not happen")
	assert_eq(rig.owners.regard_calls, 0, "the regards were not even attempted")


func test_a_refused_choice_can_be_answered_once_the_cause_is_gone_and_only_once() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	rig.owners.decline_regard_for = [&"actor_a"]
	assert_false(rig.service.choose(&"c_side", &"right").ok, "refused while the owner cannot")
	rig.owners.decline_regard_for = []
	var outcome := rig.service.choose(&"c_side", &"right")
	assert_true(outcome.ok, "the same answer succeeds once the owner can")
	assert_eq(rig.owners.regards, [[&"actor_b", &"trust", 10], [&"actor_a", &"affinity", -15]],
		"each regard moved exactly once: the refused attempt left nothing to double")
	assert_eq(rig.owners.taught, [[&"know_side", &"story:c_side"]], "taught once")
	assert_eq(rig.state.choices.size(), 1, "recorded once")
	assert_eq(rig.service.choose(&"c_side", &"right").reason,
		StoryService.REFUSE_ALREADY_CHOSEN, "and a second answer is refused as before")
	assert_eq(rig.owners.regards.size(), 2, "with nothing paid twice")


## The contract is that an owner which agreed will not then refuse. If one does anyway the
## story must still not be left holding half a decision.
func test_an_owner_that_breaks_its_word_at_the_commit_leaves_nothing_behind() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	rig.owners.breach_regard_for = [&"actor_a"]  # agreed when asked; fails when told
	var before := _snapshot(rig)
	var outcome := rig.service.choose(&"c_side", &"right")
	assert_false(outcome.ok, "refused")
	assert_eq(outcome.reason, StoryService.REFUSE_OWNER, "as an owner's refusal")
	assert_false(rig.state.has_chosen(&"c_side"), "the choice is NOT recorded")
	assert_eq(rig.service.flag_value(&"f_count"), 0, "the story wrote none of its own flags")
	assert_eq(rig.owners.regards, [], "the regard that had already moved was moved back")
	assert_eq(rig.owners.taught, [], "and nothing was taught: knowledge is committed last")
	assert_eq(_snapshot(rig), before, "so the run is exactly as it was")
	rig.owners.breach_regard_for = []
	assert_true(rig.service.choose(&"c_side", &"right").ok, "and the decision can still be made")
	assert_eq(rig.owners.regards.size(), 2, "once")


func test_an_origin_whose_grant_an_owner_declines_begins_nothing_and_gives_nothing() -> void:
	var rig := _rig(&"")
	rig.owners.decline_regard_for = [&"actor_a"]  # the kit's LAST grant; the bag would accept
	var before := _snapshot(rig)
	assert_eq(rig.service.begin(&"origin_ho_tieu").reason, StoryService.REFUSE_OWNER,
		"an Origin's start is refused before its items are handed over")
	assert_eq(_snapshot(rig), before, "nothing given, nothing taught, not begun")
	assert_eq(rig.owners.given, [], "the bag was not asked")


## THE EXIT CRITERION: a prior decision shapes a later branch through a stored fact, and the
## branches converge.
func test_a_prior_choice_decides_a_later_branch_and_the_branches_converge() -> void:
	var seen := {}
	for answer: StringName in [&"left", &"right"]:
		var rig := _rig()
		rig.service.set_flag(&"f_heard", 1)
		rig.service.choose(&"c_side", answer)
		rig.service.note(K.CULTIVATED)
		seen[answer] = rig.state.beat_id
		rig.owners.known[&"know_x"] = true
		rig.service.refresh()
		assert_eq(rig.state.beat_id, &"e", "'%s' converges on e" % answer)
	assert_eq(seen[&"left"], &"d_left", "having answered left leads through d_left")
	assert_eq(seen[&"right"], &"d_right", "anything else through d_right")


# === Conditions =============================================================

func test_conditions_read_the_record_the_origin_and_the_knowledge_owner() -> void:
	var rig := _rig(&"origin_thu_thu")
	var c := StoryConditionData.Kind
	assert_true(rig.service.condition_holds(
		StoryFixture.condition(c.ORIGIN, &"origin_thu_thu")), "the run's Origin")
	assert_false(rig.service.condition_holds(
		StoryFixture.condition(c.ORIGIN, &"origin_lang_y")), "not another")
	assert_true(rig.service.condition_holds(
		StoryFixture.condition(c.ORIGIN, &"origin_lang_y", &"", 1, true)), "negated")
	assert_false(rig.service.condition_holds(StoryFixture.condition(c.KNOWS, &"know_x")),
		"not known")
	rig.owners.known[&"know_x"] = true
	assert_true(rig.service.condition_holds(StoryFixture.condition(c.KNOWS, &"know_x")),
		"known — asked of the Knowledge Core each time, never mirrored")
	rig.service.set_flag(&"f_count", 2)
	assert_true(rig.service.condition_holds(StoryFixture.condition(c.FLAG, &"f_count", &"", 2)),
		"a flag at least 2")
	assert_false(rig.service.condition_holds(
		StoryFixture.condition(c.FLAG, &"f_count", &"", 3)), "but not at least 3")
	assert_false(rig.service.condition_holds(null), "no condition holds nothing")


# === The persistence boundary ===============================================

func test_a_mid_story_record_round_trips_exactly() -> void:
	var rig := _rig(&"origin_ho_tieu")
	rig.service.meet(&"actor_a")
	rig.service.set_flag(&"f_heard", 1)
	rig.service.choose(&"c_side", &"right")
	var story := rig.service.to_dict()
	var character := rig.player.to_dict()
	assert_eq(story["origin_id"], "origin_ho_tieu", "the Origin")
	assert_eq(story["beat_id"], "c", "the current beat")
	assert_eq(story["completed_beats"], ["a", "b"], "what was completed, in order")
	assert_eq(story["choices"], [{"choice_id": "c_side", "option_id": "right"}], "the choice")
	assert_eq(story["met"], ["actor_a"], "who was met")

	var restored := _rig(&"")
	assert_true(restored.player.from_dict(character), "the character is restored first")
	var given_before := restored.owners.given.size() + restored.owners.taught.size() \
		+ restored.owners.regards.size()
	assert_true(restored.service.load_state(story), "then the story")
	assert_eq(str(restored.service.to_dict()), str(story), "byte-stable")
	assert_eq(restored.service.flag_value(&"f_count"), 2, "the flag came with the character")
	assert_eq(restored.owners.given.size() + restored.owners.taught.size()
		+ restored.owners.regards.size(), given_before,
		"restoring grants NOTHING again: no kit, no regard, no knowledge")
	assert_eq(restored.service.choose(&"c_side", &"left").reason,
		StoryService.REFUSE_ALREADY_CHOSEN, "and a recorded choice stays answered")
	assert_true(restored.service.note(K.CULTIVATED).moved(), "the restored story plays on")


func test_a_bad_record_is_rejected_whole_and_the_old_one_is_kept() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	var good := rig.service.to_dict()
	var kept := str(good)
	var cases := {
		"an unknown schema": func(d: Dictionary) -> void: d["schema"] = 2,
		"an unexpected key": func(d: Dictionary) -> void: d["flags"] = {"f_heard": true},
		"an unknown origin": func(d: Dictionary) -> void: d["origin_id"] = "origin_chosen_one",
		"an unknown chapter": func(d: Dictionary) -> void: d["chapter_id"] = "chapter_nine",
		"a beat from another chapter": func(d: Dictionary) -> void: d["beat_id"] = "rest",
		"a wrong type": func(d: Dictionary) -> void: d["beat_id"] = 7,
		"a completed beat that is unknown": func(d: Dictionary) -> void:
			d["completed_beats"] = ["nowhere"],
		"the current beat listed as completed": func(d: Dictionary) -> void:
			d["completed_beats"] = ["a", "b"],
		"a repeated completed beat": func(d: Dictionary) -> void:
			d["completed_beats"] = ["a", "a"],
		"an unknown choice": func(d: Dictionary) -> void:
			d["choices"] = [{"choice_id": "c_unknown", "option_id": "left"}],
		"an unknown option": func(d: Dictionary) -> void:
			d["choices"] = [{"choice_id": "c_side", "option_id": "sideways"}],
		"a choice answered twice": func(d: Dictionary) -> void:
			d["choices"] = [{"choice_id": "c_side", "option_id": "left"},
				{"choice_id": "c_side", "option_id": "right"}],
		"a choice record with an extra field": func(d: Dictionary) -> void:
			d["choices"] = [{"choice_id": "c_side", "option_id": "left", "x": 1}],
		"met that is not a list": func(d: Dictionary) -> void: d["met"] = "actor_a",
		"met with an empty id": func(d: Dictionary) -> void: d["met"] = [""],
	}
	for label: String in cases:
		var bad: Dictionary = good.duplicate(true)
		(cases[label] as Callable).call(bad)
		assert_false(rig.service.load_state(bad), "%s is rejected" % label)
		assert_eq(str(rig.service.to_dict()), kept, "%s left the record as it was" % label)


## Flags arrive with the CHARACTER. A story record is only accepted beside a character whose
## flags the catalog can account for — that is how the two are shown to agree without either
## holding a copy of the other.
func test_a_record_is_refused_beside_flags_the_catalog_does_not_declare() -> void:
	var rig := _rig()
	rig.service.set_flag(&"f_heard", 1)
	var good := rig.service.to_dict()
	assert_eq(rig.service.flag_errors(), [] as Array[String], "the store is sound")
	for label: String in ["an undeclared flag", "a BOOL holding an int", "an INT out of range"]:
		var other := _rig()
		match label:
			"an undeclared flag":
				other.player.story_flags["f_from_nowhere"] = true
			"a BOOL holding an int":
				other.player.story_flags["f_heard"] = 1
			"an INT out of range":
				other.player.story_flags["f_count"] = 99
		var kept := str(other.service.to_dict())
		assert_false(other.service.flag_errors().is_empty(), "%s is reported" % label)
		assert_false(other.service.load_state(good), "%s refuses the story record" % label)
		assert_eq(str(other.service.to_dict()), kept, "%s: and nothing changed" % label)


# === Content the other owners must answer ===================================

func test_content_errors_ask_each_owner_for_what_it_must_supply() -> void:
	var rig := _rig()
	var yes := func(_id: Variant) -> bool: return true
	var no := func(_id: Variant) -> bool: return false
	var nobody := func(_id: StringName) -> CharacterState: return null
	var someone := func(_id: StringName) -> CharacterState: return rig.player
	assert_eq(rig.service.content_errors(yes, yes, someone, yes, yes, yes, yes),
		[] as Array[String], "owners that have everything: no errors")
	var errors := rig.service.content_errors(no)
	assert_true(errors.size() > 10 and errors[0].contains("no translation"), "missing text")
	errors = rig.service.content_errors(Callable(), no)
	assert_true(str(errors).contains("know_x") and str(errors).contains("know_side")
		and str(errors).contains("know_drill"),
		"missing knowledge: a trigger's, a consequence's and an Origin's, got %s" % str(errors))
	errors = rig.service.content_errors(Callable(), Callable(), nobody)
	assert_true(str(errors).contains("actor_a") and str(errors).contains("actor_b"),
		"people who are not registered")
	errors = rig.service.content_errors(Callable(), Callable(), Callable(), no)
	assert_true(str(errors).contains("not a relationship dimension"), "unknown dimensions")
	errors = rig.service.content_errors(Callable(), Callable(), Callable(), Callable(), no)
	assert_true(str(errors).contains("item_blade"), "an item the catalog does not have")
	errors = rig.service.content_errors(Callable(), Callable(), Callable(), Callable(),
		Callable(), no)
	assert_true(str(errors).contains("map_far"), "a map that does not exist")
