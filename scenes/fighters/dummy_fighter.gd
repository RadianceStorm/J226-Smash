extends CharacterBody3D

# --- Exported movement values ---
@export var walk_speed: float = 6.0
@export var dash_speed: float = 10.0
@export var jump_velocity: float = 12.0 # default: 12.0
@export var gravity: float = -30.0
@export var fastfall_speed: float = -25.0 # How fast you fastfall
@export var terminal_velocity: float = -15.0
@export var max_double_jumps: int = 999  # Number of mid-air jumps allowed

# --- Environmental Collision Boxes (ECB) ---

@onready var ecb_top = $EnvCollisionBox/top
@onready var ecb_bottom = $EnvCollisionBox/bottom
@onready var ecb_left = $EnvCollisionBox/left
@onready var ecb_right = $EnvCollisionBox/right
@onready var ecb_mesh_debug = $ECB_DebugMesh

# Get Env Coll Box to Axis Aligned Bounding Box
func get_ecb_aabb() -> AABB:
	var points = [
		ecb_top.global_position,
		ecb_bottom.global_position,
		ecb_left.global_position,
		ecb_right.global_position
	]
	
	var min_v = points[0]
	var max_v = points [0]
	
	for p in points:
		min_v = min_v.min(p)
		max_v = max_v.max(p)
		
	return AABB(min_v, max_v - min_v)

# --- Ledge ---
var ledge_points: Array[Marker3D] = []

func collect_ledges(node):
	if node is Marker3D:
		if node.name.begins_with("ledge"):
			ledge_points.append(node)
	for child in node.get_children():
		collect_ledges(child)
	print("Ledges found:", ledge_points.size())

# --- States ---
var grounded: bool = false
var hitstun: int = 0
var helpless: bool = false
var fastfalling: bool = false
var double_jumps_remaining: int = max_double_jumps
var facing_direction: int = 1

enum PlayerState {
	NORMAL,
	LEDGE_HANG
}

var state: PlayerState = PlayerState.NORMAL

# --- Down Button States ---
var down_hold_frames: int = 0
var down_tap_frames_threshold: int = 12
var down_was_pressed: bool = false
var down_tapped: bool = false

# --- Internal movement ---
var current_velocity: Vector3 = Vector3.ZERO
var groundsnap_distance = 0.1
var prev_ecb_bottom_pos: Vector3
var prev_ecb_top_pos: Vector3

# --- Ledge Functions ---

func handle_ledge_grab(ledge: Marker3D):
	print("LEDGE GRAB")
	state = PlayerState.LEDGE_HANG
	current_velocity = Vector3.ZERO
	global_position = ledge.global_position
	facing_direction = ledge.facing_direction

# check if ledgegrab hitbox is touching a ledge point
func check_grab_box(grab_area: Area3D, required_facing: int):
	var shape_node = grab_area.get_node("hitbox")
	var shape: BoxShape3D = shape_node.shape
	var center = grab_area.global_transform.origin
	var extents = shape.size / 2.0
	for ledge in ledge_points:
		if ledge.facing_direction != required_facing:
			continue

		var p = ledge.global_transform.origin

		var dx = abs(p.x - center.x)
		var dy = abs(p.y - center.y)
		var dz = abs(p.z - center.z)

		if dx <= extents.x \
		and dy <= extents.y \
		and dz <= extents.z:
			handle_ledge_grab(ledge)
			return

func check_for_ledge_grab():
	print("checking ledge grab")
	if state == PlayerState.LEDGE_HANG:
		return
	if grounded:
		return
	if current_velocity.y > 0:
		return
	check_grab_box($LedgeGrabLeft, 1)
	check_grab_box($LedgeGrabRight, -1)

func _ready():
	var stage = get_tree().get_root().find_child("StageTest", true, false)
	collect_ledges(stage)
	prev_ecb_bottom_pos = ecb_bottom.global_position
	prev_ecb_top_pos = ecb_top.global_position
	# print_tree_pretty()
	
	print($LedgeGrabLeft)
	print($LedgeGrabLeft/hitbox)
	print($LedgeGrabLeft/hitbox.shape)

func _physics_process(delta):
	
	# --- Tick hitstun ---
	if hitstun > 0:
		hitstun -= 1
		return # This won't do... Needs an update
	# if ledge_hanging:
		# current_velocity = Vector3.ZERO
		
	# --- Down tap detection ---

	down_tapped = false

	var down_pressed = Input.is_action_pressed("move_down")

	if down_pressed:
		down_hold_frames += 1
	else:
		# Button was released this frame
		if down_was_pressed:
			if down_hold_frames <= down_tap_frames_threshold:
				down_tapped = true
				print("DOWN TAP DETECTED")
		down_hold_frames = 0

	down_was_pressed = down_pressed

	# --- ECB ---
	var ecb = get_ecb_aabb()
	var ecb_center = ecb.position + (ecb.size / 2)
	var ecb_center_x = ecb.position.x + (ecb.size.x / 2)
	var ecb_left_x = ecb.position.x
	var ecb_right_x = ecb.position.x + ecb.size.x
	
	# Render debug mesh
	ecb_mesh_debug.global_position = ecb_center
	ecb_mesh_debug.scale = ecb.size
	ecb_mesh_debug.scale.z = 1
	
	
	# --- Input ---
	var input_dir = Vector3.ZERO
	input_dir.x = Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
	
	if grounded:
		if input_dir.x > 0:
			facing_direction = 1
		elif input_dir.x < 0:
			facing_direction = -1

	# --- Horizontal movement ---
	if state == PlayerState.NORMAL:
		current_velocity.x = input_dir.x * dash_speed
	#if current_velocity.x != 0:
	

	# --- Gravity ---
	if state == PlayerState.NORMAL:
		if down_tapped:
			if not grounded:
				if not fastfalling:
					if current_velocity.y < 0:
						if hitstun == 0:
							print("FASTFALL START")
							fastfalling = true	
	
		if not grounded:
			if fastfalling:
				current_velocity.y = fastfall_speed
				print("FASTFALL ACTIVE")
			else:
				current_velocity.y += gravity * delta
				if current_velocity.y < terminal_velocity:
					current_velocity.y = terminal_velocity

	# --- Jump ---
	if Input.is_action_just_pressed("jump"):
		if grounded:
			current_velocity.y = jump_velocity
			grounded = false
			fastfalling = false
		elif double_jumps_remaining > 0:
			current_velocity.y = jump_velocity  # Can customize per character later
			fastfalling = false
			double_jumps_remaining -= 1
		if state == PlayerState.LEDGE_HANG:
			current_velocity.y = jump_velocity
			fastfalling = false
			double_jumps_remaining = max_double_jumps

	# --- Apply movement manually ---
	global_position += current_velocity * delta
	
	var space_state = get_world_3d().direct_space_state
	
	# --- Ceiling Collision ---
	
	var ceiling_ray_lift := 0.02

	var ray_origins_top = [
		Vector3(ecb_left_x, prev_ecb_top_pos.y - ceiling_ray_lift, 0),
		Vector3(ecb_center_x, prev_ecb_top_pos.y - ceiling_ray_lift, 0),
		Vector3(ecb_right_x, prev_ecb_top_pos.y - ceiling_ray_lift, 0)
	]
	
	# --- Ceiling collision ---
	if current_velocity.y > 0:
		for origin in ray_origins_top:
			var ray_start = origin
			var ray_length = max(
				ceiling_ray_lift,
				current_velocity.y * delta
			)
			var ray_end = origin + Vector3.UP * ray_length

			var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
			var result = space_state.intersect_ray(query)

			if result:
				if result.collider.is_in_group("platforms"):
					var platform = result.collider
					
					if platform.is_solid:
						if result.normal.y < -0.7:
							var snap_offset = result.position.y - ecb_top.global_position.y
							global_position.y += snap_offset

							current_velocity.y = 0
							break
	
	# --- Wall Collision ---
	if current_velocity.x != 0:
		var direction = sign(current_velocity.x)
		var ray_length = abs(current_velocity.x * delta) + 0.05
		
		# Wall Ray Calculcations
		var ecb_top_y = ecb.position.y + ecb.size.y
		var ecb_bottom_y = ecb.position.y
		var ecb_center_y = ecb.position.y + (ecb.size.y / 2)
		var wall_ray_inset := 0.02
	
		var wall_ray_origins = []
			
		if direction < 0:
			# Left Side Rays
			wall_ray_origins = [
				Vector3(ecb_left_x + wall_ray_inset, ecb_bottom_y, 0),
				Vector3(ecb_left_x + wall_ray_inset, ecb_center_y, 0),
				Vector3(ecb_left_x + wall_ray_inset, ecb_top_y, 0),
			]
		else:
			wall_ray_origins = [
			# Right Side Rays
				Vector3(ecb_right_x - wall_ray_inset, ecb_bottom_y, 0),
				Vector3(ecb_right_x - wall_ray_inset, ecb_center_y, 0),
				Vector3(ecb_right_x - wall_ray_inset, ecb_top_y, 0)
			]
		
		print(ecb.size)
		print("ECB Global Position Y (frame start): ", ecb_bottom.global_position.y)

			
		for origin in wall_ray_origins:
			# ONLY cast rays on the moving side
			#if direction < 0 and origin.x != ecb_left_x:
				#continue
			#if direction > 0 and origin.x != ecb_right_x:
				#continue
			
			var ray_start = origin
			var ray_end = origin + Vector3(direction * ray_length, 0, 0)
			
			var query = PhysicsRayQueryParameters3D.create(ray_start, ray_end)
			var result = space_state.intersect_ray(query)
			
			if result and result.collider.is_in_group("platforms"):
				if abs(result.normal.x) > 0.7:
					
					var platform = result.collider
					
					if platform.is_solid:
						if direction > 0:
							var snap_offset = result.position.x - ecb_right.global_position.x
							global_position.x += snap_offset
						else:
							var snap_offset = result.position.x - ecb_left.global_position.x
							global_position.x += snap_offset
						current_velocity.x = 0
						break

	# --- Ground check raycast ---
	var groundsnap_ray_start = ecb_bottom.global_position
#	var groundsnap_ray_end = groundsnap_ray_start + Vector3.DOWN * groundsnap_distance
	var groundsnap_query = PhysicsRayQueryParameters3D.create(
			prev_ecb_bottom_pos,
			groundsnap_ray_start + Vector3.DOWN * 0.1
		)
	var hit_results: Array = []
	
	# Make a bunch of origins for groundsnap rays
	var ground_ray_lift = 0.02
	
	var ray_origins = [
		Vector3(ecb_left_x, ecb_bottom.global_position.y + ground_ray_lift, 0),
		Vector3(ecb_center_x, ecb_bottom.global_position.y + ground_ray_lift, 0),
		Vector3(ecb_right_x, ecb_bottom.global_position.y + ground_ray_lift, 0)	
	]
	
	for origin in ray_origins:
		var ray_start = origin
		var ray_length = max(groundsnap_distance + ground_ray_lift, - current_velocity.y * delta)
		var ray_end = origin + Vector3.DOWN * ray_length
		var groundsnap_array_query = PhysicsRayQueryParameters3D.create(
			ray_start,
			ray_end
		)
		
		var result = space_state.intersect_ray(groundsnap_array_query)
		if result:
			if result.collider.is_in_group("platforms"):

				var platform = result.collider

				if result.normal.y > 0.7:

					# Ignore non-solid platforms while holding down
					if Input.is_action_pressed("move_down") and not platform.is_solid:
						continue

					hit_results.append(result)

	var ground_detection_result = space_state.intersect_ray(groundsnap_query)
	
	# --- What to do when grounded ---
	
	grounded = false
	if hit_results.size() > 0:
		# Snap to highest ground level detected
		var highest_y = hit_results[0].position.y
		for r in hit_results:
			if r.position.y > highest_y:
				highest_y = r.position.y
		
		var snap_offset = highest_y - ecb_bottom.global_position.y
		# Snap only if moving downwards or not at all
		if current_velocity.y <= 0:
			global_position.y += snap_offset
			current_velocity.y = 0
			grounded = true
			double_jumps_remaining = max_double_jumps
			fastfalling = false
	
	# --- Ledge Grab ---
	check_for_ledge_grab()
	
	# --- Lock Z axis ---
	global_position.z = 0
	
	prev_ecb_bottom_pos = ecb_bottom.global_position
	prev_ecb_top_pos = ecb_top.global_position

	print("--- Frame end: ", ecb_bottom.global_position.y , "---")
	print("Grounded: ", grounded)
	print("Facing: ", facing_direction)
	#print("Ground Detection Result: ", ground_detection_result)
