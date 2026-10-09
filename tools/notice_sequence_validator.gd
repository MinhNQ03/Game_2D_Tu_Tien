class_name NoticeSequenceValidator
## Validates an observed HUD notice sequence against an explicit expected order.
##
## The playtest (`tools/playtest_flow.gd` 05d) observes the band as "kind:text" strings.
## This predicate proves each required notice appears exactly once, in the expected order —
## a missing, duplicate, unexpected or out-of-order notice fails. It is the same predicate
## the playtest uses (not a copy), and the unit tests exercise it directly.

## Whether the currently shown notice should be recorded as a new sequence entry.
## Identity-based: a non-empty text with a non-zero seq different from the last recorded
## seq is a new instance — even if kind and text are identical to the previous entry.
## A zero seq (empty slot) or a repeated seq never records, so an invalid identity
## cannot produce a false entry.
static func should_record(text: String, seq: int, last_seq: int) -> bool:
	return text != "" and seq != 0 and seq != last_seq


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
