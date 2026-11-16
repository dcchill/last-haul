class_name DistrictDebugOverlay
extends Control

@onready var district: Node3D=get_parent().get_parent()
var report: Dictionary={}
var tactics: Dictionary={}
var refresh_left:=0.0
var building_index := -1
var floor_index := 0
var building_ids: Array[String] = ["research","outpatient","logistics","facilities"]

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	visible=false
	report=district.get_meta("layout_report",{})
	if district.has_meta("building_ids"): building_ids.assign(district.get_meta("building_ids"))
	tactics=district.get_meta("tactical_report",{})
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var atmosphere:=district.get_node("Atmosphere") as DistrictAtmosphere
	match event.physical_keycode:
		KEY_F6:
			atmosphere.preset=atmosphere.preset.duplicate()
			atmosphere.preset.rain=1.0-atmosphere.preset.rain
			atmosphere.preset.wetness=atmosphere.preset.rain; atmosphere.apply()
		KEY_F7:
			visible=not visible
			if visible: district.set_meta("architecture_errors",(MedTacCampusValidator.inspect(district) if district.has_meta("campus_anchors") else CampusValidator.inspect(district)).errors)
		KEY_B:
			if not visible: return
			building_index=(building_index+2)%(building_ids.size()+1)-1
		KEY_PAGEUP:
			if not visible: return
			floor_index=mini(4 if district.has_meta("building_ids") else 1,floor_index+1)
		KEY_PAGEDOWN:
			if not visible: return
			floor_index=maxi(-1,floor_index-1)
		KEY_F9:
			var ids: Array[String]=["overcast_day","contaminated_dusk","foggy_morning","emergency_night"]
			atmosphere.preset=WorldEnvironmentPreset.make(ids[(ids.find(atmosphere.preset.id)+1)%4]); atmosphere.apply()
		KEY_F10: atmosphere.contamination_stage=(atmosphere.contamination_stage+1)%4; atmosphere.apply()
		_: return
	get_viewport().set_input_as_handled()
	queue_redraw()

func point(x: float,z: float) -> Vector2:
	if building_index<0: return Vector2(20,135)+Vector2(x+175,z+175)*1.25
	var building:=district.get_node("NavigationRegion3D/Building_"+building_ids[building_index]) as Node3D
	var bounds: AABB=building.global_transform*building.get_meta("building_bounds")
	var scale:=minf(600/bounds.size.x,390/bounds.size.z)
	return Vector2(35,155)+Vector2(x-bounds.position.x,z-bounds.position.z)*scale

func on_floor(node: Node3D) -> bool:
	var level:=floori((node.global_position.y+.5)/4.2)
	return level==floor_index

func _process(delta: float) -> void:
	if not visible: return
	refresh_left-=delta
	if refresh_left<=0: refresh_left=.25; queue_redraw()

func _draw() -> void:
	if report.is_empty(): return
	draw_rect(Rect2(10,10,660,590),Color(.035,.05,.05,.95))
	var font:=ThemeDB.fallback_font
	var atmosphere:=district.get_node("Atmosphere") as DistrictAtmosphere
	draw_string(font,Vector2(24,35),"F7 inspector  F6 rain  F9 atmosphere  F10 contamination",HORIZONTAL_ALIGNMENT_LEFT,-1,16)
	draw_string(font,Vector2(24,59),"seed %s / loops %s / %s / stage %d"%[report.get("seed",0),report.get("loops",0),atmosphere.preset.id,atmosphere.contamination_stage],HORIZONTAL_ALIGNMENT_LEFT,-1,15)
	draw_string(font,Vector2(24,83),"%.1f FPS / %.1f ms / %d draw calls / %d primitives"%[Engine.get_frames_per_second(),Performance.get_monitor(Performance.TIME_PROCESS)*1000,Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)],HORIZONTAL_ALIGNMENT_LEFT,-1,14)
	draw_string(font,Vector2(24,108),"B building: %s   PgUp/PgDn floor: %d"%["campus" if building_index<0 else building_ids[building_index],floor_index],HORIZONTAL_ALIGNMENT_LEFT,-1,14)
	if building_index>=0:
		var building:=district.get_node("NavigationRegion3D/Building_"+building_ids[building_index]) as Node3D
		for room in CampusValidator.rooms(building):
			if not on_floor(room): continue
			var bounds: AABB=room.global_transform*room.get_meta("room_bounds")
			var a:=point(bounds.position.x,bounds.position.z); var b:=point(bounds.end.x,bounds.end.z)
			draw_rect(Rect2(a,b-a),Color(.18,.35,.32,.4)); draw_rect(Rect2(a,b-a),Color(.5,.7,.62),false,1)
			draw_string(font,a+Vector2(3,13),str(room.get_meta("room_purpose")),HORIZONTAL_ALIGNMENT_LEFT,int(b.x-a.x-3),10)
			for entry: Vector3 in room.get_meta("entrance_points",PackedVector3Array()):
				var at: Vector3=room.to_global(entry); draw_circle(point(at.x,at.z),3,Color.LIGHT_GREEN)
		for node in building.find_children("*","Node3D",true,false):
			if node is RaidDoor and on_floor(node): draw_circle(point(node.global_position.x,node.global_position.z),4,Color.ORANGE if node.restricted else Color.SKY_BLUE)
			if node is NavigationLink3D and node.get_meta("campus_breach",false):
				var a: Vector3=node.to_global(node.start_position); var b: Vector3=node.to_global(node.end_position)
				draw_line(point(a.x,a.z),point(b.x,b.z),Color.GREEN if node.enabled else Color.RED,3)
			if node.has_meta("route_points") and on_floor(node):
				var path: PackedVector3Array=node.get_meta("route_points")
				for i in range(1,path.size()):
					var a: Vector3=node.to_global(path[i-1]); var b: Vector3=node.to_global(path[i]); draw_line(point(a.x,a.z),point(b.x,b.z),Color.GOLD,2)
		var errors: Array=district.get_meta("architecture_errors",[])
		draw_string(font,Vector2(24,576),"Doors blue / secure orange / routes gold / breaches green  |  %d architecture errors"%errors.size(),HORIZONTAL_ALIGNMENT_LEFT,-1,12)
		if not errors.is_empty(): draw_string(font,Vector2(24,593),str(errors[0]),HORIZONTAL_ALIGNMENT_LEFT,620,11,Color.SALMON)
		return
	for sample: Dictionary in tactics.get("exposure_samples",[]):
		draw_rect(Rect2(point(sample.x,sample.z)-Vector2.ONE*4,Vector2.ONE*8),Color(sample.exposure,.65*(1-sample.exposure),.1,.4))
	var pois: Array=report.get("pois",[])
	for edge: Dictionary in report.get("routes",[]):
		var a: Dictionary=pois.filter(func(p): return p.id==edge.a)[0]
		var b: Dictionary=pois.filter(func(p): return p.id==edge.b)[0]
		draw_line(point(a.x,a.z),point(b.x,b.z),Color(.4,.65,.7),2)
	for poi: Dictionary in pois:
		draw_circle(point(poi.x,poi.z),4,Color.WHITE)
		draw_string(font,point(poi.x,poi.z)+Vector2(6,-5),poi.id,HORIZONTAL_ALIGNMENT_LEFT,-1,13)
	for building in district.find_children("Building*","Node3D",true,false):
		if not building.has_meta("building_bounds"): continue
		var bounds: AABB=building.global_transform*building.get_meta("building_bounds")
		draw_rect(Rect2(point(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)*1.35),Color(.7,.7,.6,.7),false,2)
	for at: Dictionary in tactics.get("valid_cover",[]): draw_circle(point(at.x,at.z),2,Color(.45,.8,.45))
	for node in district.get_children():
		if node is Marker3D and node.is_in_group("raid_spawns"): draw_circle(point(node.position.x,node.position.z),5,Color.CORNFLOWER_BLUE)
		if node is ExtractionZone: draw_rect(Rect2(point(node.position.x,node.position.z)-Vector2.ONE*5,Vector2.ONE*10),Color.GREEN)
		if node is RaidGuard:
			draw_circle(point(node.position.x,node.position.z),3,Color.ORANGE_RED)
			var path: PackedVector3Array=node.navigation.get_current_navigation_path()
			for i in range(1,path.size()): draw_line(point(path[i-1].x,path[i-1].z),point(path[i].x,path[i].z),Color(.9,.6,.3,.6))
	var player:=district.get_node("Player") as Node3D
	draw_circle(point(player.position.x,player.position.z),5,Color.YELLOW)
