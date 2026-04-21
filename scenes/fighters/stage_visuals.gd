extends Node3D

func _ready():
	var platforms = get_tree().get_nodes_in_group("platforms")
	var meshes = get_children()

	for i in range(min(meshes.size(), platforms.size())):
		var platform = platforms[i]
		var mesh = meshes[i]
		var pos2d = platform.global_position
		mesh.global_position = Vector3(pos2d.x / 100.0, -pos2d.y / 100.0, 0.0)
	print("Visuals node position: ", global_position)
	print("Children count: ", get_children().size())
	for child in get_children():
		print("  Child: ", child.name, " at ", child.global_position)
	var tree_platforms = get_tree().get_nodes_in_group("platforms")
	print("Platforms in group: ", platforms.size())
	for p in tree_platforms:
		print("  Platform: ", p.name, " at 2D pos ", p.global_position)
