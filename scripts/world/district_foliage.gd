class_name DistrictFoliage
extends MultiMeshInstance3D

## The headless Dummy renderer doesn't retain MultiMesh GPU buffers while
## authoring. Store transforms explicitly, then upload once on scene entry.
@export var instance_transforms: Array[Transform3D]=[]

func _ready() -> void:
	if multimesh==null: return
	var source_mesh:=multimesh.mesh
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.mesh=source_mesh
	multimesh.instance_count=instance_transforms.size()
	for i in instance_transforms.size(): multimesh.set_instance_transform(i,instance_transforms[i])
