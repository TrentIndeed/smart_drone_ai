extends CharacterBody3D
class_name Drone

# Drone - AI-controlled hunter with physics-based movement

signal collision_detected(obstacle_position: Vector3)
signal target_shot(target_position: Vector3)
signal shot_fired(from_position: Vector3, to_position: Vector3)

@export var max_speed: float = 5.0  # units/second - Realistic 2x2ft surveillance drone (scaled down)
@export var acceleration: float = 8.0  # units/second² - Drone has better acceleration
@export var friction: float = 0.8
@export var flight_height: float = 0.5  # Lower flight height for better gameplay

# Shooting system
@export var max_shooting_range: float = 1.0  # Maximum effective range for neutralization (20ft)
@export var optimal_shooting_range: float = 0.6  # Optimal range for best accuracy (12ft)
@export var shooting_cooldown_time: float = 1.0  # Seconds between shots
@export var aiming_time: float = 0.3  # Time needed to aim before shooting

var target_position: Vector3
var emergency_mode: bool = false
var emergency_timer: float = 0.0
var max_emergency_time: float = 10.0  # Auto-exit emergency mode after 10 seconds
var trail_points: Array[Vector3] = []
var max_trail_length: int = 20
var collision_cooldown: float = 0.0
var collision_cooldown_time: float = 1.0  # Increased cooldown to prevent collision spam
var just_reset: bool = false  # Prevent collision handling right after reset

# Shooting state
var shooting_cooldown: float = 0.0
var aiming_timer: float = 0.0
var is_aiming: bool = false
var current_target: Node3D = null
var last_shot_time: float = 0.0

func _ready():
	print("Drone initialized")
	target_position = position
	
	# Set up collision layers for drone
	collision_layer = 1  # Drone is on layer 1
	collision_mask = 2   # Only collide with obstacles on layer 2

func _physics_process(delta):
	# Update collision cooldown
	if collision_cooldown > 0:
		collision_cooldown -= delta
	
	# Update emergency timer and auto-exit emergency mode if stuck too long
	if emergency_mode:
		emergency_timer += delta
		if emergency_timer > max_emergency_time:
			print("Auto-exiting emergency mode after ", max_emergency_time, " seconds")
			set_emergency_mode(false)
			emergency_timer = 0.0
	
	# Clear just_reset flag after a short delay
	if just_reset:
		collision_cooldown = collision_cooldown_time  # Prevent collisions immediately after reset
		just_reset = false
	
	# Update shooting cooldown
	if shooting_cooldown > 0:
		shooting_cooldown -= delta
	
	# Debug obstacle penetration less frequently and only when needed
	if Engine.get_process_frames() % 120 == 0 and collision_cooldown <= 0:
		_debug_nearby_obstacles()
	
	_update_movement(delta)
	_update_shooting_system(delta)
	_update_trail()
	_update_visual_feedback()

func _update_movement(delta: float):
	"""Update drone movement towards target position - drone can fly over obstacles"""
	# Safety check: If target position hasn't changed in a while, find target manually
	var target_node = get_tree().get_first_node_in_group("target")
	if target_node and (target_position.distance_to(target_node.position) > 2.0 or target_position == Vector3.ZERO):
		target_position = target_node.position  # Fix: Use Vector3, not Vector2
		if Engine.get_process_frames() % 120 == 0:  # Debug every 2 seconds
			print("Drone auto-correcting target position to: ", target_position)
	
	# Move to target position at flight height (can fly over obstacles)
	var target_3d = Vector3(target_position.x, flight_height, target_position.z)
	var direction = (target_3d - position).normalized()
	var distance = position.distance_to(target_3d)
	
	# Apply boundary checking to target position
	target_3d = _clamp_to_world_bounds(target_3d)
	direction = (target_3d - position).normalized()
	distance = position.distance_to(target_3d)
	
	# Calculate desired velocity
	var desired_velocity = Vector3.ZERO
	if distance > 0.05:  # Minimum distance threshold (scaled for 3D)
		var target_speed = max_speed
		if emergency_mode:
			target_speed *= 1.5  # Bigger speed boost in emergency (drone advantage)
		elif distance < 1.0:
			target_speed *= distance  # Slow down when close
		
		desired_velocity = direction * target_speed
	else:
		# Debug when drone is very close to target or has no target
		if Engine.get_process_frames() % 60 == 0:  # Debug every second
			print("Drone near target or no movement - Distance: ", distance, " Target: ", target_position)
	
	# Apply acceleration/deceleration
	velocity = velocity.move_toward(desired_velocity, acceleration * delta)
	
	# Apply friction when no input
	if desired_velocity.length() < 0.1:
		velocity *= friction
	
	# Apply gravity to bring drone back to flight height
	if position.y > flight_height:
		velocity.y -= 3.0 * delta  # Gentle gravity to return to flight height
	elif position.y < flight_height:
		velocity.y += 2.0 * delta  # Push up if below flight height
	
	# Maintain flight height - but allow temporary elevation for obstacle clearance
	if velocity.y <= 0 and position.y > flight_height:
		# Drone is falling back to normal flight height
		position.y = lerp(position.y, flight_height, 2.0 * delta)
	elif position.y < flight_height:
		# Drone is below normal flight height - correct it
		position.y = flight_height
	
	# Disable obstacle avoidance - let drone rely on physics collision only
	# _avoid_obstacles()
	
	# Apply boundary checking to drone position
	position = _clamp_to_world_bounds(position)
	
	# Move with collision detection - only collide with obstacles at flight height
	move_and_slide()
	
	# Handle collisions more reliably - improved logic
	if get_slide_collision_count() > 0:
		var collision = get_slide_collision(0)
		var collider = collision.get_collider()
		var collision_point = collision.get_position()
		var collision_normal = collision.get_normal()
		
		# Process collision if cooldown allows and it's a valid obstacle collision
		var is_valid_collision = false
		
		# Check if collider is an obstacle
		if collider and (collider.is_in_group("obstacles") or 
						collider.name.begins_with("tree_") or 
						collider.name.begins_with("rock_") or
						collider.collision_layer == 2):
			is_valid_collision = true
		
		# Only apply custom collision handling if needed and cooldown allows
		if is_valid_collision and collision_cooldown <= 0:
			collision_detected.emit(collision_point)
			print("Processing collision with obstacle: ", collider.name if collider else "unknown")
			print("  Collision normal: ", collision_normal)
			print("  Collision point: ", collision_point)
			print("  Drone position: ", position)
			
			# Smart collision response based on collision normal
			var bounce_direction = collision_normal
			
			# Check if this is a top collision (hitting the top of an obstacle)
			var is_top_collision = collision_normal.y > 0.7  # Normal pointing mostly upward
			var is_side_collision = abs(collision_normal.y) < 0.3  # Normal mostly horizontal
			
			if is_top_collision:
				# Collision with top of obstacle - push drone up and slightly back
				print("  Top collision detected - pushing drone up")
				bounce_direction = Vector3(collision_normal.x * 0.5, 1.0, collision_normal.z * 0.5).normalized()
				position += bounce_direction * 0.5  # Push up and away
				velocity.y = max(velocity.y, 2.0)  # Add upward velocity
			elif is_side_collision:
				# Side collision - push horizontally but maintain flight height
				print("  Side collision detected - pushing drone horizontally")
				bounce_direction.y = 0  # Keep horizontal for side collisions
				position += bounce_direction * 0.4
				position.y = flight_height  # Maintain flight height
			else:
				# General collision - use normal but bias toward horizontal
				print("  General collision detected")
				bounce_direction = Vector3(collision_normal.x, collision_normal.y * 0.3, collision_normal.z).normalized()
				position += bounce_direction * 0.3
			
			# Velocity reflection based on collision type
			if velocity.dot(collision_normal) < 0:  # Moving into the obstacle
				if is_top_collision:
					# For top collisions, reduce horizontal velocity and add upward bounce
					velocity = Vector3(velocity.x * 0.5, abs(velocity.y) + 1.5, velocity.z * 0.5)
				else:
					# For side collisions, reflect horizontally
					velocity = velocity.reflect(collision_normal) * 0.7
					velocity += bounce_direction * 1.5
			
			# Set emergency mode if collision happens repeatedly
			if not emergency_mode:
				set_emergency_mode(true)
				print("Entering emergency mode due to collision")
			
			collision_cooldown = 0.5  # Longer cooldown after collision

func _update_shooting_system(delta: float):
	"""Update the drone's shooting and targeting system"""
	# Find the target
	if not current_target:
		current_target = get_tree().get_first_node_in_group("target")
		if current_target:
			print("Drone found target: ", current_target.name)
		else:
			if Engine.get_process_frames() % 120 == 0:  # Debug every 2 seconds
				print("Drone shooting system: No target found in group 'target'!")
			return
	
	if not current_target:
		return
	
	var distance_to_target = position.distance_to(current_target.position)
	
	# Debug Y position differences that might affect shooting
	var y_difference = abs(position.y - current_target.position.y)
	var horizontal_distance = Vector2(position.x, position.z).distance_to(Vector2(current_target.position.x, current_target.position.z))
	
	# More frequent debug output when target is anywhere close
	if distance_to_target <= max_shooting_range * 3 and Engine.get_process_frames() % 15 == 0:  # More frequent debug
		print("SHOOTING DEBUG - 3D Distance: ", distance_to_target, 
			  " | Horizontal distance: ", horizontal_distance,
			  " | Y difference: ", y_difference,
			  " | Max range: ", max_shooting_range,
			  " | In range: ", distance_to_target <= max_shooting_range,
			  " | Is aiming: ", is_aiming,
			  " | Aiming timer: ", aiming_timer,
			  " | Cooldown: ", shooting_cooldown,
			  " | Drone pos: ", position,
			  " | Target pos: ", current_target.position)
	
	# Check if target is in range
	if distance_to_target <= max_shooting_range:
		# Start aiming if not already aiming
		if not is_aiming:
			is_aiming = true
			aiming_timer = aiming_time
			print("*** Drone acquiring target at range: ", distance_to_target, " ***")
			print("    Drone at: ", position, " | Target at: ", current_target.position)
		
		# Count down aiming time
		if aiming_timer > 0:
			aiming_timer -= delta
			if Engine.get_process_frames() % 15 == 0:  # More frequent aiming progress
				print(">>> Aiming progress: ", (aiming_time - aiming_timer) / aiming_time * 100, "% (", aiming_timer, " remaining)")
		
		# Fire when aimed and cooldown is ready
		if aiming_timer <= 0 and shooting_cooldown <= 0:
			print("*** FIRING CONDITIONS MET! ***")
			_fire_at_target()
		else:
			if aiming_timer > 0:
				print("  Still aiming... (", aiming_timer, " seconds left)")
			if shooting_cooldown > 0:
				print("  Shooting cooldown active (", shooting_cooldown, " seconds left)")
	else:
		# Target out of range - stop aiming
		if is_aiming:
			is_aiming = false
			aiming_timer = 0
			print("Target out of range: ", distance_to_target, " > ", max_shooting_range)
			print("  Position difference: Drone(", position, ") vs Target(", current_target.position, ")")

func _fire_at_target():
	"""Fire at the current target"""
	if not current_target:
		return
	
	var target_pos = current_target.position
	var distance = position.distance_to(target_pos)
	
	# Calculate hit probability based on range
	var hit_chance = 1.0
	if distance > optimal_shooting_range:
		# Reduced accuracy at longer ranges
		hit_chance = 1.0 - (distance - optimal_shooting_range) / (max_shooting_range - optimal_shooting_range) * 0.3
	
	print("Drone firing at target! Range: ", distance, " Hit chance: ", hit_chance * 100, "%")
	
	# Emit visual shot effect
	shot_fired.emit(position, target_pos)
	
	# Check for hit
	if randf() <= hit_chance:
		print("TARGET NEUTRALIZED!")
		target_shot.emit(target_pos)
	else:
		print("Shot missed")
	
	# Reset shooting state
	shooting_cooldown = shooting_cooldown_time
	is_aiming = false
	aiming_timer = 0
	last_shot_time = Time.get_time_dict_from_system().get("second", 0)

func get_shooting_status() -> Dictionary:
	"""Get current shooting system status"""
	var target_distance = 999.0
	if current_target:
		target_distance = position.distance_to(current_target.position)
	
	return {
		"in_range": target_distance <= max_shooting_range,
		"optimal_range": target_distance <= optimal_shooting_range,
		"distance_to_target": target_distance,
		"is_aiming": is_aiming,
		"aiming_progress": 1.0 - (aiming_timer / aiming_time) if aiming_time > 0 else 1.0,
		"cooldown_remaining": shooting_cooldown,
		"ready_to_fire": shooting_cooldown <= 0 and aiming_timer <= 0 and target_distance <= max_shooting_range
	}

func _clamp_to_world_bounds(pos: Vector3) -> Vector3:
	"""Clamp position to world boundaries"""
	# Actual map boundaries: 10x10 grid with 0.8 cell size = -4.0 to +3.2
	var min_boundary = -4.0
	var max_boundary = 3.2
	return Vector3(
		clamp(pos.x, min_boundary, max_boundary),
		flight_height,  # Maintain flight height
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
		# Calculate direction to target
		var direction = (target_position - target_indicator.global_position).normalized()
		# Check if direction is not too close to being vertical (colinear with up vector)
		if abs(direction.dot(Vector3.UP)) < 0.99:
			target_indicator.look_at(target_position, Vector3.UP)
		else:
			# Use a different up vector when target is nearly vertical
			var alt_up = Vector3.RIGHT if abs(direction.dot(Vector3.RIGHT)) < 0.99 else Vector3.FORWARD
			target_indicator.look_at(target_position, alt_up)
	else:
		target_indicator.visible = false
	
	# Change color based on mode and shooting status
	# Find the mesh instance in the drone model
	var drone_model = $DroneModel
	if drone_model:
		# Try to find MeshInstance3D nodes in the model
		var mesh_instances = _find_mesh_instances(drone_model)
		for mesh_instance in mesh_instances:
			# Create or get material for visual feedback
			var material = mesh_instance.get_surface_override_material(0)
			if not material:
				# Create a new material based on the existing one if possible
				var base_material = mesh_instance.get_surface_override_material(0)
				if not base_material and mesh_instance.mesh:
					base_material = mesh_instance.mesh.get_surface_count() > 0
				material = StandardMaterial3D.new()
				if base_material and base_material is StandardMaterial3D:
					material.albedo_texture = base_material.albedo_texture
				mesh_instance.set_surface_override_material(0, material)
			
			if material is StandardMaterial3D:
				if is_aiming and current_target:
					# Red when aiming/acquiring target
					var aiming_intensity = 1.0 - (aiming_timer / aiming_time) if aiming_time > 0 else 1.0
					material.albedo_color = Color(1, 0.2, 0.2, 1)  # Red for targeting
					material.emission_enabled = true
					material.emission = Color(0.8 * aiming_intensity, 0.1, 0.1, 1)
				elif emergency_mode:
					material.albedo_color = Color(1, 0.5, 0.2, 1)  # Orange for emergency
					material.emission_enabled = true
					material.emission = Color(0.3, 0.15, 0.05, 1)
				else:
					material.albedo_color = Color(0.8, 0.9, 1, 1)  # Slightly blue tint for normal
					material.emission_enabled = true
					material.emission = Color(0.1, 0.2, 0.3, 1)

func _avoid_obstacles():
	"""Predict and avoid only tall obstacles at flight height"""
	# Only perform avoidance if we're actually moving
	if velocity.length() < 0.1:
		return
	
	var space_state = get_world_3d().direct_space_state
	var look_ahead_distance = 1.5  # Look ahead distance
	
	# Use current movement direction
	var movement_direction = velocity.normalized()
	movement_direction.y = 0  # Keep on flight level
	
	# Check only forward direction (simplified)
	var query = PhysicsRayQueryParameters3D.create(
		position,
		position + movement_direction * look_ahead_distance,
		2  # Only check collision layer 2 (obstacles)
	)
	var result = space_state.intersect_ray(query)
	
	if result:
		var collision_point = result.position
		var collider = result.get("collider")
		
		# Only avoid if collision point is at or above flight height (tall obstacle)
		if collision_point.y >= flight_height - 0.5 and collider:
			if collider.name.begins_with("tree_") or collider.name.begins_with("rock_") or collider.is_in_group("obstacles"):
				print("Avoiding tall obstacle: ", collider.name, " at height: ", collision_point.y)
				
				# Calculate avoidance direction (perpendicular to obstacle)
				var obstacle_direction = (collision_point - position).normalized()
				obstacle_direction.y = 0
				var avoid_direction = Vector3(obstacle_direction.z, 0, -obstacle_direction.x)
				
				# Apply moderate avoidance force
				velocity += avoid_direction * acceleration * 0.3
				velocity = velocity * 0.9  # Slight speed reduction
		else:
			# Ground level obstacle - drone can fly over it
			if collider:
				print("Flying over ground obstacle: ", collider.name, " at height: ", collision_point.y)

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes in the model"""
	var mesh_instances: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node)
	
	for child in node.get_children():
		mesh_instances.append_array(_find_mesh_instances(child))
	
	return mesh_instances

func set_target_position(pos: Vector3):
	"""Set new target position from AI"""
	target_position = pos
	print("Drone target set to: ", pos)

func set_emergency_mode(enabled: bool):
	"""Enable/disable emergency mode"""
	emergency_mode = enabled
	if enabled:
		emergency_timer = 0.0  # Reset timer when entering emergency mode
		print("Drone entering emergency mode")
	else:
		emergency_timer = 0.0  # Reset timer when exiting emergency mode
		print("Drone exiting emergency mode")

func reset_position(pos: Vector3):
	"""Reset drone to starting position"""
	position = pos
	target_position = pos
	velocity = Vector3.ZERO
	emergency_mode = false
	trail_points.clear()
	just_reset = true  # Flag to prevent immediate collision handling
	print("Drone reset to position: ", pos)

func get_current_stats() -> Dictionary:
	"""Get current drone statistics"""
	var shooting_stats = get_shooting_status()
	return {
		"position": position,
		"velocity": velocity,
		"speed": velocity.length(),
		"target_position": target_position,
		"distance_to_target": position.distance_to(target_position),
		"emergency_mode": emergency_mode,
		"shooting_range": shooting_stats.distance_to_target,
		"in_firing_range": shooting_stats.in_range,
		"is_aiming": shooting_stats.is_aiming,
		"ready_to_fire": shooting_stats.ready_to_fire
	}

func _debug_obstacle_detection():
	"""Debug function to help identify phantom obstacle detections"""
	if not emergency_mode:  # Only debug when not in emergency
		return
		
	print("=== DRONE OBSTACLE DEBUG ===")
	print("Drone position: ", position)
	print("Drone velocity: ", velocity)
	print("Collision layer: ", collision_layer, " Collision mask: ", collision_mask)
	
	# Check what objects are nearby
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 2.0  # Check within 2 units
	query.shape = shape
	query.transform.origin = position
	query.collision_mask = 0xFFFFFFFF  # Check all layers
	
	var results = space_state.intersect_shape(query)
	print("Nearby objects (within 2 units): ", results.size())
	
	for result in results:
		var collider = result.get("collider")
		if collider:
			var distance = position.distance_to(collider.global_position if collider.has_method("global_position") else Vector3.ZERO)
			print("  - ", collider.name, " (distance: ", distance, ", collision_layer: ", collider.collision_layer if collider.has_method("get") else "N/A", ")")
	
	print("=== END DEBUG ===")

func _debug_nearby_obstacles():
	"""Debug function to detect when drone is inside obstacles without collision"""
	var space_state = get_world_3d().direct_space_state
	
	# Check for overlapping objects
	var query = PhysicsShapeQueryParameters3D.new()
	var shape = SphereShape3D.new()
	shape.radius = 0.3  # Small radius around drone
	query.shape = shape
	query.transform.origin = position
	query.collision_mask = 0xFFFFFFFF  # Check all layers
	
	var results = space_state.intersect_shape(query)
	
	for result in results:
		var collider = result.get("collider")
		if collider:
			var is_obstacle = (collider.name.begins_with("tree_") or 
							  collider.name.begins_with("rock_") or 
							  collider.is_in_group("obstacles"))
			
			if is_obstacle:
				print("⚠️  DRONE INSIDE OBSTACLE: ", collider.name)
				print("   Distance from center: ", position.distance_to(collider.global_position if collider.has_method("get") else Vector3.ZERO))
				
				# Only try to fix if we haven't fixed this obstacle recently
				if collision_cooldown <= 0:
					print("   🔧 Ejecting drone from obstacle...")
					_eject_drone_from_obstacle(collider)

func _eject_drone_from_obstacle(obstacle_node: Node):
	"""Eject drone from inside an obstacle to a safe position"""
	if not obstacle_node:
		return
	
	print("Ejecting drone from obstacle: ", obstacle_node.name)
	
	# Get obstacle position
	var obstacle_pos = obstacle_node.global_position if obstacle_node.has_method("get") else Vector3.ZERO
	
	# Calculate direction away from obstacle
	var eject_direction = (position - obstacle_pos).normalized()
	
	# If we're exactly at the center, choose a random direction
	if eject_direction.length() < 0.1:
		eject_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	
	# Keep on XZ plane (maintain flight height)
	eject_direction.y = 0
	eject_direction = eject_direction.normalized()
	
	# Calculate safe distance (estimated obstacle radius + safety margin)
	var safe_distance = 1.0  # Minimum safe distance
	
	# Try different ejection distances
	var ejection_attempts = [1.0, 1.5, 2.0, 2.5]
	var space_state = get_world_3d().direct_space_state
	
	for attempt_distance in ejection_attempts:
		var new_position = obstacle_pos + (eject_direction * attempt_distance)
		new_position.y = flight_height  # Maintain flight height
		
		# Check if this position is clear
		var query = PhysicsShapeQueryParameters3D.new()
		var shape = SphereShape3D.new()
		shape.radius = 0.2  # Slightly smaller check radius
		query.shape = shape
		query.transform.origin = new_position
		query.collision_mask = 2  # Only check obstacles
		
		var results = space_state.intersect_shape(query)
		var is_clear = true
		
		for result in results:
			var collider = result.get("collider")
			if collider and (collider.name.begins_with("tree_") or 
							collider.name.begins_with("rock_") or 
							collider.is_in_group("obstacles")):
				is_clear = false
				break
		
		if is_clear:
			# Found a safe position
			print("  Moving drone to safe position: ", new_position)
			position = new_position
			velocity = Vector3.ZERO  # Stop movement to prevent immediate re-collision
			collision_cooldown = 2.0  # Longer cooldown after ejection
			print("  ✅ Drone ejected successfully!")
			return
	
	# Fallback: move to a known safe position
	print("  Using fallback ejection - moving to center")
	position = Vector3(0, flight_height, 0)
	velocity = Vector3.ZERO
	collision_cooldown = 2.0
	print("  ✅ Drone moved to center as fallback!")

func _emergency_fix_obstacle_collision(obstacle_node: Node):
	"""Legacy function - now redirects to ejection"""
	_eject_drone_from_obstacle(obstacle_node)
