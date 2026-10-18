extends Control
class_name UIBookPanel
## UIBookPanel — Aetheria presentation (THE centred book, UI-02).
##
## A modal reading surface in the middle of the screen: a scrim over the world, and one large
## framed page sized by the VIEWPORT (`UIPalette.BOOK_WIDTH_FRACTION` wide, between two equal
## `BOOK_SCREEN_INSET`s) — centred at 16:9 and 16:10 alike, never sized by what it holds. The
## satchel is its first content; the learned-knowledge book (ui-03) is the next.
##
## THE SHAPE, top to bottom: the title with the one close key beside it, the tab strip (only
## when there is more than one page), the page, then the page's keys. Only the page changes when
## a tab turns; everything else is pinned, so a long page scrolls inside itself (each page owns
## its scroll) and the keys are never cut by the frame.
##
## IT DECIDES NOTHING. It shows pages its owner hands it and turns between them on the move-left
## / move-right keys, read through `InputService.is_modal_action_just_pressed` while the owner
## holds a UI_MODAL context. Opening, closing and Esc belong to the owner (the HUD), which is the
## one place that knows what else is on screen; the close key shown here is the one it obeys.
##
## A SUBCLASS that reads more keys overrides `_process` and calls `super(delta)` first.

## The page shown changed (by a key or by `select_page`).
signal page_changed(index: int)

## The close key the header names: Esc steps back one level everywhere (PX-4).
const CLOSE_ACTION := &"open_menu"
const PREV_ACTION := &"move_left"
const NEXT_ACTION := &"move_right"
const KeyPromptScript := preload("res://src/presentation/ui/components/ui_prompt_row.gd")

var _loc: Node = null
var _input: Node = null
var _frame: PanelContainer
var _title: Label
var _close_row: UIPromptRow
var _tab_strip: HBoxContainer
var _tab_row: HBoxContainer
var _turn_row: UIPromptRow
var _pages: VBoxContainer
var _keys: Label
var _title_key: String = ""
var _tab_keys: Array[String] = []
var _current: int = 0


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ensure_built()
	set_process(false)
	refresh_book_text()


## An owner may hand the book its pages before it enters the tree: the frame is built on first
## need, once.
func _ensure_built() -> void:
	if _frame == null:
		_build()


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = UIPalette.BOOK_SCRIM
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# All four sides pinned to the screen: a fraction of the width, two equal insets of the
	# height. A long page cannot grow it; it scrolls inside (the bounded-box rule, D-034).
	_frame = PanelContainer.new()
	_frame.name = "BookFrame"
	_frame.add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.anchor_left = 0.5 - UIPalette.BOOK_WIDTH_FRACTION * 0.5
	_frame.anchor_right = 0.5 + UIPalette.BOOK_WIDTH_FRACTION * 0.5
	_frame.anchor_top = 0.0
	_frame.anchor_bottom = 1.0
	_frame.offset_left = 0.0
	_frame.offset_right = 0.0
	_frame.offset_top = UIPalette.BOOK_SCREEN_INSET
	_frame.offset_bottom = -UIPalette.BOOK_SCREEN_INSET
	_frame.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_frame.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_frame)

	var column := VBoxContainer.new()
	column.name = "BookColumn"
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(header)
	_title = _label(UIPalette.BOOK_TITLE_FONT_SIZE, UIPalette.COLOR_TITLE)
	_title.name = "Title"
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title)
	# ONE close key, where the eye ends the title line — the same key on every book.
	_close_row = KeyPromptScript.new() as UIPromptRow
	_close_row.name = "CloseKey"
	header.add_child(_close_row)

	_tab_strip = HBoxContainer.new()
	_tab_strip.name = "Tabs"
	_tab_strip.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	_tab_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_strip.visible = false
	column.add_child(_tab_strip)
	_tab_row = HBoxContainer.new()
	_tab_row.name = "TabRow"
	_tab_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_row.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_tab_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_strip.add_child(_tab_row)
	_turn_row = KeyPromptScript.new() as UIPromptRow
	_turn_row.name = "TurnKey"
	_tab_strip.add_child(_turn_row)

	column.add_child(UITheme.ornament_divider())
	_pages = VBoxContainer.new()
	_pages.name = "Pages"
	_pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_pages)
	column.add_child(UITheme.ornament_divider())
	_keys = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_ACCENT)
	_keys.name = "Keys"
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_keys)


## The book's title, as a localisation key (re-read on `refresh_book_text`).
func set_title_key(key: String) -> void:
	_title_key = key
	refresh_book_text()


## Add a page under a tab named by `title_key`; returns its index. The first page is shown.
func add_page(title_key: String, page: Control) -> int:
	_ensure_built()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pages.add_child(page)
	_tab_keys.append(title_key)
	_show_current()
	refresh_book_text()
	return _tab_keys.size() - 1


func page_count() -> int:
	return _tab_keys.size()


func current_page() -> int:
	return _current


func page(index: int) -> Control:
	if index < 0 or index >= _pages.get_child_count():
		return null
	return _pages.get_child(index) as Control


func select_page(index: int) -> void:
	if page_count() == 0:
		return
	var next := clampi(index, 0, page_count() - 1)
	if next == _current:
		return
	_current = next
	_show_current()
	refresh_book_text()
	page_changed.emit(_current)


## Turn by `step` pages (wraps), as the move-left / move-right keys do.
func turn_page(step: int) -> void:
	if page_count() > 1:
		select_page(posmod(_current + step, page_count()))


## The keys line under the page: the owner writes what ITS page's keys do.
func set_keys_text(text: String) -> void:
	_ensure_built()
	_keys.text = text


## The framed page itself (what a layout test measures; the layer is the whole screen).
func frame() -> PanelContainer:
	_ensure_built()
	return _frame


## Re-read every string the book owns (title, tabs, close and turn keys) in the current language.
func refresh_book_text() -> void:
	if _title == null:
		return
	_title.text = _t(_title_key) if _title_key != "" else ""
	_close_row.set_prompt(_key_label(CLOSE_ACTION), _t("UI_BOOK_CLOSE"))
	var turn_keys := "%s/%s" % [_key_label(PREV_ACTION), _key_label(NEXT_ACTION)]
	_turn_row.set_prompt(turn_keys, _t("UI_BOOK_TURN"))
	_tab_strip.visible = page_count() > 1
	for child in _tab_row.get_children():
		_tab_row.remove_child(child)
		child.queue_free()
	for index in page_count():
		_tab_row.add_child(_tab(_tab_keys[index], index == _current))


## Read the page keys while open (the owner turns processing on and off with visibility).
func _process(_delta: float) -> void:
	if _input == null or not visible or page_count() < 2:
		return
	if _input.call("is_modal_action_just_pressed", PREV_ACTION):
		turn_page(-1)
	elif _input.call("is_modal_action_just_pressed", NEXT_ACTION):
		turn_page(1)


func _show_current() -> void:
	_current = clampi(_current, 0, maxi(0, page_count() - 1))
	for index in _pages.get_child_count():
		(_pages.get_child(index) as Control).visible = index == _current


## A tab: its name, the chosen one lit like a chosen row and in the title's gold — never by
## colour alone, the lit plate marks it too (`UI_UX_BIBLE.md` §4).
func _tab(key: String, selected: bool) -> Control:
	var plate := PanelContainer.new()
	plate.add_theme_stylebox_override("panel", UITheme.selection_stylebox(selected))
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := _label(UIPalette.BOOK_TAB_FONT_SIZE,
		UIPalette.COLOR_TITLE if selected else UIPalette.COLOR_TEXT_MUTED)
	label.text = _t(key)
	plate.add_child(label)
	return plate


func _label(font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _key_label(action: StringName) -> String:
	return String(_input.call("get_action_display_label", action)) if _input != null else "?"


func _t(key: String) -> String:
	return String(_loc.call("t", key)) if _loc != null else key


## Localised text with `{placeholder}` substitution, for a subclass's keys line.
func _t_args(key: String, args: Dictionary) -> String:
	return String(_loc.call("t_args", key, args)) if _loc != null else key
