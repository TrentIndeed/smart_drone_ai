import subprocess
import json
import time
import threading
import textwrap
import re

# --- Skill Library ---
skills = {
    "intercept": "Calculate best path to reach the target quickly.",
    "predict_target_path": "Predict future positions of a moving target.",
    "avoid_obstacles": "Plan a route that avoids obstacles.",
    "reposition": "Move to a better vantage point to regain visibility.",
}

# AI decision timing
LLM_DECISION_INTERVAL = 0.5  # Reduced from 1.0 to 0.5 seconds for more responsive AI

class DroneAI:
    def __init__(self, grid_size, plan_steps=3):
        self.grid_size = grid_size
        self.plan_steps = plan_steps
        self.reasoning = "AI initializing..."
        self.reasoning_lines = ["AI initializing...", "Analyzing environment...", "Planning movement..."]
        self.movement_plan = []
        self.current_plan_step = 0
        self.running = True
        self.history = []
        self.max_steps = 20
        
    def prompt_ollama(self, prompt, model="llama3"):
        """Send prompt to Ollama and get response."""
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
    
    def format_position(self, pos):
        """Format position to 2 decimal places."""
        return [round(pos[0], 2), round(pos[1], 2)]
    
    def get_speed(self, velocity):
        """Calculate speed from velocity vector."""
        import math
        return round(math.sqrt(velocity[0]**2 + velocity[1]**2), 2)
    
    def create_fallback_plan(self, start_pos, target_pos, obstacles):
        """Create a simple linear plan towards the target with some randomness to avoid getting stuck."""
        from environment import distance, is_position_safe, find_safe_position
        from drone import DRONE_RADIUS
        import math
        
        plan = []
        current_pos = start_pos
        
        # Check if we're close to the target
        close_to_target = distance(start_pos, target_pos) < 2.0
        
        for i in range(self.plan_steps):
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
            direct_step[0] = max(DRONE_RADIUS, min(self.grid_size - DRONE_RADIUS, direct_step[0]))
            direct_step[1] = max(DRONE_RADIUS, min(self.grid_size - DRONE_RADIUS, direct_step[1]))
            
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
                    next_pos[0] = max(DRONE_RADIUS, min(self.grid_size - DRONE_RADIUS, next_pos[0]))
                    next_pos[1] = max(DRONE_RADIUS, min(self.grid_size - DRONE_RADIUS, next_pos[1]))
            
            plan.append(self.format_position(next_pos))
            current_pos = next_pos
        
        return plan
    
    def llm_decision_loop(self, drone, target, obstacles):
        """Main AI decision loop that runs in a separate thread."""
        steps = 0

        while self.running and steps < self.max_steps:
            if not self.running:  # Check if we should stop
                break
                
            time.sleep(LLM_DECISION_INTERVAL)
            
            if not self.running:  # Check again after sleep
                break
            
            print(f"\nStep {steps}")
            print("Drone:", self.format_position(drone.pos), "Target:", self.format_position(target.pos))
            print("Drone velocity:", [round(v, 2) for v in drone.velocity], "Speed:", self.get_speed(drone.velocity))

            # If we're stuck or have no plan, create a fallback plan
            if not self.movement_plan or self.current_plan_step >= len(self.movement_plan):
                self.movement_plan = self.create_fallback_plan(drone.pos, target.pos, obstacles)
                self.current_plan_step = 0
                print("Using fallback plan:", self.movement_plan)
                continue

            # Create the prompt for the LLM
            prompt = (
                "You are a drone control AI agent. You are operating in a 100ft x 100ft area (10x10 grid, each unit = 10ft).\n"
                f"DRONE: Position {self.format_position(drone.pos)}, Velocity {[round(v, 2) for v in drone.velocity]}, Speed {self.get_speed(drone.velocity):.2f} units/s\n"
                f"TARGET: Position {self.format_position(target.pos)}, Velocity {[round(v, 2) for v in target.velocity]}, Speed {target.get_speed():.2f} units/s\n"
                f"OBSTACLES: {[self.format_position(obs) for obs in obstacles]}\n"
                "PHYSICS: Drone (2x2ft, max 34mph, 12ft/s² accel), Target (track runner, max 17mph, 8ft/s² accel)\n"
                "TARGET BEHAVIOR: The target is ACTIVELY EVADING you! It will:\n"
                "- Run away from your current position\n"
                "- Avoid walls and obstacles\n"
                "- Use trees and rocks for cover\n"
                "- Change direction to escape your pursuit\n"
                "PREDICTION: Based on target's current velocity and evasive behavior, predict where it will be in 1-3 seconds.\n"
                "STRATEGY: Create an INTERCEPTION plan, not a chase plan. Go where the target WILL BE, not where it IS.\n"
                "Consider:\n"
                "1. Target's current velocity and likely escape routes\n"
                "2. How target will react to your movement\n"
                "3. Use obstacles to cut off escape paths\n"
                "4. Plan multiple steps ahead to corner the target\n"
                "You have the following skills available:\n" +
                "\n".join([f"- {k}: {v}" for k,v in skills.items()]) + "\n"
                f"Create a {self.plan_steps}-step INTERCEPTION plan. Each step should anticipate target movement.\n"
                f"Reply in JSON like: {{\"plan\": [[x1,y1], [x2,y2], [x3,y3]], \"reasoning\": \"Target moving [direction] at [speed], will likely be at [prediction] in 2s. My plan: [strategy]\"}}"
            )

            try:
                response = self.prompt_ollama(prompt)
                match = re.search(r'\{.*?\}', response, re.DOTALL)
                if not match:
                    raise ValueError("No JSON object found in response")

                json_response = json.loads(match.group())
                plan = json_response.get("plan")
                reasoning = json_response.get("reasoning")

                if (plan and len(plan) == self.plan_steps and 
                    all(0 <= pos[0] < self.grid_size and 0 <= pos[1] < self.grid_size for pos in plan)):
                    
                    # Validate that the plan makes sense (each step gets closer to target)
                    from environment import distance
                    valid_plan = True
                    for i in range(len(plan)-1):
                        if distance(plan[i], target.pos) <= distance(plan[i+1], target.pos):
                            valid_plan = False
                            break
                    
                    if valid_plan:
                        self.movement_plan = [self.format_position(pos) for pos in plan]
                        self.current_plan_step = 0
                        self.history.append({
                            "drone": self.format_position(drone.pos),
                            "target": self.format_position(target.pos),
                            "plan": self.movement_plan,
                            "reasoning": reasoning
                        })
                        self.reasoning = reasoning
                        self.reasoning_lines = textwrap.wrap(reasoning, width=45)[:5]  # Use 5 lines to fit in smaller area
                        print(f"DEBUG: Updated reasoning: {self.reasoning_lines}")  # Debug output
                    else:
                        self.movement_plan = self.create_fallback_plan(drone.pos, target.pos, obstacles)
                        self.current_plan_step = 0
                        self.reasoning = "Plan validation failed - using fallback strategy"
                        self.reasoning_lines = ["Plan validation failed", "Using fallback strategy", "Moving toward target"]
                else:
                    self.movement_plan = self.create_fallback_plan(drone.pos, target.pos, obstacles)
                    self.current_plan_step = 0
                    self.reasoning = "Invalid plan received - using fallback"
                    self.reasoning_lines = ["Invalid plan received", "Using fallback strategy", "Direct approach"]

            except Exception as e:
                self.movement_plan = self.create_fallback_plan(drone.pos, target.pos, obstacles)
                self.current_plan_step = 0
                self.reasoning = f"AI Error: {str(e)[:50]}..."
                self.reasoning_lines = ["AI Decision Error", f"Error: {str(e)[:30]}...", "Using fallback plan"]
                print(f"DEBUG: AI Error: {e}")  # Debug output

            steps += 1
    
    def start_ai_thread(self, drone, target, obstacles):
        """Start the AI decision loop in a separate thread."""
        ai_thread = threading.Thread(target=self.llm_decision_loop, args=(drone, target, obstacles))
        ai_thread.daemon = True  # Make thread daemon so it stops when main stops
        ai_thread.start()
        return ai_thread
    
    def stop(self):
        """Stop the AI decision loop."""
        self.running = False 