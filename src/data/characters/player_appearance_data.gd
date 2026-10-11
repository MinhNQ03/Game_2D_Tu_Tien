extends Resource
class_name PlayerAppearanceData
## PlayerAppearanceData — Aetheria data (a look the player may choose, Phase 20, D-072 §2).
##
## A look is a CHARACTER TEMPLATE: the player's `CharacterState` is built from the chosen one,
## so gender, the drawn body and the portrait all come from the same place every other
## character's do. Nothing here is a second identity system.
##
## ONLY WHAT THE GAME CAN DRAW IS OFFERED. A look is valid only if its template names a visual
## profile and a portrait that exist — the identity screen must never show a choice that
## silently renders as something else.

@export var id: StringName = &""
## The name of the look on the identity screen.
@export var name_key: StringName = &""
@export var template: CharacterTemplateData = null


func gender() -> int:
	return template.gender if template != null else CharacterTemplateData.Gender.UNSPECIFIED


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	var bad := StoryIds.problem("appearance", id)
	if bad != "":
		errors.append(bad)
	if name_key == &"":
		errors.append("appearance '%s' has no name" % id)
	if template == null or not template.is_valid():
		errors.append("appearance '%s' has no valid character template" % id)
		return errors
	if template.gender == CharacterTemplateData.Gender.UNSPECIFIED:
		errors.append("appearance '%s': its template states no gender" % id)
	if template.sprite_set_ref == "" or not ResourceLoader.exists(template.sprite_set_ref):
		errors.append("appearance '%s': its body cannot be drawn ('%s')"
			% [id, template.sprite_set_ref])
	if template.portrait_ref == "" or not ResourceLoader.exists(template.portrait_ref):
		errors.append("appearance '%s': its portrait is missing ('%s')"
			% [id, template.portrait_ref])
	if template.default_sect_id != &"" or template.default_faction_id != &"":
		errors.append("appearance '%s': the player begins with no sect and no faction (C-003)"
			% id)
	return errors
