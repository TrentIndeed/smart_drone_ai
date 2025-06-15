"""
Performance Evaluator for Hunter Drone AI
Evaluates drone performance and provides feedback for strategy adjustment
"""

import time
import math
from typing import Dict, List, Optional
import logging

logger = logging.getLogger(__name__)

class PerformanceEvaluator:
    """Evaluates drone performance and strategy effectiveness"""
    
    def __init__(self):
        self.history = []
        self.max_history = 50
        self.stuck_threshold = 0.1  # Movement less than this is considered stuck
        self.inefficient_threshold = 2.0  # Times longer than optimal
        
    def evaluate_current_state(self, drone_pos: List[float], target_pos: List[float],
                             current_plan: List[List[float]], plan_step: int,
                             reasoning: str) -> Dict:
        """Evaluate current performance state"""
        
        evaluation = {
            "timestamp": time.time(),
            "drone_position": drone_pos,
            "target_position": target_pos,
            "distance_to_target": self._distance(drone_pos, target_pos),
            "plan_progress": plan_step / len(current_plan) if current_plan else 0,
            "reasoning_quality": self._evaluate_reasoning(reasoning)
        }
        
        # Check for stuck condition
        evaluation["stuck"] = self._is_stuck(drone_pos)
        
        # Check for inefficient movement
        evaluation["inefficient"] = self._is_inefficient(drone_pos, target_pos)
        
        # Check if performing well
        evaluation["performing_well"] = self._is_performing_well(drone_pos, target_pos)
        
        # Overall performance score
        evaluation["performance_score"] = self._calculate_performance_score(evaluation)
        
        # Store in history
        self.history.append(evaluation)
        if len(self.history) > self.max_history:
            self.history.pop(0)
        
        return evaluation
    
    def _is_stuck(self, current_pos: List[float]) -> bool:
        """Check if drone appears to be stuck"""
        if len(self.history) < 5:
            return False
        
        # Check recent movement
        recent_positions = [h["drone_position"] for h in self.history[-5:]]
        recent_positions.append(current_pos)
        
        total_movement = 0
        for i in range(1, len(recent_positions)):
            total_movement += self._distance(recent_positions[i-1], recent_positions[i])
        
        avg_movement = total_movement / (len(recent_positions) - 1)
        return avg_movement < self.stuck_threshold
    
    def _is_inefficient(self, drone_pos: List[float], target_pos: List[float]) -> bool:
        """Check if movement is inefficient"""
        if len(self.history) < 3:
            return False
        
        # Compare current distance to target with distance 3 steps ago
        previous_distance = self.history[-3]["distance_to_target"]
        current_distance = self._distance(drone_pos, target_pos)
        
        # If we haven't made meaningful progress, it's inefficient
        progress = previous_distance - current_distance
        return progress < 0.2  # Less than 0.2 units progress in 3 steps
    
    def _is_performing_well(self, drone_pos: List[float], target_pos: List[float]) -> bool:
        """Check if drone is performing well"""
        if len(self.history) < 3:
            return True  # Assume good performance initially
        
        # Check consistent progress toward target
        distances = [h["distance_to_target"] for h in self.history[-3:]]
        distances.append(self._distance(drone_pos, target_pos))
        
        # Check if distances are generally decreasing
        decreasing_trend = 0
        for i in range(1, len(distances)):
            if distances[i] < distances[i-1]:
                decreasing_trend += 1
        
        return decreasing_trend >= 2  # At least 2 out of 3 steps showing progress
    
    def _evaluate_reasoning(self, reasoning: str) -> float:
        """Evaluate quality of AI reasoning"""
        if not reasoning:
            return 0.0
        
        score = 0.5  # Base score
        
        # Check for key strategic concepts
        strategic_keywords = [
            "intercept", "predict", "corner", "escape", "route", 
            "strategy", "avoid", "obstacle", "target"
        ]
        
        reasoning_lower = reasoning.lower()
        for keyword in strategic_keywords:
            if keyword in reasoning_lower:
                score += 0.1
        
        # Check for specific tactical details
        if any(word in reasoning_lower for word in ["position", "direction", "speed"]):
            score += 0.1
        
        # Cap at 1.0
        return min(score, 1.0)
    
    def _calculate_performance_score(self, evaluation: Dict) -> float:
        """Calculate overall performance score"""
        score = 0.5  # Base score
        
        # Distance factor (closer is better)
        distance = evaluation["distance_to_target"]
        if distance < 1.0:
            score += 0.3
        elif distance < 3.0:
            score += 0.2
        elif distance < 5.0:
            score += 0.1
        
        # Plan progress factor
        score += evaluation["plan_progress"] * 0.2
        
        # Reasoning quality factor
        score += evaluation["reasoning_quality"] * 0.2
        
        # Penalties
        if evaluation["stuck"]:
            score -= 0.3
        if evaluation["inefficient"]:
            score -= 0.2
        
        # Bonus for good performance
        if evaluation["performing_well"]:
            score += 0.2
        
        return max(0.0, min(1.0, score))
    
    def get_performance_trends(self) -> Dict:
        """Get performance trends over time"""
        if not self.history:
            return {"trend": "no_data"}
        
        recent_scores = [h["performance_score"] for h in self.history[-10:]]
        
        if len(recent_scores) < 3:
            return {"trend": "insufficient_data", "current_score": recent_scores[-1]}
        
        # Calculate trend
        early_avg = sum(recent_scores[:len(recent_scores)//2]) / (len(recent_scores)//2)
        late_avg = sum(recent_scores[len(recent_scores)//2:]) / (len(recent_scores) - len(recent_scores)//2)
        
        trend = "improving" if late_avg > early_avg + 0.1 else \
                "declining" if late_avg < early_avg - 0.1 else "stable"
        
        return {
            "trend": trend,
            "current_score": recent_scores[-1],
            "average_score": sum(recent_scores) / len(recent_scores),
            "stuck_frequency": sum(1 for h in self.history[-10:] if h.get("stuck", False)),
            "inefficiency_frequency": sum(1 for h in self.history[-10:] if h.get("inefficient", False))
        }
    
    def _distance(self, pos1: List[float], pos2: List[float]) -> float:
        """Calculate distance between positions"""
        return math.sqrt((pos1[0] - pos2[0])**2 + (pos1[1] - pos2[1])**2) 