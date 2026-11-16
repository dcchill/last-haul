class_name DistrictSurfaceGeometry
extends RefCounted

## Split a convex polygon by a directed edge. Keeping outside pieces while
## continuing with the inside produces a subtraction without polygon holes.
static func half_plane(polygon: PackedVector2Array,a: Vector2,b: Vector2,inside: bool) -> PackedVector2Array:
	var result:=PackedVector2Array()
	if polygon.size()<3: return result
	for i in polygon.size():
		var p:=polygon[i]; var q:=polygon[(i+1)%polygon.size()]
		var dp:=(b-a).cross(p-a); var dq:=(b-a).cross(q-a)
		var keep_p: bool=dp>=0 if inside else dp<=0
		var keep_q: bool=dq>=0 if inside else dq<=0
		if keep_p: result.append(p)
		if keep_p!=keep_q: result.append(p.lerp(q,dp/(dp-dq)))
	return result

static func subtract(polygon: PackedVector2Array,cutter: PackedVector2Array) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array]=[]
	var remaining:=polygon
	var boundary:=cutter.duplicate()
	if Geometry2D.is_polygon_clockwise(boundary): boundary.reverse()
	for i in boundary.size():
		var outside:=half_plane(remaining,boundary[i],boundary[(i+1)%boundary.size()],false)
		if outside.size()>=3 and absf(area(outside))>.000001: pieces.append(outside)
		remaining=half_plane(remaining,boundary[i],boundary[(i+1)%boundary.size()],true)
		if remaining.size()<3: break
	return pieces

static func area(polygon: PackedVector2Array) -> float:
	var total:=0.0
	for i in polygon.size(): total+=polygon[i].cross(polygon[(i+1)%polygon.size()])
	return total*.5
