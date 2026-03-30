# fighter_stats.gd
# Per-character data resource. Create a unique .tres file for each character.
# All values are tuned to match Ultimate's feel by default.
class_name FighterStats
extends Resource

# ─────────────────────────────────────────────────────────────
#  Ground Movement
# ─────────────────────────────────────────────────────────────
@export_group("Ground Movement")
@export var walk_speed: float = 6.0
@export var dash_speed: float = 10.0
## Fraction of speed lost per frame while decelerating on the ground.
@export var ground_friction: float = 0.15

# ─────────────────────────────────────────────────────────────
#  Air Movement
# ─────────────────────────────────────────────────────────────
@export_group("Air Movement")
@export var air_speed: float = 8.0
## Fraction of air_speed gained per frame (acceleration feel).
@export var air_acceleration: float = 0.12
@export var air_friction: float = 0.02

# ─────────────────────────────────────────────────────────────
#  Vertical / Jump
# ─────────────────────────────────────────────────────────────
@export_group("Vertical")
@export var jump_velocity: float = 12.0
@export var short_hop_velocity: float = 7.5   # Applied when jump is released during jumpsquat
@export var double_jump_velocity: float = 11.0
@export var max_double_jumps: int = 1
## In Ultimate all characters share a universal 3-frame jumpsquat.
## Expose here so it can be broken for specific characters if ever needed.
@export var jumpsquat_frames: int = 3

# ─────────────────────────────────────────────────────────────
#  Gravity / Fall
# ─────────────────────────────────────────────────────────────
@export_group("Gravity")
@export var gravity: float = 30.0
@export var fall_speed: float = 15.0       # Terminal velocity (normal fall)
@export var fast_fall_speed: float = 23.0  # Terminal velocity (fast fall)

# ─────────────────────────────────────────────────────────────
#  Combat Physics
# ─────────────────────────────────────────────────────────────
@export_group("Combat")
## Used directly in the Ultimate knockback formula.
@export var weight: float = 100.0
## Ultimate: 0.4x knockback -> hitstun frames.
@export var hitstun_multiplier: float = 0.4
## Knockback velocity decays by this fraction each frame during hitstun.
## Ultimate value: vel *= (1 - 0.051) per frame.
@export var kb_decay: float = 0.051

# ─────────────────────────────────────────────────────────────
#  ECB Shape
# ─────────────────────────────────────────────────────────────
@export_group("ECB Shape")
@export var ecb_half_width: float = 0.4
@export var ecb_half_height: float = 0.65
## Small Z extrusion so the diamond is a valid 3D convex hull for ShapeCast3D.
@export var ecb_z_extent: float = 0.05
