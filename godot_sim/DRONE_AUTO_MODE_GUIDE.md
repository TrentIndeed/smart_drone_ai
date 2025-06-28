# Drone Auto Mode - Fixed Implementation Guide

## 🚁 Overview

The drone auto mode has been **fixed** to prevent uncontrolled ascent and now includes a proper **AUTO_CHASE** mode that automatically flies toward moving targets.

## ⚠️ What Was Fixed

### **Uncontrolled Ascent Issue - RESOLVED**
- **Problem**: Double thrust application causing drone to rise rapidly
- **Solution**: 
  - Reduced `hover_throttle` from 0.98 to 0.7 (prevents falling through floor)
  - Fixed `_apply_drone_physics()` to prevent double force application
  - Added proper attitude control separation from thrust
  - Added air resistance and angular damping for realistic flight

### **Falling Through Floor Issue - RESOLVED**
- **Problem**: Drone falling through map floor despite physics
- **Solution**:
  - Increased `hover_throttle` to 0.7 for adequate lift
  - Fixed collision mask to include ground layer (mask = 6)
  - Added minimum thrust enforcement (0.6x gravity compensation)
  - Added ground detection and emergency reset

### **Target RunningModel Error - RESOLVED**
- **Problem**: `Node not found: "RunningModel"` error in Target.gd
- **Solution**:
  - Replaced all `$RunningModel` with `get_node_or_null("RunningModel")`
  - Added null safety checks in all Target functions
  - Fixed animation player setup with proper error handling

### **Physics Improvements**
- **Proper thrust calculation**: Base thrust now properly counteracts gravity
- **Attitude control**: Separated pitch/roll/yaw torques from thrust forces
- **Stability**: Added damping and reduced control sensitivity
- **Mass**: Increased to 1.2kg for better stability
- **Collision**: Fixed collision layers for proper ground interaction

## 🎮 How to Use Auto Mode

### **Method 1: Keyboard Toggle (Easiest)**
1. Run the simulation with a drone and target in the scene
2. Press **[5]** to toggle auto chase mode on/off
3. Drone will automatically fly toward the target

### **Method 2: Auto Mode on Start**
1. Attach `AutoModeTest.gd` script to a Node in your main scene
2. Set `enable_auto_on_start = true` in the script properties
3. Run the simulation - auto mode will activate automatically

### **Method 3: Diagnostic Mode**
1. Attach `DroneTestFix.gd` script to a Node in your main scene
2. Set `auto_fix_falling = true` and `auto_fix_target_errors = true`
3. Script will automatically monitor and fix issues

### **Method 4: Manual Script Control**
```gdscript
# Get the drone
var drone = get_tree().get_first_node_in_group("drones")

# Enable auto chase mode
drone.enable_auto_mode(true)

# Disable auto chase mode  
drone.enable_auto_mode(false)

# Check if auto mode is enabled
var is_auto = drone.is_auto_mode_enabled()
```

## 🎯 Auto Chase Behavior

When **AUTO_CHASE** mode is enabled, the drone will:

1. **Find Target**: Automatically locate the first node in "target" group
2. **Predict Movement**: Predict where target will be 0.5 seconds ahead
3. **Maintain Distance**: Keep at least 1.5 units away from target
4. **Maintain Altitude**: Fly at 2.0 units height by default
5. **Smooth Movement**: Use gradual pitch/roll inputs based on distance
6. **Face Target**: Slowly rotate to face the target direction

### **Auto Chase Parameters** (configurable in editor)
- `chase_height: 2.0` - Preferred flying height
- `min_chase_distance: 1.5` - Minimum distance from target
- `target_prediction_time: 0.5` - How far ahead to predict target movement

## 🎛️ Control Reference

| Key | Action |
|-----|--------|
| **[5]** | Toggle Auto Chase Mode |
| **[1]** | Manual Mode |
| **[2]** | Stabilize Mode |
| **[3]** | Altitude Hold On |
| **[4]** | Altitude Hold Off |
| **[Space]** | Emergency Stop |
| **[R]** | Reset Positions (if AutoModeTest is active) |
| **[T]** | Toggle Target Movement (if AutoModeTest is active) |
| **[G]** | Toggle Debug Info (if AutoModeTest is active) |
| **[F1]** | Emergency Fix Falling Drone (if DroneTestFix is active) |
| **[F2]** | Fix Target Model (if DroneTestFix is active) |
| **[F3]** | Force Diagnostics (if DroneTestFix is active) |

## 🔧 Testing Setup

### **Using AutoModeTest.gd**
1. Create a Node in your main scene
2. Attach `godot_sim/scripts/AutoModeTest.gd` 
3. Configure the script properties:
   - `enable_auto_on_start: true` - Start in auto mode
   - `test_mode: true` - Enable test controls
   - `debug_info: true` - Show debug information

### **Using DroneTestFix.gd (Recommended)**
1. Create a Node in your main scene
2. Attach `godot_sim/scripts/DroneTestFix.gd`
3. Configure the script properties:
   - `auto_fix_falling: true` - Auto-fix falling drones
   - `auto_fix_target_errors: true` - Auto-fix target issues
   - `check_interval: 2.0` - How often to check (seconds)

### **Expected Behavior**
✅ **Drone should hover stable** - No rapid ascent or falling  
✅ **Proper ground collision** - Drone stays above ground  
✅ **Smooth movement toward target** - No jerky motion  
✅ **Maintains safe distance** - Doesn't crash into target  
✅ **Follows moving targets** - Predicts target movement  
✅ **Proper altitude control** - Stays at configured height  
✅ **No RunningModel errors** - Target animations work properly  

## 🐛 Debug Information

When debug is enabled, you'll see console output like:
```
=== DRONE FIX DIAGNOSTICS ===
Drone position: (0.2, 2.1, -2.3)
Drone velocity: 2.1
Drone mode: AUTO_CHASE
Auto mode: true
✅ OK: Drone altitude is normal
Target position: (1.5, 0.0, 0.8)
Target velocity: 2.8
Target health: 2/2
✅ OK: Target RunningModel found
===============================
```

## 📋 Troubleshooting

### **Drone Still Falling Through Floor?**
- ✅ **Fixed**: Increased `hover_throttle` to 0.7
- ✅ **Fixed**: Added minimum thrust of 0.6x gravity compensation
- ✅ **Fixed**: Proper collision mask (6) for ground detection
- **If still occurring**: Use DroneTestFix.gd for auto-recovery

### **Target RunningModel Errors?**
- ✅ **Fixed**: All `$RunningModel` replaced with null-safe `get_node_or_null()`
- ✅ **Fixed**: Animation player setup with proper error handling
- **If still occurring**: Check that Running.fbx model is properly imported

### **Auto Mode Not Working?**
- Verify drone is in "drones" group: `drone.add_to_group("drones")`
- Verify target is in "target" group: `target.add_to_group("target")`
- Check console for "Auto mode: Found target" message

### **Drone Not Moving Toward Target?**
- Ensure target distance > `min_chase_distance` (1.5 units)
- Check if target is moving too fast
- Verify drone flight mode shows "AUTO_CHASE"

### **Emergency Recovery**
If issues persist, use the emergency controls:
- **[F1]** - Reset falling drone to safe position
- **[F2]** - Fix target model issues  
- **[F3]** - Run diagnostic check
- **[Space]** - Emergency shutdown

## 🔄 Integration with S1/S2 System

The auto mode is designed to work alongside the existing S1/S2 architecture:

- **S1 (200Hz)**: Auto mode operates at control execution level
- **S2 (7-9Hz)**: Can override auto mode with strategic commands
- **Bypass S2**: Auto mode allows testing without LLM/LangGraph dependency

To integrate with the Python AI system, use the existing interface:
```python
# From Python side
drone_interface.set_flight_mode("AUTO_CHASE")
```

## ✅ Success Criteria

Your auto mode is working correctly if:

1. ✅ Drone hovers stably without rising uncontrollably
2. ✅ Drone does NOT fall through the ground/floor
3. ✅ No "RunningModel" node errors in console
4. ✅ Pressing [5] toggles auto mode with console feedback
5. ✅ In auto mode, drone smoothly approaches target
6. ✅ Drone maintains safe distance from target
7. ✅ Drone follows moving targets intelligently
8. ✅ Emergency stop ([Space]) works immediately
9. ✅ UI shows "AUTO_CHASE (AUTO)" mode when active
10. ✅ Target animations play without errors

---

**Note**: This implementation provides a solid foundation for the auto chase mode while maintaining compatibility with the existing LangGraph-based S2 planning system. The diagnostic tools help ensure everything is working properly. 