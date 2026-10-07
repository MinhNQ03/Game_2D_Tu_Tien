extends TestCase
## The HUD's bottom band (D-063 A1): one slot, three kinds of notice and the breakthrough banner.
##
## THE BUG IT GUARDS. The band was one FIFO line holding every notice for 3s. A refusal to the
## player's C key waited 2.6s behind a pickup notice, a stele's lesson waited 5.8s behind two
## (measured in the real app), and a full queue of 4 silently dropped the fifth notice. The old
## test pinned exactly that wait ("the first notice stays up for its full time") for EVERY
## notice — which is still right for PASSIVE notices, and wrong for the answer to a key press.
##
## "Visible on the frame it happens" is asserted as: the label shows the new text right after
## the call, with no frame awaited in between. The rendered-frame count is measured in the real
## app (`tools/playtest_flow.gd`).

const HUDScript := preload("res://src/presentation/hud/gameplay_hud.gd")

const PILL := {"name": &"ITEM_BO_HUYET_DAN_NAME", "count": 2}
const LESSON_A := {"name": &"KNOW_DAN_KHI_QUYET_NAME"}
const LESSON_B := {"name": &"KNOW_LAC_HA_STELE_RECORD_NAME"}


func _hud() -> Node:
	var hud: Node = HUDScript.new()
	add_to_tree(hud)
	return hud


func _t(key: String) -> String:
	return String(scene_tree.root.get_node("Localization").call("t", key))


func _use_language(code: String) -> void:
	scene_tree.root.get_node("Localization").call("set_language", code)


func _language() -> String:
	return String(scene_tree.root.get_node("Localization").call("get_language"))


## The notice's hold ran out (the timer is driven by hand: tests do not wait seconds).
func _expire(hud: Node) -> void:
	(hud.find_child("NoticeHold", true, false) as Timer).timeout.emit()


func _expire_banner(hud: Node) -> void:
	(hud.find_child("BreakthroughHold", true, false) as Timer).timeout.emit()


func _keys(values: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	for v: Variant in values:
		out.append(StringName(v))
	return out


# --- immediate feedback is never kept waiting ---------------------------------------------

func test_a_result_is_never_kept_waiting_behind_a_passive_notice() -> void:
	var before := _language()
	for code in ["vi", "en"]:
		_use_language(code)
		var hud := _hud()
		hud.call("announce", &"UI_ITEM_GAINED", PILL)
		assert_eq(hud.call("notice_kind"), GameplayHUD.NOTICE_PASSIVE,
			"%s: the pickup shows" % code)
		await scene_tree.process_frame  # the player acts later than the pickup
		hud.call("announce_result", &"UI_HUD_KNOWLEDGE_GAINED", LESSON_A)
		var text := String(hud.call("notice_text"))
		assert_true(text.contains(_t("KNOW_DAN_KHI_QUYET_NAME")),
			"%s: the lesson is on screen right after the call, no frame awaited (got '%s')"
				% [code, text])
		assert_eq(hud.call("notice_kind"), GameplayHUD.NOTICE_RESULT, "%s: as a RESULT" % code)
		assert_eq(hud.call("pending_notice_keys"), _keys([&"UI_ITEM_GAINED"]),
			"%s: the interrupted pickup notice is KEPT" % code)
		_expire(hud)
		assert_true(String(hud.call("notice_text")).contains(_t("ITEM_BO_HUYET_DAN_NAME")),
			"%s: and resumes when the lesson's hold is over" % code)
		free_node(hud)
	_use_language(before)


func test_an_answer_is_never_kept_waiting_behind_a_passive_notice() -> void:
	var before := _language()
	for code in ["vi", "en"]:
		_use_language(code)
		var hud := _hud()
		hud.call("announce", &"UI_ITEM_GAINED", PILL)
		await scene_tree.process_frame
		hud.call("announce_answer", &"UI_CULTIVATE_NO_METHOD")
		assert_eq(hud.call("notice_text"), _t("UI_CULTIVATE_NO_METHOD"),
			"%s: the refusal is on screen right after the call, no frame awaited" % code)
		assert_eq(hud.call("notice_kind"), GameplayHUD.NOTICE_ANSWER, "%s: as an ANSWER" % code)
		assert_eq(hud.call("pending_notice_keys"), _keys([&"UI_ITEM_GAINED"]),
			"%s: the pickup notice is kept" % code)
		_expire(hud)
		assert_true(String(hud.call("notice_text")).contains(_t("ITEM_BO_HUYET_DAN_NAME")),
			"%s: and resumes after the refusal" % code)
		free_node(hud)
	_use_language(before)


# --- passive notices: in order, never lost --------------------------------------------------

## The old queue held 4 and dropped the rest without a word: ten pickups must all be read.
func test_passive_notices_keep_their_order_and_none_is_dropped() -> void:
	var hud := _hud()
	for i in 10:
		hud.call("announce", &"UI_ITEM_GAINED", {"name": &"ITEM_LINH_THACH_NAME", "count": i + 1})
	var seen: Array[int] = []
	for _i in 10:
		var text := String(hud.call("notice_text"))
		for n in range(10, 0, -1):  # longest number first, so "10" is not read as "1"
			if text.contains("×%d" % n):
				seen.append(n)
				break
		_expire(hud)
	var expected: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
	assert_eq(seen, expected, "every pickup was shown, once, in the order it happened")
	assert_eq(hud.call("notice_text"), "", "and then the band is free")
	assert_false(hud.call("notice_backlog_overflowed"), "ten is a normal backlog")
	free_node(hud)


## Fail LOUDLY, drop nothing: past the guard the HUD reports a runaway producer and still keeps
## every notice. (The `[hud] ... past the guard` error in the log is this test's own.)
func test_the_backlog_guard_reports_a_runaway_producer_and_drops_nothing() -> void:
	var hud := _hud()
	var total := UIPalette.HUD_NOTICE_BACKLOG_GUARD + 3
	for i in total:
		hud.call("announce", &"UI_ITEM_GAINED", {"name": &"ITEM_LINH_THACH_NAME", "count": i})
	assert_true(hud.call("notice_backlog_overflowed"), "the overflow is reported")
	assert_eq((hud.call("pending_notice_keys") as Array).size(), total - 1,
		"and every notice past the guard is still waiting — none was dropped")
	var shown := 0
	while String(hud.call("notice_text")) != "":
		shown += 1
		_expire(hud)
	assert_eq(shown, total, "each one is shown in turn")
	free_node(hud)


# --- results: in order; answers: refreshed, superseded, never stale -----------------------

## A stele teaches two things in one reading: both are read, in order, before the pickups.
func test_the_results_of_one_action_keep_their_order() -> void:
	var hud := _hud()
	hud.call("announce", &"UI_ITEM_GAINED", PILL)
	await scene_tree.process_frame
	hud.call("announce_result", &"UI_HUD_KNOWLEDGE_GAINED", LESSON_A)
	hud.call("announce_result", &"UI_HUD_KNOWLEDGE_GAINED", LESSON_B)  # the same frame
	assert_true(String(hud.call("notice_text")).contains(_t("KNOW_DAN_KHI_QUYET_NAME")),
		"the first lesson is on screen")
	assert_eq(hud.call("pending_notice_keys"),
		_keys([&"UI_HUD_KNOWLEDGE_GAINED", &"UI_ITEM_GAINED"]),
		"the second lesson waits next, then the pickup")
	_expire(hud)
	assert_true(String(hud.call("notice_text")).contains(_t("KNOW_LAC_HA_STELE_RECORD_NAME")),
		"then the second lesson")
	_expire(hud)
	assert_true(String(hud.call("notice_text")).contains(_t("ITEM_BO_HUYET_DAN_NAME")),
		"then the pickup")
	free_node(hud)


## Spamming C at a spring with no method: one refusal, refreshed — never a backlog of copies
## that keeps printing the same sentence after the player has stopped.
func test_a_repeated_answer_refreshes_and_is_never_duplicated() -> void:
	var hud := _hud()
	for _i in 5:
		hud.call("announce_answer", &"UI_CULTIVATE_NO_METHOD")
		await scene_tree.process_frame
	assert_eq(hud.call("notice_text"), _t("UI_CULTIVATE_NO_METHOD"), "the refusal is up")
	assert_eq(hud.call("pending_notice_keys"), _keys([]), "and nothing is queued behind it")
	var hold := hud.find_child("NoticeHold", true, false) as Timer
	assert_true(hold.time_left > UIPalette.HUD_NOTICE_SECONDS - 0.5,
		"the last press refreshed its hold (%.2fs left)" % hold.time_left)
	_expire(hud)
	assert_eq(hud.call("notice_text"), "", "and it is gone once — not printed four more times")
	free_node(hud)


## A newer answer supersedes an older one; the stale refusal never comes back.
func test_a_new_answer_supersedes_a_stale_one() -> void:
	var hud := _hud()
	hud.call("announce_answer", &"UI_CULTIVATE_NO_SITE")
	await scene_tree.process_frame
	hud.call("announce_answer", &"UI_CULTIVATE_NO_METHOD")
	assert_eq(hud.call("notice_text"), _t("UI_CULTIVATE_NO_METHOD"), "the newer answer is up")
	assert_eq(hud.call("pending_notice_keys"), _keys([]), "the older one is not waiting")
	_expire(hud)
	assert_eq(hud.call("notice_text"), "", "and never re-shown")
	free_node(hud)


## A result interrupted by the next action is not lost: it resumes for the time it had left —
## never less than a readable minimum.
func test_an_interrupted_result_resumes_for_what_it_had_left() -> void:
	var hud := _hud()
	hud.call("announce_result", &"UI_HUD_KNOWLEDGE_GAINED", LESSON_A)
	var hold := hud.find_child("NoticeHold", true, false) as Timer
	hold.start(0.2)  # as if it had been on screen for most of its hold
	await scene_tree.process_frame
	hud.call("announce_answer", &"UI_CULTIVATE_NO_SITE")
	assert_eq(hud.call("pending_notice_keys"), _keys([&"UI_HUD_KNOWLEDGE_GAINED"]),
		"the interrupted lesson waits")
	_expire(hud)
	assert_true(String(hud.call("notice_text")).contains(_t("KNOW_DAN_KHI_QUYET_NAME")),
		"and comes back")
	assert_true(hold.wait_time >= UIPalette.HUD_NOTICE_RESUME_MIN_SECONDS - 0.001,
		"for at least the readable minimum (%.2fs)" % hold.wait_time)
	free_node(hud)


# --- the breakthrough banner: outranked by answers, never lost -----------------------------

func test_an_answer_takes_the_band_from_the_banner_which_resumes() -> void:
	var hud := _hud()
	hud.call("celebrate_breakthrough", &"REALM_HAU_THIEN_NAME", 1, true)
	assert_true(hud.call("is_breakthrough_banner_visible"), "the banner is up")
	await scene_tree.process_frame
	hud.call("announce_answer", &"UI_CULTIVATE_MISSING_KNOWLEDGE")
	assert_eq(hud.call("notice_text"), _t("UI_CULTIVATE_MISSING_KNOWLEDGE"),
		"the answer is on screen at once")
	assert_false(hud.call("is_breakthrough_banner_visible"), "the banner gave way")
	assert_true(hud.call("is_breakthrough_pending"), "PAUSED, not dropped")
	_expire(hud)
	assert_true(hud.call("is_breakthrough_banner_visible"), "it resumes after the answer")
	var hold := hud.find_child("BreakthroughHold", true, false) as Timer
	assert_true(hold.wait_time >= UIPalette.HUD_NOTICE_RESUME_MIN_SECONDS - 0.001,
		"for at least the readable minimum")
	_expire_banner(hud)
	assert_false(hud.call("is_breakthrough_banner_visible"), "and ends once")
	free_node(hud)


func test_the_banner_waits_for_an_answer_already_on_screen() -> void:
	var hud := _hud()
	hud.call("announce_result", &"UI_HUD_KNOWLEDGE_GAINED", LESSON_A)
	await scene_tree.process_frame
	hud.call("celebrate_breakthrough", &"REALM_HAU_THIEN_NAME", 1, true)
	assert_true(String(hud.call("notice_text")).contains(_t("KNOW_DAN_KHI_QUYET_NAME")),
		"the result stays on screen")
	assert_true(hud.call("is_breakthrough_pending"), "the banner waits its turn")
	_expire(hud)
	assert_true(hud.call("is_breakthrough_banner_visible"), "then the banner is up")
	free_node(hud)


func test_passive_notices_wait_behind_the_banner_and_are_kept() -> void:
	var hud := _hud()
	hud.call("announce", &"UI_ITEM_GAINED", PILL)
	await scene_tree.process_frame
	hud.call("celebrate_breakthrough", &"REALM_HAU_THIEN_NAME", 1, true)
	assert_true(hud.call("is_breakthrough_banner_visible"), "the banner outranks a pickup")
	hud.call("announce", &"UI_ITEM_GAINED", {"name": &"ITEM_LINH_THACH_NAME", "count": 1})
	assert_eq(hud.call("pending_notice_keys"), _keys([&"UI_ITEM_GAINED", &"UI_ITEM_GAINED"]),
		"the interrupted pickup and the new one both wait, in order")
	_expire_banner(hud)
	assert_true(String(hud.call("notice_text")).contains(_t("ITEM_BO_HUYET_DAN_NAME")),
		"the interrupted pickup resumes first")
	_expire(hud)
	assert_true(String(hud.call("notice_text")).contains(_t("ITEM_LINH_THACH_NAME")),
		"then the later one")
	free_node(hud)


## Answers keep coming during a breakthrough: the banner keeps waiting, and is still shown.
func test_the_banner_survives_a_run_of_answers() -> void:
	var hud := _hud()
	hud.call("celebrate_breakthrough", &"REALM_HAU_THIEN_NAME", 1, true)
	for key in [&"UI_CULTIVATE_NO_SITE", &"UI_CULTIVATE_NO_METHOD", &"UI_CULTIVATE_CEILING"]:
		await scene_tree.process_frame
		hud.call("announce_answer", key)
		assert_eq(hud.call("notice_text"), _t(String(key)), "each answer is on screen at once")
	assert_eq(hud.call("pending_notice_keys"), _keys([&"<breakthrough>"]),
		"only the banner waits — the superseded answers do not")
	_expire(hud)
	assert_true(hud.call("is_breakthrough_banner_visible"), "and the breakthrough is announced")
	free_node(hud)


# --- language -------------------------------------------------------------------------------

func test_a_language_change_re_renders_what_is_shown_and_what_waits() -> void:
	var before := _language()
	_use_language("vi")
	var hud := _hud()
	hud.call("announce", &"UI_ITEM_GAINED", PILL)
	await scene_tree.process_frame
	hud.call("announce_answer", &"UI_CULTIVATE_NO_METHOD")
	_use_language("en")
	await scene_tree.process_frame
	assert_eq(hud.call("notice_text"), _t("UI_CULTIVATE_NO_METHOD"),
		"the answer on screen is re-rendered in English")
	_expire(hud)
	assert_true(String(hud.call("notice_text")).contains(_t("ITEM_BO_HUYET_DAN_NAME")),
		"and the waiting pickup is rendered in the language of the moment it shows")
	free_node(hud)
	_use_language(before)
