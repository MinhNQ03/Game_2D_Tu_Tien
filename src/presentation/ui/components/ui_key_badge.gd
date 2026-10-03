extends PanelContainer
class_name UIKeyBadge
## UIKeyBadge — Aetheria presentation (reusable key-prompt chip).
##
## Renders a single key as a graphic keycap chip — the asset-backed `UITheme.badge_stylebox()`
## 9-slice frame with the key's DISPLAY LABEL centered on it (e.g. a jade-framed "E" / "Esc").
## It is a pure presentation widget: given a label string it draws the badge; it never reads
## physical keycodes or the InputMap itself. The owner (HUD) resolves the label through
## `InputService.get_action_display_label(action)` and passes it in, so the single owner of
## key→label mapping stays `InputService` (L-003) and badges show real glyphs, never raw
## action names or "Press E" text.
##
## Used in ≥2 places (interact + menu prompts, and any future prompt), which is why it is a
## shared component rather than inline markup (`08-ai-review-protocol.md` no-duplication).

var _label: Label


func _ready() -> void:
	add_theme_stylebox_override("panel", UITheme.badge_stylebox())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _label == null:
		_build()


func _build() -> void:
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", UIPalette.FONT_SIZE_BADGE)
	_label.add_theme_color_override("font_color", UIPalette.COLOR_TEXT)
	# A keycap reads best at least as wide as it is tall; enforce a square-ish minimum.
	_label.custom_minimum_size = Vector2(UIPalette.FONT_SIZE_BADGE, 0)
	add_child(_label)


## Set the key glyph to show (already resolved by InputService, e.g. "E", "Esc"). Safe to
## call before or after the node enters the tree.
func set_key_label(text: String) -> void:
	if _label == null:
		_build()
	_label.text = text
