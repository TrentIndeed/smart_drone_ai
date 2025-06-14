import math

# Drone physics (realistic for small commercial drone)
# Real drone max speed: ~35 mph = 51.3 ft/s = 10.26 units/s in our scale
MAX_SPEED = 10.0  # units/s (≈ 50 ft/s ≈ 34 mph)
# Real drone acceleration: ~10-15 ft/s² = 2.0-3.0 units/s² in our scale  
ACCELERATION = 2.4  # units/s² (≈ 12 ft/s²)

# Drone: 2x2ft = 0.4 units in our 10-unit grid
DRONE_RADIUS = 0.2  # 1ft radius (2ft diameter drone)

class Drone:
    def __init__(self, grid_size):
        self.grid_size = grid_size
        self.pos = [0.0, 0.0]
        self.velocity = [0.0, 0.0]
        self.target = [0.0, 0.0]
        
    def initialize_position(self, start_pos=[0.3, 0.3]):
        """Initialize drone at starting position."""
        self.pos = start_pos.copy()
        self.target = [5.0, 5.0]  # Set initial target further away
        self.velocity = [0.0, 0.0]
    
    def format_position(self, pos):
        """Format position to 2 decimal places."""
        return [round(pos[0], 2), round(pos[1], 2)]
    
    def get_speed(self):
        """Calculate current speed from velocity."""
        return round(math.sqrt(self.velocity[0]**2 + self.velocity[1]**2), 2)
    
    def move_with_acceleration(self, target_pos, dt):
        """Move drone with realistic acceleration towards target position."""
        # Calculate desired direction
        dx = target_pos[0] - self.pos[0]
        dy = target_pos[1] - self.pos[1]
        dist = math.sqrt(dx*dx + dy*dy)
        
        if dist < 0.001:
            return self.pos, [0.0, 0.0]
        
        # Normalize direction
        dx = dx / dist
        dy = dy / dist
        
        # Calculate current speed
        current_speed = self.get_speed()
        
        # Apply acceleration in the desired direction
        new_velocity = [
            self.velocity[0] + dx * ACCELERATION * dt,
            self.velocity[1] + dy * ACCELERATION * dt
        ]
        
        # Calculate new speed
        new_speed = math.sqrt(new_velocity[0]**2 + new_velocity[1]**2)
        
        # Cap speed at MAX_SPEED
        if new_speed > MAX_SPEED:
            new_velocity[0] = new_velocity[0] / new_speed * MAX_SPEED
            new_velocity[1] = new_velocity[1] / new_speed * MAX_SPEED
        
        # Update position using the new velocity
        new_pos = [
            self.pos[0] + new_velocity[0] * dt,
            self.pos[1] + new_velocity[1] * dt
        ]
        
        # Ensure minimum movement to prevent getting stuck
        if math.sqrt((new_pos[0] - self.pos[0])**2 + (new_pos[1] - self.pos[1])**2) < 0.01:
            new_pos = [
                self.pos[0] + dx * 0.1,  # Force minimum movement
                self.pos[1] + dy * 0.1
            ]
            new_velocity = [
                dx * MAX_SPEED * 0.5,  # Set minimum velocity
                dy * MAX_SPEED * 0.5
            ]
        
        return self.format_position(new_pos), [round(v, 2) for v in new_velocity]
    
    def move_towards(self, target_pos, speed, dt):
        """Simple movement towards target at constant speed."""
        dx = target_pos[0] - self.pos[0]
        dy = target_pos[1] - self.pos[1]
        dist = math.sqrt(dx*dx + dy*dy)
        if dist < 0.001:
            return target_pos
        dx = dx / dist * speed * dt
        dy = dy / dist * speed * dt
        return self.format_position([self.pos[0] + dx, self.pos[1] + dy])
    
    def update_position(self, new_pos, new_velocity):
        """Update drone position and velocity."""
        self.pos = self.format_position(new_pos)
        self.velocity = [round(v, 2) for v in new_velocity]
    
    def keep_within_bounds(self):
        """Keep drone within grid bounds and handle wall collisions."""
        bounds_changed = False
        
        if self.pos[0] <= DRONE_RADIUS:
            self.pos[0] = DRONE_RADIUS
            self.velocity[0] = 0  # Stop sliding along wall
            bounds_changed = True
        elif self.pos[0] >= self.grid_size - DRONE_RADIUS:
            self.pos[0] = self.grid_size - DRONE_RADIUS
            self.velocity[0] = 0  # Stop sliding along wall
            bounds_changed = True
            
        if self.pos[1] <= DRONE_RADIUS:
            self.pos[1] = DRONE_RADIUS
            self.velocity[1] = 0  # Stop sliding along wall
            bounds_changed = True
        elif self.pos[1] >= self.grid_size - DRONE_RADIUS:
            self.pos[1] = self.grid_size - DRONE_RADIUS
            self.velocity[1] = 0  # Stop sliding along wall
            bounds_changed = True
        
        return bounds_changed 