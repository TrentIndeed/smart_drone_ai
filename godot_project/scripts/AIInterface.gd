extends Node

# AIInterface - Handles communication between Godot and Python LangGraph agent
# This singleton manages the bridge between the game and AI agent

signal ai_decision_received(decision: Dictionary)
signal ai_error_occurred(error: String)

@export var python_script_path: String = "../agent/main.py"
@export var decision_interval: float = 0.5
@export var debug_mode: bool = true

var python_process: int
var is_ai_running: bool = false
var last_decision_time: float = 0.0
var current_drone_pos: Vector3
var current_target_pos: Vector3
var current_obstacles: Array[Vector3] = []

# HTTP server for communication (alternative to subprocess)
var http_request: HTTPRequest

func _ready():
	print("AI Interface initialized")
	http_request = HTTPRequest.new()
	http_request.name = "HTTPRequest"
	add_child(http_request)
	http_request.request_completed.connect(_on_ai_response_received)
	
	# Try to start the AI agent
	start_ai_agent()

func start_ai_agent():
	"""Start the Python AI agent process"""
	if is_ai_running:
		print("AI agent already running")
		return
	
	print("Starting AI agent...")
	# Note: In production, you might want to start a separate HTTP server
	# or use TCP sockets for communication
	is_ai_running = true

func stop_ai_agent():
	"""Stop the AI agent process"""
	if not is_ai_running:
		return
	
	print("Stopping AI agent...")
	# Clean shutdown logic here
	is_ai_running = false

func update_environment(drone_pos: Vector3, target_pos: Vector3, obstacles: Array[Vector3]):
	"""Update the AI agent with current environment state"""
	current_drone_pos = drone_pos
	current_target_pos = target_pos
	current_obstacles = obstacles
	
	# Only send updates at specified intervals
	var current_time = Time.get_time_dict_from_system()
	var time_since_last = current_time.get("second", 0) - last_decision_time
	
	if time_since_last >= decision_interval:
		_send_environment_update()
		last_decision_time = current_time.get("second", 0)

func _send_environment_update():
	"""Send environment update to AI agent"""
	if not is_ai_running:
		return
	
	var environment_data = {
		"type": "environment_update",
		"drone_position": [_world_to_grid_x(current_drone_pos.x), _world_to_grid_z(current_drone_pos.z)],
		"target_position": [_world_to_grid_x(current_target_pos.x), _world_to_grid_z(current_target_pos.z)],
		"obstacles": _format_obstacles(current_obstacles),
		"shooting_range": _calculate_shooting_range(),
		"timestamp": Time.get_time_dict_from_system()
	}
	
	if debug_mode:
		print("Sending environment update: ", environment_data)
	
	# For now, simulate AI response
	# In production, this would send to the Python agent
	_simulate_ai_response(environment_data)

func _format_obstacles(obstacles: Array[Vector3]) -> Array:
	"""Format obstacles for AI consumption with type information"""
	var formatted = []
	var obstacle_nodes = get_tree().get_nodes_in_group("obstacles")
	
	for i in range(obstacles.size()):
		var obstacle_data = {
			"position": [_world_to_grid_x(obstacles[i].x), _world_to_grid_z(obstacles[i].z)],
			"blocks_drone": false,  # Drone can fly over obstacles
			"blocks_target": true,  # Target is ground-bound
			"type": "unknown"
		}
		
		# Try to get obstacle type from the node if available
		if i < obstacle_nodes.size():
			var obstacle_node = obstacle_nodes[i]
			if obstacle_node.has_method("get_obstacle_info"):
				var info = obstacle_node.get_obstacle_info()
				obstacle_data["type"] = info.get("type", "unknown")
			elif "obstacle_type" in obstacle_node:
				obstacle_data["type"] = obstacle_node.obstacle_type
		
		formatted.append(obstacle_data)
	
	return formatted

func _world_to_grid_x(world_x: float) -> float:
	"""Convert world X coordinate to grid coordinate"""
	return world_x / 0.8 + 5.0  # 0.8 is cell_size, 5.0 is half of 10x10 grid

func _world_to_grid_z(world_z: float) -> float:
	"""Convert world Z coordinate to grid coordinate"""
	return world_z / 0.8 + 5.0  # 0.8 is cell_size, 5.0 is half of 10x10 grid

func _calculate_shooting_range() -> Dictionary:
	"""Calculate current shooting range status"""
	var distance = current_drone_pos.distance_to(current_target_pos)
	var max_range = 1.0  # Match drone's max_shooting_range (20ft)
	var optimal_range = 0.6  # Match drone's optimal_shooting_range (12ft)
	
	return {
		"distance": distance,
		"in_range": distance <= max_range,
		"optimal_range": distance <= optimal_range,
		"max_range": max_range,
		"range_percentage": (distance / max_range) * 100.0
	}

func _simulate_ai_response(environment_data: Dictionary):
	"""Simulate AI response for testing purposes"""
	# This is a placeholder - in production, this would come from the Python agent
	await get_tree().create_timer(0.1).timeout  # Simulate processing time
	
	# Calculate interception point (move towards where target will be)
	var drone_grid = environment_data["drone_position"]
	var target_grid = environment_data["target_position"]
	
	# Calculate distance and direction
	var direction_x = target_grid[0] - drone_grid[0]
	var direction_z = target_grid[1] - drone_grid[1]
	var distance = sqrt(direction_x * direction_x + direction_z * direction_z)
	
	# Predict where target will be and move there
	var predicted_x = target_grid[0] + direction_x * 0.3
	var predicted_z = target_grid[1] + direction_z * 0.3
	
	# Clamp to grid bounds
	predicted_x = clamp(predicted_x, 0, 9)
	predicted_z = clamp(predicted_z, 0, 9)
	
	# Generate more detailed reasoning based on situation
	var reasoning = ""
	var emergency_mode = false
	var confidence = 0.8
	
	if distance < 2.0:
		reasoning = "Target very close! Direct pursuit mode. Distance: " + str(round(distance * 10) / 10) + " units"
		emergency_mode = true
		confidence = 0.95
	elif distance < 4.0:
		reasoning = "Target within range. Calculating interception path. Predicting movement to (" + str(round(predicted_x * 10) / 10) + ", " + str(round(predicted_z * 10) / 10) + ")"
		confidence = 0.85
	else:
		reasoning = "Target distant. Moving to optimal position for pursuit. Distance: " + str(round(distance * 10) / 10) + " units"
		confidence = 0.7
	
	# Add obstacle awareness
	if current_obstacles.size() > 0:
		reasoning += ". Navigating through " + str(current_obstacles.size()) + " tree/rock obstacles (low-altitude challenge)"
	
	var shooting_info = _calculate_shooting_range()
	if shooting_info.in_range:
		reasoning += ". TARGET IN RANGE - engaging"
	else:
		reasoning += ". Closing to engage (range: " + str(shooting_info.distance) + ")"
	
	var simulated_response = {
		"type": "move_command",
		"target_position": [predicted_x, predicted_z],
		"reasoning": reasoning,
		"emergency_mode": emergency_mode,
		"confidence": confidence
	}
	
	ai_decision_received.emit(simulated_response)

func _on_ai_response_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	"""Handle AI response from HTTP request"""
	if response_code != 200:
		ai_error_occurred.emit("HTTP error: " + str(response_code))
		return
	
	var json = JSON.new()
	var parse_result = json.parse(body.get_string_from_utf8())
	
	if parse_result != OK:
		ai_error_occurred.emit("JSON parse error")
		return
	
	var response_data = json.data
	if debug_mode:
		print("AI Response received: ", response_data)
	
	ai_decision_received.emit(response_data)

func get_ai_status() -> Dictionary:
	"""Get current AI status"""
	return {
		"running": is_ai_running,
		"last_update": last_decision_time,
		"decision_interval": decision_interval
	}

func _exit_tree():
	"""Clean up when exiting"""
	stop_ai_agent() 
