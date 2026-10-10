extends Resource
class_name DialogueData
## DialogueData — Aetheria data (one authored conversation, Phase 18).
##
## CONTENT: who speaks it and the graph of what they say. `speaker_id` is a CHARACTER — an
## `instance_id` in the session's `CharacterRegistry`, exactly as `ShopData.keeper_id` is — so
## a dialogue belongs to someone who already exists; it defines no NPC of its own. A new
## conversation is a new resource in the `DialogueCatalogData`, never a branch in a runtime.
##
## It holds nothing that changes. Where a conversation IS right now is the runtime's cursor;
## what a choice changed lives in the system that owns it (D-066).

@export var id: StringName = &""
@export var speaker_id: StringName = &""
@export var start_node_id: StringName = &""
@export var nodes: Array[DialogueNodeData] = []


func node(node_id: StringName) -> DialogueNodeData:
	for entry in nodes:
		if entry != null and entry.id == node_id:
			return entry
	return null


func has_node(node_id: StringName) -> bool:
	return node(node_id) != null


## Every localization key the conversation shows (a line or an answer), in authored order.
func text_keys() -> Array[StringName]:
	var keys: Array[StringName] = []
	for entry in nodes:
		if entry == null:
			continue
		keys.append(entry.text_key)
		for option in entry.choices:
			if option != null:
				keys.append(option.text_key)
	return keys


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"":
		errors.append("id is empty")
	elif not String(id).begins_with("dlg_"):
		errors.append("id '%s' must use the dlg_ prefix" % id)
	if speaker_id == &"":
		errors.append("speaker_id is empty (a dialogue is spoken by a character)")
	if nodes.is_empty():
		errors.append("a dialogue with no nodes says nothing")
		return errors
	var node_ids: Dictionary = {}
	var choice_ids: Dictionary = {}
	for i in nodes.size():
		var entry := nodes[i]
		if entry == null:
			errors.append("node %d is null" % i)
			continue
		for problem in entry.validation_errors():
			errors.append("node '%s': %s" % [entry.id, problem])
		if node_ids.has(entry.id):
			errors.append("duplicate node id '%s'" % entry.id)
		node_ids[entry.id] = true
		for option in entry.choices:
			if option == null:
				continue
			if choice_ids.has(option.id):
				errors.append("duplicate choice id '%s'" % option.id)
			choice_ids[option.id] = true
	if start_node_id == &"":
		errors.append("start_node_id is empty")
	elif not node_ids.has(start_node_id):
		errors.append("start_node_id '%s' is not a node of this dialogue" % start_node_id)
	for entry in nodes:
		if entry == null:
			continue
		if entry.next_node_id != &"" and not node_ids.has(entry.next_node_id):
			errors.append("node '%s' continues to '%s', which does not exist"
				% [entry.id, entry.next_node_id])
		for option in entry.choices:
			if option != null and option.next_node_id != &"" \
					and not node_ids.has(option.next_node_id):
				errors.append("choice '%s' leads to '%s', which does not exist"
					% [option.id, option.next_node_id])
	if not errors.is_empty():
		return errors  # the walks below assume every reference resolves
	for entry in nodes:
		if entry.choices.is_empty() and _continues_forever(entry):
			errors.append(("node '%s' starts a chain of lines that never reaches an answer "
				+ "or an end") % entry.id)
	var reached := _reachable_from_start()
	for entry in nodes:
		if not reached.has(entry.id):
			errors.append("node '%s' cannot be reached from '%s'" % [entry.id, start_node_id])
	return errors


## Following only "continue" links from `from`: does the chain loop back on itself? Every step
## still needs a key press, so this is never an automatic loop — but it is a conversation whose
## only way out is to walk away, which is a content bug.
func _continues_forever(from: DialogueNodeData) -> bool:
	var seen: Dictionary = {}
	var at := from
	while at != null and at.choices.is_empty() and at.next_node_id != &"":
		if seen.has(at.id):
			return true
		seen[at.id] = true
		at = node(at.next_node_id)
	return false


func _reachable_from_start() -> Dictionary:
	var reached: Dictionary = {}
	var frontier: Array[StringName] = [start_node_id]
	while not frontier.is_empty():
		var node_id: StringName = frontier.pop_back()
		if reached.has(node_id):
			continue
		reached[node_id] = true
		var entry := node(node_id)
		if entry == null:
			continue
		if entry.next_node_id != &"":
			frontier.append(entry.next_node_id)
		for option in entry.choices:
			if option != null and option.next_node_id != &"":
				frontier.append(option.next_node_id)
	return reached
