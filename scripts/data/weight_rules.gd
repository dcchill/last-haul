class_name WeightRules
extends Resource

@export var light_limit := 20.0
@export var heavy_limit := 40.0
@export var walk_multiplier := 0.65
@export var sprint_multiplier := 0.5
@export var jump_multiplier := 0.7
@export var stamina_capacity := 100.0
@export var sprint_drain := 10.0
@export var recovery := 15.0
@export var heavy_drain_multiplier := 2.0
@export var heavy_recovery_multiplier := 0.4

func burden(weight: float) -> float:
	return clampf((weight - light_limit) / maxf(0.001, heavy_limit - light_limit), 0, 1)
