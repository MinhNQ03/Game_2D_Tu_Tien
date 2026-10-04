extends CanvasLayer
class_name GameplayHUD
## GameplayHUD — Aetheria presentation (in-map heads-up display, asset-backed pass).
##
## A screen-space (`CanvasLayer`) overlay that RENDERS a view of the running session inside
## framed pixel-art panels (shared `UITheme`/`UIPalette` 9-slice assets):
##   - top-left   : the IDENTITY PLAQUE — portrait slot + name/title + sect chip, read as ONE
##                  unit under an ornamental divider (D-041),
##   - top-right  : the map-name plaque (a localized place name under the same divider),
##   - bottom-left: a control-prompt panel with graphic key badges ([E] Interact / [Esc] Menu).
##
## D-041 changed the COMPOSITION only, never the data: the identity block used to be a flat
## stack where the sect chip was indistinguishable from the character's title (two muted hint
## lines in the same column), so the player could not tell "who I am" from "who I belong to".
## The divider + section gap make that boundary visible. Screen-edge spacing now comes from
## `UIPalette.HUD_MARGIN` rather than the generic `SPACE_MD`, so HUD framing can be retuned
## in one place without touching inner padding.
##
## It OWNS no truth. The owner (MapBase) pushes data in via `set_character()`, `set_map_name()`
## and `set_interact_available()`; the HUD only formats + displays. Key glyphs come from
## `InputService.get_action_display_label` (never raw keycodes, L-003). It refreshes on demand
## (owner call) and on language change — never per frame (`05-performance-testing.md`). This is
## the FOUNDATION HUD (identity/map/prompts); HP/mana/cultivation bars are intentionally NOT
## shown (no gameplay semantics yet) — a later phase adds them to the reserved panels.

const PromptRowScript := preload("res://src/presentation/ui/components/ui_prompt_row.gd")
const SectPanelScript := preload("res://src/presentation/sect/sect_panel.gd")

const INTERACT_ACTION := &"interact"
const OPEN_MENU_ACTION := &"open_menu"
const SECT_PANEL_ACTION := &"sect_panel"

## Side of the small sect emblem chip in the identity panel. HUD-local: nothing else in the
## UI draws a chip this size, so it stays here rather than widening the shared palette.
const SECT_EMBLEM_PX := 20

## Height of the ornamental divider strips. The source art is 136x21 (measured, D-034) and is
## scaled to this band, so it reads as a thin engraved rule rather than a picture.
const DIVIDER_HEIGHT := 8

var _loc: Node = null
var _input: Node = null
var _bus: Node = null

# Pushed-in view state (presentation copies; the HUD never mutates the source).
var _name_key: StringName = &""
var _title_key: StringName = &""
var _map_name_key: StringName = &""
var _interact_available: bool = false
var _sect_view: SectMembershipView = null  # read-only sect view (Phase 06); may be null

var _name_label: Label
var _title_label: Label
var _map_label: Label
var _interact_row: UIPromptRow
var _menu_row: UIPromptRow
var _sect_row: UIPromptRow

# Compact sect chip in the identity panel (emblem + name + rank + reputation).
var _sect_emblem: TextureRect
var _sect_name_label: Label
var _sect_rank_label: Label
# The toggleable Sect detail panel (owned here; hidden until the player opens it).
var _sect_panel: SectPanel


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	_bus = get_node_or_null("/root/EventBus")
	_build_ui()
	if _bus != null and not _bus.is_connected("language_changed", _on_language_changed):
		_bus.connect("language_changed", _on_language_changed)
	_refresh()


func _exit_tree() -> void:
	if _bus != null and _bus.is_connected("language_changed", _on_language_changed):
		_bus.disconnect("language_changed", _on_language_changed)


func _build_ui() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The HUD must wear the shared theme like the menu does (D-034). A CanvasLayer cannot
	# hold a Theme, so it goes on this root Control and every panel/label below inherits the
	# asset-backed styles AND the text outline that keeps light text readable over map art.
	root.theme = UITheme.build()
	add_child(root)

	# --- Top-left: the identity plaque -------------------------------------------
	# One plaque, two tiers: WHO I AM (portrait + name + title) above an ornamental divider,
	# WHO I BELONG TO (sect chip) below it. Before D-041 the sect lines were just two more
	# entries in the same column as the title, so the two kinds of identity blurred together.
	var identity_panel := _panel()
	identity_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	identity_panel.position = Vector2(UIPalette.HUD_MARGIN, UIPalette.HUD_MARGIN)
	root.add_child(identity_panel)

	var identity_body := VBoxContainer.new()
	identity_body.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	identity_panel.add_child(identity_body)

	var identity_row := HBoxContainer.new()
	identity_row.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	identity_body.add_child(identity_row)

	# Portrait frame slot (empty well for now; a portrait texture drops in later).
	# A NinePatchRect, NOT a TextureRect: `portrait_frame.png` is 218x118 (measured, D-034)
	# and a TextureRect reports its whole texture as the minimum size, which is what pushed a
	# giant empty rosewood plate over the identity text. Nine-patching keeps the frame's
	# corners crisp at the small size we actually want (`06-art-assets.md` nine-slice rule).
	var portrait := NinePatchRect.new()
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.custom_minimum_size = Vector2(
		UIPalette.IDENTITY_PORTRAIT_PX, UIPalette.IDENTITY_PORTRAIT_PX)
	portrait.patch_margin_left = UIPalette.PORTRAIT_MARGIN
	portrait.patch_margin_right = UIPalette.PORTRAIT_MARGIN
	portrait.patch_margin_top = UIPalette.PORTRAIT_MARGIN
	portrait.patch_margin_bottom = UIPalette.PORTRAIT_MARGIN
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(UIPalette.TEX_PORTRAIT_FRAME):
		portrait.texture = load(UIPalette.TEX_PORTRAIT_FRAME)
	identity_row.add_child(portrait)

	var identity_text := VBoxContainer.new()
	identity_text.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_text.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	identity_row.add_child(identity_text)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	identity_text.add_child(_name_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_title_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	identity_text.add_child(_title_label)

	# The engraved rule that separates the two identity tiers. Same art as the menu title and
	# the sect panel header, so all three screens read as one design language (D-041).
	identity_body.add_child(_divider_strip())

	# Compact sect chip (Phase 06): emblem + sect name + rank. It now lives in the plaque's
	# SECOND tier (a sibling of the portrait row), not nested beside the character title.
	var sect_chip := HBoxContainer.new()
	sect_chip.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	identity_body.add_child(sect_chip)

	_sect_emblem = TextureRect.new()
	_sect_emblem.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sect_emblem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# EXPAND_IGNORE_SIZE is required for `custom_minimum_size` to actually govern: the
	# default EXPAND_KEEP_SIZE makes a TextureRect report its full texture as its minimum,
	# so the chip would grow to the emblem's native size and shove the layout around (D-034).
	_sect_emblem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sect_emblem.custom_minimum_size = Vector2(SECT_EMBLEM_PX, SECT_EMBLEM_PX)
	_sect_emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sect_chip.add_child(_sect_emblem)

	var sect_text := VBoxContainer.new()
	sect_text.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	sect_chip.add_child(sect_text)

	_sect_name_label = Label.new()
	_sect_name_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_sect_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TITLE)
	sect_text.add_child(_sect_name_label)

	_sect_rank_label = Label.new()
	_sect_rank_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_sect_rank_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	sect_text.add_child(_sect_rank_label)

	# --- Top-right: the map-name plaque -------------------------------------------
	# Stays top-RIGHT (a permanent top-centre banner would sit over the playfield), but it is
	# now a proper plaque instead of a shrink-wrapped chip: a minimum width so the place name
	# is centred in a stable frame, and the same ornamental rule under it. The place name is
	# the player's sense of WHERE they are, which the UI bible ranks as primary orientation
	# information — it should look authored, not like a debug readout.
	var map_panel := _panel()
	map_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	map_panel.position = Vector2(-UIPalette.HUD_MARGIN, UIPalette.HUD_MARGIN)
	map_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	map_panel.custom_minimum_size = Vector2(UIPalette.HUD_MAP_PANEL_WIDTH, 0)
	root.add_child(map_panel)

	var map_body := VBoxContainer.new()
	map_body.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	map_panel.add_child(map_body)

	_map_label = Label.new()
	_map_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_map_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_map_label.add_theme_color_override("font_color", UIPalette.COLOR_TITLE)
	map_body.add_child(_map_label)

	map_body.add_child(_divider_strip())

	# --- Bottom-left: control-prompt panel (graphic key badges) -------------------
	var prompt_panel := _panel()
	prompt_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	prompt_panel.position = Vector2(UIPalette.HUD_MARGIN, -UIPalette.HUD_MARGIN)
	prompt_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# Grow RIGHT from the left edge but never past it; `grow_horizontal` defaults to END,
	# which is what we want here — the explicit set documents that the row is bottom-LEFT
	# anchored and is why the prompts must stay narrow (one badge + one short label each).
	prompt_panel.grow_horizontal = Control.GROW_DIRECTION_END
	root.add_child(prompt_panel)

	var prompt_box := HBoxContainer.new()
	prompt_box.add_theme_constant_override("separation", UIPalette.SPACE_LG)
	prompt_panel.add_child(prompt_box)

	_interact_row = PromptRowScript.new() as UIPromptRow
	prompt_box.add_child(_interact_row)

	_sect_row = PromptRowScript.new() as UIPromptRow
	prompt_box.add_child(_sect_row)

	_menu_row = PromptRowScript.new() as UIPromptRow
	prompt_box.add_child(_menu_row)

	# --- Sect detail panel (Phase 06): hidden until the player presses `sect_panel` ----
	# Anchored on the PANEL ITSELF, directly under `root`. The previous version wrapped it in
	# an empty size-0 Control and set `grow_horizontal = BEGIN` on that WRAPPER; growth
	# direction does not propagate to children, so the panel still grew END (rightwards) from
	# the right edge and ~95% of it sat outside the viewport — only a sliver of its jade frame
	# was visible, which read as "pressing T does nothing" (D-034).
	_sect_panel = SectPanelScript.new() as SectPanel
	_sect_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_sect_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_sect_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_sect_panel.position = Vector2(-UIPalette.HUD_MARGIN, 0)
	_sect_panel.visible = false
	root.add_child(_sect_panel)


# --- Builders ----------------------------------------------------------------

## A framed HUD panel wearing the shared 9-slice panel style.
func _panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.panel_stylebox())
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## A thin ornamental rule, used to separate tiers inside a plaque (D-041).
##
## `STRETCH_SCALE` + `size_flags_horizontal = EXPAND_FILL` makes the strip span whatever width
## its parent plaque settles at, so it keeps working when a longer localized name widens the
## panel (+40% string budget) instead of being authored for one screenshot width. It is a
## plain `TextureRect`, not a NinePatchRect: the divider is DECOR with no interior to protect,
## and scaling a 136x21 strip along one axis is exactly what the art is for. If the texture is
## missing the node simply draws nothing — the layout gap stays, so nothing jumps.
func _divider_strip() -> TextureRect:
	var strip := TextureRect.new()
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.stretch_mode = TextureRect.STRETCH_SCALE
	strip.custom_minimum_size = Vector2(0, DIVIDER_HEIGHT)
	strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(UIPalette.TEX_TITLE_DIVIDER):
		strip.texture = load(UIPalette.TEX_TITLE_DIVIDER)
	return strip


# --- Owner-pushed view state -------------------------------------------------

## Set the character identity to display (name + optional title localization keys). Pass the
## authoritative CharacterState's keys; the HUD resolves them through Localization. A null
## state clears the plate (e.g. before the player exists).
func set_character(state: CharacterState) -> void:
	if state == null:
		_name_key = &""
		_title_key = &""
	else:
		_name_key = state.name_key
		_title_key = state.title_key
	_refresh()


## Set the current map's name localization key.
func set_map_name(name_key: StringName) -> void:
	_map_name_key = name_key
	_refresh()


## Whether the player can currently interact with an exit (drives the interact prompt).
func set_interact_available(available: bool) -> void:
	if _interact_available == available:
		return
	_interact_available = available
	_refresh()


## Push the player's read-only sect membership view (Phase 06). The owner (MapBase, fed by
## WorldRuntime→SectRuntime) rebuilds + pushes this on map arrival / membership change — NOT
## per frame. Refreshes the compact chip + the (possibly open) detail panel.
func set_sect_view(view: SectMembershipView) -> void:
	_sect_view = view
	if _sect_panel != null:
		_sect_panel.set_view(view)
	_refresh()


## Semantic `sect_panel` intent toggles the detail panel. Driven through InputService (gated
## to GAMEPLAY context) — never a raw keycode (L-003). Read + handle locally, then mark the
## input handled; no scene teardown happens here so this is a safe place to touch the viewport.
func _unhandled_input(_event: InputEvent) -> void:
	if _input == null or _sect_panel == null:
		return
	if _input.call("is_gameplay_action_just_pressed", SECT_PANEL_ACTION):
		_sect_panel.visible = not _sect_panel.visible
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


## Is the Sect detail panel currently shown? (for tests)
func is_sect_panel_open() -> bool:
	return _sect_panel != null and _sect_panel.visible


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	if _name_label == null:
		return  # not built yet
	_name_label.text = _resolve(_name_key)
	_title_label.text = _resolve(_title_key)
	_title_label.visible = _title_key != &""
	_map_label.text = _resolve(_map_name_key)
	_refresh_sect_chip()
	_refresh_prompts()


## Render the compact sect chip from the read-only view (localized; never a raw id). A null
## view or a "not a member" view shows a localized "No Sect" line + no emblem.
func _refresh_sect_chip() -> void:
	if _sect_name_label == null:
		return
	if _sect_view != null and _sect_view.is_member:
		_sect_name_label.text = _resolve(_sect_view.sect_name_key)
		_sect_rank_label.text = "%s · %s %d" % [
			_resolve(_sect_view.rank_name_key),
			_text("UI_SECT_PANEL_REPUTATION"), _sect_view.reputation]
		_sect_rank_label.visible = true
		if _sect_view.emblem_ref != "" and ResourceLoader.exists(_sect_view.emblem_ref):
			_sect_emblem.texture = load(_sect_view.emblem_ref)
		else:
			_sect_emblem.texture = null
		_sect_emblem.visible = _sect_emblem.texture != null
	else:
		_sect_name_label.text = _text("UI_HUD_SECT_NONE")
		_sect_rank_label.visible = false
		_sect_emblem.texture = null
		_sect_emblem.visible = false


## Resolve a localization key to text (empty key -> empty string, no warning spam).
func _resolve(key: StringName) -> String:
	if key == &"" or _loc == null:
		return ""
	return String(_loc.call("t", key))


## Fill the two prompt rows from InputService display labels (never raw keycodes). The
## interact row is hidden until the player is standing in an exit; the menu row is always on.
func _refresh_prompts() -> void:
	if _menu_row == null:
		return
	var menu_key := _display_label(OPEN_MENU_ACTION)
	_menu_row.set_prompt(menu_key, _text("UI_HUD_MENU_ACTION"))
	_interact_row.visible = _interact_available
	if _interact_available:
		var interact_key := _display_label(INTERACT_ACTION)
		_interact_row.set_prompt(interact_key, _text("UI_HUD_INTERACT_ACTION"))
	# Sect panel prompt: always available (the player can always inspect their sect, §19).
	if _sect_row != null:
		var sect_key := _display_label(SECT_PANEL_ACTION)
		_sect_row.set_prompt(sect_key, _text("UI_SECT_PANEL_TOGGLE"))


func _display_label(action: StringName) -> String:
	if _input == null:
		return "?"
	return String(_input.call("get_action_display_label", action))


func _text(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))


func _on_language_changed(_language_code: String) -> void:
	_refresh()
