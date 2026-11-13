class_name RaidGuard
extends CharacterBody3D

enum State { IDLE, INVESTIGATE, CHASE, ATTACK, DEAD }
@export var entity_id: String = "guard-01"
@export var archetype: NPCDef
@export var material: MaterialDef
var health: float
var state: State = State.IDLE
var last_heard: Vector3
var attack_left: float = 0.0
var inventory: RaidInventory
var weapon_state: WeaponState
var corpse_id := ""
var armor_plates: ArmorPlates
@onready var navigation: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	health = archetype.health
	if archetype.armor != null:
		armor_plates = ArmorPlates.new(archetype.armor)
	last_heard = global_position

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
		if state != State.ATTACK and state != State.CHASE:
			state = State.INVESTIGATE

func hear_shot(_player_id: String, position: Vector3) -> void:
	hear(position)

func authority_tick(delta: float, player: RaidPlayer, ballistics: Ballistics) -> bool:
	if state == State.DEAD:
		return false
	attack_left = maxf(0.0, attack_left - delta)
	var sees := can_see(player, ballistics)
	if sees:
		last_heard = player.global_position
		state = State.ATTACK if global_position.distance_to(player.global_position) <= archetype.attack_range else State.CHASE
	elif state == State.ATTACK or state == State.CHASE:
		state = State.INVESTIGATE
	if state == State.INVESTIGATE or state == State.CHASE:
		if navigation.target_position.distance_to(last_heard) > 0.2:
			navigation.target_position = last_heard
		if global_position.distance_to(last_heard) < 1.0:
			state = State.IDLE
		elif NavigationServer3D.map_get_iteration_id(navigation.get_navigation_map()) > 0:
			var next := navigation.get_next_path_position()
			var direction := (next - global_position)
			direction.y = 0
			direction = direction.normalized()
			var speed_scale := armor_plates.movement_multiplier() if armor_plates != null else 1.0
			velocity.x = direction.x * archetype.speed * speed_scale
			velocity.z = direction.z * archetype.speed * speed_scale
			if direction.length() > 0.1:
				rotation.y = atan2(-direction.x, -direction.z)
	if state == State.ATTACK or state == State.IDLE:
		velocity.x = 0
		velocity.z = 0
	if state == State.ATTACK:
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
	if state == State.ATTACK and sees and attack_left == 0.0:
		attack_left = archetype.attack_interval
		return true
	return false

func die() -> void:
	state = State.DEAD
	velocity = Vector3.ZERO
	collision_layer = 0
	$MeshInstance3D.rotation.z = PI / 2.0
	$MeshInstance3D.position.y = 0.3
