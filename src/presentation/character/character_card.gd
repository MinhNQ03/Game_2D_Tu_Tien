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
## IN THE SATCHEL THE PERSON IS THE SUBJECT (docs/VISUAL_CRAFT_WORKFLOW.md, proof U1): the
## figure a step larger, on a stage the whole width of the column, standing on a dais. The
## stage is as tall as the frame at that scale plus the plate's own edge.
const STAGE_FIGURE_SCALE := 3
const STAGE_HEIGHT := 164.0
## How far below the stage's content edge the feet rest (inside the plate's padding).
const FEET_INSET := float(UIPalette.SPACE_SM)
## The dais under the figure, in the figure's own pixels (half-widths), and its contact shadow.
const DAIS_RADIUS := Vector2(15.0, 4.0)
const SHADOW_RADIUS := Vector2(13.0, 3.0)
const ELLIPSE_POINTS := 24
## Between a number and its name on a stat plate.
const STAT_PAIR_GAP := 4
## The least width a slot's name is laid out at (the figure column less its slot).
const SLOT_NAME_MIN_WIDTH := 84.0
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
	well.size_flags_horizontal = Control.SIZE_FILL if tall else Control.SIZE_SHRINK_CENTER
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
	well.custom_minimum_size = Vector2(0.0, STAGE_HEIGHT) if tall else WELL_SIZE
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
	_figure.scale = Vector2(figure_scale(), figure_scale())
	anchor.add_child(_figure)
	# the stage is as wide as the column GIVES it, known only once it is laid out
	anchor.resized.connect(_place_figure.bind(anchor))
	_place_figure(anchor)
	if _profile != null:
		_figure.setup(_profile)
	return well


## What the figure stands on: a soft contact shadow, so it stands IN the well and not on it.
func _draw_floor(floor: Control) -> void:
	if _figure == null:
		return
	var feet := _figure.position
	var unit := float(figure_scale())
	if tall:
		# a dais: ground to stand on, a tone above the plate, with one lit rim on its far side
		var dais := _ellipse(feet, DAIS_RADIUS * unit)
		floor.draw_colored_polygon(dais, UIPalette.FIGURE_DAIS)
		floor.draw_polyline(dais.slice(ELLIPSE_POINTS / 2, ELLIPSE_POINTS + 1),
			UIPalette.FIGURE_DAIS_RIM, 1.0)
	floor.draw_colored_polygon(_ellipse(feet, SHADOW_RADIUS * unit),
		UIPalette.FIGURE_CONTACT_SHADOW)


## A closed ellipse (first point repeated last), starting at its right and going by the near
## side first — so its second half is the far rim.
func _ellipse(centre: Vector2, radius: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for index in ELLIPSE_POINTS + 1:
		var angle := TAU * float(index) / float(ELLIPSE_POINTS)
		points.append(centre + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	return points


## The figure's feet rest on the node origin: the origin goes to the middle of the stage's
## floor. (The first card placed it from the well's OUTER size, 8 px right of the middle of
## what it stood in — measured by `test_the_satchels_figure_is_the_largest_...`.)
func _place_figure(floor: Control) -> void:
	if _figure == null:
		return
	if tall:
		_figure.position = Vector2(floor.size.x * 0.5, floor.size.y + FEET_INSET)
	else:
		_figure.position = Vector2(WELL_SIZE.x * 0.5, WELL_SIZE.y - UIPalette.SPACE_MD) \
			- Vector2(UIPalette.SPACE_SM, UIPalette.SPACE_SM)
	floor.queue_redraw()


func _build_slot_row(slot: int) -> Control:
	var row := HBoxContainer.new()
	row.name = "Slot%d" % slot
	row.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := UITheme.icon_slot(null)
	_slots[slot] = frame
	row.add_child(frame)
	var name_label := _label(_caption_size(), UIPalette.COLOR_TEXT_MUTED)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# A name WRAPS (two lines stand beside one slot); it is never cut. The first English
	# capture read "Travelling c..." here.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# An autowrap label measures its height at the width it HAS; with none yet it would stand
	# one letter wide and a page tall. This is the least the satchel's column leaves it.
	name_label.custom_minimum_size.x = SLOT_NAME_MIN_WIDTH
	_slot_names[slot] = name_label
	row.add_child(name_label)
	return row


## Three numbers, each beside its own name. In a band: a row of plates. In the satchel's
## column: a ledger — names down the left, numbers down the right on one edge, so the eye
## reads the numbers as a column instead of hunting for each in the middle of its own plate.
func _build_stats() -> Control:
	if tall:
		return _build_stat_ledger()
	var row := BoxContainer.new()
	row.name = "Stats"
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


func _build_stat_ledger() -> Control:
	var plate := PanelContainer.new()
	plate.name = "Stats"
	plate.add_theme_stylebox_override("panel", UITheme.inset_stylebox())
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(rows)
	for index in STAT_KEYS.size():
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", STAT_PAIR_GAP)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(pair)
		var caption := _label(_caption_size(), UIPalette.COLOR_TEXT_MUTED)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.add_child(caption)
		var value := _label(UIPalette.BOOK_ROW_FONT_SIZE, UIPalette.GOLD_PRIMARY)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pair.add_child(value)
		_stat_values.append(value)
		_stat_names.append(caption)
	return plate


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


## How many lines a slot's name takes, and how many of them are shown (equal = nothing cut).
func slot_name_lines(slot: int) -> Vector2i:
	var label := _slot_names[slot] as Label
	return Vector2i(label.get_line_count(), label.get_visible_line_count())


## True when a slot's name is drawn WHOLE: nothing clips or trims it, and wrapped at the width
## the label really has, no line of it is wider than that width.
func slot_name_is_whole(slot: int) -> bool:
	var label := _slot_names[slot] as Label
	if label.clip_text or label.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING:
		return false
	var font := label.get_theme_font(&"font")
	var wrapped := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT,
		label.size.x, label.get_theme_font_size(&"font_size"))
	return wrapped.x <= label.size.x + 0.5


## The integer scale the figure is drawn at in this card.
func figure_scale() -> int:
	return STAGE_FIGURE_SCALE if tall else FIGURE_SCALE


## The plate the figure stands in, on the screen.
func stage_rect() -> Rect2:
	return (_figure.get_parent().get_parent() as Control).get_global_rect()


## The figure's whole frame as drawn, on the screen (its feet are its node's origin).
func figure_rect() -> Rect2:
	if _profile == null:
		return Rect2()
	var frame := Vector2(_profile.frame_size) * float(figure_scale())
	return Rect2(_figure.global_position - Vector2(frame.x * 0.5, frame.y), frame)


## Where each number ENDS on the screen (x of its right edge): equal when they stand in a column.
func stat_value_right_edges() -> Array[float]:
	var out: Array[float] = []
	for label in _stat_values:
		out.append(label.get_global_rect().end.x)
	return out


## True when every stat's name is drawn whole at the width it was given.
func stat_names_are_whole() -> bool:
	for label in _stat_names:
		if label.clip_text or label.get_minimum_size().x > label.size.x + 0.5:
			return false
	return true


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


## A slot's name and a stat's name. In the satchel's column (the centred book, UI-02) they are
## read beside the book's own rows, so they stand at the body size there; a band across a page
## keeps the hint size it was laid out at.
func _caption_size() -> int:
	return UIPalette.FONT_SIZE_BODY if tall else UIPalette.FONT_SIZE_HINT


func _label(size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _t(key: String) -> String:
	return String(_loc.call("t", key)) if _loc != null else key
