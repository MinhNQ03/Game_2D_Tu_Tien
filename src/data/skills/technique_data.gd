extends Resource
class_name TechniqueData
## TechniqueData — Aetheria data (a công pháp: the framework a skill comes from, Phase 15).
##
## `PROGRESSION_CULTIVATION_DESIGN.md` §8: a technique is a knowledge system, not a stat card. It
## is LEARNED when its `required_knowledge` is held (READ through the Knowledge Core — never
## copied, D-040) and the body has reached `required_realm`/`required_layer` (read through
## `CultivationService.meets`). Compatibility and incompatibility are both first-class data
## (§8); learning a technique incompatible with one already known is refused.

@export var id: StringName = &""
@export var name_key: StringName = &""
@export var desc_key: StringName = &""
@export var element: StringName = &""
@export var required_knowledge: Array[StringName] = []
@export var required_realm: StringName = &""
@export var required_layer: int = 0
@export var incompatible_with: Array[StringName] = []
@export var skill: SkillData = null
## Which skill key (1..4) the skill sits on.
@export var slot: int = 1


func is_valid() -> bool:
	return validation_errors().is_empty()


func validation_errors() -> Array[String]:
	var errors: Array[String] = []
	if id == &"" or not String(id).begins_with("tech_"):
		errors.append("id must be a non-empty 'tech_*' id")
	if not SkillData.ELEMENTS.has(element):
		errors.append("element '%s' is not canon (COMBAT_DESIGN §3)" % element)
	if required_knowledge.is_empty():
		errors.append("a technique is learned from knowledge: required_knowledge is empty")
	if skill == null or not skill.is_valid():
		errors.append("its skill is missing or invalid: %s"
			% (str(skill.validation_errors()) if skill != null else "null"))
	elif skill.element != element:
		errors.append("its skill's element differs from the technique's")
	if slot < 1 or slot > 4:
		errors.append("slot must be 1..4")
	return errors
