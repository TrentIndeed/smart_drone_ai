extends Node3D

# Third Person Camera Controller - Follows behind drone based on movement direction

@export var follow_distance: float = 2.0    # Distance behind drone
@export var follow_height: float = 0.3      # Height above drone (reduced)
@export var follow_speed: float = 10.0      # Smooth position following speed
@export var rotation_speed: float = 6.0     # Smooth rotation following speed
@export var min_ground_height: float = 1.0  # Minimum height above ground (reduced)
@export var movement_threshold: float = 0.1  # Minimum movement to update direction

var drone: Node3D
var camera: Camera3D
var last_movement_direction: Vector3 = Vector3(0, 0, -1)  # Default facing forward
var last_drone_position: Vector3 = Vector3.ZERO

func _ready():
	camera = $Camera3D
	# Find the drone
	await get_tree().create_timer(0.1).timeout  # Wait for drone to be created
	drone = get_tree().get_first_node_in_group("drone")
	if not drone:
		print("Warning: No drone found for camera to follow")
	else:
		print("Movement-based third-person camera locked onto drone")
		last_drone_position = drone.global_position

func _process(delta):
	if not drone or not camera:
		return
	
	# Get drone position and calculate movement direction
	var drone_position = drone.global_position
	
	# Calculate movement direction from velocity or position change
	var movement_direction = Vector3.ZERO
	
	# Try to get velocity from drone if it's a CharacterBody3D
	if drone is CharacterBody3D:
		var drone_velocity = drone.velocity
		if drone_velocity.length() > movement_threshold:
			movement_direction = Vector3(drone_velocity.x, 0, drone_velocity.z).normalized()
	
	# Fallback: calculate direction from position change
	if movement_direction.length() < 0.1:
		var position_change = drone_position - last_drone_position
		if position_change.length() > movement_threshold:
			movement_direction = Vector3(position_change.x, 0, position_change.z).normalized()
	
	# Update movement direction only if drone is actually moving
	if movement_direction.length() > 0.1:
		last_movement_direction = movement_direction
	
	# Calculate camera position behind drone based on movement direction
	var camera_offset = last_movement_direction * -follow_distance + Vector3(0, follow_height, 0)
	var desired_camera_position = drone_position + camera_offset
	
	# Ensure camera doesn't go below minimum ground height
	if desired_camera_position.y < min_ground_height:
		desired_camera_position.y = min_ground_height
	
	# Smoothly move camera to desired position
	global_position = global_position.lerp(desired_camera_position, follow_speed * delta)
	
	# Calculate where camera should look - ahead in movement direction
	var look_target = drone_position + last_movement_direction * 10.0
	look_target.y = drone_position.y  # Keep look target at drone's height
	
	# Smoothly rotate camera to look in movement direction
	var current_look_direction = -global_transform.basis.z
	var target_look_direction = (look_target - global_position).normalized()
	
	if target_look_direction.length() > 0.1:
		# Smooth rotation using look_at with interpolation
		var target_transform = global_transform.looking_at(look_target, Vector3.UP)
		global_transform = global_transform.interpolate_with(target_transform, rotation_speed * delta)
	
	# Update last position for next frame
	last_drone_position = drone_position
	
	# Debug camera positioning and movement
	if Engine.get_process_frames() % 60 == 0:  # Print every 60 frames
		print("MOVEMENT-BASED CAMERA DEBUG:")
		print("  Drone position: ", drone_position)
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
