class_name HandClearance
extends RefCounted

const GAP := 0.002

static func box(pose: Transform3D, half: Vector3) -> Dictionary:
	var edges: Array[Vector3] = [pose.basis.x * half.x, pose.basis.y * half.y, pose.basis.z * half.z]
	var extent := edges[0].abs() + edges[1].abs() + edges[2].abs()
	return {"center": pose.origin, "edges": edges, "bounds": AABB(pose.origin - extent, extent * 2)}

# SAT for transformed boxes, including the sheared parallelepipeds produced by
# nonuniform animated scaling. The result moves A out of B, never moves the gun.
static func penetration(a: Dictionary, b: Dictionary, margin: float = 0.0) -> Vector3:
	if not a.bounds.grow(margin).intersects(b.bounds):
		return Vector3.ZERO
	var ae: Array = a.edges
	var be: Array = b.edges
	var axes: Array[Vector3] = [ae[1].cross(ae[2]), ae[2].cross(ae[0]), ae[0].cross(ae[1]), be[1].cross(be[2]), be[2].cross(be[0]), be[0].cross(be[1])]
	for edge in ae:
		for other in be:
			axes.append(edge.cross(other))
	var difference: Vector3 = a.center - b.center
	var minimum := INF
	var normal := Vector3.ZERO
	for raw in axes:
		if raw.length_squared() < 0.00000000000001:
			continue
		var axis := raw.normalized()
		var radius_a: float = absf(axis.dot(ae[0])) + absf(axis.dot(ae[1])) + absf(axis.dot(ae[2]))
		var radius_b: float = absf(axis.dot(be[0])) + absf(axis.dot(be[1])) + absf(axis.dot(be[2]))
		var overlap := radius_a + radius_b + margin - absf(axis.dot(difference))
		if overlap <= 0:
			return Vector3.ZERO
		if overlap < minimum:
			minimum = overlap
			normal = axis * (1 if axis.dot(difference) >= 0 else -1)
	return normal * minimum if is_finite(minimum) else Vector3.ZERO

static func clear(pose: Transform3D, half: Vector3, obstacles: Array[Dictionary], margin: float = GAP) -> bool:
	var shape := box(pose, half)
	for obstacle in obstacles:
		if not penetration(shape, obstacle, margin).is_zero_approx():
			return false
	return true

static func project(pose: Transform3D, half: Vector3, obstacles: Array[Dictionary]) -> Transform3D:
	for iteration in range(16):
		var correction := Vector3.ZERO
		var shape := box(pose, half)
		for obstacle in obstacles:
			var push := penetration(shape, obstacle, GAP)
			if push.length_squared() > correction.length_squared():
				correction = push
		if correction.is_zero_approx():
			return pose
		pose.origin += correction * 1.001
	return pose
