class_name RaidAuthority
extends Node3D

signal notice(message: String)
signal container_opened(player_id: String, container_id: String)
signal finished(result: Dictionary)
signal health_changed(player_id: String, health: float)
signal shot_fired(player_id: String, position: Vector3)
enum Phase { DEPLOYING, ACTIVE, SUCCESS, FAILURE }
var phase: Phase = Phase.DEPLOYING
var raid_id: String = ""
var player: RaidPlayer
var guard: RaidGuard
var entities: Dictionary = {}
var participants: Dictionary[String, RaidParticipant] = {}
var ballistics := Ballistics.new()
var result: Dictionary = {}
@onready var extraction: ExtractionZone = $Extraction

func deploy(player_id: String, catalog: Catalog, settings: SettingsStore) -> String:
	player = $Player
	guard = $Guard
	player.entity_id = player_id
	player.authority = self
	player.settings = settings
	entities.clear()
	var raid_entities: Array = [player, guard, extraction]
	for node in get_tree().get_nodes_in_group("raid_entities"):
		if is_ancestor_of(node):
			raid_entities.append(node)
	for entity in raid_entities:
		if entity.entity_id.is_empty() or entities.has(entity.entity_id):
			return "Missing or duplicate entity ID: " + entity.entity_id
		entities[entity.entity_id] = entity
		if entity is RaidEntity or entity is RaidGuard:
			if entity.material == null or not catalog.definitions.has(entity.material.id):
				return "Entity has missing material definition"
		if entity is RaidEntity and entity.kind == "container":
			if entity.loot == null or not catalog.definitions.has(entity.loot.id):
				return "Container has missing loot definition"
	participants[player_id] = RaidParticipant.new(player, catalog)
	raid_id = ProfileStore._new_id()
	phase = Phase.ACTIVE
	$ImpactPresenter.catalog = catalog
	ballistics.impact.connect($ImpactPresenter.present)
	shot_fired.connect(guard.hear_shot)
	return ""

func is_active() -> bool:
	return phase == Phase.ACTIVE

func _allowed(player_id: String) -> bool:
	return is_active() and participants.has(player_id) and participants[player_id].health > 0.0

func request_fire(player_id: String) -> bool:
	if not _allowed(player_id):
		return false
	var state: RaidParticipant = participants[player_id]
	if not state.weapon.fire():
		return false
	shot_fired.emit(player_id, state.actor.global_position)
	var hit := ballistics.trace(get_world_3d(), state.actor.camera.global_position, -state.actor.camera.global_basis.z, state.weapon.definition.range_meters, [state.actor.get_rid()])
	if not hit.is_empty():
		var target: Node = hit.collider
		var material: MaterialDef = load("res://resources/materials/concrete.tres")
		var target_id := ""
		if target is RaidEntity or target is RaidGuard:
			material = target.material
			target_id = target.entity_id
		ballistics.impact.emit(hit.position, hit.normal, material.id, target_id)
		_apply_damage(target, state.weapon.definition.ammo.damage, material)
	return true

func request_reload(player_id: String) -> bool:
	if not _allowed(player_id) or not participants[player_id].weapon.reload():
		return false
	notice.emit("Reloading...")
	return true

func _apply_damage(target: Node, amount: float, material: MaterialDef) -> void:
	if not is_active():
		return
	if target is RaidGuard and target.state != RaidGuard.State.DEAD:
		target.health = maxf(0.0, target.health - ballistics.damage(amount, material, target.archetype.armor))
		notice.emit("Guard hit | %d HP" % ceili(target.health))
		if target.health == 0:
			target.die()
			notice.emit("Guard neutralized")
	elif target is RaidEntity and target.kind == "target" and target.health > 0:
		target.health = maxf(0.0, target.health - ballistics.damage(amount, material, null))
		notice.emit("Target hit | %d HP" % ceili(target.health))
		if target.health == 0:
			target.get_node("MeshInstance3D").visible = false
			target.collision_layer = 0

func _container_reachable(player_id: String, container_id: String) -> bool:
	if not _allowed(player_id) or not entities.has(container_id):
		return false
	var actor: RaidPlayer = participants[player_id].actor
	var container = entities[container_id]
	if not container is RaidEntity or container.kind != "container":
		return false
	if actor.global_position.distance_to(container.global_position) > 3.5:
		return false
	var direction: Vector3 = container.global_position + Vector3.UP * 0.5 - actor.camera.global_position
	var hit := ballistics.trace(get_world_3d(), actor.camera.global_position, direction, direction.length() + 0.1, [actor.get_rid()])
	return not hit.is_empty() and hit.collider == container

func request_interact(player_id: String, container_id: String) -> bool:
	if not _container_reachable(player_id, container_id) or participants[player_id].actor.interaction_id() != container_id:
		return false
	participants[player_id].opened_container = container_id
	container_opened.emit(player_id, container_id)
	return true

func request_claim(player_id: String, container_id: String, quantity: int) -> bool:
	if not _container_reachable(player_id, container_id) or participants[player_id].opened_container != container_id:
		return false
	var container: RaidEntity = entities[container_id]
	if quantity <= 0 or quantity > container.remaining or not participants[player_id].inventory.add(container.loot.item.id, quantity):
		notice.emit("Cannot take item: unavailable quantity or pack full")
		return false
	container.remaining -= quantity
	notice.emit("Salvage secured. Reach the green extraction zone.")
	return true

func objective_complete(player_id: String) -> bool:
	return participants.has(player_id) and participants[player_id].inventory.count("salvage") > 0

func request_abandon(player_id: String) -> bool:
	if not _allowed(player_id):
		return false
	_finish(false, "Raid abandoned | salvage lost")
	return true

func request_extract(player_id: String, zone_id: String = "extraction-01") -> bool:
	if not _allowed(player_id) or zone_id != extraction.entity_id:
		return false
	if not extraction.overlaps_body(participants[player_id].actor) or not objective_complete(player_id):
		return false
	participants[player_id].extracting = true
	return true

func _update_extraction(player_id: String, delta: float) -> void:
	var state: RaidParticipant = participants[player_id]
	if not request_extract(player_id, extraction.entity_id):
		state.extracting = false
		state.extraction_left = 3.0
		return
	state.extraction_left = maxf(0.0, state.extraction_left - delta)
	if state.extraction_left == 0:
		_finish(true, "Salvage extracted")

func _finish(success: bool, reason: String) -> void:
	if not is_active():
		return
	# shortcut: a solo outcome ends the raid, split participant outcomes when adding co-op.
	phase = Phase.SUCCESS if success else Phase.FAILURE
	for state in participants.values():
		state.weapon.cancel_reload()
	result = {"raid_id": raid_id, "success": success, "reason": reason}
	finished.emit(result)

func _physics_process(delta: float) -> void:
	if not is_active():
		return
	var target: RaidParticipant
	var nearest := INF
	for state in participants.values():
		state.weapon.tick(delta)
		var distance: float = guard.global_position.distance_to(state.actor.global_position)
		if state.health > 0 and distance < nearest:
			target = state
			nearest = distance
	if target != null and guard.authority_tick(delta, target.actor, ballistics):
		target.health = maxf(0.0, target.health - guard.archetype.damage)
		health_changed.emit(target.actor.entity_id, target.health)
		notice.emit("Taking fire! Find cover | %d HP" % ceili(target.health))
		if target.health == 0.0:
			_finish(false, "Killed in action | salvage lost")
	for player_id in participants:
		_update_extraction(player_id, delta)
