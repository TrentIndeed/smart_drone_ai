extends Node
class_name DroneAI_Interface

# AI Bridge Interface for Aerodynamic Drone
# Provides advanced navigation modes and smooth control transitions

signal navigation_status_changed(status: Dictionary)
signal target_reached(position: Vector3)
signal mission_completed()

var drone_controller = null  # Can be Drone (DroneFlightAdapter), DroneFlightFallback, or any drone type
var navigation_mode: String = "manual"
var target_position: Vector3 = Vector3.ZERO
var orbit_radius: float = 2.0
var orbit_speed: float = 1.0
var approach_distance: float = 1.0

# Navigation modes
var nav_modes = {
	"manual": "Direct manual control",
	"navigate_to_target": "Navigate to specific position", 
	"orbit_target": "Orbit around target position",
	"approach_target": "Approach target to specific distance",
	"hovering": "Hold current position",
	"simple_tracking": "Simple target tracking"
}

func _ready():
	# Find the drone controller (parent node)
	drone_controller = get_parent()
	
	# Enable simple target tracking on the drone
	if drone_controller and drone_controller.has_method("enable_simple_tracking"):
		drone_controller.enable_simple_tracking(true)
		print("DroneAI_Interface connected to aerodynamic drone with simple tracking")
		add_to_group("ai_bridge")
	else:
		print("Warning: DroneAI_Interface could not connect to aerodynamic drone")

func _process(delta):
	# Update navigation based on current mode
	match navigation_mode:
		"orbit_target":
			_update_orbit_navigation(delta)
		"approach_target":
			_update_approach_navigation(delta)
		"navigate_to_target":
			_update_direct_navigation(delta)
		"hovering":
			_update_hover_navigation(delta)
		"simple_tracking":
			_update_simple_tracking(delta)

func navigate_to_target(target_pos: Vector3):
	"""Navigate directly to a target position using simple tracking"""
	target_position = target_pos
	navigation_mode = "simple_tracking"
	
	if drone_controller and drone_controller.has_method("set_target_position"):
		drone_controller.set_target_position(target_pos)
	
	_emit_nav_status()
	print("AI Bridge: Simple tracking to ", target_pos)

func orbit_target(radius: float = 2.0, speed: float = 1.0):
	"""Orbit around the current target position"""
	orbit_radius = radius
	orbit_speed = speed
	navigation_mode = "orbit_target"
	
	# Find target if we don't have a position set
	if target_position == Vector3.ZERO:
		var target_node = get_tree().get_first_node_in_group("target")
		if target_node:
			target_position = target_node.global_position
	
	_emit_nav_status()
	print("AI Bridge: Orbit target with radius ", radius, " and speed ", speed)

func approach_target(distance: float = 1.0):
	"""Approach target to a specific distance"""
	approach_distance = distance
	navigation_mode = "approach_target"
	
	# Find target if we don't have a position set
	if target_position == Vector3.ZERO:
		var target_node = get_tree().get_first_node_in_group("target")
		if target_node:
			target_position = target_node.global_position
	
	_emit_nav_status()
	print("AI Bridge: Approach target to distance ", distance)

func set_navigation_mode(mode: String):
	"""Set the navigation mode"""
	if mode in nav_modes:
		navigation_mode = mode
		_emit_nav_status()
		print("AI Bridge: Navigation mode set to ", mode)
	else:
		print("AI Bridge: Unknown navigation mode: ", mode)

func get_navigation_status() -> Dictionary:
	"""Get current navigation status"""
	var drone_pos = Vector3.ZERO
	if drone_controller:
		drone_pos = drone_controller.global_position
	
	return {
		"navigation_mode": navigation_mode,
		"target_position": target_position,
		"drone_position": drone_pos,
		"orbit_radius": orbit_radius,
		"orbit_speed": orbit_speed,
		"approach_distance": approach_distance,
		"distance_to_target": drone_pos.distance_to(target_position) if target_position != Vector3.ZERO else 0.0
	}

func _update_orbit_navigation(delta: float):
	"""Update orbit navigation mode"""
	if not drone_controller or target_position == Vector3.ZERO:
		return
	
	var drone_pos = drone_controller.global_position
	var to_target = target_position - drone_pos
	to_target.y = 0  # Keep on horizontal plane
	
	# Calculate orbit position
	var current_distance = to_target.length()
	
	if current_distance > 0.1:
		# Calculate perpendicular direction for orbit
		var orbit_direction = Vector3(-to_target.z, 0, to_target.x).normalized()
		
		# Adjust position to maintain orbit radius
		var desired_distance_vector = to_target.normalized() * orbit_radius
		var orbit_offset = orbit_direction * orbit_speed * delta * 10.0
		
		var orbit_position = target_position - desired_distance_vector + orbit_offset
		orbit_position.y = drone_pos.y  # Maintain altitude
		
		if drone_controller.has_method("set_target_position"):
			drone_controller.set_target_position(orbit_position)

func _update_approach_navigation(delta: float):
	"""Update approach navigation mode"""
	if not drone_controller or target_position == Vector3.ZERO:
		return
	
	var drone_pos = drone_controller.global_position
	var to_target = target_position - drone_pos
	var current_distance = to_target.length()
	
	if current_distance > approach_distance + 0.2:  # Approach if too far
		var approach_pos = target_position - to_target.normalized() * approach_distance
		approach_pos.y = drone_pos.y  # Maintain altitude
		
		if drone_controller.has_method("set_target_position"):
			drone_controller.set_target_position(approach_pos)
	elif current_distance < approach_distance - 0.2:  # Move away if too close
		var retreat_pos = target_position - to_target.normalized() * approach_distance
		retreat_pos.y = drone_pos.y  # Maintain altitude
		
		if drone_controller.has_method("set_target_position"):
			drone_controller.set_target_position(retreat_pos)

func _update_direct_navigation(delta: float):
	"""Update direct navigation mode"""
	if not drone_controller or target_position == Vector3.ZERO:
		return
	
	var drone_pos = drone_controller.global_position
	var distance = drone_pos.distance_to(target_position)
	
	# Check if we've reached the target
	if distance < 0.5:
		target_reached.emit(target_position)
		navigation_mode = "hovering"
		_emit_nav_status()

func _update_hover_navigation(delta: float):
	"""Update hover navigation mode"""
	if not drone_controller:
		return
	
	# Set flight mode to altitude hold for stable hovering
	if drone_controller.has_method("set_flight_mode"):
		drone_controller.set_flight_mode("ALTITUDE_HOLD")

func _update_simple_tracking(delta: float):
	"""Update simple target tracking mode"""
	if not drone_controller or target_position == Vector3.ZERO:
		return
	
	var drone_pos = drone_controller.global_position
	var to_target = target_position - drone_pos
	var current_distance = to_target.length()
	
	if current_distance > 0.5:  # Move towards the target
		var move_direction = to_target.normalized()
		var move_distance = min(current_distance, 0.5)
		var move_pos = drone_pos + move_direction * move_distance
		move_pos.y = drone_pos.y  # Maintain altitude
		
		if drone_controller.has_method("set_target_position"):
			drone_controller.set_target_position(move_pos)
	elif current_distance < 0.5:  # Move away if too close
		var retreat_pos = drone_pos - to_target.normalized() * 0.5
		retreat_pos.y = drone_pos.y  # Maintain altitude
		
		if drone_controller.has_method("set_target_position"):
			drone_controller.set_target_position(retreat_pos)

func _emit_nav_status():
	"""Emit navigation status update"""
	var status = get_navigation_status()
	navigation_status_changed.emit(status)

# Public interface for external control
func set_target_position(pos: Vector3):
	"""Set target position for navigation"""
	target_position = pos

func get_current_mode() -> String:
	"""Get current navigation mode"""
	return navigation_mode

func is_target_reached() -> bool:
	"""Check if drone has reached target"""
	if not drone_controller or target_position == Vector3.ZERO:
		return false
	
	var distance = drone_controller.global_position.distance_to(target_position)
	return distance < 0.5 
