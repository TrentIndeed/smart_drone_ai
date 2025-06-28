extends Node

# Simple test script to enable auto mode for drone testing
# Attach this to a Node in your main scene to automatically enable auto chase mode

@export var enable_auto_on_start: bool = true
@export var test_mode: bool = true
@export var debug_info: bool = true

var drone: Drone = null
var target: Target = null

func _ready():
	print("AutoModeTest: Initializing...")
	
	# Wait a moment for the scene to fully load
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Find the drone and target
	drone = get_tree().get_first_node_in_group("drones") as Drone
	target = get_tree().get_first_node_in_group("target") as Target
	
	if not drone:
		print("AutoModeTest: No drone found in 'drones' group")
		return
		
	if not target:
		print("AutoModeTest: No target found in 'target' group")
		return
	
	print("AutoModeTest: Found drone: ", drone.name)
	print("AutoModeTest: Found target: ", target.name)
	
	if enable_auto_on_start:
		_enable_auto_mode()
	
	if test_mode:
		_setup_test_environment()
	
	print("AutoModeTest: Ready! Press [5] to toggle auto mode manually")

func _enable_auto_mode():
	"""Enable auto chase mode on the drone"""
	if drone and drone.has_method("enable_auto_mode"):
		drone.enable_auto_mode(true)
		print("AutoModeTest: Auto chase mode ENABLED")
		print("AutoModeTest: Drone should now automatically fly toward the target")
	else:
		print("AutoModeTest: Drone doesn't support auto mode")

func _setup_test_environment():
	"""Setup optimal test environment"""
	if drone:
		# Position drone at a good starting point
		drone.position = Vector3(0, 2, -5)  # Start 5 units back, 2 units up
		drone.rotation = Vector3.ZERO
		
		# Reset velocities
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		
		print("AutoModeTest: Drone positioned at: ", drone.position)
	
	if target:
		# Position target at a visible location
		target.position = Vector3(0, 0, 0)
		print("AutoModeTest: Target positioned at: ", target.position)

func _input(event):
	"""Handle test mode input"""
	if not test_mode:
		return
		
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				_reset_test_positions()
			KEY_T:
				_toggle_target_movement()
			KEY_G:
				_toggle_debug_info()

func _reset_test_positions():
	"""Reset drone and target to test positions"""
	print("AutoModeTest: Resetting positions...")
	_setup_test_environment()
	
	if drone and drone.has_method("reset_position"):
		drone.reset_position(Vector3(0, 2, -5))

func _toggle_target_movement():
	"""Toggle target movement for testing"""
	if target:
		if target.max_speed > 0:
			target.max_speed = 0.0
			print("AutoModeTest: Target movement STOPPED")
		else:
			target.max_speed = 3.0
			print("AutoModeTest: Target movement ENABLED")

func _toggle_debug_info():
	"""Toggle debug information display"""
	debug_info = not debug_info
	print("AutoModeTest: Debug info: ", debug_info)

func _physics_process(delta):
	"""Show debug information if enabled"""
	if not debug_info or not drone or not target:
		return
	
	# Show debug info every 2 seconds
	if fmod(Time.get_time_dict_from_system().get("second", 0), 2) == 0 and Engine.get_process_frames() % 60 == 0:
		var distance = drone.position.distance_to(target.position)
		var drone_status = drone.get_flight_status() if drone.has_method("get_flight_status") else {}
		
		print("=== AUTO MODE TEST DEBUG ===")
		print("Drone pos: ", drone.position)
		print("Target pos: ", target.position) 
		print("Distance: ", "%.2f" % distance)
		print("Drone mode: ", drone_status.get("flight_mode", "UNKNOWN"))
		print("Auto enabled: ", drone_status.get("auto_mode", false))
		print("Drone velocity: ", "%.2f" % drone.linear_velocity.length())
		print("Target velocity: ", "%.2f" % target.velocity.length())
		print("Controls: [R]Reset [T]Toggle target [G]Toggle debug [5]Toggle auto")
		print("============================") 