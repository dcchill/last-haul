class_name DistrictDebugOverlay
extends Control

@onready var district: Node3D=get_parent().get_parent()
var report: Dictionary={}
var tactics: Dictionary={}
var refresh_left:=0.0

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	visible=false
	report=district.get_meta("layout_report",{})
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
		KEY_F7: visible=not visible
		KEY_F9:
			var ids: Array[String]=["overcast_day","contaminated_dusk","foggy_morning","emergency_night"]
			atmosphere.preset=WorldEnvironmentPreset.make(ids[(ids.find(atmosphere.preset.id)+1)%4]); atmosphere.apply()
		KEY_F10: atmosphere.contamination_stage=(atmosphere.contamination_stage+1)%4; atmosphere.apply()
		_: return
	get_viewport().set_input_as_handled()
	queue_redraw()

func point(x: float,z: float) -> Vector2: return Vector2(20,105)+Vector2(x+175,z+175)*1.35

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
	for sample: Dictionary in tactics.get("exposure_samples",[]):
		draw_rect(Rect2(point(sample.x,sample.z)-Vector2.ONE*4,Vector2.ONE*8),Color(sample.exposure,.65*(1-sample.exposure),.1,.4))
	var pois: Array=report.get("pois",[])
	for edge: Dictionary in report.get("routes",[]):
		var a: Dictionary=pois.filter(func(p): return p.id==edge.a)[0]
		var b: Dictionary=pois.filter(func(p): return p.id==edge.b)[0]
		draw_line(point(a.x,a.z),point(b.x,b.z),Color(.4,.65,.7),2)
	for poi: Dictionary in pois:
		draw_arc(point(poi.x,poi.z),35*1.35,0,TAU,24,Color(.7,.7,.6,.7))
		draw_circle(point(poi.x,poi.z),4,Color.WHITE)
		draw_string(font,point(poi.x,poi.z)+Vector2(6,-5),poi.id,HORIZONTAL_ALIGNMENT_LEFT,-1,13)
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
