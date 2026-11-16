class_name DistrictAtmosphere
extends Node3D

@export var preset: WorldEnvironmentPreset
@export var quality: WorldQualitySettings
@export_range(0,3) var contamination_stage := 1
var lights: Array[Light3D]=[]
var effects: Array[GPUParticles3D]=[]
var contamination: Array[Node3D]=[]
var wet_materials: Array[StandardMaterial3D]=[]
var local_fog: Array[FogVolume]=[]
var update_left := 0.0
var elapsed := 0.0

func _ready() -> void:
	for node in get_parent().find_children("*","",true,false):
		if node is OmniLight3D or node is SpotLight3D: lights.append(node)
		if node is GPUParticles3D: effects.append(node)
		if node is FogVolume: local_fog.append(node)
		if node is Node3D and node.has_meta("contamination_stage"): contamination.append(node)
		if node is MeshInstance3D:
			for i in node.mesh.get_surface_count() if node.mesh!=null else 0:
				var material:=node.mesh.surface_get_material(i) as StandardMaterial3D
				if material!=null and material.has_meta("wettable") and not wet_materials.has(material): wet_materials.append(material)
	if preset==null: preset=WorldEnvironmentPreset.make("overcast_day")
	if quality==null: quality=WorldQualitySettings.make(1)
	apply()

func configure(_seed_value: int) -> void:
	pass # Layout and gameplay seeds do not change weather or world collision.

func apply() -> void:
	if not is_inside_tree(): return
	var world:=get_node("../WorldEnvironment") as WorldEnvironment
	var environment:=Environment.new()
	var sky_material:=ProceduralSkyMaterial.new()
	sky_material.sky_top_color=preset.sky_color
	sky_material.sky_horizon_color=preset.horizon_color
	sky_material.ground_horizon_color=preset.horizon_color
	sky_material.ground_bottom_color=Color("30382f")
	sky_material.sun_angle_max=20
	var sky:=Sky.new()
	sky.sky_material=sky_material
	environment.background_mode=Environment.BG_SKY
	environment.sky=sky
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color=preset.ambient_color
	environment.ambient_light_energy=preset.ambient_energy
	environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled=true
	environment.fog_light_color=preset.fog_color
	environment.fog_density=preset.fog_density
	environment.fog_sky_affect=.8
	environment.volumetric_fog_enabled=quality.volumetric_fog and RenderingServer.get_current_rendering_method()=="forward_plus"
	environment.volumetric_fog_density=preset.volumetric_density
	environment.volumetric_fog_albedo=preset.fog_color
	environment.volumetric_fog_length=100
	environment.ssao_enabled=quality.level>0
	environment.ssao_radius=1.2
	environment.ssao_intensity=1.1
	world.environment=environment
	var sun:=get_node("../Sun") as DirectionalLight3D
	sun.rotation_degrees=preset.sun_rotation
	sun.light_color=preset.sun_color
	sun.light_energy=preset.sun_energy
	sun.shadow_enabled=true
	sun.directional_shadow_max_distance=quality.shadow_distance
	for material in wet_materials:
		material.roughness=lerpf(.92,.28,preset.wetness)
	for node in contamination: node.visible=contamination_stage>0 and int(node.get_meta("contamination_stage"))<=contamination_stage
	for volume in local_fog:
		volume.visible=quality.level==2 and quality.volumetric_fog and contamination_stage>=int(volume.get_meta("contamination_stage",0))
	for effect in effects:
		effect.amount_ratio=clampf(float(quality.particle_budget)/maxi(1,_total_particles()),.05,1)
		var process:=effect.process_material as ParticleProcessMaterial
		if process!=null: process.gravity=effect.get_meta("base_gravity",Vector3.ZERO)+preset.wind*.3
	update_left=0

func _total_particles() -> int:
	var count:=0
	for effect in effects: count+=effect.amount
	return count

func _process(delta: float) -> void:
	elapsed+=delta
	update_left-=delta
	if update_left>0: return
	update_left=.2
	var camera:=get_viewport().get_camera_3d()
	if camera==null or quality==null: return
	var origin:=camera.global_position
	lights.sort_custom(func(a,b): return a.global_position.distance_squared_to(origin)<b.global_position.distance_squared_to(origin))
	for i in lights.size():
		var lamp:=lights[i]
		lamp.visible=i<quality.local_light_budget and lamp.global_position.distance_to(origin)<quality.detail_distance
		if lamp.get_parent() is MedTacBreakable:
			lamp.visible=lamp.visible and lamp.get_parent().light_enabled
			var fixture:=lamp.get_parent() as MedTacBreakable
			if not lamp.has_meta("base_energy"): lamp.set_meta("base_energy",lamp.light_energy)
			var phase:=fmod(elapsed+float(fixture.entity_id.hash()%97),17.0)
			lamp.light_energy=float(lamp.get_meta("base_energy"))*(.25 if not fixture.protected and phase<.2 else 1.0)
		lamp.shadow_enabled=lamp.visible and i<quality.local_shadow_budget
	for effect in effects:
		var active:=effect.global_position.distance_to(origin)<quality.detail_distance
		if effect.get_meta("effect_kind","")=="rain": active=active and preset.rain>0
		if effect.get_meta("effect_kind","")=="contamination": active=active and contamination_stage>=2
		effect.emitting=active

static func emitter(kind: String, count := 24) -> GPUParticles3D:
	var particles:=GPUParticles3D.new()
	particles.amount=count
	particles.lifetime=4
	particles.preprocess=2
	particles.visibility_aabb=AABB(Vector3(-10,-2,-10),Vector3(20,15,20))
	particles.set_meta("effect_kind",kind)
	var material:=ParticleProcessMaterial.new()
	material.emission_shape=ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents=Vector3(1,.3,1)
	material.direction=Vector3.UP
	material.spread=20
	material.initial_velocity_min=.15
	material.initial_velocity_max=.7
	material.gravity=Vector3(0,.12,0)
	material.scale_min=.035
	material.scale_max=.12
	material.color=Color(.6,.62,.55,.5)
	match kind:
		"smoke": material.scale_min=.2; material.scale_max=.55; material.color=Color(.22,.25,.24,.55)
		"steam": material.scale_min=.08; material.scale_max=.3; material.color=Color(.7,.77,.72,.4)
		"rain":
			material.gravity=Vector3(0,-9,0); material.direction=Vector3.DOWN
			material.initial_velocity_min=6; material.initial_velocity_max=9
			material.emission_box_extents=Vector3(12,.1,12)
			material.scale_min=.025; material.scale_max=.04; material.color=Color(.6,.7,.72,.5)
		"debris": material.scale_min=.025; material.scale_max=.065; material.gravity=Vector3(.1,-.15,0)
		"contamination": material.color=Color(.45,.49,.3,.35)
	particles.set_meta("base_gravity",material.gravity)
	particles.process_material=material
	var cube:=BoxMesh.new()
	cube.size=Vector3(1,4,1) if kind=="rain" else Vector3.ONE
	var surface:=StandardMaterial3D.new()
	surface.vertex_color_use_as_albedo=true
	surface.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
	surface.roughness=1
	cube.material=surface
	particles.draw_pass_1=cube
	return particles
