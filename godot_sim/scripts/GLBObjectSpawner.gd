extends Node3D
class_name GLBObjectSpawner

# GLB Object Spawner - Procedurally places environment objects from Kenney GLB pack
# Assumes collision shapes are generated during import via Godot's "Generate Collision" option
# Only spawns environment objects, not characters

signal objects_spawned(count: int)

@export var spawn_count: int = 25
@export var grid_size: Vector2 = Vector2(15, 15)
@export var cell_size: float = 0.6
@export var min_distance_between_objects: float = 1.2
@export var enable_collision: bool = true
@export var collision_layer: int = 2  # Collision layer for spawned objects
@export var collision_mask: int = 0   # Collision mask for spawned objects
@export var debug_collision_shapes: bool = true  # Show collision shape wireframes

# GLB environment object paths (excluding characters)
# NOTE: These should be imported with "Generate Collision" enabled in Godot's Import tab
var environment_objects = [
	# Natural environment objects (higher weight for more natural terrain)
	"res://addons/GLB format/tree.glb",
	"res://addons/GLB format/tree.glb",
	"res://addons/GLB format/tree.glb",
	"res://addons/GLB format/block.glb",  # Rocks/boulders
	"res://addons/GLB format/block.glb",
	"res://addons/GLB format/bricks.glb",  # Rock formations
	"res://addons/GLB format/bricks.glb",
	
	# Structural elements
	"res://addons/GLB format/column.glb",
	"res://addons/GLB format/column-damaged.glb",
	"res://addons/GLB format/wall.glb",
	"res://addons/GLB format/wall-corner.glb",
	"res://addons/GLB format/border-straight.glb",
	"res://addons/GLB format/border-corner.glb",
	
	# Decorative elements
	"res://addons/GLB format/statue.glb",
	"res://addons/GLB format/trophy.glb",
	"res://addons/GLB format/banner.glb",
	"res://addons/GLB format/weapon-rack.glb",
	"res://addons/GLB format/weapon-spear.glb",
	"res://addons/GLB format/weapon-sword.glb",
	
	# Architectural elements
	"res://addons/GLB format/stairs.glb",
	"res://addons/GLB format/stairs-corner.glb",
	"res://addons/GLB format/stairs-corner-inner.glb",
	"res://addons/GLB format/wall-gate.glb",
	"res://addons/GLB format/floor-detail.glb"
]

# Spawned objects array
var spawned_objects: Array[Node3D] = []

func _ready():
	pass

func spawn_objects():
	"""Spawn environment objects procedurally"""
	# Clear any existing objects
	clear_objects()
	
	var successful_spawns = 0
	var max_attempts = spawn_count * 3  # Allow multiple attempts per object
	var attempts = 0
	
	while successful_spawns < spawn_count and attempts < max_attempts:
		attempts += 1
		
		# Choose random object
		var object_path = environment_objects[randi() % environment_objects.size()]
		
		# Find safe spawn position
		var spawn_pos = _find_safe_spawn_position()
		if spawn_pos == Vector3.INF:
			continue  # Skip if no safe position found
		
		# Load and instantiate the GLB object
		var object_scene = load(object_path)
		if not object_scene:
			continue
		
		var object_instance = object_scene.instantiate()
		if not object_instance:
			continue
		
		# Add to scene
		add_child(object_instance)
		
		# Adjust Y position based on object type to prevent ground clipping
		var adjusted_pos = spawn_pos
		var object_type = object_path.get_file().get_basename()
		adjusted_pos.y = _get_ground_offset_for_object(object_type)
		
		object_instance.position = adjusted_pos
		
		# Add random rotation for variety
		object_instance.rotation.y = randf() * TAU
		
		# Configure collision if requested
		if enable_collision:
			_configure_imported_collision(object_instance)
		
		# Add to tracking arrays
		spawned_objects.append(object_instance)
		object_instance.add_to_group("obstacles")
		object_instance.add_to_group("glb_objects")
		
		# Set a name for easier debugging
		object_instance.name = object_type + "_" + str(successful_spawns)
		
		successful_spawns += 1
	
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
	
	while attempts < max_attempts:
		attempts += 1
		
		# Generate random grid position
		var grid_x = randi() % int(grid_size.x)
		var grid_z = randi() % int(grid_size.y)
		var world_pos = _grid_to_world(Vector2(grid_x, grid_z))
		world_pos.y = 0.0  # Place on ground
		
		# Check if position is safe
		if _is_position_safe(world_pos):
			return world_pos
	
	return Vector3.INF  # Return invalid position

func _is_position_safe(pos: Vector3) -> bool:
	"""Check if a position is safe for spawning"""
	var safe_distance = min_distance_between_objects
	
	# Check boundaries first (more efficient)
	var margin = 0.5  # Reduced margin
	var world_min_x = -grid_size.x * cell_size * 0.5 + margin
	var world_max_x = grid_size.x * cell_size * 0.5 - margin
	var world_min_z = -grid_size.y * cell_size * 0.5 + margin  # Use grid_size.y for Z
	var world_max_z = grid_size.y * cell_size * 0.5 - margin
	
	if pos.x < world_min_x or pos.x > world_max_x or pos.z < world_min_z or pos.z > world_max_z:
		return false
	
	# Check distance from existing spawned objects
	for obj in spawned_objects:
		if is_instance_valid(obj):
			var distance = pos.distance_to(obj.position)
			if distance < safe_distance:
				return false
	
	# Check distance from other obstacles (like manually placed ones) - but exclude GLB objects
	var existing_obstacles = get_tree().get_nodes_in_group("obstacles")
	for obstacle in existing_obstacles:
		if is_instance_valid(obstacle) and not obstacle.is_in_group("glb_objects"):
			var distance = pos.distance_to(obstacle.position)
			if distance < safe_distance:
				return false
	
	# Skip physics overlap check for now - it's causing issues
	return true

func _grid_to_world(grid_pos: Vector2) -> Vector3:
	"""Convert grid coordinates to world coordinates"""
	var world_x = (grid_pos.x - grid_size.x * 0.5) * cell_size
	var world_z = (grid_pos.y - grid_size.y * 0.5) * cell_size
	return Vector3(world_x, 0.0, world_z)

func _configure_imported_collision(object_node: Node3D):
	"""Configure collision layers/masks for imported collision shapes"""
	# Find and configure all StaticBody3D nodes (generated during import)
	var static_bodies = _find_static_bodies_recursive(object_node)
	
	if static_bodies.size() == 0:
		_create_manual_collision(object_node)
		return
	
	# Configure each StaticBody3D
	for static_body in static_bodies:
		static_body.collision_layer = collision_layer
		static_body.collision_mask = collision_mask
		
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
			
			elif shape is ConcavePolygonShape3D:
				# For trimesh shapes, create a wireframe from the shape data
				var shape_debug_mesh = shape.get_debug_mesh()
				if shape_debug_mesh:
					debug_mesh.mesh = shape_debug_mesh
					debug_material.albedo_color = Color.ORANGE  # Orange for trimesh collision
					debug_mesh.set_surface_override_material(0, debug_material)
					debug_mesh.transform = collision_shape.transform
					static_body.add_child(debug_mesh)
			
			elif shape is BoxShape3D:
				# Create box wireframe
				var box_mesh = BoxMesh.new()
				box_mesh.size = (shape as BoxShape3D).size
				debug_mesh.mesh = box_mesh
				debug_material.albedo_color = Color.YELLOW  # Yellow for box collision
				debug_mesh.set_surface_override_material(0, debug_material)
				debug_mesh.transform = collision_shape.transform
				static_body.add_child(debug_mesh)
			
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

func _create_manual_collision(object_node: Node3D):
	"""Create manual collision when imported collision isn't available"""
	
	# Find all MeshInstance3D nodes in the object
	var mesh_instances = _find_mesh_instances_recursive(object_node)
	
	if mesh_instances.size() == 0:
		return
	
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
			
			# Add debug visualization
			if debug_collision_shapes:
				_add_debug_visualization_for_manual_collision(static_body, collision_shape)

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

func get_spawned_objects() -> Array[Node3D]:
	"""Get array of all spawned objects"""
	return spawned_objects.duplicate()

func _get_ground_offset_for_object(object_name: String) -> float:
	"""Get appropriate ground offset for different object types"""
	match object_name:
		# Objects that should be slightly above ground
		"tree":
			return 0.1
		"statue":
			return 0.05
		"trophy":
			return 0.05
		"banner":
			return 0.0
		"weapon-rack":
			return 0.0
		"weapon-spear":
			return 0.0
		"weapon-sword":
			return 0.0
		
		# Structural objects at ground level
		"column", "column-damaged":
			return 0.0
		"wall", "wall-corner", "wall-gate":
			return 0.0
		"border-straight", "border-corner":
			return 0.0
		
		# Natural objects
		"block":  # Rocks/boulders
			return 0.0
		"bricks":  # Rock formations
			return 0.0
		
		# Architectural elements
		"stairs", "stairs-corner", "stairs-corner-inner":
			return 0.0
		"floor-detail":
			return -0.05  # Slightly below ground
		
		_:
			return 0.0  # Default ground level

func get_object_count() -> int:
	"""Get count of successfully spawned objects"""
	return spawned_objects.size() 
