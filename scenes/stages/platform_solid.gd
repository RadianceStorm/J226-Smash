extends StaticBody2D
 
@export var ledge_points: Array[Marker2D] = []
@export var ledge_facing: Array[int] = [1, -1]
 
func _ready() -> void:
	add_to_group("platforms")
 
func get_ledge_data(ledge_marker: Marker2D) -> Dictionary:
	for i in range(ledge_points.size()):
		if ledge_points[i] == ledge_marker:
			return {
				"position": ledge_points[i].global_position,
				"facing":   ledge_facing[i]
			}
	return {}
 
