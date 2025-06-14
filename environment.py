import random
import math
import pygame

# --- Environment Setup ---
GRID_SIZE = 10  # Represents 50ft x 50ft area (each unit = 5ft)
CELL_SIZE = 60
WINDOW_SIZE = 800
REASONING_HEIGHT = 200
FPS = 60
FONT_SIZE = 16
REASONING_LINES = 8

# Obstacle size
OBSTACLE_RADIUS = 0.3  # 1.5ft radius obstacles

# Movement parameters
MIN_OBSTACLE_DISTANCE = 0.5  # 2.5ft minimum distance from obstacles

def format_position(pos):
    """Format position to 2 decimal places."""
    return [round(pos[0], 2), round(pos[1], 2)]

def random_position():
    """Generate a random position within the grid."""
    return [round(random.uniform(0, GRID_SIZE - 1), 2), round(random.uniform(0, GRID_SIZE - 1), 2)]

def distance(pos1, pos2):
    """Calculate Euclidean distance between two positions."""
    return math.sqrt((pos1[0] - pos2[0])**2 + (pos1[1] - pos2[1])**2)

def check_circle_collision(pos1, pos2, radius1, radius2):
    """Check if two circles overlap, given their center positions and radii."""
    return distance(pos1, pos2) < radius1 + radius2

def is_position_safe(pos, obstacles, drone_radius=0.2, obstacle_radius=OBSTACLE_RADIUS, relaxed=False):
    """Check if a position is safe (not colliding with obstacles)."""
    min_distance = MIN_OBSTACLE_DISTANCE
    if relaxed:
        min_distance = MIN_OBSTACLE_DISTANCE * 0.3  # More lenient when close to target
    
    required_distance = drone_radius + obstacle_radius + min_distance
    
    # Quick bounds check first
    if pos[0] < drone_radius or pos[0] > GRID_SIZE - drone_radius:
        return False
    if pos[1] < drone_radius or pos[1] > GRID_SIZE - drone_radius:
        return False
    
    # Check obstacles with optimized distance calculation
    for obs in obstacles:
        dx = pos[0] - obs[0]
        dy = pos[1] - obs[1]
        dist_squared = dx*dx + dy*dy
        if dist_squared < required_distance * required_distance:
            return False
    return True

def find_safe_position(current_pos, target_pos, obstacles, max_attempts=32):
    """Find a safe position that moves towards the target while avoiding obstacles."""
    best_pos = None
    best_score = float('-inf')
    
    # Try different angles and distances
    for _ in range(max_attempts):
        # Calculate angle towards target with some randomness
        target_angle = math.atan2(target_pos[1] - current_pos[1], target_pos[0] - current_pos[0])
        angle = target_angle + random.uniform(-math.pi/2, math.pi/2)
        
        # Try different distances
        for dist in [0.5, 0.8, 1.2, 1.5]:
            new_pos = [
                current_pos[0] + dist * math.cos(angle),
                current_pos[1] + dist * math.sin(angle)
            ]
            
            # Keep within bounds
            drone_radius = 0.2  # DRONE_RADIUS
            new_pos[0] = max(drone_radius, min(GRID_SIZE - drone_radius, new_pos[0]))
            new_pos[1] = max(drone_radius, min(GRID_SIZE - drone_radius, new_pos[1]))
            
            if is_position_safe(new_pos, obstacles):
                # Score based on progress towards target and distance from obstacles
                progress = distance(current_pos, target_pos) - distance(new_pos, target_pos)
                obstacle_distance = min(distance(new_pos, obs) for obs in obstacles)
                score = progress + obstacle_distance
                
                if score > best_score:
                    best_score = score
                    best_pos = new_pos
    
    return best_pos if best_pos else current_pos

def generate_obstacles(num_obstacles=12, drone_start_pos=[0.3, 0.3], target_start_pos=None):
    """Generate obstacles with minimum spacing (trees and rocks)."""
    obstacles = []
    obstacle_types = []
    
    for _ in range(num_obstacles):
        attempts = 0
        while attempts < 100:  # More attempts for denser placement
            pos = random_position()
            # Check if this position is far enough from other obstacles and the drone's start position
            min_spacing = 1.5 * OBSTACLE_RADIUS  # Reduced spacing for denser forest
            if (all(distance(pos, obs) > min_spacing for obs in obstacles) and
                distance(pos, drone_start_pos) > 2.0 * OBSTACLE_RADIUS and
                (target_start_pos is None or distance(pos, target_start_pos) > 1.5 * OBSTACLE_RADIUS)):
                obstacles.append(pos)
                # Randomly assign obstacle type
                obstacle_types.append(random.choice(['tree', 'rock']))
                break
            attempts += 1
    
    return obstacles, obstacle_types

class Environment:
    def __init__(self):
        self.obstacles = []
        self.obstacle_types = []
        self.screen = None
        self.font = None
        
    def initialize_pygame(self):
        """Initialize pygame display."""
        pygame.init()
        self.screen = pygame.display.set_mode((WINDOW_SIZE, WINDOW_SIZE + REASONING_HEIGHT))
        self.font = pygame.font.SysFont("Courier", 16)
        pygame.display.set_caption("Drone LLM Agent")
        return pygame.time.Clock()
    
    def setup_obstacles(self, drone_start_pos, target_start_pos=None):
        """Setup obstacles in the environment."""
        self.obstacles, self.obstacle_types = generate_obstacles(12, drone_start_pos, target_start_pos)
    
    def draw_grid(self, drone_pos, target_pos, reasoning_lines):
        """Draw the environment grid with all objects."""
        from drone import DRONE_RADIUS
        from target import TARGET_RADIUS
        
        self.screen.fill((30, 30, 30))
        
        # Draw grid
        for x in range(GRID_SIZE):
            for y in range(GRID_SIZE):
                rect = pygame.Rect(x*CELL_SIZE, y*CELL_SIZE, CELL_SIZE, CELL_SIZE)
                pygame.draw.rect(self.screen, (50, 50, 50), rect, 1)

        # Draw obstacles with different colors for trees and rocks
        for i, obs in enumerate(self.obstacles):
            if i < len(self.obstacle_types):
                if self.obstacle_types[i] == 'tree':
                    color = (34, 139, 34)  # Forest green for trees
                else:  # rock
                    color = (105, 105, 105)  # Dim gray for rocks
            else:
                color = (100, 100, 100)  # Default gray
                
            pygame.draw.circle(self.screen, color, 
                             (int(obs[0]*CELL_SIZE), int(obs[1]*CELL_SIZE)),
                             int(OBSTACLE_RADIUS*CELL_SIZE))

        # Draw target with precise position
        pygame.draw.circle(self.screen, (255, 0, 0),
                          (int(target_pos[0]*CELL_SIZE), int(target_pos[1]*CELL_SIZE)),
                          int(TARGET_RADIUS*CELL_SIZE))

        # Draw drone with precise position
        pygame.draw.circle(self.screen, (0, 0, 255),
                          (int(drone_pos[0]*CELL_SIZE), int(drone_pos[1]*CELL_SIZE)),
                          int(DRONE_RADIUS*CELL_SIZE))

        # Draw reasoning text
        for i, line in enumerate(reasoning_lines):
            text_surface = self.font.render(line, True, (255, 255, 255))
            self.screen.blit(text_surface, (5, WINDOW_SIZE + 5 + i * FONT_SIZE))

        pygame.display.flip()
    
    def render_reasoning(self, reasoning_lines):
        """Render reasoning text at bottom of screen."""
        for i, line in enumerate(reasoning_lines):
            text = self.font.render(line, True, (200, 200, 200))
            self.screen.blit(text, (10, WINDOW_SIZE + 5 + i * 20)) 