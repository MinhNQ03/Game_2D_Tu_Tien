extends Area2D
class_name MapExitZone
## MapExitZone — Aetheria gameplay (presentation-side map exit trigger).
##
## An Area2D placed in a map scene marking "stand here + press interact to leave". It
## carries ONLY a stable `exit_id` that references a `MapExit` in the map's `MapData`
## (D-022) — the destination (`to_map_id` + `entry_point`) is authored once in the data, NOT
## duplicated here, so a zone can never drift to a different destination than the data says.
## It performs NO transition itself: `MapBase` resolves `exit_id -> MapExit` and emits the
## `exit_requested` intent, which `WorldRuntime` resolves through `SceneRouter`. Keeps
## "why/where we move" out of presentation nodes (`docs/MULTIPLAYER_PLAN.md` §4).
##
## It detects the player via the PLAYER collision layer (named constant, not a magic
## number — L-002/L-014). It is a sensor (its own body is not solid).

## The id of the `MapExit` (in this map's MapData) this zone triggers. Set per-instance.
@export var exit_id: StringName = &""


func _ready() -> void:
	# Detect the player body only; this zone occupies no solid layer (sensor).
	collision_layer = 0
	collision_mask = CollisionLayers.PLAYER
	monitoring = true
