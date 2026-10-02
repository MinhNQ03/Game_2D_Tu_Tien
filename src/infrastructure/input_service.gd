extends Node
## InputService — Aetheria infrastructure (autoload "InputService").
##
## Exposes SEMANTIC input intent and owns INPUT GATING. Gameplay/UI never read physical
## keys (`if event.keycode == KEY_W`); they ask this service for intent expressed in named
## InputMap actions (CORE / §11). Whether the player used keyboard, gamepad, or (future)
## network input is invisible to callers.
##
## Gating ownership (§12): a single context stack decides who may act, with priority
##   UI_MODAL > MENU/SYSTEM > GAMEPLAY
## instead of scattering is_menu_open / is_paused flags across many nodes. Gameplay intent
## only resolves when the top context is GAMEPLAY, so a modal above gameplay can never
## leak movement/attack to the world behind it.
##
## This service does NOT run `_process`; callers poll intent when they need it (e.g. a
## future player controller in its own `_physics_process`). No per-frame cost here.

enum Context { GAMEPLAY, MENU, UI_MODAL }

## Semantic actions this layer relies on. Kept here so tests can assert the InputMap has
## them and so there is one authoritative list of the Phase-1 vocabulary.
const SEMANTIC_ACTIONS := [
	"move_up", "move_down", "move_left", "move_right",
	"interact", "attack",
	"skill_1", "skill_2", "skill_3", "skill_4",
	"dodge", "open_menu", "pause",
]

## Context stack. Bottom is the implicit baseline; we start in a non-gameplay MENU at boot.
var _context_stack: Array[int] = [Context.MENU]


# --- Context / gating --------------------------------------------------------

func current_context() -> int:
	return _context_stack[_context_stack.size() - 1]


## Push a higher-priority context (e.g. opening a modal). Returns the new top.
func push_context(ctx: int) -> int:
	_context_stack.append(ctx)
	return current_context()


## Pop the top context (e.g. closing a modal). Never pops the last baseline entry.
func pop_context() -> int:
	if _context_stack.size() > 1:
		_context_stack.pop_back()
	else:
		push_warning("[input] pop_context ignored: baseline context must remain")
	return current_context()


# --- Semantic context API (preferred call sites) -----------------------------
# Presentation/gameplay use these intent-revealing methods instead of pushing raw enum
# ints, so no magic numbers leak into call sites (`.kiro/steering/04-coding-standards.md`).
# Each hard scene/lifecycle change resets the stack to a single baseline so a stale modal
# context can never survive a transition (§15).

## A content/gameplay scene becomes the active input owner (resets stack to GAMEPLAY).
func set_gameplay_context() -> void:
	_reset_to(Context.GAMEPLAY)


## A menu becomes the active input owner (resets stack to MENU).
func set_menu_context() -> void:
	_reset_to(Context.MENU)


## Open a UI modal above the current context (suppresses gameplay intent beneath it).
## Returns the new top context.
func push_modal_context() -> int:
	return push_context(Context.UI_MODAL)


## Replace the whole stack with a single baseline context. Internal: callers use the
## intent-revealing wrappers above rather than passing a raw enum int.
func _reset_to(ctx: int) -> void:
	_context_stack = [ctx]


func is_gameplay_active() -> bool:
	return current_context() == Context.GAMEPLAY


# --- Semantic intent (only resolves when gameplay owns input) ----------------

## Normalized movement intent, or Vector2.ZERO when gameplay is not the active context.
## Uses named actions, so the physical device is irrelevant.
func get_move_vector() -> Vector2:
	if not is_gameplay_active():
		return Vector2.ZERO
	return Input.get_vector("move_left", "move_right", "move_up", "move_down")


## True if a gameplay action's semantic intent is active this frame. Gated by context.
func is_gameplay_action_pressed(action: StringName) -> bool:
	if not is_gameplay_active():
		return false
	return InputMap.has_action(action) and Input.is_action_pressed(action)


## Edge-triggered variant for "just pressed" gameplay intent.
func is_gameplay_action_just_pressed(action: StringName) -> bool:
	if not is_gameplay_active():
		return false
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


## Menu/system actions (open_menu, pause) are allowed above gameplay too; the caller that
## owns the menu layer decides what to do. This does NOT gate on GAMEPLAY context.
func is_system_action_just_pressed(action: StringName) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


## Returns the list of semantic actions missing from the project's InputMap. Used by tests
## to assert the vocabulary exists; empty array == all present.
func missing_actions() -> Array[String]:
	var missing: Array[String] = []
	for action in SEMANTIC_ACTIONS:
		if not InputMap.has_action(action):
			missing.append(action)
	return missing
