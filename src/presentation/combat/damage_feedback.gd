extends Node
class_name DamageFeedback
## DamageFeedback — Aetheria presentation (makes TAKING a hit, and DYING, visible).
##
## The receiving half of combat feedback, and the pair to `AttackFeedback`: that node draws the
## swing an entity makes, this one marks the entity that is hit. It owns its parent's
## `modulate` channel entirely — a damage flash while alive, a corpse look once dead — and
## nothing else writes it.
##
## WHY IT EXISTS. Phase 10 shipped the attacking half and left the receiving half with nothing:
## the player's health number simply dropped, with no mark on the character, so "why did I just
## lose 9 HP" was answerable only by having watched the right creature at the right moment. The
## review pass scored combat readability 4/5 for exactly this. On the other side, a player's
## swing landed with no confirmation on the creature either — only a gauge moving inside a HUD
## plaque, which is the wrong place to look during a fight. `COMBAT_DESIGN.md` §1 asks that
## hitting feel good and threats be readable; damage that leaves no mark on the thing damaged
## fails both.
##
## WHY IT OWNS THE DEATH LOOK TOO. `Enemy._on_health_died()` originally set a `Color(...)`
## literal on itself. That made a gameplay entity the author of a presentation decision (a
## colour no palette edit could reach — the same layer mistake as L-036), and it made TWO nodes
## writers of one property, so the flash and the corpse tint had to be careful not to overwrite
## each other. One owner, driven by the signals the entity already emits, removes both problems:
## the entity reports what happened to it and this node decides what that looks like.
##
## IT IS PURE PRESENTATION. It listens to `HurtboxComponent.damaged` — which carries what was
## ACTUALLY applied — plus the entity's own `died` / `health_changed`. It decides nothing,
## resolves nothing, and deleting it changes no outcome. Attaching one is a scene edit, which
## is why the player, the wolf and the training dummy all get the same feedback without a line
## of shared entity code (`03-architecture.md`: composition).
##
## IT COSTS NOTHING WHEN IDLE. `_process` is off until a hit lands and switches itself off
## again when the flash has decayed. Every creature carries one of these, so an always-on
## `_process` here would be N callbacks per frame for an effect that runs for a sixth of a
## second per hit (`05-performance-testing.md`).
##
## IT WRITES THE PARENT'S `modulate`, NOT A SPRITE'S. A `CanvasItem`'s modulate cascades to its
## children, so one write covers whatever visual the entity happens to own — the player's
## placeholder `Sprite2D`, the wolf's runtime-built `CharacterVisualComponent`, and anything
## that replaces either. Resolving "the visual node" instead would mean knowing three node
## names, one of which does not exist yet when this node is ready. The trade is that a flash
## also tints the entity's own drawn swing arc for those few frames; the whole creature
## flashing is a defensible reading of being hit, and it is the cheaper half of the trade.

## How far toward the full hit tint a flash goes, in [0, 1] (D-057B). 1.0 for a living body —
## the crimson flash is the language of "this creature was hurt". A struck OBJECT answers in
## its own material instead (the straw post wobbles and sheds chaff, `HitReaction`), and a full
## crimson flash turned the whole post into a red silhouette that hid both — so the post warms
## for an instant rather than bleeding. The hue is unchanged; only the strength is authored.
@export_range(0.0, 1.0) var flash_strength: float = 1.0

## The entity whose modulate is driven. Its own node, resolved once.
var _target: CanvasItem = null

## The damage source listened to. Null is legal and inert — see `_ready`.
var _hurtbox: HurtboxComponent = null

## The entity's resting colour, captured before anything is written. Captured ONCE: re-reading
## it at the start of each flash would snapshot the previous flash's tint whenever two hits
## land close together, and the sprite would never find its way back.
var _base: Color = Color.WHITE

## The colour this flash started from, and its length. `_duration <= 0.0` IS the idle state —
## one value, so "is it flashing" cannot disagree with "is it processing".
var _tint: Color = Color.WHITE
var _duration: float = 0.0
var _elapsed: float = 0.0

## Is the entity currently wearing its corpse look? Tracked rather than re-derived, because
## clearing it is a TRANSITION (dead -> alive again) and not a state: `health_changed` also
## fires on every ordinary hit and heal, and reacting to those would cut a flash short.
var _corpse: bool = false


func _ready() -> void:
	set_process(false)
	_target = get_parent() as CanvasItem
	if _target == null:
		push_error("[damage_feedback] parent is not a CanvasItem; it has no modulate to drive")
		return
	_base = _target.modulate
	var hurtbox := get_parent().get_node_or_null("HurtboxComponent") as HurtboxComponent
	if hurtbox != null:
		_hurtbox = hurtbox
		_hurtbox.damaged.connect(_on_damaged)
	# Duck-typed, like the rest of the combat contract: an entity that can die exposes `died`,
	# and one that cannot simply never gets a corpse look. A missing signal is a correct scene,
	# not a mis-wired one, so neither absence is reported.
	var entity := get_parent()
	if entity.has_signal("died"):
		entity.connect("died", _on_died)
	if entity.has_signal("health_changed"):
		entity.connect("health_changed", _on_health_changed)


# === Being hit ==============================================================

## A hit landed. `amount` is what was actually applied, so an absorbed hit reports 0 and must
## not flash — feedback for damage that did not happen is worse than none.
func _on_damaged(amount: int, is_critical: bool, _push_direction: Vector2 = Vector2.ZERO) -> void:
	if amount <= 0:
		return
	if _is_dead():
		# The killing blow. `died` already fired (health is applied, death fires, then the
		# hurtbox reports what landed), so the corpse look is on and must not be flashed over.
		_go_idle()
		return
	var full := UIPalette.HIT_FLASH_TINT_CRITICAL if is_critical else UIPalette.HIT_FLASH_TINT
	_tint = Color.WHITE.lerp(full, flash_strength)
	_duration = UIPalette.HIT_FLASH_SECONDS_CRITICAL if is_critical \
		else UIPalette.HIT_FLASH_SECONDS
	_elapsed = 0.0
	_target.modulate = _tint
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## Decay the flash by `delta` seconds. PUBLIC so a test can drive it deterministically instead
## of waiting on real frames — the same contract as `CharacterVisualComponent.advance()`, and
## the reason this effect is a decaying lerp on an explicit clock rather than a `Tween`: a
## tween cannot be stepped from a headless test.
func advance(delta: float) -> void:
	if _target == null or _duration <= 0.0:
		return
	if _is_dead():
		_go_idle()
		return
	_elapsed += delta
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	if t >= 1.0:
		# ASSIGNED, not lerped. `lerp(base, 1.0)` is only approximately the endpoint in
		# floating point, so decaying to it would leave a few ten-millionths of tint behind
		# every hit and a long fight would drift. The resting colour is restored exactly.
		_target.modulate = _base
		_go_idle()
		return
	_target.modulate = _tint.lerp(_base, t)


# === Dying, and coming back ==================================================

## Dead: wear the corpse look, and abandon any flash in flight rather than letting it decay
## back to a living colour over a body. Restoring a value that is no longer the truth is the
## L-023 mistake in miniature.
func _on_died() -> void:
	_go_idle()
	_corpse = true
	if _target != null:
		_target.modulate = UIPalette.CORPSE_TINT


## Only a REVIVAL clears the corpse look. `health_changed` also fires on every ordinary hit and
## heal — reacting to those would cut a flash short, since a hit reports its new health BEFORE
## the hurtbox reports the damage. The only live revival is `TrainingDummy.reset_dummy()`,
## which re-initializes health and so arrives here with a positive value.
func _on_health_changed(current: int, _maximum: int) -> void:
	if not _corpse or current <= 0:
		return
	_corpse = false
	if _target != null:
		_target.modulate = _base


# === Internals ==============================================================

## Stop flashing and stop costing anything. Deliberately does NOT write `modulate`: every
## caller has already left the sprite at the colour it should keep (the restored base, or a
## corpse tint it must not touch).
func _go_idle() -> void:
	_duration = 0.0
	_elapsed = 0.0
	set_process(false)


func _is_dead() -> bool:
	# The hurtbox is the authority (it already routes the question to the entity); `_corpse` is
	# only this node's own record of what it drew, and an entity with no hurtbox still needs
	# the guard.
	if _hurtbox != null:
		return _hurtbox.is_dead()
	return _corpse


## Is a flash running right now? (for tests — the flash is the contract.)
func is_flashing() -> bool:
	return _duration > 0.0


## Is the entity wearing its corpse look? (for tests.)
func is_corpse() -> bool:
	return _corpse


## The tint currently on the entity (for tests, which cannot see a colour on screen).
func current_tint() -> Color:
	return _target.modulate if _target != null else Color.WHITE


## The resting colour a flash decays back to (for tests).
func resting_tint() -> Color:
	return _base
