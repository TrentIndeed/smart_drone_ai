extends Node3D

# 3rd Person Camera Controller for following the drone

@export var follow_distance: float = 5.0
@export var follow_height: float = 2.5
@export var follow_speed: float = 8.0
@export var look_ahead_distance: float = 3.0
@export var camera_angle: float = 15.0  # Degrees down from horizontal

var drone: Node3D
var camera: Camera3D

func _ready():
	camera = $Camera3D
	# Find the drone
	await get_tree().create_timer(0.1).timeout  # Wait for drone to be created
	drone = get_tree().get_first_node_in_group("drone")
	if not drone:
		print("Warning: No drone found for camera to follow")

func _process(delta):
	if not drone or not camera:
		return
	
	# Get drone's velocity to determine forward direction
	var drone_velocity = Vector3.ZERO
	if drone.has_method("get_velocity"):
		drone_velocity = drone.get_velocity()
	elif "velocity" in drone:
		drone_velocity = drone.velocity
	var drone_forward = Vector3.FORWARD  # Default forward
	
	if drone_velocity.length() > 0.1:
		# Use movement direction as forward
		drone_forward = drone_velocity.normalized()
	else:
		# Use transform forward if not moving
		drone_forward = -drone.transform.basis.z
	
	# Calculate camera position behind and above drone (Fortnite/racing style)
	var camera_offset = -drone_forward * follow_distance + Vector3.UP * follow_height
	var desired_position = drone.position + camera_offset
	
	# Smoothly move camera controller to desired position
	position = position.lerp(desired_position, follow_speed * delta)
	
	# Make camera look at drone from its current position
	var camera_world_pos = global_position
	var look_target = drone.global_position + Vector3.UP * 0.2  # Look slightly above drone
	
	# Calculate look direction and apply it
	var look_direction = (look_target - camera_world_pos).normalized()
	var camera_basis = Basis.looking_at(look_direction, Vector3.UP)
	
	# Apply slight downward rotation for racing game feel
	camera_basis = camera_basis.rotated(camera_basis.x, deg_to_rad(camera_angle))
	
	# Set camera transform
	camera.transform.basis = camera_basis

func set_follow_target(target: Node3D):
	"""Set a new target for the camera to follow"""
	drone = target 