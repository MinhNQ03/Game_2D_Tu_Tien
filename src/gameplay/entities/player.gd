extends CharacterBody2D
class_name Player
## Player — Aetheria gameplay entity (composition coordinator).
##
## A `CharacterBody2D` assembled from components (`docs/ARCHITECTURE.md` §3,
## `docs/CHARACTER_SYSTEM.md` §6) — NOT an inheritance chain and NOT a God object. It only
## COORDINATES; it owns no rules:
##   - reads SEMANTIC intent from `InputService` (never physical keys) and forwards it to
##     MovementComponent (`docs/MULTIPLAYER_PLAN.md` §3 intent boundary),
##   - initializes HealthComponent from StatsComponent,
##   - exposes a minimal attack INTENT (`attack_requested`) + stat reads for a gameplay
##     coordinator to resolve a hit via the domain rule,
##   - re-exposes health signals for a HUD/coordinator.
##
## It contains NO damage math, NO max-HP calc, NO inventory/quest/cultivation/save/story,
## and reads NO raw input. The player is "a Character conceptually" (Phase 04): authoritative
## numbers live in the StatBlock (data); this node is a runtime view, so Phase 04 can bind
## the same composition to a CharacterState without a rewrite.

## Emitted when the player expresses an attack intent this frame. The sandbox/gameplay
## coordinator decides what it hits and resolves damage via the domain `DamageRules` — the
## player never computes or applies combat damage itself.
signal attack_requested()

## Re-exposed health signals (direct, local). A HUD/coordinator connects to these instead
## of reaching into the HealthComponent across the tree.
signal health_changed(current: int, maximum: int)
signal died()

const ATTACK_ACTION := &"attack"

const VisualComponentScript := preload(
	"res://src/presentation/characters/character_visual_component.gd")

@onready var _stats: StatsComponent = $StatsComponent
@onready var _health: HealthComponent = $HealthComponent
@onready var _movement: MovementComponent = $MovementComponent
@onready var _static_visual: Sprite2D = $Visual
## The attack driver (Phase 09). Present in the scene but UNARMED until `CombatRuntime` arms
## it, so a player realized outside a combat session simply cannot swing — rather than
## swinging into a world with no registry and no service.
@onready var _attack: AttackComponent = $AttackComponent

var _input: Node = null

## Resource path of the character's VISUAL profile (`CharacterVisualProfileData`), taken from
## the bound character's `CharacterTemplateData.sprite_set_ref` (presentation ref — NOT on the
## domain CharacterState, Phase 05 / D-026). Empty = keep the scene's static prototype sprite.
var _visual_profile_path: String = ""
var _visual: CharacterVisualComponent = null

## The authoritative CharacterState this node realizes (Phase 04, `docs/CHARACTER_SYSTEM.md`
## §6). The player node is a runtime VIEW; identity + stats + life-state truth live here. Set
## ONCE by the session owner (`WorldRuntime`) via `bind_character_state()` BEFORE the node is
## added to the tree, so `_ready()` initializes the composition from the one source of truth.
## When null (isolated harness/test), the node falls back to the authored StatBlock.
var _character_state: CharacterState = null


## Bind the authoritative CharacterState BEFORE adding this node to the tree. Idempotent-ish:
## intended to be called once per realization. Also pushes the state into the StatsComponent
## so stat reads come from the domain authority, not a parallel copy.
func bind_character_state(state: CharacterState) -> void:
	_character_state = state
	# `_stats` is an @onready var; it is only resolved once the node is in the tree. Guard so
	# a pre-tree bind doesn't touch a null — `_ready()` re-applies the binding to the
	# component. If called after _ready (rebind), apply immediately.
	if is_node_ready():
		_stats.bind_character_state(state)


## The authoritative CharacterState this node realizes (or null in an isolated harness).
## Turn to face `world_point` while standing (Phase 18: the player turns to whoever they are
## speaking with). Facing only — the same two consumers the movement intent feeds: the visual
## and the attack component's aim. It moves nobody.
func face_toward(world_point: Vector2) -> void:
	var toward := world_point - global_position
	if toward.length() < 0.5:
		return
	if _visual != null:
		_visual.update_facing(toward.normalized(), false)
	if _attack != null:
		_attack.set_facing(toward.normalized())


func get_character_state() -> CharacterState:
	return _character_state


## Set the visual profile resource path (from the template's `sprite_set_ref`). Call BEFORE
## the node enters the tree (like `bind_character_state`); `_ready()` resolves + attaches the
## `CharacterVisualComponent`. If called after _ready, applies immediately. Empty path leaves
## the scene's static prototype sprite in place (isolated-harness fallback). Presentation only.
func set_visual_profile_from_ref(profile_path: String) -> void:
	_visual_profile_path = profile_path
	if is_node_ready():
		_apply_visual_profile()


## The CharacterVisualComponent (or null if no profile was applied). For tests/debug.
func get_visual_component() -> CharacterVisualComponent:
	return _visual


func _ready() -> void:
	# Collision wiring from the single source of truth (`CollisionLayers`), not scene magic
	# numbers: the player occupies the PLAYER layer and collides with WORLD (walls) and the
	# DUMMY body. Done FIRST (before the stats check) so the body is always correctly layered
	# even if the entity later fails closed — the named constants are the one authority.
	collision_layer = CollisionLayers.PLAYER
	collision_mask = CollisionLayers.WORLD | CollisionLayers.DUMMY

	# Make the StatsComponent a VIEW of the authoritative state (if one was bound before the
	# node entered the tree). After this, `_stats` reads the character's current numbers.
	if _character_state != null:
		_stats.bind_character_state(_character_state)

	# Fail CLOSED on invalid/missing stat source: a broken scene must not quietly run as if
	# valid (`04-coding-standards.md`: fail loud; no silent-fallback as the normal path).
	# `validate()` already reports loudly; here we stop wiring and disable processing so the
	# entity is inert rather than half-initialized. Valid state/`.tres` take the normal path.
	if not _stats.validate():
		set_physics_process(false)
		push_error("[player] invalid stat source; player disabled (fail-closed)")
		return

	# Initialize runtime health from the authority. With a bound state, max comes from the
	# state and current from the state's authoritative current_hp (so a loaded save restores
	# wounded HP); without a state, start full from the StatBlock max.
	if _character_state != null:
		_health.initialize(_stats.get_max_hp(), _character_state.current_hp)
	else:
		_health.initialize(_stats.get_max_hp())
	_movement.setup(self)

	# Forward component signals outward as player-level signals (local, direct).
	_health.health_changed.connect(_on_health_changed)
	_health.died.connect(_on_health_died)

	# InputService is the ONLY input source (semantic gateway). Resolved once here, not
	# every physics frame, to avoid a per-tick tree lookup (`docs/PERFORMANCE.md`).
	_input = get_node_or_null("/root/InputService")

	# Resolve the data-driven visual profile (if the bound template set a sprite_set_ref).
	_apply_visual_profile()


## Resolve `_visual_profile_path` to a CharacterVisualProfileData and attach a
## CharacterVisualComponent that renders it, hiding the scene's static prototype sprite. A
## missing/invalid profile is reported loudly and leaves the static sprite as a fallback
## (presentation degrades, gameplay unaffected). An empty path is the no-op harness default.
func _apply_visual_profile() -> void:
	if _visual_profile_path == "":
		return
	if _visual != null and is_instance_valid(_visual):
		return  # already applied
	if not ResourceLoader.exists(_visual_profile_path):
		push_error("[player] visual profile missing: %s" % _visual_profile_path)
		return
	var profile := load(_visual_profile_path) as CharacterVisualProfileData
	if profile == null:
		push_error("[player] sprite_set_ref did not load as CharacterVisualProfileData: %s"
			% _visual_profile_path)
		return
	_visual = VisualComponentScript.new() as CharacterVisualComponent
	# NAMED, like the enemy's (D-056 review pass). It was the one anonymous visual component
	# in the project, so it could only be reached through `get_visual_component()` or by class
	# — which is why `AIComponent` resolves it by CLASS with a comment about scenes naming
	# freely. An anonymous node also means a debug readout or a failing assertion can only
	# quote Godot's generated name (L-040).
	_visual.name = "CharacterVisualComponent"
	add_child(_visual)
	if not _visual.setup(profile):
		# Invalid profile: drop the component, keep the static fallback sprite.
		_visual.queue_free()
		_visual = null
		return
	# The data-driven visual replaces the scene's static prototype sprite.
	if _static_visual != null and is_instance_valid(_static_visual):
		_static_visual.visible = false


func _physics_process(delta: float) -> void:
	# No input service (e.g. an isolated unit harness) → no movement; deterministic.
	if _input == null:
		return
	var intent: Vector2 = _input.call("get_move_vector")
	# A swing in flight is a commitment: the attack's authored data decides how much speed the
	# player keeps through it (D-057B), so the strike is planted rather than skated.
	var speed := _stats.get_move_speed()
	if _attack != null:
		speed *= _attack.movement_scale()
	if _cast_rooted:
		speed = 0.0  # a cast in progress roots the caster (Phase 15, SkillRuntime decides)
	_movement.apply_intent(intent, speed, delta)

	# Drive the data-driven visual facing/animation from the SAME intent (presentation only;
	# MovementComponent remains the movement authority). No-op when no profile is attached.
	if _visual != null:
		_visual.update_facing(intent, intent != Vector2.ZERO)

	# Facing is pushed to the ATTACK component from the same intent that drives movement and
	# the visual, so a swing points where the player is actually looking. The component
	# ignores a zero vector, which is what makes a standing player keep the facing they
	# stopped with instead of swinging in no direction (Phase 09).
	if _attack != null:
		_attack.set_facing(intent)

	# Edge-triggered attack INTENT. The service gates this on GAMEPLAY context, so an open
	# menu/modal can never leak an attack to the world.
	if not _cast_rooted and _input.call("is_gameplay_action_just_pressed", ATTACK_ACTION):
		# The signal is kept for the Phase-02 sandbox coordinator, which still resolves its
		# own hit. In a real session the AttackComponent owns the swing, and it REFUSES while
		# one is in flight — that refusal is the commitment rule, so it must not be worked
		# around by also emitting a second resolution path here.
		if _attack == null or not _attack.request_attack():
			attack_requested.emit()


# --- Stat reads (for a gameplay coordinator resolving a hit via DamageRules) ---

func get_attack_power() -> int:
	return _stats.get_attack()


func get_defense() -> int:
	return _stats.get_defense()


# --- Health access (intent-revealing; UI/coordinator never mutate fields directly) ---

## A cast in progress roots the caster and holds the basic attack (Phase 15). Set by
## `SkillRuntime`, which owns the cast's timing; the body only obeys.
var _cast_rooted: bool = false


func set_cast_rooted(rooted: bool) -> void:
	_cast_rooted = rooted


func is_cast_rooted() -> bool:
	return _cast_rooted


## Apply what the player wears (Phase 14), from `EquipmentRuntime`: the stat bonus enters the
## damage formula through `StatsComponent`, the attack is swapped on the `AttackComponent`, and
## the body is redrawn from the garment's visual profile (or the template's own when null).
func apply_equipment(attack_bonus: int, defense_bonus: int, attack: AttackData,
		body_visual: CharacterVisualProfileData) -> bool:
	_stats.set_equipment_bonus(attack_bonus, defense_bonus)
	var ok := true
	if attack != null and _attack != null:
		ok = _attack.swap_attack(attack)
	var profile := body_visual
	if profile == null and _visual_profile_path != "":
		profile = load(_visual_profile_path) as CharacterVisualProfileData
	if profile != null and _visual != null and is_instance_valid(_visual):
		_visual.setup(profile)
	var weapon_look := get_node_or_null("EquipmentFeedback")
	if weapon_look != null and weapon_look.has_method("show_weapon"):
		weapon_look.call("show_weapon", attack.weapon_family if attack != null else &"")
	return ok


func take_damage(amount: int) -> int:
	return _health.apply_damage(amount)


func heal(amount: int) -> int:
	return _health.heal(amount)


func get_current_health() -> int:
	return _health.get_current_health()


func get_max_health() -> int:
	return _health.get_max_health()


func is_dead() -> bool:
	return _health.is_dead()


func _on_health_changed(current: int, _maximum: int) -> void:
	# Keep the authoritative CharacterState's current_hp in sync with the runtime health view
	# (the domain stays the single source of truth; a future save reads current_hp from it).
	if _character_state != null:
		_character_state.set_current_hp(current)
	health_changed.emit(current, _maximum)


func _on_health_died() -> void:
	# Propagate the runtime death into the authoritative life-state (ALIVE -> DEAD, once).
	# The domain rejects a second kill; death_cause is left empty here (the sandbox/combat
	# phase that computes the hit will supply a cause when it exists).
	if _character_state != null:
		_character_state.mark_dead()
	died.emit()
