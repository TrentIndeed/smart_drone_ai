extends VehicleBody3D
class_name DroneFlightFallback

# Fallback Drone Flight Physics - Works without aerodynamic physics plugin

signal rotor_speed_changed(rotor_index: int, speed: float)
signal flight_mode_changed(mode: String)
signal collision_detected(position: Vector3)
signal target_shot(position: Vector3)
signal shot_fired(from_position: Vector3, to_position: Vector3)
signal target_reached(position: Vector3)
signal emergency_activated()

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
@export var hover_throttle: float = 0.5  # Throttle needed to hover
@export var max_tilt_angle: float = 30.0  # Maximum tilt in degrees
@export var max_yaw_rate: float = 180.0  # Max yaw rate in degrees/second
@export var max_climb_rate: float = 5.0  # Max climb rate in m/s
@export var thrust_force: float = 60.0  # Total thrust force in Newtons

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

# Simple PID-like controllers
var pitch_error_sum: float = 0.0
var roll_error_sum: float = 0.0
var yaw_error_sum: float = 0.0
var altitude_error_sum: float = 0.0

var last_pitch_error: float = 0.0
var last_roll_error: float = 0.0
var last_yaw_error: float = 0.0
var last_altitude_error: float = 0.0

# PID gains
var pitch_p: float = 2.0
var pitch_i: float = 0.1
var pitch_d: float = 0.5

var roll_p: float = 2.0
var roll_i: float = 0.1
var roll_d: float = 0.5

var yaw_p: float = 1.0
var yaw_i: float = 0.05
var yaw_d: float = 0.2

var altitude_p: float = 1.0
var altitude_i: float = 0.1
var altitude_d: float = 0.3

# Internal state
var hover_detected: bool = false
var ground_effect_height: float = 1.0

# AI interface variables
var target_position: Vector3 = Vector3.ZERO
var emergency_mode: bool = false
var emergency_timer: float = 0.0
var max_emergency_time: float = 10.0

# Shooting system (simplified for fallback)
var shooting_cooldown: float = 0.0
var shooting_cooldown_time: float = 0.5
var max_shooting_range: float = 1.0
var is_aiming: bool = false
var aiming_timer: float = 0.0
var aiming_time: float = 0.2
var current_target: Node3D = null

func _init():
	# Initialize rotor speed arrays
	rotor_speeds.resize(rotor_count)
	target_rotor_speeds.resize(rotor_count)
	for i in range(rotor_count):
		rotor_speeds[i] = 0.0
		target_rotor_speeds[i] = 0.0

func _ready():
	print("DroneFlightFallback initialized with ", rotor_count, " rotors")
	
	# Add to drones group for GameManager to find
	add_to_group("drones")
	
	# Set up drone-specific physics properties
	mass = 2.5  # 2.5kg drone

func _physics_process(delta: float):
	# Update flight systems
	_update_flight_control(delta)
	_update_rotor_speeds(delta)
	_detect_flight_state()
	
	# Update AI systems
	_update_ai_systems(delta)

func _integrate_forces(state: PhysicsDirectBodyState3D):
	# Apply thrust forces
	_apply_thrust_forces(state)
	_apply_ground_effect(state)

func _update_flight_control(delta: float):
	"""Main flight control logic"""
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

func _manual_flight_control():
	"""Direct control - no stabilization"""
	var base_throttle = throttle_input * hover_throttle
	
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
	
	# Calculate desired attitude from input
	var desired_pitch = pitch_input * max_tilt_angle
	var desired_roll = roll_input * max_tilt_angle
	var desired_yaw_rate = yaw_input * max_yaw_rate
	
	# Auto-level when no input
	if auto_level:
		if abs(pitch_input) < 0.1:
			desired_pitch = 0.0
		if abs(roll_input) < 0.1:
			desired_roll = 0.0
	
	# Simple PID control for attitude
	var pitch_correction = _update_pid(
		desired_pitch - current_rotation.x,
		pitch_error_sum, last_pitch_error,
		pitch_p, pitch_i, pitch_d, delta
	)
	
	var roll_correction = _update_pid(
		desired_roll - current_rotation.z,
		roll_error_sum, last_roll_error,
		roll_p, roll_i, roll_d, delta
	)
	
	var yaw_correction = yaw_input * 0.5  # Direct yaw control
	
	# Base throttle
	var base_throttle = hover_throttle + (throttle_input * 0.5)
	
	# Calculate rotor mix with corrections
	_calculate_rotor_mix(
		base_throttle,
		pitch_correction * 0.3,
		roll_correction * 0.3,
		yaw_correction
	)

func _altitude_hold_control(delta: float):
	"""Altitude hold with stabilization"""
	_stabilized_flight_control(delta)
	
	if altitude_hold_enabled:
		var altitude_error = target_altitude - position.y
		var altitude_correction = _update_pid(
			altitude_error,
			altitude_error_sum, last_altitude_error,
			altitude_p, altitude_i, altitude_d, delta
		)
		
		# Apply altitude correction to all rotors
		for i in range(rotor_count):
			target_rotor_speeds[i] += altitude_correction * 0.1

func _loiter_control(delta: float):
	"""Position hold (loiter) mode"""
	_altitude_hold_control(delta)
	# TODO: Add position hold logic

func _return_to_launch_control(delta: float):
	"""Return to launch mode"""
	_altitude_hold_control(delta)
	# TODO: Add RTL navigation logic

func _update_pid(error: float, error_sum: float, last_error: float, p: float, i: float, d: float, delta: float) -> float:
	"""Simple PID controller update"""
	error_sum += error * delta
	error_sum = clamp(error_sum, -1.0, 1.0)  # Prevent windup
	
	var derivative = (error - last_error) / delta
	last_error = error
	
	return p * error + i * error_sum + d * derivative

func _calculate_rotor_mix(base_throttle: float, pitch: float, roll: float, yaw: float):
	"""Calculate individual rotor speeds for desired motion"""
	# Quadcopter mixing logic
	if rotor_count >= 4:
		target_rotor_speeds[0] = base_throttle + pitch - roll + yaw  # Front-right
		target_rotor_speeds[1] = base_throttle + pitch + roll - yaw  # Front-left
		target_rotor_speeds[2] = base_throttle - pitch + roll + yaw  # Rear-left
		target_rotor_speeds[3] = base_throttle - pitch - roll - yaw  # Rear-right
	
	# Clamp speeds to valid range
	for i in range(rotor_count):
		target_rotor_speeds[i] = clamp(target_rotor_speeds[i], 0.0, 1.0)

func _update_rotor_speeds(delta: float):
	"""Update actual rotor speeds toward targets"""
	for i in range(rotor_count):
		# Smooth speed changes
		var speed_diff = target_rotor_speeds[i] - rotor_speeds[i]
		var speed_change = speed_diff * (delta / rotor_response_time)
		rotor_speeds[i] += speed_change
		rotor_speeds[i] = clamp(rotor_speeds[i], 0.0, 1.0)
		
		# Emit signal for visual/audio feedback
		rotor_speed_changed.emit(i, rotor_speeds[i])

func _detect_flight_state():
	"""Detect current flight state"""
	var total_rotor_speed = 0.0
	for speed in rotor_speeds:
		total_rotor_speed += speed
	
	hover_detected = (total_rotor_speed > hover_throttle * rotor_count * 0.8 and 
					  linear_velocity.length() < 2.0)

func _apply_thrust_forces(state: PhysicsDirectBodyState3D):
	"""Apply thrust forces from rotors"""
	var total_thrust = 0.0
	for speed in rotor_speeds:
		total_thrust += speed
	
	# Apply upward thrust force
	var thrust_vector = global_transform.basis.y * total_thrust * thrust_force
	state.apply_central_force(thrust_vector)
	
	# Apply torque for attitude control
	var rotor_positions = _get_rotor_positions()
	for i in range(min(rotor_count, rotor_positions.size())):
		var rotor_force = rotor_speeds[i] * thrust_force / rotor_count
		var rotor_pos = rotor_positions[i]
		var local_force = Vector3(0, rotor_force, 0)
		
		# Apply force at rotor position
		state.apply_force(global_transform.basis * local_force, global_transform.basis * rotor_pos)

func _get_rotor_positions() -> Array[Vector3]:
	"""Get positions for rotors based on configuration"""
	var positions: Array[Vector3] = []
	
	match rotor_count:
		4:  # Quadcopter - X configuration
			positions = [
				Vector3(rotor_spacing, 0, -rotor_spacing),   # Front-right
				Vector3(-rotor_spacing, 0, -rotor_spacing),  # Front-left
				Vector3(-rotor_spacing, 0, rotor_spacing),   # Rear-left
				Vector3(rotor_spacing, 0, rotor_spacing)     # Rear-right
			]
		6:  # Hexacopter
			for i in range(6):
				var angle = i * PI / 3.0
				positions.append(Vector3(
					cos(angle) * rotor_spacing,
					0,
					sin(angle) * rotor_spacing
				))
		_:  # Default to quadcopter
			positions = [
				Vector3(rotor_spacing, 0, -rotor_spacing),
				Vector3(-rotor_spacing, 0, -rotor_spacing),
				Vector3(-rotor_spacing, 0, rotor_spacing),
				Vector3(rotor_spacing, 0, rotor_spacing)
			]
			rotor_count = 4
	
	return positions

func _apply_ground_effect(state: PhysicsDirectBodyState3D):
	"""Apply ground effect - increased lift near ground"""
	var height_above_ground = position.y
	
	if height_above_ground < ground_effect_height:
		var ground_effect_factor = 1.0 + (0.2 * (1.0 - height_above_ground / ground_effect_height))
		var ground_effect_force = Vector3.UP * mass * 2.0 * ground_effect_factor
		state.apply_central_force(ground_effect_force)

# Public interface for AI control
func set_flight_mode(mode: FlightMode):
	"""Set flight mode"""
	if current_flight_mode != mode:
		current_flight_mode = mode
		flight_mode_changed.emit(FlightMode.keys()[mode])
		print("Flight mode changed to: ", FlightMode.keys()[mode])

func set_control_input(pitch: float, roll: float, yaw: float, throttle: float):
	"""Set control inputs from AI or external controller"""
	pitch_input = clamp(pitch, -1.0, 1.0)
	roll_input = clamp(roll, -1.0, 1.0)
	yaw_input = clamp(yaw, -1.0, 1.0)
	throttle_input = clamp(throttle, 0.0, 1.0)

func enable_altitude_hold(enable: bool, altitude: float = 0.0):
	"""Enable or disable altitude hold"""
	altitude_hold_enabled = enable
	if enable:
		target_altitude = altitude if altitude != 0.0 else position.y
		set_flight_mode(FlightMode.ALTITUDE_HOLD)
	else:
		set_flight_mode(FlightMode.STABILIZE)

func get_flight_status() -> Dictionary:
	"""Get current flight status"""
	return {
		"flight_mode": FlightMode.keys()[current_flight_mode],
		"hovering": hover_detected,
		"altitude": position.y,
		"attitude": rotation_degrees,
		"velocity": linear_velocity,
		"rotor_speeds": rotor_speeds.duplicate(),
		"ground_effect": position.y < ground_effect_height,
		"throttle_input": throttle_input,
		"control_input": {
			"pitch": pitch_input,
			"roll": roll_input,
			"yaw": yaw_input,
			"throttle": throttle_input
		}
	}

func emergency_shutdown():
	"""Emergency stop - cut all rotors"""
	for i in range(rotor_count):
		target_rotor_speeds[i] = 0.0
		rotor_speeds[i] = 0.0
	
	print("EMERGENCY SHUTDOWN - All rotors stopped")

# AI Interface Methods (required for compatibility)
func set_target_position(pos: Vector3):
	"""Set new target position from AI"""
	target_position = pos
	print("Drone target set to: ", pos)

func set_emergency_mode(enabled: bool):
	"""Enable/disable emergency mode"""
	emergency_mode = enabled
	if enabled:
		emergency_timer = 0.0
		emergency_activated.emit()
		print("Drone entering emergency mode")
	else:
		emergency_timer = 0.0
		print("Drone exiting emergency mode")

func reset_position(pos: Vector3):
	"""Reset drone to starting position"""
	global_position = pos
	target_position = pos
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	emergency_mode = false
	print("Drone reset to position: ", pos)

func get_current_stats() -> Dictionary:
	"""Get current drone statistics"""
	return {
		"position": global_position,
		"velocity": linear_velocity,
		"speed": linear_velocity.length(),
		"target_position": target_position,
		"distance_to_target": global_position.distance_to(target_position),
		"emergency_mode": emergency_mode,
		"shooting_range": _get_distance_to_current_target(),
		"in_firing_range": _is_target_in_range(),
		"is_aiming": is_aiming,
		"ready_to_fire": shooting_cooldown <= 0 and _is_target_in_range()
	}

func get_shooting_status() -> Dictionary:
	"""Get current shooting system status"""
	var target_distance = _get_distance_to_current_target()
	
	return {
		"in_range": target_distance <= max_shooting_range,
		"optimal_range": target_distance <= max_shooting_range * 0.6,
		"distance_to_target": target_distance,
		"is_aiming": is_aiming,
		"aiming_progress": 1.0 - (aiming_timer / aiming_time) if aiming_time > 0 else 1.0,
		"cooldown_remaining": shooting_cooldown,
		"ready_to_fire": shooting_cooldown <= 0 and aiming_timer <= 0 and target_distance <= max_shooting_range
	}

func _get_distance_to_current_target() -> float:
	"""Get distance to current target"""
	if not current_target:
		current_target = get_tree().get_first_node_in_group("target")
	
	if current_target:
		return global_position.distance_to(current_target.global_position)
	
	return 999.0

func _is_target_in_range() -> bool:
	"""Check if target is in shooting range"""
	return _get_distance_to_current_target() <= max_shooting_range

func _update_ai_systems(delta: float):
	"""Update AI-related systems"""
	# Update emergency timer
	if emergency_mode:
		emergency_timer += delta
		if emergency_timer > max_emergency_time:
			set_emergency_mode(false)
	
	# Update shooting cooldown
	if shooting_cooldown > 0:
		shooting_cooldown -= delta
	
	# Update shooting system
	_update_shooting_system(delta)
	
	# Move towards target position if set
	if target_position != Vector3.ZERO:
		_move_towards_target()

func _update_shooting_system(delta: float):
	"""Update the drone's shooting and targeting system"""
	if not current_target:
		current_target = get_tree().get_first_node_in_group("target")
		return
	
	var distance_to_target = global_position.distance_to(current_target.global_position)
	
	# Check if target is in range
	if distance_to_target <= max_shooting_range:
		# Start aiming if not already aiming
		if not is_aiming:
			is_aiming = true
			aiming_timer = aiming_time
			print("Drone acquiring target at range: ", distance_to_target)
		
		# Count down aiming time
		if aiming_timer > 0:
			aiming_timer -= delta
		
		# Fire when aimed and cooldown is ready
		if aiming_timer <= 0 and shooting_cooldown <= 0:
			_fire_at_target()
	else:
		# Target out of range - stop aiming
		if is_aiming:
			is_aiming = false
			aiming_timer = 0

func _fire_at_target():
	"""Fire at the current target"""
	if not current_target:
		return
	
	var target_pos = current_target.global_position
	print("Drone firing at target!")
	
	# Emit visual shot effect
	shot_fired.emit(global_position, target_pos)
	
	# Simple hit detection
	if randf() <= 0.8:  # 80% hit chance
		print("TARGET HIT!")
		if current_target.has_method("take_damage"):
			current_target.take_damage(1)
		else:
			target_shot.emit(target_pos)
	else:
		print("Shot missed")
	
	# Reset shooting state
	shooting_cooldown = shooting_cooldown_time
	is_aiming = false
	aiming_timer = 0

func _move_towards_target():
	"""Simple movement towards target using basic inputs"""
	var direction = (target_position - global_position).normalized()
	var distance = global_position.distance_to(target_position)
	
	if distance > 0.1:
		# Convert 3D direction to control inputs
		pitch_input = -direction.z * min(distance, 1.0)
		roll_input = direction.x * min(distance, 1.0)
		
		# Maintain altitude
		var altitude_error = target_position.y - global_position.y
		throttle_input = hover_throttle + clamp(altitude_error * 0.1, -0.3, 0.3)
	else:
		# Reached target
		target_reached.emit(global_position)
		pitch_input = 0.0
		roll_input = 0.0
		throttle_input = hover_throttle 