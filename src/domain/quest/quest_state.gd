extends RefCounted
class_name QuestState
## QuestState — Aetheria domain (where every quest stands, Phase 19, D-070).
##
## The ONLY record of quest progress. A quest with no record is AVAILABLE; a record says it
## is ACTIVE, owed its reward, or COMPLETED, and carries the count of each objective the
## quest itself counts (defeats). Objectives that are a question to another owner — is this
## known, is this held — are NOT mirrored here: they are asked each time.
##
## Pure data and its persistence boundary (`docs/SAVE_FORMAT.md` `quests`). Mutated only by
## `QuestService`; nothing else writes it.

const SCHEMA := 1

enum Status {
	ACTIVE,
	## Turned in, the bag part of the reward is paid, a later part is not. Retry pays the rest.
	REWARD_OWED,
	COMPLETED,
}

const STATUS_NAMES := {
	Status.ACTIVE: "active",
	Status.REWARD_OWED: "reward_owed",
	Status.COMPLETED: "completed",
}

## quest_id(String) -> { "status": Status, "progress": { objective_id(String) -> int },
##                      "counted": { objective_id(String) -> Array[String] source ids } }
var _records: Dictionary = {}


func has(quest_id: StringName) -> bool:
	return _records.has(String(quest_id))


func status_of(quest_id: StringName) -> int:
	return int(_records[String(quest_id)]["status"]) if has(quest_id) else -1


func is_status(quest_id: StringName, status: Status) -> bool:
	return has(quest_id) and status_of(quest_id) == status


## Quest ids that have a record, sorted (a deterministic iteration order).
func quest_ids() -> Array[StringName]:
	var keys: Array = _records.keys()
	keys.sort()
	var out: Array[StringName] = []
	for key: String in keys:
		out.append(StringName(key))
	return out


func begin(quest_id: StringName) -> void:
	_records[String(quest_id)] = {"status": Status.ACTIVE, "progress": {}, "counted": {}}


func set_status(quest_id: StringName, status: Status) -> void:
	if not has(quest_id):
		return
	var record: Dictionary = _records[String(quest_id)]
	record["status"] = status
	if status == Status.COMPLETED:
		# What was counted on the way no longer answers anything.
		record["progress"] = {}
		record["counted"] = {}


func erase(quest_id: StringName) -> void:
	_records.erase(String(quest_id))


func progress_of(quest_id: StringName, objective_id: StringName) -> int:
	if not has(quest_id):
		return 0
	return int((_records[String(quest_id)]["progress"] as Dictionary).get(
		String(objective_id), 0))


func has_counted(quest_id: StringName, objective_id: StringName, source_id: StringName) -> bool:
	if not has(quest_id):
		return false
	var counted: Dictionary = _records[String(quest_id)]["counted"]
	return (counted.get(String(objective_id), []) as Array).has(String(source_id))


## Count one more toward `objective_id`, remembering the source that paid for it.
func count_one(quest_id: StringName, objective_id: StringName, source_id: StringName) -> int:
	if not has(quest_id):
		return 0
	var record: Dictionary = _records[String(quest_id)]
	var progress: Dictionary = record["progress"]
	var counted: Dictionary = record["counted"]
	var key := String(objective_id)
	progress[key] = int(progress.get(key, 0)) + 1
	var sources: Array = counted.get(key, [])
	sources.append(String(source_id))
	counted[key] = sources
	return int(progress[key])


# --- Persistence boundary --------------------------------------------------------

func to_dict() -> Dictionary:
	var quests: Dictionary = {}
	for quest_id in quest_ids():
		var record: Dictionary = _records[String(quest_id)]
		var progress: Dictionary = {}
		var counted: Dictionary = {}
		var keys: Array = (record["progress"] as Dictionary).keys()
		keys.sort()
		for key: String in keys:
			progress[key] = int(record["progress"][key])
			counted[key] = (record["counted"].get(key, []) as Array).duplicate()
		quests[String(quest_id)] = {"status": STATUS_NAMES[int(record["status"])],
			"progress": progress, "counted": counted}
	return {"schema": SCHEMA, "quests": quests}


## Hydrate from `to_dict()` output, validated against `catalog`. Atomic and strict (L-024):
## an unknown quest or objective, an objective the quest does not count, a count outside
## 0..required, sources that do not match the count, or any wrong type rejects the WHOLE
## payload and changes nothing.
func from_dict(data: Dictionary, catalog: QuestCatalogData) -> bool:
	if catalog == null or typeof(data.get("schema")) != TYPE_INT \
			or int(data["schema"]) != SCHEMA:
		push_error("[quest-state] from_dict: unsupported schema %s" % str(data.get("schema")))
		return false
	var rows: Variant = data.get("quests")
	if typeof(rows) != TYPE_DICTIONARY:
		push_error("[quest-state] from_dict: 'quests' must be a Dictionary")
		return false
	var staged: Dictionary = {}
	for raw_id: Variant in rows:
		var quest := catalog.entry(StringName(String(raw_id))) \
			if typeof(raw_id) == TYPE_STRING else null
		var record := _staged_record(quest, (rows as Dictionary)[raw_id])
		if record.is_empty():
			push_error("[quest-state] from_dict: the record of '%s' is not valid" % str(raw_id))
			return false
		staged[String(raw_id)] = record
	_records = staged
	return true


func _staged_record(quest: QuestData, raw: Variant) -> Dictionary:
	if quest == null or typeof(raw) != TYPE_DICTIONARY:
		return {}
	var row: Dictionary = raw
	var status := -1
	for value: int in STATUS_NAMES:
		if typeof(row.get("status")) == TYPE_STRING and STATUS_NAMES[value] == row["status"]:
			status = value
	if status < 0 or typeof(row.get("progress")) != TYPE_DICTIONARY \
			or typeof(row.get("counted")) != TYPE_DICTIONARY:
		return {}
	var progress: Dictionary = {}
	var counted: Dictionary = {}
	for raw_key: Variant in row["progress"]:
		var entry := quest.objective(StringName(String(raw_key))) \
			if typeof(raw_key) == TYPE_STRING else null
		var value: Variant = row["progress"][raw_key]
		var sources: Variant = row["counted"].get(raw_key)
		if entry == null or not entry.is_counted() or status == Status.COMPLETED \
				or typeof(value) != TYPE_INT or int(value) < 1 or int(value) > entry.count \
				or typeof(sources) != TYPE_ARRAY or (sources as Array).size() != int(value):
			return {}
		var seen: Dictionary = {}
		for source: Variant in sources:
			if typeof(source) != TYPE_STRING or String(source) == "" or seen.has(source):
				return {}
			seen[source] = true
		progress[String(raw_key)] = int(value)
		counted[String(raw_key)] = (sources as Array).duplicate()
	if (row["counted"] as Dictionary).size() != progress.size():
		return {}
	return {"status": status, "progress": progress, "counted": counted}
