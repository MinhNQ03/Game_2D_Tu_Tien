extends Node
class_name CombatRuntime
## CombatRuntime — Aetheria gameplay (the per-session combat seam, Phase 09, D-007).
##
## Owns the two things a fight needs and nothing else: the `CombatService` (bound to the
## session's seeded COMBAT stream) and the `CombatHurtboxRegistry` (who can be hit). Entities
## that fight are armed from here; it resolves no hit and holds no health itself.
##
## A NODE UNDER `Main/Systems`, NOT AN AUTOLOAD (D-017). The autoload budget is frozen at
## five, and combat is strictly per-session: a global combat seam would survive a return to
## the menu carrying the previous run's hurtbox registry and RNG position, which is precisely
## the class of bug the per-session runtimes exist to prevent. It is the sixth sibling of
## `WorldRuntime` / `RelationshipRuntime` / `SectRuntime` / `FactionRuntime` /
## `WorldSimulationRuntime` and is registered LAST in `Main.SESSION_START_ORDER`, so teardown
## (the exact reverse) ends combat FIRST — before the RNG seam it borrows and the entities it
## points at are gone.
##
## IT SHARES THE WORLD'S `RngService` RATHER THAN MAKING ONE. One world seed, two independent
## streams: `derive_state()` makes `world_sim` and `combat` start far apart, so a combat roll
## can never shift the simulation's sequence. A second `RngService` with its own seed would
## mean a save had two world identities, and "which seed is this world" would stop having one
## answer (`SAVE_FORMAT.md` §3b).
##
## FAIL CLOSED, LIKE EVERY OTHER SESSION STARTER (L-025). `start_session()` builds into LOCALS
## and commits only when every step succeeded, so a rejected start leaves nothing observable:
## `is_session_active()` stays false and every getter stays empty. There is no "warn and keep
## going" path — a half-built combat session would be a world where some entities can be hit
## and others silently cannot.

## What the player is fighting changed (Phase 10). Carries a read-only `CombatTargetView`;
## `WorldRuntime` forwards it to the active map's HUD, so combat knows nothing about UI
## (`03-architecture.md`: emitters never depend on listeners).
signal combat_target_changed(view: CombatTargetView)

## A creature was defeated, and this is what defeating it is worth (Phase 11).
##
## COMBAT ANNOUNCES; IT DOES NOT PAY. This carries the authored `xp_reward` and an identity,
## and nothing else: combat holds no progression state, does not know a level exists, and has
## no reference to the player's `CharacterState`. `ProgressionRuntime` listens and is the only
## thing that mutates XP. Making combat call a progression API instead would point the
## dependency the wrong way and would put permanent character state behind a per-session
## system, both of which `03-architecture.md` forbids.
##
## `reward_id` is unique PER SPAWN (see `_next_reward_id`), so the progression owner can make
## the grant idempotent without that making a re-cleared map unrewardable.
##
## The payload is deliberately free of localized strings, UI data and animation parameters —
## it is a gameplay fact, and presentation reacts to the progression owner's events, not to
## this one.
signal enemy_defeated(reward_id: StringName, xp_reward: int)

## The enemy scene. Every creature is this ONE scene configured by `EnemyData` — there is no
## per-creature scene, which is what makes a new creature a `.tres` (Phase 10 exit criterion).
const EnemyScene := preload("res://src/gameplay/entities/enemy.tscn")

## The two sides of a fight (Phase 16). An attack never lands on the attacker's own side
## (`HurtboxComponent.team`). The player and every companion are `TEAM_PLAYER`; spawned
## creatures are `TEAM_HOSTILE` (so a pack no longer bites itself); a training post has no side
## and is hit by anyone. Two names, not a faction system: who is hostile to whom is a P17+
## question the relationship graph will answer, and this is the smallest fact combat needs now.
const TEAM_PLAYER := &"team_player"
const TEAM_HOSTILE := &"team_hostile"

## How often the allies' targets are re-chosen, in seconds. A CADENCE, not a per-frame scan:
## choosing costs O(allies x enemies), and a committed choice is also what makes a companion
## readable — it does not flicker between two wolves at similar distances.
const ALLY_RETARGET_SECONDS := 0.25

var _service: CombatService = null
var _registry: CombatHurtboxRegistry = null
var _session_active: bool = false

## Allied actors the session ticks beside the enemies (Phase 16): each a companion's
## `AIComponent`, in the order they were added (deterministic). The session does not OWN them —
## `PetRuntime` spawns and frees its pet — it only gives them the same single tick the enemies
## get and tells them what to fight.
var _allies: Array[AIComponent] = []
var _since_retarget: float = 0.0
## Retarget passes run this session — a read-only counter so a budget test can assert the
## cadence instead of trusting it.
var _retargets: int = 0

## The session's RngService, kept so enemy brains can draw from the AI stream. Combat holds
## the seam rather than a second seed: one world identity, independent streams (D-051 §10).
var _rng: RngService = null

## Entities armed this session, by id, so teardown can cancel a swing in flight rather than
## leave a hit window pending on a node that is about to be freed.
var _armed: Dictionary = {}

## Live enemies, in SPAWN ORDER. An Array, not a Dictionary, because the tick order must be
## deterministic: two enemies deciding in a different order could resolve their swings in a
## different order, and a seeded run would stop being reproducible.
var _enemies: Array[Enemy] = []

## What the enemies are hunting. Set once per map by the world, so no enemy searches the tree
## for a player — that would be an O(tree) walk per enemy per tick, and a dependency pointing
## the wrong way.
var _hunt_target: Node2D = null

## Monotonic spawn counter, used to make a defeat's `reward_id` unique per SPAWN rather than
## per spawn-table row (Phase 11).
##
## A table row's `instance_id` repeats every time the map is populated, so using it alone as
## the reward identity would mean clearing the field, leaving and coming back granted nothing
## the second time — the dedupe key would have silently become a "this row has ever been
## killed" flag. Composing it with this counter keeps the key unique per spawn while staying
## DETERMINISTIC (the counter advances in table order, which is the same order every run), so
## a seeded session remains reproducible.
var _spawn_serial: int = 0

## Per-spawn reward id, by instance id. Assigned at spawn so the death handler never has to
## derive it from a node that is already being torn down.
var _reward_ids: Dictionary = {}

## Reward ids already announced this session, so one death cannot be announced twice.
##
## This guard exists IN ADDITION to the progression owner's own ledger, and the two are not
## redundant — they stop different things. This one stops a DOUBLE EMISSION for a single
## creature (a `died` that somehow fires twice, a signal connected twice at the source).
## The owner's stops a double GRANT however the event reached it, which is the authority's job
## and the one §9 cares about. Cleared on despawn, so it is bounded by the living population
## rather than by the session's total kills.
var _announced: Dictionary = {}


## Start the combat session from the world's RNG seam.
##
## `rng` is the session's `RngService` — the SAME instance the world simulation uses, taken
## from `WorldSimulationState.rng()`. Returns true only when combat is actually live.
func start_session(rng: RngService) -> bool:
	if _session_active:
		push_error("[combat-rt] start_session called while a session is already active")
		return false
	if rng == null:
		return _fail_start("no RngService was supplied")
	if not rng.is_valid():
		return _fail_start("the supplied RngService has no valid world seed")
	var stream := rng.stream(RngService.STREAM_COMBAT)
	if stream == null:
		return _fail_start("the RngService refused to produce the '%s' stream"
			% RngService.STREAM_COMBAT)
	var service := CombatService.new(stream)
	if not service.is_ready():
		return _fail_start("the CombatService refused the combat stream")

	# Commit: every step succeeded, so the session becomes observable all at once.
	_service = service
	_registry = CombatHurtboxRegistry.new()
	_rng = rng
	_armed = {}
	_enemies = []
	_allies = []
	_since_retarget = 0.0
	_retargets = 0
	_hunt_target = null
	_spawn_serial = 0
	_reward_ids = {}
	_announced = {}
	_session_active = true
	return true


## Report a refused start and leave the runtime EXACTLY as it was.
##
## No partial state to unwind, by construction: nothing above assigns to a field until every
## check has passed, so this only has to report. That is the difference between failing closed
## and cleaning up after failing (L-025).
func _fail_start(reason: String) -> bool:
	push_error("[combat-rt] combat session NOT started: %s" % reason)
	return false


## End the session: cancel every swing in flight, drop the registry, drop the service.
##
## Cancelling FIRST is the point. A pending hit window on an entity that is about to be freed
## would resolve against a registry mid-teardown — a phantom hit on a half-dismantled world,
## which is the hardest kind of bug to reproduce because it needs a specific frame.
## Idempotent: ending a session that never started is a no-op, which is what makes the shared
## teardown path safe to run after an aborted boot.
func end_session() -> void:
	# Enemies first: stopping an AI drops its target and cancels its swing, so no brain can
	# decide against a registry that is about to disappear.
	despawn_enemies()
	for ally in _allies:
		if ally != null and is_instance_valid(ally):
			ally.stop()
	_allies.clear()
	for key in _armed.keys():
		var component: AttackComponent = _armed[key]
		if component != null and is_instance_valid(component):
			component.cancel()
	_armed.clear()
	if _registry != null:
		_registry.clear()
	_registry = null
	_service = null
	_rng = null
	_hunt_target = null
	_spawn_serial = 0
	_reward_ids.clear()
	_announced.clear()
	_session_active = false
	set_physics_process(false)


func is_session_active() -> bool:
	return _session_active


## The session's combat service, or null outside a session.
func get_service() -> CombatService:
	return _service


## The session's hurtbox registry, or null outside a session.
func get_registry() -> CombatHurtboxRegistry:
	return _registry


## Make `entity` targetable: bind its hurtbox to this session's registry.
##
## Returns false (loud) outside a session or without a hurtbox — an entity that silently is
## not targetable is a target the player can hit forever with no effect.
func register_target(entity: Node, team: StringName = &"") -> bool:
	if not _session_active:
		push_error("[combat-rt] register_target outside a session")
		return false
	var hurtbox := _find_child_of_type(entity, "HurtboxComponent") as HurtboxComponent
	if hurtbox == null:
		push_error("[combat-rt] '%s' has no HurtboxComponent, so it cannot be hit"
			% (entity.name if entity != null else "<null>"))
		return false
	if team != &"":
		hurtbox.team = team
	hurtbox.setup(entity, _registry)
	return true


## Arm `entity` to attack with `attack`, and make it targetable in the same call.
##
## One call for both sides on purpose: an attacker that is not itself a target is a one-way
## fight, and forgetting the second call is invisible until something tries to hit back.
## `attacker_id` is also what keeps the entity out of its own swing.
##
## `team` (Phase 16) puts the entity on a side: its swings skip that side and that side's
## swings skip it. Empty keeps whatever side its hurtbox already has (none, by default).
func arm_attacker(entity: Node, attack: AttackData, attacker_id: StringName,
		team: StringName = &"") -> bool:
	if not _session_active:
		push_error("[combat-rt] arm_attacker outside a session")
		return false
	var component := _find_child_of_type(entity, "AttackComponent") as AttackComponent
	if component == null:
		push_error("[combat-rt] '%s' has no AttackComponent, so it cannot attack"
			% (entity.name if entity != null else "<null>"))
		return false
	if not register_target(entity, team):
		return false
	if not component.arm(attack, _service, _registry, attacker_id, team):
		return false
	_armed[String(attacker_id)] = component
	return true


## Stop treating `attacker_id` as armed and drop its hurtbox (a dismissed companion). Cancels a
## swing in flight first, so no hit window is left pending on a body about to be freed. Safe for
## an id that was never armed.
func disarm(entity: Node, attacker_id: StringName) -> void:
	var component: AttackComponent = _armed.get(String(attacker_id))
	if component != null and is_instance_valid(component):
		component.cancel()
	_armed.erase(String(attacker_id))
	if _registry != null and entity != null and is_instance_valid(entity):
		var hurtbox := _find_child_of_type(entity, "HurtboxComponent") as HurtboxComponent
		if hurtbox != null:
			_registry.unregister(hurtbox)


## How many attackers this session has armed. A read-only window for tests and the debug
## overlay, like `Main.get_last_teardown_order()`.
func armed_count() -> int:
	return _armed.size()


# --- Enemies (Phase 10) -----------------------------------------------------
#
# Spawning, ticking and despawning live HERE rather than in a seventh `Main/Systems` node, and
# that is a deliberate call: "the combat session owns the fighters" is one cohesive
# responsibility — the service that resolves their hits, the registry that makes them
# targetable, and the creatures themselves have the same lifetime and the same teardown order.
# A separate `EnemyRuntime` would need the registry, the service and the RNG seam this node
# already holds, so it would be a node whose only content is a pointer to this one, plus
# another entry in `SESSION_START_ORDER` to keep in sync.

## Who the enemies hunt. Set by the world when it realizes the player.
func set_hunt_target(target: Node2D) -> void:
	_hunt_target = target
	for enemy in _enemies:
		if enemy != null and is_instance_valid(enemy):
			enemy.ai().set_target(target)


## Populate `host` from a spawn table. Returns the number spawned.
##
## Order is the TABLE's order, so the same table always produces the same entities with the
## same ids — which is what makes a populated map reproducible from a seed and lets a future
## authoritative server assign identical identities.
##
## A row that fails to spawn is reported and SKIPPED rather than aborting the map: one bad
## content row must not leave a playable map empty.
func spawn_from_table(table: EnemySpawnTableData, host: Node) -> int:
	if not _session_active:
		push_error("[combat-rt] spawn_from_table outside a session")
		return 0
	if table == null or not table.is_valid():
		push_error("[combat-rt] refusing to spawn from an invalid spawn table")
		return 0
	if host == null or not is_instance_valid(host):
		push_error("[combat-rt] spawn_from_table needs a host node to parent enemies under")
		return 0
	var spawned := 0
	for i in table.size():
		if _spawn_one(table.enemies[i], table.positions[i], table.instance_id_for(i), host):
			spawned += 1
	# The tick only runs while there is something to tick, so an empty map costs nothing.
	_refresh_tick()
	return spawned


func _spawn_one(
		data: EnemyData, position: Vector2, instance_id: StringName, host: Node) -> bool:
	var enemy := EnemyScene.instantiate() as Enemy
	if enemy == null:
		push_error("[combat-rt] the enemy scene did not instantiate as an Enemy")
		return false
	# Configure BEFORE entering the tree, so `_ready` sees final data — the same ordering the
	# player uses for `bind_character_state` (D-026).
	if not enemy.setup(data, instance_id):
		enemy.free()
		return false
	enemy.name = String(instance_id)
	enemy.position = position
	host.add_child(enemy)
	if not register_target(enemy, TEAM_HOSTILE):
		enemy.queue_free()
		return false
	var component := _find_child_of_type(enemy, "AttackComponent") as AttackComponent
	if component == null or not component.arm(data.attack, _service, _registry, instance_id,
			TEAM_HOSTILE):
		push_error("[combat-rt] '%s' could not be armed to attack" % instance_id)
		enemy.queue_free()
		return false
	# The AI draws from its OWN stream, not the combat one: a creature's patrol choices must
	# not shift the crit sequence, and vice versa (`derive_state` starts them far apart).
	var ai_stream := _rng.stream(STREAM_ENEMY_AI)
	if ai_stream == null or not enemy.ai().arm(data, ai_stream, position):
		push_error("[combat-rt] '%s' could not arm its AI" % instance_id)
		enemy.queue_free()
		return false
	enemy.ai().set_target(_hunt_target)
	# The reward identity is fixed at SPAWN time, not read at death: a dead creature must be
	# announceable even though its node is mid-teardown, and the id must not depend on
	# anything the death handler has to go and look up.
	_spawn_serial += 1
	_reward_ids[String(instance_id)] = _compose_reward_id(instance_id, _spawn_serial)
	enemy.died.connect(_on_enemy_died.bind(enemy))
	# The target plaque is pushed on the EVENTS the player cares about — a hit landing and a
	# death — rather than polled. "Whatever I just hit" is also the honest answer to "what am I
	# fighting": a nearest-living-enemy search would need a per-frame scan and would flicker
	# between two creatures standing at similar distances.
	enemy.health_changed.connect(_on_enemy_health_changed.bind(enemy))
	# ...and when it starts HUNTING, not only when it is hit. Publishing on damage alone meant
	# the player could watch a creature notice them and close in with nothing on screen saying
	# what it was — the panel appeared only after the first exchange, i.e. exactly after the
	# moment the information was useful. Found by looking at a playtest capture of a creature
	# mid-ALERT with an empty target plaque.
	enemy.ai().ai_state_changed.connect(_on_enemy_ai_state_changed.bind(enemy))
	_armed[String(instance_id)] = component
	_enemies.append(enemy)
	return true


## The enemy-AI stream id. Named here, in the file that draws from it, with a real consumer —
## the pattern `RngService` documents for every stream after the first (L-005).
##
## A stream per SUBSYSTEM, not per creature: all enemies share it, so one creature's patrol
## draws advance the next one's sequence. That is still deterministic because the tick order
## is deterministic (`_enemies` is kept in spawn order, and the spawn order is the table's
## order), and it keeps the save's stream list bounded by subsystems rather than by population.
## The cost is that inserting a spawn row shifts later creatures' patrol choices — acceptable
## for wandering, and the day something needs per-creature isolation (a scripted boss pattern)
## it can derive its own stream id from its instance id without changing this.
const STREAM_ENEMY_AI := &"enemy_ai"


## Free every spawned enemy. Called on map change and on session end.
##
## It STOPS each AI before freeing: a brain that decides during teardown would perceive a
## half-dismantled world, and a swing in flight would resolve against a registry that is
## already being cleared.
func despawn_enemies() -> void:
	for enemy in _enemies:
		if enemy == null or not is_instance_valid(enemy):
			continue
		enemy.ai().stop()
		if _registry != null:
			var hurtbox := _find_child_of_type(enemy, "HurtboxComponent") as HurtboxComponent
			if hurtbox != null:
				_registry.unregister(hurtbox)
		_armed.erase(String(enemy.instance_id()))
		enemy.queue_free()
	_enemies.clear()
	# Both reward ledgers are per-POPULATION, not per-session: the next `spawn_from_table`
	# mints fresh ids from the advancing serial, so a re-cleared map rewards again while a
	# single death still cannot pay twice.
	_reward_ids.clear()
	_announced.clear()
	# No enemy is left to fight: every ally drops its target NOW rather than at the next
	# retarget, so nothing can swing at a body that was just queued for deletion.
	for ally in _allies:
		if ally != null and is_instance_valid(ally):
			ally.set_target(null)
	_refresh_tick()


## Live enemy count (including corpses that have not been cleaned up yet).
func enemy_count() -> int:
	return _enemies.size()


## Enemies that are still a threat — alive and acting. The number an encounter is "over" at.
func living_enemy_count() -> int:
	var alive := 0
	for enemy in _enemies:
		if enemy != null and is_instance_valid(enemy) and not enemy.is_dead():
			alive += 1
	return alive


## The spawned enemies, in spawn order (a copy, so a caller cannot edit the session's list).
func enemies() -> Array[Enemy]:
	return _enemies.duplicate()


## A creature's health changed — publish it as the current combat target.
func _on_enemy_health_changed(_current: int, _maximum: int, enemy: Enemy) -> void:
	_publish_target(enemy)


## A creature entered an ENGAGED state — publish it, so the player learns what is coming for
## them before the first blow rather than after it.
##
## Only the engaged states: an idle creature wandering past should not take over the panel, or
## walking through a populated map would flicker the plaque between whatever happens to be
## nearby.
func _on_enemy_ai_state_changed(state_name: String, enemy: Enemy) -> void:
	if state_name in ["ALERT", "CHASE", "ATTACK", "RECOVER"]:
		_publish_target(enemy)


## Compose a per-spawn reward identity. `enemy_mist_wolf_1#3` reads as "the third creature
## spawned this session, which was spawn-table row `enemy_mist_wolf_1`".
##
## Deterministic by construction: the serial advances in spawn-table order, so the same table
## produces the same ids in the same run order every time — which is what lets a seeded
## session stay reproducible and lets a future authoritative server mint matching identities.
static func _compose_reward_id(instance_id: StringName, serial: int) -> StringName:
	return StringName("%s#%d" % [String(instance_id), serial])


## Announce what defeating `enemy` is worth, exactly once per spawn.
##
## Reads the reward from the creature's own authored data, so a new creature's worth is a
## `.tres` value and this function never grows a branch per creature.
func _announce_defeat(enemy: Enemy) -> void:
	var key := String(enemy.instance_id())
	if not _reward_ids.has(key):
		# No id was minted for this creature, which means it was never spawned through
		# `_spawn_one`. Loud: a creature that can die without being announceable is a silent
		# hole in the reward path, and silence is exactly how a reward loop goes missing.
		push_error(("[combat-rt] '%s' died with no reward id; it was not spawned through "
			+ "spawn_from_table, so its defeat cannot be announced") % key)
		return
	var reward_id: StringName = _reward_ids[key]
	if _announced.has(String(reward_id)):
		return
	_announced[String(reward_id)] = true
	var data := enemy.data()
	var reward := 0
	if data != null:
		reward = data.xp_reward
	enemy_defeated.emit(reward_id, reward)


## The reward id minted for a spawned creature, or an empty name. For tests and the debug
## overlay — the same read-only-window shape as `armed_count()`.
##
## Written as an explicit branch rather than a ternary: a `Dictionary` lookup is a `Variant`,
## so `dict[k] if ... else &""` mixes Variant with StringName and GDScript reports an
## incompatible ternary.
func reward_id_of(instance_id: StringName) -> StringName:
	var key := String(instance_id)
	if not _reward_ids.has(key):
		return &""
	return _reward_ids[key]


## Emit a read-only view of `enemy` for the HUD.
##
## A VIEW, not the node: the panel must not hold a reference to an entity that may be freed a
## frame later (`SectMembershipView` has the same contract). Combat builds the DTO and emits;
## it does not know a HUD exists — `WorldRuntime` forwards it, exactly as it forwards the sect
## and politics views.
func _publish_target(enemy: Enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	combat_target_changed.emit(CombatTargetView.make(
		enemy.data(), enemy.get_current_health(), enemy.get_max_health(), enemy.is_dead()))


## ONE physics callback drives EVERY enemy's AI.
##
## This is the whole reason the components have no `_physics_process` of their own: N enemies
## cost one callback instead of N, so "AI costs X ms for N enemies" is a number a budget test
## can assert. Each component then throttles its own DECISIONS to its profile's interval while
## executing movement every tick — the separation Phase 10 requires (C6).
func _physics_process(delta: float) -> void:
	tick_enemies(delta)
	tick_allies(delta)


## Advance every enemy's AI by `delta`.
##
## Public and delta-driven so a test can step AI with EXACT deltas: the headless runner does
## not run physics callbacks the way a game does (L-016), and AI timing is exactly what needs
## testing. Iterates the spawn-ordered array, so decisions happen in a deterministic order.
func tick_enemies(delta: float) -> void:
	for enemy in _enemies:
		if enemy == null or not is_instance_valid(enemy) or enemy.is_dead():
			continue
		enemy.ai().tick(delta)


## A creature died: it stops acting and stops being targetable, but its NODE stays.
##
## Unregistering is what stops the player swinging at a corpse forever; keeping the node is
## what lets the body remain visible as a corpse. Freeing here would tear down the emitter
## mid-signal (L-013), and the session owns the lifetime anyway.
func _on_enemy_died(enemy: Enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if _registry != null:
		var hurtbox := _find_child_of_type(enemy, "HurtboxComponent") as HurtboxComponent
		if hurtbox != null:
			_registry.unregister(hurtbox)
	_armed.erase(String(enemy.instance_id()))
	_publish_target(enemy)
	_announce_defeat(enemy)
	# Whoever was fighting it stops NOW, not at the next retarget pass.
	for ally in _allies:
		if ally != null and is_instance_valid(ally) and ally.target() == enemy:
			ally.set_target(null)
	# Nothing left alive means nothing left to think: stop the tick entirely rather than
	# iterating corpses every frame for the rest of the session.
	_refresh_tick()


# --- Allies (Phase 16) -------------------------------------------------------
#
# A companion fights through the SAME seams an enemy does — its own `AttackComponent`, this
# session's `CombatService` and registry — so nothing about damage, death or reward is new. What
# the session adds is the two things it already does for enemies: ONE tick for all of them, and
# the answer to "what should you be fighting", which only the session can give because only it
# knows who is hostile and alive.

## The ally-AI stream id: every companion's brain draws from it, never from the enemies' or
## the combat stream, so a pet being out cannot shift a crit or a wolf's patrol (L-005: named
## here, with its consumer).
const STREAM_ALLY_AI := &"ally_ai"


## Arm `entity`'s `AIComponent` as an ALLY of `owner` and start ticking it: the brain gets the
## session's ally stream, its home is the owner (a home that moves), and the session chooses its
## targets. The entity must already be armed to attack (`arm_attacker` with its team). Returns
## false (loud) when any part is missing — the caller frees the body rather than leaving an
## inert companion standing in the world.
func arm_ally(entity: Node, profile: AiProfileData, engage_distance: float, move_speed: float,
		owner_body: Node2D) -> bool:
	if not _session_active:
		push_error("[combat-rt] arm_ally outside a session")
		return false
	var ai := _find_child_of_type(entity, "AIComponent") as AIComponent
	var body := entity as Node2D
	if ai == null or body == null:
		push_error("[combat-rt] '%s' has no AIComponent, so it cannot follow or assist"
			% (entity.name if entity != null else "<null>"))
		return false
	if owner_body == null or not is_instance_valid(owner_body):
		push_error("[combat-rt] arm_ally needs a live owner to follow")
		return false
	var stream := _rng.stream(STREAM_ALLY_AI)
	if stream == null or not ai.arm_profile(profile, engage_distance, move_speed, stream,
			owner_body.global_position, String(entity.name)):
		return false
	ai.set_home_anchor(owner_body)
	return add_ally(ai)


## Tick `ally` with the session and choose its targets. Returns false (loud) outside a session
## or for an unarmed component. Idempotent: adding the same ally twice keeps one entry.
func add_ally(ally: AIComponent) -> bool:
	if not _session_active:
		push_error("[combat-rt] add_ally outside a session")
		return false
	if ally == null or not is_instance_valid(ally) or not ally.is_armed():
		push_error("[combat-rt] refusing to add an ally whose AIComponent is not armed")
		return false
	if not _allies.has(ally):
		_allies.append(ally)
	_refresh_tick()
	return true


## Stop ticking `ally`. Safe for one that was never added.
func remove_ally(ally: AIComponent) -> void:
	_allies.erase(ally)
	_refresh_tick()


func ally_count() -> int:
	return _allies.size()


func retarget_passes() -> int:
	return _retargets


## Advance every ally by `delta`: re-choose targets on the cadence, then tick each. Public and
## delta-driven for the same reason `tick_enemies` is (L-016).
func tick_allies(delta: float) -> void:
	if _allies.is_empty():
		return
	_since_retarget += delta
	if _since_retarget >= ALLY_RETARGET_SECONDS:
		_since_retarget = fmod(_since_retarget, ALLY_RETARGET_SECONDS)
		_retarget_allies()
	for ally in _allies:
		if ally != null and is_instance_valid(ally):
			ally.tick(delta)


## Give every ally the hostile it should fight, or none.
##
## THE RULE: the nearest LIVING spawned enemy to the ally, among those within the ally's
## `detect_radius` of its HOME (its owner). Measured from the owner, so a companion defends the
## ground its owner stands on and never wanders off to a fight across the map; nearest to the
## ally, so it commits to what is in front of it. An ally keeps a target that is still valid
## (alive, still inside that radius) instead of re-choosing every pass — hysteresis, so two
## wolves at similar distances do not make it dither.
##
## Candidates are ONLY this session's spawned enemies: never the player, never another ally,
## never a neutral post, never a corpse or a freed node. Ties go to the earlier spawn (strict
## `<` over the spawn-ordered array), so the choice is deterministic and needs no RNG.
func _retarget_allies() -> void:
	_retargets += 1
	for ally in _allies:
		if ally == null or not is_instance_valid(ally):
			continue
		var body := ally.get_parent() as Node2D
		var profile := ally.profile()
		if body == null or profile == null:
			continue
		ally.set_target(_choose_hostile(ally.target(), body.global_position, ally.home(),
			profile.detect_radius))


func _choose_hostile(current: Node2D, from: Vector2, home: Vector2, radius: float) -> Node2D:
	if _is_live_hostile(current) and current.global_position.distance_to(home) <= radius:
		return current
	var best: Enemy = null
	var best_distance := INF
	for enemy in _enemies:
		if not _is_live_hostile(enemy):
			continue
		if enemy.global_position.distance_to(home) > radius:
			continue
		var distance := enemy.global_position.distance_to(from)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _is_live_hostile(node: Node2D) -> bool:
	if node == null or not is_instance_valid(node):
		return false
	var enemy := node as Enemy
	return enemy != null and _enemies.has(enemy) and not enemy.is_dead()


## The tick runs only while something needs it: a living enemy, or any ally (a companion
## follows its owner whether or not there is a fight).
func _refresh_tick() -> void:
	set_physics_process(_session_active
		and (living_enemy_count() > 0 or not _allies.is_empty()))


## First direct child of `entity` whose class matches `type_name`.
##
## Direct children only, and matched by class rather than by node NAME: a scene is free to
## name its components whatever reads best, and matching on a name would make the wiring
## depend on a cosmetic choice (`04-coding-standards.md`: prefer composition over fixed paths).
func _find_child_of_type(entity: Node, type_name: String) -> Node:
	if entity == null or not is_instance_valid(entity):
		return null
	for child in entity.get_children():
		var script: Script = child.get_script()
		if script != null and script.get_global_name() == type_name:
			return child
	return null
