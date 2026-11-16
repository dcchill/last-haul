class_name RaidMapDefinition
extends Resource

@export var id := ""
@export var display_name := ""
@export_file("*.tscn") var scene_path := ""
@export_range(1, 7200) var infection_seconds := 1200.0
@export var spawn_group := "raid_spawns"
## Empty approved layouts preserves the original single-scene authoring workflow.
@export var approved_layouts: Array[String] = []
@export var insertion_count := 7
@export var extraction_count := 4
@export var assigned_extraction_count := 2
@export var active_loose_loot := 32
@export var enemy_count := 22
@export var infected_count := 16
@export var extraction_seconds := 15.0
@export var atmosphere_id := "overcast_day"

func validation_error() -> String:
	if id.is_empty() or display_name.is_empty() or scene_path.is_empty(): return "Incomplete map identity"
	if insertion_count < 1 or extraction_count < 1: return "Map needs insertions and extracts"
	if assigned_extraction_count < 1 or assigned_extraction_count > extraction_count: return "Invalid extraction assignments"
	if active_loose_loot < 0 or infected_count < 0 or enemy_count < infected_count: return "Invalid encounter/loot budget"
	if infection_seconds <= 0 or extraction_seconds <= 0: return "Invalid raid timing"
	return ""

