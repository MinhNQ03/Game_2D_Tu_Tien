extends Resource
class_name PetCatalogData
## PetCatalogData — Aetheria data (every authored pet, Phase 16). The content boundary a
## `pet_id` is resolved through: an id that is not listed here does not exist, so ownership,
## hydration and summoning all fail closed on it.

@export var entries: Array[PetData] = []


func entry(pet_id: StringName) -> PetData:
	for pet in entries:
		if pet != null and pet.id == pet_id:
			return pet
	return null


func has(pet_id: StringName) -> bool:
	return entry(pet_id) != null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for pet in entries:
		if pet != null:
			out.append(pet.id)
	return out


func is_valid() -> bool:
	return validation_errors().is_empty()


## Missing entries, duplicate ids and every entry's own errors (prefixed with its id).
func validation_errors(technique_ids: Array[StringName] = []) -> Array[String]:
	var errors: Array[String] = []
	if entries.is_empty():
		errors.append("the pet catalog is empty")
	var seen: Dictionary = {}
	for i in entries.size():
		var pet := entries[i]
		if pet == null:
			errors.append("entry %d is null (a missing or unloadable PetData)" % i)
			continue
		if seen.has(pet.id):
			errors.append("duplicate pet id '%s'" % pet.id)
		seen[pet.id] = true
		for problem in pet.validation_errors(technique_ids):
			errors.append("%s: %s" % [pet.id, problem])
	return errors
