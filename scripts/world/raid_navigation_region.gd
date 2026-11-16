class_name RaidNavigationRegion
extends NavigationRegion3D

func _init() -> void:
	# These meshes are baked assets, assembled before deployment. Synchronous region
	# updates prevent a new map exposing an empty intermediate region snapshot.
	NavigationServer3D.region_set_use_async_iterations(get_rid(),false)
