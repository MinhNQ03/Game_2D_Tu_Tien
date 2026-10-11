extends RefCounted
class_name StoryService
## StoryService — Aetheria domain (the rules of the story, Phase 20, D-072).
##
## The ONLY writer of `StoryState` (Origin, chapter, beat, completed beats, the choice record,
## who has been met) and the ONLY writer of story flags, which live in ONE place: the player's
## `CharacterState.story_flags`. Pure: no node, no scene, no text, no clock.
##
## WHAT IT DOES NOT OWN, and therefore only asks for through `StoryOwners`: what the player
## knows, how anyone regards them, what is in the bag. A decision's consequences are carried
## out by those owners; the story records that the decision was made.
##
## HOW THE STORY MOVES. Each beat has one trigger. A STATE trigger (a flag, a choice, a thing
## known, people met) is asked whenever the record changes and when the beat is entered — so
## what the player already did counts. An EVENT trigger (a scene ended, an arrival, a
## cultivation session) completes the beat only if it happens while that beat is current.
## There is no polling: every method that can change the answer ends by settling.
##
## EVERY REFUSAL CHANGES NOTHING. Each mutation checks everything it will need — including
## that the owners it must ask are there — before it writes the first thing.

const REFUSE_NOT_READY := &"story_not_ready"
const REFUSE_NOT_BEGUN := &"story_not_begun"
const REFUSE_ALREADY_BEGUN := &"story_already_begun"
const REFUSE_UNKNOWN_ORIGIN := &"story_unknown_origin"
## The Origin's starting kit does not fit in the bag.
const REFUSE_NO_ROOM := &"story_origin_no_room"
## An owner the content needs was not provided, or said no.
const REFUSE_OWNER := &"story_owner_refused"
const REFUSE_UNKNOWN_FLAG := &"story_unknown_flag"
const REFUSE_FLAG_VALUE := &"story_flag_value"
const REFUSE_UNKNOWN_CHOICE := &"story_unknown_choice"
const REFUSE_ALREADY_CHOSEN := &"story_already_chosen"
## The choice belongs to another beat.
const REFUSE_WRONG_BEAT := &"story_wrong_beat"
const REFUSE_NOT_AN_EVENT := &"story_not_an_event"
const REFUSE_NOBODY := &"story_nobody"

## The source id the Knowledge Core records for what the story teaches.
const KNOWLEDGE_SOURCE_FORMAT := "story:%s"
## ...and the prefix of the ones that came with an Origin (`story:origin_*`).
const ORIGIN_SOURCE_PREFIX := "story:origin_"

var _catalog: StoryCatalogData = null
var _origins: OriginCatalogData = null
var _state: StoryState = null
## The player's authoritative record. Its `story_flags` is the one store of flags.
var _player: CharacterState = null
var _owners: StoryOwners = null


func _init(catalog: StoryCatalogData = null, origins: OriginCatalogData = null,
		state: StoryState = null, player: CharacterState = null,
		owners: StoryOwners = null) -> void:
	if catalog == null or not catalog.is_valid():
		if catalog != null:
			push_error("[story] refusing an invalid story catalog: %s"
				% str(catalog.validation_errors()))
		return
	if origins == null or not origins.is_valid():
		if origins != null:
			push_error("[story] refusing an invalid origin catalog: %s"
				% str(origins.validation_errors()))
		return
	if state == null or player == null or owners == null:
		return
	_catalog = catalog
	_origins = origins
	_state = state
	_player = player
	_owners = owners


func is_ready() -> bool:
	return _catalog != null and _origins != null and _state != null and _player != null


func catalog() -> StoryCatalogData:
	return _catalog


func origins() -> OriginCatalogData:
	return _origins


func state() -> StoryState:
	return _state


## Did `source_id` come from an Origin's starting kit (rather than from something the player
## did)? Presentation asks, so that what a character already knew is not announced as learned.
static func is_origin_source(source_id: StringName) -> bool:
	return String(source_id).begins_with(ORIGIN_SOURCE_PREFIX)


# --- Reading -------------------------------------------------------------------

func has_begun() -> bool:
	return is_ready() and _state.has_begun()


func origin() -> OriginData:
	return _origins.entry(_state.origin_id) if has_begun() else null


func origin_is(origin_id: StringName) -> bool:
	return has_begun() and _state.origin_id == origin_id


func current_beat() -> StoryBeatData:
	return _catalog.beat(_state.beat_id) if has_begun() else null


func current_chapter() -> StoryChapterData:
	return _catalog.chapter(_state.chapter_id) if has_begun() else null


## The scene the current beat is entered with, or empty: its own, or the Origin's vignette.
func entry_scene_id() -> StringName:
	var beat := current_beat()
	if beat == null:
		return &""
	if beat.plays_origin_vignette:
		return _origins.entry(_state.origin_id).vignette_scene_id
	return beat.entry_scene_id


## The current beat's objective key, or empty before a run begins.
func objective_key() -> StringName:
	var beat := current_beat()
	return beat.objective_key if beat != null else &""


## What flag `flag_id` reads: 0 when unset or undeclared, 0/1 for a BOOL, its count for an INT.
func flag_value(flag_id: StringName) -> int:
	if not is_ready() or _catalog.flag(flag_id) == null:
		return 0
	var stored: Variant = _player.story_flags.get(String(flag_id))
	if typeof(stored) == TYPE_BOOL:
		return 1 if bool(stored) else 0
	return int(stored) if typeof(stored) == TYPE_INT else 0


func flag_at_least(flag_id: StringName, value: int) -> bool:
	return flag_value(flag_id) >= value


func condition_holds(condition: StoryConditionData) -> bool:
	if condition == null or not has_begun():
		return false
	var holds := false
	match condition.kind:
		StoryConditionData.Kind.FLAG:
			holds = flag_at_least(condition.flag_id, condition.value)
		StoryConditionData.Kind.ORIGIN:
			holds = _state.origin_id == condition.origin_id
		StoryConditionData.Kind.CHOICE:
			holds = _state.option_of(condition.choice_id) == condition.option_id
		StoryConditionData.Kind.KNOWS:
			holds = _knows(condition.knowledge_id)
	return holds != condition.negate


# --- Beginning a run -----------------------------------------------------------

## Begin the run as `origin_id`: hand over that Origin's starting kit through its owners,
## enter the first beat, and settle.
##
## Checked whole before anything is given: the Origin exists, the story has not begun and
## every owner a grant needs is present. Then the ITEMS go first, as one all-or-nothing ask of
## the bag — the only grant that can be refused for a reason of state (no room) — so a refusal
## there has given nothing at all. What follows (knowledge, a first impression) cannot be
## refused by an owner that is present; if one is anyway, the story is left NOT begun and says
## so, and the caller's only correct answer is to discard the session (`StoryRuntime` does).
func begin(origin_id: StringName) -> StoryOutcome:
	if not is_ready():
		return StoryOutcome.refused(REFUSE_NOT_READY)
	if _state.has_begun():
		return StoryOutcome.refused(REFUSE_ALREADY_BEGUN)
	var chosen := _origins.entry(origin_id)
	if chosen == null:
		return StoryOutcome.refused(REFUSE_UNKNOWN_ORIGIN)
	var items := {}
	for grant in chosen.grants:
		if not _can_carry_out_grant(grant):
			return StoryOutcome.refused(REFUSE_OWNER)
		if grant.kind == OriginGrantData.Kind.ITEM:
			items[grant.item_id] = grant.count
	if not items.is_empty() and not bool(_owners.give_all.call(items)):
		return StoryOutcome.refused(REFUSE_NO_ROOM)
	for grant in chosen.grants:
		if grant.kind != OriginGrantData.Kind.ITEM and not _carry_out_grant(chosen.id, grant):
			push_error("[story] origin '%s': an owner refused '%s' after agreeing to it"
				% [chosen.id, grant.target_key()])
			return StoryOutcome.refused(REFUSE_OWNER)
	var first := _catalog.beat(_catalog.start_beat_id)
	_state.origin_id = chosen.id
	_state.chapter_id = _catalog.chapter_of(first.id).id
	_state.beat_id = first.id
	return _settled(StoryOutcome.new())


func _can_carry_out_grant(grant: OriginGrantData) -> bool:
	match grant.kind:
		OriginGrantData.Kind.ITEM:
			return _owners.give_all.is_valid()
		OriginGrantData.Kind.KNOWLEDGE:
			return _owners.teach.is_valid()
		OriginGrantData.Kind.REGARD:
			return _owners.move_regard.is_valid()
	return false


func _carry_out_grant(origin_id: StringName, grant: OriginGrantData) -> bool:
	match grant.kind:
		OriginGrantData.Kind.KNOWLEDGE:
			return bool(_owners.teach.call(grant.knowledge_id,
				StringName(KNOWLEDGE_SOURCE_FORMAT % origin_id)))
		OriginGrantData.Kind.REGARD:
			return bool(_owners.move_regard.call(grant.character_id, grant.dimension,
				grant.delta))
	return false


# --- Flags (the one writer) ----------------------------------------------------

## Set flag `flag_id` to `value` (0 or 1 for a BOOL). Refuses an undeclared flag and a value
## outside what the flag holds, and changes nothing when it refuses.
func set_flag(flag_id: StringName, value: int) -> StoryOutcome:
	if not has_begun():
		return StoryOutcome.refused(REFUSE_NOT_BEGUN if is_ready() else REFUSE_NOT_READY)
	var declared := _catalog.flag(flag_id)
	if declared == null:
		return StoryOutcome.refused(REFUSE_UNKNOWN_FLAG)
	if value < 0 or value > declared.ceiling():
		return StoryOutcome.refused(REFUSE_FLAG_VALUE)
	_write_flag(declared, value)
	return _settled(StoryOutcome.new())


func _write_flag(declared: StoryFlagData, value: int) -> void:
	if declared.kind == StoryFlagData.Kind.BOOL:
		_player.story_flags[String(declared.id)] = value == 1
	else:
		_player.story_flags[String(declared.id)] = value


## What is wrong with the flags the player's record holds RIGHT NOW: an undeclared id, a value
## of the wrong type, or one out of range. Empty when the store is sound. Asked after a
## record is hydrated, because the flags arrive with the character, not with the story.
func flag_errors() -> Array[String]:
	var errors: Array[String] = []
	if not is_ready():
		errors.append("the story service is not ready")
		return errors
	for raw_key: Variant in _player.story_flags:
		var declared := _catalog.flag(StringName(String(raw_key))) \
			if typeof(raw_key) == TYPE_STRING else null
		var stored: Variant = _player.story_flags[raw_key]
		if declared == null:
			errors.append("flag '%s' is not declared" % str(raw_key))
		elif declared.kind == StoryFlagData.Kind.BOOL and typeof(stored) != TYPE_BOOL:
			errors.append("BOOL flag '%s' holds %s" % [declared.id, type_string(typeof(stored))])
		elif declared.kind == StoryFlagData.Kind.INT and (typeof(stored) != TYPE_INT
				or int(stored) < 0 or int(stored) > declared.max_value):
			errors.append("INT flag '%s' holds %s" % [declared.id, str(stored)])
	return errors


# --- Choices -------------------------------------------------------------------

## Answer choice `choice_id` with `option_id`. THE transaction for a story decision: it is
## recorded once, and its consequences are carried out by their owners, in this one call.
## A second answer to the same choice — a repeated key, a signal delivered twice, a stale
## panel — is refused and changes nothing.
func choose(choice_id: StringName, option_id: StringName) -> StoryOutcome:
	if not has_begun():
		return StoryOutcome.refused(REFUSE_NOT_BEGUN if is_ready() else REFUSE_NOT_READY)
	var asked := _catalog.choice(choice_id)
	var answer := asked.option(option_id) if asked != null else null
	if answer == null:
		return StoryOutcome.refused(REFUSE_UNKNOWN_CHOICE)
	if _state.has_chosen(choice_id):
		return StoryOutcome.refused(REFUSE_ALREADY_CHOSEN)
	if asked.beat_id != &"" and asked.beat_id != _state.beat_id:
		return StoryOutcome.refused(REFUSE_WRONG_BEAT)
	for consequence in answer.consequences:
		if not _can_carry_out(consequence):
			return StoryOutcome.refused(REFUSE_OWNER)
	_state.choices.append({"choice_id": String(choice_id), "option_id": String(option_id)})
	for consequence in answer.consequences:
		if not _carry_out(choice_id, consequence):
			push_error("[story] choice '%s': an owner refused '%s' after agreeing to it"
				% [choice_id, consequence.target_key()])
	var outcome := StoryOutcome.new()
	outcome.choice_id = choice_id
	outcome.option_id = option_id
	return _settled(outcome)


func _can_carry_out(consequence: StoryConsequenceData) -> bool:
	match consequence.kind:
		StoryConsequenceData.Kind.SET_FLAG:
			return _catalog.flag(consequence.flag_id) != null
		StoryConsequenceData.Kind.REGARD:
			return _owners.move_regard.is_valid()
		StoryConsequenceData.Kind.GRANT_KNOWLEDGE:
			return _owners.teach.is_valid()
	return false


func _carry_out(choice_id: StringName, consequence: StoryConsequenceData) -> bool:
	match consequence.kind:
		StoryConsequenceData.Kind.SET_FLAG:
			_write_flag(_catalog.flag(consequence.flag_id), consequence.value)
			return true
		StoryConsequenceData.Kind.REGARD:
			return bool(_owners.move_regard.call(consequence.character_id,
				consequence.dimension, consequence.delta))
		StoryConsequenceData.Kind.GRANT_KNOWLEDGE:
			return bool(_owners.teach.call(consequence.knowledge_id,
				StringName(KNOWLEDGE_SOURCE_FORMAT % choice_id)))
	return false


# --- What happens in the world -------------------------------------------------

## The player has spoken to `character_id`. Recorded once; a second meeting changes nothing.
func meet(character_id: StringName) -> StoryOutcome:
	if not has_begun():
		return StoryOutcome.refused(REFUSE_NOT_BEGUN if is_ready() else REFUSE_NOT_READY)
	if character_id == &"":
		return StoryOutcome.refused(REFUSE_NOBODY)
	if not _state.has_met(character_id):
		_state.met.append(character_id)
	return _settled(StoryOutcome.new())


## Something happened: a story scene ended, the player arrived in a map, a cultivation
## session yielded. It completes the current beat only if that beat is waiting for exactly
## this; otherwise it is noted and nothing moves.
func note(kind: StoryTriggerData.Kind, subject_id: StringName = &"") -> StoryOutcome:
	if not has_begun():
		return StoryOutcome.refused(REFUSE_NOT_BEGUN if is_ready() else REFUSE_NOT_READY)
	if not StoryTriggerData.EVENT_KINDS.has(kind):
		return StoryOutcome.refused(REFUSE_NOT_AN_EVENT)
	var outcome := StoryOutcome.new()
	var beat := current_beat()
	if beat != null and not beat.terminal and beat.trigger.kind == kind \
			and (beat.trigger.subject_id == &"" or beat.trigger.subject_id == subject_id):
		_complete(beat, outcome)
	return _settled(outcome)


## Another owner's truth changed (something became known). Ask the current beat again.
func refresh() -> StoryOutcome:
	if not has_begun():
		return StoryOutcome.refused(REFUSE_NOT_BEGUN if is_ready() else REFUSE_NOT_READY)
	return _settled(StoryOutcome.new())


# --- Settling ------------------------------------------------------------------

## Complete every beat whose STATE trigger already holds, in order, and fill in the outcome.
## Bounded by the number of beats: the catalog is acyclic, so each pass moves forward.
func _settled(outcome: StoryOutcome) -> StoryOutcome:
	for _pass in _catalog.all_beats().size() + 1:
		var beat := current_beat()
		if beat == null or beat.terminal or beat.trigger.is_event() \
				or not _trigger_holds(beat.trigger):
			break
		_complete(beat, outcome)
	outcome.ok = true
	outcome.beat_id = _state.beat_id
	return outcome


func _trigger_holds(trigger: StoryTriggerData) -> bool:
	match trigger.kind:
		StoryTriggerData.Kind.FLAG:
			return flag_at_least(trigger.subject_id, trigger.count)
		StoryTriggerData.Kind.MET:
			var seen := 0
			for who in trigger.subjects:
				if _state.has_met(who):
					seen += 1
			return seen >= trigger.count
		StoryTriggerData.Kind.CHOICE:
			return _state.has_chosen(trigger.subject_id)
		StoryTriggerData.Kind.KNOWS:
			return _knows(trigger.subject_id)
	return false


func _complete(beat: StoryBeatData, outcome: StoryOutcome) -> void:
	var next: StoryBeatData = null
	for branch in beat.branches:
		var taken := true
		for condition in branch.conditions:
			if not condition_holds(condition):
				taken = false
				break
		if taken:
			next = _catalog.beat(branch.next_beat_id)
			break
	if next == null:
		push_error("[story] beat '%s' completed with no way on" % beat.id)
		return
	_state.completed_beats.append(beat.id)
	outcome.completed.append(beat.id)
	var entered := _catalog.chapter_of(next.id)
	if entered.id != _state.chapter_id:
		_state.completed_chapters.append(_state.chapter_id)
		_state.chapter_id = entered.id
		outcome.chapter_changed = true
	_state.beat_id = next.id


func _knows(knowledge_id: StringName) -> bool:
	return _owners.knows.is_valid() and bool(_owners.knows.call(knowledge_id))


# --- Persistence boundary ------------------------------------------------------

func to_dict() -> Dictionary:
	return _state.to_dict() if is_ready() else {}


## Replace the story record with `data`. Atomic: the payload is validated whole against the
## catalogs AND the flags the player's record holds are checked against the declarations; if
## either is wrong nothing changes. Flags are not in `data` — they come with the character —
## so this is also where a story record and a character record are shown to agree.
func load_state(data: Dictionary) -> bool:
	if not is_ready():
		return false
	var staged := StoryState.new()
	if not staged.from_dict(data, _catalog, _origins):
		return false
	var problems := flag_errors()
	if not problems.is_empty():
		push_error("[story] load_state: the character's story flags are not valid: %s"
			% str(problems))
		return false
	_state.origin_id = staged.origin_id
	_state.chapter_id = staged.chapter_id
	_state.beat_id = staged.beat_id
	_state.completed_chapters = staged.completed_chapters
	_state.completed_beats = staged.completed_beats
	_state.choices = staged.choices
	_state.met = staged.met
	return true


# --- Content the other owners must be able to answer ---------------------------

## What the catalogs ask of OTHER owners that they cannot give. Structural errors are the
## catalogs' own `validation_errors`; this is the cross-owner half. Each seam is optional (an
## invalid Callable skips that check): `has_text(key)`, `has_knowledge(id)`,
## `resolve_character(instance_id) -> CharacterState`, `has_dimension(dimension)`,
## `has_item(item_id)`, `has_map(map_id)`, `has_scene(scene_id)`.
func content_errors(has_text: Callable = Callable(), has_knowledge: Callable = Callable(),
		resolve_character: Callable = Callable(), has_dimension: Callable = Callable(),
		has_item: Callable = Callable(), has_map: Callable = Callable(),
		has_scene: Callable = Callable()) -> Array[String]:
	var errors: Array[String] = []
	if not is_ready():
		errors.append("the story service is not ready")
		return errors
	if has_text.is_valid():
		var keys := _catalog.text_keys()
		for origin_entry in _origins.entries:
			keys.append_array(origin_entry.text_keys())
		for key in keys:
			if not bool(has_text.call(key)):
				errors.append("text '%s' has no translation in every language" % key)
	for beat in _catalog.all_beats():
		if beat.entry_scene_id != &"":
			_ask(errors, has_scene, beat.entry_scene_id,
				"%s: '%s' is not a story scene" % [beat.id, "%s"])
		if beat.trigger != null:
			errors.append_array(_trigger_content_errors(beat, has_knowledge,
				resolve_character, has_map, has_scene))
		for branch in beat.branches:
			for condition in branch.conditions:
				if condition.kind == StoryConditionData.Kind.KNOWS:
					_ask(errors, has_knowledge, condition.knowledge_id,
						"%s branch: knowledge '%s' is not in the catalog" % [beat.id, "%s"])
				elif condition.kind == StoryConditionData.Kind.ORIGIN \
						and not _origins.has(condition.origin_id):
					errors.append("%s branch: '%s' is not an Origin"
						% [beat.id, condition.origin_id])
	for asked in _catalog.choices:
		for answer in asked.options:
			for consequence in answer.consequences:
				var where := "%s/%s" % [asked.id, answer.id]
				if consequence.kind == StoryConsequenceData.Kind.GRANT_KNOWLEDGE:
					_ask(errors, has_knowledge, consequence.knowledge_id,
						"%s: knowledge '%s' is not in the catalog" % [where, "%s"])
				elif consequence.kind == StoryConsequenceData.Kind.REGARD:
					_ask_character(errors, resolve_character, consequence.character_id, where)
					_ask(errors, has_dimension, consequence.dimension,
						"%s: '%s' is not a relationship dimension" % [where, "%s"])
	for origin_entry in _origins.entries:
		_ask(errors, has_scene, origin_entry.vignette_scene_id,
			"%s: vignette '%s' is not a story scene" % [origin_entry.id, "%s"])
		for grant in origin_entry.grants:
			var where := String(origin_entry.id)
			match grant.kind:
				OriginGrantData.Kind.ITEM:
					_ask(errors, has_item, grant.item_id,
						"%s: item '%s' is not in the item catalog" % [where, "%s"])
				OriginGrantData.Kind.KNOWLEDGE:
					_ask(errors, has_knowledge, grant.knowledge_id,
						"%s: knowledge '%s' is not in the catalog" % [where, "%s"])
				OriginGrantData.Kind.REGARD:
					_ask_character(errors, resolve_character, grant.character_id, where)
					_ask(errors, has_dimension, grant.dimension,
						"%s: '%s' is not a relationship dimension" % [where, "%s"])
	return errors


func _trigger_content_errors(beat: StoryBeatData, has_knowledge: Callable,
		resolve_character: Callable, has_map: Callable, has_scene: Callable) -> Array[String]:
	var errors: Array[String] = []
	var trigger := beat.trigger
	match trigger.kind:
		StoryTriggerData.Kind.KNOWS:
			_ask(errors, has_knowledge, trigger.subject_id,
				"%s trigger: knowledge '%s' is not in the catalog" % [beat.id, "%s"])
		StoryTriggerData.Kind.ARRIVED:
			_ask(errors, has_map, trigger.subject_id,
				"%s trigger: '%s' is not a map" % [beat.id, "%s"])
		StoryTriggerData.Kind.SCENE_ENDED:
			if trigger.subject_id != &"":
				_ask(errors, has_scene, trigger.subject_id,
					"%s trigger: '%s' is not a story scene" % [beat.id, "%s"])
		StoryTriggerData.Kind.MET:
			for who in trigger.subjects:
				_ask_character(errors, resolve_character, who, "%s trigger" % beat.id)
	return errors


static func _ask(errors: Array[String], seam: Callable, id: StringName, message: String) -> void:
	if seam.is_valid() and not bool(seam.call(id)):
		errors.append(message % id)


static func _ask_character(errors: Array[String], resolve_character: Callable,
		who: StringName, where: String) -> void:
	if resolve_character.is_valid() and not (resolve_character.call(who) is CharacterState):
		errors.append("%s: '%s' is not a registered character" % [where, who])
