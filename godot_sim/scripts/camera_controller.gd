extends Node3D

# Third Person Camera Controller - Follows behind drone based on movement direction

@export var follow_distance: float = 2.0    # Distance behind drone
@export var follow_height: float = 0.8      # Height above drone (increased for better downward view)
@export var follow_speed: float = 8.0       # Smooth position following speed (reduced for smoother)
@export var rotation_speed: float = 4.0     # Smooth rotation following speed (reduced for smoother)
@export var min_ground_height: float = 1.2  # Minimum height above ground (increased)
@export var movement_threshold: float = 0.1  # Minimum movement to update direction
@export var smooth_factor: float = 0.15     # Additional smoothing factor for sudden changes
@export var velocity_smoothing: float = 0.8  # Smoothing for velocity-based direction

var drone: Node3D
var camera: Camera3D
var last_movement_direction: Vector3 = Vector3(0, 0, -1)  # Default facing forward
var last_drone_position: Vector3 = Vector3.ZERO
var smoothed_velocity: Vector3 = Vector3.ZERO  # Smoothed drone velocity
var target_camera_position: Vector3 = Vector3.ZERO  # Target position for camera
var current_camera_velocity: Vector3 = Vector3.ZERO  # Current camera movement velocity

# Drone finding variables
var drone_search_timer: float = 0.0
var drone_search_interval: float = 0.5  # Try to find drone every 0.5 seconds
var drone_found: bool = false

func _ready():
	camera = $Camera3D
	print("CameraController: Initializing camera system...")
	
	# Add to group so GameManager can find us
	add_to_group("camera_controller")
	add_to_group("camera_controllers")
	
	_find_drone()

func _find_drone():
	"""Robust drone finding with multiple fallback methods"""
	drone = null
	
	# Method 1: Try groups system first
	drone = get_tree().get_first_node_in_group("drones")
	if drone:
		print("CameraController: Found drone via 'drones' group: ", drone.name)
		_initialize_drone_tracking()
		return
	
	# Method 2: Try fallback group name
	drone = get_tree().get_first_node_in_group("drone")
	if drone:
		print("CameraController: Found drone via 'drone' group: ", drone.name)
		_initialize_drone_tracking()
		return
	
	# Method 3: Try finding by node name in main scene
	var main_scene = get_tree().current_scene
	if main_scene:
		drone = main_scene.get_node_or_null("AerodynamicDrone")
		if drone:
			print("CameraController: Found drone by name 'AerodynamicDrone': ", drone.name)
			_initialize_drone_tracking()
			return
	
	# Method 4: Try finding by class name
	var all_nodes = get_tree().get_nodes_in_group("drones")
	for node in all_nodes:
		if node is RigidBody3D and node.has_method("_physics_process"):
			drone = node
			print("CameraController: Found drone by class type: ", drone.name)
			_initialize_drone_tracking()
			return
	
	# Method 5: Search the entire scene tree for RigidBody3D with drone characteristics
	drone = _search_for_drone_recursive(get_tree().current_scene)
	if drone:
		print("CameraController: Found drone via recursive search: ", drone.name)
		_initialize_drone_tracking()
		return
	
	print("CameraController: No drone found yet, will retry...")
	drone_found = false

func _search_for_drone_recursive(node: Node) -> Node3D:
	"""Recursively search for a node that looks like a drone"""
	if node is RigidBody3D:
		# Check if this looks like a drone
		if node.name.to_lower().contains("drone") or node.has_signal("flight_mode_changed"):
			return node
	
	# Search children
	for child in node.get_children():
		var result = _search_for_drone_recursive(child)
		if result:
			return result
	
	return null

func _initialize_drone_tracking():
	"""Initialize camera tracking once drone is found"""
	if drone:
		drone_found = true
		last_drone_position = drone.global_position
		target_camera_position = global_position
		smoothed_velocity = Vector3.ZERO
		current_camera_velocity = Vector3.ZERO
		print("CameraController: Successfully initialized drone tracking!")
		print("  Drone position: ", drone.global_position)
		print("  Drone type: ", drone.get_class())
		print("  Drone script: ", drone.get_script().get_global_name() if drone.get_script() else "No script")

func _process(delta):
	# If we don't have a drone yet, try to find it periodically
	if not drone_found or not drone or not is_instance_valid(drone):
		drone_search_timer += delta
		if drone_search_timer >= drone_search_interval:
			drone_search_timer = 0.0
			_find_drone()
		return
	
	if not camera:
		return
	
	# Get drone position and calculate movement direction
	var drone_position = drone.global_position
	
	# Calculate movement direction from velocity with heavy smoothing
	var raw_velocity = Vector3.ZERO
	
	# Try to get velocity from drone based on its type
	if drone is CharacterBody3D:
		raw_velocity = drone.velocity
	elif drone is VehicleBody3D or drone is RigidBody3D:
		raw_velocity = drone.linear_velocity
	elif drone.has_method("get_linear_velocity"):
		# For custom physics bodies like AeroBody3D
		raw_velocity = drone.get_linear_velocity()
	else:
		# Fallback: calculate from position change
		var position_change = drone_position - last_drone_position
		raw_velocity = position_change / delta if delta > 0 else Vector3.ZERO
	
	# Apply velocity smoothing to reduce sudden camera jerks
	smoothed_velocity = smoothed_velocity.lerp(raw_velocity, velocity_smoothing * delta)
	
	# Calculate movement direction from smoothed velocity
	var movement_direction = Vector3.ZERO
	if smoothed_velocity.length() > movement_threshold:
		movement_direction = Vector3(smoothed_velocity.x, 0, smoothed_velocity.z).normalized()
	
	# Update movement direction with heavy smoothing to prevent camera snap
	if movement_direction.length() > 0.1:
		# Smooth transition to new direction to prevent camera snapping on collisions
		last_movement_direction = last_movement_direction.slerp(movement_direction, smooth_factor)
	
	# Calculate desired camera position behind drone based on smoothed movement direction
	var camera_offset = last_movement_direction * -follow_distance + Vector3(0, follow_height, 0)
	target_camera_position = drone_position + camera_offset
	
	# Ensure camera doesn't go below minimum ground height
	if target_camera_position.y < min_ground_height:
		target_camera_position.y = min_ground_height
	
	# Use smooth damping for camera position (more natural than lerp)
	var position_difference = target_camera_position - global_position
	current_camera_velocity = current_camera_velocity.lerp(position_difference * follow_speed, 0.3)
	global_position += current_camera_velocity * delta
	
	# Calculate where camera should look with predictive smoothing and downward angle
	var look_ahead_distance = 6.0 + smoothed_velocity.length() * 1.5  # Reduced look-ahead for better downward view
	var look_target = drone_position + last_movement_direction * look_ahead_distance
	look_target.y = drone_position.y - 0.2  # Look slightly below drone for better downward view
	
	# Smoothly rotate camera with quaternion interpolation for better smoothness
	var target_look_direction = (look_target - global_position).normalized()
	
	if target_look_direction.length() > 0.1:
		# Use quaternion slerp for smoother rotation
		var current_quaternion = Quaternion(global_transform.basis)
		var target_transform = global_transform.looking_at(look_target, Vector3.UP)
		var target_quaternion = Quaternion(target_transform.basis)
		
		# Smooth quaternion interpolation
		var smoothed_quaternion = current_quaternion.slerp(target_quaternion, rotation_speed * delta)
		global_transform.basis = Basis(smoothed_quaternion)
	
	# Update last position for next frame
	last_drone_position = drone_position
	
	# Reduced debug output frequency
	if Engine.get_process_frames() % 180 == 0:  # Print every 180 frames (3 seconds at 60fps)
		print("CAMERA TRACKING DEBUG:")
		print("  Drone found: ", drone_found)
		print("  Drone valid: ", is_instance_valid(drone))
		print("  Drone position: ", drone_position)
		print("  Smoothed velocity: ", smoothed_velocity)
		print("  Movement direction: ", last_movement_direction)
		print("  Camera position: ", global_position)
		print("  Look target: ", look_target)
		print("  Distance to drone: ", global_position.distance_to(drone_position))
	
	# Reset local camera transform
	camera.transform.origin = Vector3.ZERO
	camera.rotation = Vector3.ZERO

func set_follow_target(target: Node3D):
	"""Set a new target for the camera to follow"""
	drone = target
	if drone:
		drone_found = true
		last_drone_position = drone.global_position
		print("CameraController: Manual target set to: ", drone.name)

func force_find_drone():
	"""Force the camera to search for a drone immediately"""
	print("CameraController: Force searching for drone...")
	_find_drone() 
