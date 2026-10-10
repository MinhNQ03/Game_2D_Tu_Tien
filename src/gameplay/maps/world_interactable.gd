extends Node2D
class_name WorldInteractable
## WorldInteractable — Aetheria gameplay (something in the world the interact key acts on).
##
## The ONE contract `MapBase` selects on: where it is, how close the player must stand
## (`reach_px` — a DISTANCE, independent of any collision body: D-063 A2), what the prompt says,
## and WHAT it is (`interaction_kind` + `interaction_id`), so the map can report "the player used
## this" without knowing what using it means. The owner of the meaning decides — the Knowledge
## Core for a stele, `PetRuntime` for a stray animal, the NPC runtime for a person — and the map
## decides nothing.
##
## Subclasses: `KnowledgeSource` (Phase 12), `PetEncounter` (Phase 16). A map lists them under
## `KnowledgeSources` / `Interactables`; identity is the authored `interaction_id`, never a
## scene-tree path.

## How close the player must stand, in pixels.
@export var reach_px: float = 30.0

## Localization key of the VERB the prompt shows ("Read", "Befriend", "Talk").
@export var prompt_key: StringName = &"UI_HUD_INTERACT_ACTION"


## What kind of thing this is — the routing key (`&"knowledge_source"`, `&"pet_encounter"`).
func interaction_kind() -> StringName:
	return &""


## The authored, stable identity of THIS one within its kind.
func interaction_id() -> StringName:
	return &""


## Arguments for the prompt's text (a person's prompt names them). Values that are
## `StringName`s are localization keys the HUD resolves.
func prompt_args() -> Dictionary:
	return {}


## Can it be used right now? A hidden interactable (a stray already befriended) is not offered.
func is_available() -> bool:
	return visible


func reaches(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= reach_px


## The one the player means: the NEAREST available candidate in reach of `world_point`, ties
## broken by `interaction_kind` then `interaction_id` so two overlapping reaches always resolve
## the same way (never by scene order, which a re-save can change). Null when none is in reach.
static func nearest_in_reach(candidates: Array, world_point: Vector2) -> WorldInteractable:
	var best: WorldInteractable = null
	var best_distance := INF
	for candidate: Variant in candidates:
		if not (candidate is WorldInteractable):
			continue
		var item: WorldInteractable = candidate
		if not item.is_available() or not item.reaches(world_point):
			continue
		var distance := item.global_position.distance_to(world_point)
		if best == null or distance < best_distance - 0.001 \
				or (absf(distance - best_distance) <= 0.001 and _sorts_before(item, best)):
			best = item
			best_distance = distance
	return best


static func _sorts_before(a: WorldInteractable, b: WorldInteractable) -> bool:
	var ka := "%s/%s" % [a.interaction_kind(), a.interaction_id()]
	var kb := "%s/%s" % [b.interaction_kind(), b.interaction_id()]
	return ka < kb
