class_name WorldArtDirection
extends Resource

@export var title := "Decaying Voxel Realism"
@export var architecture_step := 0.25
@export var prop_step := 0.125
@export var detail_step := 0.03125
@export var wall_thickness := 0.3
@export var door_size := Vector2(1.6, 2.4)
@export var floor_height := 3.5
@export var asset_triangle_budget := 12000
@export var facade_triangle_budget := 20000
@export var palette: Dictionary = {
	"concrete": Color("777b75"), "asphalt": Color("353b3c"),
	"steel": Color("495652"), "paint": Color("71827a"),
	"rust": Color("79503d"), "glass": Color("233e43"),
	"rubber": Color("252a2b"), "wood": Color("796c50"),
	"medical": Color("b2bdb5"), "dirt": Color("55594a"),
	"contamination": Color("4f5940"), "warning": Color("b59a54"),
	"red": Color("81504a"), "light": Color("d6d6b6")}
