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
## what is on offer, then (one line each) what is done. Every quest shows its name, its state
## IN WORDS and the next thing to do. ONE quest at a time — the one in FOCUS — is opened out:
## why it matters, each objective with its count, and what it pays.
##
## WHY ONE AT A TIME. The box is bounded by the screen (it must not cover the place plaque or
## the prompt strip), and at 1280×720 two opened-out quests do not fit it. A reading panel
## takes no keys of its own, so content below the fold could be reached only with a mouse
## wheel — which is how the first capture of this panel showed one quest and hid the other.
## Instead nothing is ever below the fold: the journal's OWN key steps the focus to the next
## quest, and closes the journal after the last.

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
## The quest opened out, by id (so a view change keeps the reader on the quest they were
## reading); empty = the first one.
var _focus: StringName = &""


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


## Open the journal on the most urgent quest.
func reset_focus() -> void:
	_focus = &""
	_refresh()


## Step the focus to the next quest that can be opened out. False when the focused quest is
## the last one — the caller closes the journal.
func advance_focus() -> bool:
	var order := _focusable(_ordered())
	var at := order.find(_focused_id(order))
	if at < 0 or at + 1 >= order.size():
		return false
	_focus = order[at + 1]
	_refresh()
	return true


## The quest currently opened out, or empty when there is none.
func focused_quest_id() -> StringName:
	return _focused_id(_focusable(_ordered()))


## True when every entry is fully inside the box: nothing is below the fold.
func fits_without_scrolling() -> bool:
	return overflow_px() <= 0.5


## How far the entries run past the bottom of the box (<= 0 = they fit). For tests.
func overflow_px() -> float:
	var node: Node = _list
	while node != null and not (node is ScrollContainer):
		node = node.get_parent()
	var scroll := node as ScrollContainer
	if scroll == null or scroll.size.y <= 0.0 or scroll.get_child_count() == 0:
		return INF
	# The LAID-OUT height of what the box scrolls: a wrapped label's minimum size does not
	# count its wrapped rows until it has been given its width, so the minimum size
	# under-reports exactly the case this exists to catch.
	return (scroll.get_child(0) as Control).size.y - scroll.size.y


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
	for stale in _list.get_children():
		_list.remove_child(stale)
		stale.queue_free()
	var entries := _ordered()
	var order := _focusable(entries)
	var focused := _focused_id(order)
	for i in entries.size():
		if i > 0:
			_list.add_child(UITheme.ornament_divider())
		_list.add_child(_block(entries[i], entries[i]["quest_id"] == focused))
	_empty.visible = entries.is_empty()
	_empty.text = _t("UI_QUEST_JOURNAL_EMPTY")
	# The journal's key says what it will do NEXT: open out the following quest, or close.
	var key := _key_label(&"quest_journal")
	if order.find(focused) >= 0 and order.find(focused) + 1 < order.size():
		_keys.text = _t_args("UI_QUEST_JOURNAL_KEYS_NEXT",
			{"key": key, "close": _key_label(&"open_menu")})
	else:
		_keys.text = _t_args("UI_QUEST_JOURNAL_KEYS", {"key": key})


## The view's entries in READING order (a stable sort by urgency over the authored order).
func _ordered() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _view == null or not _view.available:
		return entries
	for rank in PHASE_ORDER.size():
		for entry in _view.entries:
			if int(PHASE_ORDER.get(int(entry["phase"]), PHASE_ORDER.size() - 1)) == rank:
				entries.append(entry)
	return entries


## The ids that can be opened out, in reading order: everything but what is done.
func _focusable(entries: Array[Dictionary]) -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in entries:
		if int(entry["phase"]) != QuestService.Phase.COMPLETED:
			out.append(entry["quest_id"])
	return out


func _focused_id(order: Array[StringName]) -> StringName:
	if order.has(_focus):
		return _focus
	return order[0] if not order.is_empty() else &""


func _block(entry: Dictionary, opened: bool) -> VBoxContainer:
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
	if not opened:
		return block
	# LEVEL 5: why it matters, once it is the player's business — it names who asked. (On
	# offer, the ask itself is the giver's to say; the line above already says where to go.)
	if phase != QuestService.Phase.AVAILABLE:
		var why := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
		why.text = _t(String(entry["summary_key"]))
		block.add_child(why)
		_add_objectives(block, entry)
	# Only when the answer goes to someone OTHER than the giver does it need saying.
	if entry["receiver_name_key"] != entry["giver_name_key"]:
		var who := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
		who.text = _t_args("UI_QUEST_ANSWER_TO",
			{"name": _t(String(entry["receiver_name_key"]))})
		block.add_child(who)
	var pays := _wrapped(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	pays.text = _t_args("UI_QUEST_REWARD", {"list": _reward_text(entry)})
	block.add_child(pays)
	return block


## The objectives of a quest UNDER WAY. (Once it is ready there is nothing left to do but
## return, and the line above says to whom — listing what was done would only push the reward
## off the page.) Ways that are alternatives are joined by "or", in words.
func _add_objectives(block: VBoxContainer, entry: Dictionary) -> void:
	if int(entry["phase"]) != QuestService.Phase.ACTIVE:
		return
	var objectives: Array = entry["objectives"]
	for i in objectives.size():
		var objective: Dictionary = objectives[i]
		var met := bool(objective["met"])
		var line := _wrapped(UIPalette.FONT_SIZE_HINT,
			UIPalette.COLOR_ACCENT if met else UIPalette.COLOR_TEXT)
		var text := _t(String(objective["text_key"]))
		if int(objective["required"]) > 1:
			text = _t_args("UI_QUEST_OBJECTIVE_COUNT", {"text": text,
				"value": int(objective["value"]), "required": int(objective["required"])})
		# Met is said in WORDS as well as in colour.
		if met:
			text = _t_args("UI_QUEST_OBJECTIVE_MET", {"text": text})
		line.text = _t_args("UI_QUEST_OBJECTIVE_OR", {"text": text}) \
			if bool(entry["any"]) and i > 0 else "· " + text
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
