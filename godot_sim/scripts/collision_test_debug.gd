extends Node

# Simple Collision Debug - Runs in main scene

func _ready():
	print("SIMPLE COLLISION DEBUG: Script loaded successfully")
	call_deferred("check_collision_setup")

func check_collision_setup():
	print("\\n=== SIMPLE COLLISION CHECK ===")
	
	# Find drone
	var drone = get_tree().current_scene.get_node_or_null("AerodynamicDrone")
	if drone:
		print("Found drone: ", drone.name, " at ", drone.position)
	else:
		print("No drone found!")
	
	# Find ground
	var ground = get_tree().current_scene.get_node_or_null("Ground")
	if ground:
		print("Found ground: ", ground.name, " layer: ", ground.collision_layer)
	else:
		print("No ground found!")
	
	print("=== END CHECK ===\\n") 