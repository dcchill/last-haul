class_name MedTacRouteBlock
extends MedTacBreakable

@export var route_id := ""
var blocked := false

func set_blocked(value: bool) -> void:
	blocked=value
	broken=false
	health=max_health
	for node in find_children("*","",true,false):
		if node is CollisionShape3D: node.set_deferred("disabled",not blocked)
		if node is GeometryInstance3D: node.visible=blocked
	var link:=get_node_or_null(navigation_link) as NavigationLink3D
	if link!=null: link.enabled=not blocked

