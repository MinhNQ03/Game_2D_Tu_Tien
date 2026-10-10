class_name NoticeSequenceValidator
## Validates an observed HUD notice sequence against an explicit expected order.
##
## The playtest (`tools/playtest_flow.gd` 05d) observes the band as "kind:text" strings.
## This predicate proves each required notice appears exactly once, in the expected order —
## a missing, duplicate, unexpected or out-of-order notice fails. It is the same predicate
## and the same recorder the playtest uses (not a copy), and the unit tests exercise them
## directly.

## Whether the currently shown notice is a NEW observation.
##
## IDENTITY IS THE SEQUENCE ID, AND MEMORY IS EVERY ID RECORDED SO FAR. The HUD preserves an
## interrupted notice and RESUMES it with its original `seq` (A/41 -> B/42 interrupts -> A/41
## resumes). Comparing only against the last recorded id (the first version) recorded the
## resumed A a second time, because 41 != 42 — one logical notice counted twice. `recorded` is
## the per-collection set of ids already recorded (id -> true), so an id is new exactly once,
## however many other notices appeared in between.
##
## Never records: blank / whitespace-only text (an empty slot), a non-positive id (no notice
## carries one), or an id already in `recorded` (a repeated frame, or a resumed notice). Two
## notices with identical kind and text but different ids are two notices. No text or timing
## heuristic. Pure: it does not touch `recorded` — the caller adds the id only AFTER the
## observation was appended (`record`).
static func should_record(text: String, seq: int, recorded: Dictionary) -> bool:
	return seq > 0 and text.strip_edges() != "" and not recorded.has(seq)


## Why an observation is MALFORMED (as opposed to ordinarily not-new), or "". A blank slot
## (`seq == 0`, empty text) and a repeated id are ordinary and stay silent, so a per-frame
## caller is not flooded; a negative id, an id with no text, text with no id, or a new notice
## with no kind can only come from a broken producer and deserve a line in the report.
static func malformed_reason(kind: String, text: String, seq: int) -> String:
	var blank := text.strip_edges() == ""
	if seq < 0:
		return "negative notice sequence id %d" % seq
	if seq == 0 and not blank:
		return "notice text '%s' with no sequence id" % text
	if seq > 0 and blank:
		return "notice sequence id %d with blank text" % seq
	if seq > 0 and kind.strip_edges() == "":
		return "notice sequence id %d ('%s') with no kind" % [seq, text]
	return ""


## Record one observation into `sequence` ("kind:text") and mark its id in `recorded`, when —
## and only when — it is a new, well-formed notice. The id is added AFTER the append, so an id
## is never marked for an entry that was not written. Returns
## {"recorded": bool, "diagnostic": String}: `diagnostic` is non-empty only for malformed input
## (see `malformed_reason`), which is never recorded.
static func record(sequence: Array[String], recorded: Dictionary, kind: String, text: String,
		seq: int) -> Dictionary:
	var diagnostic := malformed_reason(kind, text, seq)
	if diagnostic != "" or not should_record(text, seq, recorded):
		return {"recorded": false, "diagnostic": diagnostic}
	sequence.append("%s:%s" % [kind, text])
	recorded[seq] = true
	return {"recorded": true, "diagnostic": ""}


## Validate `observed` ("kind:text" strings) against `expected` (array of
## {"kind": String, "contains": String}). Returns {"ok": bool, "reason": String}.
static func validate(observed: Array[String], expected: Array) -> Dictionary:
	if observed.size() != expected.size():
		return {"ok": false,
			"reason": "length mismatch: observed %d, expected %d" % [observed.size(),
				expected.size()]}
	for i in expected.size():
		var exp: Dictionary = expected[i]
		var parts := observed[i].split(":", true, 1)
		if parts.size() < 2:
			return {"ok": false,
				"reason": "entry %d malformed: '%s'" % [i, observed[i]]}
		var kind := parts[0]
		var text := parts[1]
		if kind != String(exp["kind"]):
			return {"ok": false,
				"reason": "entry %d kind mismatch: observed '%s', expected '%s'" % [i, kind,
					String(exp["kind"])]}
		if not text.contains(String(exp["contains"])):
			return {"ok": false,
				"reason": "entry %d text mismatch: '%s' does not contain '%s'" % [i, text,
					String(exp["contains"])]}
	return {"ok": true, "reason": ""}
