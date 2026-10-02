extends Node2D
## PrologueShell — Aetheria presentation (first-scene shell).
##
## A MINIMAL, NON-GAMEPLAY content scene that proves the Core framework works end to end:
## SceneRouter loaded it, GameState holds the session, InputService gates input, and the
## scene lifecycle (_ready / _exit_tree) is clean. There is NO gameplay here — no player,
## no movement, no combat.
##
## It sets the input context to GAMEPLAY on enter and listens (event-driven, not per-frame)
## for the `open_menu` system action to return to the menu, demonstrating the input-gating
## ownership and a safe transition back.

signal return_to_menu_requested()

var _label: Label


func _ready() -> void:
	# Build a tiny localized label purely to show localization works in a content scene.
	# (Presentation only — this renders a view, it owns no gameplay/authoritative state.)
	var layer := CanvasLayer.new()
	add_child(layer)
	_label = Label.new()
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	layer.add_child(_label)
	_refresh_text()

	# This scene represents active gameplay context for input gating.
	var input := get_node_or_null("/root/InputService")
	if input != null:
		input.call("set_gameplay_context")

	# React to language changes while shown.
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and not bus.is_connected("language_changed", _on_language_changed):
		bus.connect("language_changed", _on_language_changed)


func _exit_tree() -> void:
	# Clean up our EventBus subscription so no dangling signal survives the scene.
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.is_connected("language_changed", _on_language_changed):
		bus.disconnect("language_changed", _on_language_changed)


## Event-driven input (no per-frame polling): pressing the `open_menu` system action asks
## to return to the menu. Input intent is resolved through InputService (the owner of
## input gating / semantic actions, §12), NOT by matching physical events here — the scene
## never reads raw input vocabulary directly. The scene does not perform the transition
## itself; it signals, and the coordinator (Main) decides, keeping "why we move" out of
## the scene.
func _unhandled_input(_event: InputEvent) -> void:
	var input := get_node_or_null("/root/InputService")
	if input == null:
		return
	if input.call("is_system_action_just_pressed", &"open_menu"):
		return_to_menu_requested.emit()
		get_viewport().set_input_as_handled()


func _refresh_text() -> void:
	var loc := get_node_or_null("/root/Localization")
	if loc != null and _label != null:
		var title := String(loc.call("t", "UI_PROLOGUE_PLACEHOLDER"))
		var hint := String(loc.call("t", "UI_PROLOGUE_HINT"))
		_label.text = "%s\n\n%s" % [title, hint]


func _on_language_changed(_language_code: String) -> void:
	_refresh_text()
