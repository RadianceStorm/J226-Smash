extends Camera3D

@export var offset: Vector3 = Vector3(0, 0, 6)

var target: Node3D

func _ready():
	target = get_tree().get_first_node_in_group("fighter")

func _physics_process(delta):
	if target == null:
		return
	
	global_position = target.global_position + offset
	look_at(target.global_position)
# Rough approximation of a camera, suitable for testing.
