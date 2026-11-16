class_name MedTacDressing
extends Node3D

var configured := false
var layout_seed := -1
var selected_routes: Array[String] = []

func configure(seed_value: int) -> void:
	if configured and layout_seed==seed_value: return
	layout_seed=seed_value
	configured=true
	selected_routes.clear()
	var routes: Array[MedTacRouteBlock]=[]
	for node in get_parent().find_children("*","",true,false):
		if not is_instance_valid(node): continue
		if node is MedTacVariantSlot: node.configure(seed_value)
		if node is MedTacRouteBlock: routes.append(node)
	var rng:=RandomNumberGenerator.new()
	rng.seed=hash(str(seed_value)+":secondary_routes")
	var count:=rng.randi_range(0,2)
	for i in range(routes.size()):
		var swap:=rng.randi_range(i,routes.size()-1)
		var temp:=routes[i]
		routes[i]=routes[swap]
		routes[swap]=temp
	for i in range(routes.size()):
		routes[i].set_blocked(i<count)
		if i<count: selected_routes.append(routes[i].route_id)
	for node in get_parent().find_children("*","",true,false):
		if node is MedTacBreakable and node.kind=="light" and not node.protected:
			var lamp_rng:=RandomNumberGenerator.new()
			lamp_rng.seed=hash(str(seed_value)+":lighting:"+node.entity_id)
			node.set_lighting(lamp_rng.randf()>0.18)

