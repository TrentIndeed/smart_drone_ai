@tool
extends EditorScript

# DAE Diagnostic Script - Check what happened with DAE collision import

func _run():
	print("=== DAE DIAGNOSTIC SCRIPT ===")
	print("Checking DAE import settings and providing manual fix...")
	
	# Test a few specific DAE files that are being spawned
	var test_files = [
		"res://assets/tiles/Models/DAE format/stone_smallA.dae",
		"res://assets/tiles/Models/DAE format/tree_fat.dae",
		"res://assets/tiles/Models/DAE format/stump_square.dae"
	]
	
	for file_path in test_files:
		print("\n--- Checking: ", file_path, " ---")
		_check_and_fix_dae_file(file_path)
	
	print("\n=== MANUAL FIX COMPLETE ===")
	print("If this doesn't work, we'll use a different approach...")

func _check_and_fix_dae_file(file_path: String):
	"""Check and manually fix a DAE file's collision settings"""
	
	# Check if file exists
	if not FileAccess.file_exists(file_path):
		print("  ✗ File does not exist: ", file_path)
		return
	
	# Check import file
	var import_file_path = file_path + ".import"
	if not FileAccess.file_exists(import_file_path):
		print("  ✗ Import file does not exist: ", import_file_path)
		return
	
	print("  ✓ Files exist, checking import settings...")
	
	# Read current import settings
	var import_file = FileAccess.open(import_file_path, FileAccess.READ)
	var content = import_file.get_as_text()
	import_file.close()
	
	print("  Current import file content:")
	var lines = content.split("\n")
	for line in lines:
		if line.contains("create_physics_bodies") or line.contains("root_type") or line.contains("[params]"):
			print("    ", line)
	
	# Create a completely new import configuration
	var new_content = _create_collision_import_content()
	
	# Write the new import file
	import_file = FileAccess.open(import_file_path, FileAccess.WRITE)
	import_file.store_string(new_content)
	import_file.close()
	
	print("  ✓ Updated import file with collision settings")
	
	# Force reimport
	var filesystem = EditorInterface.get_resource_filesystem()
	filesystem.reimport_files([file_path])
	
	print("  ✓ Forced reimport")
	
	# Wait and check if it worked
	print("  Checking if collision was generated...")
	
	var scene = load(file_path)
	if scene:
		var instance = scene.instantiate()
		if instance:
			var static_bodies = _find_static_bodies_recursive(instance)
			if static_bodies.size() > 0:
				print("  ✓ SUCCESS: Found ", static_bodies.size(), " collision bodies")
			else:
				print("  ✗ FAILED: No collision bodies found")
			instance.queue_free()
		else:
			print("  ✗ Could not instantiate scene")
	else:
		print("  ✗ Could not load scene")

func _create_collision_import_content() -> String:
	"""Create a new import file content with collision enabled"""
	return """[remap]

importer="scene"
importer_version=1
type="PackedScene"
uid="uid://collision_enabled"
path="res://.godot/imported/collision.scn"

[deps]

source_file="res://assets/tiles/Models/DAE format/placeholder.dae"
dest_files=["res://.godot/imported/collision.scn"]

[params]

nodes/root_type="Node3D"
nodes/root_name=""
nodes/apply_root_scale=true
nodes/root_scale=1.0
meshes/ensure_tangents=true
meshes/generate_lods=true
meshes/create_physics_bodies=true
meshes/physics_body_type=1
meshes/force_disable_mesh_compression=false
skins/use_named_skins=true
animation/import=true
animation/fps=30
animation/trimming=false
animation/remove_immutable_tracks=true
import_script/path=""
_subresources={}
"""

func _find_static_bodies_recursive(node: Node) -> Array:
	"""Recursively find all StaticBody3D nodes"""
	var static_bodies = []
	
	if node is StaticBody3D:
		static_bodies.append(node)
	
	for child in node.get_children():
		static_bodies.append_array(_find_static_bodies_recursive(child))
	
	return static_bodies 