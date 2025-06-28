extends Node

# Simple AI Interface for testing aerodynamic drone with target tracking

signal ai_status_changed(status: Dictionary)

var drone_ai_bridge: DroneAI_Interface = null
var target_node: Node3D = null
var test_mode: bool = true

func _ready():
	print("AI Interface initialized")
	
	# Find the drone AI bridge
	drone_ai_bridge = get_node_or_null("AerodynamicDrone/AI_Bridge")
	if drone_ai_bridge:
		print("Found drone AI bridge")
		# Connect to navigation status changes
		drone_ai_bridge.navigation_status_changed.connect(_on_navigation_status_changed)
	else:
		print("Warning: Could not find drone AI bridge")
	
	# Find target
	target_node = get_tree().get_first_node_in_group("target")
	if target_node:
		print("Found target at: ", target_node.global_position)
	else:
		print("Warning: No target found")
	
	# Start simple target tracking after a short delay
	if test_mode:
		call_deferred("_start_simple_tracking")

func _start_simple_tracking():
	"""Start simple target tracking test"""
	if drone_ai_bridge and target_node:
		print("Starting simple target tracking test")
		drone_ai_bridge.navigate_to_target(target_node.global_position)
	else:
		print("Cannot start tracking - missing drone or target")

func _on_navigation_status_changed(status: Dictionary):
	"""Handle navigation status updates"""
	print("Navigation status: ", status)
	ai_status_changed.emit(status)
	
	# Check if target reached
	if status.get("distance_to_target", 999.0) < 0.5:
		print("Target reached!")
		# Optional: Set new target or stop tracking
