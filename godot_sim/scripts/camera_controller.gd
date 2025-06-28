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

func _ready():
	camera = $Camera3D
	# Find the drone
	await get_tree().create_timer(0.1).timeout  # Wait for drone to be created
	drone = get_tree().get_first_node_in_group("drones")
	if not drone:
		# Try the old group name as fallback
		drone = get_tree().get_first_node_in_group("drone")
	if not drone:
		print("Warning: No drone found for camera to follow")
	else:
		print("Smooth third-person camera locked onto drone")
		last_drone_position = drone.global_position
		target_camera_position = global_position
		smoothed_velocity = Vector3.ZERO
		current_camera_velocity = Vector3.ZERO

func _process(delta):
	if not drone or not camera:
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
		print("SMOOTH CAMERA DEBUG:")
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
		last_drone_position = drone.global_position 
