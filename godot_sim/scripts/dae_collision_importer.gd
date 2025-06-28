@tool
extends EditorScript

# DAE Collision Importer - Automatically reimports all DAE files with collision enabled
# This script runs in the Godot editor to batch process DAE imports

func _run():
	print("=== DAE COLLISION IMPORTER ===")
	print("Starting batch reimport of DAE files with collision enabled...")
	
	# Path to DAE files
	var dae_directory = "res://assets/tiles/Models/DAE format/"
	print("Scanning directory: ", dae_directory)
	
	# Get all DAE files in the directory
	var dae_files = _find_dae_files(dae_directory)
	
	if dae_files.size() == 0:
		print("ERROR: No DAE files found in ", dae_directory)
		print("Make sure the path is correct and DAE files exist")
		return
	
	print("Found ", dae_files.size(), " DAE files to process:")
	for file in dae_files:
		print("  - ", file)
	
	# Process each DAE file
	var success_count = 0
	var total_count = dae_files.size()
	
	for file_path in dae_files:
		print("\n--- Processing: ", file_path, " ---")
		
		if _reimport_dae_with_collision(file_path):
			success_count += 1
			print("✓ SUCCESS: ", file_path)
		else:
			print("✗ FAILED: ", file_path)
	
	print("\n=== REIMPORT COMPLETE ===")
	print("Successfully processed: ", success_count, "/", total_count, " files")
	print("DAE files are now ready for collision detection!")
	print("You can now use SimpleObjectSpawner with collision enabled.")

func _find_dae_files(directory_path: String) -> Array[String]:
	"""Find all .dae files in the specified directory"""
	var dae_files: Array[String] = []
	
	var dir = DirAccess.open(directory_path)
	if dir == null:
		print("ERROR: Could not open directory: ", directory_path)
		return dae_files
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if file_name.ends_with(".dae"):
			var full_path = directory_path + file_name
			dae_files.append(full_path)
		file_name = dir.get_next()
	
	dir.list_dir_end()
	return dae_files

func _reimport_dae_with_collision(file_path: String) -> bool:
	"""Reimport a single DAE file with collision enabled"""
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
