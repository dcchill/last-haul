class_name RaidAuthority
extends Node3D

signal notice(message: String)
signal container_opened(player_id: String, container_id: String)
signal finished(result: Dictionary)
signal health_changed(player_id: String, health: float)
signal shot_fired(player_id: String, position: Vector3)
enum Phase { DEPLOYING, ACTIVE, SUCCESS, FAILURE }
var phase := Phase.DEPLOYING
var raid_id := ""
var player: RaidPlayer
var guard: RaidGuard
var entities: Dictionary = {}
var participants: Dictionary[String, RaidParticipant] = {}
var ballistics := Ballistics.new()
var result: Dictionary = {}
var projectiles: Array[Dictionary] = []
var projectile_serial := 0
var catalog: Catalog
var practice := false
var accumulator := 0.0
var gameplay_tick := 0
var containers: Dictionary = {}
var mounts: Array[Node3D] = []
var smoke_events: Array[Dictionary] = []
var grenade_uses: Array[Dictionary] = []
@onready var extraction: ExtractionZone = $Extraction

func deploy(player_id: String, data: Catalog, settings: SettingsStore, loadout: Dictionary = {}) -> String:
	catalog = data
	practice = loadout.get("practice", false)
	player = $Player
	guard = $Guard
	player.entity_id = player_id
	player.authority = self
	player.settings = settings
	entities.clear()
	var registered: Array = [player, guard, extraction]
	for node in get_tree().get_nodes_in_group("raid_entities"):
		if is_ancestor_of(node):
			registered.append(node)
	for entity in registered:
		if entity.entity_id.is_empty() or entities.has(entity.entity_id):
			return "Missing or duplicate entity ID: " + entity.entity_id
		entities[entity.entity_id] = entity
	var pack: RaidInventory = loadout.get("pack", RaidInventory.new(catalog.items, 10, 6))
	if loadout.is_empty():
		pack.add("m_four", 1)
		pack.add("patrol", 1)
		pack.add("five_five_six", 60)
		var mag := ArmoryInstance.fresh("stanag_magazine", catalog.items)
		mag.rounds = 30
		pack.add("stanag_magazine", 1, mag)
	participants[player_id] = RaidParticipant.new(player, catalog, pack, loadout.get("weapon", "m_four"), loadout.get("armor", ""))
	guard.health = 20.0
	guard.armor_plates = ArmorPlates.new(catalog.definitions.vest)
	raid_id = ProfileStore._new_id()
	phase = Phase.ACTIVE
	$ImpactPresenter.catalog = catalog
	ballistics.impact.connect($ImpactPresenter.present)
	shot_fired.connect(guard.hear_shot)
	shot_fired.connect(player.shot_fired)
	_build_loot()
	if practice:
		guard.set_process(false)
		for index in range(2):
			_spawn_mount("mounted_minigun" if index == 0 else "mounted_rpg", Vector3(-5 + index * 4, 0, -9), 0, true)
	return ""

func is_active() -> bool:
	return phase == Phase.ACTIVE

func _allowed(player_id: String) -> bool:
	return is_active() and participants.has(player_id) and participants[player_id].health > 0

func request_input(player_id: String, trigger: bool, aim: bool, customizing: bool = false) -> bool:
	if not _allowed(player_id):
		return false
	var state: RaidParticipant = participants[player_id]
	state.last_input = gameplay_tick
	if state.weapon == null:
		return false
	var gun := state.weapon
	var edge := trigger and not gun.trigger
	gun.customizing = customizing
	gun.aiming = aim and gun.definition.can_aim and not customizing and gun.reload_end == 0
	gun.trigger = trigger and not customizing
	if edge and gun.trigger:
		return request_fire(player_id)
	return true

func request_fire(player_id: String) -> bool:
	if not _allowed(player_id):
		return false
	var state: RaidParticipant = participants[player_id]
	var gun := state.weapon
	if gun == null or not gun.fire():
		return false
	state.next_shot = gun.next_shot
	shot_fired.emit(player_id, state.actor.global_position)
	for pellet in range(gun.definition.pellets):
		var kind := "rocket" if gun.definition.feed == "ROCKET" else "bullet"
		var origin := state.actor.eye_position() - Vector3.UP * 0.05
		var bullet := _spawn_projectile(origin, state.actor.aim_direction(), gun.definition.projectile_speed,
			gun.definition.spread * (0.35 if gun.aiming else 1.0), gun.definition.damage, gun.definition.head_multiplier, state.actor.get_rid(), kind)
		bullet.velocity += Vector3(state.actor.movement.velocity.x, 0.0 if state.actor.grounded else state.actor.movement.velocity.y, state.actor.movement.velocity.z)
	_play_shot(gun, state.actor.global_position)
	if gun.definition.feed not in ["SHELL", "ROCKET"]:
		var casing: String = {"STANAG": "five_five_six_casing", "BARRET": "fifty_cal_casing"}.get(gun.definition.feed, "nine_mm_casing")
		if not state.inventory.add(casing, 1):
			_drop_item(casing, state.actor.global_position)
	return true

func _spawn_projectile(origin: Vector3, direction: Vector3, speed: float, spread: float, damage: float, head: float, source: RID, kind: String = "bullet") -> Dictionary:
	projectile_serial += 1
	var projectile := ballistics.make_bullet(origin, direction, speed, spread, damage, head, projectile_serial, [source], kind)
	projectiles.append(projectile)
	return projectile

func request_reload(player_id: String, magazine_id: String = "auto") -> bool:
	return _allowed(player_id) and participants[player_id].weapon != null and participants[player_id].weapon.reload(magazine_id)

func request_select(player_id: String, index: int) -> bool:
	if not _allowed(player_id):
		return false
	var selected: bool = participants[player_id].select(index, catalog)
	if selected:
		player.refresh_view()
	return selected

func request_assign(player_id: String, index: int, instance_id: String) -> bool:
	if not _allowed(player_id) or index < 0 or index >= 9:
		return false
	var state: RaidParticipant = participants[player_id]
	var item_index := state.inventory.find_instance(instance_id)
	if item_index < 0 or catalog.items[state.inventory.slots[item_index].id].kind not in ["weapon", "grenade", "mount", "magazine"]:
		return false
	for slot in range(9):
		if state.quickbar[slot] == instance_id:
			state.quickbar[slot] = ""
	state.quickbar[index] = instance_id
	if index == state.selected:
		return request_select(player_id, index)
	return true

func request_equip_armor(player_id: String, instance_id: String) -> bool:
	if not _allowed(player_id):
		return false
	var state: RaidParticipant = participants[player_id]
	var index := state.inventory.find_instance(instance_id)
	if index < 0 or not catalog.definitions[state.inventory.slots[index].id] is ArmorDef:
		return false
	var armor: ArmorDef = catalog.definitions[state.inventory.slots[index].id]
	state.armor_slots[armor.slot] = instance_id
	state.refresh_armor(catalog)
	player.refresh_armor_visuals()
	return true

func request_unequip_armor(player_id: String, slot: String) -> bool:
	if not _allowed(player_id) or not participants[player_id].armor_slots.has(slot):
		return false
	participants[player_id].armor_slots.erase(slot)
	participants[player_id].refresh_armor(catalog)
	player.refresh_armor_visuals()
	return true

func request_magazine_load(player_id: String, instance_id: String, unload: bool = false) -> bool:
	if not _allowed(player_id):
		return false
	var state: RaidParticipant = participants[player_id]
	var pack := state.inventory
	var index := pack.find_instance(instance_id)
	if index < 0:
		return false
	var entry: Dictionary = pack.slots[index]
	var feed := ArmoryContent.magazine_feed(entry.id)
	if feed.is_empty() or (state.weapon != null and state.weapon.reload_magazine == instance_id):
		return false
	if unload:
		var amount := int(entry.state.rounds)
		if amount == 0 or not pack.add(feed.ammo, amount):
			return false
		index = pack.find_instance(instance_id)
		pack.slots[index].state.rounds = 0
	else:
		var amount := mini(int(feed.capacity) - int(entry.state.rounds), pack.count(feed.ammo))
		if amount <= 0 or not pack.remove(feed.ammo, amount):
			return false
		index = pack.find_instance(instance_id)
		pack.slots[index].state.rounds += amount
	pack.changed.emit()
	return true

func request_attachment(player_id: String, slot: String, incoming_id: String = "") -> bool:
	if not _allowed(player_id) or slot not in ["optic", "muzzle", "grip"]:
		return false
	var state: RaidParticipant = participants[player_id]
	var gun := state.weapon
	if gun == null or not gun.customizing or gun.reload_end > 0 or gun.cycling_bolt():
		return false
	var pack := state.inventory
	var trial := RaidInventory.new(catalog.items, pack.width, pack.height)
	trial.slots = pack.slots.duplicate(true)
	var incoming: Dictionary = {}
	if not incoming_id.is_empty():
		var index := trial.find_instance(incoming_id)
		if index < 0:
			return false
		incoming = trial.slots[index].duplicate(true)
		var attachment: Resource = catalog.definitions[incoming.id]
		if not attachment is AttachmentDef or attachment.slot != slot or not attachment.supports(gun.definition):
			return false
		trial.slots.remove_at(index)
	var outgoing: Dictionary = gun.data.attachments.get(slot, {})
	if not outgoing.is_empty() and not trial.add_entry(outgoing):
		return false
	pack.slots = trial.slots
	if incoming.is_empty():
		gun.data.attachments.erase(slot)
	else:
		gun.data.attachments[slot] = {"id": incoming.id, "quantity": 1, "state": incoming.state.duplicate(true)}
	pack.changed.emit()
	player.refresh_view()
	return true

func request_grenade(player_id: String, kind: String = "") -> bool:
	if not _allowed(player_id):
		return false
	var state: RaidParticipant = participants[player_id]
	if state.grenade_cooldown > gameplay_tick or not state.pending_throw.is_empty():
		return false
	var entry := state.held_entry()
	var id: String = entry.get("id", "") if kind.is_empty() else kind
	if id not in ["impact_nade", "smoke_nade"] or state.inventory.count(id) < 1:
		return false
	state.grenade_cooldown = gameplay_tick + 12
	state.pending_throw = {"id": id, "tick": gameplay_tick + (10 if id == "smoke_nade" else 0), "selected": state.selected, "held": entry.get("state", {}).get("instance_id", entry.get("uid", ""))}
	if state.weapon == null and id == "smoke_nade":
		player.rifle.play_clip("pin")
	return true

func _throw_pending(state: RaidParticipant) -> void:
	if state.pending_throw.is_empty() or gameplay_tick < int(state.pending_throw.tick):
		return
	var pending := state.pending_throw
	state.pending_throw = {}
	var held := state.held_entry()
	if state.health <= 0 or int(pending.selected) != state.selected or held.get("state", {}).get("instance_id", held.get("uid", "")) != pending.held or not state.inventory.remove(pending.id, 1):
		return
	_spawn_projectile(state.actor.eye_position() - Vector3.UP * 0.1, state.actor.aim_direction(),
		1.5 if pending.id == "smoke_nade" else 1.3, 2, 0, 1, state.actor.get_rid(), "smoke" if pending.id == "smoke_nade" else "impact")
	_play_tone(state.actor.global_position, "throw")

func _step_projectile(projectile: Dictionary, _delta: float = 0.05) -> bool:
	if projectile.kind == "bullet" and int(projectile.age) >= 100:
		return false
	var start: Vector3 = projectile.position
	var end: Vector3 = start + projectile.velocity
	var hit := ballistics.trace(get_world_3d(), start, end - start, start.distance_to(end), projectile.exclude)
	# Match the source's swept contact on inflated humanoid bounding boxes.
	for actor in [player, guard]:
		if actor.get_rid() in projectile.exclude or (actor == guard and guard.state == RaidGuard.State.DEAD):
			continue
		var bounds := AABB(actor.global_position + Vector3(-0.6, -0.3, -0.6), Vector3(1.2, 2.4, 1.2))
		var contact: Variant = bounds.intersects_segment(start, end)
		if contact is Vector3 and (hit.is_empty() or start.distance_squared_to(contact) < start.distance_squared_to(hit.position)):
			hit = {"collider": actor, "position": contact, "normal": -projectile.velocity.normalized()}
	if not hit.is_empty():
		projectile.position = hit.position
		if projectile.kind in ["rocket", "impact"]:
			_explode(hit.position, 3.0)
		elif projectile.kind == "smoke":
			_smoke_contact(projectile, hit)
		else:
			_apply_projectile_hit(hit.collider, projectile, hit)
			ballistics.impact.emit(hit.position, hit.normal, "steel", "")
		return false
	Ballistics.advance(projectile)
	if projectile.age > 100:
		if projectile.kind == "impact":
			_explode(projectile.position, 3.0)
		elif projectile.kind == "smoke":
			_smoke_contact(projectile, {"position": projectile.position, "normal": Vector3.UP})
		return false
	return true

func _apply_projectile_hit(target: Node, projectile: Dictionary, hit: Dictionary) -> Dictionary:
	var damage: float = projectile.damage
	if (target is RaidPlayer or target is RaidGuard) and Ballistics.headshot(target, hit.position):
		damage *= float(projectile.head_multiplier)
	_apply_damage(target, damage)
	return {"outcome": "hit", "damage": damage, "continues": false, "energy": 0.0}

func _apply_damage(target: Node, damage: float, _material: MaterialDef = null, bypass_armor: bool = false) -> void:
	if target is RaidPlayer and participants.has(target.entity_id):
		var state: RaidParticipant = participants[target.entity_id]
		state.refresh_armor(catalog)
		var applied := damage if bypass_armor else state.armor.absorb(damage)
		state.refresh_armor(catalog)
		state.health = maxf(0, state.health - applied)
		health_changed.emit(target.entity_id, state.health)
		if state.health <= 0:
			if practice:
				state.health = 20
				notice.emit("Practice: health restored")
			else:
				_finish(false, "Killed in action | gear and loot lost")
	elif target is RaidGuard and target.state != RaidGuard.State.DEAD:
		target.health = maxf(0, target.health - (target.armor_plates.absorb(damage) if not bypass_armor and target.armor_plates != null else damage))
		if target.health == 0:
			target.die()
	elif target is RaidEntity and target.kind == "target":
		target.health = maxf(0, target.health - damage)
		if target.health == 0:
			target.get_node("MeshInstance3D").visible = false
			target.collision_layer = 0

func _exposure(origin: Vector3, target: Node3D) -> float:
	var visible := 0.0
	for x in [-0.25, 0.0, 0.25]:
		for y in [0.1, 0.9, 1.7]:
			for z in [-0.25, 0.0, 0.25]:
				var point: Vector3 = target.global_position + Vector3(x, y, z)
				var hit := ballistics.trace(get_world_3d(), origin, point - origin, point.distance_to(origin), [target.get_rid()])
				if hit.is_empty():
					visible += 1.0
	return visible / 27.0

func _explode(origin: Vector3, power: float) -> void:
	var diameter := power * 2.0
	for target in [player, guard] + entities.values().filter(func(value): return value is RaidEntity and value.kind == "target"):
		var distance: float = target.global_position.distance_to(origin) / diameter
		if distance > 1:
			continue
		var force: float = (1.0 - distance) * _exposure(origin, target)
		var damage := floorf((force * force + force) * 0.5 * 7.0 * diameter + 1.0)
		_apply_damage(target, damage)
		if target is RaidPlayer:
			target.movement.velocity += (target.eye_position() - origin).normalized() * force * participants[target.entity_id].armor.knockback_multiplier()
		elif target is CharacterBody3D:
			target.velocity += (target.global_position + Vector3.UP - origin).normalized() * force * 20
	for node in find_children("*", "StaticBody3D", true, false):
		if node is VoxelDestructible:
			node.blast(origin, power)
	_play_tone(origin, "explosion")
	var burst := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = power
	sphere.height = power * 2
	burst.mesh = sphere
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1, 0.5, 0.1, 0.3)
	burst.material_override = material
	add_child(burst)
	burst.global_position = origin
	var tween := create_tween()
	tween.tween_property(burst, "scale", Vector3.ONE * 0.01, 0.25)
	tween.tween_callback(burst.queue_free)

func _smoke_contact(projectile: Dictionary, hit: Dictionary) -> void:
	var below := ballistics.trace(get_world_3d(), hit.position + Vector3.UP * 0.02, Vector3.DOWN, 1.1, [])
	if below.is_empty() and projectile.age <= 100:
		var bounce: Dictionary = projectile.duplicate(true)
		bounce.position = hit.position + hit.normal * 0.04
		bounce.velocity = Ballistics.shoot(Vector3(-projectile.velocity.x / 20.0, projectile.velocity.y / 2.0, -projectile.velocity.z / 20.0), 0.15, 10, projectile.rng)
		bounce.age = 0
		grenade_uses.append(bounce)
		return
	for delay in [0, 20, 40, 60]:
		smoke_events.append({"tick": gameplay_tick + delay, "position": hit.position, "large": delay == 0})

func _smoke_burst(origin: Vector3) -> void:
	var cloud := GPUParticles3D.new()
	cloud.amount = 120
	cloud.lifetime = 3.0
	cloud.one_shot = true
	cloud.explosiveness = 0.9
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(2, 1, 2)
	process.gravity = Vector3(0, 0.4, 0)
	process.initial_velocity_min = 0.05
	process.initial_velocity_max = 0.3
	process.scale_min = 0.3
	process.scale_max = 0.7
	cloud.process_material = process
	var mesh := SphereMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 4
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.65, 0.66, 0.68, 0.28)
	mesh.material = material
	cloud.draw_pass_1 = mesh
	add_child(cloud)
	cloud.global_position = origin + Vector3.UP
	get_tree().create_timer(4).timeout.connect(cloud.queue_free)

func _show_projectile_tracer(start: Vector3, finish: Vector3, direction: Vector3) -> void:
	var length := minf(start.distance_to(finish), 32.0)
	if length < 0.001:
		return
	var tracer := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.008, 0.008, length)
	tracer.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(1, 0.7, 0.35, 0.7)
	tracer.material_override = material
	add_child(tracer)
	tracer.global_position = finish - direction * length * 0.5
	if absf(direction.dot(Vector3.UP)) < 0.999:
		tracer.basis = Basis.looking_at(direction, Vector3.UP)
	var tween := create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(tracer.queue_free)

func _play_shot(gun: WeaponState, origin: Vector3) -> void:
	var name := "mac10fire" if gun.definition.id == "mac_ten" else "m16fire" if gun.definition.id == "m_sixteen" else "m4fire"
	var audio := AudioStreamPlayer3D.new()
	audio.stream = load(ArmoryContent.ROOT + "sounds/" + name + ".ogg")
	audio.volume_db = linear_to_db(0.2 if gun.suppressed() else 2.0)
	audio.pitch_scale = 0.7 if gun.definition.feed == "BARRET" else 1.8
	add_child(audio)
	audio.global_position = origin
	audio.finished.connect(audio.queue_free)
	audio.play()

func _play_tone(origin: Vector3, kind: String) -> void:
	var audio := AudioStreamPlayer3D.new()
	audio.stream = ArmoryAudio.make_sound(kind)
	add_child(audio)
	audio.global_position = origin
	audio.finished.connect(audio.queue_free)
	audio.play()

func _drop_item(id: String, origin: Vector3) -> void:
	var drop := RaidEntity.new()
	drop.kind = "container"
	drop.entity_id = "drop-" + ProfileStore._new_id()
	drop.material = catalog.definitions.steel
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.15, 0.08, 0.15)
	mesh.mesh = box
	drop.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	drop.add_child(collision)
	add_child(drop)
	drop.global_position = origin + Vector3(0.4, 0.1, 0.4)
	entities[drop.entity_id] = drop
	var contents := RaidInventory.new(catalog.items, 2, 2)
	contents.add(id, 1)
	containers[drop.entity_id] = contents

func _build_loot() -> void:
	for entity in entities.values():
		if entity is RaidEntity and entity.kind == "container":
			var contents := RaidInventory.new(catalog.items, 10, 6)
			contents.add("salvage", 3)
			containers[entity.entity_id] = contents
	# Six fixed crates partition the complete roster; resets are deterministic.
	for index in range(6):
		var crate := RaidEntity.new()
		crate.entity_id = "armory-crate-%d" % index
		crate.kind = "container"
		crate.material = catalog.definitions.steel
		var visual := MeshInstance3D.new()
		visual.name = "MeshInstance3D"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1, 0.8, 0.8)
		visual.mesh = mesh
		visual.position.y = 0.4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.22, 0.32, 0.2)
		visual.material_override = mat
		crate.add_child(visual)
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = mesh.size
		collision.shape = shape
		collision.position.y = 0.4
		crate.add_child(collision)
		add_child(crate)
		crate.position = Vector3(-12 + index * 4, 0, 5)
		entities[crate.entity_id] = crate
		var contents := RaidInventory.new(catalog.items, 10, 10)
		for gun_index in range(index * 2, index * 2 + 2):
			var source: Dictionary = ArmoryContent.DATA.data.guns[gun_index]
			contents.add(source.id, 1)
			contents.add(source.ammo, 32)
			if not str(source.magazine).is_empty():
				contents.add(source.magazine, 1)
		if index < ArmoryContent.ARMOR_IDS.size():
			contents.add(ArmoryContent.ARMOR_IDS[index], 1)
		var extra := ["reflex_sight", "four_x_scope", "sniper_scope", "vertical_grip", "suppressor", "maska"]
		contents.add(extra[index], 1)
		contents.add("impact_nade", 2)
		contents.add("smoke_nade", 2)
		if index < 3:
			contents.add(["gun_mount", "mounted_minigun", "mounted_rpg"][index], 1)
		containers[crate.entity_id] = contents

func _container_reachable(player_id: String, container_id: String) -> bool:
	if not _allowed(player_id) or not entities.has(container_id) or not containers.has(container_id):
		return false
	var actor: RaidPlayer = participants[player_id].actor
	var container: Node3D = entities[container_id]
	if actor.global_position.distance_to(container.global_position) > 3.5:
		return false
	var direction := container.global_position + Vector3.UP * 0.4 - actor.eye_position()
	var hit := ballistics.trace(get_world_3d(), actor.eye_position(), direction, direction.length() + 0.1, [actor.get_rid()])
	return not hit.is_empty() and hit.collider == container

func request_interact(player_id: String, entity_id: String) -> bool:
	if not _allowed(player_id):
		return false
	if entities.get(entity_id) is MountedArmory:
		return request_mount_power(player_id, entity_id)
	if not _container_reachable(player_id, entity_id):
		return false
	if participants[player_id].actor.interaction_id() != entity_id:
		return false
	participants[player_id].opened_container = entity_id
	container_opened.emit(player_id, entity_id)
	return true

func request_transfer(player_id: String, container_id: String, index: int) -> bool:
	if not _container_reachable(player_id, container_id) or participants[player_id].opened_container != container_id:
		return false
	var contents: RaidInventory = containers[container_id]
	if index < 0 or index >= contents.slots.size():
		return false
	var entry: Dictionary = contents.slots[index]
	if not participants[player_id].inventory.add_entry(entry):
		return false
	if entry.id == "salvage":
		participants[player_id].found_salvage += int(entry.quantity)
	contents.slots.remove_at(index)
	contents.changed.emit()
	return true

func request_claim(player_id: String, container_id: String, quantity: int) -> bool:
	if not _container_reachable(player_id, container_id) or participants[player_id].opened_container != container_id or quantity < 1:
		return false
	var source: RaidInventory = containers[container_id]
	if source.count("salvage") < quantity or not participants[player_id].inventory.add("salvage", quantity):
		return false
	source.remove("salvage", quantity)
	participants[player_id].found_salvage += quantity
	return true

func request_claim_at(player_id: String, container_id: String, quantity: int, _x: int, _y: int, _rotated: bool = false) -> bool:
	return request_claim(player_id, container_id, quantity)

func objective_complete(player_id: String) -> bool:
	return participants.has(player_id) and participants[player_id].found_salvage > 0

func request_abandon(player_id: String) -> bool:
	if not _allowed(player_id):
		return false
	_finish(false, "Practice ended" if practice else "Raid abandoned | gear and loot lost")
	return true

func request_extract(player_id: String, zone_id: String = "extraction-01") -> bool:
	if practice or not _allowed(player_id) or zone_id != extraction.entity_id:
		return false
	if not extraction.overlaps_body(participants[player_id].actor) or not objective_complete(player_id):
		return false
	participants[player_id].extracting = true
	return true

func _update_extraction(player_id: String, delta: float) -> void:
	var state: RaidParticipant = participants[player_id]
	if not request_extract(player_id):
		state.extracting = false
		state.extraction_left = 3
		return
	state.extraction_left = maxf(0, state.extraction_left - delta)
	if state.extraction_left < 0.00001:
		_finish(true, "Salvage extracted")

func _finish(success: bool, reason: String) -> void:
	if not is_active():
		return
	phase = Phase.SUCCESS if success else Phase.FAILURE
	for state in participants.values():
		if state.weapon != null:
			state.weapon.cancel_reload()
	result = {"raid_id": raid_id, "success": success, "reason": reason, "practice": practice}
	finished.emit(result)

func _physics_process(delta: float) -> void:
	if not is_active():
		return
	accumulator += delta
	while accumulator + 0.0000001 >= 0.05 and is_active():
		accumulator -= 0.05
		gameplay_step()

func gameplay_step() -> void:
	gameplay_tick += 1
	for state in participants.values():
		state.clock = gameplay_tick
		state.actor.authority_movement_tick()
		if state.weapon != null:
			state.weapon.advance_tick()
			if gameplay_tick - state.last_input > 15:
				state.weapon.trigger = false
				state.weapon.aiming = false
			if state.weapon.trigger and state.weapon.definition.automatic:
				request_fire(state.actor.entity_id)
		_throw_pending(state)
	for index in range(projectiles.size() - 1, -1, -1):
		var projectile := projectiles[index]
		var previous: Vector3 = projectile.position
		if not _step_projectile(projectile):
			projectiles.remove_at(index)
		_show_projectile_tracer(previous, projectile.position, (projectile.position - previous).normalized())
	projectiles.append_array(grenade_uses)
	grenade_uses.clear()
	for index in range(smoke_events.size() - 1, -1, -1):
		if gameplay_tick >= int(smoke_events[index].tick):
			_smoke_burst(smoke_events[index].position)
			smoke_events.remove_at(index)
	for mount in mounts:
		if is_instance_valid(mount):
			mount.authority_tick(self)
	if not practice and guard.authority_tick(0.05, player, ballistics):
		var gun: WeaponDef = catalog.definitions.m_four
		_spawn_projectile(guard.global_position + Vector3.UP * 1.45, player.eye_position() - (guard.global_position + Vector3.UP * 1.45), gun.projectile_speed, gun.spread, gun.damage, gun.head_multiplier, guard.get_rid())
	for id in participants:
		_update_extraction(id, 0.05)

func catalog_material(id: String) -> MaterialDef:
	return catalog.definitions[id]

func catalog_definition(id: String) -> Resource:
	return catalog.definitions[id]

func _spawn_mount(id: String, at: Vector3, heading: int, filled: bool = false) -> MountedArmory:
	var mount := MountedArmory.new()
	mount.item_id = id
	mount.entity_id = "mount-" + ProfileStore._new_id()
	mount.heading = heading
	mount.ammo = 64 if filled else 0
	add_child(mount)
	mount.position = at
	mount.rotation.y = heading * PI / 2
	entities[mount.entity_id] = mount
	mounts.append(mount)
	return mount

func request_place(player_id: String) -> bool:
	if not _allowed(player_id):
		return false
	var state: RaidParticipant = participants[player_id]
	var entry := state.held_entry()
	if entry.is_empty() or catalog.items[entry.id].kind != "mount":
		return false
	var hit := ballistics.trace(get_world_3d(), player.eye_position(), player.aim_direction(), 4, [player.get_rid()])
	if hit.is_empty() or hit.normal.y < 0.9 or hit.collider is MountedArmory:
		return false
	var at := Vector3(snappedf(hit.position.x, 1), hit.position.y + 0.01, snappedf(hit.position.z, 1))
	for mount in mounts:
		if is_instance_valid(mount) and mount.position.distance_to(at) < 1:
			return false
	if not state.inventory.remove_entry(entry):
		return false
	_spawn_mount(entry.id, at, posmod(roundi(player.rotation.y / (PI / 2)), 4))
	return true

func request_mount_power(player_id: String, id: String) -> bool:
	if not _allowed(player_id) or not entities.get(id) is MountedArmory:
		return false
	var mount: MountedArmory = entities[id]
	if player.global_position.distance_to(mount.global_position) > 3.5:
		return false
	mount.powered = not mount.powered
	mount.refill(participants[player_id].inventory)
	notice.emit("%s: %s | %d rounds. [E] toggle, [F] refill, [X] pack up" % [mount.item_id, "ON" if mount.powered else "OFF", mount.ammo])
	return true

func request_mount_refill(player_id: String, id: String) -> bool:
	if not _allowed(player_id) or not entities.get(id) is MountedArmory or player.global_position.distance_to(entities[id].global_position) > 3.5:
		return false
	return entities[id].refill(participants[player_id].inventory)

func request_mount_pickup(player_id: String, id: String) -> bool:
	if not _allowed(player_id) or not entities.get(id) is MountedArmory or player.global_position.distance_to(entities[id].global_position) > 3.5:
		return false
	var mount: MountedArmory = entities[id]
	var pack: RaidInventory = participants[player_id].inventory
	var trial := RaidInventory.new(catalog.items, pack.width, pack.height)
	trial.slots = pack.slots.duplicate(true)
	if not trial.add(mount.item_id, 1) or (mount.ammo > 0 and not trial.add(mount.ammo_id(), mount.ammo)):
		return false
	pack.slots = trial.slots
	mounts.erase(mount)
	entities.erase(id)
	mount.queue_free()
	pack.changed.emit()
	return true

func practice_grant(player_id: String, id: String) -> bool:
	if not practice or not _allowed(player_id) or not catalog.items.has(id) or id in ArmoryContent.MIGRATIONS:
		return false
	var state: RaidParticipant = participants[player_id]
	var quantity := 64 if catalog.items[id].kind == "ammo" else 8 if catalog.items[id].kind == "grenade" else 1
	if not state.inventory.add(id, quantity):
		return false
	var entry: Dictionary = state.inventory.slots.back()
	if catalog.definitions[id] is WeaponDef:
		var gun: WeaponDef = catalog.definitions[id]
		var index := state.inventory.slots.size() - 1
		if not gun.magazine_id.is_empty():
			var mag := ArmoryInstance.fresh(gun.magazine_id, catalog.items)
			mag.rounds = gun.magazine_size
			state.inventory.slots[index].state.magazine = {"id": gun.magazine_id, "quantity": 1, "state": mag}
		else:
			state.inventory.slots[index].state.rounds = gun.magazine_size
		state.quickbar[state.selected] = entry.state.instance_id
		state.select(state.selected, catalog)
		player.refresh_view()
	return true

func practice_reset(player_id: String) -> bool:
	if not practice or not _allowed(player_id):
		return false
	participants[player_id].health = 20
	projectiles.clear()
	for entity in entities.values():
		if entity is RaidEntity and entity.kind == "target":
			entity.health = entity.max_health
			entity.collision_layer = 1
			entity.get_node("MeshInstance3D").visible = true
	guard.health = 20
	guard.armor_plates = ArmorPlates.new(catalog.definitions.vest)
	guard.state = RaidGuard.State.IDLE
	guard.collision_layer = 1
	guard.get_node("MeshInstance3D").rotation.z = 0
	guard.get_node("MeshInstance3D").position.y = 0.9
	for entry in participants[player_id].inventory.slots:
		if catalog.items[entry.id].kind == "ammo":
			entry.quantity = 64
		elif catalog.items[entry.id].kind == "magazine":
			entry.state.rounds = int(ArmoryContent.magazine_feed(entry.id).get("capacity", 0))
		elif catalog.definitions[entry.id] is WeaponDef:
			if not entry.state.magazine.is_empty():
				entry.state.magazine.state.rounds = catalog.definitions[entry.id].magazine_size
			else:
				entry.state.rounds = catalog.definitions[entry.id].magazine_size if catalog.definitions[entry.id].magazine_id.is_empty() else 0
		elif catalog.items[entry.id].kind == "armor":
			entry.state.wear = 0
	return true
