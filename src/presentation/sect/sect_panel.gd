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

var _loc: Node = null

var _title: Label
var _emblem: TextureRect
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
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	add_child(box)

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

	_name = _make_label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT)
	box.add_child(_name)
	_doctrine = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_doctrine.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_doctrine)
	_type_tier = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	box.add_child(_type_tier)
	_rank = _make_label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_ACCENT)
	box.add_child(_rank)
	_reputation = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
	box.add_child(_reputation)
	_influence = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
	box.add_child(_influence)
	_territory = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT)
	box.add_child(_territory)
	_resources = _make_label(UIPalette.FONT_SIZE_HINT, UIPalette.COLOR_TEXT_MUTED)
	_resources.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_resources)

	_empty = _make_label(UIPalette.FONT_SIZE_BODY, UIPalette.COLOR_TEXT_MUTED)
	box.add_child(_empty)


func _make_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
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
	for row in [
		_name, _doctrine, _type_tier, _rank,
		_reputation, _influence, _territory, _resources,
	]:
		row.visible = is_member
	_emblem.visible = is_member
	_empty.visible = not is_member

	if not is_member:
		_empty.text = _t("UI_SECT_PANEL_NONE")
		_emblem.texture = null
		return

	_name.text = _t(String(_view.sect_name_key))
	_doctrine.text = "%s: %s" % [_t("UI_SECT_PANEL_DOCTRINE"), _t(String(_view.doctrine_key))]
	_type_tier.text = "%s: %s   %s: %d" % [
		_t("UI_SECT_PANEL_TYPE"), _t(_sect_type_key(_view.sect_type)),
		_t("UI_SECT_PANEL_TIER"), _view.tier]
	_rank.text = "%s: %s" % [_t("UI_SECT_PANEL_RANK"), _t(String(_view.rank_name_key))]
	_reputation.text = "%s: %d" % [_t("UI_SECT_PANEL_REPUTATION"), _view.reputation]
	_influence.text = "%s: %d" % [_t("UI_SECT_PANEL_INFLUENCE"), _view.influence]
	_territory.text = "%s: %d" % [_t("UI_SECT_PANEL_TERRITORY"), _view.territory_count]
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


## Compact "qty id, qty id" summary of the resource dict (resource ids are internal tokens,
## not user-facing names; shown as a terse count line, deterministic by sorted key).
func _format_resources(summary: Dictionary) -> String:
	var keys := summary.keys()
	keys.sort()
	var parts: Array[String] = []
	for key in keys:
		parts.append("%d %s" % [int(summary[key]), String(key)])
	return ", ".join(parts) if not parts.is_empty() else "-"


func _t(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))
