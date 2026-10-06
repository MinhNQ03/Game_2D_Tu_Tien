extends Node2D
class_name WorldItem
## WorldItem — Aetheria gameplay (an item lying in the world, Phase 13).
##
## Authored in a map under `Pickups`, with a stable `pickup_id`: the `InventoryRuntime` collects
## it when the player walks within `reach_px` (a distance test, headless-safe) and remembers the
## id for the rest of the run, so a collected pickup never reappears when the map is re-entered.
## Its LOOK is a presentation child (`PickupFeedback`); this node is only what and where.

@export var item: ItemData = null
@export var count: int = 1
@export var pickup_id: StringName = &""
@export var reach_px: float = 14.0


func _ready() -> void:
	if item == null or pickup_id == &"" or count < 1:
		push_error("[world-item] '%s' is not a usable pickup (item %s, id '%s', count %d)"
			% [name, item, pickup_id, count])


func reaches(world_point: Vector2) -> bool:
	return global_position.distance_to(world_point) <= reach_px
