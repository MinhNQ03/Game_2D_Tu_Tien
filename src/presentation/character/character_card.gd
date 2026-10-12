extends BoxContainer
class_name CharacterCard
## CharacterCard — Aetheria presentation (the character as a figure, not a list; the UI refresh
## that follows D-073).
##
## The body the player chose, DRAWN and breathing, standing in a well between the two things
## it can wear — what is in the hand and what is on the back — with the three numbers combat
## reads beside it. It is the head of the satchel and of the Chronicle's body page: one
## control, so both show the same person.
##
## IT OWNS NOTHING AND DECIDES NOTHING. Everything arrives as a view some owner built: the
## body's visual profile and the worn rows from `InventoryView`, the numbers from
## `ChronicleView` (the player's own stat component). An empty slot says what it is for.
##
## THE FIGURE IS THE GAME'S OWN SPRITE, at an integer scale (pixel art is never resampled) —
## the same `CharacterVisualComponent` the world and the identity screen draw with, so the
## garment shown here is the garment worn there. It idles on its own clock and costs nothing
## while the card is hidden (`_notification`).

## The figure's integer scale, and the well it stands in (a 32x48 body at 2x is 64x96).
const FIGURE_SCALE := 2
const WELL_SIZE := Vector2(76, 116)
## Between a number and its name on a stat plate.
const STAT_PAIR_GAP := 4
## What a slot is called when nothing is in it, by `EquipmentData.Slot`.
const SLOT_CAPTIONS := {
	EquipmentData.Slot.WEAPON: "UI_SHEET_SLOT_WEAPON",
	EquipmentData.Slot.BODY: "UI_SHEET_SLOT_BODY",
}
const STAT_KEYS: Array[String] = ["UI_SHEET_ATTACK", "UI_SHEET_DEFENSE", "UI_SHEET_SPEED"]
const VisualComponentScript := preload(
	"res://src/presentation/characters/character_visual_component.gd")

## Set BEFORE the card enters the tree. False (the default): the figure beside its slots and
## numbers — a band across a page (the Chronicle). True: the figure above them — a column
## beside a list (the satchel).
var tall: bool = false

var _loc: Node = null
var _figure: CharacterVisualComponent = null
var _profile: CharacterVisualProfileData = null
var _slots: Dictionary = {}          # slot -> icon slot Control
var _slot_names: Dictionary = {}     # slot -> Label
var _worn: Dictionary = {}           # slot -> name_key (StringName), what is shown now
var _worn_icons: Dictionary = {}     # slot -> Texture2D
var _stat_values: Array[Label] = []
var _stat_names: Array[Label] = []
var _stats: Array[int] = []


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	vertical = tall
	add_theme_constant_override("separation", UIPalette.SPACE_MD)
	var well := _build_well()
	well.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	well.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(well)
	var side := VBoxContainer.new()
	side.name = "Side"
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	side.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(side)
	for slot: int in [EquipmentData.Slot.WEAPON, EquipmentData.Slot.BODY]:
		side.add_child(_build_slot_row(slot))
	side.add_child(_build_stats())
	_refresh_text()
	_sync_figure()


## The well: an inset plate with the figure standing on its floor.
func _build_well() -> Control:
	var well := PanelContainer.new()
	well.name = "Well"
	well.custom_minimum_size = WELL_SIZE
	well.add_theme_stylebox_override("panel", UITheme.inset_stylebox())
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.clip_contents = true
	var anchor := Control.new()
	anchor.name = "Floor"
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.draw.connect(_draw_floor.bind(anchor))
	well.add_child(anchor)
	_figure = VisualComponentScript.new() as CharacterVisualComponent
	_figure.name = "Figure"
	_figure.scale = Vector2(FIGURE_SCALE, FIGURE_SCALE)
	anchor.add_child(_figure)
	_place_figure()
	if _profile != null:
		_figure.setup(_profile)
	return well


## What the figure stands on: a soft contact shadow, so it stands IN the well and not on it.
func _draw_floor(floor: Control) -> void:
	if _figure == null:
		return
	var feet := _figure.position
	var radius := Vector2(13.0 * FIGURE_SCALE, 3.0 * FIGURE_SCALE)
	var points := PackedVector2Array()
	for index in 20:
		var angle := TAU * float(index) / 20.0
		points.append(feet + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	floor.draw_colored_polygon(points, UIPalette.FIGURE_CONTACT_SHADOW)


## The figure's feet rest on the node origin, so the origin sits at the well's floor centre.
func _place_figure() -> void:
	if _figure != null:
		_figure.position = Vector2(WELL_SIZE.x * 0.5, WELL_SIZE.y - UIPalette.SPACE_MD) \
			- Vector2(UIPalette.SPACE_SM, UIPalette.SPACE_SM)


func _build_slot_row(slot: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Slot%d" % slot
	row.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := UITheme.icon_slot(null)
	_slots[slot] = frame
	row.add_child(frame)
	var name_label := _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	_slot_names[slot] = name_label
	row.add_child(name_label)
	return row


## Three numbers, each beside its own name: read as a row of plates, not as a sentence.
func _build_stats() -> Control:
	var row := BoxContainer.new()
	row.name = "Stats"
	row.vertical = tall
	row.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for index in STAT_KEYS.size():
		var plate := PanelContainer.new()
		plate.add_theme_stylebox_override("panel", UITheme.badge_stylebox(true))
		plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pair := HBoxContainer.new()
		pair.alignment = BoxContainer.ALIGNMENT_CENTER
		pair.add_theme_constant_override("separation", STAT_PAIR_GAP)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		plate.add_child(pair)
		var caption := _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
		pair.add_child(caption)
		var value := _label(UIPalette.FONT_SIZE_HINT, UIPalette.GOLD_PRIMARY)
		pair.add_child(value)
		_stat_values.append(value)
		_stat_names.append(caption)
		row.add_child(plate)
	return row


# === What it is told =========================================================

## The body as it is drawn in the world now (the chosen look, in whatever it wears).
func set_body(profile: CharacterVisualProfileData) -> void:
	if profile == _profile:
		return
	_profile = profile
	if _figure != null and profile != null:
		_figure.setup(profile)
	_sync_figure()


## What is worn, from the satchel's own rows (`InventoryView.rows`, the `equipped` ones).
func set_worn(rows: Array[Dictionary]) -> void:
	_worn.clear()
	_worn_icons.clear()
	for row in rows:
		if bool(row.get("equipped", false)) and row.has("slot"):
			_worn[int(row["slot"])] = row["name_key"]
			_worn_icons[int(row["slot"])] = row["icon"]
	_refresh_text()


## The numbers combat reads (`ChronicleView`). `available` false shows a dash, not a zero.
func set_stats(available: bool, attack: int, defense: int, speed: int) -> void:
	var told: Array[int] = []
	if available:
		told = [attack, defense, speed]
	_stats = told
	_refresh_text()


func refresh_language() -> void:
	_refresh_text()


# === Readouts (tests) ========================================================

func figure() -> CharacterVisualComponent:
	return _figure


func body_profile() -> CharacterVisualProfileData:
	return _profile


## What a slot says: the worn thing's name, or what the slot is for.
func slot_text(slot: int) -> String:
	return (_slot_names[slot] as Label).text if _slot_names.has(slot) else ""


## The icon DRAWN in a slot now (null when empty) — read back from the control itself.
func slot_icon(slot: int) -> Texture2D:
	if not _slots.has(slot):
		return null
	return ((_slots[slot] as Control).get_node("Icon") as TextureRect).texture


func slot_is_filled(slot: int) -> bool:
	return _worn.has(slot)


func stat_texts() -> Array[String]:
	var out: Array[String] = []
	for label in _stat_values:
		out.append(label.text)
	return out


# === Internals ===============================================================

## Everything the card was told, onto its controls. Safe before `_ready` (a card may be fed
## before it enters the tree: there is then nothing to write to yet, and `_ready` calls this).
func _refresh_text() -> void:
	for slot: int in _slots:
		UITheme.set_icon_slot(_slots[slot], _worn_icons.get(slot) as Texture2D)
	for slot: int in _slot_names:
		var label := _slot_names[slot] as Label
		var filled := _worn.has(slot)
		label.text = _t(String(_worn[slot])) if filled else _t(String(SLOT_CAPTIONS[slot]))
		label.add_theme_color_override("font_color",
			UIPalette.COLOR_TEXT if filled else UIPalette.COLOR_TEXT_MUTED)
	for index in _stat_values.size():
		_stat_values[index].text = str(_stats[index]) if index < _stats.size() else "—"
		_stat_names[index].text = _t(STAT_KEYS[index])


## The figure breathes only while it can be seen: a card in a closed panel costs nothing per
## frame (`05-performance-testing.md`; the HUD's settled-frame test holds every panel to it).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_figure()


func _sync_figure() -> void:
	if _figure != null:
		_figure.set_process(is_visible_in_tree() and _profile != null)


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _t(key: String) -> String:
	return String(_loc.call("t", key)) if _loc != null else key
