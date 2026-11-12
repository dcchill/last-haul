class_name RaidPlayer
extends CharacterBody3D

@export var entity_id: String = ""
@export var speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_speed: float = 5.0
@export var accepts_local_input: bool = true
var authority: RaidAuthority
var settings: SettingsStore
@onready var camera: Camera3D = $Camera3D
@onready var rifle = $Camera3D/Rifle
var aim_blend := 0.0
var recoil := 0.0
var horizontal_recoil := 0.0
var armor_plates: ArmorPlates
var locomotion_time := 0.0

func shot_fired(player_id: String, _position: Vector3) -> void:
	if player_id == entity_id:
		var weapon: WeaponState = authority.participants[entity_id].weapon
		recoil = weapon.vertical_recoil
		horizontal_recoil = weapon.horizontal_recoil * (1.0 if randf() < 0.5 else -1.0)
		rifle.fire()

func _process(delta: float) -> void:
	if authority == null or not authority.participants.has(entity_id):
		return
	var aiming := accepts_local_input and authority.is_active() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and InputMap.has_action("aim") and Input.is_action_pressed("aim")
	animate_weapon(delta, aiming, authority.participants[entity_id].weapon)

func animate_weapon(delta: float, aiming: bool, weapon: WeaponState) -> void:
	var planar_speed := Vector2(velocity.x, velocity.z).length()
	var gait := clampf(planar_speed / sprint_speed, 0.0, 1.0)
	locomotion_time += delta * lerpf(5.5, 9.0, gait)
	aim_blend = move_toward(aim_blend, 1.0 if aiming and weapon.reload_left == 0.0 else 0.0, delta * 6.0 / weapon.ads_time)
	recoil = move_toward(recoil, 0.0, delta * 8.0)
	horizontal_recoil = move_toward(horizontal_recoil, 0.0, delta * 8.0)
	rifle.animate(delta, weapon)
	var sight: Node3D = rifle.bones["ads_socket"]
	var sight_offset: Vector3 = rifle.to_local(sight.global_position)
	var aim_position := Vector3(0.0, 0.0, -0.48) - sight_offset
	var movement_bob := Vector3(sin(locomotion_time) * 0.012, absf(cos(locomotion_time)) * 0.018, 0.0) * gait
	var run_blend := clampf((planar_speed - speed) / maxf(sprint_speed - speed, 0.01), 0.0, 1.0)
	rifle.position = Vector3(0.3, -0.45, -0.75).lerp(aim_position, aim_blend) + Vector3(0.0, 0.0, 0.09 * recoil) + movement_bob
	rifle.rotation = Vector3(-recoil + gait * 0.012, horizontal_recoil + sin(locomotion_time * 0.5) * run_blend * 0.012, 0.0)
	camera.fov = lerpf(80.0, 65.0, aim_blend)

func _unhandled_input(event: InputEvent) -> void:
	if not accepts_local_input or authority == null or not authority.is_active() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * settings.sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * settings.sensitivity, -1.45, 1.45)
	if event.is_action_pressed("reload"):
		authority.request_reload(entity_id)
	if event.is_action_pressed("interact"):
		authority.request_interact(entity_id, interaction_id())

func _physics_process(delta: float) -> void:
	if not accepts_local_input or authority == null or not authority.is_active() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	drive_movement(input, Input.is_action_just_pressed("jump"), Input.is_action_pressed("sprint"), delta)
	if Input.is_action_pressed("fire"):
		authority.request_fire(entity_id)
	if global_position.y < -10.0:
		authority.request_abandon(entity_id)

func drive_movement(input: Vector2, jump: bool, sprint: bool, delta: float) -> void:
	var direction := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var move_speed := (sprint_speed if sprint else speed) * (armor_plates.movement_multiplier() if armor_plates != null else 1.0)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	elif jump:
		velocity.y = jump_speed
	move_and_slide()

func interaction_id() -> String:
	var hit := Ballistics.new().trace(get_world_3d(), camera.global_position, -camera.global_basis.z, 3.0, [get_rid()])
	if not hit.is_empty() and hit.collider is RaidEntity and hit.collider.kind == "container":
		return hit.collider.entity_id
	return ""
