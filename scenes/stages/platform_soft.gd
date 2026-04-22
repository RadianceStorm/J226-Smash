extends StaticBody2D
 
@export var ledge_points: Array[Marker2D] = []
 
var top_y:   float
var left_x:  float
var right_x: float
 
func _ready() -> void:
	add_to_group("platforms")
	add_to_group("soft_platforms")
 
