extends Node
class_name DroneFlightController

# Controller for drone scenes - handles input and UI updates for both DroneFlight and DroneFlightFallback

@onready var drone = get_parent()  # Can be DroneFlight or DroneFlightFallback

# UI Labels - with null safety
var flight_mode_label: Label = null
var altitude_label: Label = null
var velocity_label: Label = null
var hovering_label: Label = null

# Input smoothing
var pitch_input_smooth: float = 0.0
var roll_input_smooth: float = 0.0
var yaw_input_smooth: float = 0.0
var throttle_input_smooth: float = 0.0

var input_smoothing: float = 5.0  # Higher = more responsive

# Console status fallback
var console_status_timer: float = 0.0
var console_status_interval: float = 2.0  # Print status every 2 seconds

func _ready():
	print("DroneFlightController initialized")
	
	# Find UI elements safely
	_setup_ui_references()
	
	# Connect drone signals
	if drone:
		if drone.has_signal("flight_mode_changed"):
			drone.flight_mode_changed.connect(_on_flight_mode_changed)
		if drone.has_signal("rotor_speed_changed"):
			drone.rotor_speed_changed.connect(_on_rotor_speed_changed)

func _setup_ui_references():
	"""Setup UI element references with proper error handling"""
	# Try to find UI elements
	flight_mode_label = get_node_or_null("UI/FlightStatus/FlightModeLabel")
	altitude_label = get_node_or_null("UI/FlightStatus/AltitudeLabel")
	velocity_label = get_node_or_null("UI/FlightStatus/VelocityLabel")
	hovering_label = get_node_or_null("UI/FlightStatus/HoveringLabel")
	
	# Debug output to help identify UI structure issues
	var ui_elements_found = (flight_mode_label != null) or (altitude_label != null) or (velocity_label != null) or (hovering_label != null)
	
	if not ui_elements_found:
		print("Warning: No UI elements found. Controller will work without UI.")
		print("Available UI children: ", _get_ui_structure())
		print("Controller will function for input handling only.")
	else:
		var found_count = 0
		if flight_mode_label: found_count += 1
		if altitude_label: found_count += 1  
		if velocity_label: found_count += 1
		if hovering_label: found_count += 1
		print("UI elements found: ", found_count, "/4 labels")

func _input(event):
	"""Handle key press events for flight mode switching and emergency stop"""
	if not drone:
		return
		
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				_set_drone_flight_mode("MANUAL")
			KEY_2:
				_set_drone_flight_mode("STABILIZE")
			KEY_3:
				if drone.has_method("enable_altitude_hold"):
					drone.enable_altitude_hold(true)
			KEY_4:
				if drone.has_method("enable_altitude_hold"):
					drone.enable_altitude_hold(false)
			KEY_SPACE:
				drone.emergency_shutdown()
			KEY_ESCAPE:
				drone.emergency_shutdown()

func _physics_process(delta: float):
	if not drone:
		return
	
	_handle_input(delta)
	
	# Only update UI if we have UI elements
	if flight_mode_label or altitude_label or velocity_label or hovering_label:
		_update_ui()
	else:
		# Fallback: Print status to console periodically
		console_status_timer += delta
		if console_status_timer >= console_status_interval:
			_print_console_status()
			console_status_timer = 0.0

func _handle_input(delta: float):
	"""Handle keyboard input for drone control"""
	var target_pitch = 0.0
	var target_roll = 0.0
	var target_yaw = 0.0
	var target_throttle = 0.0
	
	# Throttle (W/S)
	if Input.is_action_pressed("ui_accept") or Input.is_key_pressed(KEY_W):
		target_throttle = 1.0
	elif Input.is_key_pressed(KEY_S):
		target_throttle = -0.5
	
	# Pitch (Up/Down arrows)
	if Input.is_action_pressed("ui_up"):
		target_pitch = -1.0  # Nose down
	elif Input.is_action_pressed("ui_down"):
		target_pitch = 1.0   # Nose up
	
	# Roll (Left/Right arrows)
	if Input.is_action_pressed("ui_left"):
		target_roll = -1.0   # Roll left
	elif Input.is_action_pressed("ui_right"):
		target_roll = 1.0    # Roll right
	
	# Yaw (A/D)
	if Input.is_key_pressed(KEY_A):
		target_yaw = -1.0    # Yaw left
	elif Input.is_key_pressed(KEY_D):
		target_yaw = 1.0     # Yaw right
	
	# Flight mode switching and emergency stop are handled in _input() method
	
	# Smooth input transitions
	pitch_input_smooth = lerp(pitch_input_smooth, target_pitch, input_smoothing * delta)
	roll_input_smooth = lerp(roll_input_smooth, target_roll, input_smoothing * delta)
	yaw_input_smooth = lerp(yaw_input_smooth, target_yaw, input_smoothing * delta)
	throttle_input_smooth = lerp(throttle_input_smooth, target_throttle, input_smoothing * delta)
	
	# Send inputs to drone
	drone.set_control_input(
		pitch_input_smooth,
		roll_input_smooth,
		yaw_input_smooth,
		throttle_input_smooth
	)

func _update_ui():
	"""Update UI labels with current flight status"""
	if not drone or not drone.has_method("get_flight_status"):
		return
	
	var status = drone.get_flight_status()
	
	# Update labels with null checks
	if flight_mode_label:
		flight_mode_label.text = "Flight Mode: " + status.flight_mode
		# Update flight mode label color
		match status.flight_mode:
			"MANUAL":
				flight_mode_label.modulate = Color.RED
			"STABILIZE":
				flight_mode_label.modulate = Color.GREEN
			"ALTITUDE_HOLD":
				flight_mode_label.modulate = Color.CYAN
			"LOITER":
				flight_mode_label.modulate = Color.YELLOW
			"RTL":
				flight_mode_label.modulate = Color.MAGENTA
			_:
				flight_mode_label.modulate = Color.WHITE
	
	if altitude_label:
		altitude_label.text = "Altitude: %.1f m" % status.altitude
	
	if velocity_label:
		velocity_label.text = "Velocity: %.1f m/s" % status.velocity.length()
	
	if hovering_label:
		# Update status
		if status.hovering:
			hovering_label.text = "Status: Hovering"
			hovering_label.modulate = Color.GREEN
		elif status.velocity.length() > 0.5:
			hovering_label.text = "Status: Flying"
			hovering_label.modulate = Color.YELLOW
		elif status.altitude > 0.1:
			hovering_label.text = "Status: Airborne"
			hovering_label.modulate = Color.CYAN
		else:
			hovering_label.text = "Status: Landed"
			hovering_label.modulate = Color.WHITE

func _on_flight_mode_changed(mode: String):
	"""Handle flight mode change signal"""
	print("Flight mode changed to: ", mode)

func _on_rotor_speed_changed(rotor_index: int, speed: float):
	"""Handle rotor speed change - could be used for audio/visual effects"""
	# This could trigger rotor sound effects or visual spinning
	pass

# Public methods for external control (AI interface)
func set_ai_control_input(pitch: float, roll: float, yaw: float, throttle: float):
	"""Allow AI to control the drone directly"""
	drone.set_control_input(pitch, roll, yaw, throttle)

func get_drone_status() -> Dictionary:
	"""Get current drone status for AI"""
	if drone:
		return drone.get_flight_status()
	else:
		return {}

func set_ai_flight_mode(mode_name: String):
	"""Allow AI to change flight mode"""
	if drone:
		_set_drone_flight_mode(mode_name)

func _set_drone_flight_mode(mode_name: String):
	"""Set flight mode - compatible with both DroneFlight and DroneFlightFallback"""
	if not drone or not drone.has_method("set_flight_mode"):
		return
		
	# Both drone classes use the same FlightMode enum values
	# We can access them through the class directly
	var mode_value = null
	match mode_name:
		"MANUAL":
			mode_value = 0  # FlightMode.MANUAL
		"STABILIZE":
			mode_value = 1  # FlightMode.STABILIZE
		"ALTITUDE_HOLD":
			mode_value = 2  # FlightMode.ALTITUDE_HOLD
		"LOITER":
			mode_value = 3  # FlightMode.LOITER
		"RTL":
			mode_value = 4  # FlightMode.RTL
	
	if mode_value != null:
		drone.set_flight_mode(mode_value)
		print("Set flight mode to: ", mode_name)
	else:
		print("Warning: Unknown flight mode: ", mode_name)

func _get_ui_structure() -> String:
	"""Helper function to debug UI structure"""
	var ui_node = get_node_or_null("UI")
	if not ui_node:
		return "No UI node found"
	
	var structure = "UI children: "
	for child in ui_node.get_children():
		structure += child.name + " "
		if child.name == "FlightStatus":
			structure += "{ FlightStatus children: "
			for subchild in child.get_children():
				structure += subchild.name + " "
			structure += "} "
	
	return structure

func _print_console_status():
	"""Print drone status to console when no UI is available"""
	if not drone or not drone.has_method("get_flight_status"):
		return
		
	var status = drone.get_flight_status()
	var status_text = "DRONE STATUS | Mode: %s | Alt: %.1fm | Vel: %.1fm/s" % [
		status.flight_mode,
		status.altitude, 
		status.velocity.length()
	]
	
	if status.hovering:
		status_text += " | HOVERING"
	elif status.velocity.length() > 0.5:
		status_text += " | FLYING"
	
	print(status_text)
