# fighter_base.gd
# Core fighter controller. Extend this class for individual characters.
#
# SCENE REQUIREMENTS:
#   - Node must be a CharacterBody3D (though move_and_slide is NOT used)
#   - Assign a FighterStats resource via the 'stats' export
#
# COLLISION LAYER CONVENTION (set in Project Settings -> Layer Names):
#   Layer 1 : solid_platforms   (always block movement)
#   Layer 2 : soft_platforms    (passthrough when holding down)
#   Layer 3 : fighters          (for hitbox overlap, not ECB)
#
# LEDGE POINTS:
#   Add nodes to the "ledges" group in the editor. Each ledge node must have
#   a facing_direction: int property (1 = right-facing ledge, -1 = left-facing).

class_name FighterBase
extends CharacterBody3D

#  --- Exports ---
@export var stats: FighterStats

# --- State Machine ---
enum State {
	GROUNDED,    # On the ground, accepting normal input
	JUMPSQUAT,   # 3-frame pre-jump window (Universal in Ultimate)
	AIRBORNE,    # In the air normally
	HITSTUN,     # Launched, tumbling — limited input
	LEDGE_HANG,  # Hanging on a ledge
}

var state: State = State.AIRBORNE

signal state_changed(new_state: State)
signal landed
signal left_ground

#  --- Physics State ---
var vel: Vector3 = Vector3.ZERO
var floor_normal: Vector3 = Vector3.UP
var grounded: bool = false
var facing: int = 1   # 1 = right, -1 = left

# --- Aerial State ---
var double_jumps_remaining: int = 0
var fastfalling: bool = false

# --- Jumpsquat ---
var _jumpsquat_frames_remaining: int = 0

# --- Hitstun ---
var hitstun_frames_remaining: int = 0
var hitstun_total_frames: int = 0
# How many frames have elapsed since hit — used for cancel windows
var _hitstun_elapsed: int = 0

# --- Input ---
var _jump_buffer: int = 0
const JUMP_BUFFER_MAX := 6

var _down_hold_frames: int = 0
var _down_was_pressed: bool = false
var _down_tapped: bool = false
const DOWN_TAP_THRESHOLD := 12

# --- ECB / Collision ---
var _ecb_cast: ShapeCast3D
const MAX_SLIDES := 4
const SOLID_LAYER := 1   # Must match Project Settings layer index
const SOFT_LAYER  := 2

#  Balloon Knockback Lookup
#  Community-verified mapping of raw hitstun -> effective hitstun
#  when raw > 32. Intermediate values are lerped.
#  Source: Ultimate frame data research (no closed-form formula exists).

const _BALLOON_TABLE: Array[Vector2] = [
	# x = raw hitstun,  y = effective hitstun
	Vector2(32, 32),
	Vector2(36, 33),
	Vector2(45, 37),
	Vector2(58, 41),
	Vector2(72, 46),
	Vector2(90, 52),
	Vector2(120, 60),
]

# --- Startup Functions ---
func _ready() -> void:
	_setup_ecb_cast()
	double_jumps_remaining = stats.max_double_jumps
	add_to_group("fighter")

func _setup_ecb_cast() -> void:
	_ecb_cast = ShapeCast3D.new()

	# Diamond ECB extruded slightly in Z to form a valid 3D convex hull
	var shape := ConvexPolygonShape3D.new()
	var hw := stats.ecb_half_width
	var hh := stats.ecb_half_height
	var z  := stats.ecb_z_extent
	shape.points = [
		Vector3( 0,  hh,  z), Vector3( 0,  hh, -z),  # Top
		Vector3( 0, -hh,  z), Vector3( 0, -hh, -z),  # Bottom
		Vector3(-hw,  0,  z), Vector3(-hw,  0, -z),  # Left
		Vector3( hw,  0,  z), Vector3( hw,  0, -z),  # Right
	]

	_ecb_cast.shape = shape
	_ecb_cast.collision_mask = (1 << (SOLID_LAYER - 1)) | (1 << (SOFT_LAYER - 1))
	_ecb_cast.exclude_parent = true
	_ecb_cast.max_results = 4  # Enough to catch corners
	add_child(_ecb_cast)

# --- Main Loop ---
func _physics_process(delta: float) -> void:
	_tick_input()
	_tick_state(delta)
	_apply_move(delta)
	global_position.z = 0.0   # Lock to 2.5D plane

# --- Input Processing ---
func _tick_input() -> void:
	# Jump buffer — keeps intent alive for JUMP_BUFFER_MAX frames
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_MAX
	elif _jump_buffer > 0:
		_jump_buffer -= 1

	# Down tap detection (for fastfall)
	_down_tapped = false
	var down_pressed := Input.is_action_pressed("move_down")
	if down_pressed:
		_down_hold_frames += 1
	else:
		if _down_was_pressed and _down_hold_frames <= DOWN_TAP_THRESHOLD:
			_down_tapped = true
		_down_hold_frames = 0
	_down_was_pressed = down_pressed

	# Soft platform passthrough: exclude soft layer when holding down
	if down_pressed:
		_ecb_cast.collision_mask = (1 << (SOLID_LAYER - 1))
	else:
		_ecb_cast.collision_mask = (1 << (SOLID_LAYER - 1)) | (1 << (SOFT_LAYER - 1))

# --- State Dispatcher ---
func _tick_state(delta: float) -> void:
	match state:
		State.GROUNDED:   _state_grounded(delta)
		State.JUMPSQUAT:  _state_jumpsquat(delta)
		State.AIRBORNE:   _state_airborne(delta)
		State.HITSTUN:    _state_hitstun(delta)
		State.LEDGE_HANG: _state_ledge_hang(delta)

# --- State: GROUNDED ---
func _state_grounded(_delta: float) -> void:
	var input_x := _get_input_x()

	if input_x != 0.0:
		facing = sign(input_x)
		vel.x = input_x * stats.dash_speed
	else:
		# Friction deceleration
		vel.x = move_toward(vel.x, 0.0, stats.dash_speed * stats.ground_friction)

	vel.y = 0.0

	if _jump_buffer > 0:
		_jump_buffer = 0
		_begin_jumpsquat()

# --- State: JUMPSQUAT ---
func _state_jumpsquat(_delta: float) -> void:
	# Minimal horizontal movement during jumpsquat (can still slide)
	vel.x = move_toward(vel.x, 0.0, stats.dash_speed * stats.ground_friction)
	vel.y = 0.0

	_jumpsquat_frames_remaining -= 1
	if _jumpsquat_frames_remaining <= 0:
		_launch_jump()

# --- State: AIRBORNE ---
func _state_airborne(delta: float) -> void:
	var input_x := _get_input_x()

	# Air movement: accelerate toward target speed, not instant
	var target_x := input_x * stats.air_speed
	vel.x = move_toward(vel.x, target_x, stats.air_speed * stats.air_acceleration)

	# Update facing in air (for directional aerials)
	if input_x != 0.0:
		facing = sign(input_x)

	# Fastfall
	if _down_tapped and not fastfalling and vel.y <= 0.0:
		fastfalling = true

	# Gravity
	if fastfalling:
		vel.y = -stats.fast_fall_speed
	else:
		vel.y -= stats.gravity * delta
		vel.y = maxf(vel.y, -stats.fall_speed)

	# Double jump (consumes buffer)
	if _jump_buffer > 0 and double_jumps_remaining > 0:
		_jump_buffer = 0
		double_jumps_remaining -= 1
		vel.y = stats.double_jump_velocity
		fastfalling = false

# --- State: HITSTUN ---
func _state_hitstun(delta: float) -> void:
	_hitstun_elapsed += 1
	hitstun_frames_remaining -= 1

	# Knockback velocity decay (Ultimate: ~0.051 per frame)
	vel.x *= (1.0 - stats.kb_decay)

	# Normal gravity still applies during tumble
	vel.y -= stats.gravity * delta
	vel.y = maxf(vel.y, -stats.fall_speed)

	# --- Hitstun cancel windows (Ultimate values) ---
	# Airdodge cancel: frame 40+
	if _hitstun_elapsed >= 40 and Input.is_action_just_pressed("airdodge"):
		_set_state(State.AIRBORNE)
		return
	# Aerial cancel: frame 45+
	if _hitstun_elapsed >= 45 and Input.is_action_just_pressed("jump"):
		vel.y = stats.double_jump_velocity
		double_jumps_remaining -= 1
		_set_state(State.AIRBORNE)
		return

	if hitstun_frames_remaining <= 0:
		_set_state(State.AIRBORNE)

# --- State: LEDGE_HANG ---
func _state_ledge_hang(_delta: float) -> void:
	vel = Vector3.ZERO

	if _jump_buffer > 0:
		_jump_buffer = 0
		vel.y = stats.jump_velocity
		double_jumps_remaining = stats.max_double_jumps
		_set_state(State.AIRBORNE)

# --- Jump Helpers ---
func _begin_jumpsquat() -> void:
	_jumpsquat_frames_remaining = stats.jumpsquat_frames
	_set_state(State.JUMPSQUAT)

func _launch_jump() -> void:
	# Short hop: jump released before jumpsquat ends
	if Input.is_action_pressed("jump"):
		vel.y = stats.jump_velocity
	else:
		vel.y = stats.short_hop_velocity

	fastfalling = false
	double_jumps_remaining = stats.max_double_jumps
	_set_state(State.AIRBORNE)

#  --- Combat: Receiving a Hit ---
#  Called externally by the hitbox resolution system.

## percent: the target's current damage percentage.
## damage:  raw damage of the move (used in kb formula).
## bkb:     base knockback.
## kbg:     knockback growth.
## angle:   launch angle in degrees (0 = right, 90 = straight up).
## hitlag:  freeze frames (pre-calculated by attacker's hitbox system).
func receive_hit(percent: float, damage: float, bkb: float, kbg: float, angle_deg: float, _hitlag: int) -> void:
	var kb      := _calc_knockback(percent, damage, bkb, kbg)
	var hitstun := _calc_hitstun(kb)
	var angle   := deg_to_rad(angle_deg)

	# Convert knockback to launch velocity (Ultimate: kb * 0.03)
	var launch_speed := kb * 0.03
	vel = Vector3(cos(angle), sin(angle), 0.0) * launch_speed

	hitstun_total_frames     = hitstun
	hitstun_frames_remaining = hitstun
	_hitstun_elapsed         = 0

	fastfalling = false
	_set_state(State.HITSTUN)
	# TODO: freeze for hitlag frames (pause _physics_process via a counter in the calling system)

# --- Knockback Formula ---
func _calc_knockback(percent: float, damage: float, bkb: float, kbg: float) -> float:
	# Ultimate formula (community-verified):
	# KB = (((dmg/10 + dmg*percent/20) * (200/(weight+100)) * 1.4) + 18) * (kbg/100) + bkb
	var scaled := ((damage / 10.0) + (damage * percent / 20.0)) * (200.0 / (stats.weight + 100.0)) * 1.4
	return (scaled + 18.0) * (kbg / 100.0) + bkb

# --- Hitstun + Balloon Knockback (Ultimate) ---
func _calc_hitstun(knockback: float) -> int:
	var raw := int(knockback * stats.hitstun_multiplier)

	if raw <= 32:
		return raw

	# Balloon knockback: compress hitstun above 32 frames via
	# animation speed-up. No closed-form exists; interpolate the lookup table.
	return _balloon_lookup(raw)

func _balloon_lookup(raw: int) -> int:
	# Walk the table and lerp between known points
	for i in range(_BALLOON_TABLE.size() - 1):
		var lo: Vector2 = _BALLOON_TABLE[i]
		var hi: Vector2 = _BALLOON_TABLE[i + 1]
		if raw <= hi.x:
			var t := (raw - lo.x) / (hi.x - lo.x)
			return int(lerp(lo.y, hi.y, t))

	# Beyond the last table entry: roughly half compression
	var last: Vector2 = _BALLOON_TABLE[-1]
	var excess := raw - last.x
	return int(last.y + excess * 0.4)

# --- Movement Resolution (ShapeCast3D sweep) ---
func _apply_move(delta: float) -> void:
	var remaining := vel * delta
	if state == State.GROUNDED or State.JUMPSQUAT:
		remaining.y -= 0.1
	var was_grounded := grounded
	grounded   = false
	floor_normal = Vector3.UP

	for _i in MAX_SLIDES:
		if remaining.is_zero_approx():
			break

		_ecb_cast.target_position = remaining
		_ecb_cast.force_shapecast_update()

		if not _ecb_cast.is_colliding():
			global_position += remaining
			break

		var safe     := _ecb_cast.get_closest_collision_safe_fraction()
		var normal   := _ecb_cast.get_collision_normal(0)
		var collider := _ecb_cast.get_collider(0)

		# Move to safe position (just before contact)
		global_position += remaining * safe
		remaining *= (1.0 - safe)

		# Categorise by surface normal
		if normal.y > 0.7:
			_on_floor_contact(normal, collider)
		elif normal.y < -0.7:
			# Ceiling: kill upward velocity
			vel.y = minf(vel.y, 0.0)

		# Slide remaining movement and velocity along the surface
		remaining = remaining.slide(normal)
		vel       = vel.slide(normal)

	# --- Landing / leaving ground transitions ---
	if grounded and not was_grounded:
		_on_land()
	elif not grounded and was_grounded and state != State.JUMPSQUAT:
		left_ground.emit()

func _on_floor_contact(normal: Vector3, _collider: Object) -> void:
	floor_normal = normal
	grounded     = true
	vel.y        = 0.0

func _on_land() -> void:
	fastfalling              = false
	double_jumps_remaining   = stats.max_double_jumps
	hitstun_frames_remaining = 0
	landed.emit()

	# Forced landing lag during hitstun (Ultimate rule):
	# remain in GROUNDED but could apply landing lag frames here.
	
	# Only transition if previously airborne; Don't interrupt JUMPSQUAT or GROUNDED
	if state == State.AIRBORNE or state == State.HITSTUN:
		_set_state(State.GROUNDED)

# --- State Transition Helper ---
func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	state = new_state
	state_changed.emit(new_state)

# --- Utility ---
func _get_input_x() -> float:
	return Input.get_action_strength("move_right") - Input.get_action_strength("move_left")

## Called by the ledge system when a grab is confirmed.
func handle_ledge_grab(ledge_position: Vector3, ledge_facing: int) -> void:
	global_position          = ledge_position
	facing                   = ledge_facing
	vel                      = Vector3.ZERO
	hitstun_frames_remaining = 0
	_set_state(State.LEDGE_HANG)
