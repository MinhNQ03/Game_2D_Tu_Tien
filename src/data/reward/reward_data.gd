extends Resource
class_name RewardData
## RewardData — Aetheria data (what a source pays, Phase 19, D-070).
##
## CONTENT: the parts of ONE reward, each paid by the system that owns what it changes — the
## bag (`items`), progression (`xp`), the relationship graph (one character's regard for the
## player). It says WHAT; `RewardService` decides whether it has been paid and in which order,
## and the owners do the paying. It carries no id of its own: the id belongs to the SOURCE
## that pays it (a quest, a defeat, later a drop), which is what lets one authored reward be
## paid by many sources without the ledger confusing them.
##
## A CLOSED set of parts. A new kind of part arrives with the first content that needs it.

## Bounds that keep one reward from being a typo away from breaking the economy.
const MAX_ITEM_COUNT := 99
const MAX_XP := 1000
const MAX_REGARD_DELTA := 50

@export var items: Array[RewardItemData] = []
@export var xp: int = 0
## Whose regard for the player moves (a `CharacterRegistry` instance id), on which dimension
## of the relationship graph, by how much. All three, or none.
@export var regard_character_id: StringName = &""
@export var regard_dimension: StringName = &""
@export var regard_delta: int = 0


func has_items() -> bool:
	return not items.is_empty()


func has_regard() -> bool:
	return regard_delta != 0


## { item_id -> count }, the shape `InventoryRuntime.exchange` gives.
func item_counts() -> Dictionary:
	var out: Dictionary = {}
	for entry in items:
		if entry != null and entry.item != null:
			out[entry.item.id] = int(out.get(entry.item.id, 0)) + entry.count
	return out


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var seen: Dictionary = {}
	for i in items.size():
		var entry := items[i]
		if entry == null:
			errors.append("item %d is null" % i)
			continue
		for problem in entry.validation_errors():
			errors.append("item %d: %s" % [i, problem])
		if entry.item != null:
			if seen.has(entry.item.id):
				errors.append("item '%s' is listed twice" % entry.item.id)
			seen[entry.item.id] = true
	if xp < 0 or xp > MAX_XP:
		errors.append("xp %d is outside 0..%d" % [xp, MAX_XP])
	var named := regard_character_id != &"" or regard_dimension != &""
	if regard_delta == 0 and named:
		errors.append("names whose regard moves but moves it by 0")
	if regard_delta != 0:
		if regard_character_id == &"" or regard_dimension == &"":
			errors.append("moves regard by %d without naming whose and on which dimension"
				% regard_delta)
		if absi(regard_delta) > MAX_REGARD_DELTA:
			errors.append("a regard move of %d exceeds the ceiling %d"
				% [regard_delta, MAX_REGARD_DELTA])
	if items.is_empty() and xp == 0 and regard_delta == 0:
		errors.append("pays nothing")
	return errors
