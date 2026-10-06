extends RefCounted
class_name TechniqueService
## TechniqueService — Aetheria domain (the ONE path by which a technique is learned, Phase 15).
##
## A technique is learned when the Knowledge Core holds its `required_knowledge` (READ, never
## copied — D-040 / C-012), the body meets its realm (`CultivationService.meets`), and nothing
## already known is incompatible with it (§8). Learning writes `CharacterState.technique_ids`
## through `add_technique` (the storage boundary) — nothing else writes it
## (`tests/unit/skills/test_skills.gd` walks `src/`).

const LEARNED := &"learned"
const ALREADY := &"already_known"
const NEEDS_KNOWLEDGE := &"needs_knowledge"
const NEEDS_REALM := &"needs_realm"
const INCOMPATIBLE := &"incompatible"

var _knowledge: KnowledgeService = null
var _cultivation: CultivationService = null


func _init(knowledge: KnowledgeService = null, cultivation: CultivationService = null) -> void:
	_knowledge = knowledge
	_cultivation = cultivation


func is_ready() -> bool:
	return _knowledge != null and _cultivation != null


## Why `state` cannot learn `technique` now, or LEARNED when it can (ALREADY when known).
func blocker(state: CharacterState, technique: TechniqueData) -> StringName:
	if state.technique_ids.has(technique.id):
		return ALREADY
	if not _knowledge.knows_all(technique.required_knowledge):
		return NEEDS_KNOWLEDGE
	if not _cultivation.meets(state, technique.required_realm, technique.required_layer):
		return NEEDS_REALM
	for known in state.technique_ids:
		if technique.incompatible_with.has(known):
			return INCOMPATIBLE
	return LEARNED


func learn(state: CharacterState, technique: TechniqueData) -> StringName:
	var reason := blocker(state, technique)
	if reason == LEARNED:
		state.add_technique(technique.id)
	return reason
