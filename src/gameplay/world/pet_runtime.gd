extends Node
class_name PetRuntime
## PetRuntime — Aetheria gameplay (the linh thú in a running session, Phase 16).
##
## Per-session node under `Main/Systems` (no autoload), started AFTER everything it reads and
## therefore ended first. It owns:
##   * the `PetStore` (persistent: owned pets, their XP, the active one) through `PetService`;
##   * the ONE runtime `Pet` body of the active pet while it is out — spawned beside the player,
##     armed through `CombatRuntime` (so it fights through the session's `CombatService`, registry
##     and single AI tick), and freed on dismissal, on a map change, on the player's death and on
##     session end.
##
## AUTHORITY. Ownership and XP are decided by `PetService`; a hit, a death and a kill's reward
## are decided by combat, exactly as for any fighter — this node never touches a health value,
## a damage number or the player's XP. It LISTENS to `CombatRuntime.enemy_defeated` and grants
## the pet its authored share of a kill it was out for, once per reward id.
##
## INPUT. The semantic `pet_summon` action (through `InputService`, gameplay context only)
## calls or dismisses the active pet. Befriending arrives as an interaction the map reports
## (`PetEncounter`), forwarded by `WorldRuntime`.
##
## FAIL CLOSED. Every refusal emits `pet_refused(reason_key)` with a key the HUD can say, and
## leaves no body, no registration and no changed state behind. A pet that could not be armed
## is freed, not left standing.
##
## PERSISTENCE. `to_dict()` / `from_dict()` are the plain-data boundary of `PetStore`
## (SAVE_FORMAT `pets`); Phase 23 will call them. No file is written here.

signal pet_acquired(pet_id: StringName)
signal pet_summoned(pet_id: StringName)
## `reason`: &"dismissed" (asked to), &"fell" (defeated), &"silent" (map change, teardown).
signal pet_dismissed(pet_id: StringName, reason: StringName)
signal pet_refused(reason_key: StringName)
signal pet_level_changed(pet_id: StringName, level: int)
## Anything a pet view shows changed (owned / out / level / recall).
signal view_changed()

const CATALOG_PATH := "res://data/pets/pet_catalog.tres"
const TECHNIQUE_CATALOG_PATH := "res://data/techniques/technique_catalog.tres"
const PetScene := preload("res://src/gameplay/entities/pet.tscn")

const SUMMON_ACTION := &"pet_summon"

const REASON_DISMISSED := &"dismissed"
const REASON_FELL := &"fell"
const REASON_SILENT := &"silent"

const REFUSE_NONE_OWNED := &"UI_PET_NONE"
const REFUSE_RECOVERING := &"UI_PET_RECOVERING"
const REFUSE_NO_ROOM := &"UI_PET_NO_ROOM"
const REFUSE_UNAVAILABLE := &"UI_PET_UNAVAILABLE"
const REFUSE_OWNER_DOWN := &"UI_PET_OWNER_DOWN"

## Where a called pet appears, relative to the player, tried in this order — behind and to the
## side first, so it never pops up in front of the player's feet. The first free one wins.
const SPAWN_OFFSETS: Array[Vector2] = [
	Vector2(-22, 10), Vector2(22, 10), Vector2(-26, -8), Vector2(26, -8),
	Vector2(0, 24), Vector2(0, -24), Vector2(-34, 0), Vector2(34, 0),
]

var _service: PetService = null
var _world: Node = null
var _combat: CombatRuntime = null
var _input: Node = null
var _session_active: bool = false

## The active pet's runtime body, or null while it is not out.
var _pet: Pet = null
## The player wants the active pet out: true between a summon and a dismissal, and KEPT across
## a map change so the companion is there again on arrival.
var _wants_out: bool = false
## Seconds until a pet that fell can be called again (runtime only).
var _recall_left: float = 0.0
## Reward ids the pet has already been paid for, so one kill cannot pay it twice.
var _paid: Dictionary = {}
## Monotonic per-session serial so each summoning has a unique combat id.
var _summon_serial: int = 0


func _ready() -> void:
	set_physics_process(false)


## Start the pet session. `world` is the WorldRuntime (player, active map, map signals) and
## `combat` the live CombatRuntime. Builds into locals and commits only when every step passed.
##
## `catalog` is the content seam: null loads the shipped `CATALOG_PATH`; a test (or a later
## content pack) passes its own, and nothing else in this node changes.
func start_session(world: Node, combat: CombatRuntime, catalog: PetCatalogData = null) -> bool:
	if _session_active:
		push_error("[pet-rt] start_session while a session is active")
		return false
	if world == null or combat == null or not combat.is_session_active():
		push_error("[pet-rt] pet session NOT started: a dependency is missing or inactive")
		return false
	if catalog == null:
		catalog = load(CATALOG_PATH) as PetCatalogData
	if catalog == null:
		push_error("[pet-rt] pet session NOT started: %s did not load" % CATALOG_PATH)
		return false
	var errors := catalog.validation_errors(_technique_ids())
	if not errors.is_empty():
		push_error("[pet-rt] pet session NOT started: the pet catalog is invalid: %s"
			% str(errors))
		return false
	var service := PetService.new(catalog, PetStore.new())
	if not service.is_ready():
		push_error("[pet-rt] pet session NOT started: the PetService refused its catalog")
		return false
	_service = service
	_world = world
	_combat = combat
	_input = get_node_or_null("/root/InputService")
	_pet = null
	_wants_out = false
	_recall_left = 0.0
	_paid = {}
	_summon_serial = 0
	_session_active = true
	_combat.enemy_defeated.connect(_on_enemy_defeated)
	if _world.has_signal("active_map_leaving"):
		_world.connect("active_map_leaving", _on_map_leaving)
	if _world.has_signal("active_map_ready"):
		_world.connect("active_map_ready", _on_map_ready)
	set_physics_process(true)
	_sync_encounters()
	return true


## End the session: free the body through the normal path, drop every connection. Idempotent.
func end_session() -> void:
	set_physics_process(false)
	if _pet != null:
		_despawn(REASON_SILENT)
	if _combat != null and is_instance_valid(_combat) \
			and _combat.enemy_defeated.is_connected(_on_enemy_defeated):
		_combat.enemy_defeated.disconnect(_on_enemy_defeated)
	if _world != null and is_instance_valid(_world):
		if _world.has_signal("active_map_leaving") \
				and _world.is_connected("active_map_leaving", _on_map_leaving):
			_world.disconnect("active_map_leaving", _on_map_leaving)
		if _world.has_signal("active_map_ready") \
				and _world.is_connected("active_map_ready", _on_map_ready):
			_world.disconnect("active_map_ready", _on_map_ready)
	_service = null
	_world = null
	_combat = null
	_input = null
	_wants_out = false
	_recall_left = 0.0
	_paid.clear()
	_session_active = false


func is_session_active() -> bool:
	return _session_active


func get_service() -> PetService:
	return _service


## The active pet's runtime body while it is out, else null.
func active_pet() -> Pet:
	return _pet if _pet != null and is_instance_valid(_pet) else null


func is_out() -> bool:
	return active_pet() != null


func recall_remaining() -> float:
	return _recall_left


# --- Player-facing intents ----------------------------------------------------

## The player befriended the stray `pet_id` (a `PetEncounter` the map reported). Ownership is
## decided by `PetService`; on success the new pet becomes the active one and comes out.
## Returns &"" on success, else the refusal key (also emitted).
func befriend(pet_id: StringName) -> StringName:
	if not _session_active:
		return _refuse(REFUSE_UNAVAILABLE)
	var reason := _service.acquire(pet_id)
	if reason != &"":
		return _refuse(reason)
	_service.activate(pet_id)
	pet_acquired.emit(pet_id)
	_sync_encounters()
	view_changed.emit()
	# It walks with the player from the moment it is befriended. A failure to appear here (no
	# room) is reported by `summon` and does not undo the ownership.
	summon()
	return &""


## Call or send away the active pet (the `pet_summon` key).
func toggle() -> StringName:
	if is_out():
		return dismiss()
	return summon()


## Bring the active pet out beside the player. &"" on success — also when it is ALREADY out
## (idempotent: a second call never makes a second body). Else the refusal key.
func summon() -> StringName:
	if not _session_active:
		return _refuse(REFUSE_UNAVAILABLE)
	if is_out():
		_wants_out = true
		return &""
	if _service.store().owned_count() == 0:
		return _refuse(REFUSE_NONE_OWNED)
	if _service.active_pet() == null:
		_service.activate(_service.store().owned_ids()[0])
	if _recall_left > 0.0:
		return _refuse(REFUSE_RECOVERING)
	var player := _player()
	if player == null:
		return _refuse(REFUSE_UNAVAILABLE)
	if player.has_method("is_dead") and bool(player.call("is_dead")):
		return _refuse(REFUSE_OWNER_DOWN)
	var reason := _spawn(_service.active_pet(), player)
	if reason != &"":
		return _refuse(reason)
	_wants_out = true
	pet_summoned.emit(_pet.data().id)
	view_changed.emit()
	return &""


## Send the active pet away. &"" always; safe (and silent) when it is not out.
func dismiss() -> StringName:
	_wants_out = false
	if not is_out():
		return &""
	_despawn(REASON_DISMISSED)
	view_changed.emit()
	return &""


# --- Spawn / despawn ----------------------------------------------------------

func _spawn(data: PetData, player: Node2D) -> StringName:
	var map: Node = _world.call("get_active_map")
	var host := map.get_node_or_null("PlayerHost") if map != null else null
	if data == null or host == null:
		push_error("[pet-rt] cannot summon: no pet definition or no PlayerHost in the map")
		return REFUSE_UNAVAILABLE
	var stats := _service.stats_of(data.id)
	var body := PetScene.instantiate() as Pet
	_summon_serial += 1
	var instance_id := StringName("%s#%d" % [data.id, _summon_serial])
	if body == null or not body.setup(data, instance_id, stats):
		if body != null:
			body.free()
		push_error("[pet-rt] cannot summon '%s': the pet body refused its setup" % data.id)
		return REFUSE_UNAVAILABLE
	body.name = "Pet"
	host.add_child(body)
	var spot: Variant = _free_spot(body, player.global_position)
	if spot == null:
		body.free()
		return REFUSE_NO_ROOM
	body.global_position = spot
	if not _combat.arm_attacker(body, data.attack, instance_id, CombatRuntime.TEAM_PLAYER) \
			or not _combat.arm_ally(body, data.ai_profile, data.engage_distance,
				stats.move_speed, player):
		_combat.disarm(body, instance_id)
		body.free()
		push_error("[pet-rt] cannot summon '%s': it could not be armed" % data.id)
		return REFUSE_UNAVAILABLE
	body.died.connect(_on_pet_died)
	_pet = body
	return &""


## The first of `SPAWN_OFFSETS` around `around` where the body does not overlap the world, or
## null. `test_move` with no motion is the body's own collision asked "would I be inside
## something here" — walls, water and solid props all answer, with no physics frame needed.
func _free_spot(body: Pet, around: Vector2) -> Variant:
	for offset in SPAWN_OFFSETS:
		var candidate := around + offset
		var at := Transform2D(0.0, candidate)
		if not body.test_move(at, Vector2.ZERO):
			return candidate
	return null


## Free the pet's body and everything that points at it. The ONE despawn path.
func _despawn(reason: StringName) -> void:
	var body := active_pet()
	_pet = null
	if body == null:
		return
	var pet_id := body.data().id
	if body.died.is_connected(_on_pet_died):
		body.died.disconnect(_on_pet_died)
	if _combat != null and is_instance_valid(_combat) and _combat.is_session_active():
		_combat.remove_ally(body.ai())
		_combat.disarm(body, body.instance_id())
	body.ai().stop()
	body.queue_free()
	pet_dismissed.emit(pet_id, reason)


func _on_pet_died() -> void:
	var body := active_pet()
	if body == null:
		return
	_recall_left = body.data().recall_seconds
	_wants_out = false
	_despawn(REASON_FELL)
	view_changed.emit()


# --- The world moving under it ------------------------------------------------

## The active map is about to be freed: the body goes with it, cleanly, and comes back on
## arrival if the player still wants it out.
func _on_map_leaving() -> void:
	if is_out():
		var keep := _wants_out
		_despawn(REASON_SILENT)
		_wants_out = keep


func _on_map_ready() -> void:
	_sync_encounters()
	if _wants_out and not is_out():
		var player := _player()
		var data := _service.active_pet()
		if player != null and data != null and _spawn(data, player) == &"":
			pet_summoned.emit(data.id)
		else:
			_wants_out = false
		view_changed.emit()


## Hide every stray the player already owns in the active map, so it is never offered twice.
func _sync_encounters() -> void:
	if not _session_active:
		return
	var map: Node = _world.call("get_active_map")
	var host := map.get_node_or_null("Interactables") if map != null else null
	if host == null:
		return
	for child in host.get_children():
		var encounter := child as PetEncounter
		if encounter != null and encounter.pet != null:
			encounter.visible = not _service.store().owns(encounter.pet.id)
	if map.has_method("refresh_interactables"):
		map.call("refresh_interactables")


# --- Growth -------------------------------------------------------------------

## A creature was defeated while the pet was out: it earns its authored share, once per kill.
## The player's XP is the progression owner's business and is untouched here.
func _on_enemy_defeated(reward_id: StringName, xp_reward: int) -> void:
	if not is_out() or _paid.has(reward_id):
		return
	_paid[reward_id] = true
	var data := _pet.data()
	var share := int(floor(float(xp_reward) * float(data.xp_share_percent) / 100.0))
	if share <= 0:
		return
	var result := _service.earn_xp(data.id, share)
	if not bool(result["accepted"]):
		return
	if int(result["level_after"]) > int(result["level_before"]):
		_pet.apply_stats(_service.stats_of(data.id))
		pet_level_changed.emit(data.id, int(result["level_after"]))
	view_changed.emit()


# --- Tick ---------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	tick(delta)


## One step: the recall countdown, and the summon key. Public and delta-driven for tests.
func tick(delta: float) -> void:
	if not _session_active:
		return
	if _recall_left > 0.0:
		_recall_left = maxf(0.0, _recall_left - delta)
		if _recall_left == 0.0:
			view_changed.emit()
	if is_out():
		var player := _player()
		if player != null and player.has_method("is_dead") and bool(player.call("is_dead")):
			# The owner fell: the companion withdraws rather than fighting on alone.
			_wants_out = false
			_despawn(REASON_SILENT)
			view_changed.emit()
	if _input != null and bool(_input.call("is_gameplay_action_just_pressed", SUMMON_ACTION)):
		toggle()


# --- View ---------------------------------------------------------------------

## The read-only snapshot the HUD shows. Built on demand; pushed on `view_changed`, never
## per frame.
func build_view() -> PetView:
	var view := PetView.make_empty()
	var data := _service.active_pet() if _service != null else null
	if data == null:
		return view
	view.available = true
	view.name_key = StringName(data.name_key)
	view.level = _service.level_of(data.id)
	view.out = is_out()
	view.recovering = _recall_left > 0.0
	return view


# --- Persistence boundary -------------------------------------------------------

func to_dict() -> Dictionary:
	return _service.store().to_dict() if _service != null else {}


## Restore the store from `to_dict()` output. Atomic: a rejected payload changes nothing. A pet
## that was out is sent away first (its body belongs to the state being replaced) and is not
## re-summoned — being out is runtime, not saved.
func from_dict(data: Dictionary) -> bool:
	if not _session_active:
		return false
	var probe := PetStore.new()
	if not probe.from_dict(data, _service.catalog()):
		return false
	if is_out():
		_despawn(REASON_SILENT)
	_wants_out = false
	_service.store().from_dict(data, _service.catalog())
	_sync_encounters()
	view_changed.emit()
	return true


# --- Helpers ------------------------------------------------------------------

func _refuse(reason: StringName) -> StringName:
	pet_refused.emit(reason)
	return reason


func _player() -> Node2D:
	if _world == null or not is_instance_valid(_world):
		return null
	return _world.call("get_player") as Node2D


## Known technique ids, to validate `PetData.skills` against (empty when the catalog is absent,
## in which case only the shape is validated).
func _technique_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	if not ResourceLoader.exists(TECHNIQUE_CATALOG_PATH):
		return out
	var catalog := load(TECHNIQUE_CATALOG_PATH) as TechniqueCatalogData
	if catalog == null:
		return out
	for technique in catalog.entries:
		if technique != null:
			out.append(technique.id)
	return out
