extends StaticBody3D

@export var is_solid: bool = false
@export var ledge_points: Array[Marker3D] = [$LedgePointLeft, $LedgePointRight]

var top_y:   float
var left_x:  float
var right_x: float

func _ready() -> void:
	add_to_group("platforms")
	add_to_group("soft_platforms")
	var shape := $CollisionShape3D.shape as BoxShape3D
	top_y   = global_position.y + shape.size.y / 2.0
	left_x  = global_position.x - shape.size.x / 2.0
	right_x = global_position.x + shape.size.x / 2.0
