extends Camera3D

@export var offset: Vector3 = Vector3(0, 0, 6)

var target: Node3D

func _ready():
	var fighter = get_tree().get_first_node_in_group("fighter_mesh")
	target = fighter

func _physics_process(_delta):
	if target == null:
		return
	print("Camera at: ", global_position, " looking at: ", target.global_position)
	
	global_position = target.global_position + offset
	look_at(target.global_position)
# Rough approximation of a camera for testing. It sucks but I will interpolate it later and all that fancy stuff.
