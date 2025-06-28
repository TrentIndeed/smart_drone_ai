@tool
extends RigidBody3D
class_name Drone

# Pure Aerodynamic Drone Flight - Uses AeroBody3D for realistic physics

signal rotor_speed_changed(rotor_index: int, speed: float)
signal flight_mode_changed(mode: String)
signal collision_detected(position: Vector3)
signal target_shot(position: Vector3)
signal shot_fired(from_position: Vector3, to_position: Vector3)
signal target_reached(position: Vector3)
signal emergency_activated()
signal boundary_warning(distance: float, position: Vector3)

enum FlightMode {
	MANUAL,
	STABILIZE,
	ALTITUDE_HOLD,
	LOITER,
	RTL  # Return to Launch
}

@export_group("Drone Configuration")
@export var rotor_count: int = 4
@export var rotor_spacing: float = 0.5  # Distance from center to rotor
@export var max_rotor_speed: float = 1000.0  # RPM
@export var rotor_response_time: float = 0.2  # Time to reach target speed

@export_group("Flight Parameters")
@export var hover_throttle: float = 0.98  # Throttle needed to hover
@export var max_tilt_angle: float = 15.0  # Maximum tilt in degrees
@export var max_yaw_rate: float = 90.0  # Max yaw rate in degrees/second
@export var max_climb_rate: float = 3.0  # Max climb rate in m/s
@export var thrust_force: float = 25.0  # Total thrust force in Newtons

@export_group("Stability")
@export var stability_factor: float = 2.0  # How aggressively to stabilize
@export var auto_level: bool = true  # Automatically level when no input
@export var altitude_hold_enabled: bool = false
@export var target_altitude: float = 0.0

@export_group("Control Input")
@export var pitch_input: float = 0.0  # -1 to 1 (forward/backward)
@export var roll_input: float = 0.0   # -1 to 1 (left/right)
@export var yaw_input: float = 0.0    # -1 to 1 (rotate left/right)
@export var throttle_input: float = 0.0  # 0 to 1 (up/down)

# Flight state
var current_flight_mode: FlightMode = FlightMode.STABILIZE
var rotor_speeds: Array[float] = []
var target_rotor_speeds: Array[float] = []

# AI interface variables
var target_position: Vector3 = Vector3.ZERO
var emergency_mode: bool = false
var emergency_timer: float = 0.0
var max_emergency_time: float = 5.0

# Shooting system
var shooting_cooldown: float = 0.0
var shooting_cooldown_time: float = 0.5
var max_shooting_range: float = 1.0
var is_aiming: bool = false
var aiming_timer: float = 0.0
var aiming_time: float = 0.2
var current_target: Node3D = null

# Simple PID-like controllers for aerodynamic flight control
var pitch_error_sum: float = 0.0
var roll_error_sum: float = 0.0
var yaw_error_sum: float = 0.0
var altitude_error_sum: float = 0.0

var last_pitch_error: float = 0.0
var last_roll_error: float = 0.0
var last_yaw_error: float = 0.0
var last_altitude_error: float = 0.0

# PID gains (conservative for stability)
var pitch_p: float = 0.05
var pitch_i: float = 0.001
var pitch_d: float = 0.01

var roll_p: float = 0.05
var roll_i: float = 0.001
var roll_d: float = 0.01

var yaw_p: float = 0.03
var yaw_i: float = 0.0005
var yaw_d: float = 0.005

var altitude_p: float = 0.05
var altitude_i: float = 0.001
var altitude_d: float = 0.01

# Internal state
var hover_detected: bool = false
var ground_effect_height: float = 1.0

# Boundary detection
@export var map_size: Vector2 = Vector2(10, 10)  # Map dimensions (X, Z)
@export var boundary_warning_distance: float = 1.0  # Distance from edge to start warning
@export var boundary_emergency_distance: float = 0.2  # Distance from edge for emergency return
var boundary_warning_active: bool = false
var last_boundary_warning: float = 0.0
var boundary_warning_cooldown: float = 2.0

func _init():
	# Initialize rotor speed arrays
	rotor_speeds.resize(rotor_count)
	target_rotor_speeds.resize(rotor_count)
	for i in range(rotor_count):
		rotor_speeds[i] = 0.0
		target_rotor_speeds[i] = 0.0
	
	# Start with no control inputs
	throttle_input = 0.0
	pitch_input = 0.0
	roll_input = 0.0
	yaw_input = 0.0

func _ready():
	print("DroneFlightAdapter initialized with ", rotor_count, " rotors")
	print("Node type: RigidBody3D")
	print("Using manual force application for drone physics")
	
	# Add to drones group for GameManager to find
	add_to_group("drones")
	
	# Set up drone-specific physics properties
	mass = 1.0  # 1.0kg drone
	
	# Set collision layers properly
	collision_layer = 1  # Drone layer
	collision_mask = 2   # Collide with obstacles/ground
	
	# Set default flight mode to STABILIZE for stable hovering
	current_flight_mode = FlightMode.STABILIZE
	
	# Configure RigidBody3D properties for drone flight
	print("Configuring RigidBody3D-specific properties")
	# No special properties needed - using manual force application
	
	# Set initial control inputs to hover
	throttle_input = 0.0  # This gets added to hover_throttle
	pitch_input = 0.0
	roll_input = 0.0
	yaw_input = 0.0
	
	# No debug visualization needed for RigidBody3D approach
	print("Using manual force application for drone physics")
	
	# Initialize with no target position to trigger fallback behavior
	target_position = Vector3.ZERO
	
	# Start looking for targets immediately
	call_deferred("_find_and_track_target")
	
	print("Drone initialized with hover throttle: ", hover_throttle)

func _physics_process(delta: float):
	# Skip processing in editor or if simulation not running
	if Engine.is_editor_hint():
		return
		
	var game_manager = get_node_or_null("/root/GameManager")
	if game_manager and game_manager.has_method("get_simulation_stats"):
		var stats = game_manager.get_simulation_stats()
		if not stats.get("running", false):
			return  # Don't process when simulation is stopped
	
	# Update flight control using RigidBody3D with manual force application
	_update_flight_control(delta)
	
	_update_rotor_speeds(delta)
	_detect_flight_state()
	_check_boundaries(delta)
	_check_stability(delta)
	_update_ai_systems(delta)

func _integrate_forces(state: PhysicsDirectBodyState3D):
	"""Apply thrust and control forces manually"""
	_apply_thrust_forces(state)
	_apply_control_forces(state)

func _update_flight_control(delta: float):
	"""Flight control using RigidBody3D with manual force application"""
	# Update flight modes first to calculate control inputs
	match current_flight_mode:
		FlightMode.MANUAL:
			_manual_flight_control()
		FlightMode.STABILIZE:
			_stabilized_flight_control(delta)
		FlightMode.ALTITUDE_HOLD:
			_altitude_hold_control(delta)
		FlightMode.LOITER:
			_loiter_control(delta)
		FlightMode.RTL:
			_return_to_launch_control(delta)
	
	# Debug output every 3 seconds
	if fmod(Time.get_time_dict_from_system().get("second", 0), 3) == 0:
		print("RigidBody3D control - Pitch:", pitch_input, " Roll:", roll_input, " Yaw:", yaw_input, " Throttle:", throttle_input)

func _manual_flight_control():
	"""Direct control - no stabilization"""
	var base_throttle = hover_throttle + (throttle_input * 0.02)
	
	# Calculate rotor mix for manual control
	_calculate_rotor_mix(
		base_throttle,
		pitch_input * 0.3,
		roll_input * 0.3,
		yaw_input * 0.3
	)

func _stabilized_flight_control(delta: float):
	"""Stabilized flight with attitude hold"""
	var current_rotation = rotation_degrees
	
	# Reset PID if drone is extremely tilted (safety measure)
	if abs(current_rotation.x) > 60 or abs(current_rotation.z) > 60:
		pitch_error_sum = 0.0
		roll_error_sum = 0.0
		last_pitch_error = 0.0
		last_roll_error = 0.0
		print("Resetting PID due to extreme tilt: ", current_rotation)
	
	# Calculate desired attitude from input
	var desired_pitch = pitch_input * max_tilt_angle
	var desired_roll = roll_input * max_tilt_angle
	var desired_yaw_rate = yaw_input * max_yaw_rate
	
	# Auto-level when no input (with stronger damping)
	if auto_level:
		if abs(pitch_input) < 0.1:
			desired_pitch = -current_rotation.x * 0.5  # Return to level gradually
		if abs(roll_input) < 0.1:
			desired_roll = -current_rotation.z * 0.5   # Return to level gradually
	
	# Simple PID control for attitude
	var pitch_error = desired_pitch - current_rotation.x
	var roll_error = desired_roll - current_rotation.z
	
	var pitch_correction = _update_pid_pitch(pitch_error, delta)
	var roll_correction = _update_pid_roll(roll_error, delta)
	
	var yaw_correction = yaw_input * 0.5  # Direct yaw control
	
	# Calculate base throttle with altitude hold
	var base_throttle = hover_throttle
	if altitude_hold_enabled:
		var altitude_error = target_altitude - position.y
		var altitude_correction = _update_pid_altitude(altitude_error, delta)
		base_throttle += altitude_correction
	else:
		base_throttle += (throttle_input * 0.1)  # Manual throttle adjustment
	
	# Apply rotor mixing
	_calculate_rotor_mix(base_throttle, pitch_correction, roll_correction, yaw_correction)

func _altitude_hold_control(delta: float):
	"""Altitude hold mode"""
	altitude_hold_enabled = true
	_stabilized_flight_control(delta)

func _loiter_control(delta: float):
	"""Loiter mode - hold position"""
	if target_position == Vector3.ZERO:
		target_position = position  # Use current position if no target set
	
	var position_error = target_position - position
	
	# Convert position error to pitch/roll commands
	pitch_input = clamp(-position_error.z * 0.5, -1.0, 1.0)
	roll_input = clamp(position_error.x * 0.5, -1.0, 1.0)
	
	# Hold altitude
	target_altitude = target_position.y
	altitude_hold_enabled = true
	
	_stabilized_flight_control(delta)

func _return_to_launch_control(delta: float):
	"""Return to launch mode"""
	target_position = Vector3.ZERO  # Return to origin
	target_altitude = 2.0  # Safe altitude
	_loiter_control(delta)

func _calculate_rotor_mix(throttle: float, pitch: float, roll: float, yaw: float):
	"""Calculate individual rotor speeds based on control inputs"""
	if rotor_count != 4:
		return  # Only support quadcopter for now
	
	# Quadcopter X configuration
	# Front motors: 0=front-right, 1=front-left
	# Rear motors: 2=rear-left, 3=rear-right
	# Motors 1,3 spin CW, motors 0,2 spin CCW
	
	var motor_throttle = [
		throttle - pitch + roll - yaw,  # Front-right (CCW)
		throttle - pitch - roll + yaw,  # Front-left (CW)
		throttle + pitch - roll - yaw,  # Rear-left (CCW)
		throttle + pitch + roll + yaw   # Rear-right (CW)
	]
	
	# Set target rotor speeds
	for i in range(rotor_count):
		target_rotor_speeds[i] = clamp(motor_throttle[i] * max_rotor_speed, 0.0, max_rotor_speed)

func _update_rotor_speeds(delta: float):
	"""Update actual rotor speeds towards target speeds"""
	for i in range(rotor_count):
		var speed_diff = target_rotor_speeds[i] - rotor_speeds[i]
		var speed_change = speed_diff * (delta / rotor_response_time)
		rotor_speeds[i] += speed_change
		rotor_speeds[i] = clamp(rotor_speeds[i], 0.0, max_rotor_speed)
		
		# Emit signal when speed changes significantly
		if abs(speed_change) > 10.0:
			rotor_speed_changed.emit(i, rotor_speeds[i])

func _get_rotor_positions() -> Array[Vector3]:
	"""Get rotor positions for quadcopter X configuration"""
	var positions: Array[Vector3] = []
	var half_spacing = rotor_spacing * 0.707  # 45-degree offset for X config
	
	positions.append(Vector3(half_spacing, 0, -half_spacing))   # Front-right
	positions.append(Vector3(-half_spacing, 0, -half_spacing))  # Front-left
	positions.append(Vector3(-half_spacing, 0, half_spacing))   # Rear-left
	positions.append(Vector3(half_spacing, 0, half_spacing))    # Rear-right
	
	return positions

func _update_pid_pitch(error: float, delta: float) -> float:
	"""Update pitch PID controller"""
	pitch_error_sum += error * delta
	pitch_error_sum = clamp(pitch_error_sum, -1.0, 1.0)  # Prevent windup
	
	var error_derivative = (error - last_pitch_error) / delta
	last_pitch_error = error
	
	return (pitch_p * error) + (pitch_i * pitch_error_sum) + (pitch_d * error_derivative)

func _update_pid_roll(error: float, delta: float) -> float:
	"""Update roll PID controller"""
	roll_error_sum += error * delta
	roll_error_sum = clamp(roll_error_sum, -1.0, 1.0)  # Prevent windup
	
	var error_derivative = (error - last_roll_error) / delta
	last_roll_error = error
	
	return (roll_p * error) + (roll_i * roll_error_sum) + (roll_d * error_derivative)

func _update_pid_altitude(error: float, delta: float) -> float:
	"""Update altitude PID controller"""
	altitude_error_sum += error * delta
	altitude_error_sum = clamp(altitude_error_sum, -2.0, 2.0)  # Prevent windup
	
	var error_derivative = (error - last_altitude_error) / delta
	last_altitude_error = error
	
	return (altitude_p * error) + (altitude_i * altitude_error_sum) + (altitude_d * error_derivative)

func _detect_flight_state():
	"""Detect current flight state for system monitoring"""
	var velocity_magnitude = linear_velocity.length()
	var altitude = position.y
	
	hover_detected = velocity_magnitude < 0.5 and altitude > 0.2

func _check_boundaries(delta: float):
	"""Check if drone is approaching map boundaries"""
	var half_map = map_size * 0.5
	var pos = Vector2(position.x, position.z)
	
	# Calculate distance to nearest boundary
	var dist_to_boundary = min(
		min(half_map.x - abs(pos.x), half_map.y - abs(pos.y)),
		min(pos.x + half_map.x, pos.y + half_map.y)
	)
	
	if dist_to_boundary < boundary_emergency_distance:
		if not emergency_mode:
			print("Emergency boundary breach - returning to center")
			emergency_mode = true
			emergency_timer = 0.0
			emergency_activated.emit()
		
		# Emergency return to center
		target_position = Vector3.ZERO
		current_flight_mode = FlightMode.RTL
		
	elif dist_to_boundary < boundary_warning_distance:
		if not boundary_warning_active and Time.get_time_dict_from_system().get("second", 0) - last_boundary_warning > boundary_warning_cooldown:
			boundary_warning_active = true
			last_boundary_warning = Time.get_time_dict_from_system().get("second", 0)
			boundary_warning.emit(dist_to_boundary, position)
			print("Boundary warning - distance: ", dist_to_boundary)
	else:
		boundary_warning_active = false
		if emergency_mode:
			emergency_mode = false
			print("Returned to safe area")

func _check_stability(delta: float):
	"""Check drone stability and trigger emergency if needed"""
	var rotation_deg = rotation_degrees
	var max_safe_angle = 75.0  # Emergency only at very extreme angles
	
	if abs(rotation_deg.x) > max_safe_angle or abs(rotation_deg.z) > max_safe_angle:
		if not emergency_mode:
			print("Emergency instability detected - angles: ", rotation_deg)
			emergency_mode = true
			emergency_timer = 0.0
			emergency_activated.emit()
			
			# Reset control inputs and stabilize
			pitch_input = 0.0
			roll_input = 0.0
			yaw_input = 0.0
			throttle_input = 0.3
			
			# Force stabilize mode
			current_flight_mode = FlightMode.STABILIZE
	
	if emergency_mode:
		emergency_timer += delta
		if emergency_timer > max_emergency_time:
			print("Emergency recovery timeout - resetting position")
			position = Vector3(0, 2, 0)  # Teleport to safe position
			rotation = Vector3.ZERO
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
			emergency_mode = false

func _update_ai_systems(delta: float):
	"""Update AI-related systems"""
	# Update shooting cooldown
	if shooting_cooldown > 0:
		shooting_cooldown -= delta
	
	# Update aiming
	if is_aiming:
		aiming_timer += delta
		if aiming_timer >= aiming_time:
			_execute_shot()
			is_aiming = false
			aiming_timer = 0.0
	
	# Simple AI behavior - move towards target if no target is set
	if target_position == Vector3.ZERO:
		_find_and_track_target()

# Public API for AI interface
func get_drone_position() -> Vector3:
	return position

func get_drone_rotation() -> Vector3:
	return rotation_degrees

func get_drone_velocity() -> Vector3:
	return linear_velocity

func set_target(pos: Vector3):
	target_position = pos
	if current_flight_mode != FlightMode.MANUAL:
		current_flight_mode = FlightMode.LOITER

func set_target_position(pos: Vector3):
	"""Set target position (AI interface compatibility)"""
	set_target(pos)

func set_flight_mode(mode: String):
	match mode.to_upper():
		"MANUAL":
			current_flight_mode = FlightMode.MANUAL
		"STABILIZE":
			current_flight_mode = FlightMode.STABILIZE
		"ALTITUDE_HOLD":
			current_flight_mode = FlightMode.ALTITUDE_HOLD
		"LOITER":
			current_flight_mode = FlightMode.LOITER
		"RTL":
			current_flight_mode = FlightMode.RTL
	
	flight_mode_changed.emit(mode)

func set_control_input(pitch: float, roll: float, yaw: float, throttle: float):
	pitch_input = clamp(pitch, -1.0, 1.0)
	roll_input = clamp(roll, -1.0, 1.0)
	yaw_input = clamp(yaw, -1.0, 1.0)
	throttle_input = clamp(throttle, 0.0, 1.0)

func aim_at_target(target: Node3D):
	if shooting_cooldown <= 0 and target:
		current_target = target
		is_aiming = true
		aiming_timer = 0.0

func _execute_shot():
	if current_target and is_instance_valid(current_target):
		var distance = position.distance_to(current_target.position)
		if distance <= max_shooting_range:
			shot_fired.emit(position, current_target.position)
			target_shot.emit(current_target.position)
			shooting_cooldown = shooting_cooldown_time
			print("Shot fired at target at distance: ", distance)
		else:
			print("Target out of range: ", distance, " > ", max_shooting_range)

func is_stable() -> bool:
	var rotation_deg = rotation_degrees
	return abs(rotation_deg.x) < 30 and abs(rotation_deg.z) < 30

func get_distance_to_target() -> float:
	if current_target and is_instance_valid(current_target):
		return position.distance_to(current_target.position)
	return -1.0

func reset_position(pos: Vector3):
	"""Reset drone to specified position"""
	position = pos
	target_position = Vector3.ZERO
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	rotation = Vector3.ZERO
	emergency_mode = false
	
	# Reset all PID controllers
	pitch_error_sum = 0.0
	roll_error_sum = 0.0
	yaw_error_sum = 0.0
	altitude_error_sum = 0.0
	last_pitch_error = 0.0
	last_roll_error = 0.0
	last_yaw_error = 0.0
	last_altitude_error = 0.0
	
	# Reset rotor speeds
	for i in range(rotor_count):
		rotor_speeds[i] = 0.0
		target_rotor_speeds[i] = 0.0
	
	# Reset control inputs
	pitch_input = 0.0
	roll_input = 0.0
	yaw_input = 0.0
	throttle_input = 0.0
	
	print("Drone reset to position: ", pos)

func _apply_thrust_forces(state: PhysicsDirectBodyState3D):
	"""Apply thrust forces from rotors"""
	var total_thrust = 0.0
	for speed in rotor_speeds:
		total_thrust += speed / max_rotor_speed  # Normalize to 0-1
	
	# Apply upward thrust force (compensate for gravity + additional thrust)
	var base_thrust = mass * 9.8 * hover_throttle  # Gravity compensation
	var additional_thrust = mass * 9.8 * throttle_input  # Additional thrust
	var total_force = base_thrust + additional_thrust
	
	var thrust_vector = transform.basis.y * total_force
	state.apply_central_force(thrust_vector)

func _apply_control_forces(state: PhysicsDirectBodyState3D):
	"""Apply control torques for attitude control"""
	var rotor_positions = _get_rotor_positions()
	
	# Calculate individual rotor forces
	var base_thrust = hover_throttle + throttle_input
	
	# Apply rotor mixing for attitude control
	var motor_throttle = [
		base_thrust - pitch_input * 0.3 + roll_input * 0.3 - yaw_input * 0.3,  # Front-right
		base_thrust - pitch_input * 0.3 - roll_input * 0.3 + yaw_input * 0.3,  # Front-left
		base_thrust + pitch_input * 0.3 - roll_input * 0.3 - yaw_input * 0.3,  # Rear-left
		base_thrust + pitch_input * 0.3 + roll_input * 0.3 + yaw_input * 0.3   # Rear-right
	]
	
	# Apply forces at rotor positions
	for i in range(min(rotor_count, rotor_positions.size())):
		var rotor_force = clamp(motor_throttle[i], 0.0, 2.0) * mass * 9.8 * 0.25  # Quarter of total thrust per rotor
		var force_vector = transform.basis.y * rotor_force
		var rotor_world_pos = transform.basis * rotor_positions[i]
		state.apply_force(force_vector, rotor_world_pos)

func _find_and_track_target():
	"""Find target and start tracking it"""
	var target_node = get_tree().get_first_node_in_group("target")
	if target_node and is_instance_valid(target_node):
		target_position = target_node.position
		current_flight_mode = FlightMode.LOITER
		print("Drone found target at: ", target_position)
	else:
		# No target found - hover in place
		if current_flight_mode != FlightMode.STABILIZE:
			current_flight_mode = FlightMode.STABILIZE
			print("No target found - hovering")

func _on_body_entered(body):
	if body != self:
		collision_detected.emit(position)
		print("Collision detected with: ", body.name)
