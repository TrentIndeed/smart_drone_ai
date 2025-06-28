extends Node
class_name CollisionLayerInfo

# Collision Layer Information and Utilities
# Documents the collision layer system used throughout the project

# COLLISION LAYER ASSIGNMENTS (WORKING SETUP):
# Layer 1 (value 1): Drone collision bodies
# Layer 2 (value 2): Obstacles/Environment objects (GLB spawned objects, boundary walls)
# Layer 3 (value 4): Target collision bodies  
# Layer 4 (value 8): Ground/Floor collision (CURRENT: ground.tscn uses layer 8)
#
# DRONE COLLISION MASK = 14 (binary: 1110 = layers 2+3+4 = values 2+4+8)

const COLLISION_LAYERS = {
	"DRONE": 1,      # Layer 1 = value 1
	"OBSTACLES": 2,  # Layer 2 = value 2
	"TARGET": 4,     # Layer 3 = value 4  
	"GROUND_FLOOR": 8 # Layer 4 = value 8
}

const COLLISION_MASKS = {
	"DRONE": 14,  # 2+4+8 = layers 2,3,4 (obstacles + targets + ground)
	"TARGET": 2,  # Layer 2 only (obstacles)
	"OBSTACLES": 0, # No collision detection needed
	"GROUND": 0   # No collision detection needed
}

static func print_collision_info():
	"""Print information about collision layers used in the project"""
	print("=== COLLISION LAYER ANALYSIS ===")
	print("Based on analysis of object spawners and existing collision:")
	print()
	print("CURRENT USAGE:")
	print("  • Randomly placed objects (GLBObjectSpawner, SimpleObjectSpawner): Layer 2")
	print("  • Current ground.tscn: Layer 8") 
	print("  • Boundary walls in ground.tscn: Layer 2")
	print()
	print("RECOMMENDED STANDARDIZATION:")
	print("  • Layer 1: Drone collision bodies")
	print("  • Layer 2: Environment obstacles") 
	print("  • Layer 3: Target collision bodies")
	print("  • Layer 4: Ground/Floor collision")
	print()
	print("ISSUE IDENTIFIED:")
	print("  Ground uses layer 8, but objects use layer 2")
	print("  This creates inconsistency - recommend using layer 4 for ground")

static func get_objects_by_collision_layer() -> Dictionary:
	"""Get all collision objects grouped by their collision layer"""
	var layers = {}
	
	# Find all StaticBody3D nodes in the scene
	var static_bodies = []
	_find_static_bodies_recursive(Engine.get_main_loop().current_scene, static_bodies)
	
	for body in static_bodies:
		var layer = body.collision_layer
		if layer not in layers:
			layers[layer] = []
		layers[layer].append({
			"name": body.name,
			"path": body.get_path(),
			"groups": body.get_groups()
		})
	
	return layers

static func _find_static_bodies_recursive(node: Node, result: Array):
	"""Recursively find all StaticBody3D nodes"""
	if node is StaticBody3D:
		result.append(node)
	
	for child in node.get_children():
		_find_static_bodies_recursive(child, result)

static func update_ground_collision_layer():
	"""Update existing ground collision to use the recommended layer"""
	var ground_node = Engine.get_main_loop().current_scene.get_node_or_null("Ground")
	
	if ground_node and ground_node is StaticBody3D:
		var old_layer = ground_node.collision_layer
		ground_node.collision_layer = COLLISION_LAYERS.FLOOR_RECOMMENDED
		print("Updated ground collision layer from ", old_layer, " to ", COLLISION_LAYERS.FLOOR_RECOMMENDED)
		return true
	else:
		print("Ground node not found or not StaticBody3D")
		return false

static func verify_collision_consistency() -> Dictionary:
	"""Check collision layer consistency across the project"""
	var report = {
		"consistent": true,
		"issues": [],
		"recommendations": []
	}
	
	var layers = get_objects_by_collision_layer()
	
	# Check if ground uses different layer than objects
	var has_ground_layer_8 = 8 in layers
	var has_objects_layer_2 = 2 in layers
	
	if has_ground_layer_8 and has_objects_layer_2:
		report.consistent = false
		report.issues.append("Ground uses layer 8 while objects use layer 2")
		report.recommendations.append("Update ground to use layer 4 for consistency")
	
	# Check for orphaned collision layers
	for layer in layers.keys():
		if layer not in [1, 2, 3, 4, 8]:
			report.issues.append("Unexpected collision layer found: " + str(layer))
	
	return report

# Example usage in script:
func _ready():
	if OS.is_debug_build():
		CollisionLayerInfo.print_collision_info()
		
		var consistency = CollisionLayerInfo.verify_collision_consistency()
		if not consistency.consistent:
			print("COLLISION ISSUES FOUND:")
			for issue in consistency.issues:
				print("  ⚠️  ", issue)
			print("RECOMMENDATIONS:")
			for rec in consistency.recommendations:
				print("  💡 ", rec) 