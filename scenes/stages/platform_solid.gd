extends StaticBody3D

@export var is_solid: bool = true
@export var ledge_points: Array[Marker3D] = [$LedgePointLeft, $LedgePointRight]
@export var ledge_facing: Array[int] = [1, -1]

func _ready():
	add_to_group("platforms")

func get_ledge_data(ledge_area):

	for i in range(ledge_points.size()):

		if ledge_points[i] == ledge_area:

			return {
				"position": ledge_points[i].global_position,
				"facing": ledge_facing[i]
			}

	return null
