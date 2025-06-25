extends Node
class_name DroneFlightController

# Controller for the DroneFlight scene - handles input and UI updates

@onready var drone: DroneFlight = get_parent()
@onready var flight_mode_label: Label = $UI/FlightStatus/FlightModeLabel
@onready var altitude_label: Label = $UI/FlightStatus/AltitudeLabel
@onready var velocity_label: Label = $UI/FlightStatus/VelocityLabel
@onready var hovering_label: Label = $UI/FlightStatus/HoveringLabel

# Input smoothing
var pitch_input_smooth: float = 0.0
var roll_input_smooth: float = 0.0
var yaw_input_smooth: float = 0.0
var throttle_input_smooth: float = 0.0

var input_smoothing: float = 5.0  # Higher = more responsive

func _ready():
	print("DroneFlightController initialized")
	
	# Connect drone signals
	if drone:
		drone.flight_mode_changed.connect(_on_flight_mode_changed)
		drone.rotor_speed_changed.connect(_on_rotor_speed_changed)

func _physics_process(delta: float):
	if not drone:
		return
	
	_handle_input(delta)
	_update_ui()

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
	
	# Flight mode switching
	if Input.is_key_just_pressed(KEY_1):
		drone.set_flight_mode(DroneFlight.FlightMode.MANUAL)
	elif Input.is_key_just_pressed(KEY_2):
		drone.set_flight_mode(DroneFlight.FlightMode.STABILIZE)
	elif Input.is_key_just_pressed(KEY_3):
		drone.enable_altitude_hold(true)
	elif Input.is_key_just_pressed(KEY_4):
		drone.enable_altitude_hold(false)
	
	# Emergency stop
	if Input.is_action_just_pressed("ui_cancel") or Input.is_key_just_pressed(KEY_SPACE):
		drone.emergency_shutdown()
	
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
	if not drone:
		return
	
	var status = drone.get_flight_status()
	
	# Update labels
	flight_mode_label.text = "Flight Mode: " + status.flight_mode
	altitude_label.text = "Altitude: %.1f m" % status.altitude
	velocity_label.text = "Velocity: %.1f m/s" % status.velocity.length()
	
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

func set_ai_flight_mode(mode: DroneFlight.FlightMode):
	"""Allow AI to change flight mode"""
	if drone:
		drone.set_flight_mode(mode) 