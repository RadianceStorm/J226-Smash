extends StaticBody2D
 
@export var ledge_points: Array[Marker2D] = []
 
var top_y:   float
var left_x:  float
var right_x: float
 
func _ready() -> void:
	add_to_group("platforms")
	add_to_group("soft_platforms")
	var shape := $CollisionShape2D.shape as RectangleShape2D
	# In 2D +Y is down, so the top edge is global_position.y - half height
	top_y   = global_position.y - shape.size.y / 2.0
	left_x  = global_position.x - shape.size.x / 2.0
	right_x = global_position.x + shape.size.x / 2.0
 
