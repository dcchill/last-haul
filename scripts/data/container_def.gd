class_name ContainerDef
extends Resource

@export var id: String = "container"
@export var display_name: String = "Storage"
@export var dimensions: Vector2i = Vector2i(5, 5)
@export var allowed_categories: PackedStringArray = []
@export var prohibited_categories: PackedStringArray = []
@export var weight_limit: float = 0.0
@export var item_limit: int = 0
@export var background: Texture2D = preload("res://ui/container_large_no_slots.png")
@export var slot_size: int = 36
@export var searchable: bool = false
@export var search_seconds: float = 1.5
@export var progressive_discovery: bool = false
@export var accessible: bool = true
@export var persistent: bool = true
