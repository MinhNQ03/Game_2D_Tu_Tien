extends Control
## SettingsMenu — Aetheria presentation (application settings screen, D-035).
##
## Currently one setting: the UI LANGUAGE (vi/en). It exists so a per-phase beta build can be
## play-tested in Vietnamese without editing code or config files (`01-product.md`: Vietnamese
## and English are both first-class from the foundation).
##
## Presentation only. It renders the choices, sends the chosen code to the `Localization`
## service, and emits `close_requested` — it decides NOTHING about navigation (Main owns
## that, like the MainMenu intents) and owns no persistence (Localization + SettingsStore do).
## The language buttons are built FROM `Localization.available_languages()`, so adding a third
## language is a CSV + one label key, with no change here (`07-localization.md`).
##
## It re-resolves its own text on `EventBus.language_changed`, so pressing a language button
## updates this screen live — the most direct confirmation the switch worked.

## The player is done with settings; Main should return to the menu.
signal close_requested()

## Localization key per supported language code. A code with no entry here falls back to
## showing the raw code, which is loud enough to notice in review but never crashes.
const LANGUAGE_LABEL_KEYS := {
	"vi": "UI_LANGUAGE_VI",
	"en": "UI_LANGUAGE_EN",
}

## Preferences on disk. This screen WRITES the choice (Main reads it at boot); the
## `Localization` service stays disk-free on purpose so unit tests cannot leave a stale
## language behind in `user://` (D-035).
const SettingsStoreScript := preload("res://src/infrastructure/settings_store.gd")

var _loc: Node = null
var _bus: Node = null

var _title: Label
var _hint: Label
var _back_button: Button
## language code -> Button, so `_refresh_text` can relabel and re-mark the active one.
var _language_buttons: Dictionary = {}


func _ready() -> void:
	# See the note in `main_menu.gd`: `set_anchors_preset` PRESERVES the current rect (0x0 for
	# a `.tscn` root Control with no authored size) instead of zeroing the offsets, so this
	# screen had the same crammed-into-the-corner defect. Always the and_offsets variant for a
	# full-rect screen.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = UITheme.build()
	_loc = get_node_or_null("/root/Localization")
	_bus = get_node_or_null("/root/EventBus")
	_build_ui()
	_refresh_text()

	# Settings is a menu-context screen: it must not let gameplay actions through.
	var input := get_node_or_null("/root/InputService")
	if input != null:
		input.call("set_menu_context")

	if _bus != null and not _bus.is_connected("language_changed", _on_language_changed):
		_bus.connect("language_changed", _on_language_changed)

	_back_button.grab_focus()


func _exit_tree() -> void:
	if _bus != null and _bus.is_connected("language_changed", _on_language_changed):
		_bus.disconnect("language_changed", _on_language_changed)


func _build_ui() -> void:
	# The SAME composed backdrop the menu wears, from the one builder (D-050). This screen
	# used to paint a flat `COLOR_BACKGROUND` fill, so the game had one composed screen and
	# one void — not because anybody chose that, but because the composition lived inside
	# `main_menu.gd` and was only reachable by copying it.
	#
	# A full backdrop rather than a translucent scrim over the menu: the menu's plaque is a
	# different height, so leaving it visible underneath put a second plaque frame around this
	# one and left the covered screen's title and Quit label legible around the edges. This is
	# a SCREEN in navigation terms — Main opens it, Main closes it, Back returns — so it is
	# composed like one.
	UITheme.build_backdrop(self)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	panel.custom_minimum_size = Vector2(UIPalette.MENU_PANEL_WIDTH, 0)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_title.add_theme_color_override("font_color", UIPalette.COLOR_TITLE)
	box.add_child(_title)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_hint.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	box.add_child(_hint)

	# One button per SUPPORTED language, read from the service so this screen never holds a
	# second copy of the language list (`07-localization.md`: adding a language is data).
	for code in _supported_languages():
		# Built through the ONE menu-button factory (D-050), so this screen wears the same
		# plate, size and interaction states as the menu. It used to roll its own bare
		# `Button` at a hand-typed width with no role, which is why all three actions here
		# rendered as identical untinted plates.
		var button := UITheme.menu_button(UITheme.ROLE_SECONDARY)
		button.pressed.connect(_on_language_chosen.bind(code))
		box.add_child(button)
		_language_buttons[code] = button

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, UIPalette.SPACE_MD)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_back_button = UITheme.menu_button(UITheme.ROLE_SECONDARY)
	_back_button.pressed.connect(_on_back)
	box.add_child(_back_button)


## Supported codes from the Localization service, or a safe literal pair if the service is
## absent (headless structural tests that build this screen without autoloads).
func _supported_languages() -> Array:
	if _loc != null and _loc.has_method("available_languages"):
		# Explicit cast: `call()` returns Variant, and returning a Variant where an Array is
		# declared is exactly the inferred/unsafe-type class of warning that fails the build
		# under warnings-as-errors (L-020).
		return _loc.call("available_languages") as Array
	return LANGUAGE_LABEL_KEYS.keys()


func _refresh_text() -> void:
	if _loc == null:
		return
	_title.text = String(_loc.call("t", "UI_SETTINGS_TITLE"))
	_hint.text = String(_loc.call("t", "UI_SETTINGS_LANGUAGE_HINT"))
	_back_button.text = String(_loc.call("t", "UI_SETTINGS_BACK"))

	var active := String(_loc.call("get_language"))
	for code in _language_buttons:
		var button: Button = _language_buttons[code]
		var key: String = String(LANGUAGE_LABEL_KEYS.get(code, ""))
		var label := String(_loc.call("t", key)) if key != "" else String(code)
		# TWO carriers for "this is the language in use", neither of them sufficient alone:
		#   * TEXT — a localized template, not the `> x <` ASCII brackets this used to print.
		#     Brackets are not a visual language, they shifted the label off-centre, and they
		#     are untranslatable punctuation wrapped around a translated name.
		#   * ROLE — the active button is promoted to PRIMARY, the same treatment New Game
		#     gets on the menu, so the choice is visible at a glance too.
		# Disabling the active one would drop it out of the focus order, so it stays pressable
		# (re-selecting is a harmless no-op).
		# Explicitly typed: `code` comes out of a Dictionary as Variant, so `code == active`
		# is a Variant comparison and `:=` would infer Variant — which this project promotes
		# to a compile error (L-020).
		var is_active: bool = String(code) == active
		button.text = String(_loc.call("t_args", "UI_SETTINGS_LANGUAGE_ACTIVE",
			{"language": label})) if is_active else label
		UITheme.apply_button_role(button,
			UITheme.ROLE_PRIMARY if is_active else UITheme.ROLE_SECONDARY)


func _on_language_chosen(code: String) -> void:
	if _loc == null:
		return
	# Localization validates the code and emits `language_changed` on the bus, which brings
	# us (and the menu underneath) back through `_refresh_text`.
	if not bool(_loc.call("set_language", code)):
		push_warning("[settings] language '%s' was rejected" % code)
		return
	# Remember the choice for the next launch. A failed write is warned by the store and is
	# non-fatal: the language still applied for this session.
	SettingsStoreScript.new().set_language(code)
	_refresh_text()


func _on_back() -> void:
	close_requested.emit()


func _on_language_changed(_language_code: String) -> void:
	_refresh_text()
