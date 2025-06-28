extends Node

# Auto Chase Fix Test - Immediately enables auto mode for testing

@export var enable_on_start: bool = true
@export var debug_movement: bool = true

var drone: Drone = null
var target: Target = null

func _ready():
	print("AutoChaseFixTest: Starting...")
	
	# Wait for scene to load
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Find components
	drone = get_tree().get_first_node_in_group("drones") as Drone
	target = get_tree().get_first_node_in_group("target") as Target
	
	if not drone:
		print("AutoChaseFixTest: ERROR - No drone found!")
		return
		
	if not target:
		print("AutoChaseFixTest: ERROR - No target found!")
		return
	
	print("AutoChaseFixTest: Found drone: ", drone.name, " at ", drone.position)
	print("AutoChaseFixTest: Found target: ", target.name, " at ", target.position)
	
	if enable_on_start:
		print("AutoChaseFixTest: Enabling auto mode in 2 seconds...")
		await get_tree().create_timer(2.0).timeout
		_enable_auto_chase()

func _enable_auto_chase():
	"""Enable auto chase mode with debug output"""
	print("AutoChaseFixTest: ENABLING AUTO CHASE MODE")
	
	if drone and drone.has_method("enable_auto_mode"):
		# Set auto mode property directly first
		drone.auto_mode_enabled = true
		
		# Then call the enable function
		drone.enable_auto_mode(true)
		
		print("AutoChaseFixTest: Auto mode enabled!")
		print("AutoChaseFixTest: Current flight mode: ", drone.current_flight_mode)
		print("AutoChaseFixTest: Auto mode enabled: ", drone.auto_mode_enabled)
		
		# Force target search
		if drone.has_method("_find_and_track_target"):
			drone._find_and_track_target()
		
		await get_tree().create_timer(1.0).timeout
		print("AutoChaseFixTest: Status check:")
		print("  Flight mode: ", drone.current_flight_mode) 
		print("  Auto enabled: ", drone.auto_mode_enabled)
		print("  Target found: ", drone.current_target_node != null)
		if drone.current_target_node:
			print("  Target name: ", drone.current_target_node.name)
			print("  Target position: ", drone.current_target_node.position)
	else:
		print("AutoChaseFixTest: ERROR - Drone doesn't support auto mode!")

func _physics_process(delta):
	"""Monitor auto chase status"""
	if not debug_movement or not drone:
		return
	
	# Debug every 2 seconds
	if Engine.get_process_frames() % 120 == 0:
		if drone.auto_mode_enabled:
			print("=== AUTO CHASE STATUS ===")
			print("Drone position: ", drone.position)
			print("Target position: ", target.position if target else "NO TARGET")
			print("Distance: ", drone.position.distance_to(target.position) if target else "N/A")
			print("Drone velocity: ", drone.linear_velocity.length())
			print("Flight mode: ", drone.current_flight_mode)
			print("Pitch input: ", drone.pitch_input)
			print("Roll input: ", drone.roll_input)
			print("========================")

func _input(event):
	"""Manual controls for testing"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F5:
				_enable_auto_chase()
			KEY_F6:
				_disable_auto_chase()
			KEY_F7:
				_reset_positions()

func _disable_auto_chase():
	"""Disable auto chase for testing"""
	if drone and drone.has_method("enable_auto_mode"):
		drone.enable_auto_mode(false)
		print("AutoChaseFixTest: Auto mode disabled")

func _reset_positions():
	"""Reset positions for testing"""
	if drone:
		drone.position = Vector3(0, 2, -3)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		print("AutoChaseFixTest: Reset drone position")
	
	if target:
		target.position = Vector3(0, 0, 3)
		print("AutoChaseFixTest: Reset target position")
	
	print("AutoChaseFixTest: Distance after reset: ", drone.position.distance_to(target.position) if drone and target else "N/A") 