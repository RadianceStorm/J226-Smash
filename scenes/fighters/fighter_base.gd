class_name FighterBase
# For individual fighters, extend this class

extends CharacterBody3D

# --- Hitbox Sides ---
@onready var _collision_shape: CollisionShape3D = $HitboxRoot

func _get_hitbox_bounds() -> Dictionary:
	var shape := _collision_shape.shape as BoxShape3D
	var origin := _collision_shape.global_position
	return {
		"left":   origin.x - shape.size.x / 2.0,
		"right":  origin.x + shape.size.x / 2.0,
		"bottom": origin.y - shape.size.y / 2.0,
	}

# --- Exports ---
@export var stats: FighterStats

# --- State Machine ---
enum State {
	GROUNDED,    # On the ground, accepting normal input
	JUMPSQUAT,   # 3-frame pre-jump window
	AIRBORNE,    # In the air
	HITSTUN,     # Launched — limited input
	LEDGE_HANG,  # Hanging on a ledge
}

var state: State = State.AIRBORNE

signal state_changed(new_state: State)
signal landed
signal left_ground

# --- Physics State ---
var vel: Vector3 = Vector3.ZERO
var floor_normal: Vector3 = Vector3.UP
var grounded: bool = false
var facing: int = 1        # 1 = right, -1 = left. Only updates on ground.

# --- Aerial State ---
var double_jumps_remaining: int = 0
var fastfalling: bool = false

# --- Jumpsquat ---
var _jumpsquat_frames_remaining: int = 0
var _full_hop_intended: bool = false

# --- Hitstun ---
var hitstun_frames_remaining: int = 0
var hitstun_total_frames: int = 0
var _hitstun_elapsed: int = 0

# --- Input ---
var _jump_buffer: int = 0
const JUMP_BUFFER_MAX := 6

var _down_hold_frames: int = 0
var _down_was_pressed: bool = false
var _down_tapped: bool = false
const DOWN_TAP_THRESHOLD := 12


# --- Balloon Knockback Lookup ---
# Community-verified raw->effective hitstun mapping above 32 frames.
# No closed-form formula exists; intermediate values are lerped.
const _BALLOON_TABLE: Array[Vector2] = [
	Vector2(32,  32),
	Vector2(36,  33),
	Vector2(45,  37),
	Vector2(58,  41),
	Vector2(72,  46),
	Vector2(90,  52),
	Vector2(120, 60),
]

var _soft_platforms: Array = []

func _ready() -> void:
	double_jumps_remaining = stats.max_double_jumps
	floor_stop_on_slope    = true
	floor_max_angle        = deg_to_rad(46)
	add_to_group("fighter")
	call_deferred("_collect_soft_platforms")

func _collect_soft_platforms() -> void:
	_soft_platforms = get_tree().get_nodes_in_group("soft_platforms")

# --- Main Loop ---
func _physics_process(delta: float) -> void:
	_tick_input()
	_tick_state(delta)
	_apply_move()
	_debug_print()

# --- Input ---
func _tick_input() -> void:
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_MAX
	elif _jump_buffer > 0:
		_jump_buffer -= 1

	_down_tapped = false
	var down_pressed := Input.is_action_pressed("move_down")
	if down_pressed:
		_down_hold_frames += 1
	else:
		if _down_was_pressed and _down_hold_frames <= DOWN_TAP_THRESHOLD:
			_down_tapped = true
		_down_hold_frames = 0
	_down_was_pressed = down_pressed

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

	# Facing only updates on the ground
	if input_x > 0.0:
		facing = 1
	elif input_x < 0.0:
		facing = -1

	if input_x != 0.0:
		vel.x = input_x * stats.dash_speed
	else:
		vel.x = move_toward(vel.x, 0.0, stats.dash_speed * stats.ground_friction)

	vel.y = 0.0

	if _jump_buffer > 0:
		_jump_buffer = 0
		_begin_jumpsquat()

# --- State: JUMPSQUAT ---
func _state_jumpsquat(_delta: float) -> void:
	vel.x = move_toward(vel.x, 0.0, stats.dash_speed * stats.ground_friction)
	vel.y = 0.0

	# Releasing jump during jumpsquat commits to short hop
	if not Input.is_action_pressed("jump"):
		_full_hop_intended = false

	_jumpsquat_frames_remaining -= 1
	if _jumpsquat_frames_remaining <= 0:
		_launch_jump()

# --- State: AIRBORNE ---
func _state_airborne(delta: float) -> void:
	var input_x := _get_input_x()

	# Air movement: accelerate toward target, not instant
	# Facing does NOT update here — only updates on ground
	var target_x := input_x * stats.air_speed
	vel.x = move_toward(vel.x, target_x, stats.air_speed * stats.air_acceleration)

	# Fastfall
	if _down_tapped and not fastfalling and vel.y <= 0.0:
		fastfalling = true
		print("[FASTFALL] Started")

	# Gravity
	if fastfalling:
		vel.y = -stats.fast_fall_speed
	else:
		vel.y -= stats.gravity * delta
		vel.y  = maxf(vel.y, -stats.fall_speed)

	# Double jump
	if _jump_buffer > 0 and double_jumps_remaining > 0:
		_jump_buffer           = 0
		double_jumps_remaining -= 1
		vel.y                  = stats.double_jump_velocity
		fastfalling            = false
		print("[JUMP] Double jump used. Remaining: ", double_jumps_remaining)

# --- State: HITSTUN ---
func _state_hitstun(delta: float) -> void:
	_hitstun_elapsed         += 1
	hitstun_frames_remaining -= 1

	# Knockback decay
	vel.x *= (1.0 - stats.kb_decay)

	# Gravity during tumble
	vel.y -= stats.gravity * delta
	vel.y  = maxf(vel.y, -stats.fall_speed)

	# Cancel windows (Ultimate values)
	if _hitstun_elapsed >= 40 and Input.is_action_just_pressed("airdodge"):
		print("[HITSTUN] Cancelled via airdodge at frame ", _hitstun_elapsed)
		_set_state(State.AIRBORNE)
		return
	if _hitstun_elapsed >= 45 and Input.is_action_just_pressed("jump"):
		vel.y                  = stats.double_jump_velocity
		double_jumps_remaining -= 1
		print("[HITSTUN] Cancelled via aerial at frame ", _hitstun_elapsed)
		_set_state(State.AIRBORNE)
		return

	if hitstun_frames_remaining <= 0:
		print("[HITSTUN] Expired after ", _hitstun_elapsed, " frames")
		_set_state(State.AIRBORNE)

# --- State: LEDGE_HANG ---
func _state_ledge_hang(_delta: float) -> void:
	vel = Vector3.ZERO

	if _jump_buffer > 0:
		_jump_buffer           = 0
		vel.y                  = stats.jump_velocity
		double_jumps_remaining = stats.max_double_jumps
		print("[LEDGE] Jumped off ledge")
		_set_state(State.AIRBORNE)

# --- Jump Helpers ---
func _begin_jumpsquat() -> void:
	_full_hop_intended          = true
	_jumpsquat_frames_remaining = stats.jumpsquat_frames
	print("[JUMP] Jumpsquat started")
	_set_state(State.JUMPSQUAT)

func _launch_jump() -> void:
	vel.y                  = stats.jump_velocity if _full_hop_intended else stats.short_hop_velocity
	fastfalling            = false
	double_jumps_remaining = stats.max_double_jumps
	print("[JUMP] Launched — full hop: ", _full_hop_intended, "  vel.y: ", vel.y)
	_set_state(State.AIRBORNE)

# --- Movement Resolution ---
func _apply_move() -> void:
	var was_grounded := grounded
	
	_update_soft_platform_mask()

	floor_snap_length = 0.15 if (state == State.GROUNDED or state == State.JUMPSQUAT) else 0.0
	velocity = vel
	move_and_slide()
	vel = velocity

	grounded     = is_on_floor()
	floor_normal = get_floor_normal() if grounded else Vector3.UP
	global_position.z = 0.0

	if grounded and not was_grounded:
		_on_land()
	elif not grounded and was_grounded and state != State.JUMPSQUAT:
		left_ground.emit()
		print("[GROUND] Left ground")
		_set_state(State.AIRBORNE)
		
	_update_soft_platform_mask()

func _update_soft_platform_mask() -> void:
	var holding_down := Input.is_action_pressed("move_down")
	var bounds := _get_hitbox_bounds()

	var should_collide := true
	if holding_down:
		should_collide = false
	else:
		for platform in _soft_platforms:
			var p_top:   float = platform.top_y
			var p_left:  float = platform.left_x
			var p_right: float = platform.right_x
			if bounds.bottom < p_top:
				should_collide = false
				floor_snap_length = 0.0
				break
			if bounds.left > p_right:
				should_collide = false
				break
			if bounds.right < p_left:
				should_collide = false
				break

	set_collision_mask_value(2, should_collide)


func _on_land() -> void:
	fastfalling              = false
	double_jumps_remaining   = stats.max_double_jumps
	hitstun_frames_remaining = 0
	print("[GROUND] Landed")
	landed.emit()

	if state == State.AIRBORNE or state == State.HITSTUN:
		_set_state(State.GROUNDED)

# --- Combat: Receiving a Hit ---
# Called externally by the hitbox resolution system.
# percent  : target's current damage %
# damage   : raw move damage (used in kb formula)
# bkb      : base knockback
# kbg      : knockback growth
# angle_deg: launch angle in degrees (0=right, 90=up)
# _hitlag  : freeze frames (handled by calling system — TODO)
func receive_hit(percent: float, damage: float, bkb: float, kbg: float, angle_deg: float, _hitlag: int) -> void:
	var kb      := _calc_knockback(percent, damage, bkb, kbg)
	var hitstun := _calc_hitstun(kb)
	var angle   := deg_to_rad(angle_deg)

	vel = Vector3(cos(angle), sin(angle), 0.0) * (kb * 0.03)

	hitstun_total_frames     = hitstun
	hitstun_frames_remaining = hitstun
	_hitstun_elapsed         = 0
	fastfalling              = false

	print("[HIT] KB: ", kb, "  Hitstun: ", hitstun, "  Angle: ", angle_deg)
	_set_state(State.HITSTUN)

# --- Knockback Formula (Ultimate) ---
func _calc_knockback(percent: float, damage: float, bkb: float, kbg: float) -> float:
	var scaled := ((damage / 10.0) + (damage * percent / 20.0)) * (200.0 / (stats.weight + 100.0)) * 1.4
	return (scaled + 18.0) * (kbg / 100.0) + bkb

# --- Hitstun + Balloon Knockback ---
func _calc_hitstun(knockback: float) -> int:
	var raw := int(knockback * stats.hitstun_multiplier)
	if raw <= 32:
		return raw
	return _balloon_lookup(raw)

func _balloon_lookup(raw: int) -> int:
	for i in range(_BALLOON_TABLE.size() - 1):
		var lo: Vector2 = _BALLOON_TABLE[i]
		var hi: Vector2 = _BALLOON_TABLE[i + 1]
		if raw <= hi.x:
			var t := (raw - lo.x) / (hi.x - lo.x)
			return int(lerp(lo.y, hi.y, t))
	var last: Vector2 = _BALLOON_TABLE[-1]
	return int(last.y + (raw - last.x) * 0.4)

# --- State Transition ---
func _set_state(new_state: State) -> void:
	if state == new_state:
		return
	print("[STATE] ", State.keys()[state], " -> ", State.keys()[new_state])
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
	print("[LEDGE] Grabbed ledge facing ", ledge_facing)
	_set_state(State.LEDGE_HANG)

# --- Debug (runs every physics frame) ---
func _debug_print() -> void:
	print("State: %-12s | Grounded: %-5s | Facing: %-2s | DJ: %s | vel: %s" % [
		State.keys()[state],
		str(grounded),
		str(facing),
		str(double_jumps_remaining),
		str(vel.round())
	])
	var bounds := _get_hitbox_bounds()
	print("Hitbox — left: %s | right: %s | bottom: %s" % [
		str(snappedf(bounds.left,   0.001)),
		str(snappedf(bounds.right,  0.001)),
		str(snappedf(bounds.bottom, 0.001)),
	])
