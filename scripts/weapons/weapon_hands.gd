class_name WeaponHands
extends Node3D

const GLOVE_HALF := Vector3(0.05, 0.045, 0.06)
const SLEEVE_HALF := Vector3(0.055, 0.055, 0.135)
var hands: Dictionary = {}
var poses: Dictionary = {}
var solids: Array[Dictionary] = []
var profile: WeaponHandProfile
var last_action := ""
var transitions: Dictionary = {}
var worst_correction := 0.0
var targets_debug: Dictionary = {}
var carried: Dictionary = {}
var prop_return: Dictionary = {}

func _ready() -> void:
	var glove := StandardMaterial3D.new()
	glove.albedo_color = Color(0.25, 0.22, 0.16)
	var sleeve := StandardMaterial3D.new()
	sleeve.albedo_color = Color(0.19, 0.24, 0.17)
	for side in ["right", "left"]:
		var parts: Dictionary = {}
		for kind in ["glove", "sleeve"]:
			var mesh := BoxMesh.new()
			mesh.size = (GLOVE_HALF if kind == "glove" else SLEEVE_HALF) * 2
			var visual := MeshInstance3D.new()
			visual.name = side.capitalize() + kind.capitalize()
			visual.mesh = mesh
			visual.layers = 2
			visual.material_override = glove if kind == "glove" else sleeve
			add_child(visual)
			parts[kind] = visual
		hands[side] = parts

func bind(data: WeaponHandProfile) -> void:
	profile = data
	last_action = ""
	transitions.clear()
	carried.clear()
	prop_return.clear()

func _contact(view: Node3D, bone: String, point: Vector3, angles: Vector3) -> Transform3D:
	var pose: Transform3D = global_transform.affine_inverse() * view.contact_transform(bone, point)
	pose.basis = pose.basis.orthonormalized() * Basis.from_euler(angles * PI / 180.0)
	return pose

func _path(progress: float, keys: Array) -> Vector3:
	var previous: Array = keys[0]
	for key: Array in keys:
		if progress < float(key[0]):
			var fraction := smoothstep(float(previous[0]), float(key[0]), progress)
			return Vector3(previous[1]).lerp(key[1], fraction)
		previous = key
	return previous[1]

func _magazine(view: Node3D, weapon: WeaponState, action: String, progress: float) -> void:
	if profile.magazine_bone.is_empty() or not view.bones.has(profile.magazine_bone):
		return
	var bone: Node3D = view.bones[profile.magazine_bone]
	var drop := profile.magazine_drop
	var offset := _path(progress, [[0, Vector3.ZERO], [0.14, Vector3.ZERO], [0.30, profile.withdraw_offset], [0.42, drop], [0.48, drop], [0.70, profile.insert_offset], [0.84, Vector3.ZERO], [1, Vector3.ZERO]])
	if action == "unload" and progress >= 0.42:
		offset = drop
	bone.position = Vector3(bone.get_meta("rest_position")) + offset
	bone.rotation_degrees = Vector3(bone.get_meta("rest_rotation")) + Vector3(0, 0, -12 * sin(clampf(progress, 0, 1) * PI))
	if not weapon.definition.magazine_id.is_empty():
		var had_magazine: bool = not weapon.data.magazine.is_empty()
		bone.visible = (had_magazine and progress < 0.42) or (action != "unload" and progress >= 0.48)
	elif profile.magazine_bone == "rocket":
		bone.visible = progress >= 0.48

# Deterministic evaluation is shared by live presentation and frame-seeking tests.
# It never changes ammunition, cooldowns, inventory, or authoritative animation time.
func evaluate(view: Node3D, weapon: WeaponState, action: String, seconds: float, delta: float = 0.0, snap: bool = true) -> Dictionary:
	if profile == null or hands.is_empty():
		return {}
	var progress := clampf(seconds / weapon.definition.reload_seconds, 0, 1)
	var reload := action.begins_with("reload") or action == "unload"
	if snap:
		carried.clear()
		prop_return.clear()
	elif not reload and not carried.is_empty():
		# A cancelled exchange returns the same prop continuously. Authority has
		# retained the magazine; presentation must not teleport it into the well.
		if not weapon.data.magazine.is_empty() and carried.progress > 0.14 and carried.progress < 0.84:
			prop_return = carried.duplicate(true)
			prop_return.elapsed = 0.0
		carried.clear()
	if reload:
		prop_return.clear()
		_magazine(view, weapon, action, progress)
		if not profile.loading_prop_bone.is_empty():
			var prop: Node3D = view.bones[profile.loading_prop_bone]
			var offset := _path(progress, [[0, Vector3.ZERO], [0.12, Vector3.ZERO], [0.26, profile.magazine_drop], [0.34, profile.magazine_drop], [0.50, profile.insert_offset], [0.66, Vector3.ZERO], [1, Vector3.ZERO]])
			prop.position = Vector3(prop.get_meta("rest_position")) + offset
	var returning := not prop_return.is_empty()
	var return_amount := 0.0
	if returning:
		prop_return.elapsed += delta
		return_amount = clampf(prop_return.elapsed / 0.24, 0, 1)
		var prop: Node3D = view.bones[prop_return.bone]
		var rest: Transform3D = global_transform.affine_inverse() * prop.global_transform
		if prop_return.bone == "cogwheel":
			# Keep the grasped drum still until released, then let its feed rotation
			# resume. Carrying the hand around a spinning drum crosses the receiver.
			var local_rest := Transform3D(Basis.from_euler(Vector3(prop.get_meta("rest_rotation")) * PI / 180), Vector3(prop.get_meta("rest_position")))
			rest = global_transform.affine_inverse() * prop.get_parent().global_transform * local_rest
		var start: Transform3D = prop_return.pose
		var middle := start.origin.lerp(rest.origin, 0.5) + profile.reach_clearance
		var path := start.interpolate_with(rest, smoothstep(0, 0.72, return_amount))
		path.origin = _path(return_amount, [[0, start.origin], [0.32, middle], [0.72, rest.origin], [1, rest.origin]])
		prop.global_transform = global_transform * path
	var right := _contact(view, profile.right_bone, profile.right_point, profile.right_angles)
	var left := _contact(view, profile.left_bone, profile.left_point, profile.left_angles)
	if weapon.data.attachments.has("grip") and view.bones.has("grip_socket"):
		left = _contact(view, "grip_socket", Vector3(view.bones.grip_socket.get_meta("pivot")) + Vector3(-1.5, -0.8, 0), profile.left_angles)
	if reload:
		var target := _contact(view, profile.magazine_bone if not profile.magazine_bone.is_empty() else profile.loading_bone, profile.magazine_point if not profile.magazine_bone.is_empty() else profile.loading_point, Vector3(-12, 0, 18))
		var outside := Vector3(minf(left.origin.x, target.origin.x), minf(left.origin.y, target.origin.y), maxf(left.origin.z, target.origin.z)) + profile.reach_clearance
		if profile.magazine_bone.is_empty():
			var supply := target.origin + Vector3(-0.12, -0.55, 0.12)
			left.origin = _path(progress, [[0, left.origin], [0.12, outside], [0.26, supply], [0.42, target.origin], [0.66, target.origin], [0.82, outside], [1, left.origin]])
			if not profile.loading_prop_bone.is_empty():
				left.origin = _path(progress, [[0, left.origin], [0.12, outside], [0.30, target.origin], [0.74, target.origin], [0.90, outside], [1, left.origin]])
		else:
			left.origin = _path(progress, [[0, left.origin], [0.07, outside], [0.14, target.origin], [0.80, target.origin], [0.9, outside], [1, left.origin]])
			if progress >= 0.14 and progress <= 0.80:
				left.origin = target.origin
			if action == "reload_insert" and progress < 0.48:
				# With an empty well there is nothing to remove. Reach straight to
				# the pouch, then follow the incoming magazine out of view.
				left.origin = _path(progress, [[0, left.origin], [0.12, outside], [0.30, target.origin], [0.48, target.origin]])
			elif action == "unload" and progress > 0.42:
				left.origin = _path(progress, [[0.42, target.origin], [0.70, outside], [1, left.origin]])
		left.basis = left.basis.slerp(target.basis, smoothstep(0, 0.14, progress) * (1 - smoothstep(0.80, 1, progress)))
	if action == "fire" and not profile.bolt_bone.is_empty():
		var cycle: float = clampf(seconds / float(view.clips.fire.length), 0, 1)
		var handle := _contact(view, profile.bolt_bone, profile.bolt_point, Vector3(-5, 0, -15))
		var grip_basis := right.basis
		var outside := right.origin + Vector3(0.13, 0.06, 0.01)
		right.origin = _path(cycle, [[0, right.origin], [0.10, outside], [0.23, handle.origin], [0.74, handle.origin], [0.85, outside], [1, right.origin]])
		if cycle >= 0.23 and cycle <= 0.74:
			right.origin = handle.origin
		right.basis = grip_basis.slerp(handle.basis, smoothstep(0.10, 0.23, cycle) * (1 - smoothstep(0.74, 1, cycle)))
	if action == "equip":
		var raise := 1 - smoothstep(0, 0.35, seconds)
		left.origin += Vector3(-0.05, 0.06, 0.03) * raise
		right.origin += Vector3(0.05, 0.03, 0.02) * raise
	if returning:
		var prop: Node3D = view.bones[prop_return.bone]
		var grasp: Transform3D = global_transform.affine_inverse() * prop.global_transform * prop_return.grasp
		left = grasp.interpolate_with(left, smoothstep(0.72, 1, return_amount))
		transitions.erase("left")
	solids = view.solid_shapes(self)
	var targets := {"right": right, "left": left}
	targets_debug = targets.duplicate(true)
	for side in ["right", "left"]:
		var desired: Transform3D = targets[side]
		if not snap and poses.has(side) and not (returning and side == "left"):
			if action != last_action and poses[side].glove.origin.distance_to(desired.origin) > 0.08:
				transitions[side] = {"start": poses[side].glove, "elapsed": 0.0}
			if transitions.has(side):
				var transition: Dictionary = transitions[side]
				transition.elapsed += delta
				var amount := clampf(transition.elapsed / 0.16, 0, 1)
				var middle: Vector3 = transition.start.origin.lerp(desired.origin, 0.5) + Vector3(0.08 if side == "right" else -0.08, -0.10, 0.03)
				desired.origin = _path(amount, [[0, transition.start.origin], [0.5, middle], [1, desired.origin]])
				desired.basis = transition.start.basis.slerp(desired.basis, smoothstep(0, 1, amount))
				if amount >= 1:
					transitions.erase(side)
		var fitted := _fit(desired, side)
		poses[side] = fitted
		hands[side].glove.transform = fitted.glove
		hands[side].sleeve.transform = fitted.sleeve
	if not snap and reload and not profile.magazine_bone.is_empty():
		var prop: Node3D = view.bones[profile.magazine_bone]
		carried = {"bone": profile.magazine_bone, "pose": global_transform.affine_inverse() * prop.global_transform, "grasp": prop.global_transform.affine_inverse() * global_transform * poses.left.glove, "progress": progress}
	if returning and return_amount >= 1:
		prop_return.clear()
	last_action = action
	return poses.duplicate(true)

func _sleeve(glove: Transform3D, elbow: Vector3) -> Transform3D:
	var direction := (elbow - glove.origin).normalized()
	if direction.is_zero_approx():
		direction = Vector3.BACK
	return Transform3D(Basis.looking_at(-direction, Vector3.UP), glove.origin + direction * 0.18)

func _fit(desired: Transform3D, side: String) -> Dictionary:
	var glove := HandClearance.project(desired, GLOVE_HALF, solids)
	var sign_x := 1.0 if side == "right" else -1.0
	var elbow := profile.right_elbow if side == "right" else profile.left_elbow
	var sleeve := _sleeve(glove, elbow)
	for attempt in range(21):
		if HandClearance.clear(glove, GLOVE_HALF, solids, 0.001) and HandClearance.clear(sleeve, SLEEVE_HALF, solids, 0.001):
			break
		# Steer the cuff around moving parts while preserving the wrist contact.
		# Trying both vertical directions matters for the rotating minigun drum:
		# a sleeve that clears one spoke can otherwise enter the following spoke.
		var found := false
		for offset in [Vector3(0, 0.3, 0), Vector3(sign_x * 0.3, 0, 0.1), Vector3(0, 0, 0.4), Vector3(0, -0.3, 0.2), Vector3(sign_x * 0.4, 0.3, 0.3), Vector3(sign_x * 0.6, -0.2, 0.5), Vector3(0, 1, 0.5)]:
			var candidate := _sleeve(glove, elbow + offset)
			if HandClearance.clear(candidate, SLEEVE_HALF, solids, 0.001):
				sleeve = candidate
				found = true
				break
		if found and HandClearance.clear(glove, GLOVE_HALF, solids, 0.001): break
		# Advance from the target so projection cannot trap a transition between overlapping solids.
		glove.origin = desired.origin + Vector3(sign_x * 0.02, -0.006, 0.005) * (attempt + 1)
		glove = HandClearance.project(glove, GLOVE_HALF, solids)
		sleeve = _sleeve(glove, elbow)
	worst_correction = maxf(worst_correction, desired.origin.distance_to(glove.origin))
	return {"glove": glove, "sleeve": sleeve}

func intersections(tolerance: float = 0.0001) -> Array[String]:
	var failures: Array[String] = []
	for side in poses:
		for kind in ["glove", "sleeve"]:
			var shape := HandClearance.box(poses[side][kind], GLOVE_HALF if kind == "glove" else SLEEVE_HALF)
			for solid in solids:
				if HandClearance.penetration(shape, solid).length() > tolerance:
					failures.append(side + ":" + kind + ":" + str(solid.get("tag", "")))
	return failures
