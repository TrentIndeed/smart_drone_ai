# Collision Workflow - Using Godot's Automatic Collision Generation

This document explains the updated collision handling approach for the Smart Drone AI project. We now use Godot's built-in automatic collision generation during import instead of manually creating CollisionShape3D nodes in GDScript.

## Workflow Overview

### 1. Asset Import Process

1. **Place Assets**: Put your 3D assets (`.glb`, `.obj`, `.dae` files) in the `godot_project/assets/` folder
2. **Select Asset**: In Godot's FileSystem dock, click on the 3D asset file
3. **Open Import Tab**: Go to the Import tab (usually next to Scene/Inspector)
4. **Enable Collision Generation**: Check the **"Generate Collision"** checkbox
5. **Reimport**: Click the "Reimport" button
6. **Verify**: The imported scene will now contain StaticBody3D + CollisionShape3D nodes automatically

### 2. Collision Types Generated

Godot can generate different types of collision shapes:
- **Convex Collision**: Fast, simple collision detection (good for most objects)
- **Trimesh Collision**: Precise collision detection (more expensive, good for complex static geometry)
- **Box Collision**: Simple box-shaped collision (fastest)

### 3. Updated Spawning Scripts

The following scripts have been updated to work with pre-imported collision:

#### SimpleObjectSpawner.gd
- **Purpose**: Spawns natural environment objects (trees, rocks, stones)
- **Assets**: Uses DAE format models from `assets/tiles/Models/DAE format/`
- **Collision**: Assumes collision is pre-generated during import
- **Debug**: Green wireframes for imported collision shapes

#### GLBObjectSpawner.gd  
- **Purpose**: Spawns GLB environment objects (buildings, structures)
- **Assets**: Uses GLB format models from `addons/GLB format/`
- **Collision**: Assumes collision is pre-generated during import
- **Debug**: Blue wireframes for imported collision shapes

## Script Configuration

### Export Variables

Both spawning scripts now include these collision-related export variables:

```gdscript
@export var collision_layer: int = 2  # Collision layer for spawned objects
@export var collision_mask: int = 0   # Collision mask for spawned objects  
@export var debug_collision_shapes: bool = false  # Show collision wireframes
```

### Collision Layer Setup

- **Layer 2**: Used for environment obstacles/objects
- **Mask 0**: Objects don't actively detect collisions (static obstacles)
- **Debug Mode**: Shows colored wireframes around collision shapes

## How It Works

### 1. Asset Loading
```gdscript
# Load the pre-imported scene (collision already included)
var model_scene = load(model_path)
var model_instance = model_scene.instantiate()
```

### 2. Collision Configuration
```gdscript
# Find all StaticBody3D nodes created during import
var static_bodies = _find_static_bodies_recursive(model_instance)

# Configure collision layers for each StaticBody3D
for static_body in static_bodies:
    static_body.collision_layer = collision_layer
    static_body.collision_mask = collision_mask
```

### 3. Debug Visualization
```gdscript
# Add colored wireframes to visualize collision shapes
if debug_collision_shapes:
    _add_debug_visualization_for_imported_collision(static_body)
```

## Advantages of This Approach

1. **Performance**: No runtime collision generation overhead
2. **Consistency**: Collision shapes are generated once during import
3. **Quality**: Godot's built-in collision generation is optimized
4. **Editor Preview**: You can see collision shapes in the editor
5. **Simplicity**: No complex GDScript collision generation code

## Troubleshooting

### No Collision Detected
**Problem**: Objects spawn but have no collision
**Solution**: 
1. Select the asset file in FileSystem
2. Go to Import tab
3. Check "Generate Collision" 
4. Click "Reimport"

### Console Warnings
You may see warnings like:
```
WARNING: No StaticBody3D nodes found. Ensure 'Generate Collision' was enabled during import!
To fix: Select the model in FileSystem, go to Import tab, check 'Generate Collision', then reimport
```

**Solution**: Follow the instructions in the warning message.

### Debug Visualization Colors

- **Green**: SimpleObjectSpawner collision shapes (DAE models)
- **Blue**: GLBObjectSpawner collision shapes (GLB models) 
- **Cyan**: Trimesh collision shapes
- **Yellow**: Box collision shapes
- **Orange**: Trimesh shapes from GLB
- **Magenta**: Unknown/fallback shapes

## Asset Requirements

### For SimpleObjectSpawner (DAE Models)
- All models in `assets/tiles/Models/DAE format/` should have collision generated
- Trees, rocks, stones, stumps

### For GLBObjectSpawner (GLB Models)  
- All models in `addons/GLB format/` should have collision generated
- Buildings, structures, decorative objects

## Migration from Old System

The old system used these methods (now removed):
- `create_single_convex_collision()`
- `create_trimesh_shape()`
- Manual CollisionShape3D creation

The new system relies entirely on pre-imported collision shapes, making the code cleaner and more performant.

## Testing

1. Enable debug visualization: `debug_collision_shapes = true`
2. Run the scene
3. Look for colored wireframes around spawned objects
4. Verify collision detection works with the drone or other physics objects

## Performance Notes

- Pre-imported collision is faster than runtime generation
- Convex shapes are faster than trimesh for collision detection
- Box shapes are fastest but least accurate
- Use debug mode sparingly in production (visual overhead) 