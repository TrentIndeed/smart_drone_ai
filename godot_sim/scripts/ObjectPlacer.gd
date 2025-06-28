extends Node3D
class_name ObjectPlacer

# Example script showing how to place individual 3D objects with pre-imported collision
# Assumes collision shapes are generated during import via Godot's "Generate Collision" option

@export var object_path: String = "res://assets/tiles/Models/DAE format/tree_default.dae"
@export var spawn_position: Vector3 = Vector3.ZERO
@export var random_rotation: bool = true
@export var collision_layer: int = 2  # Collision layer for placed object
@export var collision_mask: int = 0   # Collision mask for placed object
@export var debug_collision_shapes: bool = false  # Show collision wireframes

var placed_object: Node3D = null

func _ready():
	print("ObjectPlacer initialized")
	print("COLLISION NOTICE: Ensure the object is imported with 'Generate Collision' enabled")

func place_object():
	"""Place a single object at the specified position with pre-imported collision"""
	print("=== OBJECT PLACER DEBUG ===")
	print("Placing object: ", object_path)
	print("Position: ", spawn_position)
	print("Using pre-imported collision shapes")
	
	# Clear any existing object
	clear_object()
	
	# Load the model scene
	var model_scene = load(object_path)
	if not model_scene:
		print("ERROR: Could not load model from: ", object_path)
		return false
	
	print("Model loaded successfully")
	
	# Instantiate the model
	var model_instance = model_scene.instantiate()
	if not model_instance:
		print("ERROR: Could not instantiate model")
		return false
	
	print("Model instantiated successfully")
	
	# Set position and rotation
	model_instance.position = spawn_position
	if random_rotation:
		model_instance.rotation.y = randf() * TAU
	
	# Set name based on model file
	var model_name = object_path.get_file().get_basename()
	model_instance.name = model_name + "_placed"
	
	# Add to scene
	add_child(model_instance)
	placed_object = model_instance
	
	# Configure collision for the pre-imported collision shapes
	_configure_imported_collision(model_instance)
	
	# Add to groups for easy identification
	model_instance.add_to_group("obstacles")
	model_instance.add_to_group("placed_objects")
	
	print("SUCCESS: Placed ", model_instance.name, " at ", spawn_position)
	return true

func clear_object():
	"""Clear the currently placed object"""
	if placed_object and is_instance_valid(placed_object):
		print("Clearing existing placed object: ", placed_object.name)
		placed_object.queue_free()
		placed_object = null

func _configure_imported_collision(model_node: Node3D):
	"""Configure collision layers/masks for imported collision shapes"""
	print("    Configuring imported collision for model: ", model_node.name)
	
	# Find and configure all StaticBody3D nodes (generated during import)
	var static_bodies = _find_static_bodies_recursive(model_node)
	
	if static_bodies.size() == 0:
		print("    WARNING: No StaticBody3D nodes found. Ensure 'Generate Collision' was enabled during import!")
		print("    To fix: Select the model in FileSystem, go to Import tab, check 'Generate Collision', then reimport")
		return
	
	print("    Found ", static_bodies.size(), " StaticBody3D collision nodes")
	
	# Configure each StaticBody3D
	for static_body in static_bodies:
		static_body.collision_layer = collision_layer
		static_body.collision_mask = collision_mask
		print("      Configured collision layers for: ", static_body.name)
		
		# Add debug visualization if enabled
		if debug_collision_shapes:
			_add_debug_visualization_for_imported_collision(static_body)

func _find_static_bodies_recursive(node: Node) -> Array[StaticBody3D]:
	"""Recursively find all StaticBody3D nodes (generated during import)"""
	var static_bodies: Array[StaticBody3D] = []
	
	if node is StaticBody3D:
		static_bodies.append(node as StaticBody3D)
	
	# Recursively check children
	for child in node.get_children():
		static_bodies.append_array(_find_static_bodies_recursive(child))
	
	return static_bodies

func _add_debug_visualization_for_imported_collision(static_body: StaticBody3D):
	"""Add debug visualization for imported collision shapes"""
	for child in static_body.get_children():
		if child is CollisionShape3D:
			var collision_shape = child as CollisionShape3D
			
			# Create debug visualization based on shape type
			var debug_mesh = MeshInstance3D.new()
			debug_mesh.name = "DEBUG_" + collision_shape.name
			
			var shape = collision_shape.shape
			var debug_material = StandardMaterial3D.new()
			debug_material.flags_unshaded = true
			debug_material.wireframe = true
			debug_material.flags_transparent = true
			debug_material.albedo_color = Color.RED  # Red for manually placed objects
			
			if shape is ConvexPolygonShape3D:
				# Use the shape's debug mesh for convex shapes
				var shape_debug_mesh = shape.get_debug_mesh()
				if shape_debug_mesh:
					debug_mesh.mesh = shape_debug_mesh
					debug_mesh.set_surface_override_material(0, debug_material)
					debug_mesh.transform = collision_shape.transform
					static_body.add_child(debug_mesh)
					print("      Added debug visualization for convex collision: ", collision_shape.name)
			
			elif shape is ConcavePolygonShape3D:
				# For trimesh shapes, create a wireframe from the shape data
				var shape_debug_mesh = shape.get_debug_mesh()
				if shape_debug_mesh:
					debug_mesh.mesh = shape_debug_mesh
					debug_material.albedo_color = Color.PURPLE  # Purple for trimesh collision
					debug_mesh.set_surface_override_material(0, debug_material)
					debug_mesh.transform = collision_shape.transform
					static_body.add_child(debug_mesh)
					print("      Added debug visualization for trimesh collision: ", collision_shape.name)
			
			elif shape is BoxShape3D:
				# Create box wireframe
				var box_mesh = BoxMesh.new()
				box_mesh.size = (shape as BoxShape3D).size
				debug_mesh.mesh = box_mesh
				debug_material.albedo_color = Color.YELLOW  # Yellow for box collision
				debug_mesh.set_surface_override_material(0, debug_material)
				debug_mesh.transform = collision_shape.transform
				static_body.add_child(debug_mesh)
				print("      Added debug visualization for box collision: ", collision_shape.name)
			
			else:
				# Fallback for other shape types
				var shape_aabb = collision_shape.get_aabb()
				var box_mesh = BoxMesh.new()
				box_mesh.size = shape_aabb.size
				debug_mesh.mesh = box_mesh
				debug_material.albedo_color = Color.WHITE  # White for unknown shapes
				debug_mesh.set_surface_override_material(0, debug_material)
				debug_mesh.position = shape_aabb.get_center()
				debug_mesh.transform.basis = debug_mesh.transform.basis.scaled(collision_shape.scale)
				static_body.add_child(debug_mesh)
				print("      Added fallback debug visualization for: ", collision_shape.name)

# Call this function from the editor or via code to place an object
func place_object_at_position(new_position: Vector3):
	"""Helper function to place object at a specific position"""
	spawn_position = new_position
	place_object()

# Call this function to check if the object has collision
func has_collision() -> bool:
	"""Check if the placed object has collision shapes"""
	if not placed_object or not is_instance_valid(placed_object):
		return false
	
	var static_bodies = _find_static_bodies_recursive(placed_object)
	return static_bodies.size() > 0

# Get collision information for debugging
func get_collision_info() -> Dictionary:
	"""Get information about the collision shapes of the placed object"""
	var info = {
		"has_collision": false,
		"static_body_count": 0,
		"collision_shape_count": 0,
		"shape_types": []
	}
	
	if not placed_object or not is_instance_valid(placed_object):
		return info
	
	var static_bodies = _find_static_bodies_recursive(placed_object)
	info.has_collision = static_bodies.size() > 0
	info.static_body_count = static_bodies.size()
	
	for static_body in static_bodies:
		for child in static_body.get_children():
			if child is CollisionShape3D:
				info.collision_shape_count += 1
				var shape = child.shape
				if shape:
					info.shape_types.append(shape.get_class())
	
	return info 