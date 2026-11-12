class_name RaidAuthority
extends Node3D

const VoxelDestructibleScript = preload("res://scripts/world/voxel_destructible.gd")

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
var projectiles: Array[Dictionary] = []
var projectile_serial: int = 0
var catalog: Catalog
@onready var extraction: ExtractionZone = $Extraction

func deploy(player_id: String, catalog: Catalog, settings: SettingsStore, loadout: Dictionary = {}) -> String:
	self.catalog = catalog
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
	var pack: RaidInventory = loadout.get("pack", RaidInventory.new(catalog.items, 10, 6))
	var weapon_id: String = loadout.get("weapon", "rifle")
	var armor_id: String = loadout.get("armor", "patrol")
	var attachments: Array = loadout.get("attachments", WeaponState.LOADOUTS.get(settings.starter_loadout, []))
	if not catalog.definitions.get(weapon_id) is WeaponDef or not catalog.definitions.get(armor_id) is ArmorDef:
		return "Loadout is missing a valid weapon or armor"
	if pack.count(catalog.definitions[weapon_id].ammo.id) == 0 and loadout.is_empty():
		pack.add(catalog.definitions[weapon_id].ammo.id, 60)
	participants[player_id] = RaidParticipant.new(player, catalog, pack, weapon_id, armor_id, attachments)
	raid_id = ProfileStore._new_id()
	phase = Phase.ACTIVE
	$ImpactPresenter.catalog = catalog
	ballistics.impact.connect($ImpactPresenter.present)
	shot_fired.connect(guard.hear_shot)
	shot_fired.connect(player.shot_fired)
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
	_spawn_projectile(state.actor.camera.global_position, -state.actor.camera.global_basis.z,
		state.weapon.definition.ammo, state.weapon.muzzle_velocity,
		state.weapon.hipfire_spread * (1.0 - state.actor.aim_blend) + state.weapon.sway * state.actor.aim_blend,
		state.weapon.definition.range_meters, state.actor.get_rid(), state.weapon.damage_multiplier)
	return true

func _spawn_projectile(origin: Vector3, direction: Vector3, ammo: AmmoDef, muzzle_velocity: float,
		spread: float, max_range: float, source: RID, damage_scale: float = 1.0) -> void:
	projectile_serial += 1
	var projectile := ballistics.make_projectile(origin, direction, ammo, muzzle_velocity, spread,
		max_range, projectile_serial, [source])
	projectile.damage_scale = damage_scale
	projectiles.append(projectile)

func _show_projectile_tracer(start: Vector3, finish: Vector3, direction: Vector3) -> void:
	var length := minf(start.distance_to(finish), 1.5)
	if length < 0.01:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.012, 0.012, length)
	tracer.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.62, 0.18)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.32, 0.06)
	tracer.material_override = material
	tracer.position = finish - direction * length * 0.5
	tracer.basis = Basis.looking_at(direction, Vector3.UP)
	add_child(tracer)
	get_tree().create_timer(0.08).timeout.connect(tracer.queue_free)

func _step_projectile(projectile: Dictionary, delta: float) -> bool:
	var ammo: AmmoDef = projectile.ammo
	var start: Vector3 = projectile.position
	projectile.velocity = ballistics.velocity_after_forces(projectile.velocity, ammo, delta)
	projectile.energy = ballistics.energy(ammo.mass_kg, projectile.velocity.length())
	var direction: Vector3 = projectile.velocity.normalized()
	var travel := minf(projectile.velocity.length() * delta, projectile.range - projectile.traveled)
	var cursor := start
	var left := travel
	for _contact in range(8):
		if left <= 0.001 or projectile.energy < 5.0:
			break
		var query := PhysicsRayQueryParameters3D.create(cursor, cursor + direction * left, 1, projectile.exclude)
		query.hit_from_inside = true
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			projectile.position = cursor + direction * left
			projectile.traveled += left
			return projectile.traveled < projectile.range and projectile.energy >= 5.0
		var target: Node = hit.collider
		var point: Vector3 = hit.position
		var used := cursor.distance_to(point)
		projectile.traveled += used
		left -= used
		var material: MaterialDef = target.material if (target is RaidEntity or target is RaidGuard or target is VoxelDestructibleScript) else catalog_material("concrete")
		var target_id: String = target.entity_id if (target is RaidEntity or target is RaidGuard or target is RaidPlayer) else ""
		ballistics.impact.emit(point, hit.normal, material.id, target_id)
		if target is VoxelDestructibleScript:
			target.damage_at(point, ballistics.projectile_damage(projectile, material) * float(projectile.get("damage_scale", 1.0)), direction)
		if target is RaidGuard or target is RaidPlayer or (target is RaidEntity and target.kind == "target"):
			var outcome := _apply_projectile_hit(target, projectile, hit)
			if not outcome.continues:
				return false
			if outcome.outcome == "ricochet":
				direction = projectile.velocity.normalized().bounce(hit.normal).normalized()
				projectile.velocity = direction * projectile.velocity.length()
			else:
				direction = projectile.velocity.normalized()
			projectile.position = point + direction * 0.03
			projectile.exclude.append((target as CollisionObject3D).get_rid())
			left = maxf(0.0, left - 0.03)
			cursor = projectile.position
			continue
		var grazing := absf(direction.dot(hit.normal))
		var ricochet_chance: float = material.ricochet * clampf((0.5 - grazing) / 0.5, 0.0, 1.0) / (1.0 + ammo.penetration / 100.0)
		if projectile.ricochets < 2 and projectile.rng.randf() < ricochet_chance:
			projectile.ricochets += 1
			projectile.energy *= 0.6
			projectile.velocity = projectile.velocity.bounce(hit.normal) * sqrt(0.6)
			direction = projectile.velocity.normalized()
			projectile.position = point + hit.normal * 0.01
			projectile.exclude.append((target as CollisionObject3D).get_rid())
			cursor = projectile.position
			continue
		# shortcut: configured thickness stands in for collider depth; upgrade when geometry exposes entry/exit surfaces.
		var cost := material.resistance * material.thickness_meters
		if cost >= projectile.energy:
			return false
		projectile.energy -= cost
		projectile.velocity = direction * ballistics.speed_for_energy(ammo.mass_kg, projectile.energy)
		var thickness := material.thickness_meters + 0.01
		projectile.position = point + direction * thickness
		projectile.traveled += thickness
		projectile.exclude.append((target as CollisionObject3D).get_rid())
		left = maxf(0.0, left - thickness)
		cursor = projectile.position
	return projectile.traveled < projectile.range and projectile.energy >= 5.0

func _apply_projectile_hit(target: Node, projectile: Dictionary, hit: Dictionary) -> Dictionary:
	var ammo: AmmoDef = projectile.ammo
	var material: MaterialDef = target.material if (target is RaidGuard or target is RaidEntity) else catalog_material("steel")
	var damage: float = ballistics.projectile_damage(projectile, material) * float(projectile.get("damage_scale", 1.0))
	var armor: ArmorPlates
	if target is RaidGuard:
		armor = target.armor_plates
	elif target is RaidPlayer and participants.has(target.entity_id):
		armor = participants[target.entity_id].armor
	var outcome := {"outcome": "unprotected", "damage": damage, "continues": false, "energy": 0.0}
	if armor != null:
		outcome = armor.impact(target, projectile.velocity.normalized(), hit.normal, ammo, damage, projectile.rng)
	if outcome.energy > 0.0 and outcome.energy < 1.0:
		projectile.energy *= outcome.energy
		projectile.velocity = projectile.velocity.normalized() * ballistics.speed_for_energy(ammo.mass_kg, projectile.energy)
	if target is RaidGuard and target.state != RaidGuard.State.DEAD:
		target.health = maxf(0.0, target.health - outcome.damage)
		notice.emit("Guard hit (%s) | %d HP" % [outcome.outcome, ceili(target.health)])
		if target.health == 0.0:
			target.die()
			notice.emit("Guard neutralized")
	elif target is RaidPlayer and participants.has(target.entity_id):
		var state: RaidParticipant = participants[target.entity_id]
		state.health = maxf(0.0, state.health - outcome.damage)
		health_changed.emit(target.entity_id, state.health)
		notice.emit("Taking fire (%s) | %d HP" % [outcome.outcome, ceili(state.health)])
		if state.health == 0.0:
			_finish(false, "Killed in action | salvage lost")
	elif target is RaidEntity and target.kind == "target" and target.health > 0:
		target.health = maxf(0.0, target.health - outcome.damage)
		notice.emit("Target hit | %d HP" % ceili(target.health))
		if target.health == 0:
			target.get_node("MeshInstance3D").visible = false
			target.collision_layer = 0
	return outcome

func catalog_material(id: String) -> MaterialDef:
	return catalog_definition(id) as MaterialDef

func catalog_definition(id: String) -> Resource:
	return catalog.definitions[id]

func request_reload(player_id: String) -> bool:
	if not _allowed(player_id) or not participants[player_id].weapon.reload():
		return false
	notice.emit("Reloading...")
	return true

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
	return _claim(player_id, container_id, quantity, Vector2i(-1, -1))

func request_claim_at(player_id: String, container_id: String, quantity: int, x: int, y: int, rotated: bool = false) -> bool:
	return _claim(player_id, container_id, quantity, Vector2i(x, y), rotated)

func _claim(player_id: String, container_id: String, quantity: int, position: Vector2i, rotated: bool = false) -> bool:
	if not _container_reachable(player_id, container_id) or participants[player_id].opened_container != container_id:
		return false
	var container: RaidEntity = entities[container_id]
	if quantity <= 0 or quantity > container.remaining:
		notice.emit("Cannot take item: unavailable quantity or pack full")
		return false
	var pack: RaidInventory = participants[player_id].inventory
	var can_add := pack.add(container.loot.item.id, quantity) if position.x < 0 else pack.add_at(container.loot.item.id, quantity, position.x, position.y, rotated)
	if not can_add:
		notice.emit("Cannot take item: unavailable quantity or pack full")
		return false
	container.remaining -= quantity
	if container.loot.item.id == "salvage":
		participants[player_id].found_salvage += quantity
	notice.emit("Salvage secured. Reach the green extraction zone.")
	return true

func objective_complete(player_id: String) -> bool:
	return participants.has(player_id) and participants[player_id].found_salvage > 0

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
		if state.health > 0.0 and distance < nearest:
			target = state
			nearest = distance
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		var previous: Vector3 = projectile.position
		if not _step_projectile(projectile, delta):
			_show_projectile_tracer(previous, projectile.position, projectile.velocity.normalized())
			projectiles.remove_at(index)
		else:
			_show_projectile_tracer(previous, projectile.position, projectile.velocity.normalized())
	if target != null and guard.authority_tick(delta, target.actor, ballistics):
		_spawn_projectile(guard.global_position + Vector3.UP * 1.45, target.actor.camera.global_position - (guard.global_position + Vector3.UP * 1.45),
			target.weapon.definition.ammo, target.weapon.muzzle_velocity, 0.0, guard.archetype.attack_range,
			guard.get_rid(), guard.archetype.damage / target.weapon.definition.ammo.damage)
	for player_id in participants:
		_update_extraction(player_id, delta)
