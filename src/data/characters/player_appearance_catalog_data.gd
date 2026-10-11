extends Resource
class_name PlayerAppearanceCatalogData
## PlayerAppearanceCatalogData — Aetheria data (the looks offered at New Game, Phase 20).
##
## The first entry is the default selection.

@export var entries: Array[PlayerAppearanceData] = []


func entry(appearance_id: StringName) -> PlayerAppearanceData:
	for look in entries:
		if look != null and look.id == appearance_id:
			return look
	return null


func has(appearance_id: StringName) -> bool:
	return entry(appearance_id) != null


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for look in entries:
		if look != null:
			out.append(look.id)
	return out


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if entries.is_empty():
		errors.append("no appearance is offered")
	var seen := {}
	var bodies := {}
	for i in entries.size():
		var look := entries[i]
		if look == null:
			errors.append("appearance %d is null" % i)
			continue
		errors.append_array(look.validation_errors())
		if seen.has(look.id):
			errors.append("duplicate appearance id '%s'" % look.id)
		seen[look.id] = true
		# Two "choices" that draw the same body are one choice wearing two names.
		if look.template != null and look.template.sprite_set_ref != "":
			if bodies.has(look.template.sprite_set_ref):
				errors.append("appearances '%s' and '%s' draw the same body"
					% [bodies[look.template.sprite_set_ref], look.id])
			bodies[look.template.sprite_set_ref] = look.id
	return errors
