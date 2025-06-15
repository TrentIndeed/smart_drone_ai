extends CharacterBody3D
class_name Target

# Target - Evasive entity that tries to escape from the drone

signal caught

@export var max_speed: float = 2.0  # units/second (scaled for 3D)
@export var evasion_strength: float = 1.0
@export var randomness: float = 0.3

var trail_points: Array[Vector3] = []
var max_trail_length: int = 15
var last_drone_position: Vector3
var panic_mode: bool = false
var panic_timer: float = 0.0
var movement_direction: Vector3 = Vector3.ZERO
var direction_change_timer: float = 0.0
var stuck_timer: float = 0.0
var last_position: Vector3 = Vector3.ZERO

func _ready():
	print("Target initialized at position: ", position)
	last_drone_position = position
	# Initialize with a random movement direction
	movement_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	direction_change_timer = randf_range(1.0, 3.0)
	
	# Start with some initial velocity to ensure movement
	velocity = movement_direction * max_speed * 0.5
	last_position = position

func _check_if_stuck(delta: float):
	"""Check if target is stuck and force direction change if needed"""
	var distance_moved = position.distance_to(last_position)
	
	if distance_moved < 0.02:  # Barely moved (reduced threshold)
		stuck_timer += delta
		if stuck_timer > 1.0:  # Stuck for 1 second (reduced time)
			print("Target stuck at: ", position, " - forcing new direction")
			# Force a completely new random direction
			movement_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			velocity = movement_direction * max_speed
			stuck_timer = 0.0
			direction_change_timer = 1.5  # Change direction again soon if still stuck
	else:
		stuck_timer = 0.0  # Reset if moving
	
	last_position = position

func _physics_process(delta):
	_check_if_stuck(delta)
	_update_trail()
	_update_panic_mode(delta)
	_update_autonomous_movement(delta)

func _update_trail():
	"""Update movement trail for visualization"""
	# Only update trail every few frames to improve performance
	if Engine.get_process_frames() % 8 != 0:
		return
		
	trail_points.append(position)
	if trail_points.size() > max_trail_length:
		trail_points.pop_front()
	
	# Simple trail - just store points, don't create expensive 3D objects every frame

func _update_panic_mode(delta: float):
	"""Update panic mode based on drone proximity"""
	var drone = get_tree().get_first_node_in_group("drone")
	if drone:
		var distance_to_drone = position.distance_to(drone.position)
		
		# Enter panic mode if drone is close (fixed distance for 3D world)
		if distance_to_drone < 2.0:  # 2 world units instead of 150
			panic_mode = true
			panic_timer = 2.0  # Stay in panic for 2 seconds
		elif panic_timer <= 0:
			panic_mode = false
	
	if panic_timer > 0:
		panic_timer -= delta
	
	# Update visual feedback
	var mesh_instance = $MeshInstance3D
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		if panic_mode:
			material.albedo_color = Color(1, 0.1, 0.1, 1)  # Bright red when panicked
			material.emission = Color(0.5, 0.05, 0.05, 1)
		else:
			material.albedo_color = Color(1, 0.3, 0.2, 1)  # Normal orange-red
			material.emission = Color(0.3, 0.1, 0.05, 1)

func _update_autonomous_movement(delta: float):
	"""Update autonomous movement when not being controlled externally"""
	# Change direction periodically or if stuck
	direction_change_timer -= delta
	var is_stuck = velocity.length() < 0.1  # Check if barely moving
	
	if direction_change_timer <= 0.0 or is_stuck:
		# Choose a direction that moves away from boundaries
		var new_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
		
		# Bias away from boundaries if near them (but allow more map usage)
		var min_boundary = -4.0
		var max_boundary = 3.2
		var boundary_bias = Vector3.ZERO
		var boundary_threshold = 0.3  # Only bias when very close to boundary
		
		if position.x > max_boundary - boundary_threshold:  # Near right boundary
			boundary_bias.x = -0.5
		elif position.x < min_boundary + boundary_threshold:  # Near left boundary
			boundary_bias.x = 0.5
			
		if position.z > max_boundary - boundary_threshold:  # Near far boundary
			boundary_bias.z = -0.5
		elif position.z < min_boundary + boundary_threshold:  # Near near boundary
			boundary_bias.z = 0.5
		
		# Combine random direction with boundary bias
		new_direction = (new_direction + boundary_bias * 2.0).normalized()
		movement_direction = new_direction
		
		direction_change_timer = randf_range(1.5, 3.0)
		if is_stuck:
			direction_change_timer = randf_range(0.5, 1.0)  # Change direction faster if stuck
	
	# Always apply base movement (target should always be moving)
	velocity = movement_direction * (max_speed * 0.7)  # Always moving at 70% speed
	
	# Avoid boundaries
	_avoid_boundaries()
	
	# Move with physics
	move_and_slide()
	
	# Handle collisions
	if get_slide_collision_count() > 0:
		_handle_obstacle_collision()

func move_evasively(evasion_direction: Vector3, delta: float):
	"""Move evasively based on drone position"""
	var current_speed = max_speed
	
	# Speed boost in panic mode
	if panic_mode:
		current_speed *= 1.5  # Increased speed boost
	
	# Add randomness to movement (keep on XZ plane)
	var random_offset = Vector3(
		randf_range(-randomness, randomness),
		0,
		randf_range(-randomness, randomness)
	)
	
	var final_direction = (evasion_direction + random_offset).normalized()
	# Keep movement on XZ plane
	final_direction.y = 0
	
	# Override autonomous movement when evading
	velocity = final_direction * current_speed
	movement_direction = final_direction  # Update movement direction
	
	# Keep target at ground level
	position.y = 0.0
	
	# Apply boundary checking to avoid walls
	_avoid_boundaries()
	
	# Move with collision detection
	move_and_slide()
	
	# Check for obstacles and adjust
	if get_slide_collision_count() > 0:
		_handle_obstacle_collision()

func _avoid_boundaries():
	"""Avoid world boundaries"""
	# Actual map boundaries based on 10x10 grid with 0.8 cell size
	# Grid coordinates 0-9 become world coordinates -4.0 to +3.2
	var min_boundary = -4.0  # Left/near edge
	var max_boundary = 3.2   # Right/far edge  
	var margin = 0.15  # Slightly larger margin to prevent corner sticking
	
	# Check if we're in a corner (near multiple boundaries simultaneously)
	var near_x_max = position.x >= max_boundary - margin
	var near_x_min = position.x <= min_boundary + margin
	var near_z_max = position.z >= max_boundary - margin
	var near_z_min = position.z <= min_boundary + margin
	
	var in_corner = (near_x_max or near_x_min) and (near_z_max or near_z_min)
	
	if in_corner:
		# Corner escape - move diagonally toward center
		print("Target in corner at: ", position, " - escaping toward center")
		var escape_direction = Vector3.ZERO
		
		# Move toward center from any corner
		if position.x > 0:
			escape_direction.x = -1.0
		else:
			escape_direction.x = 1.0
			
		if position.z > 0:
			escape_direction.z = -1.0
		else:
			escape_direction.z = 1.0
		
		# Force strong movement toward center
		movement_direction = escape_direction.normalized()
		velocity = movement_direction * max_speed * 1.3  # Extra speed to escape
		direction_change_timer = 1.5  # Don't change direction for a while
		
		# Move away from corner immediately
		position = Vector3(
			clamp(position.x, min_boundary + margin * 2, max_boundary - margin * 2),
			position.y,
			clamp(position.z, min_boundary + margin * 2, max_boundary - margin * 2)
		)
		return
	
	# Regular boundary handling (not in corner)
	var hit_boundary = false
	var bounce_direction = movement_direction
	
	# X boundary handling
	if position.x <= min_boundary + margin:
		bounce_direction.x = abs(bounce_direction.x) + 0.3  # Strong bounce right
		hit_boundary = true
		position.x = min_boundary + margin
	elif position.x >= max_boundary - margin:
		bounce_direction.x = -abs(bounce_direction.x) - 0.3  # Strong bounce left
		hit_boundary = true
		position.x = max_boundary - margin
	
	# Z boundary handling  
	if position.z <= min_boundary + margin:
		bounce_direction.z = abs(bounce_direction.z) + 0.3  # Strong bounce forward
		hit_boundary = true
		position.z = min_boundary + margin
	elif position.z >= max_boundary - margin:
		bounce_direction.z = -abs(bounce_direction.z) - 0.3  # Strong bounce backward
		hit_boundary = true
		position.z = max_boundary - margin
	
	# If we hit a boundary, apply strong bounce
	if hit_boundary:
		movement_direction = bounce_direction.normalized()
		velocity = movement_direction * velocity.length()
		# Add randomness to prevent getting stuck in patterns
		var random_offset = Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		movement_direction = (movement_direction + random_offset).normalized()
		direction_change_timer = 1.0  # Force direction change soon
		print("Target bounced off boundary at: ", position)

func _handle_obstacle_collision():
	"""Handle collision with obstacles"""
	# Get collision normal and find alternative direction
	var collision = get_slide_collision(0)
	var collision_normal = collision.get_normal()
	
	# Calculate reflection direction on XZ plane
	var reflect_dir = velocity.bounce(collision_normal)
	reflect_dir.y = 0  # Keep on ground
	
	# Add some randomness to avoid getting stuck in loops
	var random_offset = Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
	velocity = (reflect_dir + random_offset).normalized() * velocity.length()
	
	# Update movement direction for autonomous movement
	movement_direction = velocity.normalized()

func reset_position(pos: Vector3):
	"""Reset target to starting position"""
	position = pos
	velocity = Vector3.ZERO
	panic_mode = false
	panic_timer = 0.0
	trail_points.clear()
	print("Target reset to position: ", pos)

func check_capture(drone_position: Vector3, capture_distance: float = 0.8):
	"""Check if target has been captured by drone"""
	var distance = position.distance_to(drone_position)
	if distance < capture_distance:
		print("Target captured! Distance was: ", distance)
		
		# Visual feedback - flash bright white
		var mesh_instance = $MeshInstance3D
		var material = mesh_instance.get_surface_override_material(0)
		if material:
			material.albedo_color = Color.WHITE
			material.emission = Color.WHITE
		
		# Stop movement
		velocity = Vector3.ZERO
		
		caught.emit()
		return true
	return false

func get_current_stats() -> Dictionary:
	"""Get current target statistics"""
	return {
		"position": position,
		"velocity": velocity,
		"speed": velocity.length(),
		"panic_mode": panic_mode,
		"panic_timer": panic_timer
	} 