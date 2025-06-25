extends Node

# AI Interface for communicating with external AI agent
# Handles HTTP requests and translates commands to drone actions

var http_server: TCPServer
var clients: Array = []
var drone_controller: Node = null
var ai_bridge_controller: Node = null
var port: int = 8080

func _ready():
	print("AIInterface initializing...")
	
	# Add to group for easy finding
	add_to_group("ai_interface")
	
	# Find the drone controller with retry logic
	await _find_drone_controller()
	
	if not drone_controller:
		print("ERROR: No drone found in 'drones' group!")
		return
	
	print("Found drone controller: ", drone_controller.name)
	
	# Look for AI bridge controller
	ai_bridge_controller = get_tree().get_first_node_in_group("ai_bridge")
	if ai_bridge_controller:
		print("Found AI bridge controller: ", ai_bridge_controller.name)
	else:
		print("No AI bridge controller found")
	
	# Start HTTP server
	http_server = TCPServer.new()
	var result = http_server.listen(port)
	if result == OK:
		print("AI Interface server started on port ", port)
	else:
		print("Failed to start AI Interface server: ", result)
	
	# Connect to drone signals for event reporting
	if drone_controller:
		# Connect aerodynamic drone signals
		if drone_controller.has_signal("collision_detected"):
			drone_controller.collision_detected.connect(_on_collision_detected)
		if drone_controller.has_signal("target_reached"):
			drone_controller.target_reached.connect(_on_target_reached)
		if drone_controller.has_signal("flight_mode_changed"):
			drone_controller.flight_mode_changed.connect(_on_flight_mode_changed)
		if drone_controller.has_signal("emergency_activated"):
			drone_controller.emergency_activated.connect(_on_emergency_activated)
		if drone_controller.has_signal("shot_fired"):
			drone_controller.shot_fired.connect(_on_shot_fired)

func _process(_delta):
	# Accept new connections
	if http_server and http_server.is_connection_available():
		var client = http_server.take_connection()
		clients.append(client)
		print("New AI client connected")
	
	# Process existing connections
	for i in range(clients.size() - 1, -1, -1):
		var client = clients[i]
		if client.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			clients.remove_at(i)
			continue
		
		if client.get_available_bytes() > 0:
			var request = client.get_utf8_string(client.get_available_bytes())
			_handle_http_request(client, request)

func _handle_http_request(client: StreamPeerTCP, request: String):
	"""Handle incoming HTTP request from AI agent"""
	print("Received AI request: ", request.substr(0, 200), "...")
	
	var response_data = {}
	var status_code = 200
	
	# Parse HTTP request
	var lines = request.split("\n")
	if lines.size() == 0:
		response_data = {"error": "Empty request"}
		status_code = 400
	else:
		var request_line = lines[0]
		var parts = request_line.split(" ")
		
		if parts.size() < 2:
			response_data = {"error": "Invalid request format"}
			status_code = 400
		else:
			var method = parts[0]
			var path = parts[1]
			
			# Extract JSON body if present
			var body = ""
			var body_start = request.find("\r\n\r\n")
			if body_start != -1:
				body = request.substr(body_start + 4)
			
			# Route the request
			if method == "GET" and path == "/status":
				response_data = _get_comprehensive_status()
			elif method == "POST" and path == "/command":
				response_data = _process_command(body)
			elif method == "GET" and path == "/health":
				response_data = {"status": "healthy", "timestamp": Time.get_unix_time_from_system()}
			else:
				response_data = {"error": "Endpoint not found"}
				status_code = 404
	
	# Send HTTP response
	_send_http_response(client, response_data, status_code)

func _send_http_response(client: StreamPeerTCP, data: Dictionary, status_code: int = 200):
	"""Send HTTP response to client"""
	var json_string = JSON.stringify(data)
	var response = "HTTP/1.1 " + str(status_code) + " OK\r\n"
	response += "Content-Type: application/json\r\n"
	response += "Content-Length: " + str(json_string.length()) + "\r\n"
	response += "Access-Control-Allow-Origin: *\r\n"
	response += "\r\n"
	response += json_string
	
	client.put_data(response.to_utf8_buffer())

func _get_comprehensive_status() -> Dictionary:
	"""Get comprehensive drone and environment status"""
	if not drone_controller:
		return {"error": "No drone controller available"}
	
	# Get aerodynamic drone status
	var drone_status = {}
	if drone_controller.has_method("get_flight_status"):
		drone_status = drone_controller.get_flight_status()
	else:
		# Fallback basic status
		drone_status = {
			"position": drone_controller.global_position,
			"velocity": Vector3.ZERO,
			"flight_mode": "unknown",
			"emergency_mode": false
		}
	
	# Get navigation status
	var nav_status = {}
	if ai_bridge_controller and ai_bridge_controller.has_method("get_navigation_status"):
		nav_status = ai_bridge_controller.get_navigation_status()
	
	# Get shooting system status
	var shooting_status = {}
	if drone_controller.has_method("get_shooting_status"):
		shooting_status = drone_controller.get_shooting_status()
	
	# Get environment information
	var environment = _get_environment_info()
	
	return {
		"drone": drone_status,
		"navigation": nav_status,
		"shooting": shooting_status,
		"environment": environment,
		"timestamp": Time.get_unix_time_from_system()
	}

func _process_command(json_body: String) -> Dictionary:
	"""Process command from AI agent"""
	if json_body.is_empty():
		return {"error": "Empty command body"}
	
	var json = JSON.new()
	var parse_result = json.parse(json_body)
	if parse_result != OK:
		return {"error": "Invalid JSON in command"}
	
	var command_data = json.data
	if not command_data.has("action"):
		return {"error": "No action specified"}
	
	var action = command_data.action
	print("Processing AI command: ", action)
	
	match action:
		"navigate_to":
			return _handle_navigate_to(command_data)
		"set_flight_mode":
			return _handle_set_flight_mode(command_data)
		"emergency_stop":
			return _handle_emergency_stop(command_data)
		"reset_position":
			return _handle_reset_position(command_data)
		"shoot_target":
			return _handle_shoot_target(command_data)
		"orbit_target":
			return _handle_orbit_target(command_data)
		"approach_target":
			return _handle_approach_target(command_data)
		"hover":
			return _handle_hover(command_data)
		"set_navigation_mode":
			return _handle_set_navigation_mode(command_data)
		_:
			return {"error": "Unknown action: " + str(action)}

func _handle_navigate_to(data: Dictionary) -> Dictionary:
	"""Handle navigation command"""
	if not data.has("target"):
		return {"error": "No target position specified"}
	
	var target = data.target
	var target_pos = Vector3.ZERO
	
	if target is Array and target.size() >= 3:
		target_pos = Vector3(target[0], target[1], target[2])
	elif target is Dictionary:
		target_pos = Vector3(
			target.get("x", 0),
			target.get("y", 0),
			target.get("z", 0)
		)
	else:
		return {"error": "Invalid target position format"}
	
	# Send to aerodynamic drone controller
	if ai_bridge_controller and ai_bridge_controller.has_method("navigate_to_target"):
		ai_bridge_controller.navigate_to_target(target_pos)
		return {"success": true, "message": "Navigation command sent", "target": target_pos}
	elif drone_controller and drone_controller.has_method("set_target_position"):
		drone_controller.set_target_position(target_pos)
		return {"success": true, "message": "Target position set", "target": target_pos}
	else:
		return {"error": "No navigation method available"}

func _handle_set_flight_mode(data: Dictionary) -> Dictionary:
	"""Handle flight mode change"""
	if not data.has("mode"):
		return {"error": "No flight mode specified"}
	
	var mode = data.mode
	if drone_controller and drone_controller.has_method("set_flight_mode"):
		drone_controller.set_flight_mode(mode)
		return {"success": true, "message": "Flight mode set to " + str(mode)}
	else:
		return {"error": "Flight mode control not available"}

func _handle_emergency_stop(_data: Dictionary) -> Dictionary:
	"""Handle emergency stop command"""
	if drone_controller and drone_controller.has_method("emergency_stop"):
		drone_controller.emergency_stop()
		return {"success": true, "message": "Emergency stop activated"}
	elif drone_controller and drone_controller.has_method("set_emergency_mode"):
		drone_controller.set_emergency_mode(true)
		return {"success": true, "message": "Emergency mode activated"}
	else:
		return {"error": "Emergency stop not available"}

func _handle_reset_position(data: Dictionary) -> Dictionary:
	"""Handle position reset command"""
	var reset_pos = Vector3(0, 1, 0)  # Default reset position
	
	if data.has("position"):
		var pos_data = data.position
		if pos_data is Array and pos_data.size() >= 3:
			reset_pos = Vector3(pos_data[0], pos_data[1], pos_data[2])
		elif pos_data is Dictionary:
			reset_pos = Vector3(
				pos_data.get("x", 0),
				pos_data.get("y", 1),
				pos_data.get("z", 0)
			)
	
	if drone_controller and drone_controller.has_method("reset_position"):
		drone_controller.reset_position(reset_pos)
		return {"success": true, "message": "Position reset", "position": reset_pos}
	else:
		return {"error": "Position reset not available"}

func _handle_shoot_target(_data: Dictionary) -> Dictionary:
	"""Handle shooting command"""
	if drone_controller and drone_controller.has_method("engage_target"):
		drone_controller.engage_target()
		return {"success": true, "message": "Target engagement initiated"}
	else:
		return {"error": "Shooting system not available"}

func _handle_orbit_target(data: Dictionary) -> Dictionary:
	"""Handle orbit command"""
	if not ai_bridge_controller:
		return {"error": "AI bridge controller not available"}
	
	if not ai_bridge_controller.has_method("orbit_target"):
		return {"error": "Orbit functionality not available"}
	
	var radius = data.get("radius", 2.0)
	var speed = data.get("speed", 1.0)
	
	ai_bridge_controller.orbit_target(radius, speed)
	return {"success": true, "message": "Orbit mode activated"}

func _handle_approach_target(data: Dictionary) -> Dictionary:
	"""Handle approach command"""
	if not ai_bridge_controller:
		return {"error": "AI bridge controller not available"}
	
	if not ai_bridge_controller.has_method("approach_target"):
		return {"error": "Approach functionality not available"}
	
	var distance = data.get("distance", 1.0)
	ai_bridge_controller.approach_target(distance)
	return {"success": true, "message": "Approach mode activated"}

func _handle_hover(_data: Dictionary) -> Dictionary:
	"""Handle hover command"""
	if ai_bridge_controller and ai_bridge_controller.has_method("set_navigation_mode"):
		ai_bridge_controller.set_navigation_mode("hovering")
		return {"success": true, "message": "Hover mode activated"}
	elif drone_controller and drone_controller.has_method("set_flight_mode"):
		drone_controller.set_flight_mode("ALTITUDE_HOLD")
		return {"success": true, "message": "Altitude hold mode activated"}
	else:
		return {"error": "Hover mode not available"}

func _handle_set_navigation_mode(data: Dictionary) -> Dictionary:
	"""Handle navigation mode change"""
	if not data.has("mode"):
		return {"error": "No navigation mode specified"}
	
	var mode = data.mode
	if ai_bridge_controller and ai_bridge_controller.has_method("set_navigation_mode"):
		ai_bridge_controller.set_navigation_mode(mode)
		return {"success": true, "message": "Navigation mode set to " + str(mode)}
	else:
		return {"error": "Navigation mode control not available"}

func _get_environment_info() -> Dictionary:
	"""Get information about the environment"""
	var scene_tree = get_tree()
	
	# Find target
	var target_node = scene_tree.get_first_node_in_group("target")
	var target_info = {}
	if target_node:
		target_info = {
			"position": target_node.global_position,
			"exists": true,
			"name": target_node.name
		}
		if target_node.has_method("get_health"):
			target_info["health"] = target_node.get_health()
	else:
		target_info = {"exists": false}
	
	# Find obstacles
	var obstacles = scene_tree.get_nodes_in_group("obstacles")
	var obstacle_info = []
	for obstacle in obstacles:
		obstacle_info.append({
			"name": obstacle.name,
			"position": obstacle.global_position
		})
	
	return {
		"target": target_info,
		"obstacles": obstacle_info,
		"map_bounds": {
			"min": Vector3(-4.0, 0, -4.0),
			"max": Vector3(4.0, 3.0, 4.0)
		}
	}

# Signal handlers for event reporting
func _on_collision_detected(position: Vector3):
	print("AI Interface: Collision detected at ", position)

func _on_target_reached(position: Vector3):
	print("AI Interface: Target reached at ", position)

func _on_flight_mode_changed(new_mode: String):
	print("AI Interface: Flight mode changed to ", new_mode)

func _on_emergency_activated():
	print("AI Interface: Emergency mode activated")

func _on_shot_fired(from_pos: Vector3, to_pos: Vector3):
	print("AI Interface: Shot fired from ", from_pos, " to ", to_pos)

func update_environment():
	"""Legacy compatibility function for GameManager"""
	# This function exists for compatibility with GameManager.gd
	# In the aerodynamic system, environment updates are handled differently
	pass

func _find_drone_controller():
	"""Find the drone controller with retry logic"""
	var max_attempts = 10
	var attempt = 0
	
	while attempt < max_attempts and not drone_controller:
		var scene_tree = get_tree()
		drone_controller = scene_tree.get_first_node_in_group("drones")
		
		if not drone_controller:
			# Try alternative ways to find the drone
			var main_scene = scene_tree.current_scene
			if main_scene:
				drone_controller = main_scene.get_node_or_null("AerodynamicDrone")
		
		if not drone_controller:
			# Try the old group name
			drone_controller = scene_tree.get_first_node_in_group("drone")
		
		if drone_controller:
			print("Found drone controller: ", drone_controller.name)
			break
		
		attempt += 1
		if attempt < max_attempts:
			print("Drone not found yet, attempt ", attempt, "/", max_attempts, " - retrying...")
			await get_tree().process_frame
		else:
			print("Failed to find drone after ", max_attempts, " attempts")
