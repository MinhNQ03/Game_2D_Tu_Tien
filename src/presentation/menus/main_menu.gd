extends Control
## MainMenu — Aetheria presentation (main-menu shell).
##
## Functional, minimal, localized, non-polished (NOT the production UI). It offers a route
## to New Game and Quit; Load Game is a disabled placeholder (no save system in Phase 01).
##
## The menu does not know *why* a new game starts or *how* scenes load — it emits intent
## signals and the coordinator (Main) drives GameState + SceneRouter. All text is resolved
## from localization keys; no literal user-facing strings here.

signal new_game_pressed()
signal quit_pressed()

var _title: Label
var _new_game_button: Button
var _load_game_button: Button
var _quit_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_text()

	# Menu owns the MENU input context while shown (input gating ownership, §12).
	var input := get_node_or_null("/root/InputService")
	if input != null:
		input.call("reset_to", 1)  # Context.MENU == 1

	var bus := get_node_or_null("/root/EventBus")
	if bus != null and not bus.is_connected("language_changed", _on_language_changed):
		bus.connect("language_changed", _on_language_changed)


func _exit_tree() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.is_connected("language_changed", _on_language_changed):
		bus.disconnect("language_changed", _on_language_changed)


func _build_ui() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	_new_game_button = Button.new()
	_new_game_button.pressed.connect(_on_new_game)
	box.add_child(_new_game_button)

	_load_game_button = Button.new()
	_load_game_button.disabled = true  # No save system yet (Phase 23).
	box.add_child(_load_game_button)

	_quit_button = Button.new()
	_quit_button.pressed.connect(_on_quit)
	box.add_child(_quit_button)


func _refresh_text() -> void:
	var loc := get_node_or_null("/root/Localization")
	if loc == null:
		return
	_title.text = String(loc.call("t", "UI_MENU_TITLE"))
	_new_game_button.text = String(loc.call("t", "UI_MENU_NEW_GAME"))
	_load_game_button.text = String(loc.call("t", "UI_MENU_LOAD_GAME"))
	_quit_button.text = String(loc.call("t", "UI_MENU_QUIT"))


func _on_new_game() -> void:
	new_game_pressed.emit()


func _on_quit() -> void:
	quit_pressed.emit()


func _on_language_changed(_language_code: String) -> void:
	_refresh_text()
