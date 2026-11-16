class_name WorldQualitySettings
extends Resource

@export_enum("Low", "Medium", "High") var level := 1
@export var detail_distance := 100.0
@export var shadow_distance := 90.0
@export var particle_budget := 1024
@export var volumetric_fog := true
@export var local_shadow_budget := 2
@export var local_light_budget := 16

static func make(index: int) -> WorldQualitySettings:
	var path:="res://resources/district/quality_"+str(clampi(index,0,2))+".tres"
	if ResourceLoader.exists(path): return (load(path) as WorldQualitySettings).duplicate()
	var q := WorldQualitySettings.new()
	q.level=clampi(index,0,2)
	q.detail_distance=[65.0,100.0,160.0][q.level]
	q.shadow_distance=[55.0,90.0,140.0][q.level]
	q.particle_budget=[384,1024,2048][q.level]
	q.volumetric_fog=q.level>0
	q.local_shadow_budget=[0,2,4][q.level]
	q.local_light_budget=[8,16,24][q.level]
	return q
