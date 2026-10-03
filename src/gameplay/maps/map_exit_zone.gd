extends Area2D
class_name MapExitZone
## MapExitZone — Aetheria gameplay (presentation-side map exit trigger).
##
## An Area2D placed in a map scene marking "stand here + press interact to leave to another
## map". It carries only the DESTINATION ids; it performs NO transition itself — the map
## coordinator (`MapBase`) reads these and emits an `exit_requested` intent, which
## WorldRuntime resolves through SceneRouter. Keeps "why we move" out of presentation nodes
## (`docs/MULTIPLAYER_PLAN.md` §4).
##
## It detects the player via the PLAYER collision layer (named constant, not a magic
## number — L-002/L-014). It is a sensor (its own body is not solid).

## Destination map id (matches a `MapData.id`). Set per-instance in the scene.
@export var to_map_id: StringName = &""

## Named spawn marker in the destination map to arrive at.
@export var entry_point: StringName = &""


func _ready() -> void:
	# Detect the player body only; this zone occupies no solid layer (sensor).
	collision_layer = 0
	collision_mask = CollisionLayers.PLAYER
	monitoring = true
