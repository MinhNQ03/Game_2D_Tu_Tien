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


func test_should_record_new_instance_with_identical_text() -> void:
	# Two consecutive instances with identical kind+text but different seq are
	# recorded as two instances — the text-change heuristic would collapse them.
	assert_true(NoticeSequenceValidator.should_record("passive:X", 41, 40),
		"new seq records even with identical text")
	assert_true(NoticeSequenceValidator.should_record("passive:X", 42, 41),
		"third instance with identical text also records")

func test_should_record_rejects_repeated_seq() -> void:
	assert_false(NoticeSequenceValidator.should_record("passive:X", 40, 40),
		"same seq does not record twice")

func test_should_record_rejects_empty_identity() -> void:
	assert_false(NoticeSequenceValidator.should_record("passive:X", 0, 39),
		"zero seq (empty slot) never records")
	assert_false(NoticeSequenceValidator.should_record("", 41, 40),
		"empty text never records even with a valid seq")
