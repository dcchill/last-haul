extends "res://scripts/characters/block_character.gd"

const SHELL := "d5ac3e"
const EDGE := "f1cf68"
const RUST := "885037"
const JOINT := "303c3c"
@export var first_person := true
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var eyes: Array[MeshInstance3D] = []
var torso: Node3D
var head: Node3D
var mouth: MeshInstance3D
var phase := 0.0
var clock := 0.0
var boot_left := 1.2
var damage_left := 0.0
var landing := 0.0
var previous_health := 20.0
var was_grounded := false
var face_state := "normal"

func _ready() -> void:
	torso = pivot(self, "Torso", Vector3.ZERO)
	part(torso, Vector3(0.48, 0.48, 0.26), Vector3(0, 1.08, 0.18), SHELL)
	part(torso, Vector3(0.42, 0.055, 0.28), Vector3(0, 1.30, 0.18), EDGE)
	part(torso, Vector3(0.34, 0.13, 0.28), Vector3(0, 0.79, 0.13), JOINT)
	part(torso, Vector3(0.31, 0.23, 0.025), Vector3(0, 1.09, 0.035), RUST)
	part(torso, Vector3(0.28, 0.21, 0.03), Vector3(0, 1.10, 0.015), EDGE)
	for x in [-0.10, -0.05, 0.0]:
		part(torso, Vector3(0.023, 0.08, 0.012), Vector3(x, 1.12, -0.007), JOINT)
	part(torso, Vector3(0.04, 0.04, 0.014), Vector3(0.09, 1.13, -0.008), "91d8c6", true)
	part(torso, Vector3(0.13, 0.055, 0.016), Vector3(-0.14, 0.9, 0.04), RUST)
	part(torso, Vector3(0.06, 0.09, 0.016), Vector3(0.19, 1.21, 0.04), RUST)
	part(torso, Vector3(0.26, 0.32, 0.10), Vector3(0, 1.10, 0.36), JOINT)
	for y in [1.03, 1.10, 1.17]:
		part(torso, Vector3(0.20, 0.025, 0.02), Vector3(0, y, 0.42), "687a72")
	part(torso, Vector3(0.13, 0.12, 0.13), Vector3(0, 1.37, 0.11), JOINT)
	head = pivot(torso, "ScreenHead", Vector3(0, 1.59, 0.07))
	part(head, Vector3(0.54, 0.36, 0.35), Vector3.ZERO, RUST)
	part(head, Vector3(0.56, 0.31, 0.36), Vector3(0, 0.015, 0), SHELL)
	part(head, Vector3(0.50, 0.045, 0.36), Vector3(0, 0.18, 0), EDGE)
	part(head, Vector3(0.46, 0.255, 0.025), Vector3(0, 0, -0.19), JOINT)
	part(head, Vector3(0.40, 0.205, 0.015), Vector3(0, 0, -0.209), "142b30")
	for side in [-1, 1]:
		eyes.append(part(head, Vector3(0.075, 0.085, 0.009), Vector3(side * 0.105, 0.025, -0.222), "83ebdb", true))
		part(head, Vector3(0.034, 0.11, 0.14), Vector3(side * 0.295, 0, 0.03), JOINT)
		part(head, Vector3(0.022, 0.022, 0.015), Vector3(side * 0.25, -0.13, -0.188), "aeb4a0")
	mouth = part(head, Vector3(0.065, 0.012, 0.009), Vector3(0, -0.06, -0.222), "83ebdb", true)
	part(head, Vector3(0.08, 0.045, 0.018), Vector3(-0.19, 0.15, -0.187), RUST)
	part(head, Vector3(0.025, 0.14, 0.025), Vector3(0.18, 0.26, 0.04), JOINT)
	part(head, Vector3(0.06, 0.05, 0.05), Vector3(0.18, 0.34, 0.04), RUST)
	for side in [-1, 1]:
		var leg := pivot(torso, "LegLeft" if side < 0 else "LegRight", Vector3(side * 0.145, 0.74, 0.08))
		part(leg, Vector3(0.16, 0.27, 0.18), Vector3(0, -0.16, 0), SHELL)
		part(leg, Vector3(0.20, 0.10, 0.21), Vector3(0, -0.34, 0), JOINT)
		part(leg, Vector3(0.17, 0.22, 0.19), Vector3(0, -0.51, 0), SHELL)
		part(leg, Vector3(0.12, 0.055, 0.02), Vector3(0, -0.43, -0.105), RUST)
		part(leg, Vector3(0.235, 0.13, 0.33), Vector3(0, -0.66, -0.055), SHELL)
		part(leg, Vector3(0.245, 0.035, 0.34), Vector3(0, -0.722, -0.055), JOINT)
		part(leg, Vector3(0.20, 0.04, 0.02), Vector3(0, -0.66, -0.227), RUST)
		legs.append(leg)
		var arm := pivot(torso, "ArmLeft" if side < 0 else "ArmRight", Vector3(side * 0.34, 1.27, 0.10))
		part(arm, Vector3(0.20, 0.15, 0.24), Vector3.ZERO, EDGE)
		part(arm, Vector3(0.13, 0.24, 0.16), Vector3(0, -0.17, 0), SHELL)
		part(arm, Vector3(0.14, 0.09, 0.17), Vector3(0, -0.32, 0), JOINT)
		part(arm, Vector3(0.16, 0.18, 0.18), Vector3(0, -0.44, 0), SHELL)
		part(arm, Vector3(0.17, 0.10, 0.18), Vector3(0, -0.58, 0), JOINT)
		part(arm, Vector3(0.10, 0.05, 0.015), Vector3(0, -0.42, -0.10), RUST)
		arms.append(arm)
	set_first_person(first_person)

func set_first_person(enabled: bool) -> void:
	first_person = enabled
	shadow_only(head, enabled)
	for arm in arms: shadow_only(arm, enabled)

# The showcase drives this pose without a player, inventory, or camera.
func pose(delta: float, speed := 0.0, crouching := false, low_power := false, shutdown := false) -> void:
	clock += delta
	phase += delta * (9.0 if speed > 0.2 else 1.5)
	boot_left = maxf(0, boot_left - delta)
	damage_left = maxf(0, damage_left - delta)
	landing = move_toward(landing, 0, delta * 0.4)
	torso.position.y = sin(phase) * 0.008 - landing - (0.22 if crouching else 0.0)
	for index in range(2):
		legs[index].rotation.x = sin(phase + index * PI) * minf(speed * 0.1, 0.5)
		arms[index].rotation.x = -legs[index].rotation.x
	torso.rotation.x = move_toward(torso.rotation.x, 0.6 if shutdown else 0.0, delta * 2)
	head.rotation.z = sin(clock * 1.4) * 0.025 if not shutdown else 0.12
	face_state = "off" if shutdown else "hurt" if damage_left > 0 else "boot" if boot_left > 0 else "low" if low_power else "normal"
	for index in range(eyes.size()):
		var eye := eyes[index]
		eye.visible = not shutdown
		eye.scale.y = 0.12 if fmod(clock, 4.1) < 0.12 else 0.45 if low_power else 1.0
		eye.rotation.z = (1 if index == 0 else -1) * (0.45 if damage_left > 0 else -0.18 if low_power else 0.0)
		if boot_left > 0: eye.scale.y = 0.15 + 0.85 * (1.0 - boot_left / 1.2)
	mouth.visible = not shutdown
	mouth.scale.x = 0.5 if low_power or damage_left > 0 else 1.0

func _process(delta: float) -> void:
	if not get_parent() is RaidPlayer: return
	var actor: RaidPlayer = get_parent()
	var state := actor.participant()
	if state == null: return
	if state.health < previous_health: damage_left = 0.25
	previous_health = state.health
	if actor.grounded and not was_grounded: landing = 0.08
	was_grounded = actor.grounded
	var speed := Vector2(actor.velocity.x, actor.velocity.z).length() if actor.authority.is_active() else 0.0
	pose(delta, speed, actor.crouching, state.battery <= 60, state.battery <= 0 or state.health <= 0)
	actor.camera.rotation.z += sin(damage_left * 45) * damage_left * 0.12
	actor.camera.rotation.x += boot_left * 0.12 + (0.45 if state.battery <= 0 or state.health <= 0 else 0.0)
