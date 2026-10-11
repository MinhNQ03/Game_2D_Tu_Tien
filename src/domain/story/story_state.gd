extends RefCounted
class_name StoryState
## StoryState — Aetheria domain (where the story stands for this run, Phase 20, D-072).
##
## The ONLY record of: the run's Origin, the current chapter and beat, what has been
## completed, every decision that was made (in order), and whom the player has met. Mutated
## only by `StoryService`.
##
## STORY FLAGS ARE NOT HERE. They have one store — the player's `CharacterState.story_flags` —
## and this class does not repeat them, so a snapshot of the story and a snapshot of the
## character can never disagree about a flag.
##
## Pure data and its persistence boundary (`docs/SAVE_FORMAT.md` `story`). No file I/O.

const SCHEMA := 1

var origin_id: StringName = &""
var chapter_id: StringName = &""
var beat_id: StringName = &""
var completed_chapters: Array[StringName] = []
var completed_beats: Array[StringName] = []
## [{"choice_id": String, "option_id": String}], in the order they were made.
var choices: Array[Dictionary] = []
## Instance ids of the named characters the player has spoken to, in order.
var met: Array[StringName] = []


## Has a run begun (an Origin chosen and a first beat entered)?
func has_begun() -> bool:
	return origin_id != &"" and beat_id != &""


func option_of(choice_id: StringName) -> StringName:
	for record in choices:
		if record["choice_id"] == String(choice_id):
			return StringName(String(record["option_id"]))
	return &""


func has_chosen(choice_id: StringName) -> bool:
	return option_of(choice_id) != &""


func has_met(character_id: StringName) -> bool:
	return met.has(character_id)


func has_completed(completed_beat_id: StringName) -> bool:
	return completed_beats.has(completed_beat_id)


# --- Persistence boundary --------------------------------------------------------

func to_dict() -> Dictionary:
	var out_choices: Array = []
	for record in choices:
		out_choices.append({"choice_id": String(record["choice_id"]),
			"option_id": String(record["option_id"])})
	return {
		"schema": SCHEMA,
		"origin_id": String(origin_id),
		"chapter_id": String(chapter_id),
		"beat_id": String(beat_id),
		"completed_chapters": _strings(completed_chapters),
		"completed_beats": _strings(completed_beats),
		"choices": out_choices,
		"met": _strings(met),
	}


## Hydrate from `to_dict()` output, validated against the catalogs. Atomic and strict (L-024):
## an unknown origin, chapter, beat, choice or option, a beat that is not in its chapter, a
## repeated entry, a current beat also listed as completed, an unexpected key or any wrong
## type rejects the WHOLE payload and changes nothing.
func from_dict(data: Dictionary, catalog: StoryCatalogData, origins: OriginCatalogData) -> bool:
	var staged := _staged(data, catalog, origins)
	if staged == null:
		return false
	origin_id = staged.origin_id
	chapter_id = staged.chapter_id
	beat_id = staged.beat_id
	completed_chapters = staged.completed_chapters
	completed_beats = staged.completed_beats
	choices = staged.choices
	met = staged.met
	return true


static func _staged(data: Dictionary, catalog: StoryCatalogData,
		origins: OriginCatalogData) -> StoryState:
	if catalog == null or origins == null:
		push_error("[story-state] from_dict: no catalog to validate against")
		return null
	var expected := ["schema", "origin_id", "chapter_id", "beat_id", "completed_chapters",
		"completed_beats", "choices", "met"]
	for key: Variant in data:
		if not expected.has(key):
			return _reject("unexpected key '%s'" % str(key))
	if typeof(data.get("schema")) != TYPE_INT or int(data["schema"]) != SCHEMA:
		return _reject("unsupported schema %s" % str(data.get("schema")))
	for key: String in ["origin_id", "chapter_id", "beat_id"]:
		if typeof(data.get(key)) != TYPE_STRING:
			return _reject("'%s' must be a String" % key)
	var staged := StoryState.new()
	staged.origin_id = StringName(String(data["origin_id"]))
	staged.chapter_id = StringName(String(data["chapter_id"]))
	staged.beat_id = StringName(String(data["beat_id"]))
	if not origins.has(staged.origin_id):
		return _reject("unknown origin '%s'" % staged.origin_id)
	var chapter := catalog.chapter(staged.chapter_id)
	if chapter == null or chapter.beat(staged.beat_id) == null:
		return _reject("beat '%s' is not in chapter '%s'" % [staged.beat_id, staged.chapter_id])
	var listed := _unique_ids(data.get("completed_chapters"))
	if listed.is_empty() and not _is_empty_array(data.get("completed_chapters")):
		return _reject("'completed_chapters' is not a list of distinct ids")
	for id in listed:
		if catalog.chapter(id) == null or id == staged.chapter_id:
			return _reject("completed chapter '%s' is unknown or is the current one" % id)
	staged.completed_chapters = listed
	listed = _unique_ids(data.get("completed_beats"))
	if listed.is_empty() and not _is_empty_array(data.get("completed_beats")):
		return _reject("'completed_beats' is not a list of distinct ids")
	for id in listed:
		if catalog.beat(id) == null or id == staged.beat_id:
			return _reject("completed beat '%s' is unknown or is the current one" % id)
	staged.completed_beats = listed
	listed = _unique_ids(data.get("met"))
	if listed.is_empty() and not _is_empty_array(data.get("met")):
		return _reject("'met' is not a list of distinct ids")
	staged.met = listed
	if typeof(data.get("choices")) != TYPE_ARRAY:
		return _reject("'choices' must be an Array")
	for raw: Variant in data["choices"]:
		if typeof(raw) != TYPE_DICTIONARY or (raw as Dictionary).size() != 2 \
				or typeof(raw.get("choice_id")) != TYPE_STRING \
				or typeof(raw.get("option_id")) != TYPE_STRING:
			return _reject("a choice record is not {choice_id, option_id}")
		var asked := catalog.choice(StringName(String(raw["choice_id"])))
		if asked == null or asked.option(StringName(String(raw["option_id"]))) == null \
				or staged.has_chosen(asked.id):
			return _reject("choice record '%s' -> '%s' is unknown or repeated"
				% [raw["choice_id"], raw["option_id"]])
		staged.choices.append({"choice_id": String(raw["choice_id"]),
			"option_id": String(raw["option_id"])})
	return staged


static func _reject(why: String) -> StoryState:
	push_error("[story-state] from_dict: %s" % why)
	return null


static func _strings(ids: Array[StringName]) -> Array:
	var out: Array = []
	for id in ids:
		out.append(String(id))
	return out


static func _is_empty_array(raw: Variant) -> bool:
	return typeof(raw) == TYPE_ARRAY and (raw as Array).is_empty()


## `raw` as distinct, non-empty ids — or an empty list when it is not such a list.
static func _unique_ids(raw: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for entry: Variant in raw:
		if typeof(entry) != TYPE_STRING or String(entry) == "" \
				or out.has(StringName(String(entry))):
			var none: Array[StringName] = []
			return none
		out.append(StringName(String(entry)))
	return out
