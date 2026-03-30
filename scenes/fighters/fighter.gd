extends CharacterBody3D

# --- Exported movement values ---
@export var walk_speed: float = 6.0
@export var dash_speed: float = 10.0
@export var jump_velocity: float = 12.0 # default: 12.0
@export var gravity: float = -30.0
@export var fastfall_speed: float = -25.0 # How fast you fastfall
@export var terminal_velocity: float = -15.0
@export var max_double_jumps: int = 999  # Number of mid-air jumps allowed

# --- Ledge ---
var ledge_points: Array[Marker3D] = []

func collect_ledges(node):
	if node is Marker3D:
		if node.name.begins_with("Ledge"):
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
	# print_tree_pretty

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
	
	var _space_state = get_world_3d().direct_space_state
	
	# --- Ceiling Collision ---
	
	# --- What to do when grounded ---
	
	grounded = false
		# Snap only if moving downwards or not at all
	if current_velocity.y <= 0:
		current_velocity.y = 0
		grounded = true
		double_jumps_remaining = max_double_jumps
		fastfalling = false
	
	# --- Ledge Grab ---
	check_for_ledge_grab()
	
	# --- Lock Z axis ---
	global_position.z = 0
	
	print("Grounded: ", grounded)
	print("Facing: ", facing_direction)
	print("--- FRAME END ---")
