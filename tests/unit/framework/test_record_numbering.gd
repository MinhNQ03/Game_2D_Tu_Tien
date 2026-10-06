extends TestCase
## The project's numbered records stay citable: every `## L-NNN` lesson number is used ONCE.
##
## A lesson is cited by number from code comments, decisions and other lessons ("see L-038"),
## so a number used twice makes every such citation ambiguous. It happened TWICE in a row
## (D-056 review pass): the D-055 follow-up appended a second `L-038` and D-056 a second
## `L-039`, each numbered from memory instead of from the last heading in the file, and a new
## code comment then cited the wrong one. Nothing failed, because nothing read the file.
##
## Lessons only: `DECISIONS.md` legitimately reuses a number for a sub-section ("D-048 review
## pass", "D-055 FOLLOW-UP"), so the same rule there would be a false alarm.

const LESSONS_PATH := "res://.kiro/steering/09-lessons-learned.md"


func test_every_lesson_number_is_used_once_and_in_order() -> void:
	var text := FileAccess.get_file_as_string(LESSONS_PATH)
	assert_true(not text.is_empty(), "the lessons file is readable at %s" % LESSONS_PATH)
	if text.is_empty():
		return
	var numbers := _lesson_numbers(text)
	# The walk itself must work, or "no duplicates" would be trivially true of nothing.
	assert_true(numbers.size() >= 40,
		"the heading walk found the lessons (%d found)" % numbers.size())
	assert_eq(_duplicates(numbers), [],
		("each L-number is used once — a reused number makes every citation of it ambiguous. "
			+ "Number a new lesson from the LAST heading in the file, not from memory"))
	# STRICTLY INCREASING, not contiguous: L-012 was never written, and renumbering 29 lessons
	# to close a gap nobody cites would break every existing citation to fix nothing. What
	# matters is that the next lesson is appended after the last one.
	for i in range(1, numbers.size()):
		if numbers[i] <= numbers[i - 1]:
			assert_true(false,
				("lessons are appended in increasing order — L-%03d follows L-%03d "
					+ "(heading %d)") % [numbers[i], numbers[i - 1], i + 1])
			break


## The check is not vacuous: the exact collision that shipped is detected.
func test_a_reused_lesson_number_is_detected() -> void:
	var fixture := ("## L-037 — a\nbody\n## L-038 — b\n## L-039 — c\n"
		+ "## L-038 — the collision\n")
	assert_eq(_duplicates(_lesson_numbers(fixture)), [38],
		"a second `## L-038` heading is reported as a duplicate")
	# A citation in prose, or a heading at another level, is not a lesson heading.
	assert_eq(_lesson_numbers("see L-038 in prose\n### L-038 sub\n## L-001 — a\n"), [1],
		"only `## L-NNN` headings count")


func _lesson_numbers(text: String) -> Array[int]:
	var heading := RegEx.create_from_string("(?m)^## L-(\\d{3})\\b")
	var numbers: Array[int] = []
	for found in heading.search_all(text):
		numbers.append(int(found.get_string(1)))
	return numbers


func _duplicates(numbers: Array[int]) -> Array[int]:
	var seen := {}
	var repeated: Array[int] = []
	for n in numbers:
		if seen.has(n) and not repeated.has(n):
			repeated.append(n)
		seen[n] = true
	return repeated
