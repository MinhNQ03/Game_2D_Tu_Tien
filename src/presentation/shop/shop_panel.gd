extends PanelContainer
class_name ShopPanel
## ShopPanel — Aetheria presentation (trading with a shopkeeper, Phase 17).
##
## A bounded side panel in the same frame and hierarchy as the satchel: title → who and how
## they price → your funds → the BUY / SELL tabs → rows (only these scroll) → the selected
## item's description → the outcome of the last request → the keys.
##
## KEYBOARD FIRST, through `InputService.is_modal_action_just_pressed` while the HUD holds a
## UI_MODAL context: move_up / move_down choose a row, move_left / move_right switch between
## buying and selling, `interact` trades ONE of the selected row. Closing (Esc) is the HUD's.
##
## It decides nothing. Every price shown is the one `ShopService` quoted into the `ShopView`;
## a press REQUESTS a trade (`buy_requested` / `sell_requested`) and the outcome comes back as
## a new view whose status line says what happened or why it did not.

signal buy_requested(item_id: StringName)
signal sell_requested(item_id: StringName)

enum Tab { BUY, SELL }

## The currency icon beside the funds, at the item sheets' native 16 px doubled.
const FUNDS_ICON_PX := 20

var _loc: Node = null
var _input: Node = null
var _title: Label
var _keeper: Label
var _terms: Label
var _funds_icon: TextureRect
var _funds: Label
var _tab_buy: Label
var _tab_sell: Label
var _list: VBoxContainer
var _scroll: ScrollContainer
var _empty: Label
var _desc: Label
var _status: Label
var _keys: Label
var _view: ShopView = null
var _tab: int = Tab.BUY
var _selected: int = 0
## The process frame the panel was last opened on. The key press that OPENED the shop (interact,
## on the keeper) is still "just pressed" for the rest of that frame; reading it here too would
## trade on the same press — so the panel reads no key until a later frame.
var _opened_frame: int = -1


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_title = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	_title.name = "Title"
	_title.clip_text = true
	column.add_child(_title)
	# Who, and on what terms — ONE line, so the rows below keep the height (the panel is a
	# bounded box between the plaque and the prompt strip; every header line costs a row).
	var who := HBoxContainer.new()
	who.name = "Who"
	who.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	column.add_child(who)
	_keeper = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
	_keeper.name = "Keeper"
	who.add_child(_keeper)
	_terms = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_terms.name = "Terms"
	_terms.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_terms.clip_text = true
	who.add_child(_terms)
	# The two sides on the left, the customer's funds on the right of the same line.
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	column.add_child(tabs)
	_tab_buy = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT)
	_tab_buy.name = "TabBuy"
	tabs.add_child(_tab_buy)
	_tab_sell = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT)
	_tab_sell.name = "TabSell"
	tabs.add_child(_tab_sell)
	_funds = _label(UIPalette.FONT_SIZE_BODY, UIPalette.GOLD_PRIMARY)
	_funds.name = "FundsText"
	_funds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_funds.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_funds.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tabs.add_child(_funds)
	_funds_icon = TextureRect.new()
	_funds_icon.name = "FundsIcon"
	_funds_icon.custom_minimum_size = Vector2(FUNDS_ICON_PX, FUNDS_ICON_PX)
	_funds_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_funds_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_funds_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_funds_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabs.add_child(_funds_icon)
	column.add_child(UITheme.ornament_divider())
	var box := UITheme.scroll_body(column)
	_scroll = box.get_parent().get_parent() as ScrollContainer
	_list = VBoxContainer.new()
	_list.name = "ShopRows"
	_list.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	box.add_child(_list)
	_empty = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT_MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_empty)
	column.add_child(UITheme.ornament_divider())
	_desc = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_desc.name = "Description"
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.max_lines_visible = 2
	column.add_child(_desc)
	_status = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)
	_keys = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	_keys.name = "Keys"
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_keys)
	set_process(false)
	refresh()


func set_view(view: ShopView) -> void:
	var reopened := view != null and view.open \
		and (_view == null or not _view.open or _view.shop_id != view.shop_id)
	_view = view
	if reopened:
		_tab = Tab.BUY
		_selected = 0
		_opened_frame = Engine.get_process_frames()
	refresh()


func tab() -> int:
	return _tab


func selected_index() -> int:
	return _selected


func rows() -> Array[Dictionary]:
	if _view == null:
		return [] as Array[Dictionary]
	return _view.buy_rows if _tab == Tab.BUY else _view.sell_rows


func selected_item_id() -> StringName:
	var shown := rows()
	if shown.is_empty():
		return &""
	return shown[clampi(_selected, 0, shown.size() - 1)]["item_id"]


## The status line as shown (for tests and the E2E).
func status_text() -> String:
	return _status.text if _status != null else ""


## Move the selection by `step` rows (wraps), as the move keys do.
func move_selection(step: int) -> void:
	var n := rows().size()
	if n == 0:
		return
	_selected = posmod(_selected + step, n)
	refresh()


## Show the buying or the selling side.
func set_tab(next: int) -> void:
	if next == _tab:
		return
	_tab = next
	_selected = 0
	refresh()


## Ask to trade ONE of the selected row.
func request_trade() -> void:
	var item_id := selected_item_id()
	if item_id == &"":
		return
	if _tab == Tab.BUY:
		buy_requested.emit(item_id)
	else:
		sell_requested.emit(item_id)


## Read the modal keys while open (the HUD turns processing on and off with visibility).
func _process(_delta: float) -> void:
	if _input == null or not visible or Engine.get_process_frames() <= _opened_frame:
		return
	if _input.call("is_modal_action_just_pressed", &"move_up"):
		move_selection(-1)
	elif _input.call("is_modal_action_just_pressed", &"move_down"):
		move_selection(1)
	elif _input.call("is_modal_action_just_pressed", &"move_left"):
		set_tab(Tab.BUY)
	elif _input.call("is_modal_action_just_pressed", &"move_right"):
		set_tab(Tab.SELL)
	elif _input.call("is_modal_action_just_pressed", &"interact"):
		request_trade()


func refresh() -> void:
	if _title == null:
		return
	for child in _list.get_children():
		child.queue_free()
	if _view == null or not _view.open:
		_title.text = ""
		return
	_title.text = _t(String(_view.name_key))
	_keeper.text = _t(String(_view.keeper_name_key))
	if _view.modifier_percent < 0:
		_terms.text = _t_args("UI_SHOP_TERMS_DISCOUNT", {"percent": -_view.modifier_percent})
		_terms.add_theme_color_override("font_color", UIPalette.COLOR_ACCENT)
	elif _view.modifier_percent > 0:
		_terms.text = _t_args("UI_SHOP_TERMS_MARKUP", {"percent": _view.modifier_percent})
		_terms.add_theme_color_override("font_color", UIPalette.COLOR_CRIMSON_HOVER)
	else:
		_terms.text = _t("UI_SHOP_TERMS_BASE")
		_terms.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	_funds_icon.texture = _view.currency_icon
	_funds.text = _t_args("UI_SHOP_FUNDS", {
		"currency": _t(String(_view.currency_name_key)), "count": _view.balance})
	_paint_tab(_tab_buy, "UI_SHOP_TAB_BUY", _tab == Tab.BUY)
	_paint_tab(_tab_sell, "UI_SHOP_TAB_SELL", _tab == Tab.SELL)
	var shown := rows()
	_selected = clampi(_selected, 0, maxi(0, shown.size() - 1))
	_empty.visible = shown.is_empty()
	_empty.text = _t("UI_SHOP_EMPTY_BUY" if _tab == Tab.BUY else "UI_SHOP_EMPTY_SELL")
	for i in shown.size():
		_list.add_child(_row(shown[i], i == _selected))
	if not shown.is_empty():
		_reveal_selected.call_deferred()
	_desc.text = "" if shown.is_empty() else _t(String(shown[_selected]["desc_key"]))
	_refresh_status(shown)
	_keys.text = _t_args("UI_SHOP_KEYS", {
		"trade": _key(&"interact"), "left": _key(&"move_left"), "right": _key(&"move_right"),
		"close": _key(&"open_menu")})


## The outcome of the last request; with none, WHY the selected row cannot be bought now.
func _refresh_status(shown: Array[Dictionary]) -> void:
	var key := _view.status_key
	var args := _view.status_args.duplicate()
	var refusal := _view.status_is_refusal
	if key == &"" and _tab == Tab.BUY and not shown.is_empty():
		key = shown[_selected]["reason_key"]
		refusal = true
	for k: Variant in args:
		if typeof(args[k]) == TYPE_STRING_NAME:
			args[k] = _t(String(args[k]))
	if not args.is_empty():
		args["currency"] = _t(String(_view.currency_name_key))
	_status.text = "" if key == &"" else (_t_args(String(key), args) if not args.is_empty()
		else _t(String(key)))
	_status.add_theme_color_override("font_color",
		UIPalette.COLOR_CRIMSON_HOVER if refusal else UIPalette.COLOR_ACCENT)


func _paint_tab(label: Label, key: String, active: bool) -> void:
	label.text = ("▸ %s" if active else "  %s") % _t(key)
	label.add_theme_color_override("font_color",
		UIPalette.COLOR_TITLE if active else UIPalette.COLOR_TEXT_MUTED)


func _reveal_selected() -> void:
	if _scroll == null or not is_inside_tree():
		return
	var live := _list.get_children().filter(func(c: Node) -> bool:
		return not c.is_queued_for_deletion())
	if _selected < live.size():
		_scroll.ensure_control_visible(live[_selected] as Control)


func _row(row: Dictionary, selected: bool) -> Control:
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(UIPalette.COLOR_ACCENT, 0.22) if selected else Color(0, 0, 0, 0)
	style.border_color = UIPalette.COLOR_ACCENT if selected else Color(0, 0, 0, 0)
	style.set_border_width_all(1 if selected else 0)
	style.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", style)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	frame.add_child(line)
	line.add_child(UITheme.icon_slot(row["icon"]))
	var buyable := _tab == Tab.SELL or StringName(row.get("reason_key", &"")) == &""
	var name_label := _label(UIPalette.FONT_SIZE_BODY,
		UIPalette.COLOR_TEXT if buyable else UIPalette.COLOR_TEXT_MUTED)
	name_label.text = _t(String(row["name_key"]))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name_label)
	# How many: what the shop has left (∞ when it never runs out), or what the customer holds.
	var count := _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	if _tab == Tab.SELL:
		count.text = "×%d" % int(row["held"])
	else:
		count.text = "∞" if int(row["stock"]) == ShopEntryData.UNLIMITED \
			else "×%d" % int(row["stock"])
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(count)
	# The price NOW, and the base price beside it whenever standing has moved it.
	var price := _label(UIPalette.FONT_SIZE_BODY, UIPalette.GOLD_PRIMARY)
	price.text = str(int(row["price"]))
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.custom_minimum_size = Vector2(22, 0)
	line.add_child(price)
	if int(row["base_price"]) != int(row["price"]):
		var base := _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_DISABLED)
		base.text = "(%d)" % int(row["base_price"])
		base.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(base)
	return frame


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _key(action: StringName) -> String:
	return String(_input.call("get_action_display_label", action)) if _input != null else "?"


func _t(key: String) -> String:
	return String(_loc.call("t", key)) if _loc != null else key


func _t_args(key: String, args: Dictionary) -> String:
	return String(_loc.call("t_args", key, args)) if _loc != null else key
