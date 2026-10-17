extends Node
class_name StoryRuntime
## StoryRuntime — Aetheria gameplay (the session's story, Phase 20, D-072).
##
## Per-session node under `Main/Systems` (no autoload). It owns the session's story record
## through the ONE `StoryService`, hands that service the seams to what it does not own
## (knowledge, regard, the bag), and turns what happens in the session into the FACTS the
## service understands: the player arrived somewhere, a scene ended, something became known.
##
## IT DECIDES NOTHING THE SERVICE DID NOT. Which beat is current, whether a choice may be
## answered, what a flag holds — all asked of the service. This node routes and announces.
##
## A STORY SCENE IS PRESENTATION. A beat that is entered with a scene has ALREADY been
## committed when the scene starts, so advancing, skipping or interrupting a scene can change
## nothing but what is on screen. Which step is showing is runtime-only and is not saved.
##
## FAIL CLOSED. An invalid catalog, content naming something its owner does not have, or an
## Origin whose starting kit cannot be handed over, stops the session from starting — and the
## caller discards the whole session, so a half-applied start cannot be played.
##
## No `_process`: nothing here runs unless the session announces something or someone asks.

## Anything a story view shows changed (the objective, the chapter).
signal view_changed()
## A scene started, moved to its next step, or ended.
signal scene_changed()
## Announced AFTER the record was committed.
signal beat_completed(beat_id: StringName)
signal chapter_entered(chapter_id: StringName)
signal choice_recorded(choice_id: StringName, option_id: StringName)

const CATALOG_PATH := "res://data/story/story_catalog.tres"
const ORIGINS_PATH := "res://data/story/origin_catalog.tres"
const SCENES_PATH := "res://data/story/story_scene_catalog.tres"
## Where an ambience a beat names must exist (the profile presentation applies — D-073 §3).
## Only its EXISTENCE is asked here, as for a map or a scene: the story never loads it.
const AMBIENCE_PATH := "res://data/ambience/ambience_%s.tres"
## The cause recorded on a relationship edge the story moves.
const REGARD_CAUSE := &"story"

var _world: Node = null
var _knowledge: KnowledgeRuntime = null
var _relationship: RelationshipRuntime = null
var _inventory: InventoryRuntime = null
var _service: StoryService = null
var _scenes: StorySceneCatalogData = null
var _session_active: bool = false
## What the purpose line said at the last `view_changed` (see `_apply`).
var _shown_objective_key: StringName = &""

## The scene on screen and its step, or null. Runtime-only.
var _scene: StorySceneData = null
var _step: int = 0
var _conversation_open: bool = false
var _scene_waiting: bool = false


## Start the session as `origin_id`. Builds into locals and commits only when every check
## passed and the run has begun. The catalogs are the content seams (null = the shipped ones).
func start_session(world: Node, knowledge: KnowledgeRuntime,
		relationship: RelationshipRuntime, inventory: InventoryRuntime,
		origin_id: StringName, catalog: StoryCatalogData = null,
		origins: OriginCatalogData = null, scenes: StorySceneCatalogData = null) -> bool:
	if _session_active:
		push_error("[story-rt] start_session while a session is active")
		return false
	if world == null or not world.has_method("get_player_character") \
			or not world.has_method("get_character_registry") \
			or not world.has_method("get_map_lookup") \
			or knowledge == null or not knowledge.is_session_active() \
			or relationship == null or not relationship.is_session_active() \
			or inventory == null or not inventory.is_session_active():
		push_error("[story-rt] session NOT started: a dependency is missing or inactive")
		return false
	if catalog == null:
		catalog = load(CATALOG_PATH) as StoryCatalogData
	if origins == null:
		origins = load(ORIGINS_PATH) as OriginCatalogData
	if scenes == null:
		scenes = load(SCENES_PATH) as StorySceneCatalogData
	if catalog == null or origins == null or scenes == null:
		push_error("[story-rt] session NOT started: a story catalog did not load")
		return false
	if not scenes.is_valid():
		push_error("[story-rt] session NOT started: %s" % str(scenes.validation_errors()))
		return false
	var player: CharacterState = world.call("get_player_character")
	var registry: CharacterRegistry = world.call("get_character_registry")
	if player == null or registry == null:
		push_error("[story-rt] session NOT started: the world has no player or no registry")
		return false
	# Commit the fields the owner seams read BEFORE the service can call them.
	_world = world
	_knowledge = knowledge
	_relationship = relationship
	_inventory = inventory
	var service := StoryService.new(catalog, origins, StoryState.new(), player, _owners())
	var errors: Array[String] = []
	if not service.is_ready():
		errors.append("the StoryService refused its catalogs")
	else:
		errors = _content_errors(service, scenes, registry)
	if errors.is_empty():
		var begun := service.begin(origin_id)
		if not begun.ok:
			errors.append("the run could not begin as '%s': %s" % [origin_id, begun.reason])
	if not errors.is_empty():
		push_error("[story-rt] session NOT started: %s" % str(errors))
		_clear()
		return false
	_service = service
	_scenes = scenes
	_session_active = true
	_knowledge.knowledge_gained.connect(_on_knowledge_gained)
	if _world.has_signal("active_map_ready"):
		_world.connect("active_map_ready", _on_map_ready)
	_enter_scene_of_current_beat()
	return true


## End the session: stop listening, then drop everything. Idempotent.
func end_session() -> void:
	if _knowledge != null and is_instance_valid(_knowledge) \
			and _knowledge.knowledge_gained.is_connected(_on_knowledge_gained):
		_knowledge.knowledge_gained.disconnect(_on_knowledge_gained)
	if _world != null and is_instance_valid(_world) and _world.has_signal("active_map_ready") \
			and _world.is_connected("active_map_ready", _on_map_ready):
		_world.disconnect("active_map_ready", _on_map_ready)
	_clear()


func _clear() -> void:
	_conversation_open = false
	_scene_waiting = false
	_world = null
	_knowledge = null
	_relationship = null
	_inventory = null
	_service = null
	_scenes = null
	_scene = null
	_step = 0
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_service() -> StoryService:
	return _service


# --- The seams to what the story does not own ---------------------------------

func _owners() -> StoryOwners:
	var owners := StoryOwners.new()
	owners.knows = _knows
	owners.can_teach = _can_teach
	owners.teach_all = _teach_all
	owners.can_move_regard = _can_move_regard
	owners.move_regard = _move_regard
	owners.give_all = _give_all
	owners.take_all = _take_all
	return owners


func _knows(knowledge_id: StringName) -> bool:
	return _knowledge != null and _knowledge.get_service().knows(knowledge_id)


## The Knowledge Core's own answer to "could you teach this?" (prepare — D-073 §2).
func _can_teach(knowledge_id: StringName) -> bool:
	return _knowledge != null and _knowledge.is_session_active() \
		and _knowledge.get_service().can_grant(knowledge_id)


## Everything an answer or an Origin teaches, as the Knowledge owner's ONE atomic batch.
func _teach_all(knowledge_ids: Array[StringName], source_id: StringName) -> bool:
	return _knowledge != null and _knowledge.is_session_active() \
		and _knowledge.grant_all(knowledge_ids, source_id)


func _player_id() -> StringName:
	var player: CharacterState = _world.call("get_player_character") \
		if _world != null and is_instance_valid(_world) else null
	return player.instance_id if player != null else &""


## The relationship graph's own answer to "could you move this regard?" (prepare).
func _can_move_regard(character_id: StringName, dimension: StringName, delta: int) -> bool:
	return _relationship != null and _relationship.is_session_active() \
		and RegardRules.can_move(_relationship.get_service(), _relationship.get_config(),
			character_id, _player_id(), dimension, delta)


## A character's regard for the PLAYER, moved through the relationship graph's service.
## Returns the graph's own answer (`RegardRules.move`): `{ ok, old_value, new_value }`.
func _move_regard(character_id: StringName, dimension: StringName, delta: int) -> Dictionary:
	if _relationship == null or not _relationship.is_session_active():
		return {"ok": false, "old_value": 0, "new_value": 0}
	return RegardRules.move(_relationship.get_service(), _relationship.get_config(),
		character_id, _player_id(), dimension, delta, REGARD_CAUSE)


## ALL of `items` into the bag, or none (the bag's own all-or-nothing exchange).
func _give_all(items: Dictionary) -> bool:
	return _inventory != null and _inventory.exchange({}, items)


## The same exchange the other way (to undo `_give_all` when a later owner broke its word).
func _take_all(items: Dictionary) -> bool:
	return _inventory != null and _inventory.exchange(items, {})


func _content_errors(service: StoryService, scenes: StorySceneCatalogData,
		registry: CharacterRegistry) -> Array[String]:
	var maps: Dictionary = _world.call("get_map_lookup")
	var items := _inventory.get_catalog()
	var knowledge := _knowledge.get_catalog()
	var graph := _relationship.get_service()
	var has_text := _translation_check()
	var errors := service.content_errors(has_text,
		func(id: StringName) -> bool: return knowledge.has(id),
		registry.resolver(),
		func(dimension: StringName) -> bool: return graph.has_dimension(dimension),
		func(item_id: StringName) -> bool: return items.entry(item_id) != null,
		func(map_id: StringName) -> bool: return maps.has(map_id),
		func(scene_id: StringName) -> bool: return scenes.has(scene_id),
		func(ambience: StringName) -> bool:
			return ResourceLoader.exists(AMBIENCE_PATH % ambience))
	for scene in scenes.entries:
		if has_text.is_valid():
			for key in scene.text_keys():
				if not bool(has_text.call(key)):
					errors.append("%s: text '%s' has no translation in every language"
						% [scene.id, key])
		for who in scene.speaker_ids():  # (a hint's action is checked below)
			if registry.get_character(who) == null:
				errors.append("%s: speaker '%s' is not a registered character"
					% [scene.id, who])
	for beat in service.catalog().all_beats():
		if beat.completion_hint_action != &"" \
				and not InputMap.has_action(beat.completion_hint_action):
			errors.append("%s: hint action '%s' is not an input action"
				% [beat.id, beat.completion_hint_action])
	return errors


# --- What the session tells the story -----------------------------------------

func _on_map_ready() -> void:
	if not _session_active:
		return
	var map_id: StringName = _world.call("get_current_map_id")
	_apply(_service.note(StoryTriggerData.Kind.ARRIVED, map_id))


func _on_knowledge_gained(_knowledge_id: StringName, _source_id: StringName) -> void:
	if _session_active:
		_apply(_service.refresh())


## The player spoke to `character_id` (asked by the conversation when it opens).
func meet(character_id: StringName) -> StoryOutcome:
	return _apply(_service.meet(character_id)) if _session_active \
		else StoryOutcome.refused(StoryService.REFUSE_NOT_READY)


## Answer a story choice (asked by the conversation, or by the session for a choice made
## with the player's feet). The service is the whole transaction.
func choose(choice_id: StringName, option_id: StringName) -> StoryOutcome:
	if not _session_active:
		return StoryOutcome.refused(StoryService.REFUSE_NOT_READY)
	var outcome := _service.choose(choice_id, option_id)
	if outcome.ok:
		choice_recorded.emit(choice_id, option_id)
	return _apply(outcome)


func set_flag(flag_id: StringName, value: int = 1) -> StoryOutcome:
	return _apply(_service.set_flag(flag_id, value)) if _session_active \
		else StoryOutcome.refused(StoryService.REFUSE_NOT_READY)


## A cultivation session yielded (told by the session's wiring).
func note_cultivated() -> StoryOutcome:
	return _apply(_service.note(StoryTriggerData.Kind.CULTIVATED)) if _session_active \
		else StoryOutcome.refused(StoryService.REFUSE_NOT_READY)


## Announce what a call to the service did, AFTER it was committed, and show the scene the
## story has now arrived at. Returns the outcome unchanged.
##
## The PURPOSE LINE is derived (experience upgrade): an Origin's personal step can be met by a
## piece of knowledge or a flag while the beat stays where it is. So a call that moved no beat
## still announces a new view when what the line would say has changed — and only then.
func _apply(outcome: StoryOutcome) -> StoryOutcome:
	if outcome == null or not outcome.ok:
		return outcome
	if not outcome.moved():
		if _service.objective_key() != _shown_objective_key:
			_shown_objective_key = _service.objective_key()
			view_changed.emit()
		return outcome
	_shown_objective_key = _service.objective_key()
	for beat_id in outcome.completed:
		beat_completed.emit(beat_id)
	if outcome.chapter_changed:
		chapter_entered.emit(_service.state().chapter_id)
	_enter_scene_of_current_beat()
	view_changed.emit()
	return outcome


# --- Scenes (presentation; they change nothing) -------------------------------

## A conversation opened or closed (told by `DialogueRuntime`). A scene that becomes due
## while someone is still speaking waits for them to finish: two surfaces never hold the
## player at once, and nothing is skipped.
func set_conversation_open(open: bool) -> void:
	_conversation_open = open
	if not open and _scene_waiting and _session_active:
		_enter_scene_of_current_beat()


func _enter_scene_of_current_beat() -> void:
	if _conversation_open:
		_scene_waiting = true
		return
	_scene_waiting = false
	var scene := _scenes.entry(_service.entry_scene_id())
	if scene == null:
		return
	_scene = scene
	_step = 0
	scene_changed.emit()


func is_scene_playing() -> bool:
	return _scene != null


## Show the next step, or end the scene after its last one.
func advance_scene() -> void:
	if _scene == null:
		return
	if _step < _scene.steps.size() - 1:
		_step += 1
		scene_changed.emit()
	else:
		_end_scene()


## Stop showing the scene now. Exactly what reaching its end does: nothing was waiting on the
## remaining steps, because a scene changes nothing.
func skip_scene() -> void:
	if _scene != null:
		_end_scene()


func _end_scene() -> void:
	var ended := _scene.id
	_scene = null
	_step = 0
	scene_changed.emit()
	_apply(_service.note(StoryTriggerData.Kind.SCENE_ENDED, ended))


## How the maps are lit while the current beat lasts ("" = as authored). Derived each time.
func ambience_id() -> StringName:
	return _service.ambience_id() if _session_active else &""


## The step now on screen, or null when no scene is playing.
func build_scene_view() -> StorySceneView:
	if _scene == null:
		return null
	var step := _scene.steps[_step]
	var view := StorySceneView.new()
	view.scene_id = _scene.id
	view.step_index = _step
	view.step_count = _scene.steps.size()
	view.elsewhere = _scene.elsewhere
	view.backdrop_ref = _scene.backdrop_ref
	view.kind = step.kind
	view.text_key = step.text_key
	view.sub_key = step.sub_key
	if step.speaker_id != &"":
		var registry: CharacterRegistry = _world.call("get_character_registry")
		var speaker := registry.get_character(step.speaker_id) if registry != null else null
		if speaker != null:
			view.speaker_name_key = speaker.name_key
	return view


func build_view() -> StoryView:
	var view := StoryView.new()
	if not _session_active:
		return view
	view.objective_key = _service.objective_key()
	var chapter := _service.current_chapter()
	view.chapter_title_key = chapter.title_key if chapter != null else &""
	var origin := _service.origin()
	if origin != null:
		view.origin_name_key = origin.name_key
		view.origin_goal_key = origin.goal_key
		view.origin_problem_key = origin.problem_key
		view.origin_edge_key = origin.edge_key
		view.origin_cost_key = origin.cost_key
		view.origin_why_here_key = origin.why_here_key
	view.personal_objective_key = _service.personal_objective_key()
	var state := _service.state()
	for beat_id in state.completed_beats:
		var beat := _service.catalog().beat(beat_id)
		if beat != null and beat.record_key != &"":
			view.records.append(beat.record_key)
	for entry: Dictionary in state.choices:
		var asked := _service.catalog().choice(StringName(String(entry["choice_id"])))
		var answer := asked.option(StringName(String(entry["option_id"]))) \
			if asked != null else null
		if answer != null:
			view.decisions.append(answer.record_key)
	view.met = state.met.duplicate()
	view.noticed = _service.noticed_keys()
	for character_id in state.met:
		view.decisions_about[character_id] = _service.decisions_about(character_id)
	return view


## `key -> bool`: translated in every language. A node outside the tree (a unit test with no
## autoloads) has nobody to ask and skips the check.
func _translation_check() -> Callable:
	var loc := get_node_or_null("/root/Localization") if is_inside_tree() else null
	if loc == null or not loc.has_method("is_translated"):
		return Callable()
	return func(key: StringName) -> bool: return bool(loc.call("is_translated", String(key)))


# --- Persistence boundary -------------------------------------------------------

func to_dict() -> Dictionary:
	return _service.to_dict() if _service != null else {}


## Restore the story record. Atomic: a rejected payload changes nothing. The scene on screen
## is not part of it.
func from_dict(data: Dictionary) -> bool:
	if not _session_active or not _service.load_state(data):
		return false
	_scene = null
	_step = 0
	scene_changed.emit()
	view_changed.emit()
	return true
