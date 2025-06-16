"""
Drone Planner for Hunter AI
Handles strategic planning, path generation, and interception calculations
"""

import asyncio
import json
import subprocess
import time
import math
from typing import Dict, List, Tuple, Optional
import logging

logger = logging.getLogger(__name__)

class DronePlanner:
    """Strategic planner for drone movement and interception"""
    
    def __init__(self, grid_size: int = 10):
        self.grid_size = grid_size
        self.plan_steps = 3
        self.max_speed = 16.0  # ft/s - Realistic 2x2ft surveillance drone speed  
        self.max_acceleration = 15.0  # ft/s² - Better acceleration than human
        
        # Skill library - drone can fly over obstacles, target cannot
        self.skills = {
            "intercept": "Calculate best path to reach the target quickly - drone can fly over obstacles",
            "predict_target_path": "Predict future positions of a moving target",
            "aerial_advantage": "Fly directly over obstacles that block the ground-bound target",
            "corner_target": "Use obstacles to trap the ground-bound target - drone can fly over",
            "overhead_pursuit": "Maintain pursuit by flying over terrain the target must navigate around",
            "engagement_positioning": "Position for optimal shooting range (1.5 units) to neutralize target",
            "shooting_approach": "Close to 2.5 unit max range for target engagement",
            "emergency_pursuit": "Direct aggressive pursuit when other strategies fail"
        }
    
    async def create_interception_plan(self, drone_pos: List[float], target_pos: List[float], 
                                     obstacles: List[Dict], memory_context: Dict,
                                     emergency_mode: bool = False) -> Tuple[List[List[float]], str]:
        """Create an interception plan using AI reasoning"""
        
        if emergency_mode:
            return self._create_emergency_plan(drone_pos, target_pos, obstacles)
        
        # Try AI-powered planning first
        try:
            plan, reasoning = await self._ai_powered_planning(
                drone_pos, target_pos, obstacles, memory_context
            )
            
            if self._validate_plan(plan, drone_pos, target_pos, obstacles):
                return plan, reasoning
            else:
                logger.warning("AI plan failed validation, using fallback")
                
        except Exception as e:
            logger.error(f"AI planning failed: {e}")
        
        # Fallback to algorithmic planning
        return self._create_algorithmic_plan(drone_pos, target_pos, obstacles)
    
    async def _ai_powered_planning(self, drone_pos: List[float], target_pos: List[float], 
                                 obstacles: List[Dict], memory_context: Dict) -> Tuple[List[List[float]], str]:
        """Use AI (Ollama) to generate strategic plans"""
        
        # Build context from memory
        context_str = self._build_memory_context(memory_context)
        
        # Calculate current metrics
        distance_to_target = self._distance(drone_pos, target_pos)
        target_direction = self._get_direction(drone_pos, target_pos)
        
        # Create AI prompt
        prompt = f"""You are an expert hunter drone strategist. You control a drone hunting an evasive target.

CURRENT SITUATION:
- Drone Position: {self._format_pos(drone_pos)} 
- Target Position: {self._format_pos(target_pos)}
- Distance to Target: {distance_to_target:.2f} units
- Target Direction: {target_direction}
- Obstacles: {self._format_obstacles_for_prompt(obstacles)}

ENVIRONMENT:
- Grid Size: {self.grid_size}x{self.grid_size} units (each unit = 10ft)
- Drone: Max speed {self.max_speed} ft/s (~35 mph), Max acceleration {self.max_acceleration} ft/s² - CAN FLY OVER OBSTACLES
- Target: Human runner (~25 mph max), ground-bound, CANNOT fly over obstacles - must navigate around them
- Speed Advantage: Drone is ~40% faster than target and has aerial mobility
- WEAPONS: Must neutralize target within shooting range (max 2.5 units, optimal 1.5 units)
- MISSION: Position within range and engage - NOT capture by proximity

MEMORY CONTEXT:
{context_str}

AVAILABLE SKILLS:
{chr(10).join([f"- {skill}: {desc}" for skill, desc in self.skills.items()])}

TASK: Create a {self.plan_steps}-step interception plan. The target is ACTIVELY EVADING - predict where it will go and intercept it there.

STRATEGY CONSIDERATIONS:
1. AERIAL ADVANTAGE: You can fly directly over obstacles while target must go around
2. ENGAGEMENT RANGE: Must get within 2.5 units to neutralize (optimal: 1.5 units)
3. Predict target's likely escape routes (limited by ground obstacles)
4. Use obstacles to cut off target's escape paths - you can fly over them to intercept
5. Plan positioning for engagement, not just pursuit - STOP WHEN IN RANGE
6. Target will seek cover behind obstacles - use your flight to bypass this
7. Maintain shooting position once in optimal range (1.5 units)
8. Use successful patterns from memory

Respond in JSON format:
{{
    "plan": [[x1,y1], [x2,y2], [x3,y3]],
    "reasoning": "Detailed explanation of strategy and predictions",
    "strategy_type": "intercept|corner|pursuit|ambush",
    "confidence": 0.0-1.0
}}"""

        try:
            response = await self._query_ollama(prompt)
            result = self._parse_ai_response(response)
            
            if result and "plan" in result and "reasoning" in result:
                return result["plan"], result["reasoning"]
            else:
                raise ValueError("Invalid AI response format")
                
        except Exception as e:
            logger.error(f"AI planning error: {e}")
            raise
    
    async def _query_ollama(self, prompt: str, model: str = "llama3") -> str:
        """Query Ollama API asynchronously"""
        try:
            process = await asyncio.create_subprocess_exec(
                "ollama", "run", model,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE
            )
            
            stdout, stderr = await process.communicate(prompt.encode())
            
            if process.returncode != 0:
                raise RuntimeError(f"Ollama error: {stderr.decode()}")
            
            return stdout.decode().strip()
            
        except Exception as e:
            logger.error(f"Ollama query failed: {e}")
            raise
    
    def _parse_ai_response(self, response: str) -> Optional[Dict]:
        """Parse AI response and extract JSON"""
        try:
            # Find JSON in response
            start = response.find('{')
            end = response.rfind('}') + 1
            
            if start >= 0 and end > start:
                json_str = response[start:end]
                return json.loads(json_str)
            else:
                logger.warning("No JSON found in AI response")
                return None
                
        except json.JSONDecodeError as e:
            logger.error(f"JSON parsing error: {e}")
            return None
    
    def _create_algorithmic_plan(self, drone_pos: List[float], target_pos: List[float], 
                               obstacles: List[Dict]) -> Tuple[List[List[float]], str]:
        """Create plan using algorithmic approach"""
        
        # Calculate interception points
        plan = []
        current_pos = drone_pos[:]
        
        # Predict target movement
        target_velocity = self._estimate_target_velocity(target_pos)
        
        for step in range(self.plan_steps):
            # Predict where target will be
            prediction_time = (step + 1) * 0.5  # 0.5 seconds per step
            predicted_target_pos = [
                target_pos[0] + target_velocity[0] * prediction_time,
                target_pos[1] + target_velocity[1] * prediction_time
            ]
            
            # Plan interception point
            interception_point = self._calculate_interception_point(
                current_pos, predicted_target_pos, obstacles
            )
            
            plan.append(interception_point)
            current_pos = interception_point
        
        # Calculate current distance for reasoning
        current_distance = self._distance(drone_pos, target_pos)
        if current_distance <= 1.5:
            range_status = "OPTIMAL ENGAGEMENT RANGE"
        elif current_distance <= 2.5:
            range_status = "IN SHOOTING RANGE"
        else:
            range_status = f"CLOSING TO ENGAGE ({current_distance:.1f} units)"
        
        reasoning = f"Algorithmic engagement plan: {range_status}. Target velocity: {target_velocity}"
        
        return plan, reasoning
    
    def _create_emergency_plan(self, drone_pos: List[float], target_pos: List[float], 
                             obstacles: List[Dict]) -> Tuple[List[List[float]], str]:
        """Create emergency plan for when drone is stuck or failing"""
        
        # Direct pursuit with obstacle avoidance
        plan = []
        current_pos = drone_pos[:]
        
        for step in range(self.plan_steps):
            # Move directly toward target with small steps
            direction = self._get_direction_vector(current_pos, target_pos)
            step_size = 0.5  # Small steps in emergency mode
            
            next_pos = [
                current_pos[0] + direction[0] * step_size,
                current_pos[1] + direction[1] * step_size
            ]
            
            # Clamp to bounds
            next_pos = self._clamp_to_bounds(next_pos)
            
            # Basic obstacle avoidance (drone can fly over obstacles, so this is minimal)
            if self._is_position_unsafe(next_pos, obstacles, for_drone=True):
                # Try perpendicular directions (though drone should rarely need this)
                perpendicular = [-direction[1], direction[0]]
                next_pos = [
                    current_pos[0] + perpendicular[0] * step_size,
                    current_pos[1] + perpendicular[1] * step_size
                ]
                next_pos = self._clamp_to_bounds(next_pos)
            
            plan.append(next_pos)
            current_pos = next_pos
        
        reasoning = "Emergency direct pursuit plan - moving aggressively toward target"
        
        return plan, reasoning
    
    def _validate_plan(self, plan: List[List[float]], drone_pos: List[float], 
                      target_pos: List[float], obstacles: List[Dict]) -> bool:
        """Validate that a plan is reasonable"""
        if not plan or len(plan) != self.plan_steps:
            return False
        
        # Check all positions are within bounds
        for pos in plan:
            if not (0 <= pos[0] < self.grid_size and 0 <= pos[1] < self.grid_size):
                return False
        
        # Check plan generally moves toward target
        plan_end = plan[-1]
        initial_distance = self._distance(drone_pos, target_pos)
        final_distance = self._distance(plan_end, target_pos)
        
        # Plan should reduce distance to target (or at least not increase it significantly)
        if final_distance > initial_distance * 1.2:
            return False
        
        return True
    
    def _build_memory_context(self, memory_context: Dict) -> str:
        """Build context string from memory"""
        context_parts = []
        
        # Successful strategies
        if memory_context.get("successful_strategies"):
            context_parts.append("SUCCESSFUL STRATEGIES:")
            for strategy in memory_context["successful_strategies"][:3]:
                context_parts.append(f"- {strategy.get('strategy', 'Unknown')}")
        
        # Failure patterns
        if memory_context.get("failure_patterns", {}).get("most_common_failure"):
            context_parts.append(f"AVOID: {memory_context['failure_patterns']['most_common_failure']}")
        
        # Recent target behaviors
        if memory_context.get("target_behaviors"):
            context_parts.append("TARGET BEHAVIORS:")
            for behavior in memory_context["target_behaviors"][:2]:
                context_parts.append(f"- {behavior.get('behavior_pattern', 'Unknown')}")
        
        return "\n".join(context_parts) if context_parts else "No relevant memory context"
    
    def _calculate_interception_point(self, drone_pos: List[float], target_pos: List[float], 
                                    obstacles: List[Dict]) -> List[float]:
        """Calculate optimal interception point for engagement"""
        # Calculate current distance to target
        direction = self._get_direction_vector(drone_pos, target_pos)
        distance = self._distance(drone_pos, target_pos)
        
        # Shooting range parameters
        max_range = 2.5
        optimal_range = 1.5
        
        # If already in optimal range, stay close
        if distance <= optimal_range:
            step_size = 0.2  # Small adjustments only
        elif distance <= max_range:
            # In shooting range - close to optimal range
            step_size = min((distance - optimal_range) * 0.8, 0.5)
        else:
            # Too far - close distance more aggressively
            step_size = min(distance / 2, 1.0)
        
        interception_point = [
            drone_pos[0] + direction[0] * step_size,
            drone_pos[1] + direction[1] * step_size
        ]
        
        # Minimal obstacle avoidance for drone (can fly over most obstacles)
        if self._is_position_unsafe(interception_point, obstacles, for_drone=True):
            # Try alternative positions (though drone should rarely need this)
            for angle_offset in [0.5, -0.5, 1.0, -1.0]:
                angle = math.atan2(direction[1], direction[0]) + angle_offset
                alt_point = [
                    drone_pos[0] + math.cos(angle) * step_size,
                    drone_pos[1] + math.sin(angle) * step_size
                ]
                if not self._is_position_unsafe(alt_point, obstacles, for_drone=True):
                    interception_point = alt_point
                    break
        
        return self._clamp_to_bounds(interception_point)
    
    def _estimate_target_velocity(self, target_pos: List[float]) -> List[float]:
        """Estimate target velocity based on position"""
        # Simplified - assume target moves away from center
        center = [self.grid_size / 2, self.grid_size / 2]
        direction = self._get_direction_vector(center, target_pos)
        speed = 1.8  # Realistic human jogging speed (3.0 * 0.6 base multiplier)
        
        return [direction[0] * speed, direction[1] * speed]
    
    def _get_direction_vector(self, from_pos: List[float], to_pos: List[float]) -> List[float]:
        """Get normalized direction vector"""
        dx = to_pos[0] - from_pos[0]
        dy = to_pos[1] - from_pos[1]
        distance = math.sqrt(dx*dx + dy*dy)
        
        if distance < 0.001:
            return [0.0, 0.0]
        
        return [dx/distance, dy/distance]
    
    def _get_direction(self, from_pos: List[float], to_pos: List[float]) -> str:
        """Get cardinal direction description"""
        dx = to_pos[0] - from_pos[0]
        dy = to_pos[1] - from_pos[1]
        
        if abs(dx) > abs(dy):
            return "East" if dx > 0 else "West"
        else:
            return "North" if dy > 0 else "South"
    
    def _distance(self, pos1: List[float], pos2: List[float]) -> float:
        """Calculate distance between positions"""
        return math.sqrt((pos1[0] - pos2[0])**2 + (pos1[1] - pos2[1])**2)
    
    def _is_position_unsafe(self, pos: List[float], obstacles: List[Dict], 
                          safety_margin: float = 0.5, for_drone: bool = True) -> bool:
        """Check if position is too close to obstacles
        
        Args:
            pos: Position to check
            obstacles: List of obstacle dictionaries with position and blocking info
            safety_margin: Safety distance
            for_drone: If True, only check obstacles that block drones (none currently)
                      If False, check obstacles that block target (all of them)
        """
        for obstacle in obstacles:
            # Handle both old format (list) and new format (dict)
            if isinstance(obstacle, dict):
                obstacle_pos = obstacle["position"]
                blocks_drone = obstacle.get("blocks_drone", True)  # Default to blocking for safety
                
                # Drone can fly over obstacles, target cannot
                if for_drone and not blocks_drone:
                    continue  # Skip obstacles that don't block the drone
                
            else:
                # Legacy format - treat as position only
                obstacle_pos = obstacle
            
            if self._distance(pos, obstacle_pos) < safety_margin:
                return True
        
        return False
    
    def _clamp_to_bounds(self, pos: List[float]) -> List[float]:
        """Clamp position to grid bounds"""
        return [
            max(0.5, min(self.grid_size - 0.5, pos[0])),
            max(0.5, min(self.grid_size - 0.5, pos[1]))
        ]
    
    def _format_pos(self, pos: List[float]) -> str:
        """Format position for display"""
        return f"[{pos[0]:.1f}, {pos[1]:.1f}]"
    
    def _format_obstacles_for_prompt(self, obstacles: List[Dict]) -> str:
        """Format obstacles for AI prompt"""
        formatted = []
        for obs in obstacles:
            if isinstance(obs, dict):
                pos_str = self._format_pos(obs["position"])
                obs_type = obs.get("type", "unknown")
                blocks_target = obs.get("blocks_target", True)
                formatted.append(f"{pos_str} ({obs_type}, blocks_target: {blocks_target})")
            else:
                # Legacy format
                formatted.append(self._format_pos(obs))
        return formatted