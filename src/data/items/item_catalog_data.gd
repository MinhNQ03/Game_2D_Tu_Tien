extends Resource
class_name ItemCatalogData
## ItemCatalogData — Aetheria data (every item that exists, Phase 13). The inventory refuses an
## id the catalog does not name, so a save cannot smuggle in an item and a typo in a pickup is a
## loud refusal rather than a phantom stack.

@export var id: StringName = &""
@export var entries: Array[ItemData] = []


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var seen := {}
	for entry in entries:
		if entry == null:
			errors.append("a null entry")
			continue
		for reason in entry.validation_errors():
			errors.append("%s: %s" % [entry.id, reason])
		if seen.has(entry.id):
			errors.append("'%s' is listed twice" % entry.id)
		seen[entry.id] = true
	if entries.is_empty():
		errors.append("the catalog names no items")
	return errors


func entry(item_id: StringName) -> ItemData:
	for e in entries:
		if e != null and e.id == item_id:
			return e
	return null
