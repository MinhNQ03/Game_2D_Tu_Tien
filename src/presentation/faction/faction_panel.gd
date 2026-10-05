extends PanelContainer
class_name FactionPanel
## FactionPanel — Aetheria presentation (the toggleable Sect Politics panel, Phase 07).
##
## Renders a read-only `SectPoliticsView`: the sect's direction (contested or settled), which
## side the player is on, and one block per faction — name, stance, influence and share, the
## goals it pursues, and the argument it is actually making.
##
## PURE PRESENTATION. It resolves localization keys and formats numbers. It holds no faction
## truth, runs no politics rules, and shows no raw content id (§21). When there is no session
## or no faction it renders a localized empty state rather than an empty frame that reads as a
## bug.
##
## It is created + owned by the HUD, which toggles it on the semantic `faction_panel` action
## and pushes a fresh view in. It never reaches into the domain itself.
##
## VISUAL LANGUAGE (D-041, `UI_UX_BIBLE.md` §3a): the shared `UITheme` panel plate, the
## ornamental rule under the section title, and the aligned caption/value rows the sect panel
## established — so this screen is recognisably the same UI rather than a new dialect. The
## faction blocks are built ONCE and then shown/hidden/refilled, never rebuilt per refresh:
## the view can be pushed on every membership change, and churning nodes on each push would
## allocate on a path the player triggers repeatedly (`05-performance-testing.md`).

## Minimum panel width. Wide enough for the longest localized caption + value on one line,
## and a floor rather than a fixed width so a longer vi/en string can still widen it.
const PANEL_MIN_WIDTH := 320

## How many faction blocks are pre-built. The shipped Thanh Vân Tông landscape has three; the
## cap exists so a content author who adds a fourth sees a deterministic, documented truncation
## instead of an unbounded panel that grows off-screen. The overflow line reports the count, so
## the omission is visible rather than silent.
const MAX_ROWS := 6

var _loc: Node = null

var _title: Label
var _divider: TextureRect
var _direction: Label
var _your_side: Label
var _empty: Label
var _overflow: Label
var _rows_box: VBoxContainer

## One pre-built block of labels per displayable faction row.
var _blocks: Array = []

var _view: SectPoliticsView = null


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title == null:
		_build()
	_refresh()


func _build() -> void:
	# The panel is a BOUNDED box on the screen edge (`GameplayHUD._bound_side_panel`), so its
	# content must scroll rather than stretch the frame: three factions of detail is taller
	# than a phone screen, and content that outgrows its frame pushes the 9-slice border
	# off-screen, which is what made this panel render with no visible plate at all.
	# `follow_focus` so keyboard navigation cannot select a row that is scrolled out of sight.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Explicit STOP: the panel itself and every label in it are MOUSE_FILTER_IGNORE, and this
	# is the ONE node in the subtree that must actually receive input — otherwise the wheel
	# passes straight through and the content can be clipped with no way to reach it.
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	# Fill the scroll viewport's width so the value rows and the divider span the panel
	# instead of shrink-wrapping their text.
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	_title = _make_label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	box.add_child(_title)

	_divider = _make_divider()
	box.add_child(_divider)

	# LEVEL 2 — the one-line answer the player opened the panel for: is the sect's direction
	# in dispute, and where do they stand in it?
	_direction = _make_label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_ACCENT)
	box.add_child(_direction)

	_your_side = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
	_your_side.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_your_side)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, UIPalette.SECTION_GAP - UIPalette.SPACE_SM)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(gap)

	# LEVEL 3 — the faction blocks.
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", UIPalette.SECTION_GAP)
	box.add_child(_rows_box)
	for i in MAX_ROWS:
		_blocks.append(_build_block(_rows_box))

	_overflow = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	box.add_child(_overflow)

	_empty = _make_label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT_MUTED)
	_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_empty)


## Build one faction block and return its parts as a Dictionary of labels.
##
## A Dictionary rather than a dedicated class because a new `.gd` for a four-label bundle that
## nothing outside this file constructs would be a file to maintain for no seam
## (`03-architecture.md` anti-over-engineering). The keys are read in exactly one place
## (`_fill_block`), so the looseness is contained.
func _build_block(parent: VBoxContainer) -> Dictionary:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	parent.add_child(block)

	# The faction's name carries its own status marker ("holds sway" / "your side") as TEXT,
	# never as colour alone — colour is never the only carrier of meaning (`UI_UX_BIBLE` §4).
	var name_label := _make_label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TITLE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(name_label)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	block.add_child(rows)
	var stance := _add_value_row(rows)
	var influence := _add_value_row(rows)

	var goals := _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	goals.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(goals)

	# LEVEL 5 — the argument itself. Shown for the player's OWN side and for whoever holds
	# sway, and withheld from the rest.
	#
	# The first version printed every faction's full doctrine, which turned a comparison list
	# into three paragraphs of prose — the list's job is to let the player compare sides at a
	# glance, and the detail belongs to the one or two that currently matter to them. This is a
	# density decision, not a capacity one: the panel scrolls now, so the wall of text was no
	# longer breaking the layout, it was just unreadable.
	var doctrine := _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	doctrine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(doctrine)

	var relation := _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_ACCENT)
	relation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	block.add_child(relation)

	return {
		"root": block,
		"name": name_label,
		"stance": stance,
		"influence": influence,
		"goals": goals,
		"doctrine": doctrine,
		"relation": relation,
	}


## One aligned "caption …… value" row; returns the VALUE label (the caption is reachable from
## it via metadata, the same shape the sect panel uses).
func _add_value_row(parent: VBoxContainer) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	parent.add_child(row)

	var caption := _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)

	var value := _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)
	value.set_meta("caption", caption)
	return value


func _set_row(value_label: Label, caption_key: String, value_text: String) -> void:
	var caption: Label = value_label.get_meta("caption")
	if caption != null:
		caption.text = _t(caption_key)
	value_label.text = value_text


## Delegates to the ONE divider factory (D-050) — see `UITheme.ornament_divider`.
func _make_divider() -> TextureRect:
	return UITheme.ornament_divider()


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Owner-pushed view state -------------------------------------------------

## Push a read-only politics view (built by FactionRuntime). Triggers a re-render.
func set_view(view: SectPoliticsView) -> void:
	_view = view
	_refresh()


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	if _title == null:
		return
	_title.text = _t("UI_FACTION_PANEL_TITLE")

	var available := _view != null and _view.is_available
	var rows: Array = _view.rows if available else []
	var has_rows := not rows.is_empty()

	_divider.visible = available
	_direction.visible = available and has_rows
	_your_side.visible = available and has_rows
	_empty.visible = not available or not has_rows

	if not available:
		# No live faction session at all — a different statement from "this sect has none".
		_empty.text = _t("UI_FACTION_PANEL_UNAVAILABLE")
		_hide_blocks_from(0)
		_overflow.visible = false
		return
	if not has_rows:
		_empty.text = _t("UI_FACTION_PANEL_NONE")
		_hide_blocks_from(0)
		_overflow.visible = false
		return

	# The sect's direction, as a WORD. "Contested" is the political fact the player needs; a
	# colour change alone would not survive a colour-blind player or a screenshot.
	_direction.text = "%s: %s" % [
		_t("UI_FACTION_PANEL_DIRECTION"),
		_t("UI_FACTION_PANEL_CONTESTED") if _view.is_contested
			else _t("UI_FACTION_PANEL_SETTLED")]

	var player_row: SectPoliticsView.Row = null
	for row in rows:
		var r := row as SectPoliticsView.Row
		if r.is_player_faction:
			player_row = r
	if player_row != null:
		_your_side.text = "%s: %s" % [
			_t("UI_FACTION_PANEL_YOUR_SIDE"), _t(String(player_row.name_key))]
	else:
		_your_side.text = _t("UI_FACTION_PANEL_NO_SIDE")

	var shown := mini(rows.size(), _blocks.size())
	for i in shown:
		_fill_block(_blocks[i], rows[i] as SectPoliticsView.Row)
	_hide_blocks_from(shown)

	# Truncation is REPORTED, never silent: a content author who adds a seventh faction must
	# be able to see that the panel stopped showing them.
	_overflow.visible = rows.size() > shown
	if _overflow.visible:
		_overflow.text = "+%d" % (rows.size() - shown)


func _fill_block(block: Dictionary, row: SectPoliticsView.Row) -> void:
	var root: Control = block["root"]
	root.visible = true

	var markers: Array[String] = []
	if row.is_dominant:
		markers.append(_t("UI_FACTION_PANEL_DOMINANT"))
	if row.is_player_faction:
		markers.append(_t("UI_FACTION_PANEL_YOUR_SIDE"))
	var name_label: Label = block["name"]
	name_label.text = _t(String(row.name_key))
	if not markers.is_empty():
		name_label.text += " · " + " · ".join(markers)

	_set_row(block["stance"], "UI_FACTION_PANEL_STANCE", _t(stance_key(row.stance)))
	# Influence and its share read together: the raw weight alone means nothing without the
	# denominator, and the share alone hides that the whole sect may be weak.
	_set_row(block["influence"], "UI_FACTION_PANEL_INFLUENCE",
		"%d (%d%%)" % [row.influence, row.influence_share])

	var goals_label: Label = block["goals"]
	var goal_texts: Array[String] = []
	for key in row.goal_keys:
		goal_texts.append(_t(String(key)))
	goals_label.text = "%s: %s" % [_t("UI_FACTION_PANEL_GOALS"), ", ".join(goal_texts)]
	goals_label.visible = not goal_texts.is_empty()

	var doctrine_label: Label = block["doctrine"]
	var show_doctrine := row.doctrine_key != &"" and (row.is_player_faction or row.is_dominant)
	doctrine_label.text = _t(String(row.doctrine_key)) if show_doctrine else ""
	doctrine_label.visible = show_doctrine

	var relation_label: Label = block["relation"]
	match row.relation_to_player_faction:
		&"ALLIED":
			relation_label.text = _t("UI_FACTION_PANEL_RELATION_ALLIED")
			relation_label.visible = true
		&"RIVAL":
			relation_label.text = _t("UI_FACTION_PANEL_RELATION_RIVAL")
			relation_label.visible = true
		_:
			relation_label.text = ""
			relation_label.visible = false


func _hide_blocks_from(start: int) -> void:
	for i in range(start, _blocks.size()):
		var root: Control = (_blocks[i] as Dictionary)["root"]
		root.visible = false


## Localization key for a `FactionTemplateData.Stance` ordinal. A pure naming map, not a
## registry: adding a stance means adding its enum value and one CSV row. An unknown ordinal
## falls back to NEUTRAL's key rather than leaking the number to the screen (§21).
static func stance_key(stance: int) -> String:
	match stance:
		FactionTemplateData.Stance.LOYALIST:
			return "FACTION_STANCE_LOYALIST"
		FactionTemplateData.Stance.REFORMIST:
			return "FACTION_STANCE_REFORMIST"
		FactionTemplateData.Stance.RADICAL:
			return "FACTION_STANCE_RADICAL"
		_:
			return "FACTION_STANCE_NEUTRAL"


func _t(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))
