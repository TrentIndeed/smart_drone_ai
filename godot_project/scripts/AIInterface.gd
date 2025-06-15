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
		"timestamp": Time.get_time_dict_from_system()
	}
	
	if debug_mode:
		print("Sending environment update: ", environment_data)
	
	# For now, simulate AI response
	# In production, this would send to the Python agent
	_simulate_ai_response(environment_data)

func _format_obstacles(obstacles: Array[Vector3]) -> Array:
	"""Format obstacles for AI consumption"""
	var formatted = []
	for obstacle in obstacles:
		formatted.append([_world_to_grid_x(obstacle.x), _world_to_grid_z(obstacle.z)])  # Use x,z for ground plane
	return formatted

func _world_to_grid_x(world_x: float) -> float:
	"""Convert world X coordinate to grid coordinate"""
	return world_x / 0.8 + 5.0  # 0.8 is cell_size, 5.0 is half of 10x10 grid

func _world_to_grid_z(world_z: float) -> float:
	"""Convert world Z coordinate to grid coordinate"""
	return world_z / 0.8 + 5.0  # 0.8 is cell_size, 5.0 is half of 10x10 grid

func _simulate_ai_response(environment_data: Dictionary):
	"""Simulate AI response for testing purposes"""
	# This is a placeholder - in production, this would come from the Python agent
	await get_tree().create_timer(0.1).timeout  # Simulate processing time
	
	# Calculate interception point (move towards where target will be)
	var drone_grid = environment_data["drone_position"]
	var target_grid = environment_data["target_position"]
	
	# Simple interception: move towards target with slight prediction
	var direction_x = target_grid[0] - drone_grid[0]
	var direction_z = target_grid[1] - drone_grid[1]
	
	# Predict where target will be and move there
	var predicted_x = target_grid[0] + direction_x * 0.3
	var predicted_z = target_grid[1] + direction_z * 0.3
	
	# Clamp to grid bounds
	predicted_x = clamp(predicted_x, 0, 10)
	predicted_z = clamp(predicted_z, 0, 10)
	
	var simulated_response = {
		"type": "move_command",
		"target_position": [predicted_x, predicted_z],
		"reasoning": "Simulated AI: Intercepting target at predicted position",
		"emergency_mode": false,
		"confidence": 0.8
	}
	
	ai_decision_received.emit(simulated_response)

func _on_ai_response_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
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
