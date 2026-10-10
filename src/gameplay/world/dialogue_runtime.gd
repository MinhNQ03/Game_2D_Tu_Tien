extends Node
class_name DialogueRuntime
## DialogueRuntime — Aetheria gameplay (the conversation the player is in, Phase 18, D-066).
##
## Per-session node under `Main/Systems` (no autoload). It owns exactly one thing: the CURSOR
## of the open conversation — which dialogue, which line, with whom. That is runtime state and
## is never serialized; a load resumes in the world, not mid-sentence. It owns no flag, no
## knowledge and no regard:
##
##   * WHO can be spoken to, and whether they are in reach, is `NpcRuntime`'s (`engage`,
##     `reach_refusal`) — asked when a talk starts and again on every answer;
##   * which answers are offered and what submitting one comes to is `DialogueService`'s;
##   * a regard move lands in the relationship graph through `RelationshipService`, a grant
##     goes through `KnowledgeRuntime.grant` (so it is announced like any other learning), and
##     "trade" is handed to `NpcRuntime.open_shop_of` AFTER this conversation has closed.
##
## Someone with no authored conversation is not this node's business: `talk` passes them to
## `NpcRuntime.interact`, whose behaviour for them is unchanged (a greeting, or their own shop).
##
## FAIL CLOSED. An invalid catalog, or content naming something its owner does not have, stops
## the session from starting. Every refusal emits a reason key and changes nothing.
##
## No `_process`: nothing here runs unless the player talks, answers or leaves.

signal dialogue_opened(dialogue_id: StringName, speaker_id: StringName)
signal dialogue_closed(dialogue_id: StringName, reason: StringName)
## An answer (or a "continue") was accepted. `outcome` holds ids and numbers only.
signal choice_made(outcome: DialogueOutcome)
signal choice_refused(reason_key: StringName)
## The open conversation's view changed (opened, a new line, closed).
signal view_changed()

const CATALOG_PATH := "res://data/dialogue/dialogue_catalog.tres"

## Why a conversation closed.
const REASON_ENDED := &"ended"          # its last line was acknowledged / a choice ended it
const REASON_LEFT := &"left"            # the player walked away from it (Esc, a fight)
const REASON_HANDOFF := &"handoff"      # it handed over to another service (the shop)
const REASON_MAP := &"map"              # the map it was held in is going away
const REASON_OUT_OF_REACH := &"reach"   # the speaker is no longer in reach
const REASON_SESSION := &"session"      # the session ended

var _world: Node = null
var _npcs: NpcRuntime = null
var _knowledge: KnowledgeRuntime = null
var _service: DialogueService = null
var _session_active: bool = false

var _dialogue: DialogueData = null
var _node_id: StringName = &""
var _line_serial: int = 0


## Start the session. Builds into locals and commits only when every check passed: the catalog
## is structurally valid AND everything it names exists in its owner (knowledge ids,
## relationship dimensions and ranges, a shop for every "trade", a translation of every line
## in every language). `catalog` is the content seam (null = the shipped one).
func start_session(world: Node, npcs: NpcRuntime, knowledge: KnowledgeRuntime,
		relationship: RelationshipRuntime, catalog: DialogueCatalogData = null) -> bool:
	if _session_active:
		push_error("[dialogue-rt] start_session while a session is active")
		return false
	if world == null or npcs == null or not npcs.is_session_active() \
			or knowledge == null or not knowledge.is_session_active() \
			or relationship == null or not relationship.is_session_active():
		push_error("[dialogue-rt] session NOT started: a dependency is missing or inactive")
		return false
	if catalog == null:
		catalog = load(CATALOG_PATH) as DialogueCatalogData
	if catalog == null:
		push_error("[dialogue-rt] session NOT started: %s did not load" % CATALOG_PATH)
		return false
	var service := DialogueService.new(catalog, knowledge.get_service(),
		relationship.get_service(), relationship.get_config())
	if not service.is_ready():
		push_error("[dialogue-rt] session NOT started: the DialogueService refused its catalog")
		return false
	var shops := npcs.get_service().catalog()
	var errors := service.content_errors(_translation_check(),
		func(character_id: StringName) -> bool: return shops.shop_of_keeper(character_id) != null)
	if not errors.is_empty():
		push_error("[dialogue-rt] session NOT started: %s" % str(errors))
		return false
	_world = world
	_npcs = npcs
	_knowledge = knowledge
	_service = service
	_dialogue = null
	_node_id = &""
	_session_active = true
	if _world.has_signal("active_map_leaving"):
		_world.connect("active_map_leaving", _on_map_leaving)
	return true


## End the session: close the conversation, drop every connection. Idempotent.
func end_session() -> void:
	if _session_active:
		_close(REASON_SESSION)
	if _world != null and is_instance_valid(_world) and _world.has_signal("active_map_leaving") \
			and _world.is_connected("active_map_leaving", _on_map_leaving):
		_world.disconnect("active_map_leaving", _on_map_leaving)
	_world = null
	_npcs = null
	_knowledge = null
	_service = null
	_dialogue = null
	_node_id = &""
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_service() -> DialogueService:
	return _service


func is_open() -> bool:
	return _dialogue != null


func open_dialogue_id() -> StringName:
	return _dialogue.id if _dialogue != null else &""


func current_node_id() -> StringName:
	return _node_id


# --- Talking -------------------------------------------------------------------

## The player talks to `character_id`. `NpcRuntime` decides whether they can be addressed (in
## this map, bound, in reach) and turns them to the player. With an authored conversation it
## opens at its first line; without one, `NpcRuntime`'s own behaviour stands. Returns &"" on
## success, else the refusal key. A talk while one is already open changes nothing.
func talk(character_id: StringName) -> StringName:
	if not _session_active:
		return DialogueService.REFUSE_NOT_READY
	if _dialogue != null:
		return &""
	var dialogue := _service.catalog().dialogue_of_speaker(character_id)
	if dialogue == null:
		return _npcs.interact(character_id)
	var refusal := _npcs.engage(character_id)
	if refusal != &"":
		return refusal
	_dialogue = dialogue
	dialogue_opened.emit(dialogue.id, dialogue.speaker_id)
	_enter(dialogue.start_node_id)
	return &""


## Acknowledge a line that offers no choices: the next line, or the end.
func advance() -> DialogueOutcome:
	if _dialogue == null:
		return _refuse(DialogueService.REFUSE_NOT_READY)
	var outcome := _service.advance(_dialogue.id, _node_id)
	if not outcome.ok:
		return _refuse(outcome.reason)
	return _follow(outcome)


## Submit `choice_id` as the answer to line `node_id`. An answer to a line that is not the
## current one — a stale panel, a second press — is refused; so is one whose speaker has gone
## out of reach (which also closes the conversation). Everything else is `DialogueService`'s
## decision, re-validated there.
func choose(node_id: StringName, choice_id: StringName) -> DialogueOutcome:
	if _dialogue == null:
		return _refuse(DialogueService.REFUSE_NOT_READY)
	if node_id != _node_id:
		return _refuse(DialogueService.REFUSE_CHOICE_GONE)
	var reach := _npcs.reach_refusal(_dialogue.speaker_id)
	if reach != &"":
		_close(REASON_OUT_OF_REACH)
		return _refuse(reach)
	var listener := _listener_id()
	var outcome := _service.choose(_dialogue.id, _node_id, choice_id, listener,
		_knowledge.grant)
	if not outcome.ok:
		return _refuse(outcome.reason)
	return _follow(outcome)


## The player leaves the conversation. Safe (and silent) when none is open.
func leave() -> void:
	_close(REASON_LEFT)


func _follow(outcome: DialogueOutcome) -> DialogueOutcome:
	choice_made.emit(outcome)
	if outcome.action == DialogueService.ACTION_OPEN_SHOP:
		# Close FIRST: the shop must never open behind a conversation that still holds input.
		var keeper := _dialogue.speaker_id
		_close(REASON_HANDOFF)
		_npcs.open_shop_of(keeper)
	elif outcome.ended:
		_close(REASON_ENDED)
	else:
		_enter(outcome.next_node_id)
	return outcome


func _enter(node_id: StringName) -> void:
	_node_id = node_id
	_line_serial += 1
	var line := _dialogue.node(node_id)
	if line != null and line.gesture != DialogueNodeData.GESTURE_NONE:
		_npcs.gesture(_dialogue.speaker_id, line.gesture)
	view_changed.emit()


func _close(reason: StringName) -> void:
	if _dialogue == null:
		return
	var dialogue_id := _dialogue.id
	_dialogue = null
	_node_id = &""
	dialogue_closed.emit(dialogue_id, reason)
	view_changed.emit()


func _refuse(reason: StringName) -> DialogueOutcome:
	choice_refused.emit(reason)
	return DialogueOutcome.refused(reason, open_dialogue_id(), _node_id)


func _on_map_leaving() -> void:
	_close(REASON_MAP)


# --- View ---------------------------------------------------------------------

## The read-only snapshot the dialogue panel shows (closed when no conversation is open).
func build_view() -> DialogueView:
	var view := DialogueView.make_closed()
	var line := _dialogue.node(_node_id) if _dialogue != null else null
	if line == null:
		return view
	view.open = true
	view.dialogue_id = _dialogue.id
	view.node_id = _node_id
	view.line_serial = _line_serial
	view.speaker_id = _dialogue.speaker_id
	var speaker := _speaker_state()
	if speaker != null:
		view.speaker_name_key = speaker.name_key
		view.speaker_title_key = speaker.title_key
	var template := _npcs.template_of(_dialogue.speaker_id)
	view.portrait_path = template.portrait_ref if template != null else ""
	view.mood = line.mood
	view.gestures = line.gesture != DialogueNodeData.GESTURE_NONE
	view.text_key = line.text_key
	for option in _service.eligible_choices(_dialogue.id, _node_id, _listener_id()):
		view.choices.append({"id": option.id, "text_key": option.text_key})
	view.continues = line.choices.is_empty() and line.next_node_id != &""
	return view


func _speaker_state() -> CharacterState:
	var registry: CharacterRegistry = _world.call("get_character_registry") \
		if _world != null and is_instance_valid(_world) else null
	return registry.get_character(_dialogue.speaker_id) if registry != null else null


func _listener_id() -> StringName:
	var character: CharacterState = _world.call("get_player_character") \
		if _world != null and is_instance_valid(_world) else null
	return character.instance_id if character != null else &""


## `key -> bool`: translated in every language. Asked of the `Localization` autoload; a node
## outside the tree (a unit test with no autoloads) has nobody to ask and skips the check.
func _translation_check() -> Callable:
	var loc := get_node_or_null("/root/Localization") if is_inside_tree() else null
	if loc == null or not loc.has_method("is_translated"):
		return Callable()
	return func(key: StringName) -> bool: return bool(loc.call("is_translated", String(key)))
