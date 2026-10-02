extends Node2D
class_name PlayerSandbox
## PlayerSandbox — Aetheria gameplay (TEMPORARY Phase-02 gameplay-validation scene).
##
## A real, runnable scene so a human can play the Phase-02 Player: move the player around a
## walled area and attack a Training Dummy, proving top-down movement + collision + a
## bidirectional minimal-damage interaction. It is the first gameplay scene after New Game
## *for Phase 02 only* — it is NOT a story/prologue system and NOT a combat system. Phase 03
## (World/Map) replaces it as the real first scene; this is explicitly a validation sandbox.
##
## This node is the GAMEPLAY COORDINATOR (`docs/ARCHITECTURE.md` §2 gameplay layer): it owns
## the demo interaction (range check + who-hits-whom) and resolves "how much" through the
## domain `DamageRules` — presentation never decides outcomes (`docs/MULTIPLAYER_PLAN.md`
## §4). The Player/Dummy own their own movement/health; the coordinator does not reach into
## their internals. Input intent still flows only through `InputService`.
##
## Mirrors the first-scene contract Main expects: emits `return_to_menu_requested` and
## resolves `open_menu` via InputService, like the prologue shell it replaces.

signal return_to_menu_requested()

## Fixed sandbox interaction range (px). A TEST/DEMO value for Phase 02 validation, NOT a
## combat-balance system — there is no real combat range model yet (D-007 Open).
const SANDBOX_ATTACK_RANGE: float = 64.0

@onready var _player: Player = $Player
@onready var _dummy: TrainingDummy = $TrainingDummy
@onready var _hud_label: Label = $HUD/InfoLabel

var _input: Node = null
var _bus: Node = null


func _ready() -> void:
	_input = get_node_or_null("/root/InputService")
	_bus = get_node_or_null("/root/EventBus")

	# Boundary walls occupy the WORLD collision layer from the single source of truth
	# (`CollisionLayers`), not scene magic numbers. They are static targets, so they detect
	# nothing (mask 0); the player's mask includes WORLD, so the player stays inside.
	for wall in $Walls.get_children():
		if wall is StaticBody2D:
			wall.collision_layer = CollisionLayers.WORLD
			wall.collision_mask = 0

	if _input != null:
		_input.call("set_gameplay_context")

	# The player's attack INTENT is resolved HERE (coordinator decides target + damage).
	_player.attack_requested.connect(_on_player_attack)
	_player.health_changed.connect(_on_entity_health_changed)
	_dummy.health_changed.connect(_on_entity_health_changed)

	if _bus != null and not _bus.is_connected("language_changed", _on_language_changed):
		_bus.connect("language_changed", _on_language_changed)

	_refresh_hud()


func _exit_tree() -> void:
	if _bus != null and _bus.is_connected("language_changed", _on_language_changed):
		_bus.disconnect("language_changed", _on_language_changed)


## Resolve a player attack intent: if the dummy is in range, the player hits it, and the
## dummy deterministically retaliates — demonstrating bidirectional health interaction.
## Both hits go through the ONE domain rule. Public so the E2E/sandbox tests can drive the
## exact same resolution the real intent triggers (no duplicated logic in tests).
func resolve_player_attack() -> void:
	if _player.is_dead() or _dummy.is_dead():
		return
	if _player.global_position.distance_to(_dummy.global_position) > SANDBOX_ATTACK_RANGE:
		return
	# Player hits dummy.
	var to_dummy: int = DamageRules.compute_hit(_player.get_attack_power(), _dummy.get_defense())
	_dummy.take_damage(to_dummy)
	# Dummy retaliates (deterministic; it does not act on its own — the coordinator drives
	# it to prove the player is damageable too). Skip if the dummy just died.
	if not _dummy.is_dead():
		var to_player: int = DamageRules.compute_hit(
			_dummy.get_attack_power(), _player.get_defense())
		_player.take_damage(to_player)
	_refresh_hud()


func _on_player_attack() -> void:
	resolve_player_attack()


func _on_entity_health_changed(_current: int, _maximum: int) -> void:
	_refresh_hud()


## Event-driven return-to-menu intent, resolved through InputService (never raw input).
func _unhandled_input(_event: InputEvent) -> void:
	if _input == null:
		return
	if _input.call("is_system_action_just_pressed", &"open_menu"):
		# Capture the viewport and mark the event handled BEFORE emitting: emitting
		# `return_to_menu_requested` lets the coordinator (Main) swap this scene out
		# synchronously, after which this node is out of the tree and `get_viewport()`
		# returns null. Guard against that so a mid-transition press can't crash.
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return_to_menu_requested.emit()


func _refresh_hud() -> void:
	var loc := get_node_or_null("/root/Localization")
	if loc == null or _hud_label == null:
		return
	var hint := String(loc.call("t", "UI_SANDBOX_HINT"))
	var player_label := String(loc.call("t", "UI_SANDBOX_PLAYER_HP"))
	var dummy_label := String(loc.call("t", "UI_SANDBOX_DUMMY_HP"))
	_hud_label.text = "%s\n%s %d/%d\n%s %d/%d" % [
		hint,
		player_label, _player.get_current_health(), _player.get_max_health(),
		dummy_label, _dummy.get_current_health(), _dummy.get_max_health(),
	]


func _on_language_changed(_language_code: String) -> void:
	_refresh_hud()
