extends TestCase
## Regression tests for NoticeSequenceValidator — the exact predicate used by
## tools/playtest_flow.gd 05d to prove the notice order. (D-063 A1 item #2 reopen.)

const R := "result"
const P := "passive"

func _expected() -> Array:
	return [
		{"kind": R, "contains": "Dan Khi Quyet"},
		{"kind": R, "contains": "Lac Ha Stele Record"},
		{"kind": P, "contains": "Bo Huyet Dan"},
		{"kind": P, "contains": "Manual Phong"},
		{"kind": P, "contains": "Dao Bao Thanh Van"},
	]

func _observed_full() -> Array[String]:
	return [
		"result:Dan Khi Quyet — lesson text",
		"result:Lac Ha Stele Record — lesson text",
		"passive:Bo Huyet Dan x2",
		"passive:Manual Phong",
		"passive:Dao Bao Thanh Van",
	]

func test_valid_full_sequence_passes() -> void:
	var verdict: Dictionary = NoticeSequenceValidator.validate(_observed_full(), _expected())
	assert_true(bool(verdict["ok"]),
		"valid lesson+3-pickup sequence passes: %s" % verdict["reason"])

func test_missing_pickup_notice_fails() -> void:
	var observed := _observed_full()
	observed.remove_at(2)  # drop the pill notice
	var verdict: Dictionary = NoticeSequenceValidator.validate(observed, _expected())
	assert_false(bool(verdict["ok"]), "missing pill notice fails")

func test_duplicate_pickup_notice_fails() -> void:
	var observed := _observed_full()
	observed.insert(3, "passive:Manual Phong")  # duplicate the manual notice
	var verdict: Dictionary = NoticeSequenceValidator.validate(observed, _expected())
	assert_false(bool(verdict["ok"]), "duplicate manual notice fails")

func test_unexpected_pickup_replacing_expected_fails() -> void:
	var observed := _observed_full()
	observed[4] = "passive:Strange Sword"  # robe replaced by an unexpected item
	var verdict: Dictionary = NoticeSequenceValidator.validate(observed, _expected())
	assert_false(bool(verdict["ok"]), "unexpected pickup replacing the robe fails")

func test_wrong_order_fails() -> void:
	var observed := _observed_full()
	var tmp: String = observed[2]
	observed[2] = observed[4]
	observed[4] = tmp  # pill and robe swapped
	var verdict: Dictionary = NoticeSequenceValidator.validate(observed, _expected())
	assert_false(bool(verdict["ok"]), "pill/robe swapped order fails")

func test_old_two_passive_sequence_fails_when_three_expected() -> void:
	# The old incorrect expectation (2 passives) must fail when all three pickups
	# were collected and all three notices are expected.
	var observed: Array[String] = [
		"result:Dan Khi Quyet — lesson text",
		"result:Lac Ha Stele Record — lesson text",
		"passive:Manual Phong",
		"passive:Dao Bao Thanh Van",
	]
	var verdict: Dictionary = NoticeSequenceValidator.validate(observed, _expected())
	assert_false(bool(verdict["ok"]), "two-passive sequence fails when three are expected")

func test_exact_length_required() -> void:
	var observed := _observed_full()
	observed.append("passive:Extra Notice")
	var verdict: Dictionary = NoticeSequenceValidator.validate(observed, _expected())
	assert_false(bool(verdict["ok"]), "extra trailing notice fails the exact-length check")

func test_wrong_kind_fails() -> void:
	var observed := _observed_full()
	observed[0] = "passive:Dan Khi Quyet — lesson text"  # lesson shown as passive
	var verdict: Dictionary = NoticeSequenceValidator.validate(observed, _expected())
	assert_false(bool(verdict["ok"]), "lesson with wrong kind fails")

func test_empty_sequence_fails() -> void:
	var verdict: Dictionary = NoticeSequenceValidator.validate([], _expected())
	assert_false(bool(verdict["ok"]), "empty observed sequence fails")


# --- identity: the set of every recorded id (D-063 interrupted-notice regression) ---------

func test_a_new_valid_id_is_accepted() -> void:
	assert_true(NoticeSequenceValidator.should_record("passive:X", 41, {}),
		"an id never recorded is a new notice")
	assert_true(NoticeSequenceValidator.should_record("passive:X", 41, {40: true}),
		"and stays new beside other recorded ids")


func test_a_repeated_frame_of_the_same_id_is_rejected() -> void:
	var sequence: Array[String] = []
	var recorded: Dictionary = {}
	for _frame in 5:
		NoticeSequenceValidator.record(sequence, recorded, P, "X", 40)
	assert_eq(sequence.size(), 1, "five frames of one notice are one observation")
	assert_false(NoticeSequenceValidator.should_record("X", 40, recorded),
		"the same id does not record twice")


func test_identical_kind_and_text_with_distinct_ids_are_both_accepted() -> void:
	var sequence: Array[String] = []
	var recorded: Dictionary = {}
	NoticeSequenceValidator.record(sequence, recorded, P, "X", 41)
	NoticeSequenceValidator.record(sequence, recorded, P, "X", 42)
	assert_eq(" | ".join(sequence), "passive:X | passive:X",
		"two instances with the same words are two notices")


## THE REGRESSION. A/41 shows, B/42 interrupts it, the HUD resumes A with its ORIGINAL id.
## The last-id-only predicate recorded A twice (41 != 42).
func test_a_resumed_notice_is_not_recorded_again() -> void:
	var sequence: Array[String] = []
	var recorded: Dictionary = {}
	for step in [[P, "A", 41], [R, "B", 42], [P, "A", 41]]:
		NoticeSequenceValidator.record(sequence, recorded, String(step[0]), String(step[1]),
			int(step[2]))
	assert_eq(" | ".join(sequence), "passive:A | result:B",
		"A/41 -> B/42 -> A/41 resumed records A and B only")
	assert_eq(recorded.size(), 2, "and exactly the two ids are remembered")


func test_a_recorded_id_stays_rejected_after_several_others() -> void:
	var sequence: Array[String] = []
	var recorded: Dictionary = {}
	NoticeSequenceValidator.record(sequence, recorded, P, "A", 41)
	for seq in [42, 43, 44, 45]:
		NoticeSequenceValidator.record(sequence, recorded, R, "later", seq)
	var again: Dictionary = NoticeSequenceValidator.record(sequence, recorded, P, "A", 41)
	assert_false(bool(again["recorded"]), "A/41 is still known four notices later")
	assert_eq(String(again["diagnostic"]), "", "and a resumed notice is ordinary, not an error")
	assert_eq(sequence.size(), 5, "five distinct notices, five entries")


func test_blank_text_is_rejected() -> void:
	for text in ["", " ", "\t \n"]:
		assert_false(NoticeSequenceValidator.should_record(text, 41, {}),
			"blank text '%s' never records, even with a valid id" % text.c_escape())


func test_non_positive_ids_are_rejected() -> void:
	for seq in [0, -1, -41]:
		assert_false(NoticeSequenceValidator.should_record("passive:X", seq, {}),
			"id %d never records" % seq)


func test_the_id_is_marked_only_after_the_entry_is_written() -> void:
	var sequence: Array[String] = []
	var recorded: Dictionary = {}
	NoticeSequenceValidator.record(sequence, recorded, P, "", 41)
	NoticeSequenceValidator.record(sequence, recorded, "", "X", 41)
	assert_true(recorded.is_empty() and sequence.is_empty(),
		"a rejected observation marks no id, so the well-formed notice 41 can still record")
	assert_true(bool(NoticeSequenceValidator.record(sequence, recorded, P, "X", 41)["recorded"]),
		"which it then does")


## Malformed input fails SAFE (nothing recorded) and says why; ordinary non-observations — an
## empty slot, a repeated frame — stay silent so a per-frame caller is not flooded.
func test_malformed_input_is_diagnosed_and_ordinary_input_is_silent() -> void:
	var sequence: Array[String] = []
	var recorded: Dictionary = {}
	for bad in [[P, "X", -3], [P, "X", 0], [P, "  ", 7], ["", "X", 7]]:
		var verdict: Dictionary = NoticeSequenceValidator.record(sequence, recorded,
			String(bad[0]), String(bad[1]), int(bad[2]))
		assert_false(bool(verdict["recorded"]), "malformed %s is not recorded" % str(bad))
		assert_ne(String(verdict["diagnostic"]), "", "and is diagnosed: %s" % str(bad))
	assert_true(sequence.is_empty() and recorded.is_empty(), "nothing was written")
	var blank: Dictionary = NoticeSequenceValidator.record(sequence, recorded, "", "", 0)
	assert_eq(String(blank["diagnostic"]), "", "an empty slot is ordinary")
	NoticeSequenceValidator.record(sequence, recorded, P, "X", 7)
	var repeat: Dictionary = NoticeSequenceValidator.record(sequence, recorded, P, "X", 7)
	assert_eq(String(repeat["diagnostic"]), "", "a repeated frame is ordinary")
	assert_false(bool(repeat["recorded"]), "and not recorded")
