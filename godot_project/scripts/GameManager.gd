extends Node3D

# GameManager - Main coordinator for the hunter drone simulation
# Manages drone, target, obstacles, and AI integration

signal simulation_started
signal simulation_ended(success: bool)
signal target_caught
signal obstacle_hit

@export var grid_size: Vector2 = Vector2(10, 10)  # 10x10 grid
@export var cell_size: float = 0.8  # 0.8 units per grid cell (scaled down for 3D)
@export var max_simulation_time: float = 120.0  # 2 minutes max

# Game objects
var drone: Drone
var target: Target
var obstacles: Array[Obstacle] = []

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
	
	# Wait a frame to ensure any duplicates are cleared
	await get_tree().process_frame
	
	# Initialize game objects
	_setup_game_objects()
	
	# Start simulation
	start_simulation()

func _setup_game_objects():
	"""Initialize drone, target, and obstacles"""
	# Clear any existing entities first
	_clear_existing_entities()
	
	# Create drone
	drone = preload("res://scenes/Drone.tscn").instantiate()
	add_child(drone)
	drone.position = _grid_to_world(Vector2(1, 1))
	drone.collision_detected.connect(_on_drone_collision)
	drone.add_to_group("drone")
	print("Drone created at: ", drone.position)
	
	# Create target
	target = preload("res://scenes/Target.tscn").instantiate()
	add_child(target)
	target.position = _grid_to_world(Vector2(8, 8))
	target.caught.connect(_on_target_caught)
	target.add_to_group("target")
	print("Target created at: ", target.position)
	
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
	"""Generate random obstacles in the environment"""
	var obstacle_positions = [
		Vector2(3, 3),
		Vector2(5, 2),
		Vector2(7, 5),
		Vector2(2, 7),
		Vector2(6, 8)
	]
	
	for pos in obstacle_positions:
		var obstacle = preload("res://scenes/Obstacle.tscn").instantiate()
		add_child(obstacle)
		obstacle.position = _grid_to_world(pos)
		obstacles.append(obstacle)

func start_simulation():
	"""Start the hunting simulation"""
	if simulation_running:
		return
	
	print("Starting hunter drone simulation")
	simulation_running = true
	start_time = Time.get_time_dict_from_system().get("second", 0)
	simulation_time = 0.0
	
	# Reset positions
	drone.reset_position(_grid_to_world(Vector2(1, 1)))
	target.reset_position(_grid_to_world(Vector2(8, 8)))
	
	simulation_started.emit()

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
		stop_simulation(false)
		return
	
	# Update AI with current state
	_update_ai_state()
	
	# Update target behavior (evasive movement)
	_update_target_behavior(delta)
	
	# Check for target capture
	if drone and target:
		var distance = drone.position.distance_to(target.position)
		if distance < 0.8:  # Capture distance
			print("CAPTURE DETECTED! Distance: ", distance)
			_on_target_caught()
		else:
			# Also let target check for capture (backup)
			target.check_capture(drone.position)

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
	
	# Calculate evasion direction (away from drone, on XZ plane)
	var evasion_direction = Vector3(target_pos.x - drone_pos.x, 0, target_pos.z - drone_pos.z).normalized()
	
	# Add some randomness to movement
	var random_offset = Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	evasion_direction += random_offset
	evasion_direction = evasion_direction.normalized()
	
	# Move target
	target.move_evasively(evasion_direction, delta)

func _on_ai_decision_received(decision: Dictionary):
	"""Handle AI decision from LangGraph agent"""
	if not simulation_running or not drone:
		return
	
	print("AI Decision: ", decision.get("reasoning", "No reasoning provided"))
	
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

func _on_target_caught():
	"""Handle successful target capture"""
	print("Target caught! Simulation successful.")
	
	# Update UI to show success
	var status_label = get_node("../UI/StatusPanel/StatusLabel")
	if status_label:
		status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: TARGET CAPTURED!\nSimulation Complete - Success!\n\nPress R to restart or ESC to exit"
	
	# Hide the target to show it was captured (but don't destroy it)
	if target:
		target.visible = false
	
	target_caught.emit()
	stop_simulation(true)
	
	# Don't auto-exit - wait for user input

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
			var status_label = get_node("../UI/StatusPanel/StatusLabel")
			if status_label:
				status_label.text = "Hunter Drone AI - LangGraph Edition\nStatus: PAUSED\nPress Space to resume, R to restart, ESC to exit"
		else:
			print("Resuming simulation")
			start_simulation()
	elif Input.is_action_just_pressed("ui_accept"):  # Enter key
		if not simulation_running:
			start_simulation() 
