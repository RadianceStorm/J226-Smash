extends StaticBody3D

@export var is_solid: bool = false
@export var ledge_points: Array[Marker3D] = [$LedgePointLeft, $LedgePointRight]

func _ready():
	add_to_group("platforms")
