extends StaticBody3D
class_name Obstacle

# Obstacle - Static environmental barrier

@export var obstacle_type: String = "rock"  # rock, tree, building, etc.

func _ready():
	print("Obstacle initialized at: ", position)
	add_to_group("obstacles")

func get_obstacle_info() -> Dictionary:
	"""Get obstacle information for AI"""
	return {
		"position": position,
		"type": obstacle_type,
		"size": $CollisionShape3D.shape.size if $CollisionShape3D.shape is BoxShape3D else Vector3(0.6, 0.6, 0.6)
	} 