class_name RaidNavigation
extends RefCounted

static func path(map: RID, start: Vector3, destination: Vector3) -> PackedVector3Array:
	var query:=NavigationPathQueryParameters3D.new()
	query.map=map
	query.start_position=start
	query.target_position=destination
	query.path_search_max_polygons=65536
	var result:=NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(query,result)
	return result.path
