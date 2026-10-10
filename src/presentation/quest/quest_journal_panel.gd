extends PanelContainer
class_name QuestJournalPanel
## QuestJournalPanel — Aetheria presentation (the quest journal, Phase 19).
##
## A READING panel in the shared side-panel frame, opened and closed on the semantic
## `quest_journal` action. NOT modal: it takes no input context, the player keeps walking
## with it open, and it closes with every other reading surface when a hostile turns on the
## player (audit AUD-15: no fifth hand-copied modal).
##
## It renders a read-only `QuestJournalView` and resolves localization keys. PURE
## PRESENTATION: it holds no quest truth and decides nothing — a quest is taken, answered or
## given back by talking to its person, never from here.
##
## WHAT IT SHOWS, MOST URGENT FIRST: what is ready to answer, then what is under way, then
## what is on offer, then (one line each) what is done. For each: its name and state IN
## WORDS, the next thing to do, why it matters, who asked, each objective with its count, and
## what it pays.

## Reading order by `QuestService.Phase`: READY, ACTIVE, AVAILABLE, COMPLETED.
const PHASE_ORDER := {
	QuestService.Phase.READY: 0,
	QuestService.Phase.ACTIVE: 1,
	QuestService.Phase.AVAILABLE: 2,
	QuestService.Phase.COMPLETED: 3,
}

var _loc: Node = null
var _input: Node = null
var _title: Label
var _list: VBoxContainer
var _empty: Label
var _keys: Label
var _view: QuestJournalView = null


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title == null:
		_build()
	_refresh()


func _build() -> void:
	# Title and keys are PINNED; only the entries scroll (a long journal on a short screen
	# must scroll inside the bounded box, never push the frame off-screen — D-050).
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	add_child(column)
	_title = _label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	column.add_child(_title)
	column.add_child(UITheme.ornament_divider())
	var body := PanelContainer.new()
	body.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	_list = UITheme.scroll_body(body)
	_list.name = "Entries"
	_list.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_empty = _label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT_MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_empty)
	_keys = _label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	_keys.name = "Keys"
	column.add_child(_keys)


## Push a fresh view (event-driven from the quest owner; never polled).
func set_view(view: QuestJournalView) -> void:
	_view = view
	_refresh()


## The titles shown, in reading order — for tests and captures.
func shown_quest_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if _list != null:
		for block in _list.get_children():
			if not block.is_queued_for_deletion() and block.has_meta("quest_id"):
				out.append(block.get_meta("quest_id"))
	return out


## Every line of text one quest's block shows — for tests.
func block_text(quest_id: StringName) -> String:
	var lines: PackedStringArray = []
	if _list != null:
		for block in _list.get_children():
			if block.is_queued_for_deletion() or block.get_meta("quest_id", &"") != quest_id:
				continue
			for label in block.find_children("*", "Label", true, false):
				lines.append((label as Label).text)
	return "\n".join(lines)


func refresh_language() -> void:
	_refresh()


func _refresh() -> void:
	if _title == null:
		return
	_title.text = _t("UI_QUEST_JOURNAL_TITLE")
	_keys.text = _t_args("UI_QUEST_JOURNAL_KEYS", {"close": _key_label(&"quest_journal")})
	for stale in _list.get_children():
		_list.remove_child(stale)
		stale.queue_free()
	var entries: Array[Dictionary] = []
	if _view != null and _view.available:
		entries = _view.entries.duplicate()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(PHASE_ORDER.get(int(a["phase"]), 9)) < int(PHASE_ORDER.get(int(b["phase"]), 9)))
	for i in entries.size():
		if i > 0:
			_list.add_child(UITheme.ornament_divider())
		_list.add_child(_block(entries[i]))
	_empty.visible = entries.is_empty()
	_empty.text = _t("UI_QUEST_JOURNAL_EMPTY")


func _block(entry: Dictionary) -> VBoxContainer:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	block.set_meta("quest_id", entry["quest_id"])
	var phase := int(entry["phase"])
	var done := phase == QuestService.Phase.COMPLETED
	# LEVEL 2: the quest's name — and its state as a WORD beside it, never colour alone.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	block.add_child(head)
	var title := _label(UIPalette.FONT_SIZE_BODY,
		UIPalette.COLOR_TEXT_MUTED if done else UIPalette.COLOR_TITLE)
	title.text = _t(String(entry["title_key"]))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(title)
	var state := _label(UIPalette.FONT_SIZE_HINT, _phase_color(phase))
	state.text = _t(_phase_key(phase, bool(entry["owed"])))
	state.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(state)
	if done:
		return block
	# LEVEL 3: the next thing to do — the one line about the player.
	if entry["hint_key"] != &"":
		var hint := _wrapped(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_ACCENT)
		hint.text = _t(String(entry["hint_key"]))
		block.add_child(hint)
	# LEVEL 5: why it matters, once it is the player's business.
	if phase != QuestService.Phase.AVAILABLE:
		var why := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
		why.text = _t(String(entry["summary_key"]))
		block.add_child(why)
		_add_objectives(block, entry)
	var who := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	who.text = _t_args("UI_QUEST_FROM", {"name": _t(String(entry["giver_name_key"]))})
	if entry["receiver_name_key"] != entry["giver_name_key"]:
		who.text += "\n" + _t_args("UI_QUEST_ANSWER_TO",
			{"name": _t(String(entry["receiver_name_key"]))})
	block.add_child(who)
	var pays := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	pays.text = _t_args("UI_QUEST_REWARD", {"list": _reward_text(entry)})
	block.add_child(pays)
	return block


func _add_objectives(block: VBoxContainer, entry: Dictionary) -> void:
	var objectives: Array = entry["objectives"]
	if bool(entry["any"]) and objectives.size() > 1:
		var either := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
		either.text = _t("UI_QUEST_ANY_OF")
		block.add_child(either)
	for objective: Dictionary in objectives:
		var met := bool(objective["met"])
		var line := _wrapped(UIPalette.FONT_SIZE_HINT,
			UIPalette.COLOR_ACCENT if met else UIPalette.COLOR_TEXT)
		var text := _t(String(objective["text_key"]))
		if int(objective["required"]) > 1:
			text = _t_args("UI_QUEST_OBJECTIVE_COUNT", {"text": text,
				"value": int(objective["value"]), "required": int(objective["required"])})
		# Met is said in WORDS as well as in colour.
		line.text = "· " + (_t_args("UI_QUEST_OBJECTIVE_MET", {"text": text}) if met else text)
		block.add_child(line)


func _reward_text(entry: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: Dictionary in entry["reward_items"]:
		parts.append(_t_args("UI_QUEST_REWARD_ITEM",
			{"name": _t(String(item["name_key"])), "count": int(item["count"])}))
	if int(entry["reward_xp"]) > 0:
		parts.append(_t_args("UI_QUEST_REWARD_XP", {"xp": int(entry["reward_xp"])}))
	if int(entry["reward_regard_delta"]) != 0:
		parts.append(_t_args("UI_QUEST_REWARD_REGARD", {
			"name": _t(String(entry["reward_regard_name_key"])),
			"dimension": _t("UI_REL_DIM_%s"
				% String(entry["reward_regard_dimension"]).to_upper())}))
	return " · ".join(parts)


func _phase_key(phase: int, owed: bool) -> String:
	if owed:
		return "UI_QUEST_PHASE_OWED"
	match phase:
		QuestService.Phase.ACTIVE:
			return "UI_QUEST_PHASE_ACTIVE"
		QuestService.Phase.READY:
			return "UI_QUEST_PHASE_READY"
		QuestService.Phase.COMPLETED:
			return "UI_QUEST_PHASE_COMPLETED"
	return "UI_QUEST_PHASE_AVAILABLE"


func _phase_color(phase: int) -> Color:
	match phase:
		QuestService.Phase.READY:
			return UIPalette.COLOR_ACCENT
		QuestService.Phase.ACTIVE:
			return UIPalette.COLOR_TEXT
	return UIPalette.COLOR_TEXT_MUTED


func _wrapped(size: int, color: Color) -> Label:
	var label := _label(size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _key_label(action: StringName) -> String:
	if _input != null and _input.has_method("get_action_display_label"):
		return String(_input.call("get_action_display_label", action))
	return String(action)


func _t(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))


func _t_args(key: String, args: Dictionary) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t_args", key, args))
