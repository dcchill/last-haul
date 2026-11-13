extends "res://scripts/characters/block_character.gd"

const SCAV_NAMES := ["Track jacket", "Work coat", "Surplus"]
const ZOMBIE_NAMES := ["Civilian", "Laborer", "Medical"]
var zombie := false
var variant := 0
var torso: Node3D
var head: Node3D
var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var forearms: Array[Node3D] = []
var weapon_mount: Node3D
var weapon_view: Node3D
var phase := 0.0
var fallen := false

static func select_variant(entity_id: String, requested: int) -> int:
	return requested if requested >= 0 and requested < 3 else int(entity_id.hash() % 3)

func build(is_zombie: bool, appearance: int) -> void:
	zombie = is_zombie
	variant = clampi(appearance, 0, 2)
	var cloth: String = (["736b62", "66747b", "8caaa3"] if zombie else ["4f6572", "807252", "56644a"])[variant]
	var pants: String = (["414a56", "514b3b", "536f6c"] if zombie else ["383d48", "4a5146", "444b3a"])[variant]
	var skin: String = (["91977c", "a4a084", "8d9c8b"] if zombie else ["b79a80", "a58b73", "c1a186"])[variant]
	torso = pivot(self, "Torso", Vector3(0, 0.86, 0))
	part(torso, Vector3(0.43, 0.51, 0.27), Vector3(0, 0.30, 0), cloth)
	part(torso, Vector3(0.40, 0.15, 0.25), Vector3(0, -0.01, 0), pants)
	part(torso, Vector3(0.44, 0.055, 0.28), Vector3(0, 0.05, 0), "383731")
	part(torso, Vector3(0.065, 0.045, 0.02), Vector3(0.03, 0.05, -0.15), "a0987c")
	part(torso, Vector3(0.13, 0.12, 0.14), Vector3(0, 0.59, 0), skin)
	head = pivot(torso, "Head", Vector3(0, 0.77, -0.025))
	part(head, Vector3(0.29, 0.32, 0.28), Vector3.ZERO, skin)
	part(head, Vector3(0.22, 0.09, 0.25), Vector3(0, -0.17, -0.012), skin)
	part(head, Vector3(0.065, 0.075, 0.055), Vector3(0, -0.015, -0.16), skin)
	for side in [-1, 1]:
		part(head, Vector3(0.045, 0.09, 0.08), Vector3(side * 0.16, -0.015, 0), skin)
		part(head, Vector3(0.085, 0.046 if zombie else 0.028, 0.013), Vector3(side * 0.075, 0.038, -0.148), "4b5047" if zombie else "493e34")
		part(head, Vector3(0.025, 0.018, 0.009), Vector3(side * 0.075, 0.032, -0.159), "d3cfab" if zombie else "252c29")
	part(head, Vector3(0.11, 0.025, 0.016), Vector3(0, -0.118, -0.151), "5c3b33" if zombie else "725b49")
	for side in [-1, 1]:
		var leg := pivot(torso, "LegLeft" if side < 0 else "LegRight", Vector3(side * 0.12, -0.07, 0))
		part(leg, Vector3(0.18, 0.34, 0.22), Vector3(0, -0.18, 0), pants)
		part(leg, Vector3(0.16, 0.28, 0.19), Vector3(0, -0.49, 0), pants)
		part(leg, Vector3(0.20, 0.18, 0.30), Vector3(0, -0.69, -0.035), "343832")
		part(leg, Vector3(0.21, 0.035, 0.31), Vector3(0, -0.77, -0.035), "262b29")
		part(leg, Vector3(0.115, 0.115, 0.015), Vector3(0, -0.32, -0.12), "747165" if side < 0 else cloth)
		legs.append(leg)
		var arm := pivot(torso, "ArmLeft" if side < 0 else "ArmRight", Vector3(side * 0.30, 0.50, 0))
		part(arm, Vector3(0.17, 0.28, 0.22), Vector3(0, -0.11, 0), cloth)
		var forearm := pivot(arm, "Forearm", Vector3(0, -0.25, 0))
		part(forearm, Vector3(0.145, 0.24, 0.18), Vector3(0, -0.10, 0), skin if zombie and side > 0 else cloth)
		part(forearm, Vector3(0.15, 0.11, 0.17), Vector3(0, -0.26, 0), skin if zombie else "45483d")
		arms.append(arm)
		forearms.append(forearm)
	if zombie:
		_zombie_details(cloth, skin)
	else:
		_scav_details(cloth)
	weapon_mount = pivot(torso, "WeaponMount", Vector3(0.13, 0.30, -0.31))
	pose(0)

func _zombie_details(cloth: String, skin: String) -> void:
	part(head, Vector3(0.26, 0.05, 0.24), Vector3(0, 0.17, 0.02), "55584c")
	part(head, Vector3(0.06, 0.08, 0.015), Vector3(-0.12, -0.08, -0.15), "784e44")
	part(torso, Vector3(0.11, 0.13, 0.017), Vector3(0.12, 0.35, -0.145), "573b35")
	part(torso, Vector3(0.045, 0.07, 0.02), Vector3(0.10, 0.36, -0.158), skin)
	for index in range(4):
		part(torso, Vector3(0.065, 0.05 + (index % 2) * 0.055, 0.025), Vector3(-0.15 + index * 0.10, 0.02, -0.14), cloth)
	part(legs[0], Vector3(0.08, 0.105, 0.018), Vector3(0, -0.28, -0.135), skin)
	part(forearms[1], Vector3(0.07, 0.06, 0.015), Vector3(0, -0.08, -0.10), "784e44")
	if variant == 0:
		part(torso, Vector3(0.055, 0.40, 0.02), Vector3(-0.05, 0.30, -0.15), "454c48")
		part(head, Vector3(0.10, 0.12, 0.25), Vector3(-0.11, 0.12, 0.04), "55584c")
	elif variant == 1:
		part(head, Vector3(0.36, 0.10, 0.34), Vector3(0, 0.20, 0), "aa9049")
		part(head, Vector3(0.39, 0.035, 0.37), Vector3(0, 0.14, -0.02), "7c6e41")
		for x in [-0.13, 0.13]:
			part(torso, Vector3(0.045, 0.45, 0.025), Vector3(x, 0.30, -0.15), "b0a16b")
		part(torso, Vector3(0.38, 0.04, 0.03), Vector3(0, 0.17, -0.155), "b0a16b")
	else:
		part(torso, Vector3(0.035, 0.43, 0.02), Vector3(0, 0.30, -0.15), "b4c2ae")
		part(torso, Vector3(0.11, 0.09, 0.025), Vector3(-0.12, 0.40, -0.15), "c6c9b2")
		part(torso, Vector3(0.055, 0.015, 0.012), Vector3(-0.12, 0.42, -0.17), "546e6a")
		part(head, Vector3(0.30, 0.07, 0.27), Vector3(0, 0.18, 0), "99b4a6")

func _scav_details(cloth: String) -> void:
	var webbing := "655a42" if variant != 1 else "4a5144"
	part(torso, Vector3(0.36, 0.29, 0.065), Vector3(0, 0.28, -0.165), webbing)
	for side in [-1, 1]:
		part(torso, Vector3(0.045, 0.45, 0.025), Vector3(side * 0.15, 0.33, -0.16), "383f34")
		part(torso, Vector3(0.045, 0.42, 0.025), Vector3(side * 0.15, 0.33, 0.155), "383f34")
		part(torso, Vector3(0.10, 0.17, 0.075), Vector3(side * 0.105, 0.25, -0.225), webbing)
		part(torso, Vector3(0.105, 0.035, 0.08), Vector3(side * 0.105, 0.33, -0.228), "8b7c59")
	part(torso, Vector3(0.31, 0.40, 0.18), Vector3(0, 0.30, 0.24), webbing)
	part(torso, Vector3(0.25, 0.15, 0.07), Vector3(0, 0.20, 0.36), "81735a")
	part(torso, Vector3(0.26, 0.04, 0.20), Vector3(0, 0.50, 0.25), "93846b")
	if variant == 0:
		part(head, Vector3(0.32, 0.14, 0.30), Vector3(0, 0.16, 0.015), "414849")
		part(head, Vector3(0.34, 0.055, 0.32), Vector3(0, 0.10, 0.015), "656960")
		for side in range(2):
			part(arms[side], Vector3(0.018, 0.23, 0.20), Vector3(-0.091 if side == 0 else 0.091, -0.11, 0), "c1b99a")
		part(torso, Vector3(0.025, 0.14, 0.018), Vector3(0, 0.48, -0.15), "c1b99a")
	elif variant == 1:
		part(head, Vector3(0.36, 0.37, 0.16), Vector3(0, 0.015, 0.13), cloth)
		part(head, Vector3(0.36, 0.09, 0.34), Vector3(0, 0.20, 0.03), cloth)
		for side in [-1, 1]:
			part(head, Vector3(0.065, 0.34, 0.30), Vector3(side * 0.17, 0.015, 0.03), cloth)
		part(head, Vector3(0.30, 0.13, 0.035), Vector3(0, -0.12, -0.16), "5f6559")
		part(torso, Vector3(0.45, 0.19, 0.28), Vector3(0, -0.08, 0), cloth)
	else:
		part(head, Vector3(0.35, 0.15, 0.32), Vector3(0, 0.17, 0), "655e4c")
		part(head, Vector3(0.34, 0.085, 0.05), Vector3(0, 0.14, -0.17), "9d947b")
		for side in [-1, 1]:
			part(head, Vector3(0.07, 0.22, 0.22), Vector3(side * 0.18, -0.025, 0.025), "9d947b")
		part(head, Vector3(0.24, 0.09, 0.025), Vector3(0, -0.14, -0.15), "5a5140")
		part(torso, Vector3(0.13, 0.08, 0.02), Vector3(-0.11, 0.48, -0.15), "8c8162")

func equip(weapon: WeaponState) -> void:
	if zombie or weapon == null: return
	if is_instance_valid(weapon_view):
		weapon_mount.remove_child(weapon_view)
		weapon_view.queue_free()
	weapon_view = preload("res://scripts/weapons/bedrock_weapon.gd").new()
	weapon_view.show_hands = false
	weapon_mount.add_child(weapon_view)
	var gun := weapon.definition
	weapon_view.configure(gun.model_path, gun.texture_path, gun.animation_path)
	weapon_view.seek_visual(weapon, "idle", 0)
	weapon_view.show_attachments(weapon)
	# Anchor the real model's grip to the right hand, independent of its source origin.
	weapon_view.position = -gun.hand_profile.right_point / 16.0

func pose(delta: float, speed := 0.0, attacking := false, attack_age := 10.0, dead := false) -> void:
	fallen = dead
	phase += delta * (5.0 if zombie else 7.0)
	torso.position = Vector3(0, 0.86 + sin(phase * 2) * minf(speed, 1) * 0.012, 0)
	torso.rotation = Vector3(0.13 if zombie else 0.0, 0, 0)
	head.rotation = Vector3(0.10 if zombie else 0.0, sin(phase * 0.25) * 0.035, -0.10 if zombie else 0.0)
	for index in range(2):
		legs[index].rotation.x = sin(phase + index * PI) * minf(speed * 0.14, 0.42)
		arms[index].rotation = Vector3(-0.55 - index * 0.14 if zombie else -0.55, 0, 0.08 if index == 0 else -0.08)
		forearms[index].rotation.x = -0.25 if zombie else -0.95
		if zombie:
			arms[index].rotation.x += sin(phase + index) * 0.08
			if attacking and attack_age < 0.45:
				arms[index].rotation.x -= sin(attack_age / 0.45 * PI) * 0.9
		else:
			arms[index].rotation.x -= 0.2 if attacking else 0.0
	weapon_mount.rotation.x = -0.10 if attacking else 0.18
	weapon_mount.position.z = -0.31 + (0.055 * (1.0 - attack_age / 0.16) if attacking and attack_age < 0.16 else 0.0)
	if dead:
		torso.position = Vector3(0, 0.39 if not zombie else 0.23, 0)
		torso.rotation = Vector3(-PI / 2, 0, 0.12)
		for arm in arms: arm.rotation.x = -0.15
		for leg in legs: leg.rotation.x = 0
		for forearm in forearms: forearm.rotation.x = -0.2
