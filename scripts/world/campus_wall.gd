@tool
class_name CampusWall
extends VoxelDestructible

## Editable voxel panel. Structural and secure walls use ordinary static bodies.
@export var wall_material: Material
@export var initial_openings: Array[Rect2i] = []
var geometry_revision := 0
var preview_hash := 0

func _ready() -> void:
	collision=get_node("CollisionShape3D"); surface=get_node("MeshInstance3D")
	reset_cells()
	_rebuild()
	if wall_material != null: surface.material_override = wall_material
	preview_hash=hash([dimensions,initial_openings])
	set_process(Engine.is_editor_hint())

func reset_cells() -> void:
	cell_health.resize(dimensions.x*dimensions.y*dimensions.z); cell_health.fill(CELL_HEALTH)
	for opening in initial_openings:
		for x in range(maxi(0,opening.position.x),mini(dimensions.x,opening.end.x)):
			for y in range(maxi(0,opening.position.y),mini(dimensions.y,opening.end.y)):
				for z in dimensions.z: cell_health[_index(Vector3i(x,y,z))]=0

func _process(_delta: float) -> void:
	if hash([dimensions,initial_openings])==preview_hash: return
	reset_cells(); _rebuild(); preview_hash=hash([dimensions,initial_openings])

func _rebuild() -> void:
	super._rebuild()
	geometry_revision += 1
	if not Engine.is_editor_hint() and geometry_revision > 1 and is_inside_tree():
		get_tree().call_group("campus_breaches", "mark_dirty", get_parent())
