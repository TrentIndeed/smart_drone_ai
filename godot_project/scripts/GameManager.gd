extends Node3D

# GameManager - Main coordinator for the hunter drone simulation
# Manages drone, target, obstacles, and AI integration

signal simulation_started
signal simulation_ended(success: bool)
signal target_caught
signal obstacle_hit

@export var grid_size: Vector2 = Vector2(10, 10)  # 10x10 grid
@export var cell_size: float = 0.8  # 0.8 units per grid cell (scaled down for 3D)
@export var max_simulation_time: float = 600.0  # 10 minutes max (extended timeout)
@export var auto_restart_enabled: bool = true  # Auto-restart when simulation completes
@export var auto_restart_delay: float = 1.0  # Seconds to wait before auto-restart (reduced for faster restart)

# Game objects
var drone: Drone
var target: Target
var obstacles: Array[Node3D] = []

# Simulation state
var simulation_running: bool = false
var simulation_time: float = 0.0
var start_time: float = 0.0

# AI Integration
var ai_interface: Node

func _ready():
	print("GameManager initialized")
	
	# Check if there are multiple GameManagers (shouldn't happen)
	var game_managers = get_tree().get_nodes_in_group("game_manager")
	if game_managers.size() > 0:
		print("WARNING: Multiple GameManagers detected! Removing duplicates.")
		for gm in game_managers:
			if gm != self:
				gm.queue_free()
	
	# Add self to group for tracking
	add_to_group("game_manager")
	
	ai_interface = get_node("/root/AIInterface")
	
	# Connect AI signals
	ai_interface.ai_decision_received.connect(_on_ai_decision_received)
	ai_interface.ai_error_occurred.connect(_on_ai_error)
	
	# Initialize UI immediately with proper controls display
	var status_label = get_node_or_null("../UI/StatusPanel/StatusLabel")
	if status_label:
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: Initializing...\nMISSION: Neutralize target within 20ft range\nSPEEDS: Drone 35mph (navigates tree branches), Target 25mph (ground-bound)\nWEAPONS: Optimal range 12ft, Max range 20ft\nControls: R to restart, Space to pause/resume, ESC to exit\nPress any key to see controls"
	else:
		print("Status label not found - UI may not be set up correctly")
	
	# Initialize AI reasoning display
	var ai_reasoning_label = get_node_or_null("../UI/AIReasoningPanel/AIReasoningLabel")
	if ai_reasoning_label:
		ai_reasoning_label.text = "AI Reasoning:\nInitializing AI system...\nAnalyzing environment...\nTACTICAL CHALLENGE: Drone must navigate tree branches\nWEAPONS SYSTEM: Engaging within 10ft range only\nTarget is ground-bound - both must avoid obstacles\nPreparing strategic assessment..."
	else:
		print("AI reasoning label not found - UI may not be set up correctly")
	
	# Wait a frame to ensure any duplicates are cleared
	await get_tree().process_frame
	
	# Initialize game objects
	_setup_game_objects()
	
	# Start simulation and update UI properly
	call_deferred("_initialize_and_start")

func _setup_game_objects():
	"""Initialize drone, target, and obstacles"""
	# Clear any existing entities first
	_clear_existing_entities()
	
	# Create drone
	drone = preload("res://scenes/Drone.tscn").instantiate()
	add_child(drone)
	# Find a safe spawn position for the drone too
	var drone_spawn_pos = _find_safe_drone_spawn_position()
	drone.position = drone_spawn_pos
	drone.collision_detected.connect(_on_drone_collision)
	drone.target_shot.connect(_on_target_neutralized)
	drone.shot_fired.connect(_on_shot_fired)
	drone.add_to_group("drone")
	print("Drone created at: ", drone.position)
	
	# Create target
	target = preload("res://scenes/Target.tscn").instantiate()
	add_child(target)
	# Find a safe spawn position away from obstacles
	var target_spawn_pos = _find_safe_spawn_position()
	target_spawn_pos.y = 0.0  # Ensure target is at ground level
	target.position = target_spawn_pos
	target.caught.connect(_on_target_caught)
	target.add_to_group("target")
	print("Target created at: ", target.position)
	
	# Only add collision shapes if they don't exist (for faster restart)
	if obstacles.is_empty():
		await _add_collision_to_obstacles()
	
	# Create obstacles
	_generate_obstacles()

func _clear_existing_entities():
	"""Clear any existing game entities"""
	# Remove existing drones
	var existing_drones = get_tree().get_nodes_in_group("drone")
	for existing_drone in existing_drones:
		existing_drone.queue_free()
	
	# Remove existing targets
	var existing_targets = get_tree().get_nodes_in_group("target")
	for existing_target in existing_targets:
		existing_target.queue_free()
	
	# Clear obstacles array and remove obstacle nodes
	for obstacle in obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	obstacles.clear()

func _generate_obstacles():
	"""Collect manually placed obstacles from the scene"""
	# Clear any existing obstacles
	obstacles.clear()
	
	# Find all nodes in the obstacles group (manually placed)
	var obstacle_nodes = get_tree().get_nodes_in_group("obstacles")
	
	for obstacle in obstacle_nodes:
		# Only add obstacles that are children of this GameManager or Main scene
		if obstacle.get_parent() == self or obstacle.get_parent() == get_parent():
			obstacles.append(obstacle)
			print("Found obstacle: ", obstacle.name, " at position: ", obstacle.position)
	
	# Also add manually placed trees and rocks as obstacles for pathfinding
	var tree_nodes = []
	var rock_nodes = []
	
	# Find all tree and rock nodes by searching children
	for child in get_children():
		if child.name.begins_with("tree_"):
			tree_nodes.append(child)
		elif child.name.begins_with("rock_"):
			rock_nodes.append(child)
	
	# Add trees and rocks to obstacles array for collision detection
	for tree in tree_nodes:
		if tree and is_instance_valid(tree):
			obstacles.append(tree)
			tree.add_to_group("obstacles")  # Add to obstacles group
			print("Found tree obstacle: ", tree.name, " at position: ", tree.position)
	
	for rock in rock_nodes:
		if rock and is_instance_valid(rock):
			obstacles.append(rock)
			rock.add_to_group("obstacles")  # Add to obstacles group
			print("Found rock obstacle: ", rock.name, " at position: ", rock.position)
	
	print("Total obstacles found: ", obstacles.size())
	
	# If no obstacles found, add a few programmatically as backup
	if obstacles.size() == 0:
		print("No manually placed obstacles found - adding some programmatically")
		_add_default_obstacles()

func start_simulation():
	"""Start the AI simulation"""
	if simulation_running:
		print("Simulation already running")
		return
	
	print("Starting hunter drone simulation...")
	
	# Generate obstacles and add collision
	_generate_obstacles()
	await _add_collision_to_obstacles()
	
	# Emergency collision scan and fix
	# Skip emergency scan to prevent performance issues and duplicate collision bodies
	print("Skipping emergency collision scan - using simplified setup")
	
	# Reset existing drone and target positions if they exist, or create them
	if drone and target:
		# Reset positions
		var drone_spawn_pos = _find_safe_drone_spawn_position()
		drone.reset_position(drone_spawn_pos)
		var target_spawn_pos = _find_safe_spawn_position()
		target_spawn_pos.y = 0.0  # Ensure target is at ground level
		target.reset_position(target_spawn_pos)
	else:
		# Create new entities if they don't exist
		_setup_game_objects()
	
	simulation_running = true
	start_time = Time.get_time_dict_from_system().get("second", 0)
	simulation_time = 0.0
	
	# Update UI to show running state
	var status_label = get_node_or_null("../UI/StatusPanel/StatusLabel")
	if status_label:
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: RUNNING\nMISSION: Neutralize target within 20ft range\nSPEEDS: Drone 35mph (navigates tree branches), Target 25mph (ground-bound)\nWEAPONS: Optimal range 12ft, Max range 20ft\nControls: R to restart, Space to pause/resume, ESC to exit"
	
	simulation_started.emit()
	print("Simulation started successfully!")

func stop_simulation(success: bool = false):
	"""Stop the simulation"""
	if not simulation_running:
		return
	
	print("Simulation ended. Success: ", success)
	simulation_running = false
	simulation_ended.emit(success)

func _process(delta):
	if not simulation_running:
		return
	
	simulation_time += delta
	
	# Check for timeout
	if simulation_time > max_simulation_time:
		print("Simulation timed out after ", max_simulation_time, " seconds")
		stop_simulation(false)
		
		# Schedule auto-restart for timeout case too
		if auto_restart_enabled:
			print("Auto-restart scheduled after timeout in ", auto_restart_delay, " seconds")
			await get_tree().create_timer(auto_restart_delay).timeout
			if not simulation_running:  # Only restart if still stopped
				print("Auto-restarting simulation after timeout...")
				restart_simulation()
		return
	
	# Update AI with current state
	_update_ai_state()
	
	# Update target behavior (evasive movement)
	_update_target_behavior(delta)
	
	# No longer check for proximity capture - only shooting neutralization
	# The drone's shooting system handles target neutralization automatically

func _update_ai_state():
	"""Send current environment state to AI"""
	var drone_pos = drone.position
	var target_pos = target.position
	var obstacle_positions: Array[Vector3] = []
	
	for obstacle in obstacles:
		obstacle_positions.append(obstacle.position)
	
	ai_interface.update_environment(drone_pos, target_pos, obstacle_positions)

func _update_target_behavior(delta: float):
	"""Update target's evasive behavior"""
	if not target:
		return
	
	# Get current positions
	var target_pos = target.position
	var drone_pos = drone.position
	var distance_to_drone = target_pos.distance_to(drone_pos)
	
	# Trigger evasive behavior if drone is within shooting range or close
	if distance_to_drone < 3.5:  # Start evasive behavior when drone approaches shooting range
		# Calculate evasion direction (away from drone, on XZ plane)
		var evasion_direction = Vector3(target_pos.x - drone_pos.x, 0, target_pos.z - drone_pos.z).normalized()
		
		# Add some randomness to movement
		var random_offset = Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
		evasion_direction += random_offset
		evasion_direction = evasion_direction.normalized()
		
		# Move target evasively
		target.move_evasively(evasion_direction, delta)

func _on_ai_decision_received(decision: Dictionary):
	"""Handle AI decision from LangGraph agent"""
	if not simulation_running or not drone:
		return
	
	print("AI Decision: ", decision.get("reasoning", "No reasoning provided"))
	
	# Update AI reasoning display in UI
	var ai_reasoning_label = get_node_or_null("../UI/AIReasoningPanel/AIReasoningLabel")
	if ai_reasoning_label:
		var reasoning_text = decision.get("reasoning", "No reasoning provided")
		var confidence = decision.get("confidence", 0.0)
		var decision_type = decision.get("type", "unknown")
		
		ai_reasoning_label.text = "AI Reasoning:\n" + reasoning_text + "\n\nDecision Type: " + decision_type + "\nConfidence: " + str(confidence * 100) + "%"
	
	match decision.get("type", ""):
		"move_command":
			var target_pos = decision.get("target_position", [0, 0])
			var world_pos = _grid_to_world(Vector2(target_pos[0], target_pos[1]))
			drone.set_target_position(world_pos)
			
			# Handle emergency mode
			if decision.get("emergency_mode", false):
				drone.set_emergency_mode(true)
			else:
				drone.set_emergency_mode(false)
		
		"no_action":
			# AI decided not to act this turn
			pass
		
		_:
			print("Unknown AI decision type: ", decision.get("type", ""))

func _on_ai_error(error: String):
	"""Handle AI error"""
	print("AI Error: ", error)
	# Could implement fallback behavior here

func _on_drone_collision(obstacle_position: Vector3):
	"""Handle drone collision with obstacle"""
	print("Drone collision at: ", obstacle_position)
	obstacle_hit.emit()
	
	# Could add penalty or damage system here

func _on_target_neutralized(target_position: Vector3):
	"""Handle successful target neutralization via shooting"""
	print("Target neutralized at: ", target_position)
	
	# Update UI to show success
	var status_label = get_node("../UI/StatusPanel/StatusLabel")
	if status_label:
		if auto_restart_enabled:
			status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: TARGET NEUTRALIZED!\nDrone successfully engaged target within 20ft range\nSimulation Complete - Success!\n\nAuto-restarting in " + str(auto_restart_delay) + " seconds..."
		else:
			status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: TARGET NEUTRALIZED!\nDrone successfully engaged target within 20ft range\nSimulation Complete - Success!\n\nPress R to restart or ESC to exit"
	
	# Hide the target to show it was neutralized (but don't destroy it)
	if target:
		target.visible = false
	
	target_caught.emit()
	stop_simulation(true)
	
	# Schedule auto-restart if enabled
	if auto_restart_enabled:
		print("Auto-restart scheduled in ", auto_restart_delay, " seconds")
		await get_tree().create_timer(auto_restart_delay).timeout
		if not simulation_running:  # Only restart if still stopped
			print("Auto-restarting simulation...")
			restart_simulation()

func _on_shot_fired(from_pos: Vector3, to_pos: Vector3):
	"""Handle visual effects for shots fired"""
	print("Shot fired from: ", from_pos, " to: ", to_pos)
	# Could add visual effects here - muzzle flash, tracer, etc.

func _on_target_caught():
	"""Legacy capture function - now redirects to neutralization"""
	_on_target_neutralized(target.position if target else Vector3.ZERO)

func _grid_to_world(grid_pos: Vector2) -> Vector3:
	"""Convert grid coordinates to world coordinates"""
	return Vector3(
		(grid_pos.x - grid_size.x/2) * cell_size,
		0,
		(grid_pos.y - grid_size.y/2) * cell_size
	)

func _world_to_grid(world_pos: Vector3) -> Vector2:
	"""Convert world coordinates to grid coordinates"""
	return Vector2(
		world_pos.x / cell_size + grid_size.x/2,
		world_pos.z / cell_size + grid_size.y/2
	)

func get_simulation_stats() -> Dictionary:
	"""Get current simulation statistics"""
	return {
		"running": simulation_running,
		"time_elapsed": simulation_time,
		"drone_position": _world_to_grid(drone.position) if drone else Vector2.ZERO,
		"target_position": _world_to_grid(target.position) if target else Vector2.ZERO,
		"distance_to_target": drone.position.distance_to(target.position) if drone and target else 0.0
	}

func _add_default_obstacles():
	"""Add some default obstacles if none found manually"""
	var obstacle_positions = [
		Vector2(3, 3),
		Vector2(5, 2),
		Vector2(7, 5)
	]
	
	for pos in obstacle_positions:
		var obstacle = preload("res://scenes/Obstacle.tscn").instantiate()
		add_child(obstacle)
		obstacle.position = _grid_to_world(pos)
		obstacles.append(obstacle)

func restart_simulation():
	"""Restart the simulation"""
	print("Restarting simulation...")
	stop_simulation(false)
	
	# Restore target visibility if it was hidden
	if target:
		target.visible = true
	
	# Update UI
	var status_label = get_node("../UI/StatusPanel/StatusLabel")
	if status_label:
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: Restarting...\nControls: R to restart, Space to pause"
	
	await get_tree().create_timer(0.5).timeout
	start_simulation()

func _find_safe_drone_spawn_position() -> Vector3:
	"""Find a safe position to spawn the drone away from obstacles"""
	# Try several potential spawn positions for drone
	var safe_positions = [
		_grid_to_world(Vector2(1, 1)),   # Original spawn position
		_grid_to_world(Vector2(2, 1)),   # Nearby alternative
		_grid_to_world(Vector2(1, 2)),   # Another nearby alternative
		_grid_to_world(Vector2(0, 0)),   # Center-left corner
		_grid_to_world(Vector2(2, 2)),   # Slightly more central
		_grid_to_world(Vector2(0, 1)),   # Left edge
		_grid_to_world(Vector2(1, 0)),   # Bottom edge
	]
	
	# Check each position for safety
	for pos in safe_positions:
		pos.y = 0.5  # Set proper flight height for drone
		if _is_spawn_position_safe(pos):
			print("Found safe drone spawn at: ", pos)
			return pos
	
	# Fallback to a safe position
	print("Using fallback drone spawn position")
	var fallback = _grid_to_world(Vector2(0, 0))
	fallback.y = 0.5  # Flight height
	return fallback

func _find_safe_spawn_position() -> Vector3:
	"""Find a safe position to spawn the target away from obstacles"""
	# Try several potential spawn positions
	var safe_positions = [
		_grid_to_world(Vector2(7, 7)),   # Further from corner
		_grid_to_world(Vector2(6, 8)),   # Alternative position
		_grid_to_world(Vector2(8, 6)),   # Another alternative
		_grid_to_world(Vector2(5, 7)),   # Even safer
		_grid_to_world(Vector2(7, 5)),   # Another safe spot
		_grid_to_world(Vector2(2, 8)),   # Far from drone spawn
		_grid_to_world(Vector2(8, 2)),   # Corner opposite to drone
	]
	
	# Check each position for safety
	for pos in safe_positions:
		if _is_spawn_position_safe(pos):
			print("Found safe target spawn at: ", pos)
			return pos
	
	# Fallback to a known safe position in the center
	print("Using fallback target spawn position")
	return _grid_to_world(Vector2(5, 5))

func _is_spawn_position_safe(test_pos: Vector3) -> bool:
	"""Check if a spawn position is safe from obstacles"""
	var safe_distance = 2.0  # Increased minimum distance from obstacles
	
	# Check distance from all obstacles
	for obstacle in obstacles:
		if obstacle and is_instance_valid(obstacle):
			var distance = test_pos.distance_to(obstacle.position)
			if distance < safe_distance:
				print("Position ", test_pos, " too close to obstacle ", obstacle.name, " (distance: ", distance, ")")
				return false
	
	# Use physics system to check for overlaps
	var space_state = get_world_3d().direct_space_state
	var shape = CapsuleShape3D.new()
	shape.radius = 0.5
	shape.height = 1.0
	
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform.origin = test_pos
	query.collision_mask = 0xFFFFFFFF  # Check all collision layers
	
	var results = space_state.intersect_shape(query)
	if results.size() > 0:
		print("Position ", test_pos, " overlaps with physics bodies: ", results.size(), " objects")
		return false
	
	# Check boundaries with larger margin
	var min_boundary = -3.0  # Stay further away from edges
	var max_boundary = 2.2
	
	var within_bounds = (test_pos.x > min_boundary and test_pos.x < max_boundary and
			test_pos.z > min_boundary and test_pos.z < max_boundary)
	
	if not within_bounds:
		print("Position ", test_pos, " outside safe boundaries")
	
	return within_bounds

func _input(event):
	"""Handle input events"""
	if event.is_action_pressed("ui_cancel"):  # ESC key
		print("Exiting application...")
		get_tree().quit()
	elif event.is_action_pressed("ui_restart"):  # R key
		restart_simulation()
	elif event.is_action_pressed("ui_pause"):  # Space key
		print("Space key pressed - toggling pause")
		if simulation_running:
			print("Pausing simulation")
			stop_simulation(false)
			# Update UI to show paused state
			var status_label = get_node_or_null("../UI/StatusPanel/StatusLabel")
			if status_label:
				status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: PAUSED\nPress Space to resume, R to restart, ESC to exit"
		else:
			print("Resuming simulation")
			# Update UI to show running state
			var status_label = get_node_or_null("../UI/StatusPanel/StatusLabel")
			if status_label:
				status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: RUNNING\nControls: R to restart, Space to pause/resume, ESC to exit\nCamera: 3rd Person Drone View"
			start_simulation()
	elif Input.is_action_just_pressed("ui_accept"):  # Enter key
		if not simulation_running:
			start_simulation() 

func _initialize_and_start():
	"""Initialize the game and update UI properly"""
	# Update UI to show that initialization is complete
	var status_label = get_node_or_null("../UI/StatusPanel/StatusLabel")
	if status_label:
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: READY TO START\nMISSION: Neutralize target within 20ft range\nSPEEDS: Drone 35mph (navigates tree branches), Target 25mph (ground-bound)\nWEAPONS: Optimal range 12ft, Max range 20ft\nControls: R to restart, Space to pause/resume, ESC to exit"
	
	start_simulation() 

func _add_collision_to_obstacles():
	"""Add collision shapes to imported 3D models that don't have them"""
	print("=== ADDING COLLISION SHAPES TO OBSTACLES ===")
	
	# Find all tree and rock nodes - use a set to avoid duplicates
	var processed_nodes = {}
	var tree_nodes = []
	var rock_nodes = []
	
	# Search only direct children to avoid duplicates
	for child in get_children():
		var node_id = child.get_instance_id()
		if node_id in processed_nodes:
			continue
		processed_nodes[node_id] = true
		
		if child.name.begins_with("tree_"):
			tree_nodes.append(child)
		elif child.name.begins_with("rock_"):
			rock_nodes.append(child)
	
	print("Found obstacles:")
	print("  Trees: ", tree_nodes.size())
	print("  Rocks: ", rock_nodes.size()) 
	
	# Add collision to each tree
	for tree in tree_nodes:
		if tree and is_instance_valid(tree):
			await _add_static_collision_to_node(tree, Vector3(0.2, 1.0, 0.2))  # Small collision for trees
	
	# Add collision to each rock
	for rock in rock_nodes:
		if rock and is_instance_valid(rock):
			await _add_static_collision_to_node(rock, Vector3(0.3, 0.3, 0.3))  # Small collision for rocks

func _verify_all_obstacles_have_collision():
	"""Verify that all obstacles have proper collision setup"""
	print("=== VERIFYING OBSTACLE COLLISION SETUP ===")
	
	var total_obstacles = 0
	var obstacles_with_collision = 0
	
	# Check all nodes with obstacle-like names or in obstacles group
	var all_potential_obstacles = []
	_find_nodes_by_name(get_tree().root, "tree_", all_potential_obstacles)
	_find_nodes_by_name(get_tree().root, "rock_", all_potential_obstacles)
	
	# Add group members
	var group_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obstacle in group_obstacles:
		if obstacle not in all_potential_obstacles:
			all_potential_obstacles.append(obstacle)
	
	for obstacle in all_potential_obstacles:
		# Skip invalid/freed nodes
		if not obstacle or not is_instance_valid(obstacle):
			continue
			
		total_obstacles += 1
		var has_collision = false
		
		# Check if obstacle itself is a StaticBody3D
		if obstacle is StaticBody3D:
			has_collision = true
			print("  ✓ ", obstacle.name, " - is StaticBody3D (layer: ", obstacle.collision_layer, ")")
		else:
			# Check if it has a collision body child
			for child in obstacle.get_children():
				if child is StaticBody3D and child.name.ends_with("_CollisionBody"):
					has_collision = true
					print("  ✓ ", obstacle.name, " - has collision body (layer: ", child.collision_layer, ")")
					break
		
		if has_collision:
			obstacles_with_collision += 1
		else:
			print("  ✗ ", obstacle.name, " - NO COLLISION DETECTED!")
			# Try to add collision to missing ones
			await _add_static_collision_to_node(obstacle, Vector3(0.4, 0.4, 0.4))
			obstacles_with_collision += 1
	
	print("=== COLLISION VERIFICATION COMPLETE ===")
	print("Total obstacles: ", total_obstacles)
	print("Obstacles with collision: ", obstacles_with_collision)
	print("Coverage: ", (obstacles_with_collision * 100.0 / total_obstacles) if total_obstacles > 0 else 100.0, "%")

func _add_static_collision_to_node(node: Node3D, collision_size: Vector3):
	"""Add StaticBody3D with collision shape to a 3D node"""
	# Safety check - ensure node is valid and not freed
	if not node or not is_instance_valid(node):
		print("  Skipping invalid/freed node")
		return
	
	# Skip if this node is already a StaticBody3D with proper collision layer
	if node is StaticBody3D:
		if node.collision_layer == 2:
			print("  ", node.name, " already has collision layer 2")
			return
		else:
			print("  ", node.name, " is StaticBody3D but wrong layer (", node.collision_layer, "), fixing...")
			node.collision_layer = 2
			node.collision_mask = 0
			return
	
	# Check if collision body already exists
	var existing_collision = null
	for child in node.get_children():
		if child is StaticBody3D and child.name.ends_with("_CollisionBody"):
			existing_collision = child
			break
	
	if existing_collision:
		# Just ensure it has the right settings
		existing_collision.collision_layer = 2
		existing_collision.collision_mask = 0
		print("  ", node.name, " already has collision body")
		return
	
	print("  Adding collision to: ", node.name, " at position: ", node.position)
	
	# Create StaticBody3D for collision
	var static_body = StaticBody3D.new()
	static_body.name = node.name + "_CollisionBody"
	
	# Create collision shape
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"
	
	# Create appropriate shape based on the object type
	var shape
	if node.name.begins_with("tree_"):
		# Use capsule shape for trees (better for trunk + branches)
		shape = CapsuleShape3D.new()
		shape.radius = collision_size.x
		shape.height = collision_size.y
	else:
		# Use box shape for rocks and other obstacles
		shape = BoxShape3D.new()
		shape.size = collision_size
	
	collision_shape.shape = shape
	
	# Set collision layers and masks for proper interaction
	static_body.collision_layer = 2  # Layer 2 for obstacles
	static_body.collision_mask = 0   # Obstacles don't need to detect collisions with others
	
	# Add collision shape to static body
	static_body.add_child(collision_shape)
	
	# Add static body to the obstacle node
	node.add_child(static_body)
	
	# Add to obstacles group for navigation
	node.add_to_group("obstacles")
	
	print("  ✓ Added collision to: ", node.name, " (layer: ", static_body.collision_layer, ")")

func _find_nodes_by_name(parent: Node, name_pattern: String, result_array: Array):
	"""Recursively find nodes whose names start with the pattern"""
	for child in parent.get_children():
		if child.name.begins_with(name_pattern):
			result_array.append(child)
		_find_nodes_by_name(child, name_pattern, result_array)

func _emergency_scan_and_fix_all_obstacles():
	"""Emergency scan to find and fix all obstacles that might not have collision"""
	print("=== EMERGENCY OBSTACLE COLLISION SCAN ===")
	
	var fixed_count = 0
	var total_scanned = 0
	
	# Get all potential obstacles from the entire scene
	var all_nodes = []
	_get_all_nodes_recursive(get_tree().root, all_nodes)
	
	for node in all_nodes:
		# Skip invalid/freed nodes
		if not node or not is_instance_valid(node):
			continue
			
		if node.name.begins_with("tree_") or node.name.begins_with("rock_") or node.is_in_group("obstacles"):
			total_scanned += 1
			print("Scanning obstacle: ", node.name, " (type: ", node.get_class(), ")")
			
			var needs_fix = false
			var collision_info = "None"
			
			# Check what type of collision setup this node has
			if node is StaticBody3D:
				if node.collision_layer != 2:
					needs_fix = true
					collision_info = "StaticBody3D on wrong layer (" + str(node.collision_layer) + ")"
				else:
					collision_info = "StaticBody3D on correct layer"
			else:
				# Check if it has collision body children
				var has_collision_child = false
				for child in node.get_children():
					if child is StaticBody3D and child.collision_layer == 2:
						has_collision_child = true
						collision_info = "Has correct collision child"
						break
					elif child is StaticBody3D:
						child.collision_layer = 2
						child.collision_mask = 0
						has_collision_child = true
						collision_info = "Fixed collision child layer"
						needs_fix = true
						break
				
				if not has_collision_child:
					needs_fix = true
					collision_info = "No collision body found"
			
			print("  Status: ", collision_info)
			
			if needs_fix:
				print("  🔧 Fixing obstacle collision...")
				await _force_add_collision_to_obstacle(node)
				fixed_count += 1
				print("  ✅ Fixed!")
	
	print("=== EMERGENCY SCAN COMPLETE ===")
	print("Total obstacles scanned: ", total_scanned)
	print("Obstacles fixed: ", fixed_count)
	print("Success rate: ", ((total_scanned - fixed_count) * 100.0 / total_scanned) if total_scanned > 0 else 100.0, "% already correct")

func _get_all_nodes_recursive(node: Node, result_array: Array):
	"""Recursively get all nodes in the scene tree"""
	result_array.append(node)
	for child in node.get_children():
		_get_all_nodes_recursive(child, result_array)

func _force_add_collision_to_obstacle(obstacle_node: Node3D):
	"""Force add collision to an obstacle, removing any existing faulty collision"""
	# Safety check - ensure node is valid and not freed
	if not obstacle_node or not is_instance_valid(obstacle_node):
		print("    Skipping invalid/freed obstacle node")
		return
	
	print("    Force-fixing collision for: ", obstacle_node.name)
	
	# If it's already a StaticBody3D, just fix the layer
	if obstacle_node is StaticBody3D:
		obstacle_node.collision_layer = 2
		obstacle_node.collision_mask = 0
		print("    Fixed StaticBody3D layer")
		return
	
	# Remove any existing collision bodies that might be faulty
	var children_to_remove = []
	for child in obstacle_node.get_children():
		if child is StaticBody3D:
			children_to_remove.append(child)
	
	for child in children_to_remove:
		print("    Removing existing collision body: ", child.name)
		child.queue_free()
	
	await get_tree().process_frame
	
	# Create new collision body
	var static_body = StaticBody3D.new()
	static_body.name = obstacle_node.name + "_ForceCollision"
	static_body.collision_layer = 2
	static_body.collision_mask = 0
	
	# Create collision shape based on obstacle type
	var collision_shape = CollisionShape3D.new()
	var shape
	
	if obstacle_node.name.begins_with("tree_"):
		shape = CapsuleShape3D.new()
		shape.radius = 0.25
		shape.height = 1.2
		print("    Created capsule collision for tree")
	else:
		shape = BoxShape3D.new()
		shape.size = Vector3(0.4, 0.4, 0.4)
		print("    Created box collision for rock/obstacle")
	
	collision_shape.shape = shape
	static_body.add_child(collision_shape)
	obstacle_node.add_child(static_body)
	
	# Ensure it's in obstacles group
	obstacle_node.add_to_group("obstacles")
	
	print("    ✅ Force-added collision successfully!")
