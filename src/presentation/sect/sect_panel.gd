extends PanelContainer
class_name SectPanel
## SectPanel — Aetheria presentation (the toggleable Sect detail panel, Phase 06 §19).
##
## A small framed panel (shared `UITheme`/`UIPalette` Xianxia 9-slice look) that renders a
## read-only `SectMembershipView`: emblem + name + doctrine + type/tier + the player's rank +
## reputation/influence/territory + a compact resource summary. It is PURE PRESENTATION: it
## renders a view and resolves localization keys; it holds NO sect truth, runs NO sect rules,
## and shows NO raw ids (§21). When the player has no sect it renders a localized empty state
## rather than crashing.
##
## It is created + owned by the HUD; the HUD toggles its visibility on the semantic
## `sect_panel` action and pushes a fresh view in. It never reaches into the domain itself.

const SectTemplate := preload("res://src/data/sects/sect_template_data.gd")

## Side of the emblem chip in the panel header.
const EMBLEM_PX := 28

## Minimum panel width, wide enough for the longest localized label + value on one line.
const PANEL_MIN_WIDTH := 280

## Localization key prefix for a sect resource's display name (§7). The id is upper-cased and
## appended: `pills` -> `SECT_RESOURCE_PILLS`.
const RESOURCE_KEY_PREFIX := "SECT_RESOURCE_"

## Shown instead of an unlocalized resource id. A missing translation degrades to a localized
## generic word, never to the internal token.
const RESOURCE_FALLBACK_KEY := "UI_SECT_PANEL_RESOURCE_UNKNOWN"

var _loc: Node = null

var _title: Label
var _emblem: TextureRect
var _divider: TextureRect
var _name: Label
var _doctrine: Label
var _type_tier: Label
var _rank: Label
var _reputation: Label
var _influence: Label
var _territory: Label
var _resources: Label
var _empty: Label

var _view: SectMembershipView = null


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _title == null:
		_build()
	_refresh()


func _build() -> void:
	# Scrolls inside its bounded box for the same reason the politics panel does: this panel is
	# anchored to the screen edges now, and a long doctrine or a large resource list on a short
	# screen (a phone in landscape) must scroll rather than push the 9-slice frame off-screen.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The one node in this subtree that must receive input (everything else is IGNORE), or the
	# wheel passes through and clipped content becomes unreachable.
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	# Header: emblem + title.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	box.add_child(header)

	_emblem = TextureRect.new()
	_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Without EXPAND_IGNORE_SIZE the rect reports the emblem's native size as its minimum
	# and `custom_minimum_size` becomes a no-op floor, widening the panel (D-034).
	_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_emblem.custom_minimum_size = Vector2(EMBLEM_PX, EMBLEM_PX)
	_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_emblem)

	_title = _make_label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_title)

	# Ornamental divider under the section title, from the ONE theme factory (D-050) so this
	# panel and the menu genuinely read as one design language instead of each approximating
	# it. Four screens used to build this themselves, at three different heights.
	_divider = UITheme.ornament_divider()
	box.add_child(_divider)

	# LEVEL 2 — primary identity. The sect's own name is the thing the player came to read,
	# so it is the largest text in the panel after the section title (A12).
	_name = _make_label(UIPalette.FONT_SIZE_SUBTITLE, UIPalette.COLOR_TITLE)
	box.add_child(_name)

	# LEVEL 5 — supporting flavour. Wraps, muted, deliberately the quietest block.
	_doctrine = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_doctrine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_doctrine)

	# LEVEL 3 — the player's standing. Jade accent: this is the one line about *them*.
	_rank = _make_label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_ACCENT)
	box.add_child(_rank)

	var section_gap := Control.new()
	section_gap.custom_minimum_size = Vector2(0, UIPalette.SECTION_GAP - UIPalette.SPACE_SM)
	section_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(section_gap)

	# LEVEL 4 — supporting values as aligned label/value rows, so the numbers form a column
	# the eye can scan instead of four sentences of differing length.
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	box.add_child(rows)
	_type_tier = _add_value_row(rows)
	_reputation = _add_value_row(rows)
	_influence = _add_value_row(rows)
	_territory = _add_value_row(rows)

	# LEVEL 5 — the resource summary wraps under the value column.
	_resources = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_resources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_resources)

	_empty = _make_label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT_MUTED)
	box.add_child(_empty)


## One aligned "label …… value" row: the caption sits left in muted text, the value right in
## primary text. Returns the VALUE label (the caller sets its text and the caption via
## `_set_row`), because the value is what changes at runtime.
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
	# The caption is reachable from the value for `_set_row` without a second member each.
	value.set_meta("caption", caption)
	return value


## Fill one value row: `caption_key` is localized, `value_text` is already formatted.
func _set_row(value_label: Label, caption_key: String, value_text: String) -> void:
	var caption: Label = value_label.get_meta("caption")
	if caption != null:
		caption.text = _t(caption_key)
	value_label.text = value_text


## Show or hide a whole value row (caption included).
func _set_row_visible(value_label: Label, shown: bool) -> void:
	value_label.visible = shown
	var caption: Label = value_label.get_meta("caption")
	if caption != null:
		caption.visible = shown
	var row := value_label.get_parent() as Control
	if row != null:
		row.visible = shown


func _make_label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Push a read-only membership view (built by SectRuntime). Triggers a re-render.
func set_view(view: SectMembershipView) -> void:
	_view = view
	_refresh()


func _refresh() -> void:
	if _title == null:
		return
	_title.text = _t("UI_SECT_PANEL_TITLE")
	var is_member := _view != null and _view.is_member
	# Toggle the detail rows vs the empty-state line.
	for row in [_name, _doctrine, _rank, _resources]:
		row.visible = is_member
	for value_label in [_type_tier, _reputation, _influence, _territory]:
		_set_row_visible(value_label, is_member)
	_emblem.visible = is_member
	_divider.visible = is_member
	_empty.visible = not is_member

	if not is_member:
		_empty.text = _t("UI_SECT_PANEL_NONE")
		_emblem.texture = null
		return

	# LEVEL 2: the sect's name stands alone — no "Name:" caption, because the section title
	# already said what this panel is about (A12).
	_name.text = _t(String(_view.sect_name_key))
	_doctrine.text = _t(String(_view.doctrine_key))
	# LEVEL 3: the player's own standing.
	_rank.text = "%s: %s" % [_t("UI_SECT_PANEL_RANK"), _t(String(_view.rank_name_key))]
	# LEVEL 4: aligned value column.
	_set_row(_type_tier, "UI_SECT_PANEL_TYPE", "%s · %s %d" % [
		_t(_sect_type_key(_view.sect_type)), _t("UI_SECT_PANEL_TIER"), _view.tier])
	_set_row(_reputation, "UI_SECT_PANEL_REPUTATION", str(_view.reputation))
	_set_row(_influence, "UI_SECT_PANEL_INFLUENCE", str(_view.influence))
	_set_row(_territory, "UI_SECT_PANEL_TERRITORY", str(_view.territory_count))
	# LEVEL 5: the quietest block.
	_resources.text = "%s: %s" % [
		_t("UI_SECT_PANEL_RESOURCES"), _format_resources(_view.resource_summary)]

	if _view.emblem_ref != "" and ResourceLoader.exists(_view.emblem_ref):
		_emblem.texture = load(_view.emblem_ref)
	else:
		_emblem.texture = null


## Map a SectType int to its localization key (never shows the raw enum/id).
func _sect_type_key(sect_type: int) -> String:
	match sect_type:
		SectTemplate.SectType.DEMONIC:
			return "SECT_TYPE_DEMONIC"
		SectTemplate.SectType.NEUTRAL:
			return "SECT_TYPE_NEUTRAL"
		SectTemplate.SectType.HIDDEN:
			return "SECT_TYPE_HIDDEN"
		_:
			return "SECT_TYPE_ORTHODOX"


## Compact "qty NAME, qty NAME" summary of the resource dict, deterministic by sorted key.
##
## The dict keys are INTERNAL content ids (`spirit_stones`, `blood_crystals`, …) and must
## never reach the screen (§21, `07-localization.md`: no raw id, no hard-coded user-facing
## text). Each id is resolved to its localized display name; an id with no authored key gets
## the localized GENERIC label, so an unlocalized resource degrades to "Unknown Resource" /
## "Tài nguyên khác" rather than leaking the token.
func _format_resources(summary: Dictionary) -> String:
	var keys := summary.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%d %s" % [int(summary[key]), _resource_label(String(key))])
	return ", ".join(parts) if not parts.is_empty() else "-"


## The localization KEY for a sect resource id: `spirit_stones` -> `SECT_RESOURCE_SPIRIT_STONES`
## (§7 convention). A pure, static naming rule — NOT a resource registry/lookup table: adding
## a resource id to content means adding its two CSV rows, no code and no new system
## (`03-architecture.md` anti-over-engineering).
static func resource_name_key(resource_id: String) -> String:
	return RESOURCE_KEY_PREFIX + resource_id.to_upper()


## Localized display name for a resource id, or the localized generic fallback when the
## convention key has not been authored. Never returns the raw id.
func _resource_label(resource_id: String) -> String:
	var key := resource_name_key(resource_id)
	if _loc != null and bool(_loc.call("has_key", key)):
		return _t(key)
	return _t(RESOURCE_FALLBACK_KEY)


func _t(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))
