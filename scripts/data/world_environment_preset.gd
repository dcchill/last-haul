class_name WorldEnvironmentPreset
extends Resource

@export var id := "overcast_day"
@export var sky_color := Color("7d898e")
@export var horizon_color := Color("a6ada7")
@export var sun_color := Color("d7ddd2")
@export var sun_rotation := Vector3(-48, -35, 0)
@export var sun_energy := 0.9
@export var ambient_color := Color("a7b5bb")
@export var ambient_energy := 0.4
@export var fog_color := Color("87928b")
@export var fog_density := 0.002
@export var volumetric_density := 0.003
@export var rain := 0.0
@export var wetness := 0.0
@export var wind := Vector3(0.6, 0, 0.2)

static func make(identity: String,load_saved := true) -> WorldEnvironmentPreset:
	var path:="res://resources/district/environments/"+identity+".tres"
	if load_saved and ResourceLoader.exists(path): return (load(path) as WorldEnvironmentPreset).duplicate()
	var p := WorldEnvironmentPreset.new()
	p.id = identity
	match identity:
		"contaminated_dusk":
			p.sky_color=Color("5d6976"); p.horizon_color=Color("a48d75")
			p.sun_rotation=Vector3(-12,-60,0); p.sun_color=Color("e5ba87"); p.sun_energy=1.1
			p.ambient_energy=.4; p.fog_color=Color("747d79"); p.volumetric_density=.012
		"foggy_morning":
			p.sun_energy=.55; p.fog_density=.009; p.volumetric_density=.035
			p.sky_color=Color("899c9d"); p.fog_color=Color("a0ada7")
		"emergency_night":
			p.sky_color=Color("101b28"); p.horizon_color=Color("24313a")
			p.sun_color=Color("718da6"); p.sun_energy=.18; p.ambient_energy=.28
			p.fog_color=Color("28373c"); p.volumetric_density=.012
	return p
