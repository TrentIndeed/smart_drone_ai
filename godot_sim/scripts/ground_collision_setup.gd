extends Node3D
class_name GroundCollisionSetup

# Ground Collision Setup - Creates floor collision using the same pattern as object spawners
# Follows the exact collision setup pattern from GLBObjectSpawner and SimpleObjectSpawner

@export var floor_size: Vector2 = Vector2(15, 15)  # Floor dimensions (X, Z)
@export var floor_thickness: float = 0.2  # How thick the collision floor should be
@export var collision_layer: int = 4  # Ground layer (different from obstacles)
@export var collision_mask: int = 0   # Floor doesn't need to detect collisions
@export var debug_collision_shapes: bool = true  # Show collision wireframe
@export var floor_material_color: Color = Color(0.2, 0.4, 0.1, 1.0)  # Ground green color

var floor_static_body: StaticBody3D = null
var floor_collision_shape: CollisionShape3D = null
var floor_mesh_instance: MeshInstance3D = null

func _ready():
	print("GroundCollisionSetup: Creating floor collision using object spawner pattern")
	create_floor_collision()

func create_floor_collision():
	"""Create floor collision using the same pattern as randomly placed objects"""
	print("=== GROUND COLLISION SETUP ===")
	print("Floor size: ", floor_size)
	print("Collision layer: ", collision_layer)
	print("Using same pattern as GLBObjectSpawner and SimpleObjectSpawner")
	
	# Step 1: Create StaticBody3D (same as object spawners)
	floor_static_body = StaticBody3D.new()
	floor_static_body.name = "FloorCollision"
	floor_static_body.collision_layer = collision_layer
	floor_static_body.collision_mask = collision_mask
	add_child(floor_static_body)
	
	print("✅ Created StaticBody3D with collision_layer = ", collision_layer)
	
	# Step 2: Create visual mesh (same pattern as object spawners)
	floor_mesh_instance = MeshInstance3D.new()
	floor_mesh_instance.name = "FloorMesh"
	
	# Create plane mesh for visual representation
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = floor_size
	floor_mesh_instance.mesh = plane_mesh
	
	# Apply material (same pattern as object spawners)
	var floor_material = StandardMaterial3D.new()
	floor_material.albedo_color = floor_material_color
	floor_material.roughness = 0.8
	floor_material.metallic = 0.0
	floor_mesh_instance.set_surface_override_material(0, floor_material)
	
	floor_static_body.add_child(floor_mesh_instance)
	print("✅ Created visual mesh with material")
	
	# Step 3: Create CollisionShape3D (same as object spawners)
	floor_collision_shape = CollisionShape3D.new()
	floor_collision_shape.name = "FloorCollisionShape"
	
	# Step 4: Create BoxShape3D (same as object spawners)
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(floor_size.x, floor_thickness, floor_size.y)
	floor_collision_shape.shape = box_shape
	
	# Position collision shape slightly below surface (same as current ground.tscn)
	floor_collision_shape.transform.origin.y = -floor_thickness * 0.5
	
	floor_static_body.add_child(floor_collision_shape)
	print("✅ Created BoxShape3D collision: ", box_shape.size)
	
	# Step 5: Add to groups (same as object spawners)
	floor_static_body.add_to_group("environment")
	floor_static_body.add_to_group("floor_collision")
	print("✅ Added to groups: environment, floor_collision")
	
	# Step 6: Add debug visualization (same pattern as object spawners)
	if debug_collision_shapes:
		_add_debug_visualization_for_floor_collision()
		print("✅ Added debug collision visualization")
	
	print("SUCCESS: Floor collision created using object spawner pattern")

func _add_debug_visualization_for_floor_collision():
	"""Add debug visualization for floor collision (same pattern as object spawners)"""
	
	# Create debug visualization based on collision shape (same as GLBObjectSpawner)
	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "DEBUG_FloorCollision"
	
	var shape = floor_collision_shape.shape
	var debug_material = StandardMaterial3D.new()
	debug_material.flags_unshaded = true
	debug_material.wireframe = true
	debug_material.flags_transparent = true
	debug_material.albedo_color = Color.CYAN  # Cyan for floor collision (different from objects)
	
	if shape is BoxShape3D:
		# Create box wireframe (same as object spawners)
		var box_mesh = BoxMesh.new()
		box_mesh.size = (shape as BoxShape3D).size
		debug_mesh.mesh = box_mesh
		debug_mesh.set_surface_override_material(0, debug_material)
		debug_mesh.transform = floor_collision_shape.transform
		floor_static_body.add_child(debug_mesh)
		print("      Added debug wireframe for floor collision")

func get_collision_info() -> Dictionary:
	"""Get collision information (same pattern as ObjectPlacer)"""
	var info = {
		"has_collision": false,
		"static_body_count": 0,
		"collision_shape_count": 0,
		"collision_layer": collision_layer,
		"floor_size": floor_size,
		"shape_type": ""
	}
	
	if floor_static_body and is_instance_valid(floor_static_body):
		info.has_collision = true
		info.static_body_count = 1
		
		if floor_collision_shape and is_instance_valid(floor_collision_shape):
			info.collision_shape_count = 1
			if floor_collision_shape.shape:
				info.shape_type = floor_collision_shape.shape.get_class()
	
	return info

func set_collision_layer(new_layer: int):
	"""Change collision layer (useful for debugging)"""
	collision_layer = new_layer
	if floor_static_body and is_instance_valid(floor_static_body):
		floor_static_body.collision_layer = new_layer
		print("Floor collision layer changed to: ", new_layer)

func toggle_debug_visualization():
	"""Toggle debug visualization on/off"""
	debug_collision_shapes = !debug_collision_shapes
	
	if floor_static_body and is_instance_valid(floor_static_body):
		# Remove existing debug visualization
		var debug_node = floor_static_body.get_node_or_null("DEBUG_FloorCollision")
		if debug_node:
			debug_node.queue_free()
		
		# Add new debug visualization if enabled
		if debug_collision_shapes:
			_add_debug_visualization_for_floor_collision()
	
	print("Floor debug visualization: ", "ON" if debug_collision_shapes else "OFF")

# Public interface for external scripts
func has_collision() -> bool:
	"""Check if floor has collision (same pattern as ObjectPlacer)"""
	return floor_static_body != null and is_instance_valid(floor_static_body)

func get_floor_bounds() -> AABB:
	"""Get floor boundaries"""
	var bounds = AABB()
	bounds.position = Vector3(-floor_size.x * 0.5, -floor_thickness, -floor_size.y * 0.5)
	bounds.size = Vector3(floor_size.x, floor_thickness, floor_size.y)
	return bounds 