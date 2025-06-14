import math
import random

# Target physics (track runner - reduced speed for easier catching)
# Target max speed: reduced from 25 mph to ~18 mph for easier drone interception
TARGET_MAX_SPEED = 3.5  # units/s (≈ 17.5 ft/s ≈ 12 mph)
# Track runner acceleration: slightly reduced for easier catching
TARGET_ACCELERATION = 1.2  # units/s² (≈ 6 ft/s²)

# Target: Human-sized runner
TARGET_RADIUS = 0.1  # 0.5ft radius (1ft diameter person)

class Target:
    def __init__(self, grid_size):
        self.grid_size = grid_size
        self.pos = [0.0, 0.0]
        self.velocity = [0.0, 0.0]
        self.direction = [0.0, 0.0]
        
    def random_position(self):
        """Generate a random position within the grid."""
        return [round(random.uniform(0, self.grid_size - 1), 2), 
                round(random.uniform(0, self.grid_size - 1), 2)]
    
    def initialize_position(self):
        """Initialize target at a random position."""
        self.pos = self.random_position()
        self.velocity = [0.0, 0.0]
        self.direction = [random.uniform(-1, 1), random.uniform(-1, 1)]
    
    def get_speed(self):
        """Calculate current speed from velocity."""
        return round(math.sqrt(self.velocity[0]**2 + self.velocity[1]**2), 2)
    
    def move_with_acceleration(self, desired_direction, dt):
        """Move target with realistic acceleration like a track runner."""
        # Normalize desired direction
        dir_magnitude = math.sqrt(desired_direction[0]**2 + desired_direction[1]**2)
        if dir_magnitude < 0.001:
            # If no desired direction, gradually slow down
            deceleration = TARGET_ACCELERATION * 0.5
            current_speed = self.get_speed()
            if current_speed > 0.1:
                self.velocity = [
                    self.velocity[0] * (1 - deceleration * dt / current_speed),
                    self.velocity[1] * (1 - deceleration * dt / current_speed)
                ]
            else:
                self.velocity = [0.0, 0.0]
        else:
            # Normalize direction
            desired_direction = [desired_direction[0] / dir_magnitude, desired_direction[1] / dir_magnitude]
            
            # Apply acceleration in desired direction
            self.velocity = [
                self.velocity[0] + desired_direction[0] * TARGET_ACCELERATION * dt,
                self.velocity[1] + desired_direction[1] * TARGET_ACCELERATION * dt
            ]
            
            # Cap speed at TARGET_MAX_SPEED
            new_speed = self.get_speed()
            if new_speed > TARGET_MAX_SPEED:
                self.velocity[0] = self.velocity[0] / new_speed * TARGET_MAX_SPEED
                self.velocity[1] = self.velocity[1] / new_speed * TARGET_MAX_SPEED
        
        # Update position
        self.pos = [
            self.pos[0] + self.velocity[0] * dt,
            self.pos[1] + self.velocity[1] * dt
        ]
        
        # Format position
        self.pos = [round(self.pos[0], 2), round(self.pos[1], 2)]
        self.velocity = [round(v, 2) for v in self.velocity]
    
    def calculate_evasion_direction(self, drone_pos, obstacles):
        """Calculate direction to evade drone while avoiding obstacles and walls."""
        from environment import distance, OBSTACLE_RADIUS
        
        drone_distance = distance(self.pos, drone_pos)
        
        # Calculate escape direction from drone
        if drone_distance > 0.1:
            escape_direction = [
                (self.pos[0] - drone_pos[0]) / drone_distance,
                (self.pos[1] - drone_pos[1]) / drone_distance
            ]
        else:
            escape_direction = [random.uniform(-1, 1), random.uniform(-1, 1)]
        
        # Add wall avoidance
        wall_avoidance = [0.0, 0.0]
        wall_buffer = TARGET_RADIUS + 0.5  # Stay away from walls
        
        if self.pos[0] < wall_buffer:  # Too close to left wall
            wall_avoidance[0] += 1.0
        elif self.pos[0] > self.grid_size - wall_buffer:  # Too close to right wall
            wall_avoidance[0] -= 1.0
            
        if self.pos[1] < wall_buffer:  # Too close to top wall
            wall_avoidance[1] += 1.0
        elif self.pos[1] > self.grid_size - wall_buffer:  # Too close to bottom wall
            wall_avoidance[1] -= 1.0
        
        # Add obstacle avoidance
        obstacle_avoidance = [0.0, 0.0]
        for obs in obstacles:
            obs_distance = distance(self.pos, obs)
            if obs_distance < OBSTACLE_RADIUS + TARGET_RADIUS + 0.8:  # Close to obstacle
                if obs_distance > 0.1:
                    avoid_dir = [
                        (self.pos[0] - obs[0]) / obs_distance,
                        (self.pos[1] - obs[1]) / obs_distance
                    ]
                    obstacle_avoidance[0] += avoid_dir[0] * 0.5
                    obstacle_avoidance[1] += avoid_dir[1] * 0.5
        
        # Combine all influences with weights
        drone_weight = 2.0 if drone_distance < 3.0 else 1.0  # Stronger avoidance when drone is close
        wall_weight = 3.0  # Strong wall avoidance
        obstacle_weight = 1.5
        random_weight = 0.3  # Small random component for unpredictability
        
        direction = [
            escape_direction[0] * drone_weight + 
            wall_avoidance[0] * wall_weight + 
            obstacle_avoidance[0] * obstacle_weight +
            random.uniform(-1, 1) * random_weight,
            
            escape_direction[1] * drone_weight + 
            wall_avoidance[1] * wall_weight + 
            obstacle_avoidance[1] * obstacle_weight +
            random.uniform(-1, 1) * random_weight
        ]
        
        # Normalize direction
        dir_magnitude = math.sqrt(direction[0]**2 + direction[1]**2)
        if dir_magnitude > 0.1:
            direction[0] /= dir_magnitude
            direction[1] /= dir_magnitude
        
        return direction
    
    def update(self, drone_pos, obstacles, dt):
        """Update target position and behavior."""
        # Calculate evasion direction
        self.direction = self.calculate_evasion_direction(drone_pos, obstacles)
        
        # Move with acceleration
        self.move_with_acceleration(self.direction, dt)
        
        # Keep target within bounds with better boundary handling
        if self.pos[0] <= TARGET_RADIUS:
            self.pos[0] = TARGET_RADIUS
            self.velocity[0] = abs(self.velocity[0]) * 0.5  # Bounce away from wall
        elif self.pos[0] >= self.grid_size - TARGET_RADIUS:
            self.pos[0] = self.grid_size - TARGET_RADIUS
            self.velocity[0] = -abs(self.velocity[0]) * 0.5  # Bounce away from wall
            
        if self.pos[1] <= TARGET_RADIUS:
            self.pos[1] = TARGET_RADIUS
            self.velocity[1] = abs(self.velocity[1]) * 0.5  # Bounce away from wall
        elif self.pos[1] >= self.grid_size - TARGET_RADIUS:
            self.pos[1] = self.grid_size - TARGET_RADIUS
            self.velocity[1] = -abs(self.velocity[1]) * 0.5  # Bounce away from wall 