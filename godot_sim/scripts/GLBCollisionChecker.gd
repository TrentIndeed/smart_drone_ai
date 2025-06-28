@tool
extends EditorScript

# Quick GLB collision checker - run in editor to see which files have collision

func _run():
	print("=== GLB COLLISION STATUS CHECK ===")
	
	var glb_files = [
		"res://addons/GLB format/tree.glb",
		"res://addons/GLB format/banner.glb",
		"res://addons/GLB format/wall.glb",
		"res://addons/GLB format/block.glb",
		"res://addons/GLB format/column.glb"
	]
	
	for glb_path in glb_files:
		print("\nChecking: ", glb_path)
		
		# Try to load the GLB
		var scene = load(glb_path)
		if not scene:
			print("  ❌ FAILED to load GLB file")
			continue
		
		# Instantiate it
		var instance = scene.instantiate()
		if not instance:
			print("  ❌ FAILED to instantiate GLB")
			continue
		
		# Check for StaticBody3D nodes
		var static_bodies = _find_static_bodies(instance)
		if static_bodies.size() > 0:
			print("  ✅ HAS COLLISION: Found ", static_bodies.size(), " StaticBody3D nodes")
		else:
			print("  ❌ NO COLLISION: No StaticBody3D nodes found")
		
		# Clean up
		instance.queue_free()
	
	print("\n=== CHECK COMPLETE ===")

func _find_static_bodies(node: Node) -> Array:
	var static_bodies = []
	
	if node is StaticBody3D:
		static_bodies.append(node)
	
	for child in node.get_children():
		static_bodies.append_array(_find_static_bodies(child))
	
	return static_bodies 
