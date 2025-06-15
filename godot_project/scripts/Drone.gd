extends CharacterBody3D
class_name Drone

# Drone - AI-controlled hunter with physics-based movement

signal collision_detected(obstacle_position: Vector3)

@export var max_speed: float = 3.0  # units/second (scaled for 3D)
@export var acceleration: float = 6.0  # units/second²
@export var friction: float = 0.8

var target_position: Vector3
var emergency_mode: bool = false
var trail_points: Array[Vector3] = []
var max_trail_length: int = 20
var collision_cooldown: float = 0.0
var collision_cooldown_time: float = 0.3

func _ready():
	print("Drone initialized")
	target_position = position

func _physics_process(delta):
	# Update collision cooldown
	if collision_cooldown > 0:
		collision_cooldown -= delta
	
	_update_movement(delta)
	_update_trail()
	_update_visual_feedback()

func _update_movement(delta: float):
	"""Update drone movement towards target position"""
	# Keep movement on XZ plane (ground plane)
	var target_2d = Vector3(target_position.x, position.y, target_position.z)
	var direction = (target_2d - position).normalized()
	var distance = position.distance_to(target_2d)
	
	# Apply boundary checking to target position
	target_2d = _clamp_to_world_bounds(target_2d)
	direction = (target_2d - position).normalized()
	distance = position.distance_to(target_2d)
	
	# Calculate desired velocity
	var desired_velocity = Vector3.ZERO
	if distance > 0.05:  # Minimum distance threshold (scaled for 3D)
		var target_speed = max_speed
		if emergency_mode:
			target_speed *= 1.2  # 20% speed boost in emergency
		elif distance < 1.0:
			target_speed *= distance  # Slow down when close
		
		desired_velocity = direction * target_speed
	
	# Apply acceleration/deceleration
	velocity = velocity.move_toward(desired_velocity, acceleration * delta)
	
	# Apply friction when no input
	if desired_velocity.length() < 0.1:
		velocity *= friction
	
	# Keep drone at a fixed height
	position.y = 0.3
	
	# Apply boundary checking to drone position
	position = _clamp_to_world_bounds(position)
	
	# Move and handle collisions
	var was_on_floor = is_on_floor()
	move_and_slide()
	
	# Handle obstacle collisions by adjusting target position (with cooldown)
	if get_slide_collision_count() > 0 and collision_cooldown <= 0:
		var collision = get_slide_collision(0)
		collision_detected.emit(collision.get_position())
		
		# Find alternative path around obstacle
		var obstacle_normal = collision.get_normal()
		var avoidance_direction = Vector3(-obstacle_normal.z, 0, obstacle_normal.x)
		
		# Add some randomness to avoid loops
		var random_factor = Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		avoidance_direction += random_factor
		avoidance_direction = avoidance_direction.normalized()
		
		# Adjust target position to go around obstacle
		target_position = position + avoidance_direction * 1.5
		target_position = _clamp_to_world_bounds(target_position)
		
		# Set cooldown to prevent rapid bouncing
		collision_cooldown = collision_cooldown_time

func _clamp_to_world_bounds(pos: Vector3) -> Vector3:
	"""Clamp position to world boundaries"""
	# Actual map boundaries: 10x10 grid with 0.8 cell size = -4.0 to +3.2
	var min_boundary = -4.0
	var max_boundary = 3.2
	return Vector3(
		clamp(pos.x, min_boundary, max_boundary),
		pos.y,
		clamp(pos.z, min_boundary, max_boundary)
	)

func _update_trail():
	"""Update movement trail for visualization"""
	# Only update trail every few frames to improve performance
	if Engine.get_process_frames() % 5 != 0:
		return
		
	trail_points.append(position)
	if trail_points.size() > max_trail_length:
		trail_points.pop_front()
	
	# Simple trail - just store points, don't create expensive 3D objects every frame

func _update_visual_feedback():
	"""Update visual elements like target indicator"""
	var target_indicator = $TargetIndicator
	if target_position != Vector3.ZERO:
		target_indicator.visible = true
		target_indicator.look_at(target_position, Vector3.UP)
	else:
		target_indicator.visible = false
	
	# Change color based on emergency mode
	var mesh_instance = $MeshInstance3D
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		if emergency_mode:
			material.albedo_color = Color(1, 0.5, 0.2, 1)  # Orange for emergency
			material.emission = Color(0.3, 0.15, 0.05, 1)
		else:
			material.albedo_color = Color(0.2, 0.6, 1, 1)  # Blue for normal
			material.emission = Color(0.1, 0.3, 0.5, 1)

func set_target_position(pos: Vector3):
	"""Set new target position from AI"""
	target_position = pos
	print("Drone target set to: ", pos)

func set_emergency_mode(enabled: bool):
	"""Enable/disable emergency mode"""
	emergency_mode = enabled
	if enabled:
		print("Drone entering emergency mode")
	else:
		print("Drone exiting emergency mode")

func reset_position(pos: Vector3):
	"""Reset drone to starting position"""
	position = pos
	target_position = pos
	velocity = Vector3.ZERO
	emergency_mode = false
	trail_points.clear()
	print("Drone reset to position: ", pos)

func get_current_stats() -> Dictionary:
	"""Get current drone statistics"""
	return {
		"position": position,
		"velocity": velocity,
		"speed": velocity.length(),
		"target_position": target_position,
		"distance_to_target": position.distance_to(target_position),
		"emergency_mode": emergency_mode
	} 