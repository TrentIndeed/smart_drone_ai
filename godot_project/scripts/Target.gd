extends CharacterBody3D
class_name Target

# Target - Evasive entity that tries to escape from the drone

signal caught

@export var max_speed: float = 3.0  # units/second - Realistic 25 mph human runner (scaled down)
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

# Animation system
var animation_player: AnimationPlayer = null
var current_animation: String = ""

func _ready():
	print("Target initialized at position: ", position)
	print("Target visible: ", visible)
	print("Target collision shape: ", $CollisionShape3D.shape)
	
	# Ensure target is visible
	visible = true
	
	last_drone_position = position
	# Initialize with a random movement direction
	movement_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	direction_change_timer = randf_range(1.0, 3.0)
	
	# Find and setup animation player
	call_deferred("_setup_animation_player")
	
	# Start with some initial velocity to ensure movement
	velocity = movement_direction * max_speed * 0.5
	last_position = position
	
	# Check for initial overlaps and push away from obstacles
	call_deferred("_fix_initial_position")
	
	# Debug animation system status
	print("Target running animation system status:")
	print("- RunningModel node exists: ", has_node("RunningModel"))
	if has_node("RunningModel"):
		print("- RunningModel children: ", $RunningModel.get_children())
		print("- Looking for AnimationPlayer in model...")

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
		
		# Enter panic mode if drone is close (much earlier detection)
		if distance_to_drone < 4.0:  # Start evading when drone is 4 units away
			panic_mode = true
			panic_timer = 3.0  # Stay in panic for 3 seconds
		elif panic_timer <= 0:
			panic_mode = false
	
	if panic_timer > 0:
		panic_timer -= delta
	
	# Update visual feedback - now with animation
	_update_animation()
	
	# Fallback: Always ensure target faces movement direction (even without animation)
	_update_model_orientation()
	
	# Update model color if available
	var running_model = $RunningModel
	if running_model:
		var mesh_instances = _find_mesh_instances(running_model)
		for mesh_instance in mesh_instances:
			var material = mesh_instance.get_surface_override_material(0)
			if not material:
				material = StandardMaterial3D.new()
				mesh_instance.set_surface_override_material(0, material)
			
			if material is StandardMaterial3D:
				if panic_mode:
					material.albedo_color = Color(1, 0.8, 0.8, 1)  # Light red tint when panicked
					material.emission_enabled = true
					material.emission = Color(0.3, 0.05, 0.05, 1)
				else:
					material.albedo_color = Color(1, 1, 1, 1)  # Normal color
					material.emission_enabled = false

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
	var base_speed_multiplier = 0.6  # Reduced to 0.6 for more realistic human jogging pace
	var intended_velocity = movement_direction * (max_speed * base_speed_multiplier)
	
	# Obstacle avoidance prediction - check if we're about to hit something
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		position, 
		position + intended_velocity.normalized() * 0.8,  # Look ahead
		collision_mask
	)
	var result = space_state.intersect_ray(query)
	
	if result:
		# Obstacle detected ahead - try to go around
		print("Target avoiding obstacle ahead")
		var avoid_direction = _find_avoidance_direction(result.normal)
		movement_direction = avoid_direction
		intended_velocity = avoid_direction * (max_speed * base_speed_multiplier)
		direction_change_timer = 1.0  # Don't change direction too soon
	
	velocity = intended_velocity
	
	# Avoid boundaries
	_avoid_boundaries()
	
	# Keep target at ground level before movement
	position.y = 0.0
	
	# Move with physics
	move_and_slide()
	
	# Keep target at ground level after movement (prevent floating)
	position.y = 0.0
	
	# Handle collisions (backup in case prediction failed)
	if get_slide_collision_count() > 0:
		_handle_obstacle_collision()

func move_evasively(evasion_direction: Vector3, _delta: float):
	"""Move evasively based on drone position"""
	var current_speed = max_speed
	
	# Speed boost in panic mode
	if panic_mode:
		current_speed *= 1.3  # Moderate speed boost when evading (adrenaline rush)
	
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
	var intended_velocity = final_direction * current_speed
	
	# Check for obstacles in evasion path too
	var space_state = get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(
		position, 
		position + intended_velocity.normalized() * 0.6,  # Shorter lookahead when evading
		collision_mask
	)
	var result = space_state.intersect_ray(query)
	
	if result:
		# Obstacle in evasion path - adjust direction
		var avoid_direction = _find_avoidance_direction(result.normal)
		# Blend avoidance with evasion
		final_direction = (final_direction + avoid_direction * 2.0).normalized()
		intended_velocity = final_direction * current_speed
	
	velocity = intended_velocity
	movement_direction = final_direction  # Update movement direction
	
	# Keep target at proper ground level (accounting for collision shape offset)
	position.y = 0.0
	
	# Ensure target doesn't clip into ground or "hop"
	var ground_space_state = get_world_3d().direct_space_state
	var ground_check = PhysicsRayQueryParameters3D.create(
		position + Vector3(0, 0.5, 0),  # Start slightly above
		position + Vector3(0, -0.5, 0), # Check down to ground
		8  # Ground collision layer (updated to layer 8)
	)
	var ground_result = ground_space_state.intersect_ray(ground_check)
	if ground_result:
		position.y = ground_result.position.y + 0.05  # Slightly above ground
	
	# Apply boundary checking to avoid walls
	_avoid_boundaries()
	
	# Move with collision detection
	move_and_slide()
	
	# Check for obstacles and adjust (backup)
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
	"""Handle collision with obstacles - improved to prevent clipping and loops"""
	# Get collision normal and find alternative direction
	var collision = get_slide_collision(0)
	var collision_normal = collision.get_normal()
	var collision_point = collision.get_position()
	var collider = collision.get_collider()
	
	print("Target collision with obstacle: ", collider.name if collider else "unknown", " at: ", position)
	
	# More aggressive pushback to escape tight spots
	var pushback_direction = (position - collision_point).normalized()
	pushback_direction.y = 0  # Keep on ground plane
	
	# Stronger pushback to prevent getting stuck
	position += pushback_direction * 0.3
	
	# If it's the small rock at center, use special escape logic
	var is_center_rock = (collider and collider.name.begins_with("rock_smallC") and 
						  collision_point.distance_to(Vector3.ZERO) < 1.0)
	
	var best_direction
	if is_center_rock:
		# For center rock, move directly away from center (0,0,0)
		print("  Escaping from center rock - moving directly away from origin")
		best_direction = position.normalized()  # Direction from origin to current position
		if best_direction.length() < 0.1:
			# If too close to origin, pick a random direction
			best_direction = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		best_direction.y = 0
		# Move far enough to clear the obstacle
		position += best_direction * 0.8
	else:
		# Normal obstacle avoidance
		var avoidance_options = [
			Vector3(collision_normal.z, 0, -collision_normal.x),  # Perpendicular right
			Vector3(-collision_normal.z, 0, collision_normal.x),  # Perpendicular left
			-collision_normal  # Direct bounce back
		]
		
		# Choose the best avoidance direction
		best_direction = avoidance_options[0]
		for direction in avoidance_options:
			direction.y = 0
			direction = direction.normalized()
			# Simple check - prefer directions that lead toward open space
			var test_pos = position + direction * 1.0  # Larger test distance
			if _is_position_safe(test_pos):
				best_direction = direction
				break
		
		# Add significant randomness to break repeating patterns
		var random_offset = Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
		best_direction = (best_direction + random_offset).normalized()
	
	# Update movement direction and velocity
	movement_direction = best_direction
	velocity = best_direction * max_speed * 0.8  # Reduced speed after collision
	
	# Force direction change soon to avoid getting stuck
	direction_change_timer = randf_range(0.3, 0.8)  # Shorter timer for faster direction changes

func _find_avoidance_direction(obstacle_normal: Vector3) -> Vector3:
	"""Find a good direction to avoid an obstacle"""
	# Try perpendicular directions first
	var avoidance_options = [
		Vector3(obstacle_normal.z, 0, -obstacle_normal.x),  # Perpendicular right
		Vector3(-obstacle_normal.z, 0, obstacle_normal.x),  # Perpendicular left
		-obstacle_normal  # Direct bounce back
	]
	
	# Test each direction and pick the safest one
	for direction in avoidance_options:
		direction.y = 0
		direction = direction.normalized()
		var test_pos = position + direction * 1.0
		if _is_position_safe(test_pos):
			return direction
	
	# If all else fails, just bounce back
	var fallback = -obstacle_normal
	fallback.y = 0
	return fallback.normalized()

func _is_position_safe(test_pos: Vector3) -> bool:
	"""Check if a position is relatively safe from obstacles"""
	# Simple check - just verify it's within bounds for now
	var min_boundary = -4.0
	var max_boundary = 3.2
	var margin = 0.2
	
	return (test_pos.x > min_boundary + margin and test_pos.x < max_boundary - margin and
			test_pos.z > min_boundary + margin and test_pos.z < max_boundary - margin)

func reset_position(pos: Vector3):
	"""Reset target to starting position"""
	# Ensure target is always at ground level
	pos.y = 0.0
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

func _setup_animation_player():
	"""Find and setup the animation player for the running model"""
	var running_model = $RunningModel
	if running_model:
		print("RunningModel found at scale: ", running_model.scale)
		print("RunningModel scene file path: ", running_model.scene_file_path)
		
		# Check for mesh instances and fix materials
		var mesh_instances = _find_mesh_instances(running_model)
		print("Found ", mesh_instances.size(), " mesh instances in running model")
		for mesh in mesh_instances:
			# Fix materials - Mixamo models often have transparent or missing materials
			_fix_mesh_materials(mesh)
		
		animation_player = _find_animation_player(running_model)
		if animation_player:
			print("Found AnimationPlayer in running model at path: ", animation_player.get_path())
			var anim_list = animation_player.get_animation_list()
			print("Available animations: ", anim_list)
			print("Total animation count: ", anim_list.size())
			
			# Debug: Print all animation details
			for i in range(anim_list.size()):
				var anim_name = anim_list[i]
				var anim = animation_player.get_animation(anim_name)
				print("Animation ", i, ": '", anim_name, "' - Length: ", anim.length, "s, Tracks: ", anim.get_track_count())
			
			# Wait a frame for everything to be set up properly
			await get_tree().process_frame
			
			# Try ALL available animations instead of guessing names
			var animation_found = false
			
			# First, try to use any animation that exists
			if anim_list.size() > 0:
				current_animation = anim_list[0]
				animation_found = true
				print("Using first available animation: ", current_animation)
			
			# Also try common names as backup
			var possible_names = ["Take 001", "mixamo.com", "Take001", "Running", "Run", "Armature|mixamo.com", "Armature|Take 001"]
			for anim_name in possible_names:
				if animation_player.has_animation(anim_name):
					current_animation = anim_name
					animation_found = true
					print("Found animation with common name: ", anim_name)
					break
			
			# If no common names found, use first available
			if not animation_found and anim_list.size() > 0:
				current_animation = anim_list[0]
				animation_found = true
				print("Using first available animation: ", current_animation)
			
			# Start the animation
			if animation_found and current_animation != "":
				print("Starting animation: ", current_animation)
				animation_player.play(current_animation)
				animation_player.speed_scale = 1.0
				
				# Set animation to loop (Godot 4 syntax)
				if animation_player.has_animation(current_animation):
					var animation = animation_player.get_animation(current_animation)
					animation.loop_mode = Animation.LOOP_LINEAR
					print("Animation loop mode set to LINEAR")
				
				# Verify animation is playing
				await get_tree().process_frame
				if animation_player.is_playing():
					print("SUCCESS: Animation is now playing!")
					_create_backup_visual_indicators()
				else:
					print("WARNING: Animation failed to start - implementing fallback")
					_implement_animation_fallback()
			else:
				print("ERROR: No animations found to play - implementing fallback")
				_implement_animation_fallback()
		else:
			print("ERROR: No AnimationPlayer found in running model - implementing fallback")
			print("RunningModel children structure:")
			_debug_print_node_tree(running_model, 0)
			_implement_animation_fallback()
	else:
		print("ERROR: No RunningModel node found - implementing fallback!")
		_implement_animation_fallback()
	
	# Additional debug: Check if the model itself is visible and working
	print("=== TARGET MODEL DEBUG ===")
	print("Target scale: ", scale)
	print("Target position: ", position)
	print("Target rotation: ", rotation)
	if has_node("RunningModel"):
		var model = $RunningModel
		print("RunningModel scale: ", model.scale)
		print("RunningModel position: ", model.position)
		print("RunningModel visible: ", model.visible)
		print("RunningModel scene_file_path: ", model.scene_file_path)
	print("=== END DEBUG ===")

func _implement_animation_fallback():
	"""Implement visual fallback when animation system fails"""
	print("Implementing animation fallback - creating enhanced procedural running animation")
	
	# Create a more realistic running animation for the model
	var running_model = $RunningModel
	if running_model:
		# Fast running steps - very quick bob to simulate feet hitting ground
		var bob_tween = create_tween()
		bob_tween.set_loops()
		bob_tween.tween_property(running_model, "position:y", 0.1, 0.1)   # Quick up
		bob_tween.tween_property(running_model, "position:y", -0.02, 0.05) # Quick down (foot contact)
		bob_tween.tween_property(running_model, "position:y", 0.08, 0.1)   # Quick up again
		bob_tween.tween_property(running_model, "position:y", 0.0, 0.05)   # Down to normal
		print("Created enhanced running bob animation for RunningModel")
		
		# Running lean - forward lean with slight bounce
		var lean_tween = create_tween()
		lean_tween.set_loops()
		lean_tween.tween_property(running_model, "rotation:x", deg_to_rad(-8), 0.2)   # Lean forward more
		lean_tween.tween_property(running_model, "rotation:x", deg_to_rad(-4), 0.2)   # Lean back
		print("Created enhanced running lean animation for RunningModel")
		
		# Arm swing simulation - more pronounced side motion
		var sway_tween = create_tween()
		sway_tween.set_loops()
		sway_tween.tween_property(running_model, "rotation:z", deg_to_rad(3), 0.15)   # Right lean
		sway_tween.tween_property(running_model, "rotation:z", deg_to_rad(-3), 0.15)  # Left lean
		print("Created enhanced running sway animation for RunningModel")
		
		# Scale pulse to show energy/effort
		var scale_tween = create_tween()
		scale_tween.set_loops()
		scale_tween.tween_property(running_model, "scale", Vector3(1.05, 0.95, 1.05), 0.15)
		scale_tween.tween_property(running_model, "scale", Vector3(0.95, 1.05, 0.95), 0.15)
		print("Created running scale pulse animation for RunningModel")
	
	# Create visual speed indicators around the target
	_create_backup_visual_indicators()
	
	# Set a flag that we're using fallback animation
	current_animation = "FALLBACK_RUNNING"
	print("Enhanced fallback running animation active - should look much more like running now!")

func _create_backup_visual_indicators():
	"""Create visual indicators to show target is running/moving"""
	# No visual indicators needed - focus on the model animation
	print("Skipping visual indicators - focusing on model animation")

func _debug_print_node_tree(node: Node, depth: int):
	"""Recursively print node tree structure for debugging"""
	var indent = "  ".repeat(depth)
	print(indent, "- ", node.name, " (", node.get_class(), ")")
	
	for child in node.get_children():
		_debug_print_node_tree(child, depth + 1)

func _find_animation_player(node: Node) -> AnimationPlayer:
	"""Recursively find AnimationPlayer in the model"""
	if node is AnimationPlayer:
		return node
	
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	
	return null

func _update_animation():
	"""Update animation based on movement state"""
	# Handle fallback animation case
	if current_animation == "FALLBACK_RUNNING":
		# Using procedural animation fallback - nothing to update
		return
		
	if not animation_player:
		# Check if we need to re-setup animation player
		if Engine.get_process_frames() % 60 == 0:  # Check once per second
			print("Target running animation still not being implemented - no AnimationPlayer found")
		return
	
	# Force animation to play if it's not playing (fix T-pose)
	if current_animation != "" and not animation_player.is_playing():
		print("Animation stopped - restarting: ", current_animation)
		call_deferred("_force_restart_animation")
	
	# Always ensure animation is playing if we have one
	if current_animation != "" and animation_player.is_playing():
		var speed_ratio = velocity.length() / max_speed
		# Keep animation playing at reasonable speed
		animation_player.speed_scale = max(0.8, speed_ratio * 1.5)
	elif current_animation != "":
		# Force animation to start if it's not playing
		call_deferred("_force_restart_animation")

func _force_restart_animation():
	"""Force restart animation (called deferred to avoid timing issues)"""
	if animation_player and current_animation != "":
		animation_player.stop()
		await get_tree().process_frame
		animation_player.play(current_animation)
		animation_player.speed_scale = 1.0
		
		# Ensure loop is set
		if animation_player.has_animation(current_animation):
			var animation = animation_player.get_animation(current_animation)
			animation.loop_mode = Animation.LOOP_LINEAR
		
		print("Force restarted animation: ", current_animation)
	else:
		print("Cannot restart animation - AnimationPlayer or animation missing")

func _update_model_orientation():
	"""Ensure target model faces movement direction (works even without animation)"""
	if velocity.length() > 0.1:
		var look_direction = velocity.normalized()
		var target_rotation = atan2(look_direction.x, look_direction.z)
		rotation.y = lerp_angle(rotation.y, target_rotation, 0.08)  # Smooth rotation

func _find_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes in the model"""
	var mesh_instances: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node)
	
	for child in node.get_children():
		mesh_instances.append_array(_find_mesh_instances(child))
	
	return mesh_instances

func _fix_mesh_materials(mesh_instance: MeshInstance3D):
	"""Fix materials for Mixamo models that might have transparency issues"""
	if not mesh_instance.mesh:
		return
	
	var surface_count = mesh_instance.mesh.get_surface_count()
	print("Mesh ", mesh_instance.name, " has ", surface_count, " surfaces")
	
	for i in range(surface_count):
		var existing_material = mesh_instance.get_surface_override_material(i)
		if not existing_material:
			# Create a new visible material
			var new_material = StandardMaterial3D.new()
			new_material.albedo_color = Color(0.8, 0.7, 0.6, 1.0)  # Skin-like color
			new_material.metallic = 0.0
			new_material.roughness = 0.8
			mesh_instance.set_surface_override_material(i, new_material)
			print("Created new material for ", mesh_instance.name, " surface ", i)
		else:
			# Fix existing material if it's transparent
			if existing_material is StandardMaterial3D:
				var std_mat = existing_material as StandardMaterial3D
				if std_mat.albedo_color.a < 1.0:
					print("Fixed transparency for ", mesh_instance.name, " surface ", i)
					std_mat.albedo_color.a = 1.0
				
				# Ensure it's not using transparency blend mode
				if std_mat.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
					std_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					print("Disabled transparency mode for ", mesh_instance.name)

func _fix_initial_position():
	"""Fix initial position to be at ground level and away from obstacles"""
	# Force target to ground level immediately
	position.y = 0.0
	
	# Check for horizontal overlaps with obstacles
	var space_state = get_world_3d().direct_space_state
	var shape = CapsuleShape3D.new()
	shape.radius = 0.15  # Slightly larger than target's collision shape
	shape.height = 0.6
	
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = position
	query.collision_mask = 2  # Only check obstacle layer
	
	var results = space_state.intersect_shape(query)
	
	if results.size() > 0:
		# Push away from overlapping obstacles
		print("Target spawned overlapping obstacles, pushing away...")
		var pushback = Vector3.ZERO
		
		for result in results:
			var collider = result.get("collider")
			if collider:
				var direction = (position - collider.global_position)
				direction.y = 0  # Keep on ground plane
				if direction.length() > 0:
					pushback += direction.normalized()
		
		if pushback.length() > 0:
			position += pushback.normalized() * 0.5  # Push away
			position.y = 0.0  # Ensure still at ground level
	
	print("Target fixed to ground position: ", position) 
