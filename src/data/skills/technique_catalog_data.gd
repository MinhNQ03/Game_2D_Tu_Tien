extends Resource
class_name TechniqueCatalogData
## TechniqueCatalogData — Aetheria data (every technique that exists, Phase 15).

@export var id: StringName = &""
@export var entries: Array[TechniqueData] = []


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var slots := {}
	for entry in entries:
		if entry == null:
			errors.append("a null entry")
			continue
		for reason in entry.validation_errors():
			errors.append("%s: %s" % [entry.id, reason])
		if slots.has(entry.slot):
			errors.append("'%s' and '%s' share skill key %d" % [slots[entry.slot], entry.id,
				entry.slot])
		slots[entry.slot] = entry.id
	return errors


func entry(technique_id: StringName) -> TechniqueData:
	for e in entries:
		if e != null and e.id == technique_id:
			return e
	return null
