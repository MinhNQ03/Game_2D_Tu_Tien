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
const FactionPanelScript := preload("res://src/presentation/faction/faction_panel.gd")
const LevelUpFeedbackScript := preload(
	"res://src/presentation/progression/level_up_feedback.gd")

const INTERACT_ACTION := &"interact"
const OPEN_MENU_ACTION := &"open_menu"
const SECT_PANEL_ACTION := &"sect_panel"
const FACTION_PANEL_ACTION := &"faction_panel"

## Side of the small sect emblem chip in the identity panel. HUD-local: nothing else in the
## UI draws a chip this size, so it stays here rather than widening the shared palette.
const SECT_EMBLEM_PX := 20

## Height of the ornamental divider strips. The source art is 136x21 (measured, D-034) and is
## scaled to this band, so it reads as a thin engraved rule rather than a picture.
const DIVIDER_HEIGHT := 8

## How far the painted portrait is inset inside its frame, so the frame's border art overlaps
## the picture's edge instead of the picture spilling over the border.
const PORTRAIT_INSET := 5

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
## World time + the last world event (Phase 08). Two muted lines under the place name.
var _world_date_label: Label
var _world_event_label: Label
var _portrait: TextureRect
## The player's health gauge (Phase 09). Hidden until a health value arrives, so a HUD built
## outside a combat session shows no gauge rather than a full bar for health nothing owns.
var _health_gauge: ProgressBar
## Level badge + XP meter (Phase 11). Both hidden until a progression view arrives.
var _level_label: Label
var _xp_meter: ProgressBar
## Transient centre-screen level-up announcement; owned by `_level_up` while it runs.
var _level_up_banner: Label
## The one-shot level-up celebration. Owned here; presentation-only; idle when not running.
var _level_up: LevelUpFeedback = null
## The last progression view pushed in, kept so `_refresh_text()` can re-resolve its strings
## on a language change without the progression session having to push again.
var _progression_view: ProgressionView = null
## The combat target plaque (Phase 10): what the player is fighting. Hidden with no target.
var _target_panel: PanelContainer
var _target_name_label: Label
var _target_threat_label: Label
var _target_gauge: ProgressBar
## Retires the target plaque a moment after a kill (see `set_target_view`).
var _target_linger: Timer
## The last target view pushed in, kept so `_refresh_text()` can re-resolve its keys on a
## language change without the combat session having to push again.
var _target_view: CombatTargetView = null
var _interact_row: UIPromptRow
var _menu_row: UIPromptRow
var _sect_row: UIPromptRow
var _faction_row: UIPromptRow

# Compact sect chip in the identity panel (emblem + name + rank + reputation).
var _sect_emblem: TextureRect
var _sect_name_label: Label
var _sect_rank_label: Label
# The toggleable Sect detail panel (owned here; hidden until the player opens it).
var _sect_panel: SectPanel
# The toggleable Sect Politics panel (Phase 07). Anchored on the opposite side of the screen
# from the sect panel so the player can read membership and politics side by side rather than
# having one cover the other.
var _faction_panel: FactionPanel
var _politics_view: SectPoliticsView = null  # read-only politics view; may be null
var _world_sim_view: WorldSimView = null  # read-only world-sim view (Phase 08); may be null
# The full-rect Control every HUD element hangs off. Held so the safe-area inset can be
# re-applied on a viewport change without rebuilding the HUD.
var _root: Control = null


func _ready() -> void:
	_loc = get_node_or_null("/root/Localization")
	_input = get_node_or_null("/root/InputService")
	_bus = get_node_or_null("/root/EventBus")
	_build_ui()
	if _bus != null and not _bus.is_connected("language_changed", _on_language_changed):
		_bus.connect("language_changed", _on_language_changed)
	_refresh()


func _exit_tree() -> void:
	# Stop the level-up celebration before the HUD leaves the tree. A map transition or a
	# return to the menu can land mid-effect, and an effect still decaying toward a colour on
	# a node that is being freed is writing `modulate` on a dangling target.
	if _level_up != null and is_instance_valid(_level_up):
		_level_up.cancel()
	if _bus != null and _bus.is_connected("language_changed", _on_language_changed):
		_bus.disconnect("language_changed", _on_language_changed)
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.disconnect(_on_viewport_resized)


func _build_ui() -> void:
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root = root
	# The HUD must wear the shared theme like the menu does (D-034). A CanvasLayer cannot
	# hold a Theme, so it goes on this root Control and every panel/label below inherits the
	# asset-backed styles AND the text outline that keeps light text readable over map art.
	root.theme = UITheme.build()
	add_child(root)
	# Keep the whole HUD inside the device's usable area (notch / rounded corners / camera
	# cutout) and re-apply it whenever the viewport changes — a rotation or a window resize
	# changes the safe area, and a HUD that only reads it once would leave content under the
	# notch for the rest of the session.
	_apply_safe_area()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_on_viewport_resized):
		vp.size_changed.connect(_on_viewport_resized)

	# --- Top-left: the identity plaque -------------------------------------------
	# One plaque, two tiers: WHO I AM (portrait + name + title) above an ornamental divider,
	# WHO I BELONG TO (sect chip) below it. Before D-041 the sect lines were just two more
	# entries in the same column as the title, so the two kinds of identity blurred together.
	var identity_panel := _panel()
	# Named so a layout assertion can report WHICH plaque is wrong. The reserve test used to
	# print `@PanelContainer@5822=156`, which names nothing a reader can act on.
	identity_panel.name = "IdentityPlaque"
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
	# The well is a stack: the painted portrait UNDER the rosewood nine-patch frame, so the
	# frame's border art overlaps the portrait's edges the way a real mounted picture does.
	# The frame alone was what shipped before — an empty plate with nothing in it (D-044).
	var portrait_well := Control.new()
	portrait_well.custom_minimum_size = Vector2(
		UIPalette.IDENTITY_PORTRAIT_PX, UIPalette.IDENTITY_PORTRAIT_PX)
	portrait_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	identity_row.add_child(portrait_well)

	# The painted face. An `AtlasTexture` head crop (see `UITheme.portrait_texture`) because
	# the source is a full standing figure; inset by the frame's border so the art sits INSIDE
	# the frame rather than under its edge.
	_portrait = TextureRect.new()
	_portrait.name = "Portrait"
	# LINEAR: painted art, not pixel art — and this is a DOWNscale (310px source into a 56px
	# well), where nearest would alias the face badly.
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_portrait.offset_left = PORTRAIT_INSET
	_portrait.offset_top = PORTRAIT_INSET
	_portrait.offset_right = -PORTRAIT_INSET
	_portrait.offset_bottom = -PORTRAIT_INSET
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.texture = UITheme.portrait_texture()
	_portrait.visible = _portrait.texture != null
	portrait_well.add_child(_portrait)

	# The frame, drawn OVER the portrait — and it must be a HOLLOW one, which is why this is
	# `UITheme.ornament_frame()` and no longer `portrait_frame.png`.
	#
	# D-034 MEASURED `portrait_frame.png` at centre brightness 229: it is an opaque light
	# PANEL, not a frame. Nine-patching it over the portrait therefore painted a cream plate
	# straight across the face, and the identity plaque shipped for two phases showing an
	# empty slot that read as a missing asset — the measurement was on record and the
	# consequence of drawing an opaque centre OVER something was not drawn from it.
	# `frame_ornate.png` measures centre alpha 0, so it frames without covering (L-021).
	var portrait_frame := UITheme.ornament_frame()
	portrait_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_well.add_child(portrait_frame)

	var identity_text := VBoxContainer.new()
	identity_text.alignment = BoxContainer.ALIGNMENT_CENTER
	identity_text.add_theme_constant_override("separation", UIPalette.ROW_GAP)
	identity_row.add_child(identity_text)

	# The name shares its row with the LEVEL badge (Phase 11). Level belongs here, beside the
	# character's name, because it answers "who am I" at a glance — the phase brief ranks
	# "LEVEL must be easy to identify" first in the HUD hierarchy, and a number tucked under
	# two gauges is not at a glance. It is gold, which in this palette means structure and
	# attainment, and is the hue the XP meter below also uses so the pair reads as one idea.
	var name_row := HBoxContainer.new()
	name_row.name = "NameRow"
	name_row.add_theme_constant_override("separation", UIPalette.SPACE_MD)
	identity_text.add_child(name_row)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)

	_level_label = Label.new()
	_level_label.name = "LevelBadge"
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_level_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_level_label.add_theme_color_override("font_color", UIPalette.GOLD_PRIMARY)
	# A width FLOOR so `Cấp 1` and `Cấp 20` do not resize the plaque as the player levels —
	# a plaque that changes width on a level-up would make the whole HUD twitch.
	_level_label.custom_minimum_size = Vector2(UIPalette.LEVEL_BADGE_MIN_WIDTH, 0)
	# Hidden until a progression view arrives, for the same reason the health gauge is: a
	# badge reading `Cấp 0` for progression nothing owns is worse than no badge.
	_level_label.visible = false
	name_row.add_child(_level_label)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_title_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	identity_text.add_child(_title_label)

	# The health gauge (Phase 09). It appears NOW and not earlier because combat finally owns
	# the value it shows — the UI bible forbids a gauge for state no system owns, since a bar
	# that looks right in a mock and shows nothing real in a build is worse than no bar.
	#
	# Styled by `UITheme.vitals_gauge()`, not here: C18 requires combat UI to use the shared
	# foundation, so the next gauge (mana, cultivation progress, a boss bar) inherits the same
	# look instead of being styled again by whoever adds it.
	_health_gauge = UITheme.vitals_gauge()
	# Hidden until a real value arrives. A gauge sitting at full for health nothing has
	# reported is the same lie as a gauge for a system that does not exist yet.
	_health_gauge.visible = false
	identity_text.add_child(_health_gauge)

	# The XP meter (Phase 11), directly under the health gauge and deliberately SUBORDINATE to
	# it: thinner, and gold where health is jade. Both separations are palette tokens and both
	# matter — the phase brief requires XP not to be confusable with HP, and these two sit one
	# above the other in the same plaque, which is the hardest place to tell two bars apart.
	# The meter also WRITES its value as text ("XP 20 / 45"), so the distinction survives for
	# a player who cannot use the colour at all (`docs/UI_UX_BIBLE.md` §4).
	_xp_meter = UITheme.xp_meter()
	_xp_meter.visible = false
	identity_text.add_child(_xp_meter)

	# The level-up celebration drives the BADGE, not the meter: the meter's job is to be read
	# accurately, and a flashing bar is harder to read, while a badge catching light is
	# exactly the "something happened to me" signal a level-up wants. Presentation-only, and
	# idle (zero per-frame cost) until a level actually changes.
	# The transient level-up announcement. Anchored to the SCREEN CENTRE, deliberately outside
	# every plaque: a label that appears inside the identity plaque would grow it mid-
	# celebration, which both makes the HUD twitch and invalidates `TOP_PLAQUE_RESERVE` for
	# the duration of the effect (a hidden child contributes nothing to a container's minimum
	# size — the exact trap that produced four wrong values for that constant).
	#
	# The centre is also where it MEANS the most: the camera follows the player, so the player
	# is near the middle of the screen, and the announcement lands on them rather than in a
	# corner being reported about them.
	_level_up_banner = Label.new()
	_level_up_banner.name = "LevelUpBanner"
	_level_up_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_up_banner.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_level_up_banner.add_theme_color_override("font_color", UIPalette.GOLD_PRIMARY)
	# BOTTOM-CENTRE, in the band above the prompt strip — not the screen centre.
	#
	# Two capture-found defects led here. Centred, it printed across the player's body, because
	# the camera follows the player. Nudged up from the centre, it still did: the camera is
	# CLAMPED by the map limits, so the player's screen position moves and a fixed offset from
	# the centre just relocates the collision. A band the HUD already reserves cannot collide
	# with anything, at any resolution.
	_level_up_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_level_up_banner.offset_top -= UIPalette.LEVEL_UP_BANNER_BOTTOM_INSET
	_level_up_banner.offset_bottom -= UIPalette.LEVEL_UP_BANNER_BOTTOM_INSET
	_level_up_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_level_up_banner.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_level_up_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_up_banner.visible = false
	root.add_child(_level_up_banner)

	_level_up = LevelUpFeedbackScript.new() as LevelUpFeedback
	_level_up.name = "LevelUpFeedback"
	add_child(_level_up)
	_level_up.bind_target(_level_label)
	_level_up.bind_banner(_level_up_banner)

	# The engraved rule that separates the two identity tiers. Same art as the menu title and
	# the sect panel header, so all three screens read as one design language (D-041).
	identity_body.add_child(_divider_strip())

	# Compact sect chip (Phase 06): emblem + sect name + rank. It now lives in the plaque's
	# SECOND tier (a sibling of the portrait row), not nested beside the character title.
	var sect_chip := HBoxContainer.new()
	sect_chip.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	identity_body.add_child(sect_chip)

	_sect_emblem = TextureRect.new()
	# Named so the tier-separation test can identify it structurally. It used to be found by
	# "the only TextureRect in the plaque", which stopped being true the moment the identity
	# row gained a painted portrait (D-044) — a name is the stable marker.
	_sect_emblem.name = "SectEmblem"
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
	map_panel.name = "MapPlaque"
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

	# World time + the last thing the world did on its own (Phase 08). It belongs UNDER the
	# place name because both answer orientation questions — "where am I" and "when is it" —
	# and the UI bible ranks orientation as primary. Two muted hint lines, not a panel of its
	# own: the player should be able to notice that the world moved without them
	# (`SOCIAL_DESIGN.md` §7) without a readout competing with the playfield for attention.
	_world_date_label = Label.new()
	_world_date_label.name = "WorldDate"
	_world_date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_date_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_world_date_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	map_body.add_child(_world_date_label)

	_world_event_label = Label.new()
	_world_event_label.name = "WorldEvent"
	_world_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_world_event_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_world_event_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	_world_event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# +40% string length for vi↔en must not clip (`docs/UI_UX_BIBLE.md`), and this line is the
	# longest thing in a narrow plaque, so it wraps rather than widening the panel.
	_world_event_label.custom_minimum_size = Vector2(UIPalette.HUD_MAP_PANEL_WIDTH, 0)
	# CAPPED, so the plaque has a maximum height at all. This is the only label in a top
	# plaque sized by a sentence, and an unbounded plaque makes `TOP_PLAQUE_RESERVE`
	# unknowable — which is how the side panels came to overlap it. Two lines absorbs the
	# +40% vi<->en growth the UI bible requires; past that the line trims, because growing
	# over the playfield is worse than losing the tail of a passive hint.
	_world_event_label.max_lines_visible = UIPalette.HUD_WORLD_EVENT_MAX_LINES
	_world_event_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	map_body.add_child(_world_event_label)

	# --- Top-centre: the combat target plaque (Phase 10) --------------------------
	#
	# Between the two top plaques, which is the one region of the top strip nothing owns, and
	# centred because the thing you are FIGHTING belongs in the middle of your attention —
	# not tucked into a corner with your own identity or the date.
	#
	# Hidden until there is a target, so "not fighting anything" and "a target at 0 HP" can
	# never look the same. Built from the same `_panel()` as every other plaque, so it needs
	# no styling of its own (C18).
	_target_panel = _panel()
	_target_panel.name = "TargetPlaque"
	_target_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_panel.position = Vector2(0, UIPalette.HUD_MARGIN)
	_target_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_target_panel.custom_minimum_size = Vector2(UIPalette.HUD_MAP_PANEL_WIDTH, 0)
	_target_panel.visible = false
	root.add_child(_target_panel)

	var target_body := VBoxContainer.new()
	target_body.add_theme_constant_override("separation", UIPalette.SPACE_SM)
	_target_panel.add_child(target_body)

	_target_name_label = Label.new()
	_target_name_label.name = "TargetName"
	_target_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_name_label.add_theme_font_size_override(
		"font_size", UIPalette.FONT_SIZE_SUBTITLE)
	_target_name_label.add_theme_color_override("font_color", UIPalette.COLOR_TITLE)
	target_body.add_child(_target_name_label)

	_target_threat_label = Label.new()
	_target_threat_label.name = "TargetThreat"
	_target_threat_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_target_threat_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_HINT)
	_target_threat_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT_MUTED)
	target_body.add_child(_target_threat_label)

	# The SAME gauge factory the player's health uses, so target health and player health are
	# read the same way. A second gauge styled differently would make the player learn two
	# readouts for one concept.
	_target_gauge = UITheme.vitals_gauge()
	target_body.add_child(_target_gauge)

	# One-shot timer that retires the plaque after a kill. A `Timer` rather than a `_process`
	# countdown: it costs nothing while stopped, which matters on a node that exists for the
	# whole session and is used for a second or two per fight.
	_target_linger = Timer.new()
	_target_linger.name = "TargetLinger"
	_target_linger.one_shot = true
	_target_linger.timeout.connect(_on_target_linger_timeout)
	_target_panel.add_child(_target_linger)

	# --- Bottom-left: control-prompt panel (graphic key badges) -------------------
	var prompt_panel := _panel()
	prompt_panel.name = "PromptStrip"
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

	_faction_row = PromptRowScript.new() as UIPromptRow
	prompt_box.add_child(_faction_row)

	_menu_row = PromptRowScript.new() as UIPromptRow
	prompt_box.add_child(_menu_row)

	# --- Sect detail panel (Phase 06): hidden until the player presses `sect_panel` ----
	# Anchored on the PANEL ITSELF, directly under `root`. The previous version wrapped it in
	# an empty size-0 Control and set `grow_horizontal = BEGIN` on that WRAPPER; growth
	# direction does not propagate to children, so the panel still grew END (rightwards) from
	# the right edge and ~95% of it sat outside the viewport — only a sliver of its jade frame
	# was visible, which read as "pressing T does nothing" (D-034).
	_sect_panel = SectPanelScript.new() as SectPanel
	_bound_side_panel(_sect_panel, false)
	_sect_panel.visible = false
	root.add_child(_sect_panel)

	# --- Sect Politics panel (Phase 07): hidden until the player presses `faction_panel` ---
	# Anchored CENTER_LEFT, opposite the sect panel, and growing END (rightwards) from the
	# left edge. Anchors and growth go on the panel ITSELF, never on a wrapper: growth does
	# not propagate to children, which is what pushed the Phase-06 sect panel off-screen
	# (D-034). Both panels may be open at once by design — membership and politics are two
	# halves of one question.
	_faction_panel = FactionPanelScript.new() as FactionPanel
	_bound_side_panel(_faction_panel, true)
	_faction_panel.visible = false
	root.add_child(_faction_panel)


## Anchor a toggleable side panel as a BOUNDED BOX defined by the screen, not by its content.
##
## This is the fix for the panel that rendered without a frame and buried the control prompts.
## The old version anchored from the vertical centre with `grow_vertical = BOTH` and let the
## panel take its content's minimum size, so a long list grew past the top AND bottom of the
## viewport: the 9-slice frame is drawn at the panel's edges, and those edges were off-screen.
##
## Now all four sides are pinned to screen anchors, so the panel's height is
## `screen - margins - reserved prompt strip` at EVERY resolution and it is structurally
## incapable of overflowing or of entering the bottom strip the prompts own. Content longer
## than the box scrolls inside it (each panel owns a ScrollContainer) instead of escaping it.
func _bound_side_panel(panel: Control, on_left: bool) -> void:
	# LEFT_WIDE / RIGHT_WIDE pin top+bottom to the screen and give a full-height column; the
	# explicit offsets below then inset it. Using the and_offsets variant for the same reason
	# the menu needed it: the plain preset would preserve the current (minimum) rect.
	panel.set_anchors_and_offsets_preset(
		Control.PRESET_LEFT_WIDE if on_left else Control.PRESET_RIGHT_WIDE)
	if on_left:
		panel.offset_left = UIPalette.HUD_MARGIN
		panel.offset_right = UIPalette.HUD_MARGIN + UIPalette.SIDE_PANEL_WIDTH
	else:
		panel.offset_left = -(UIPalette.HUD_MARGIN + UIPalette.SIDE_PANEL_WIDTH)
		panel.offset_right = -UIPalette.HUD_MARGIN
	# Start BELOW the top plaque strip, not at the screen margin (D-050). A full-height side
	# panel anchored at `HUD_MARGIN` occupies the same region as the top-right map/world
	# plaque, and the sect panel was covering the place name completely — visible the moment
	# the panel was captured open, invisible to every test. Reserving the strip by name makes
	# "a side panel must not cover the plaque" arithmetic, the same way
	# `PROMPT_STRIP_RESERVE` protects the prompt row at the bottom.
	panel.offset_top = UIPalette.HUD_MARGIN + UIPalette.TOP_PLAQUE_RESERVE
	# Stop short of the bottom so the control prompts are never covered (the reserved strip).
	panel.offset_bottom = -(UIPalette.HUD_MARGIN + UIPalette.PROMPT_STRIP_RESERVE)
	# A bounded box must not be re-expanded by its own minimum size.
	panel.grow_horizontal = Control.GROW_DIRECTION_END if on_left \
		else Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_END


## Inset the whole HUD by the device's safe area (notch, rounded corners, camera cutout).
##
## `DisplayServer.get_display_safe_area()` is in native SCREEN pixels while the HUD lives in
## the stretched canvas, so the inset is converted through the viewport/window ratio — without
## that conversion the inset would be wrong by exactly the stretch factor on every device that
## actually has a notch. On desktop the safe area equals the screen, so every inset is 0 and
## this is a no-op.
func _apply_safe_area() -> void:
	if _root == null:
		return
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var window_size := DisplayServer.window_get_size()
	if window_size.x <= 0 or window_size.y <= 0:
		return
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return
	var vp := get_viewport()
	if vp == null:
		return
	var canvas := vp.get_visible_rect().size
	var sx := canvas.x / float(window_size.x)
	var sy := canvas.y / float(window_size.y)
	_root.offset_left = maxf(0.0, float(safe.position.x) * sx)
	_root.offset_top = maxf(0.0, float(safe.position.y) * sy)
	_root.offset_right = -maxf(0.0, float(screen.x - safe.end.x) * sx)
	_root.offset_bottom = -maxf(0.0, float(screen.y - safe.end.y) * sy)


func _on_viewport_resized() -> void:
	_apply_safe_area()


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
## Delegates to the ONE divider factory (D-050). It used to build its own `TextureRect` with
## its own filter/stretch/size, and so did the main menu — duplicated styling that had already
## produced a visible bug (the stretched jade divider read as a progress bar in every panel
## header). The HUD now asks the theme, like it asks for every other style.
func _divider_strip() -> TextureRect:
	return UITheme.ornament_divider()


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


## Push the player's health into the gauge (Phase 09). Called by whoever connects the player's
## `health_changed` signal — the HUD never reads a HealthComponent itself, so it stays a view.
##
## A non-positive maximum HIDES the gauge instead of showing an empty one: "no health has been
## reported" and "this character is at 0 HP" are different states, and rendering them the same
## way would make a wiring failure look like a death.
func set_health(current: int, maximum: int) -> void:
	if _health_gauge == null:
		return
	if maximum <= 0:
		_health_gauge.visible = false
		return
	_health_gauge.visible = true
	UITheme.set_gauge_value(_health_gauge, current, maximum)


## Is the health gauge currently shown? (for tests — the gauge's visibility IS its contract.)
func is_health_gauge_visible() -> bool:
	return _health_gauge != null and _health_gauge.visible


## Push the player's read-only level/XP view (Phase 11). Pushed by the owner (MapBase, fed by
## WorldRuntime → ProgressionRuntime) on map arrival and on every XP change — never polled.
##
## An unavailable view HIDES the badge and the meter rather than blanking them: "no
## progression session" and "a fresh character at level 1 with no XP" are different states,
## and rendering them the same way would make a wiring failure look like a new game.
func set_progression_view(view: ProgressionView) -> void:
	_progression_view = view
	if _level_label == null or _xp_meter == null:
		return
	var available := view != null and view.available
	_level_label.visible = available
	_xp_meter.visible = available
	if not available:
		return
	_refresh_progression()


## Play the one-shot level-up celebration. Called by the owner when `level_changed` fires.
##
## The HUD does not decide WHEN a level-up happened — it is told. It only decides what one
## looks like, which is the division `03-architecture.md` requires: the gameplay layer reports
## the event and owns no presentation decision.
func celebrate_level_up(level: int) -> void:
	if _level_up_banner != null:
		_level_up_banner.text = _text_args("UI_HUD_LEVEL_UP", {"level": level})
	if _level_up != null and is_instance_valid(_level_up):
		_level_up.celebrate(level)


## Is the progression row shown? (for tests — its visibility IS the contract.)
func is_progression_visible() -> bool:
	return _level_label != null and _level_label.visible


## The level-up effect, so a test can drive its clock deterministically.
func level_up_feedback() -> LevelUpFeedback:
	return _level_up


## Render the level badge + XP meter from the cached view.
##
## Separate from `set_progression_view` so a LANGUAGE CHANGE re-renders the existing numbers
## without the progression session needing to push again — the same reason the target plaque
## and the world-sim lines each have their own refresh.
func _refresh_progression() -> void:
	if _level_label == null or _xp_meter == null:
		return
	if _progression_view == null or not _progression_view.available:
		return
	_level_label.text = _text_args("UI_HUD_LEVEL", {"level": _progression_view.level})
	var text := ""
	if _progression_view.at_ceiling:
		text = _text("UI_HUD_XP_COMPLETE")
	else:
		text = _text_args("UI_HUD_XP_PROGRESS", {
			"into": _progression_view.xp_into_level,
			"cost": _progression_view.xp_for_next,
		})
	UITheme.set_xp_meter_value(_xp_meter, _progression_view.xp_into_level,
		_progression_view.xp_for_next, _progression_view.at_ceiling, text)


## Show what the player is fighting (Phase 10). A null or empty view HIDES the plaque.
##
## Pushed by the combat session when a target's health changes or it dies — never polled, so
## the HUD does no per-frame work (`05-performance-testing.md`). The view is cached so a
## language change can re-resolve its keys without the session pushing again.
func set_target_view(view: CombatTargetView) -> void:
	_target_view = view
	if _target_panel == null:
		return
	if view == null or not view.has_target:
		_target_panel.visible = false
		_target_linger.stop()
		return
	_target_panel.visible = true
	UITheme.set_gauge_value(_target_gauge, view.current_health, view.max_health)
	_refresh_target_text()
	# A DEAD target lingers, then goes. Long enough to read what you killed, short enough that
	# the plaque is not still advertising a corpse minutes later. A live target cancels the
	# timer, so taking a second creature's attention keeps the panel up.
	if view.is_dead:
		_target_linger.start(UIPalette.TARGET_PLAQUE_LINGER)
	else:
		_target_linger.stop()


## The dead target has been on screen long enough: retire the plaque.
func _on_target_linger_timeout() -> void:
	if _target_panel != null:
		_target_panel.visible = false


## Is the target plaque shown? (for tests — its visibility IS the contract.)
func is_target_panel_visible() -> bool:
	return _target_panel != null and _target_panel.visible


## Resolve the target's localization keys. Separate from `set_target_view` so a language change
## re-renders the existing target instead of needing the combat session to re-push it.
func _refresh_target_text() -> void:
	if _target_view == null or not _target_view.has_target or _loc == null:
		return
	_target_name_label.text = _resolve(_target_view.name_key)
	# A dead target keeps its name and gauge but loses its threat line: the rating describes a
	# live danger, and leaving it up over a corpse reads as the UI not having noticed.
	if _target_view.is_dead or _target_view.threat_key == &"":
		_target_threat_label.text = ""
	else:
		_target_threat_label.text = _resolve(_target_view.threat_key)


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


## Push the read-only sect politics view (Phase 07). The owner (MapBase, fed by
## WorldRuntime→FactionRuntime) rebuilds + pushes this on map arrival / politics change — NOT
## per frame.
func set_politics_view(view: SectPoliticsView) -> void:
	_politics_view = view
	if _faction_panel != null:
		_faction_panel.set_view(view)


## Push the read-only world-simulation view (Phase 08). The owner (MapBase, fed by
## WorldRuntime→WorldSimulationRuntime) rebuilds + pushes this on map arrival and after the
## world has ticked — NOT per frame.
func set_world_sim_view(view: WorldSimView) -> void:
	_world_sim_view = view
	_refresh_world_sim()


## Semantic `sect_panel` / `faction_panel` intent toggles the matching panel. Driven through
## InputService (gated to GAMEPLAY context) — never a raw keycode (L-003). Read + handle
## locally, then mark the input handled; no scene teardown happens here so this is a safe
## place to touch the viewport.
func _unhandled_input(_event: InputEvent) -> void:
	if _input == null:
		return
	var handled := false
	if _sect_panel != null \
			and _input.call("is_gameplay_action_just_pressed", SECT_PANEL_ACTION):
		_sect_panel.visible = not _sect_panel.visible
		handled = true
	if _faction_panel != null \
			and _input.call("is_gameplay_action_just_pressed", FACTION_PANEL_ACTION):
		_faction_panel.visible = not _faction_panel.visible
		handled = true
	if handled:
		var vp := get_viewport()
		if vp != null:
			vp.set_input_as_handled()


## Is the Sect detail panel currently shown? (for tests)
func is_sect_panel_open() -> bool:
	return _sect_panel != null and _sect_panel.visible


## Is the Sect Politics panel currently shown? (for tests)
func is_faction_panel_open() -> bool:
	return _faction_panel != null and _faction_panel.visible


# --- Rendering ---------------------------------------------------------------

func _refresh() -> void:
	if _name_label == null:
		return  # not built yet
	_name_label.text = _resolve(_name_key)
	_title_label.text = _resolve(_title_key)
	_title_label.visible = _title_key != &""
	_map_label.text = _resolve(_map_name_key)
	# Re-resolve the combat target too, so a language change relabels what the player is
	# fighting without the combat session having to push the view again.
	_refresh_target_text()
	_refresh_sect_chip()
	_refresh_progression()
	_refresh_world_sim()
	_refresh_prompts()


## Render world time + the last world event from the read-only view (Phase 08).
##
## With no simulation the two lines are HIDDEN rather than blanked: an empty label still
## occupies its row in the plaque, so blanking would leave a gap that reads as a broken layout.
##
## The event line names WHAT KIND of thing moved and WHICH WAY, never the subject and never a
## raw id (see `WorldSimView`'s note on why the subject has to wait for a phase that can name
## things). The magnitude's SIGN picks the verb, so vi and en each read as a sentence instead
## of as "influence +3", which would need no translation and convey less.
func _refresh_world_sim() -> void:
	if _world_date_label == null or _world_event_label == null:
		return
	if _world_sim_view == null or not _world_sim_view.available:
		_world_date_label.visible = false
		_world_event_label.visible = false
		return
	_world_date_label.visible = true
	_world_date_label.text = _text_args("UI_HUD_WORLD_DATE", {
		"year": _world_sim_view.year,
		"season": _world_sim_view.season,
		"day": _world_sim_view.day,
	})
	_world_event_label.visible = true
	if not _world_sim_view.has_last_event():
		_world_event_label.text = _text("UI_HUD_WORLD_QUIET")
		return
	var subject := _resolve(_world_sim_view.last_event_kind_key)
	var template := "UI_HUD_WORLD_EVENT_ROSE" if _world_sim_view.last_event_magnitude >= 0 \
		else "UI_HUD_WORLD_EVENT_FELL"
	_world_event_label.text = _text_args(template, {"subject": subject})


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
	# Politics prompt: also always available. The player can read a sect's internal argument
	# without belonging to a faction — that is how they decide whether to take a side at all.
	if _faction_row != null:
		var faction_key := _display_label(FACTION_PANEL_ACTION)
		_faction_row.set_prompt(faction_key, _text("UI_FACTION_PANEL_TOGGLE"))


func _display_label(action: StringName) -> String:
	if _input == null:
		return "?"
	return String(_input.call("get_action_display_label", action))


func _text(key: String) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t", key))


## Localized text with `{placeholder}` substitution (`Localization.t_args`). Used for the
## world date + event lines, which are SENTENCES with numbers in them — building them by
## concatenation would break grammar across languages (`07-localization.md`).
func _text_args(key: String, args: Dictionary) -> String:
	if _loc == null:
		return key
	return String(_loc.call("t_args", key, args))


func _on_language_changed(_language_code: String) -> void:
	_refresh()
