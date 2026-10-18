extends RefCounted
class_name DialogueOffers
## DialogueOffers — which of a line's authored answers can ever be on screen TOGETHER (UI-01).
##
## The dialogue box is sized by what it shows, so a test or a capture that wants the tallest box
## a line can produce needs the largest set of its answers some state of the world offers at
## once — not every answer authored on it (the scout's hub authors seven and never shows more
## than five). Shared by the dialogue layout tests and `tools/capture_ui.gd`; nothing in the
## game depends on it.
##
## A quest is in exactly one phase and a thing is either known or not, so answers conditioned
## on different phases of one quest — or on knowing and on not knowing the same thing — are
## mutually exclusive by construction; every state of those owners is tried and the widest
## offer kept. Regard is NOT modelled: a regard condition is assumed met, which can only make
## the measured box taller than any real one.


static func largest(line: DialogueNodeData) -> Array[DialogueChoiceData]:
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
				# A story flag holds 0..the largest value any answer here asks it for.
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
	var best: Array[DialogueChoiceData] = []
	for state in states:
		var phase_of: Dictionary = {}
		var known: Dictionary = {}
		var rest := state
		for quest_id in quests:
			phase_of[quest_id] = rest % phases
			rest /= phases
		for fact in facts:
			known[fact] = rest % 2 == 1
			rest /= 2
		var flag_at: Dictionary = {}
		for flag_id: StringName in flag_top:
			var span := int(flag_top[flag_id]) + 1
			flag_at[flag_id] = rest % span
			rest /= span
		var origin_at := rest  # == origins.size() means "none of these"
		var offered: Array[DialogueChoiceData] = []
		for option in line.choices:
			var met := true
			for condition in option.conditions:
				var holds := true
				if condition.kind == DialogueConditionData.Kind.QUEST_PHASE:
					holds = int(phase_of[condition.quest_id]) == int(condition.quest_phase)
				elif condition.kind == DialogueConditionData.Kind.KNOWS:
					holds = bool(known[condition.knowledge_id])
				elif condition.kind == DialogueConditionData.Kind.FLAG:
					holds = int(flag_at[condition.flag_id]) >= condition.value
				elif condition.kind == DialogueConditionData.Kind.ORIGIN:
					holds = origins.find(condition.origin_id) == origin_at
				else:
					continue  # regard: assumed met
				if holds == condition.negate:
					met = false
			if met:
				offered.append(option)
		if offered.size() > best.size():
			best = offered
	return best


## The template a dialogue's speaker is played from (`actor_x` speaks as `npc_x.tres`), or null.
static func speaker_template(speaker_id: StringName) -> CharacterTemplateData:
	var path := "res://data/characters/npc_%s.tres" % String(speaker_id).trim_prefix("actor_")
	return load(path) as CharacterTemplateData if ResourceLoader.exists(path) else null


## A view of `line` as `dialogue`'s speaker says it, offering its largest set of answers.
static func view_of(dialogue: DialogueData, line: DialogueNodeData,
		serial: int = 1) -> DialogueView:
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
	var choices: Array[Dictionary] = []
	for option in largest(line):
		choices.append({"id": option.id, "text_key": option.text_key})
	view.choices = choices
	view.continues = line.choices.is_empty() and line.next_node_id != &""
	return view
