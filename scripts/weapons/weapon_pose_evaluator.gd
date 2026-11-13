class_name WeaponPoseEvaluator
extends RefCounted

static func place(view: Node3D, weapon: WeaponState, aim: float, magnification: int = 1, displacement: Vector3 = Vector3.ZERO, angles: Vector3 = Vector3.ZERO) -> void:
	var profile := weapon.definition.hand_profile
	var heavy := weapon.definition.id in ["mini_gun", "upgraded_mini_gun"]
	var scale_factor := (0.8 if weapon.definition.id in ["mini_gun", "upgraded_mini_gun", "mac_ten", "double_barrel"] else 1.0) - aim * 0.1
	view.scale = Vector3.ONE * scale_factor
	var sight: Node3D = view.bones.get("optic_socket" if weapon.data.attachments.has("optic") else "ads_socket")
	var aim_position := Vector3(0, -0.2, -0.55)
	if sight != null:
		var offset: Vector3 = view.to_local(sight.global_position)
		if weapon.data.attachments.has("optic"):
			offset.y += (0.375 if magnification > 1 else 0.25) * 0.25
		if magnification > 1:
			offset.z += 0.39 * 0.25
		aim_position = Vector3(0, 0, -profile.scope_distance if magnification > 1 else -profile.iron_sight_distance) - offset * scale_factor
	var hip := profile.hip_grip - profile.right_point / 16.0 * scale_factor
	view.position = hip.lerp(aim_position + profile.sight_offset, aim) + displacement
	if view.action == "equip":
		# Bring replacement geometry up from below the view, leaving room for the
		# persistent hands to release the old grip and meet the new weapon.
		view.position += Vector3(0, -0.75, 0.08) * (1 - smoothstep(0, 0.30, view.action_time))
	view.rotation_degrees = angles + (Vector3(4, 5, 0) if heavy else Vector3.ZERO)

static func seek(view: Node3D, rig: WeaponHands, weapon: WeaponState, action: String, seconds: float, aim: float = 0.0, magnification: int = 1, spin: float = 0.0) -> Dictionary:
	view.spin_angle = spin
	view.seek_visual(weapon, action, seconds)
	place(view, weapon, aim, magnification)
	if rig.profile != weapon.definition.hand_profile:
		rig.bind(weapon.definition.hand_profile)
	return rig.evaluate(view, weapon, action, seconds)
