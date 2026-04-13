# Character data resource. Make a .tres file for each character.

class_name FighterStats
extends Resource

# --- Ground Movement ---
@export_group("Ground Movement")
## How fast the character walks when the walk toggle is enabled.
@export var walk_speed: float = 6.0
## How fast the character runs.
@export var dash_speed: float = 10.0
## How fast the character decelerates on the ground. This is a fraction that the ground speed is multiplied by.
@export var ground_friction: float = 0.15

# --- Air Movement ---
@export_group("Air Movement")
## The maximum air speed the character can achieve while moving normally (e.g. not being launched or using a special move)
@export var air_speed: float = 8.0
## The measure of horizontal movement control the character has while airborne.
@export var air_acceleration: float = 0.12
## How fast the character decelerates in the air. Works the same as ground friction.
@export var air_friction: float = 0.02

# --- Jumping ---
@export_group("Jumping")
## How high/fast the character jumps. Affected by gravity.
@export var jump_velocity: float = 12.0
## How high the character jumps when a short hop is inputted.
@export var short_hop_velocity: float = 7.5
## How high the character jumps when double jumping.
@export var double_jump_velocity: float = 11.0
## How many times the character can double jump before touching the ground again.
@export var max_double_jumps: int = 1
# In Ultimate all characters share a universal 3-frame jumpsquat
# But i'm just gonna leave it as a setting so fighters can change it easily
## How many frames before the character leaves the ground after inputting a jump.
@export var jumpsquat_frames: int = 3

# --- Gravity ---
@export_group("Gravity")
## How fast the character falls.
@export var gravity: float = 30.0
## Terminal velocity.
@export var fall_speed: float = 15.0
## Velocity set while fastfalling. This should be a positive number.
@export var fast_fall_speed: float = 23.0

# --- Combat ---
@export_group("Combat")
## How hard it is to launch the character. Higher values result in lower knockback received and higher survivability. Doesn't affect movement.
@export var weight: float = 100.0
