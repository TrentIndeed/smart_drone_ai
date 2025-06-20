@tool
extends EditorScript

# Test terrain texture loading
# Run from Tools > Execute Script

func _run():
	print("=== Testing Terrain Texture Loading ===")
	
	test_texture_loading("res://Main_slot0_albedo_bump.png", "Albedo Bump")
	test_texture_loading("res://Main_slot0_normal_roughness.png", "Normal Roughness")
	
	print("=== Test Complete ===")
	print("If any textures failed to load, restart Godot to apply import changes.")

func test_texture_loading(path: String, name: String):
	print("\nTesting: ", name)
	print("Path: ", path)
	
	# Check if file exists
	if not FileAccess.file_exists(path):
		print("  ❌ File does not exist!")
		return
	
	print("  ✅ File exists")
	
	# Try to load the texture
	var texture = load(path)
	if texture:
		print("  ✅ Texture loaded successfully")
		print("    Size: ", texture.get_width(), "x", texture.get_height())
		print("    Type: ", texture.get_class())
		
		# Test if it's a valid texture
		if texture is Texture2D:
			print("  ✅ Valid Texture2D")
		else:
			print("  ⚠️  Not a Texture2D - Type: ", type_string(typeof(texture)))
	else:
		print("  ❌ FAILED TO LOAD - This is the source of your error!")
		print("    Check import settings and restart Godot")

# Additional diagnostic function
func check_import_files():
	print("\nChecking import files...")
	
	var import_files = [
		"res://Main_slot0_albedo_bump.png.import",
		"res://Main_slot0_normal_roughness.png.import"
	]
	
	for import_path in import_files:
		if FileAccess.file_exists(import_path):
			print("  ✅ ", import_path.get_file())
		else:
			print("  ❌ Missing: ", import_path.get_file()) 