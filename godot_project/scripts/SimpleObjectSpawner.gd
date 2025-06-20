extends Node3D
class_name SimpleObjectSpawner

# Environment Object Spawner - Uses GLB format objects for reliable collision
# Assumes collision shapes are generated during import via Godot's "Generate Collision" option

signal objects_spawned(count: int)

@export var spawn_count: int = 43  # Number of objects to spawn (1.7x more than original 25)
@export var grid_size: Vector2 = Vector2(15, 15)  # 15x15 grid for dense distribution
@export var cell_size: float = 0.65  # Size of each grid cell
@export var min_distance_between_objects: float = 0.7  # Minimum distance between objects
@export var use_grid_distribution: bool = true  # Whether to use grid-based distribution
@export var debug_collision_shapes: bool = true  # Show collision shape wireframes
@export var collision_layer: int = 2  # Collision layer for spawned objects
@export var collision_mask: int = 0   # Collision mask for spawned objects

# Spawned objects array
var spawned_objects: Array[Node3D] = []

# Environment objects to spawn - Using GLB format for reliable collision
# NOTE: These should be imported with "Generate Collision" enabled in Godot's Import tab
var environment_objects: Array[String] = [
	# Core GLB objects that support collision well
	"res://addons/GLB format/tree.glb",
	"res://addons/GLB format/block.glb",
	"res://addons/GLB format/column.glb",
	"res://addons/GLB format/column-damaged.glb",
	"res://addons/GLB format/statue.glb",
	"res://addons/GLB format/bricks.glb",
	"res://addons/GLB format/wall.glb",
	"res://addons/GLB format/wall-corner.glb",
	"res://addons/GLB format/banner.glb",
	"res://addons/GLB format/trophy.glb",
	"res://addons/GLB format/weapon-rack.glb",
	"res://addons/GLB format/stairs.glb",
	"res://addons/GLB format/stairs-corner.glb",
	"res://addons/GLB format/border-straight.glb",
	"res://addons/GLB format/border-corner.glb",
	"res://addons/GLB format/floor.glb",
	"res://addons/GLB format/floor-detail.glb"
]

func _ready():
	print("SimpleObjectSpawner initialized")
	print("COLLISION NOTICE: Using GLB objects with automatic collision generation")
	print("Ensure all GLB objects are imported with 'Generate Collision' enabled")

func spawn_objects():
	"""Spawn natural environment objects with even distribution"""
	print("=== ENVIRONMENT SPAWNER DEBUG ===")
	print("Spawning ", spawn_count, " GLB environment objects...")
	print("Available models: ", environment_objects.size())
	print("Grid distribution: ", use_grid_distribution)
	print("Using pre-imported GLB collision shapes (Generate Collision must be enabled during import)")
	
	# Clear any existing objects
	clear_objects()
	
	var successful_spawns = 0
	
	if use_grid_distribution:
		successful_spawns = _spawn_with_grid_distribution()
	else:
		successful_spawns = _spawn_with_random_distribution()
	
	print("=== ENVIRONMENT SPAWN COMPLETE ===")
	print("Successfully spawned ", successful_spawns, " environment objects")
	objects_spawned.emit(successful_spawns)

func _spawn_with_grid_distribution() -> int:
	"""Spawn objects using a grid-based distribution for even coverage"""
	print("Using grid distribution for even coverage...")
	
	var successful_spawns = 0
	var grid_cells = []
	
	# Create a list of all grid cells
	for x in range(int(grid_size.x)):
		for z in range(int(grid_size.y)):
			grid_cells.append(Vector2(x, z))
	
	# Shuffle the grid cells for random variety
	grid_cells.shuffle()
	
	# Try to place objects in grid cells
	var max_objects = min(spawn_count, grid_cells.size())
	
	for i in range(max_objects):
		var grid_pos = grid_cells[i]
		
		# Add some randomness within the grid cell
		var offset_x = randf_range(-0.3, 0.3)
		var offset_z = randf_range(-0.3, 0.3)
		var world_pos = _grid_to_world(grid_pos)
		world_pos.x += offset_x
		world_pos.z += offset_z
		world_pos.y = 0.0
		
		print("Grid spawn attempt ", i + 1, "/", max_objects, " at grid(", grid_pos.x, ",", grid_pos.y, ") -> world", world_pos)
		
		# Check if position is safe (but with relaxed constraints for grid placement)
		if _is_position_safe_relaxed(world_pos):
			# Choose random environment object
			var object_path = environment_objects[randi() % environment_objects.size()]
			print("  Loading GLB model: ", object_path)
			
			# Load and create the object
			var obstacle = _create_environment_obstacle(object_path, world_pos)
			if obstacle:
				add_child(obstacle)
				spawned_objects.append(obstacle)
				obstacle.add_to_group("obstacles")
				obstacle.add_to_group("environment_objects")
				
				successful_spawns += 1
				print("  SUCCESS: Grid placed ", obstacle.name, " at ", world_pos)
			else:
				print("  ERROR: Failed to create obstacle from ", object_path)
		else:
			print("  Position not safe, skipping...")
	
	return successful_spawns

func _spawn_with_random_distribution() -> int:
	"""Spawn objects using random distribution (original method)"""
	print("Using random distribution...")
	
	var successful_spawns = 0
	var max_attempts = spawn_count * 3
	var attempts = 0
	
	while successful_spawns < spawn_count and attempts < max_attempts:
		attempts += 1
		print("Random spawn attempt ", attempts, "/", max_attempts)
		
		# Choose random environment object
		var object_path = environment_objects[randi() % environment_objects.size()]
		print("Loading GLB model: ", object_path)
		
		# Find safe spawn position
		var spawn_pos = _find_safe_spawn_position()
		if spawn_pos == Vector3.INF:
			print("Could not find safe position, skipping...")
			continue
		
		print("Spawning at position: ", spawn_pos)
		
		# Load and create the object
		var obstacle = _create_environment_obstacle(object_path, spawn_pos)
		if obstacle:
			add_child(obstacle)
			spawned_objects.append(obstacle)
			obstacle.add_to_group("obstacles")
			obstacle.add_to_group("environment_objects")
			
			successful_spawns += 1
			print("SUCCESS: Created ", obstacle.name, " at ", spawn_pos)
		else:
			print("ERROR: Failed to create obstacle from ", object_path)
	
	return successful_spawns

func _create_environment_obstacle(model_path: String, pos: Vector3) -> Node3D:
	"""Load and create an environment obstacle from a GLB file with pre-imported collision"""
	print("  Loading GLB model: ", model_path)
	
	# Load the model scene
	var model_scene = load(model_path)
	if not model_scene:
		print("  ERROR: Could not load GLB model from: ", model_path)
		return null
	
	print("  GLB model loaded successfully")
	
	# Instantiate the model
	var model_instance = model_scene.instantiate()
	if not model_instance:
		print("  ERROR: Could not instantiate GLB model")
		return null
	
	print("  GLB model instantiated successfully")
	
	# Set position and rotation
	model_instance.position = pos
	model_instance.rotation.y = randf() * TAU  # Random rotation for variety
	
	# Set name based on model file
	var model_name = model_path.get_file().get_basename()
	model_instance.name = model_name + "_" + str(spawned_objects.size())
	
	# Configure collision for the pre-imported collision shapes
	_configure_imported_collision(model_instance)
	
	print("  Created GLB environment obstacle successfully: ", model_instance.name)
	return model_instance

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
			debug_material.albedo_color = Color.GREEN  # Green for imported collision
			
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
					debug_material.albedo_color = Color.CYAN  # Cyan for trimesh collision
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

func clear_objects():
	"""Clear all spawned objects"""
	print("Clearing existing environment objects...")
	for obj in spawned_objects:
		if is_instance_valid(obj):
			obj.queue_free()
	spawned_objects.clear()
	
	# Also clear any existing environment objects
	var existing_objects = get_tree().get_nodes_in_group("environment_objects")
	for obj in existing_objects:
		if is_instance_valid(obj):
			obj.queue_free()

func _find_safe_spawn_position() -> Vector3:
	"""Find a safe position to spawn an object"""
	var max_attempts = 15
	var attempts = 0
	
	while attempts < max_attempts:
		attempts += 1
		
		# Generate random grid position
		var grid_x = randi() % int(grid_size.x)
		var grid_z = randi() % int(grid_size.y)
		var world_pos = _grid_to_world(Vector2(grid_x, grid_z))
		world_pos.y = 0.0  # Place on ground
		
		print("  Trying position: grid(", grid_x, ",", grid_z, ") -> world", world_pos)
		
		# Check if position is safe
		if _is_position_safe(world_pos):
			print("  Position is safe!")
			return world_pos
	
	print("  Could not find safe position after ", max_attempts, " attempts")
	return Vector3.INF

func _is_position_safe(pos: Vector3) -> bool:
	"""Check if a position is safe for spawning"""
	var safe_distance = min_distance_between_objects
	
	# Check distance from existing objects
	for obj in spawned_objects:
		if is_instance_valid(obj):
			var distance = pos.distance_to(obj.position)
			if distance < safe_distance:
				print("    Too close to existing object (distance: ", distance, ")")
				return false
	
	# Check distance from other obstacles
	var existing_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obstacle in existing_obstacles:
		if is_instance_valid(obstacle):
			var distance = pos.distance_to(obstacle.position)
			if distance < safe_distance:
				print("    Too close to existing obstacle (distance: ", distance, ")")
				return false
	
	# Check boundaries
	var margin = 0.5
	var world_min = -grid_size.x * cell_size * 0.5 + margin
	var world_max = grid_size.x * cell_size * 0.5 - margin
	
	if pos.x < world_min or pos.x > world_max or pos.z < world_min or pos.z > world_max:
		print("    Outside boundaries")
		return false
	
	print("    Position is safe")
	return true

func _is_position_safe_relaxed(pos: Vector3) -> bool:
	"""Check if position is safe with relaxed constraints for grid placement"""
	var safe_distance = min_distance_between_objects * 0.7  # Relaxed distance for grid
	
	# Check distance from existing objects
	for obj in spawned_objects:
		if is_instance_valid(obj):
			var distance = pos.distance_to(obj.position)
			if distance < safe_distance:
				print("    Too close to existing object (distance: ", distance, ")")
				return false
	
	# Check boundaries - allow objects closer to edges
	var margin = 0.2  # Smaller margin for edge-to-edge coverage
	var world_min = -grid_size.x * cell_size * 0.5 + margin
	var world_max = grid_size.x * cell_size * 0.5 - margin
	
	if pos.x < world_min or pos.x > world_max or pos.z < world_min or pos.z > world_max:
		print("    Outside relaxed boundaries")
		return false
	
	return true

func _grid_to_world(grid_pos: Vector2) -> Vector3:
	"""Convert grid coordinates to world coordinates"""
	var world_x = (grid_pos.x - grid_size.x * 0.5) * cell_size
	var world_z = (grid_pos.y - grid_size.y * 0.5) * cell_size
	return Vector3(world_x, 0.0, world_z)

func get_spawned_objects() -> Array[Node3D]:
	"""Get array of all spawned objects"""
	return spawned_objects.duplicate()

func get_object_count() -> int:
	"""Get count of successfully spawned objects"""
	return spawned_objects.size() 
