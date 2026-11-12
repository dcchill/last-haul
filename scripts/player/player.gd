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
	var move_speed := sprint_speed if sprint else speed
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
