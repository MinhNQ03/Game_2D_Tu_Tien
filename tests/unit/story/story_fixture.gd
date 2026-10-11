extends RefCounted
class_name StoryFixture
## Typed builders for story tests: a small, VALID catalog that every negative case departs
## from in exactly one place (L-024), and a set of fake owners that record what they are asked.
##
## The fixture story:  a --(flag f_heard)--> b --(choice c_side)--> c --(event CULTIVATED)-->
##   [c_side == left] d_left | [otherwise] d_right  --(knows know_x)--> e --> rest (terminal).

const FlagScript := preload("res://src/data/story/story_flag_data.gd")
const ConditionScript := preload("res://src/data/story/story_condition_data.gd")
const ConsequenceScript := preload("res://src/data/story/story_consequence_data.gd")
const TriggerScript := preload("res://src/data/story/story_trigger_data.gd")
const BranchScript := preload("res://src/data/story/story_branch_data.gd")
const BeatScript := preload("res://src/data/story/story_beat_data.gd")
const OptionScript := preload("res://src/data/story/story_option_data.gd")
const ChoiceScript := preload("res://src/data/story/story_choice_data.gd")
const ChapterScript := preload("res://src/data/story/story_chapter_data.gd")
const CatalogScript := preload("res://src/data/story/story_catalog_data.gd")
const OriginScript := preload("res://src/data/story/origin_data.gd")
const GrantScript := preload("res://src/data/story/origin_grant_data.gd")
const OriginCatalogScript := preload("res://src/data/story/origin_catalog_data.gd")


static func flag(id: StringName, kind: int = StoryFlagData.Kind.BOOL,
		max_value: int = 1) -> StoryFlagData:
	var out: StoryFlagData = FlagScript.new()
	out.id = id
	out.kind = kind as StoryFlagData.Kind
	out.max_value = max_value
	out.purpose = "fixture"
	return out


static func trigger(kind: int, subject: StringName = &"", count: int = 1,
		subjects: Array[StringName] = []) -> StoryTriggerData:
	var out: StoryTriggerData = TriggerScript.new()
	out.kind = kind as StoryTriggerData.Kind
	out.subject_id = subject
	out.count = count
	out.subjects = subjects
	return out


static func condition(kind: int, id: StringName, option: StringName = &"",
		value: int = 1, negate: bool = false) -> StoryConditionData:
	var out: StoryConditionData = ConditionScript.new()
	out.kind = kind as StoryConditionData.Kind
	out.negate = negate
	match out.kind:
		StoryConditionData.Kind.FLAG:
			out.flag_id = id
			out.value = value
		StoryConditionData.Kind.ORIGIN:
			out.origin_id = id
		StoryConditionData.Kind.CHOICE:
			out.choice_id = id
			out.option_id = option
		StoryConditionData.Kind.KNOWS:
			out.knowledge_id = id
	return out


static func branch(next: StringName,
		conditions: Array[StoryConditionData] = []) -> StoryBranchData:
	var out: StoryBranchData = BranchScript.new()
	out.next_beat_id = next
	out.conditions = conditions
	return out


static func beat(id: StringName, beat_trigger: StoryTriggerData,
		branches: Array[StoryBranchData]) -> StoryBeatData:
	var out: StoryBeatData = BeatScript.new()
	out.id = id
	out.objective_key = StringName("OBJ_%s" % id)
	out.record_key = StringName("REC_%s" % id)
	out.source = "fixture"
	out.trigger = beat_trigger
	out.branches = branches
	return out


static func rest(id: StringName) -> StoryBeatData:
	var out: StoryBeatData = BeatScript.new()
	out.id = id
	out.objective_key = StringName("OBJ_%s" % id)
	out.source = "fixture"
	out.terminal = true
	return out


static func regard(who: StringName, dimension: StringName, delta: int) -> StoryConsequenceData:
	var out: StoryConsequenceData = ConsequenceScript.new()
	out.kind = StoryConsequenceData.Kind.REGARD
	out.character_id = who
	out.dimension = dimension
	out.delta = delta
	return out


static func set_flag(id: StringName, value: int = 1) -> StoryConsequenceData:
	var out: StoryConsequenceData = ConsequenceScript.new()
	out.kind = StoryConsequenceData.Kind.SET_FLAG
	out.flag_id = id
	out.value = value
	return out


static func teach(id: StringName) -> StoryConsequenceData:
	var out: StoryConsequenceData = ConsequenceScript.new()
	out.kind = StoryConsequenceData.Kind.GRANT_KNOWLEDGE
	out.knowledge_id = id
	return out


static func option(id: StringName,
		consequences: Array[StoryConsequenceData] = []) -> StoryOptionData:
	var out: StoryOptionData = OptionScript.new()
	out.id = id
	out.record_key = StringName("REC_OPTION_%s" % id)
	out.consequences = consequences
	return out


static func choice(id: StringName, beat_id: StringName,
		options: Array[StoryOptionData]) -> StoryChoiceData:
	var out: StoryChoiceData = ChoiceScript.new()
	out.id = id
	out.beat_id = beat_id
	out.title_key = StringName("TITLE_%s" % id)
	out.options = options
	return out


static func chapter(id: StringName, beats: Array[StoryBeatData], act: int = 0) -> StoryChapterData:
	var out: StoryChapterData = ChapterScript.new()
	out.id = id
	out.title_key = StringName("TITLE_%s" % id)
	out.act = act
	out.beats = beats
	return out


## The fixture story described at the top of this file.
static func catalog() -> StoryCatalogData:
	var no_conditions: Array[StoryConditionData] = []
	var to_b: Array[StoryBranchData] = [branch(&"b", no_conditions)]
	var to_c: Array[StoryBranchData] = [branch(&"c", no_conditions)]
	var left_only: Array[StoryConditionData] = [
		condition(StoryConditionData.Kind.CHOICE, &"c_side", &"left")]
	var fork: Array[StoryBranchData] = [branch(&"d_left", left_only),
		branch(&"d_right", no_conditions)]
	var to_e: Array[StoryBranchData] = [branch(&"e", no_conditions)]
	var to_e_again: Array[StoryBranchData] = [branch(&"e", no_conditions)]
	var to_rest: Array[StoryBranchData] = [branch(&"rest", no_conditions)]
	var first: Array[StoryBeatData] = [
		beat(&"a", trigger(StoryTriggerData.Kind.FLAG, &"f_heard"), to_b),
		beat(&"b", trigger(StoryTriggerData.Kind.CHOICE, &"c_side"), to_c),
		beat(&"c", trigger(StoryTriggerData.Kind.CULTIVATED), fork),
		beat(&"d_left", trigger(StoryTriggerData.Kind.KNOWS, &"know_x"), to_e),
		beat(&"d_right", trigger(StoryTriggerData.Kind.KNOWS, &"know_x"), to_e_again),
		beat(&"e", trigger(StoryTriggerData.Kind.ARRIVED, &"map_far"), to_rest),
	]
	var second: Array[StoryBeatData] = [rest(&"rest")]
	var left_effects: Array[StoryConsequenceData] = [regard(&"actor_a", &"trust", 15)]
	var right_effects: Array[StoryConsequenceData] = [
		regard(&"actor_b", &"trust", 10), regard(&"actor_a", &"affinity", -15),
		set_flag(&"f_count", 2), teach(&"know_side")]
	var options: Array[StoryOptionData] = [
		option(&"left", left_effects), option(&"right", right_effects)]
	var out: StoryCatalogData = CatalogScript.new()
	var chapters: Array[StoryChapterData] = [
		chapter(&"chapter_one", first), chapter(&"chapter_two", second, 1)]
	var flags: Array[StoryFlagData] = [
		flag(&"f_heard"), flag(&"f_count", StoryFlagData.Kind.INT, 3)]
	var choices: Array[StoryChoiceData] = [choice(&"c_side", &"b", options)]
	out.chapters = chapters
	out.flags = flags
	out.choices = choices
	out.start_beat_id = &"a"
	return out


static func grant_item(item_id: StringName, count: int) -> OriginGrantData:
	var out: OriginGrantData = GrantScript.new()
	out.kind = OriginGrantData.Kind.ITEM
	out.item_id = item_id
	out.count = count
	out.reason = "fixture"
	return out


static func grant_knowledge(knowledge_id: StringName) -> OriginGrantData:
	var out: OriginGrantData = GrantScript.new()
	out.kind = OriginGrantData.Kind.KNOWLEDGE
	out.knowledge_id = knowledge_id
	out.reason = "fixture"
	return out


static func grant_regard(who: StringName, dimension: StringName, delta: int) -> OriginGrantData:
	var out: OriginGrantData = GrantScript.new()
	out.kind = OriginGrantData.Kind.REGARD
	out.character_id = who
	out.dimension = dimension
	out.delta = delta
	out.reason = "fixture"
	return out


static func origin(id: StringName, grants: Array[OriginGrantData] = []) -> OriginData:
	var out: OriginData = OriginScript.new()
	out.id = id
	var stem := String(id).to_upper()
	out.name_key = StringName(stem + "_NAME")
	out.problem_key = StringName(stem + "_PROBLEM")
	out.edge_key = StringName(stem + "_EDGE")
	out.cost_key = StringName(stem + "_COST")
	out.goal_key = StringName(stem + "_GOAL")
	out.vignette_scene_id = StringName("scene_%s" % id)
	out.grants = grants
	return out


## The five frozen ids; the first carries one grant of each kind.
static func origins() -> OriginCatalogData:
	var kit: Array[OriginGrantData] = [grant_item(&"item_blade", 1),
		grant_knowledge(&"know_drill"), grant_regard(&"actor_a", &"affinity", -10)]
	var entries: Array[OriginData] = []
	for id in OriginCatalogData.FROZEN_IDS:
		var none: Array[OriginGrantData] = []
		entries.append(origin(id, kit if id == &"origin_ho_tieu" else none))
	var out: OriginCatalogData = OriginCatalogScript.new()
	out.entries = entries
	return out


## Fake owners that remember everything they were asked, and can be told to refuse.
##
## The seams are BOUND METHODS, not lambdas: a lambda here would capture `self`, the seams
## object would hold the lambda, and `self` holds the seams — a reference cycle that pins this
## object and every script it names until exit (the leak the faction fixture once had).
##
## TWO KINDS OF "NO" (D-073 §2). `decline_*` is an owner that says, when ASKED, that it cannot
## do the thing — the ordinary refusal. `breach_*` is an owner that agreed when asked and then
## fails anyway — a broken contract, which the story must still survive whole.
class Owners extends RefCounted:
	var known: Dictionary = {}
	var taught: Array = []
	## Every regard move that STANDS, as [who, dimension, applied].
	var regards: Array = []
	var given: Array = []
	var bag_has_room := true
	## Characters whose regard this owner says it cannot move / knowledge it cannot teach.
	var decline_regard_for: Array[StringName] = []
	var decline_teach: Array[StringName] = []
	## The same, but only discovered at the commit.
	var breach_regard_for: Array[StringName] = []
	var breach_teach: Array[StringName] = []
	## How many times each commit seam was called (a refused choice must call none).
	var regard_calls := 0
	var teach_calls := 0
	var seams: StoryOwners = null

	func _init() -> void:
		seams = StoryOwners.new()
		seams.knows = _knows
		seams.can_teach = _can_teach
		seams.teach = _teach
		seams.can_move_regard = _can_move_regard
		seams.move_regard = _move_regard
		seams.give_all = _give_all

	func _knows(id: StringName) -> bool:
		return known.has(id)

	func _can_teach(id: StringName) -> bool:
		return not decline_teach.has(id)

	func _teach(id: StringName, source: StringName) -> bool:
		teach_calls += 1
		if decline_teach.has(id) or breach_teach.has(id):
			return false
		taught.append([id, source])
		known[id] = true
		return true

	func _can_move_regard(who: StringName, _dimension: StringName, _delta: int) -> bool:
		return not decline_regard_for.has(who)

	## The relationship owner's own answer shape (`RegardRules.move`): what it was, what it is.
	## A move by the exact inverse of one that stands cancels it, as it does in the graph.
	func _move_regard(who: StringName, dimension: StringName, delta: int) -> Dictionary:
		regard_calls += 1
		if decline_regard_for.has(who) or breach_regard_for.has(who):
			return {"ok": false, "old_value": 0, "new_value": 0}
		var inverse := regards.find([who, dimension, -delta])
		if inverse >= 0:
			regards.remove_at(inverse)
		else:
			regards.append([who, dimension, delta])
		return {"ok": true, "old_value": 0, "new_value": delta}

	func _give_all(items: Dictionary) -> bool:
		if not bag_has_room:
			return false
		for item_id: StringName in items:
			given.append([item_id, items[item_id]])
		return true
