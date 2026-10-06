extends PanelContainer
class_name SkillDock
## SkillDock — Aetheria presentation (the learned techniques and the linh khí pool, Phase 15).
##
## Bottom-RIGHT, on the quiet hint band (`UI_UX_BIBLE.md` §3c weight ladder: the player TRACKS
## it, but it is not identity), opposite the prompt strip and clear of the bottom-centre
## announcements. Hidden until a technique is learned — a dock of empty slots is a promise the
## game cannot keep yet. Each slot: the skill's icon, its key, a cooldown shade draining from the
## top, and dimmed when it cannot be cast now (cooldown, not enough qi, a cast in flight). Under
## them, the linh khí bar — a gauge for a stat a system now owns (`SkillRuntime`).
##
## Compact by budget: the permanent HUD must stay under 15% of the screen; this adds ~0.5%.

const SLOT_PX := 32
const QI_BAR_HEIGHT := 6
const QI_FILL := Color(0.60, 0.86, 0.96)

var _slots: HBoxContainer
var _qi_bar: ProgressBar
var _input: Node = null
var _view: SkillView = null


func _ready() -> void:
	_input = get_node_or_null("/root/InputService")
	add_theme_stylebox_override("panel", UITheme.hint_band_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	add_child(box)
	_slots = HBoxContainer.new()
	_slots.name = "Slots"
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
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(SLOT_PX, SLOT_PX)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_SCALE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(icon)
	var shade := ColorRect.new()
	shade.name = "Cooldown"
	shade.color = Color(0, 0, 0, 0.6)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(shade)
	var key := Label.new()
	key.name = "Key"
	key.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	key.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	key.position = Vector2(1, -4)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(key)
	return slot


func _fill_slot(slot: Control, row: Dictionary) -> void:
	(slot.get_node("Icon") as TextureRect).texture = row["icon"]
	var total := float(row["cooldown_total"])
	var fraction := clampf(float(row["cooldown_left"]) / total, 0.0, 1.0) if total > 0.0 else 0.0
	var shade := slot.get_node("Cooldown") as ColorRect
	shade.position = Vector2.ZERO
	shade.size = Vector2(SLOT_PX, roundf(SLOT_PX * fraction))
	var action := StringName("skill_%d" % int(row["slot"]))
	(slot.get_node("Key") as Label).text = String(_input.call("get_action_display_label",
		action)) if _input != null else str(row["slot"])
	slot.modulate = Color.WHITE if bool(row["ready"]) else Color(0.6, 0.6, 0.65)
