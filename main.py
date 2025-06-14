# drone_llm_agent.py
# Requires: `ollama` running locally with a model like `llama3`
# GUI requires: `pip install pygame`

import subprocess
import json
import time
import random
import re
import math
import threading
import textwrap

import numpy as np
import pygame

# --- Skill Library ---
skills = {
    "intercept": "Calculate best path to reach the target quickly.",
    "predict_target_path": "Predict future positions of a moving target.",
    "avoid_obstacles": "Plan a route that avoids obstacles.",
    "reposition": "Move to a better vantage point to regain visibility.",
}

# --- Drone Environment Setup ---
GRID_SIZE = 10
CELL_SIZE = 60
WINDOW_SIZE = GRID_SIZE * CELL_SIZE
REASONING_HEIGHT = 200
FPS = 60
FONT_SIZE = 16
REASONING_LINES = 8
MOVE_SPEED = 5.0
MAX_SPEED = 8.0
ACCELERATION = 4.0
TARGET_SPEED = 2.0
LLM_DECISION_INTERVAL = 1.0
DRONE_RADIUS = 0.3  # Smaller radius for drone
TARGET_RADIUS = 0.3  # Smaller radius for target
OBSTACLE_RADIUS = 0.4  # Slightly larger radius for obstacles
MIN_OBSTACLE_DISTANCE = 0.6  # Reduced minimum distance to obstacles

# Global state
drone_pos = [0.0, 0.0]
drone_target = [0.0, 0.0]
drone_velocity = [0.0, 0.0]
target_pos = [0.0, 0.0]
target_direction = [0.0, 0.0]
obstacles = []
reasoning = ""
reasoning_lines = []
running = True
llm_thread = None
movement_plan = []  # List of planned positions
current_plan_step = 0
PLAN_STEPS = 3  # Number of steps in each plan

def format_position(pos):
    return [round(pos[0], 2), round(pos[1], 2)]

def random_position():
    return [round(random.uniform(0, GRID_SIZE - 1), 2), round(random.uniform(0, GRID_SIZE - 1), 2)]

def distance(pos1, pos2):
    return math.sqrt((pos1[0] - pos2[0])**2 + (pos1[1] - pos2[1])**2)

def get_speed(velocity):
    return round(math.sqrt(velocity[0]**2 + velocity[1]**2), 2)

def move_with_acceleration(current_pos, current_velocity, target_pos, dt):
    # Calculate desired direction
    dx = target_pos[0] - current_pos[0]
    dy = target_pos[1] - current_pos[1]
    dist = math.sqrt(dx*dx + dy*dy)
    
    if dist < 0.001:
        return current_pos, [0.0, 0.0]
    
    # Normalize direction
    dx = dx / dist
    dy = dy / dist
    
    # Calculate current speed
    current_speed = get_speed(current_velocity)
    
    # Apply acceleration in the desired direction
    new_velocity = [
        current_velocity[0] + dx * ACCELERATION * dt,
        current_velocity[1] + dy * ACCELERATION * dt
    ]
    
    # Calculate new speed
    new_speed = get_speed(new_velocity)
    
    # Cap speed at MAX_SPEED
    if new_speed > MAX_SPEED:
        new_velocity[0] = new_velocity[0] / new_speed * MAX_SPEED
        new_velocity[1] = new_velocity[1] / new_speed * MAX_SPEED
    
    # Update position using the new velocity
    new_pos = [
        current_pos[0] + new_velocity[0] * dt,
        current_pos[1] + new_velocity[1] * dt
    ]
    
    # Ensure minimum movement to prevent getting stuck
    if distance(new_pos, current_pos) < 0.01:
        new_pos = [
            current_pos[0] + dx * 0.1,  # Force minimum movement
            current_pos[1] + dy * 0.1
        ]
        new_velocity = [
            dx * MAX_SPEED * 0.5,  # Set minimum velocity
            dy * MAX_SPEED * 0.5
        ]
    
    return format_position(new_pos), [round(v, 2) for v in new_velocity]

def move_towards(current_pos, target_pos, speed, dt):
    dx = target_pos[0] - current_pos[0]
    dy = target_pos[1] - current_pos[1]
    dist = math.sqrt(dx*dx + dy*dy)
    if dist < 0.001:
        return target_pos
    dx = dx / dist * speed * dt
    dy = dy / dist * speed * dt
    return format_position([current_pos[0] + dx, current_pos[1] + dy])

# --- Ollama Communication ---
def prompt_ollama(prompt, model="llama3"):
    process = subprocess.Popen(
        ["ollama", "run", model],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        encoding='utf-8'  # Explicitly set UTF-8 encoding
    )
    response, _ = process.communicate(input=prompt)
    return response.strip()

def check_circle_collision(pos1, pos2, radius1, radius2):
    """Check if two circles overlap, given their center positions and radii."""
    return distance(pos1, pos2) < radius1 + radius2

def is_position_safe(pos, obstacles, drone_radius=DRONE_RADIUS, obstacle_radius=OBSTACLE_RADIUS, relaxed=False):
    """Check if a position is safe (not colliding with obstacles)."""
    min_distance = MIN_OBSTACLE_DISTANCE
    if relaxed:
        min_distance = MIN_OBSTACLE_DISTANCE * 0.5  # More lenient when close to target
    
    for obs in obstacles:
        if distance(pos, obs) < drone_radius + obstacle_radius + min_distance:
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
            new_pos[0] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, new_pos[0]))
            new_pos[1] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, new_pos[1]))
            
            if is_position_safe(new_pos, obstacles):
                # Score based on progress towards target and distance from obstacles
                progress = distance(current_pos, target_pos) - distance(new_pos, target_pos)
                obstacle_distance = min(distance(new_pos, obs) for obs in obstacles)
                score = progress + obstacle_distance
                
                if score > best_score:
                    best_score = score
                    best_pos = new_pos
    
    return best_pos if best_pos else current_pos

def create_fallback_plan(start_pos, target_pos):
    """Create a simple linear plan towards the target with some randomness to avoid getting stuck."""
    plan = []
    current_pos = start_pos
    
    # Check if we're close to the target
    close_to_target = distance(start_pos, target_pos) < 2.0
    
    for i in range(PLAN_STEPS):
        if close_to_target:
            # When close to target, use smaller, more direct steps
            step_size = 0.2
        else:
            # When far from target, use larger steps
            step_size = 0.3
            
        # Try direct path first
        direct_step = [
            current_pos[0] + (target_pos[0] - current_pos[0]) * step_size,
            current_pos[1] + (target_pos[1] - current_pos[1]) * step_size
        ]
        direct_step[0] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, direct_step[0]))
        direct_step[1] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, direct_step[1]))
        
        # Use relaxed safety when close to target
        if is_position_safe(direct_step, obstacles, relaxed=close_to_target):
            next_pos = direct_step
        else:
            # If direct path is blocked, try alternative positions
            next_pos = find_safe_position(current_pos, target_pos, obstacles)
            
            # If still can't find safe position, just move towards target anyway
            if distance(next_pos, current_pos) < 0.1:
                next_pos = [
                    current_pos[0] + (target_pos[0] - current_pos[0]) * (step_size * 0.5),
                    current_pos[1] + (target_pos[1] - current_pos[1]) * (step_size * 0.5)
                ]
                next_pos[0] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, next_pos[0]))
                next_pos[1] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, next_pos[1]))
        
        plan.append(format_position(next_pos))
        current_pos = next_pos
    
    return plan

def llm_decision_loop():
    global drone_target, reasoning, reasoning_lines, running, drone_pos, drone_velocity, movement_plan, current_plan_step
    history = []
    steps = 0

    while running and steps < 20:
        time.sleep(LLM_DECISION_INTERVAL)
        
        print(f"\nStep {steps}")
        print("Drone:", format_position(drone_pos), "Target:", format_position(target_pos))
        print("Drone velocity:", [round(v, 2) for v in drone_velocity], "Speed:", get_speed(drone_velocity))

        # If we're stuck or have no plan, create a fallback plan
        if not movement_plan or current_plan_step >= len(movement_plan):
            movement_plan = create_fallback_plan(drone_pos, target_pos)
            current_plan_step = 0
            print("Using fallback plan:", movement_plan)
            continue

        obs = {
            "drone": format_position(drone_pos),
            "drone_velocity": [round(v, 2) for v in drone_velocity],
            "drone_speed": get_speed(drone_velocity),
            "target": format_position(target_pos),
            "obstacles": [format_position(obs) for obs in obstacles],
            "skills": skills,
            "history": history[-5:],
        }
        prompt = (
            "You are a drone control AI agent. You are on a 10x10 grid.\n"
            f"Current position: {format_position(drone_pos)}\n"
            f"Current velocity: {[round(v, 2) for v in drone_velocity]}\n"
            f"Current speed: {get_speed(drone_velocity):.2f} units/second\n"
            f"Target position: {format_position(target_pos)}\n"
            f"Obstacles at: {[format_position(obs) for obs in obstacles]}\n"
            "Your goal is to get in line of sight and intercept the target.\n"
            "You have the following skills available:\n" +
            "\n".join([f"- {k}: {v}" for k,v in skills.items()]) + "\n"
            "You can move in any direction within the 10x10 grid (x and y must stay between 0 and 9).\n"
            "Create a 3-step plan to intercept the target. Each step should be a position that gets closer to the target.\n"
            "The drone only needs to touch the target's edge to intercept it, not hit its center.\n"
            "Reply in JSON like: {\"plan\": [[x1,y1], [x2,y2], [x3,y3]], \"reasoning\": \"...\"}"
        )

        try:
            response = prompt_ollama(prompt)
            match = re.search(r'\{.*?\}', response, re.DOTALL)
            if not match:
                raise ValueError("No JSON object found in response")

            json_response = json.loads(match.group())
            plan = json_response.get("plan")
            reasoning = json_response.get("reasoning")

            if (plan and len(plan) == PLAN_STEPS and 
                all(0 <= pos[0] < GRID_SIZE and 0 <= pos[1] < GRID_SIZE for pos in plan)):
                
                # Validate that the plan makes sense (each step gets closer to target)
                valid_plan = True
                for i in range(len(plan)-1):
                    if distance(plan[i], target_pos) <= distance(plan[i+1], target_pos):
                        valid_plan = False
                        break
                
                if valid_plan:
                    movement_plan = [format_position(pos) for pos in plan]
                    current_plan_step = 0
                    history.append({
                        "drone": format_position(drone_pos),
                        "target": format_position(target_pos),
                        "plan": movement_plan,
                        "reasoning": reasoning
                    })
                    reasoning_lines = textwrap.wrap(reasoning, width=50)[:REASONING_LINES]
                else:
                    print("Invalid plan - steps don't get closer to target")
                    movement_plan = create_fallback_plan(drone_pos, target_pos)
                    current_plan_step = 0
            else:
                print("Invalid plan from LLM. Using fallback plan...")
                movement_plan = create_fallback_plan(drone_pos, target_pos)
                current_plan_step = 0

        except Exception as e:
            print("LLM parsing failed:", e)
            print("RAW LLM response:", response)
            movement_plan = create_fallback_plan(drone_pos, target_pos)
            current_plan_step = 0

        steps += 1

# --- Pygame GUI ---
def draw_grid(screen, font):
    screen.fill((30, 30, 30))
    
    # Draw grid
    for x in range(GRID_SIZE):
        for y in range(GRID_SIZE):
            rect = pygame.Rect(x*CELL_SIZE, y*CELL_SIZE, CELL_SIZE, CELL_SIZE)
            pygame.draw.rect(screen, (50, 50, 50), rect, 1)

    # Draw obstacles
    for obs in obstacles:
        pygame.draw.circle(screen, (100, 100, 100), 
                         (int(obs[0]*CELL_SIZE), int(obs[1]*CELL_SIZE)),
                         int(OBSTACLE_RADIUS*CELL_SIZE))

    # Draw target with precise position
    pygame.draw.circle(screen, (255, 0, 0),
                      (int(target_pos[0]*CELL_SIZE), int(target_pos[1]*CELL_SIZE)),
                      int(TARGET_RADIUS*CELL_SIZE))

    # Draw drone with precise position
    pygame.draw.circle(screen, (0, 0, 255),
                      (int(drone_pos[0]*CELL_SIZE), int(drone_pos[1]*CELL_SIZE)),
                      int(DRONE_RADIUS*CELL_SIZE))

    # Draw reasoning text
    for i, line in enumerate(reasoning_lines):
        text_surface = font.render(line, True, (255, 255, 255))
        screen.blit(text_surface, (5, WINDOW_SIZE + 5 + i * FONT_SIZE))

    pygame.display.flip()

def render_reasoning(screen, font):
    # Text is now wrapped in the llm_decision_loop
    for i, line in enumerate(reasoning_lines):
        text = font.render(line, True, (200, 200, 200))
        screen.blit(text, (10, WINDOW_SIZE + 5 + i * 20))

# --- Main Animation Loop ---
def main():
    global drone_pos, drone_velocity, target_pos, target_direction, obstacles, running, movement_plan, current_plan_step

    pygame.init()
    screen = pygame.display.set_mode((WINDOW_SIZE, WINDOW_SIZE + REASONING_HEIGHT))
    font = pygame.font.SysFont("Courier", 16)
    pygame.display.set_caption("Drone LLM Agent")
    clock = pygame.time.Clock()

    # Initialize positions
    drone_pos = [0.3, 0.3]  # Start slightly away from edge
    drone_target = [5.0, 5.0]  # Set initial target further away
    drone_velocity = [0.0, 0.0]
    target_pos = random_position()
    target_direction = [random.uniform(-1, 1), random.uniform(-1, 1)]
    
    # Generate obstacles with minimum spacing
    obstacles = []
    for _ in range(3):  # Reduced number of obstacles
        attempts = 0
        while attempts < 50:  # Limit attempts to prevent infinite loop
            pos = random_position()
            # Check if this position is far enough from other obstacles and the drone's start position
            if (all(distance(pos, obs) > 2.5 * OBSTACLE_RADIUS for obs in obstacles) and
                distance(pos, drone_pos) > 2.5 * OBSTACLE_RADIUS):
                obstacles.append(pos)
                break
            attempts += 1
    
    movement_plan = []
    current_plan_step = 0
    stuck_counter = 0  # Counter to detect when drone is stuck
    last_pos = drone_pos.copy()  # Track last position for stuck detection
    unsafe_counter = 0  # Counter for unsafe path attempts
    position_history = []  # Track recent positions to detect oscillation
    emergency_mode = False  # Emergency mode for when drone is really stuck

    # Start LLM decision thread
    llm_thread = threading.Thread(target=llm_decision_loop)
    llm_thread.start()

    last_time = time.time()
    while running:
        current_time = time.time()
        dt = current_time - last_time
        last_time = current_time

        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
                break

        # Track position history for oscillation detection
        position_history.append(drone_pos.copy())
        if len(position_history) > 20:  # Keep last 20 positions
            position_history.pop(0)

        # Check for oscillation (drone moving back and forth)
        if len(position_history) >= 10:
            recent_positions = position_history[-10:]
            avg_movement = sum(distance(recent_positions[i], recent_positions[i-1]) 
                             for i in range(1, len(recent_positions))) / (len(recent_positions) - 1)
            if avg_movement < 0.05:  # Very small movements indicate stuck
                stuck_counter += 1

        # Update drone position with acceleration
        if movement_plan and current_plan_step < len(movement_plan):
            # Move towards the current step in the plan
            new_pos, new_velocity = move_with_acceleration(drone_pos, drone_velocity, movement_plan[current_plan_step], dt)
            
            # Check distance to target for safety adjustments
            distance_to_target = distance(drone_pos, target_pos)
            close_to_target = distance_to_target < 2.0
            
            # Adjust unsafe threshold based on distance to target and emergency mode
            unsafe_threshold = 1 if emergency_mode else (2 if close_to_target else 3)
            
            # In emergency mode, be much more lenient with safety
            safety_check = True
            if emergency_mode:
                safety_check = True  # Always allow movement in emergency mode
            else:
                safety_check = is_position_safe(new_pos, obstacles, relaxed=close_to_target)
            
            # Check if the new position is safe (but be more lenient when close to target)
            if safety_check or unsafe_counter > unsafe_threshold:
                # Reset unsafe counter if we found a safe path
                if safety_check:
                    unsafe_counter = 0
                
                # Check if we're actually moving
                movement_distance = distance(new_pos, last_pos)
                if movement_distance < 0.01:
                    stuck_counter += 1
                    if stuck_counter > 3:  # Reduced threshold for faster response
                        print("Drone appears stuck, entering emergency mode...")
                        emergency_mode = True
                        # Force movement towards target
                        emergency_direction = [
                            (target_pos[0] - drone_pos[0]) / distance_to_target if distance_to_target > 0 else 0,
                            (target_pos[1] - drone_pos[1]) / distance_to_target if distance_to_target > 0 else 0
                        ]
                        new_pos = [
                            drone_pos[0] + emergency_direction[0] * 0.3,
                            drone_pos[1] + emergency_direction[1] * 0.3
                        ]
                        new_pos[0] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, new_pos[0]))
                        new_pos[1] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, new_pos[1]))
                        new_velocity = [emergency_direction[0] * MAX_SPEED * 0.5, emergency_direction[1] * MAX_SPEED * 0.5]
                        movement_plan = create_fallback_plan(new_pos, target_pos)
                        current_plan_step = 0
                        stuck_counter = 0
                else:
                    stuck_counter = 0
                    # Exit emergency mode if we're moving well
                    if emergency_mode and movement_distance > 0.1:
                        emergency_mode = False
                        print("Exiting emergency mode - drone moving normally")
                    
                drone_pos = new_pos
                drone_velocity = new_velocity
                last_pos = drone_pos.copy()
            else:
                # If not safe, increment unsafe counter
                unsafe_counter += 1
                if unsafe_counter > unsafe_threshold:
                    if close_to_target:
                        print("Close to target, forcing careful movement...")
                    else:
                        print("Too many unsafe attempts, forcing movement...")
                    drone_pos = new_pos
                    drone_velocity = new_velocity
                    last_pos = drone_pos.copy()
                    unsafe_counter = 0
                else:
                    # Create a new plan
                    movement_plan = create_fallback_plan(drone_pos, target_pos)
                    current_plan_step = 0

            # Adjust step completion tolerance based on distance to target and emergency mode
            step_tolerance = 0.3 if emergency_mode else (0.1 if close_to_target else 0.2)
            
            # Check if we've reached the current step
            if distance(drone_pos, movement_plan[current_plan_step]) < step_tolerance:
                current_plan_step += 1
                if current_plan_step >= len(movement_plan):
                    # Plan complete, wait for next plan
                    movement_plan = []
                    current_plan_step = 0
        else:
            # No movement plan - create one immediately
            if not movement_plan:
                movement_plan = create_fallback_plan(drone_pos, target_pos)
                current_plan_step = 0

        # Keep drone within bounds
        drone_pos[0] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, drone_pos[0]))
        drone_pos[1] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, drone_pos[1]))

        # Update target position
        target_pos = move_towards(target_pos, 
                                [target_pos[0] + target_direction[0], 
                                 target_pos[1] + target_direction[1]], 
                                TARGET_SPEED, dt)

        # Bounce target off walls
        if target_pos[0] <= TARGET_RADIUS or target_pos[0] >= GRID_SIZE - TARGET_RADIUS:
            target_direction[0] *= -1
        if target_pos[1] <= TARGET_RADIUS or target_pos[1] >= GRID_SIZE - TARGET_RADIUS:
            target_direction[1] *= -1

        # Keep target within bounds
        target_pos[0] = max(TARGET_RADIUS, min(GRID_SIZE - TARGET_RADIUS, target_pos[0]))
        target_pos[1] = max(TARGET_RADIUS, min(GRID_SIZE - TARGET_RADIUS, target_pos[1]))

        # Check for collision using circle boundaries
        if check_circle_collision(drone_pos, target_pos, DRONE_RADIUS, TARGET_RADIUS):
            print("✅ Target reached! Ending simulation.")
            running = False
            break

        draw_grid(screen, font)
        render_reasoning(screen, font)
        clock.tick(FPS)

    pygame.quit()
    llm_thread.join()

if __name__ == "__main__":
    main()