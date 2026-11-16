class_name DistrictGenerationConfig
extends Resource

@export var generator_version := 2
@export_range(280,500) var size_meters := 350.0
@export var minimum_loops := 3
@export var minimum_poi_degree := 3
@export var minimum_enterable_fraction := 0.7
@export var maximum_exposure_gap := 25.0
@export var curated_seeds: Array[int] = [19381]
