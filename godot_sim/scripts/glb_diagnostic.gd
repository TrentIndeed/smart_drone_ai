@tool
extends EditorScript

# GLB Diagnostic Script - Check GLB file locations and collision status

func _run():
	print("=== GLB DIAGNOSTIC SCRIPT ===")
	print("Checking GLB file locations and collision status...")
	
	# Check multiple possible locations for GLB files
	var possible_paths = [
		"res://addons/GLB format/",
		"res://assets/GLB format/",
		"res://addons/",
		"res://assets/"
	]
	
	for path in possible_paths:
		print("\n--- Checking path: ", path, " ---")
		_check_directory_for_glb(path)
	
	# Check the specific files that GLBObjectSpawner tries to load
	print("\n=== CHECKING GLBObjectSpawner FILE REFERENCES ===")
	var spawner_files = [
		"res://addons/GLB format/banner.glb",
		"res://addons/GLB format/block.glb",
		"res://addons/GLB format/tree.glb",
		"res://addons/GLB format/column.glb"
	]
	
	for file_path in spawner_files:
		print("\n--- Checking: ", file_path, " ---")
		_check_glb_file_collision(file_path)
	
	print("\n=== DIAGNOSTIC COMPLETE ===")

func _check_directory_for_glb(dir_path: String):
	"""Check a directory for GLB files"""
	var dir = DirAccess.open(dir_path)
	if dir == null:
		print("  ✗ Directory not found: ", dir_path)
		return
	
	print("  ✓ Directory exists: ", dir_path)
	
	# List GLB files
	var glb_files = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".glb"):
			glb_files.append(file_name)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	
	if glb_files.size() > 0:
		print("  Found ", glb_files.size(), " GLB files:")
		for file in glb_files:
			print("    - ", file)
			
			# Check collision for first few files
			if glb_files.find(file) < 3:  # Check first 3 files
				var full_path = dir_path + file
				_check_glb_file_collision(full_path)
	else:
		print("  No GLB files found in this directory")

func _check_glb_file_collision(file_path: String):
	"""Check if a GLB file has collision enabled"""
	print("    Checking collision for: ", file_path)
	
	# Check if file exists
	if not FileAccess.file_exists(file_path):
		print("      ✗ File does not exist")
		return
	
	# Check import file
	var import_file_path = file_path + ".import"
	if not FileAccess.file_exists(import_file_path):
		print("      ✗ Import file does not exist: ", import_file_path)
		return
	
	# Read import file
	var import_file = FileAccess.open(import_file_path, FileAccess.READ)
	if import_file == null:
		print("      ✗ Could not read import file")
		return
	
	var import_content = import_file.get_as_text()
	import_file.close()
	
	# Check for collision settings
	var has_physics_bodies = import_content.contains("meshes/create_physics_bodies=true")
	var root_type = ""
	
	var lines = import_content.split("\n")
	for line in lines:
		if line.strip_edges().begins_with("nodes/root_type="):
			root_type = line.strip_edges()
			break
	
	print("      Import settings:")
	print("        create_physics_bodies: ", has_physics_bodies)
	print("        root_type: ", root_type)
	
	# Try to load and check for collision
	var scene = load(file_path)
	if scene == null:
		print("      ✗ Could not load scene")
		return
	
	var instance = scene.instantiate()
	if instance == null:
		print("      ✗ Could not instantiate scene")
		return
	
	# Check for StaticBody3D nodes
	var static_bodies = _find_static_bodies_recursive(instance)
	var collision_shapes = _find_collision_shapes_recursive(instance)
	
	print("      Runtime collision check:")
	print("        StaticBody3D nodes found: ", static_bodies.size())
	print("        CollisionShape3D nodes found: ", collision_shapes.size())
	
	if static_bodies.size() > 0:
		print("      ✓ HAS COLLISION")
	else:
		print("      ✗ NO COLLISION")
	
	# Clean up
	instance.queue_free()

func _find_static_bodies_recursive(node: Node) -> Array:
	"""Recursively find all StaticBody3D nodes"""
	var static_bodies = []
	
	if node is StaticBody3D:
		static_bodies.append(node)
	
	for child in node.get_children():
		static_bodies.append_array(_find_static_bodies_recursive(child))
	
	return static_bodies

func _find_collision_shapes_recursive(node: Node) -> Array:
	"""Recursively find all CollisionShape3D nodes"""
	var collision_shapes = []
	
	if node is CollisionShape3D:
		collision_shapes.append(node)
	
	for child in node.get_children():
		collision_shapes.append_array(_find_collision_shapes_recursive(child))
	
	return collision_shapes 