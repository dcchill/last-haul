class_name WeaponHandProfile
extends Resource

@export var weapon_id := ""
# Contact points use the authored model's pixel coordinates (16 pixels per meter).
@export var right_bone := "frame"
@export var right_point := Vector3.ZERO
@export var left_bone := "frame"
@export var left_point := Vector3.ZERO
@export var right_angles := Vector3(-5, 0, -8)
@export var left_angles := Vector3(-8, 0, 8)
@export var magazine_bone := "mag"
@export var magazine_point := Vector3(-1.5, 0, 0)
@export var loading_bone := "frame"
@export var loading_point := Vector3.ZERO
@export var bolt_bone := ""
@export var bolt_point := Vector3.ZERO
@export var hip_grip := Vector3(0.36, -0.32, -0.62)
@export var iron_sight_distance := 0.55
@export var scope_distance := 0.14
@export var sight_offset := Vector3.ZERO
@export var loading_prop_bone := ""
@export var right_elbow := Vector3(0.64, -0.65, -0.15)
@export var left_elbow := Vector3(-0.22, -0.64, -0.22)
@export var magazine_drop := Vector3(-0.12, -0.72, 0.1)
@export var withdraw_offset := Vector3(-0.07, -0.13, 0.04)
@export var insert_offset := Vector3(-0.06, -0.15, 0.03)
@export var reach_clearance := Vector3(-0.10, -0.06, 0.03)

func valid() -> bool:
	if weapon_id.is_empty() or right_bone.is_empty() or left_bone.is_empty() or loading_bone.is_empty():
		return false
	for point in [right_point, left_point, right_angles, left_angles, magazine_point, loading_point, bolt_point, hip_grip, sight_offset, right_elbow, left_elbow, magazine_drop, withdraw_offset, insert_offset, reach_clearance]:
		if not point.is_finite(): return false
	return iron_sight_distance > 0 and scope_distance > 0
