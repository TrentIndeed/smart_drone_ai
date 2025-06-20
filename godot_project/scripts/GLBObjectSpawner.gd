extends Node3D
class_name GLBObjectSpawner

# GLB Object Spawner - Procedurally places environment objects from Kenney GLB pack
# Assumes collision shapes are generated during import via Godot's "Generate Collision" option
# Only spawns environment objects, not characters

signal objects_spawned(count: int)

@export var spawn_count: int = 8
@export var grid_size: Vector2 = Vector2(10, 10)
@export var cell_size: float = 0.8
@export var min_distance_between_objects: float = 1.5
@export var enable_collision: bool = true
@export var collision_layer: int = 2  # Collision layer for spawned objects
@export var collision_mask: int = 0   # Collision mask for spawned objects
@export var debug_collision_shapes: bool = true  # Show collision shape wireframes

# GLB environment object paths (excluding characters)
# NOTE: These should be imported with "Generate Collision" enabled in Godot's Import tab
var environment_objects = [
	"res://addons/GLB format/banner.glb",
	"res://addons/GLB format/block.glb",
	"res://addons/GLB format/border-corner.glb",
	"res://addons/GLB format/border-straight.glb",
	"res://addons/GLB format/bricks.glb",
	"res://addons/GLB format/column-damaged.glb",
	"res://addons/GLB format/column.glb",
	"res://addons/GLB format/floor-detail.glb",
	"res://addons/GLB format/floor.glb",
	"res://addons/GLB format/stairs-corner-inner.glb",
	"res://addons/GLB format/stairs-corner.glb",
	"res://addons/GLB format/stairs.glb",
	"res://addons/GLB format/statue.glb",
	"res://addons/GLB format/tree.glb",
	"res://addons/GLB format/trophy.glb",
	"res://addons/GLB format/wall-corner.glb",
	"res://addons/GLB format/wall-gate.glb",
	"res://addons/GLB format/wall.glb",
	"res://addons/GLB format/weapon-rack.glb",
	"res://addons/GLB format/weapon-spear.glb",
	"res://addons/GLB format/weapon-sword.glb"
]

# Spawned objects array
var spawned_objects: Array[Node3D] = []

func _ready():
	print("GLBObjectSpawner initialized")
	print("COLLISION NOTICE: Ensure all GLB objects are imported with 'Generate Collision' enabled")

func spawn_objects():
	"""Spawn environment objects procedurally"""
	print("=== GLB SPAWNER DEBUG ===")
	print("Spawning ", spawn_count, " GLB environment objects...")
	print("Available objects: ", environment_objects.size())
	print("Enable collision: ", enable_collision)
	print("Grid size: ", grid_size)
	print("Cell size: ", cell_size)
	print("Using pre-imported collision shapes (Generate Collision must be enabled during import)")
	
	# Clear any existing objects
	clear_objects()
	
	var successful_spawns = 0
	var max_attempts = spawn_count * 3  # Allow multiple attempts per object
	var attempts = 0
	
	while successful_spawns < spawn_count and attempts < max_attempts:
		attempts += 1
		print("Attempt ", attempts, "/", max_attempts)
		
		# Choose random object
		var object_path = environment_objects[randi() % environment_objects.size()]
		print("Trying to spawn: ", object_path)
		
		# Find safe spawn position
		var spawn_pos = _find_safe_spawn_position()
		if spawn_pos == Vector3.INF:
			print("Could not find safe spawn position, skipping...")
			continue  # Skip if no safe position found
		
		print("Found spawn position: ", spawn_pos)
		
		# Load and instantiate the GLB object
		var object_scene = load(object_path)
		if not object_scene:
			print("ERROR: Failed to load GLB object: ", object_path)
			continue
		
		print("Loaded scene successfully")
		
		var object_instance = object_scene.instantiate()
		if not object_instance:
			print("ERROR: Failed to instantiate GLB object: ", object_path)
			continue
		
		print("Instantiated object successfully")
		
		# Add to scene
		add_child(object_instance)
		object_instance.position = spawn_pos
		print("Added to scene at position: ", spawn_pos)
		
		# Add random rotation for variety
		object_instance.rotation.y = randf() * TAU
		
		# Configure collision if requested
		if enable_collision:
			print("Configuring imported collision...")
			_configure_imported_collision(object_instance)
		
		# Add to tracking arrays
		spawned_objects.append(object_instance)
		object_instance.add_to_group("obstacles")
		object_instance.add_to_group("glb_objects")
		
		# Set a name for easier debugging
		var object_name = object_path.get_file().get_basename()
		object_instance.name = object_name + "_" + str(successful_spawns)
		
		successful_spawns += 1
		print("SUCCESS: Spawned ", object_instance.name, " at ", spawn_pos)
	
	print("=== SPAWN COMPLETE ===")
	print("Successfully spawned ", successful_spawns, " GLB objects (", attempts, " attempts)")
	objects_spawned.emit(successful_spawns)

func clear_objects():
	"""Clear all spawned objects"""
	for obj in spawned_objects:
		if is_instance_valid(obj):
			obj.queue_free()
	spawned_objects.clear()
	
	# Also clear any existing GLB objects
	var existing_glb_objects = get_tree().get_nodes_in_group("glb_objects")
	for obj in existing_glb_objects:
		if is_instance_valid(obj):
			obj.queue_free()

func _find_safe_spawn_position() -> Vector3:
	"""Find a safe position to spawn an object"""
	var max_attempts = 20
	var attempts = 0
	
	print("Finding safe spawn position...")
	
	while attempts < max_attempts:
		attempts += 1
		
		# Generate random grid position
		var grid_x = randi() % int(grid_size.x)
		var grid_z = randi() % int(grid_size.y)
		var world_pos = _grid_to_world(Vector2(grid_x, grid_z))
		world_pos.y = 0.0  # Place on ground
		
		print("Trying position attempt ", attempts, ": grid(", grid_x, ",", grid_z, ") -> world", world_pos)
		
		# Check if position is safe
		if _is_position_safe(world_pos):
			print("Position is safe!")
			return world_pos
		else:
			print("Position not safe, trying again...")
	
	print("ERROR: Could not find safe spawn position after ", max_attempts, " attempts")
	return Vector3.INF  # Return invalid position

func _is_position_safe(pos: Vector3) -> bool:
	"""Check if a position is safe for spawning"""
	var safe_distance = min_distance_between_objects
	
	print("  Checking position safety for: ", pos)
	print("  Safe distance: ", safe_distance)
	print("  Existing spawned objects: ", spawned_objects.size())
	
	# Check boundaries first (more efficient)
	var margin = 0.5  # Reduced margin
	var world_min_x = -grid_size.x * cell_size * 0.5 + margin
	var world_max_x = grid_size.x * cell_size * 0.5 - margin
	var world_min_z = -grid_size.y * cell_size * 0.5 + margin  # Use grid_size.y for Z
	var world_max_z = grid_size.y * cell_size * 0.5 - margin
	
	print("  Boundary check: x(", world_min_x, " to ", world_max_x, "), z(", world_min_z, " to ", world_max_z, ")")
	print("  Position: x=", pos.x, " z=", pos.z)
	
	if pos.x < world_min_x or pos.x > world_max_x or pos.z < world_min_z or pos.z > world_max_z:
		print("  UNSAFE: Outside boundaries")
		return false
	
	# Check distance from existing spawned objects
	for obj in spawned_objects:
		if is_instance_valid(obj):
			var distance = pos.distance_to(obj.position)
			if distance < safe_distance:
				print("  UNSAFE: Too close to existing object at ", obj.position, " (distance: ", distance, ")")
				return false
	
	# Check distance from other obstacles (like manually placed ones) - but exclude GLB objects
	var existing_obstacles = get_tree().get_nodes_in_group("obstacles")
	print("  Existing obstacles in scene: ", existing_obstacles.size())
	for obstacle in existing_obstacles:
		if is_instance_valid(obstacle) and not obstacle.is_in_group("glb_objects"):
			var distance = pos.distance_to(obstacle.position)
			if distance < safe_distance:
				print("  UNSAFE: Too close to existing obstacle at ", obstacle.position, " (distance: ", distance, ")")
				return false
	
	# Skip physics overlap check for now - it's causing issues
	print("  SAFE: Position passed all checks")
	return true

func _grid_to_world(grid_pos: Vector2) -> Vector3:
	"""Convert grid coordinates to world coordinates"""
	var world_x = (grid_pos.x - grid_size.x * 0.5) * cell_size
	var world_z = (grid_pos.y - grid_size.y * 0.5) * cell_size
	return Vector3(world_x, 0.0, world_z)

func _configure_imported_collision(object_node: Node3D):
	"""Configure collision layers/masks for imported collision shapes"""
	print("    Configuring imported collision for object: ", object_node.name)
	
	# Find and configure all StaticBody3D nodes (generated during import)
	var static_bodies = _find_static_bodies_recursive(object_node)
	
	if static_bodies.size() == 0:
		print("    WARNING: No StaticBody3D nodes found. Creating manual collision...")
		_create_manual_collision(object_node)
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
			debug_material.albedo_color = Color.BLUE  # Blue for GLB imported collision
			
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
					debug_material.albedo_color = Color.ORANGE  # Orange for trimesh collision
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
				debug_material.albedo_color = Color.MAGENTA  # Magenta for unknown shapes
				debug_mesh.set_surface_override_material(0, debug_material)
				debug_mesh.position = shape_aabb.get_center()
				debug_mesh.transform.basis = debug_mesh.transform.basis.scaled(collision_shape.scale)
				static_body.add_child(debug_mesh)
				print("      Added fallback debug visualization for: ", collision_shape.name)

func _create_manual_collision(object_node: Node3D):
	"""Create manual collision when imported collision isn't available"""
	print("      Creating manual collision for: ", object_node.name)
	
	# Find all MeshInstance3D nodes in the object
	var mesh_instances = _find_mesh_instances_recursive(object_node)
	
	if mesh_instances.size() == 0:
		print("      ERROR: No MeshInstance3D nodes found for collision creation")
		return
	
	print("      Found ", mesh_instances.size(), " mesh instances for collision")
	
	# Create a StaticBody3D to hold all collision shapes
	var static_body = StaticBody3D.new()
	static_body.name = object_node.name + "_collision"
	static_body.collision_layer = collision_layer
	static_body.collision_mask = collision_mask
	object_node.add_child(static_body)
	
	# Create collision shapes for each mesh
	for mesh_instance in mesh_instances:
		if mesh_instance.mesh == null:
			continue
		
		var collision_shape = CollisionShape3D.new()
		collision_shape.name = mesh_instance.name + "_shape"
		
		# Create convex collision shape from mesh
		var shape = mesh_instance.mesh.create_convex_shape()
		if shape:
			collision_shape.shape = shape
			collision_shape.transform = mesh_instance.transform
			static_body.add_child(collision_shape)
			print("        Created convex collision for: ", mesh_instance.name)
			
			# Add debug visualization
			if debug_collision_shapes:
				_add_debug_visualization_for_manual_collision(static_body, collision_shape)
		else:
			print("        ERROR: Failed to create convex shape for: ", mesh_instance.name)
	
	print("      Manual collision creation complete for: ", object_node.name)

func _find_mesh_instances_recursive(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find all MeshInstance3D nodes"""
	var mesh_instances: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		mesh_instances.append(node as MeshInstance3D)
	
	# Recursively check children
	for child in node.get_children():
		mesh_instances.append_array(_find_mesh_instances_recursive(child))
	
	return mesh_instances

func _add_debug_visualization_for_manual_collision(static_body: StaticBody3D, collision_shape: CollisionShape3D):
	"""Add debug visualization for manually created collision shapes"""
	var debug_mesh = MeshInstance3D.new()
	debug_mesh.name = "DEBUG_" + collision_shape.name
	
	var shape = collision_shape.shape
	var debug_material = StandardMaterial3D.new()
	debug_material.flags_unshaded = true
	debug_material.wireframe = true
	debug_material.flags_transparent = true
	debug_material.albedo_color = Color.GREEN  # Green for manual collision
	
	if shape is ConvexPolygonShape3D:
		var shape_debug_mesh = shape.get_debug_mesh()
		if shape_debug_mesh:
			debug_mesh.mesh = shape_debug_mesh
			debug_mesh.set_surface_override_material(0, debug_material)
			debug_mesh.transform = collision_shape.transform
			static_body.add_child(debug_mesh)
			print("        Added debug visualization for manual collision: ", collision_shape.name)

func get_spawned_objects() -> Array[Node3D]:
	"""Get array of all spawned objects"""
	return spawned_objects.duplicate()

func get_object_count() -> int:
	"""Get count of successfully spawned objects"""
	return spawned_objects.size() 
