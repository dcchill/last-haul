class_name RaidDoor
extends StaticBody3D

@export var entity_id := ""
@export var restricted := false
@export var inside_direction := Vector3.FORWARD
@export var material: MaterialDef
@export var open := false
@export var unlocked := false
@export var traversal_link: NodePath
var auto_close_left := 0.0

func _ready() -> void:
	add_to_group("raid_doors")
	refresh()

func is_inside(actor: Node3D) -> bool:
	return (actor.global_position - global_position).dot(global_basis * inside_direction) > 0.35

func activate(from_inside := false) -> void:
	if restricted and not unlocked and from_inside:
		open = true
		auto_close_left = 4.0
	else:
		open = not open
	refresh()

func refresh() -> void:
	for node in get_children():
		if node is CollisionShape3D: node.set_deferred("disabled", open)
		if node is MeshInstance3D: node.visible = not open
	var link := get_node_or_null(traversal_link) as NavigationLink3D
	if link != null: link.enabled = open or not restricted or unlocked

func _physics_process(delta: float) -> void:
	if auto_close_left <= 0: return
	auto_close_left -= delta
	if auto_close_left <= 0:
		# Do not close through an actor; egress must never crush or trap anyone.
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = $CollisionShape3D.shape
		query.transform = $CollisionShape3D.global_transform
		query.exclude = [get_rid()]
		query.collision_mask = 1
		var occupied := false
		for hit in get_world_3d().direct_space_state.intersect_shape(query, 64):
			if hit.collider is RaidPlayer or hit.collider is RaidGuard: occupied = true
		if occupied:
			auto_close_left = 0.5
			return
		open = false
		refresh()

