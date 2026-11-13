class_name RaidGuard
extends CharacterBody3D

enum State { IDLE, INVESTIGATE, CHASE, ATTACK, DEAD, PATROL, SEARCH, RETURN, TAKE_COVER }
@export var entity_id: String = "guard-01"
@export var archetype: NPCDef
@export var material: MaterialDef
@export_range(-1, 2) var appearance_variant := -1
# shortcut: routes and cover use static baked navigation; add dynamic rebaking when structural destruction changes paths.
@export var patrol_points := PackedVector3Array()
@export var cover_points := PackedVector3Array()
var patrol_index := 0
var home_position := Vector3.ZERO
var search_left := 0.0
var cover_left := 0.0
var cover_target := Vector3.ZERO
var health: float
var state: State = State.IDLE
var last_heard: Vector3
var attack_left: float = 0.0
var inventory: RaidInventory
var weapon_state: WeaponState
var corpse_id := ""
var armor_plates: ArmorPlates
@onready var navigation: NavigationAgent3D = $NavigationAgent3D
@onready var body: Node3D = $Visual

func _ready() -> void:
	health = archetype.health
	if archetype.armor != null:
		armor_plates = ArmorPlates.new(archetype.armor)
	last_heard = global_position
	home_position = global_position
	body.build(archetype.melee, body.select_variant(entity_id, appearance_variant))

func _process(delta: float) -> void:
	var raid := get_parent() as RaidAuthority
	if raid == null or not raid.is_active(): return
	body.pose(delta, Vector2(velocity.x, velocity.z).length(), state in [State.ATTACK, State.TAKE_COVER], archetype.attack_interval - attack_left, state == State.DEAD)

func reset_visual() -> void:
	body.pose(0)

func can_see(player: RaidPlayer, ballistics: Ballistics) -> bool:
	var offset := player.global_position - global_position
	if offset.length() > archetype.sight_range:
		return false
	if offset.length() > 0.1 and (-global_basis.z).dot(offset.normalized()) < cos(deg_to_rad(archetype.field_of_view * 0.5)):
		return false
	return clear_sight(player, ballistics)

func clear_sight(player: RaidPlayer, ballistics: Ballistics) -> bool:
	var origin := global_position + Vector3.UP * 1.45
	var destination := player.eye_position()
	var hit := ballistics.trace(get_world_3d(), origin, destination - origin, origin.distance_to(destination) + 0.1, [get_rid()])
	return not hit.is_empty() and hit.collider == player

func hear(position: Vector3) -> void:
	if state != State.DEAD and global_position.distance_to(position) <= archetype.hearing_range:
		last_heard = position
		if archetype.melee or state not in [State.ATTACK, State.CHASE, State.TAKE_COVER]:
			state = State.INVESTIGATE

func hear_shot(_player_id: String, position: Vector3) -> void:
	hear(position)

func authority_tick(delta: float, player: RaidPlayer, ballistics: Ballistics) -> bool:
	if state == State.DEAD:
		return false
	attack_left = maxf(0.0, attack_left - delta)
	cover_left = maxf(0.0, cover_left - delta)
	var sees := can_see(player, ballistics)
	var destination := global_position
	var moving := false
	if sees:
		last_heard = player.global_position
		search_left = 3.0
		if global_position.distance_to(player.global_position) > archetype.attack_range:
			state = State.CHASE
			destination = last_heard
			moving = true
		else:
			state = State.ATTACK
			if not archetype.melee and not cover_points.is_empty():
				if cover_left == 0:
					cover_target = choose_cover(player, ballistics)
					cover_left = 3.0
				if global_position.distance_to(cover_target) > 0.8:
					state = State.TAKE_COVER
					destination = cover_target
					moving = true
	elif state in [State.ATTACK, State.CHASE, State.TAKE_COVER]:
		state = State.INVESTIGATE
	if not sees:
		if state == State.INVESTIGATE:
			destination = last_heard
			moving = true
			if global_position.distance_to(last_heard) < 1.0:
				state = State.SEARCH
				search_left = 3.0
		elif state == State.SEARCH:
			search_left = maxf(0.0, search_left - delta)
			rotation.y += delta * 0.9
			if search_left == 0: state = State.RETURN
		elif state == State.RETURN:
			destination = home_position
			moving = true
			if global_position.distance_to(home_position) < 1.0: state = State.IDLE
		elif not patrol_points.is_empty():
			state = State.PATROL
			destination = patrol_points[patrol_index]
			moving = true
			if global_position.distance_to(destination) < 1.0:
				patrol_index = (patrol_index + 1) % patrol_points.size()
	velocity.x = 0
	velocity.z = 0
	if moving and NavigationServer3D.map_get_iteration_id(navigation.get_navigation_map()) > 0:
		if navigation.target_position.distance_to(destination) > 0.2:
			navigation.target_position = destination
		var direction := navigation.get_next_path_position() - global_position
		direction.y = 0
		direction = direction.normalized()
		var speed_scale := armor_plates.movement_multiplier() if armor_plates != null else 1.0
		velocity.x = direction.x * archetype.speed * speed_scale
		velocity.z = direction.z * archetype.speed * speed_scale
		if direction.length() > 0.1: rotation.y = atan2(-direction.x, -direction.z)
	if sees:
		var offset := player.global_position - global_position
		rotation.y = atan2(-offset.x, -offset.z)
	velocity.y = -2.0 if test_move(global_transform, Vector3.DOWN * 0.03) else velocity.y - 18.0 * delta
	var travel := velocity * delta
	for _slide in range(3):
		var collision := move_and_collide(travel)
		if collision == null:
			break
		travel = collision.get_remainder().slide(collision.get_normal())
		velocity = velocity.slide(collision.get_normal())
	if state in [State.ATTACK, State.TAKE_COVER] and sees and attack_left == 0.0:
		attack_left = archetype.attack_interval
		return true
	return false

func choose_cover(player: RaidPlayer, ballistics: Ballistics) -> Vector3:
	var best := global_position
	var distance := 8.0
	var map := navigation.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0: return best
	for point in cover_points:
		var travel := global_position.distance_to(point)
		if travel >= distance: continue
		var path := NavigationServer3D.map_get_path(map, global_position, point, true)
		if path.is_empty() or path[path.size() - 1].distance_to(point) > 1.0: continue
		var low := point + Vector3.UP * 0.6
		var shield := ballistics.trace(get_world_3d(), low, player.eye_position() - low, low.distance_to(player.eye_position()), [get_rid()])
		if shield.is_empty() or shield.collider == player: continue
		best = point
		distance = travel
	return best

func die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	collision_layer = 0
	body.pose(0, 0, false, 10, true)
