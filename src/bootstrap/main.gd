extends Node2D
## Main bootstrap node for Aetheria.
##
## Foundation only — this is NOT gameplay. It establishes the top-level scene
## structure that Phase 1 (Core) will grow into:
##
##   Main
##   ├── Systems   (infrastructure/gameplay system nodes & future autoload hosts)
##   ├── World     (maps, entities, world simulation host)
##   └── UI        (HUD, menus, overlays)
##
## Layers: see .kiro/steering/03-architecture.md and docs/ARCHITECTURE.md.
## The three containers mirror the presentation / gameplay / world split so later
## systems attach under the correct branch instead of piling onto one God node.

## Child container names this scene guarantees to expose. Kept as constants so tests
## and future systems reference them without magic strings.
const CONTAINER_SYSTEMS := "Systems"
const CONTAINER_WORLD := "World"
const CONTAINER_UI := "UI"

const REQUIRED_CONTAINERS := [CONTAINER_SYSTEMS, CONTAINER_WORLD, CONTAINER_UI]


func _ready() -> void:
	# Validate the scene is structured as the rest of the project expects. Failing
	# loudly here (rather than silently) is deliberate — a broken bootstrap should
	# never look like a healthy boot. See .kiro/steering/04-coding-standards.md.
	assert(_has_required_containers(), "Main scene is missing a required container node.")
	print("[boot] Aetheria main scene ready. Foundation boot OK.")


## Returns true only if every required container node exists as a direct child.
## Pure/queryable so the smoke test can assert on it without side effects.
func has_required_structure() -> bool:
	return _has_required_containers()


func _has_required_containers() -> bool:
	for container_name in REQUIRED_CONTAINERS:
		if get_node_or_null(NodePath(container_name)) == null:
			push_error("[boot] Missing required container: %s" % container_name)
			return false
	return true
