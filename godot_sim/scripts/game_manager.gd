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
@export var debug_collision_shapes: bool = false  # Show collision shape wireframes (Toggle with 'C' key)

# Game objects
var drone: Node3D  # Can be Drone (DroneFlightAdapter), DroneFlightFallback, or any drone type
var target: Target
var obstacles: Array[Node3D] = []
var glb_spawner: GLBObjectSpawner
var simple_spawner: SimpleObjectSpawner
var use_simple_spawner: bool = false  # Use GLBObjectSpawner for better collision

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
	
	# Get reference to main scene
	var main_scene = get_tree().current_scene
	
	# Try multiple paths to find AI_Interface
	if main_scene:
		ai_interface = main_scene.get_node_or_null("AI_Interface")
	if not ai_interface:
		ai_interface = get_node_or_null("/root/Main/AI_Interface")
	if not ai_interface:
		# Try finding anywhere in scene tree
		var ai_nodes = get_tree().get_nodes_in_group("ai_interface")
		if ai_nodes.size() > 0:
			ai_interface = ai_nodes[0]
	if not ai_interface:
		print("Warning: AI_Interface node not found - AI functionality disabled")
	
	# Note: New HTTP-based AI interface doesn't use signals
	# AI communication is handled via HTTP requests/responses
	
	# Initialize UI immediately with proper controls display
	var status_label = null
	var ai_reasoning_label = null
	
	if main_scene:
		status_label = main_scene.get_node_or_null("UI/StatusPanel/StatusLabel")
		ai_reasoning_label = main_scene.get_node_or_null("UI/AIReasoningPanel/AIReasoningLabel")
	
	if status_label:
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: Initializing...\nMISSION: Neutralize target within 20ft range (2 shots required)\nSPEEDS: Drone 35mph (navigates tree branches), Target 25mph (ground-bound)\nWEAPONS: Optimal range 12ft, Max range 20ft, Fast targeting\nControls: R to restart, Space to pause/resume, C to toggle collision debug, ESC to exit\nPress any key to see controls"
	else:
		print("Status label not found - UI may not be set up correctly")
	
	# Initialize AI reasoning display
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
	"""Initialize drone, target, and GLB obstacles"""
	# Clear any existing entities first
	_clear_existing_entities()
	
	# Create spawner (GLB or simple fallback)
	if use_simple_spawner:
		if not simple_spawner:
			var SimpleSpawnerScript = load("res://scripts/simple_object_spawner.gd")
			if SimpleSpawnerScript:
				simple_spawner = SimpleSpawnerScript.new()
				simple_spawner.name = "SimpleSpawner"
				simple_spawner.debug_collision_shapes = debug_collision_shapes  # Pass debug flag
				add_child(simple_spawner)
				simple_spawner.objects_spawned.connect(_on_simple_objects_spawned)
			else:
				print("ERROR: Could not load SimpleObjectSpawner script!")
				return
		
		# Spawn simple objects
		simple_spawner.spawn_objects()
	else:
		# Create GLB spawner if it doesn't exist
		if not glb_spawner:
			var GLBSpawnerScript = load("res://scripts/glb_object_spawner.gd")
			if GLBSpawnerScript:
				glb_spawner = GLBSpawnerScript.new()
				glb_spawner.name = "GLBSpawner"
				glb_spawner.debug_collision_shapes = debug_collision_shapes  # Pass debug flag
				add_child(glb_spawner)
				glb_spawner.objects_spawned.connect(_on_glb_objects_spawned)
			else:
				print("ERROR: Could not load GLBObjectSpawner script!")
				return
		
		# Spawn GLB objects first
		glb_spawner.spawn_objects()
	
	# Find existing drone in scene instead of creating new one
	var drones = get_tree().get_first_node_in_group("drones")
	if drones and drones is Node3D:
		drone = drones
	if not drone:
		# Try finding by node name in main scene
		var main_scene = get_tree().current_scene
		if main_scene:
			var found_drone = main_scene.get_node_or_null("AerodynamicDrone")
			if found_drone and found_drone is Node3D:
				drone = found_drone
	if not drone:
		# Try finding anywhere in the scene tree
		var all_drones = get_tree().get_nodes_in_group("drones")
		if all_drones.size() > 0:
			var other_drone = all_drones[0]
			if other_drone is Node3D:
				drone = other_drone
	if not drone:
		print("ERROR: No drone found in 'drones' group!")
		return
	
	# Debug: Print drone type for compatibility verification
	print("Found drone type: ", drone.get_script().get_global_name() if drone.get_script() else "No script")
	print("Drone class: ", drone.get_class())
	
	# Find a safe spawn position for the drone
	var drone_spawn_pos = _find_safe_drone_spawn_position()
	if drone is Node3D:
		drone.position = drone_spawn_pos
	else:
		print("Warning: Drone is not a Node3D, cannot set position")
	
	# Connect signals (aerodynamic drone signals)
	if drone.has_signal("collision_detected"):
		drone.collision_detected.connect(_on_drone_collision)
	if drone.has_signal("target_shot"):
		drone.target_shot.connect(_on_target_neutralized)
	if drone.has_signal("shot_fired"):
		drone.shot_fired.connect(_on_shot_fired)
	if drone.has_signal("target_reached"):
		drone.target_reached.connect(_on_target_reached)
	if drone.has_signal("flight_mode_changed"):
		drone.flight_mode_changed.connect(_on_flight_mode_changed)
	
	print("Using existing aerodynamic drone at: ", drone.position if drone is Node3D else "Unknown")
	
	# Create target
	target = preload("res://scenes/target.tscn").instantiate()
	add_child(target)
	# Find a safe spawn position away from obstacles
	var target_spawn_pos = _find_safe_spawn_position()
	target_spawn_pos.y = 0.0  # Ensure target is at ground level
	target.position = target_spawn_pos
	target.caught.connect(_on_target_caught)
	target.target_hit.connect(_on_target_hit)
	target.target_neutralized.connect(_on_target_neutralized_by_target)
	target.add_to_group("target")
	print("Target created at: ", target.position)

func _clear_existing_entities():
	"""Clear any existing game entities"""
	# Don't remove the aerodynamic drone - just reset its position
	# It's part of the main scene now
	
	# Remove existing targets
	var existing_targets = get_tree().get_nodes_in_group("target")
	for existing_target in existing_targets:
		existing_target.queue_free()
	
	# Clear GLB objects if spawner exists
	if glb_spawner:
		glb_spawner.clear_objects()
	
	# Clear simple objects if spawner exists
	if simple_spawner:
		simple_spawner.clear_objects()
	
	# Clear obstacles array and remove obstacle nodes
	for obstacle in obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	obstacles.clear()

func _on_glb_objects_spawned(count: int):
	"""Callback when GLB objects are spawned"""
	# Update obstacles array with spawned GLB objects
	if glb_spawner:
		obstacles = glb_spawner.get_spawned_objects()

func _on_simple_objects_spawned(count: int):
	"""Callback when simple objects are spawned"""
	# Update obstacles array with spawned simple objects
	if simple_spawner:
		obstacles = simple_spawner.get_spawned_objects()

# Old obstacle generation removed - now using GLB spawner

func start_simulation():
	"""Start the AI simulation"""
	if simulation_running:
		print("Simulation already running")
		return
	
	print("Starting hunter drone simulation...")
	
	# GLB objects are spawned in _setup_game_objects() now
	print("Using GLB objects for obstacles")
	
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
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: RUNNING\nMISSION: Neutralize target within 20ft range (2 shots required)\nSPEEDS: Drone 35mph (navigates tree branches), Target 25mph (ground-bound)\nWEAPONS: Optimal range 12ft, Max range 20ft, Fast targeting\nControls: R to restart, Space to pause/resume, ESC to exit"
	
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
	var drone_pos = drone.position if drone is Node3D else Vector3.ZERO
	var target_pos = target.position if target else Vector3.ZERO
	var obstacle_positions: Array[Vector3] = []
	
	for obstacle in obstacles:
		obstacle_positions.append(obstacle.position)
	
	# Note: AIInterface uses simple target tracking, not complex environment updates
	# The drone AI bridge handles target tracking automatically

func _update_target_behavior(delta: float):
	"""Update target's evasive behavior"""
	if not target:
		return
	
	# Get current positions
	var target_pos = target.position
	var drone_pos = drone.position if drone is Node3D else Vector3.ZERO
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

# Note: These functions are no longer used since AI interface switched to HTTP
# AI decisions are now handled directly via HTTP requests to the AIInterface

func _legacy_on_ai_decision_received(_decision: Dictionary):
	"""Legacy function - AI now uses HTTP interface"""
	print("Legacy AI decision handler called - this should not happen")

func _legacy_on_ai_error(error: String):
	"""Legacy function - AI now uses HTTP interface"""
	print("Legacy AI error handler called: ", error)

func _on_target_reached(position: Vector3):
	"""Handle drone reaching target position"""
	print("Drone reached target position: ", position)

func _on_flight_mode_changed(new_mode: String):
	"""Handle flight mode changes"""
	print("Drone flight mode changed to: ", new_mode)

func _on_drone_collision(obstacle_position: Vector3):
	"""Handle drone collision with obstacle"""
	print("Drone collision at: ", obstacle_position)
	obstacle_hit.emit()
	
	# Could add penalty or damage system here

func _on_target_hit(remaining_health: int):
	"""Handle target being hit but not neutralized"""
	print("Target hit! Remaining health: ", remaining_health)
	# Could add UI feedback here showing target health

func _on_target_neutralized_by_target():
	"""Handle target neutralization called by the target itself"""
	print("Target neutralized by target signal!")
	_on_target_neutralized(target.position if target else Vector3.ZERO)

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
	if target and is_instance_valid(target):
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
		"drone_position": _world_to_grid(drone.position) if drone and drone is Node3D else Vector2.ZERO,
		"target_position": _world_to_grid(target.position) if target else Vector2.ZERO,
		"distance_to_target": drone.position.distance_to(target.position) if drone and drone is Node3D and target else 0.0
	}

# _add_default_obstacles method removed - using GLB spawner now

func restart_simulation():
	"""Restart the simulation"""
	print("Restarting simulation...")
	stop_simulation(false)
	
	# Restore target visibility if it was hidden and reset health
	if target and is_instance_valid(target):
		target.visible = true
		if target.has_method("reset_health"):
			target.reset_health()
	
	# Update UI
	var status_label = get_node("../UI/StatusPanel/StatusLabel")
	if status_label:
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: Restarting...\nControls: R to restart, Space to pause"
	
	await get_tree().create_timer(0.5).timeout
	start_simulation()

func _find_safe_drone_spawn_position() -> Vector3:
	"""Find a safe position to spawn the drone away from obstacles"""
	# Try several potential spawn positions for drone - focus on safe center areas
	var safe_positions = [
		Vector3(0, 2, 0),      # Center at good altitude
		Vector3(1, 2, 1),      # Nearby safe spot
		Vector3(-1, 2, 1),     # Another safe spot
		Vector3(1, 2, -1),     # Another variation
		Vector3(-1, 2, -1),    # Final variation
		Vector3(0, 2, 2),      # Forward position
		Vector3(0, 2, -2),     # Rear position
	]
	
	# Check each position for safety
	for pos in safe_positions:
		if _is_spawn_position_safe(pos):
			print("Found safe drone spawn at: ", pos)
			return pos
	
	# Fallback to a safe position in the center
	print("Using fallback drone spawn position")
	var fallback = Vector3(0, 2, 0)  # Safe center position at good altitude
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
	elif event is InputEventKey and event.pressed and event.keycode == KEY_C:  # C key to toggle collision debug
		debug_collision_shapes = !debug_collision_shapes
		print("Collision shape debug: ", "ON" if debug_collision_shapes else "OFF")
		
		# Update spawner debug setting
		if simple_spawner:
			simple_spawner.debug_collision_shapes = debug_collision_shapes
		if glb_spawner:
			glb_spawner.debug_collision_shapes = debug_collision_shapes
		
		# Recreate objects with new debug setting
		_refresh_collision_debug()

func _refresh_collision_debug():
	"""Refresh collision debug visualization"""
	print("Refreshing collision debug visualization...")
	
	# Clear and respawn objects with debug visualization
	if simple_spawner:
		simple_spawner.clear_objects()
		simple_spawner.spawn_objects()
	elif glb_spawner:
		glb_spawner.clear_objects()
		glb_spawner.spawn_objects()

func _initialize_and_start():
	"""Initialize the game and update UI properly"""
	# Update UI to show that initialization is complete
	var status_label = get_node_or_null("../UI/StatusPanel/StatusLabel")
	if status_label:
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: READY TO START\nMISSION: Neutralize target within 20ft range\nSPEEDS: Drone 35mph (navigates tree branches), Target 25mph (ground-bound)\nWEAPONS: Optimal range 12ft, Max range 20ft\nControls: R to restart, Space to pause/resume, ESC to exit"
	
	start_simulation() 

# All old collision methods removed - GLB objects handle collision automatically
