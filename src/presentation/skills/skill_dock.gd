extends PanelContainer
class_name SkillDock
## SkillDock — Aetheria presentation (the learned techniques and the linh khí pool, Phase 15).
##
## BOTTOM-CENTRE (D-062): the player's hands are under the player. Below the playfield's clear
## zone and the announcement band, so it never covers the fight or a notice. Hidden until a
## technique is learned — a dock of empty slots is a promise the game cannot keep yet.
##
## Each slot is the kit's icon slot (`UITheme.slot_texture`) — the SAME family as the satchel's
## item slots — with an inner ring in the technique's ELEMENT hue, the icon in its well, the key
## on a keycap, and a cooldown shade draining from the top INSIDE the well (never over the gold
## frame). A slot that cannot be cast now (cooldown, not enough qi, a cast in flight) dims.
## Under the slots, the linh khí bar — a gauge for a stat a system owns (`SkillRuntime`).
##
## No plate of its own: the slots are framed objects, and a box around framed objects is the
## "four giant permanent boxes" the brief forbids. Compact by budget: the permanent HUD must
## stay under 15% of the screen.

const WELL_INSET := 4
const QI_BAR_HEIGHT := 8
const QI_FILL := Color(0.60, 0.86, 0.96)
const COOLDOWN_SHADE := Color(0.02, 0.03, 0.06, 0.72)

var _slots: HBoxContainer
var _qi_bar: ProgressBar
var _input: Node = null
var _view: SkillView = null


func _ready() -> void:
	_input = get_node_or_null("/root/InputService")
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	add_child(box)
	_slots = HBoxContainer.new()
	_slots.name = "Slots"
	_slots.alignment = BoxContainer.ALIGNMENT_CENTER
	_slots.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	box.add_child(_slots)
	_qi_bar = UITheme.qi_bar(QI_BAR_HEIGHT, QI_FILL)
	box.add_child(_qi_bar)
	visible = false
	refresh()


func set_view(view: SkillView) -> void:
	_view = view
	refresh()


func slot_count() -> int:
	return _view.slots.size() if _view != null else 0


func qi_shown() -> float:
	return _qi_bar.value if _qi_bar != null else 0.0


func refresh() -> void:
	if _slots == null:
		return
	visible = _view != null and not _view.slots.is_empty()
	if not visible:
		return
	_qi_bar.max_value = float(maxi(1, _view.qi_max))
	_qi_bar.value = _view.qi
	var rows := _view.slots
	while _slots.get_child_count() > rows.size():
		var last := _slots.get_child(_slots.get_child_count() - 1)
		_slots.remove_child(last)
		last.queue_free()
	while _slots.get_child_count() < rows.size():
		_slots.add_child(_make_slot())
	for i in rows.size():
		_fill_slot(_slots.get_child(i), rows[i])


func _make_slot() -> Control:
	# The kit's icon slot (the satchel's family), plus the dock's own cooldown shade and keycap.
	var slot := UITheme.icon_slot()
	var shade := ColorRect.new()
	shade.name = "Cooldown"
	shade.color = COOLDOWN_SHADE
	shade.position = Vector2(WELL_INSET, WELL_INSET)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(shade)
	# The key on a keycap, hanging off the slot's lower edge — the dock is read "press this".
	var cap := PanelContainer.new()
	cap.name = "KeyCap"
	cap.add_theme_stylebox_override("panel", UITheme.badge_stylebox())
	cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cap)
	var key := Label.new()
	key.name = "Key"
	key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_BADGE)
	key.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cap.add_child(key)
	return slot


func _fill_slot(slot: Control, row: Dictionary) -> void:
	UITheme.set_icon_slot(slot, row["icon"], StringName(row.get("element", &"")))
	var total := float(row["cooldown_total"])
	var fraction := clampf(float(row["cooldown_left"]) / total, 0.0, 1.0) if total > 0.0 else 0.0
	var well := float(UIPalette.SLOT_PX - WELL_INSET * 2)
	var shade := slot.get_node("Cooldown") as ColorRect
	shade.size = Vector2(well, roundf(well * fraction))
	shade.visible = fraction > 0.0
	var action := StringName("skill_%d" % int(row["slot"]))
	var cap := slot.get_node("KeyCap") as PanelContainer
	(cap.get_node("Key") as Label).text = String(_input.call("get_action_display_label",
		action)) if _input != null else str(row["slot"])
	cap.reset_size()
	cap.position = Vector2(UIPalette.SLOT_PX - cap.size.x + UIPalette.SPACE_SM,
		UIPalette.SLOT_PX - cap.size.y * 0.5)
	slot.modulate = Color.WHITE if bool(row["ready"]) else Color(0.6, 0.6, 0.65)
