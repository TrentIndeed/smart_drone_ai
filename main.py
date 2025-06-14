# drone_llm_agent.py
# Requires: `ollama` running locally with a model like `llama3`
# GUI requires: `pip install pygame`

import time
import pygame

# Import our modules
from environment import Environment, FPS, check_circle_collision, distance, GRID_SIZE
from drone import Drone, DRONE_RADIUS, MAX_SPEED
from target import Target, TARGET_RADIUS  
from ai import DroneAI

# Movement parameters
MOVE_SPEED = 6.0  # Increased for smaller arena

def main():
    # Initialize environment
    env = Environment()
    clock = env.initialize_pygame()
    
    # Initialize drone
    drone = Drone(GRID_SIZE)
    drone.initialize_position()
    
    # Initialize target
    target = Target(GRID_SIZE)
    target.initialize_position()
    
    # Setup obstacles
    env.setup_obstacles(drone.pos, target.pos)
            
    # Initialize AI
    ai = DroneAI(GRID_SIZE)
    
    # Movement tracking variables
    stuck_counter = 0
    last_pos = drone.pos.copy()
    unsafe_counter = 0
    position_history = []
    emergency_mode = False
    last_print_time = 0
    
    # Start AI decision thread
    ai_thread = ai.start_ai_thread(drone, target, env.obstacles)
    
    # Main game loop
    last_time = time.time()
    running = True
    
    while running:
        current_time = time.time()
        dt = current_time - last_time
        last_time = current_time

        # Handle pygame events
        for event in pygame.event.get():
            if event.type == pygame.QUIT:
                running = False
                break

        # Track position history for oscillation detection
        if len(position_history) == 0 or current_time - getattr(main, 'last_history_time', 0) > 0.1:
            position_history.append(drone.pos.copy())
            main.last_history_time = current_time
            if len(position_history) > 15:
                position_history.pop(0)

        # Check for oscillation (drone moving back and forth)
        if len(position_history) >= 8 and current_time - getattr(main, 'last_oscillation_check', 0) > 0.5:
            recent_positions = position_history[-8:]
            avg_movement = sum(distance(recent_positions[i], recent_positions[i-1]) 
                             for i in range(1, len(recent_positions))) / (len(recent_positions) - 1)
            if avg_movement < 0.05:
                stuck_counter += 1
            main.last_oscillation_check = current_time

        # Update drone position
        if ai.movement_plan and ai.current_plan_step < len(ai.movement_plan):
            # Move towards the current step in the plan
            new_pos, new_velocity = drone.move_with_acceleration(ai.movement_plan[ai.current_plan_step], dt)
            
            # Check distance to target for safety adjustments
            distance_to_target = distance(drone.pos, target.pos)
            close_to_target = distance_to_target < 2.0
            
            # Adjust unsafe threshold based on distance to target and emergency mode
            unsafe_threshold = 1 if emergency_mode else (2 if close_to_target else 3)
            
            # Safety check with emergency mode considerations
            from environment import is_position_safe
            safety_check = True if emergency_mode else is_position_safe(new_pos, env.obstacles, relaxed=close_to_target)
            
            if safety_check or unsafe_counter > unsafe_threshold:
                # Reset unsafe counter if we found a safe path
                if safety_check:
                    unsafe_counter = 0
                
                # Check if we're actually moving
                movement_distance = distance(new_pos, last_pos)
                if movement_distance < 0.01:
                    stuck_counter += 1
                    if stuck_counter > 5:
                        # Throttle console output
                        if current_time - last_print_time > 2.0:
                            print("Drone stuck, entering emergency mode...")
                            last_print_time = current_time
                        emergency_mode = True
                        
                        # Force movement towards target
                        emergency_direction = [
                            (target.pos[0] - drone.pos[0]) / distance_to_target if distance_to_target > 0 else 0,
                            (target.pos[1] - drone.pos[1]) / distance_to_target if distance_to_target > 0 else 0
                        ]
                        new_pos = [
                            drone.pos[0] + emergency_direction[0] * 0.3,
                            drone.pos[1] + emergency_direction[1] * 0.3
                        ]
                        new_pos[0] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, new_pos[0]))
                        new_pos[1] = max(DRONE_RADIUS, min(GRID_SIZE - DRONE_RADIUS, new_pos[1]))
                        new_velocity = [emergency_direction[0] * MAX_SPEED * 0.5, emergency_direction[1] * MAX_SPEED * 0.5]
                        
                        ai.movement_plan = ai.create_fallback_plan(new_pos, target.pos, env.obstacles)
                        ai.current_plan_step = 0
                        stuck_counter = 0
                        unsafe_counter = 0
                else:
                    stuck_counter = 0
                    if emergency_mode and movement_distance > 0.1:
                        emergency_mode = False
                    
                drone.update_position(new_pos, new_velocity)
                last_pos = drone.pos.copy()
            else:
                # If not safe, increment unsafe counter
                unsafe_counter += 1
                if unsafe_counter > unsafe_threshold:
                    if current_time - last_print_time > 3.0:
                        if close_to_target:
                            print("Close to target, forcing movement...")
                        else:
                            print("Forcing movement...")
                        last_print_time = current_time
                    drone.update_position(new_pos, new_velocity)
                    last_pos = drone.pos.copy()
                    unsafe_counter = 0
                else:
                    ai.movement_plan = ai.create_fallback_plan(drone.pos, target.pos, env.obstacles)
                    ai.current_plan_step = 0
            
            # Check if we've reached the current step
            step_tolerance = 0.3 if emergency_mode else (0.1 if close_to_target else 0.2)
            if distance(drone.pos, ai.movement_plan[ai.current_plan_step]) < step_tolerance:
                ai.current_plan_step += 1
                if ai.current_plan_step >= len(ai.movement_plan):
                    ai.movement_plan = []
                    ai.current_plan_step = 0
        else:
            # No movement plan - create one immediately
            if not ai.movement_plan:
                ai.movement_plan = ai.create_fallback_plan(drone.pos, target.pos, env.obstacles)
                ai.current_plan_step = 0

        # Keep drone within bounds
        bounds_changed = drone.keep_within_bounds()
        if bounds_changed and ai.movement_plan:
            ai.movement_plan = ai.create_fallback_plan(drone.pos, target.pos, env.obstacles)
            ai.current_plan_step = 0
        
        # Update target behavior
        target.update(drone.pos, env.obstacles, dt)

        # Check for collision
        if check_circle_collision(drone.pos, target.pos, DRONE_RADIUS, TARGET_RADIUS):
            print("✅ Target reached! Ending simulation.")
            running = False
            break

        # Render everything
        env.draw_grid(drone.pos, target.pos, ai.reasoning_lines)
        env.render_reasoning(ai.reasoning_lines)
        clock.tick(FPS)

    # Clean shutdown
    ai.stop()
    pygame.quit()
    if ai_thread.is_alive():
        ai_thread.join(timeout=1.0)

if __name__ == "__main__":
    main()