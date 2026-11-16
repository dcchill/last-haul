class_name DistrictPOIDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export var purpose := "industrial"
@export var footprint := Vector2(40,40)
@export var loot_profiles: Array[String] = ["technical"]
@export var risk := 1.0
@export var building_scenes: Array[PackedScene] = []
