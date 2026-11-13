class_name ItemDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export_range(1, 999) var stack_limit: int = 20
@export_range(1, 128) var width: int = 1
@export_range(1, 128) var height: int = 1
@export var kind: String = "item"
@export_multiline var description: String = ""
@export var rarity: String = "common"
@export var icon: Texture2D
@export var weight: float = 0.0
@export var max_durability: float = 100.0
@export var value: int = 0
@export var equipment_slots: PackedStringArray = []
@export var tags: PackedStringArray = []
@export var metadata: Dictionary = {}
@export var container: ContainerDef
@export var world_scene: PackedScene
@export var battery_amount := 0.0
@export var heal_amount := 0.0
@export var stamina_amount := 0.0
@export var melee_damage := 0.0
var definition: Resource
