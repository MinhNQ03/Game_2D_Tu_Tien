extends RefCounted
class_name StoryIds
## StoryIds — Aetheria data (what a stable story id is, Phase 20, D-072).
##
## Every Origin, chapter, beat, flag, choice and option is named by an id that is written into
## resources, tests, documents and — from Phase 23 — save files. Such an id is lower-case ASCII:
## a letter, then letters, digits and underscores. Nothing else.
##
## The rule exists because of a real defect: the canon ledger spelt `origin_ho_tieu` with a
## Cyrillic `о` (U+043E). It rendered identically and compared unequal.

const FIRST := "abcdefghijklmnopqrstuvwxyz"
const REST := "abcdefghijklmnopqrstuvwxyz0123456789_"


static func is_stable(id: StringName) -> bool:
	var text := String(id)
	if text.is_empty() or not FIRST.contains(text[0]):
		return false
	for i in text.length():
		if not REST.contains(text[i]):
			return false
	return true


## The error to report for `id`, or "" when it is stable. `what` names the thing ("beat").
static func problem(what: String, id: StringName) -> String:
	if id == &"":
		return "a %s has no id" % what
	if not is_stable(id):
		return "%s id '%s' is not lower-case ASCII (a-z, 0-9, _; a letter first)" % [what, id]
	return ""
