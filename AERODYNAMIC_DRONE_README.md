# Aerodynamic Drone Physics System

This document explains the integration of the Godot Aerodynamic Physics plugin with the Smart Drone AI project, providing realistic drone flight simulation.

## Overview

The `DroneFlight.gd` script extends the `AeroBody3D` class from the aerodynamic physics plugin to create a realistic quadcopter drone with:

- **Multiple Rotors**: Individual thrust control for each rotor
- **Aerodynamic Surfaces**: Small stabilizing surfaces for realistic flight dynamics
- **Flight Modes**: Multiple flight assistance modes
- **PID Control**: Automatic stabilization and altitude hold
- **Ground Effects**: Realistic ground effect simulation
- **Gyroscopic Effects**: Rotor-induced gyroscopic forces

## Plugin Integration

### Prerequisites

1. The Godot Aerodynamic Physics plugin is installed at `res://addons/godot_aerodynamic_physics/`
2. The plugin is enabled in Project Settings > Plugins
3. Physics substeps are configured in Project Settings > Physics > 3D > Aerodynamics

### Key Components Used

- **AeroBody3D**: Main physics body with aerodynamic simulation
- **AeroThrusterComponent**: Individual rotor thrust simulation
- **AeroSurface3D**: Aerodynamic surfaces for lift/drag
- **PID**: Built-in PID controller for stability

## DroneFlight.gd Features

### Core Systems

#### 1. Rotor System
```gdscript
# Automatic rotor creation in quadcopter X configuration
@export var rotor_count: int = 4
@export var rotor_spacing: float = 0.5
@export var max_rotor_speed: float = 1000.0
```

#### 2. Flight Modes
- **MANUAL**: Direct control, no stabilization
- **STABILIZE**: Attitude hold with auto-level
- **ALTITUDE_HOLD**: Stabilization + altitude maintenance  
- **LOITER**: Position hold (GPS-style)
- **RTL**: Return to launch (future implementation)

#### 3. Stability System
```gdscript
# PID controllers for each axis
var pitch_pid: PID
var roll_pid: PID  
var yaw_pid: PID
var altitude_pid: PID
```

#### 4. Physics Effects
- **Ground Effect**: Increased lift efficiency near ground
- **Gyroscopic Effects**: Rotor-induced torques
- **Aerodynamic Stability**: Small fins for natural stability

### Configuration

#### Rotor Configuration
```gdscript
# Individual rotor positions (X configuration)
Vector3(rotor_spacing, 0, -rotor_spacing)   # Front-right
Vector3(-rotor_spacing, 0, -rotor_spacing)  # Front-left  
Vector3(-rotor_spacing, 0, rotor_spacing)   # Rear-left
Vector3(rotor_spacing, 0, rotor_spacing)    # Rear-right
```

#### Rotor Mixing Logic
```gdscript
# Quadcopter control mixing
target_rotor_speeds[0] = base_throttle + pitch - roll + yaw  # FR
target_rotor_speeds[1] = base_throttle + pitch + roll - yaw  # FL
target_rotor_speeds[2] = base_throttle - pitch + roll + yaw  # RL  
target_rotor_speeds[3] = base_throttle - pitch - roll - yaw  # RR
```

## Usage

### 1. Setting up a Scene

```gdscript
# Create an AeroBody3D node
# Attach the DroneFlight.gd script
# Configure the exported parameters:

rotor_count = 4
rotor_spacing = 0.4
hover_throttle = 0.6
max_tilt_angle = 35.0
stability_factor = 2.5
```

### 2. Manual Control

Use the `DroneFlightController.gd` for keyboard input:

- **W/S**: Throttle up/down
- **Arrow Keys**: Pitch/Roll control
- **A/D**: Yaw left/right
- **1/2/3/4**: Flight mode switching
- **Space**: Emergency stop

### 3. AI Control Interface

```gdscript
# Get the drone reference
var drone = get_node("DroneFlight")

# Set control inputs (-1.0 to 1.0)
drone.set_control_input(pitch, roll, yaw, throttle)

# Change flight mode
drone.set_flight_mode(DroneFlight.FlightMode.STABILIZE)

# Enable altitude hold
drone.enable_altitude_hold(true, 5.0)  # Hold at 5m

# Get current status
var status = drone.get_flight_status()
print("Altitude: ", status.altitude)
print("Flight Mode: ", status.flight_mode)
print("Hovering: ", status.hovering)
```

### 4. Integration with Existing AI

To integrate with your existing AI system:

```gdscript
# In your AI planner/evaluator
func update_drone_control():
    var drone_flight = get_drone_flight_node()
    
    # Calculate desired movement
    var pitch = calculate_pitch_input()
    var roll = calculate_roll_input()  
    var yaw = calculate_yaw_input()
    var throttle = calculate_throttle_input()
    
    # Send to aerodynamic drone
    drone_flight.set_control_input(pitch, roll, yaw, throttle)
    
    # Get realistic flight status
    var status = drone_flight.get_flight_status()
    return status
```

## Physics Comparison

### Original Drone.gd vs DroneFlight.gd

| Feature | Original | Aerodynamic |
|---------|----------|-------------|
| Physics Base | CharacterBody3D | AeroBody3D (VehicleBody3D) |
| Movement | Direct velocity | Thrust-based forces |
| Obstacles | Collision detection | Flight over obstacles |
| Stability | Manual collision handling | Aerodynamic stability |
| Realism | Arcade-style | Flight simulator |
| Wind Effects | None | Full aerodynamic simulation |
| Ground Effect | None | Realistic ground cushion |

### Benefits of Aerodynamic System

1. **Realistic Flight Dynamics**: Proper acceleration, momentum, and inertia
2. **Natural Stability**: Aerodynamic surfaces provide inherent stability  
3. **Environmental Effects**: Wind, air density, ground effect
4. **Scalable**: Easy to modify rotor count (4, 6, 8 rotors)
5. **Professional**: Industry-standard flight control modes

## Troubleshooting

### Common Issues

1. **Drone Not Hovering Properly**
   - Check `hover_throttle` value (usually 0.5-0.7)
   - Verify rotor `max_thrust_force` (try 15-20N per rotor)
   - Ensure mass is appropriate (2-3kg for small drone)

2. **Unstable Flight**
   - Reduce PID gains (P=2.0, I=0.1, D=0.5)
   - Increase `stability_factor`
   - Check rotor positioning and thrust balance

3. **Poor Response**
   - Decrease `rotor_response_time` (0.1-0.2s)
   - Increase input smoothing in controller
   - Verify physics substeps (4-8 recommended)

4. **Performance Issues**
   - Disable debug visualization (`show_debug = false`)
   - Reduce physics substeps if needed
   - Optimize aerodynamic surface count

### Debug Visualization

Enable debug mode to see aerodynamic forces:

```gdscript
drone.show_debug = true
drone.show_lift_vectors = true  
drone.show_drag_vectors = true
```

## Advanced Configuration

### Custom Rotor Configurations

```gdscript
# Hexacopter setup
rotor_count = 6
# Positions calculated automatically in _get_rotor_positions()

# Octocopter setup  
rotor_count = 8
# Custom positions can be defined
```

### Wind Simulation

```gdscript
# Apply wind effects
drone.wind = Vector3(5, 0, 2)  # 5 m/s wind in X direction
```

### Custom PID Tuning

```gdscript
# Access PID controllers in _setup_pid_controllers()
pitch_pid.p = 3.0  # More aggressive
pitch_pid.i = 0.05 # Less integral
pitch_pid.d = 0.8  # More damping
```

## Integration Examples

### Example 1: Patrol Mode
```gdscript
func patrol_waypoints(waypoints: Array[Vector3]):
    drone.set_flight_mode(DroneFlight.FlightMode.STABILIZE)
    
    for waypoint in waypoints:
        # Calculate direction to waypoint
        var direction = (waypoint - drone.position).normalized()
        
        # Convert to control inputs
        var pitch = -direction.z * 0.5
        var roll = direction.x * 0.5
        var throttle = calculate_altitude_control(waypoint.y)
        
        drone.set_control_input(pitch, roll, 0, throttle)
        
        # Wait until close to waypoint
        await reached_waypoint(waypoint)
```

### Example 2: Target Tracking
```gdscript
func track_target(target_position: Vector3):
    var to_target = target_position - drone.position
    var distance = to_target.length()
    
    # Maintain optimal shooting distance
    var desired_distance = 15.0  # meters
    var approach_factor = (distance - desired_distance) / desired_distance
    
    # Calculate control inputs
    var pitch = -to_target.normalized().z * approach_factor * 0.3
    var roll = to_target.normalized().x * approach_factor * 0.3
    var yaw = calculate_yaw_to_target(target_position)
    
    drone.set_control_input(pitch, roll, yaw, 0.6)
```

This aerodynamic system provides a solid foundation for realistic drone simulation while maintaining compatibility with your existing AI systems. 