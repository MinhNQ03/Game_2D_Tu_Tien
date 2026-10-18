extends RefCounted
class_name DialogueOffers
## DialogueOffers — which of a line's authored answers can ever be on screen TOGETHER (UI-01).
##
## The dialogue box is sized by what it shows, so a test or a capture that wants to see every
## answer a line can show, and the tallest box it can produce, needs every set of its answers
## some state of the world offers at once — not every answer authored on it (the scout's hub
## authors seven and never shows more than five). Shared by the dialogue layout tests and
## `tools/capture_ui.gd`; nothing in the game depends on it.
##
## Whether an answer is offered is `DialogueService`'s own rule (`condition_met`), asked over a
## STAGED world: every phase of every quest the line's answers name, knowing and not knowing
## every thing they name, every value of every flag up to the largest asked, and each Origin
## they name or another. Regard is NOT staged: a regard condition is assumed met, which can only
## add answers to a set, never hide one.

const CATALOG := "res://data/dialogue/dialogue_catalog.tres"
const RELATIONSHIP_CONFIG := "res://data/relationship/relationship_config.tres"


## Every MAXIMAL set of `line`'s answers some staged world offers together, in authored order:
## no set returned is part of another, and every answer that can be offered at all is in one.
static func sets(line: DialogueNodeData) -> Array:
	var world := StagedWorld.new()
	var config := load(RELATIONSHIP_CONFIG) as RelationshipConfigData
	var service := DialogueService.new(load(CATALOG) as DialogueCatalogData,
		StagedKnowledge.new(world), RelationshipService.new(RelationshipStore.new(config), config),
		config, StagedQuests.new(world), StagedStory.new(world))
	if not service.is_ready():
		push_error("[dialogue-offers] the staged dialogue service is not ready")
		return []
	var quests: Array[StringName] = []
	var facts: Array[StringName] = []
	var flag_top: Dictionary = {}
	var origins: Array[StringName] = []
	for option in line.choices:
		for condition in option.conditions:
			if condition.kind == DialogueConditionData.Kind.QUEST_PHASE \
					and not quests.has(condition.quest_id):
				quests.append(condition.quest_id)
			elif condition.kind == DialogueConditionData.Kind.KNOWS \
					and not facts.has(condition.knowledge_id):
				facts.append(condition.knowledge_id)
			elif condition.kind == DialogueConditionData.Kind.FLAG:
				flag_top[condition.flag_id] = maxi(int(flag_top.get(condition.flag_id, 0)),
					condition.value)
			elif condition.kind == DialogueConditionData.Kind.ORIGIN \
					and not origins.has(condition.origin_id):
				origins.append(condition.origin_id)
	var phases := QuestData.Phase.size()
	var states := int(pow(phases, quests.size())) * int(pow(2, facts.size()))
	for flag_id: StringName in flag_top:
		states *= int(flag_top[flag_id]) + 1
	states *= origins.size() + 1  # a run has ONE Origin: one of these, or another
	var found: Dictionary = {}  # the offered ids, joined -> the offered answers
	for state in states:
		var rest := state
		world.phase_of.clear()
		world.known.clear()
		world.flag_at.clear()
		for quest_id in quests:
			world.phase_of[quest_id] = rest % phases
			rest /= phases
		for fact in facts:
			world.known[fact] = rest % 2 == 1
			rest /= 2
		for flag_id: StringName in flag_top:
			var span := int(flag_top[flag_id]) + 1
			world.flag_at[flag_id] = rest % span
			rest /= span
		world.origin = origins[rest] if rest < origins.size() else &""
		var offered: Array[DialogueChoiceData] = []
		var ids: PackedStringArray = []
		for option in line.choices:
			var met := true
			for condition in option.conditions:
				if condition.kind == DialogueConditionData.Kind.RELATIONSHIP_AT_LEAST:
					continue  # regard: assumed met
				if not service.condition_met(condition, &"", &""):
					met = false
					break
			if met:
				offered.append(option)
				ids.append(String(option.id))
		found[",".join(ids)] = offered
	var out: Array = []
	for key: String in found:
		var offered: Array[DialogueChoiceData] = found[key]
		var inside := false
		for other: String in found:
			if other != key and _part_of(offered, found[other]):
				inside = true
				break
		if not inside and not offered.is_empty():
			out.append(offered)
	return out


## The set of `line`'s answers with the most answers offered together (the first, on a tie).
static func largest(line: DialogueNodeData) -> Array[DialogueChoiceData]:
	var best: Array[DialogueChoiceData] = []
	for offered: Array[DialogueChoiceData] in sets(line):
		if offered.size() > best.size():
			best = offered
	return best


static func _part_of(small: Array[DialogueChoiceData], big: Array[DialogueChoiceData]) -> bool:
	if small.size() >= big.size():
		return false
	for option in small:
		if not big.has(option):
			return false
	return true


## The template a dialogue's speaker is played from (`actor_x` speaks as `npc_x.tres`), or null.
static func speaker_template(speaker_id: StringName) -> CharacterTemplateData:
	var path := "res://data/characters/npc_%s.tres" % String(speaker_id).trim_prefix("actor_")
	return load(path) as CharacterTemplateData if ResourceLoader.exists(path) else null


## A view of `line` as `dialogue`'s speaker says it, offering `offered` (its largest set of
## answers when not given).
static func view_of(dialogue: DialogueData, line: DialogueNodeData, serial: int = 1,
		offered: Array = []) -> DialogueView:
	var view := DialogueView.new()
	view.open = true
	view.dialogue_id = dialogue.id
	view.node_id = line.id
	view.line_serial = serial
	view.speaker_id = dialogue.speaker_id
	var who := speaker_template(dialogue.speaker_id)
	if who != null:
		view.speaker_name_key = who.name_key
		view.speaker_title_key = who.title_key
		view.portrait_path = who.portrait_ref
	view.mood = line.mood
	view.gestures = line.gesture != DialogueNodeData.GESTURE_NONE
	view.text_key = line.text_key
	var shown: Array = offered
	if shown.is_empty():
		shown = largest(line)
	var choices: Array[Dictionary] = []
	for option: DialogueChoiceData in shown:
		choices.append({"id": option.id, "text_key": option.text_key})
	view.choices = choices
	view.continues = line.choices.is_empty() and line.next_node_id != &""
	return view


## The world `sets` stages, and the owners `DialogueService` asks it through.
class StagedWorld extends RefCounted:
	var phase_of: Dictionary = {}
	var known: Dictionary = {}
	var flag_at: Dictionary = {}
	var origin: StringName = &""


class StagedKnowledge extends KnowledgeService:
	var _world: StagedWorld

	func _init(world: StagedWorld) -> void:
		super()
		_world = world

	func is_ready() -> bool:
		return true

	func knows(knowledge_id: StringName) -> bool:
		return bool(_world.known.get(knowledge_id, false))


class StagedQuests extends QuestService:
	var _world: StagedWorld

	func _init(world: StagedWorld) -> void:
		super()
		_world = world

	func is_ready() -> bool:
		return true

	func phase_of(quest_id: StringName) -> QuestData.Phase:
		return int(_world.phase_of.get(quest_id, 0)) as QuestData.Phase


class StagedStory extends StoryService:
	var _world: StagedWorld

	func _init(world: StagedWorld) -> void:
		super()
		_world = world

	func is_ready() -> bool:
		return true

	func flag_at_least(flag_id: StringName, value: int) -> bool:
		return int(_world.flag_at.get(flag_id, 0)) >= value

	func origin_is(origin_id: StringName) -> bool:
		return _world.origin == origin_id
