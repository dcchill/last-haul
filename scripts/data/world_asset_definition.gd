class_name WorldAssetDefinition
extends Resource

@export var id := ""
@export_file("*.tscn", "*.glb", "*.gltf") var scene_path := ""
@export var expected_size := Vector3.ONE
@export var dimension_tolerance := 0.2
@export var triangle_budget := 12000
@export var required_components: Array[String] = []
@export var collision_required := true
@export var provenance := "Original Last Haul asset"
@export var source_file := ""
