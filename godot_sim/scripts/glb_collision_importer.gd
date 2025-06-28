@tool
extends EditorScript

# GLB Collision Importer - Automatically reimports all GLB files with collision enabled
# This script runs in the Godot editor to batch process GLB imports

func _run():
	print("=== GLB COLLISION IMPORTER ===")
	print("Starting batch reimport of GLB files with collision enabled...")
	
	# Path to GLB files
	var glb_directory = "res://addons/GLB format/"
	print("Scanning directory: ", glb_directory)
	
	# Get all GLB files in the directory
	var glb_files = _find_glb_files(glb_directory)
	
	if glb_files.size() == 0:
		print("ERROR: No GLB files found in ", glb_directory)
		print("Make sure the path is correct and GLB files exist")
		return
	
	print("Found ", glb_files.size(), " GLB files to process:")
	for file in glb_files:
		print("  - ", file)
	
	# Process each GLB file
	var success_count = 0
	var total_count = glb_files.size()
	
	for file_path in glb_files:
		print("\n--- Processing: ", file_path, " ---")
		
		if _reimport_glb_with_collision(file_path):
			success_count += 1
			print("✓ SUCCESS: ", file_path)
		else:
			print("✗ FAILED: ", file_path)
	
	print("\n=== REIMPORT COMPLETE ===")
	print("Successfully processed: ", success_count, "/", total_count, " files")
	print("GLB files are now ready for collision detection!")
	print("You can now use GLBObjectSpawner with collision enabled.")

func _find_glb_files(directory_path: String) -> Array[String]:
	"""Find all .glb files in the specified directory"""
	var glb_files: Array[String] = []
	
	var dir = DirAccess.open(directory_path)
	if dir == null:
		print("ERROR: Could not open directory: ", directory_path)
		return glb_files
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".glb"):
			var full_path = directory_path + file_name
			glb_files.append(full_path)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return glb_files

func _reimport_glb_with_collision(file_path: String) -> bool:
	"""Reimport a single GLB file with collision enabled"""
	print("  Configuring import settings for: ", file_path)
	
	# Get the .import file path
	var import_file_path = file_path + ".import"
	print("  Import file: ", import_file_path)
	
	# Check if import file exists
	if not FileAccess.file_exists(import_file_path):
		print("  ERROR: Import file not found: ", import_file_path)
		return false
	
	# Read the current import file
	var import_file = FileAccess.open(import_file_path, FileAccess.READ)
	if import_file == null:
		print("  ERROR: Could not open import file for reading")
		return false
	
	var import_content = import_file.get_as_text()
	import_file.close()
	
	# Modify the import settings
	var modified_content = _modify_import_settings(import_content)
	
	# Write the modified import file
	import_file = FileAccess.open(import_file_path, FileAccess.WRITE)
	if import_file == null:
		print("  ERROR: Could not open import file for writing")
		return false
	
	import_file.store_string(modified_content)
	import_file.close()
	
	print("  ✓ Import settings updated")
	
	# Force reimport using EditorInterface
	var filesystem = EditorInterface.get_resource_filesystem()
	if filesystem == null:
		print("  ERROR: Could not get resource filesystem")
		return false
	
	# Reimport the file
	filesystem.reimport_files([file_path])
	print("  ✓ File reimported")
	
	return true

func _modify_import_settings(content: String) -> String:
	"""Modify the import file content to enable collision"""
	var lines = content.split("\n")
	var modified_lines = []
	var in_params_section = false
	var found_physics_bodies = false
	var found_root_type = false
	
	for line in lines:
		var trimmed_line = line.strip_edges()
		
		# Check if we're in the [params] section
		if trimmed_line == "[params]":
			in_params_section = true
			modified_lines.append(line)
			continue
		elif trimmed_line.begins_with("[") and trimmed_line != "[params]":
			in_params_section = false
		
		# If we're in params section, look for settings to modify
		if in_params_section:
			if trimmed_line.begins_with("meshes/create_physics_bodies="):
				modified_lines.append("meshes/create_physics_bodies=true")
				found_physics_bodies = true
				print("    ✓ Updated create_physics_bodies to true")
				continue
			elif trimmed_line.begins_with("nodes/root_type="):
				modified_lines.append('nodes/root_type="Node3D"')
				found_root_type = true
				print("    ✓ Updated root_type to Node3D")
				continue
		
		# Keep the original line
		modified_lines.append(line)
	
	# If we didn't find the physics bodies setting, add it
	if not found_physics_bodies:
		# Find the [params] section and add the setting
		var params_index = -1
		for i in range(modified_lines.size()):
			if modified_lines[i].strip_edges() == "[params]":
				params_index = i
				break
		
		if params_index >= 0:
			modified_lines.insert(params_index + 1, "meshes/create_physics_bodies=true")
			print("    ✓ Added create_physics_bodies=true")
		else:
			print("    ⚠ Could not find [params] section to add physics bodies setting")
	
	# If we didn't find the root type setting, add it
	if not found_root_type:
		# Find the [params] section and add the setting
		var params_index = -1
		for i in range(modified_lines.size()):
			if modified_lines[i].strip_edges() == "[params]":
				params_index = i
				break
		
		if params_index >= 0:
			modified_lines.insert(params_index + 1, 'nodes/root_type="Node3D"')
			print("    ✓ Added root_type=Node3D")
		else:
			print("    ⚠ Could not find [params] section to add root type setting")
	
	return "\n".join(modified_lines)

# Helper function to validate that reimport worked (simplified version)
func _validate_reimport(file_path: String) -> bool:
	"""Check if the reimported file has collision shapes"""
	print("  Validating reimport for: ", file_path)
	
	# Load the reimported scene
	var scene = load(file_path)
	if scene == null:
		print("  ✗ Could not load reimported scene")
		return false
	
	# Instantiate to check for collision
	var instance = scene.instantiate()
	if instance == null:
		print("  ✗ Could not instantiate scene")
		return false
	
	# Check for StaticBody3D nodes (indicates collision was generated)
	var static_bodies = _find_static_bodies_recursive(instance)
	var has_collision = static_bodies.size() > 0
	
	# Clean up
	instance.queue_free()
	
	if has_collision:
		print("  ✓ Collision validation passed (", static_bodies.size(), " StaticBody3D nodes found)")
	else:
		print("  ⚠ No collision shapes found - collision generation may have failed")
	
	return has_collision

func _find_static_bodies_recursive(node: Node) -> Array:
	"""Recursively find all StaticBody3D nodes"""
	var static_bodies = []
	
	if node is StaticBody3D:
		static_bodies.append(node)
	
	for child in node.get_children():
		static_bodies.append_array(_find_static_bodies_recursive(child))
	
	return static_bodies 
