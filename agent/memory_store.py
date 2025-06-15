"""
Memory Store for Hunter Drone AI
Handles storage and retrieval of agent memories, experiences, and learned patterns
"""

import json
import os
import time
from typing import Dict, List, Optional, Tuple
from datetime import datetime, timedelta
import logging

logger = logging.getLogger(__name__)

class MemoryStore:
    """Manages agent memory storage and retrieval"""
    
    def __init__(self, memory_file: str = "data/memory.json"):
        self.memory_file = memory_file
        self.memory_data = self._load_memory()
        
        # Memory categories
        self.categories = {
            "successful_strategies": [],
            "failed_attempts": [],
            "target_behaviors": [],
            "obstacle_patterns": [],
            "interception_points": [],
            "performance_metrics": []
        }
        
        # Initialize categories if not present
        for category in self.categories:
            if category not in self.memory_data:
                self.memory_data[category] = []
    
    def _load_memory(self) -> Dict:
        """Load memory from file"""
        if os.path.exists(self.memory_file):
            try:
                with open(self.memory_file, 'r') as f:
                    return json.load(f)
            except (json.JSONDecodeError, FileNotFoundError) as e:
                logger.warning(f"Could not load memory file: {e}")
                return {}
        return {}
    
    def _save_memory(self):
        """Save memory to file"""
        os.makedirs(os.path.dirname(self.memory_file), exist_ok=True)
        with open(self.memory_file, 'w') as f:
            json.dump(self.memory_data, f, indent=2)
    
    def store_successful_strategy(self, drone_pos: List[float], target_pos: List[float], 
                                 strategy: str, plan: List[List[float]], 
                                 time_to_success: float):
        """Store a successful hunting strategy"""
        memory_entry = {
            "timestamp": time.time(),
            "drone_position": drone_pos,
            "target_position": target_pos,
            "strategy": strategy,
            "plan": plan,
            "time_to_success": time_to_success,
            "success_rate": 1.0
        }
        
        self.memory_data["successful_strategies"].append(memory_entry)
        self._save_memory()
        logger.info(f"Stored successful strategy: {strategy[:50]}...")
    
    def store_failed_attempt(self, drone_pos: List[float], target_pos: List[float], 
                           strategy: str, failure_reason: str):
        """Store a failed hunting attempt"""
        memory_entry = {
            "timestamp": time.time(),
            "drone_position": drone_pos,
            "target_position": target_pos,
            "strategy": strategy,
            "failure_reason": failure_reason,
            "failure_type": self._classify_failure(failure_reason)
        }
        
        self.memory_data["failed_attempts"].append(memory_entry)
        self._save_memory()
        logger.info(f"Stored failed attempt: {failure_reason[:50]}...")
    
    def store_target_behavior(self, target_pos: List[float], target_velocity: List[float], 
                            behavior_pattern: str, context: Dict):
        """Store observed target behavior pattern"""
        memory_entry = {
            "timestamp": time.time(),
            "target_position": target_pos,
            "target_velocity": target_velocity,
            "behavior_pattern": behavior_pattern,
            "context": context
        }
        
        self.memory_data["target_behaviors"].append(memory_entry)
        self._save_memory()
        logger.info(f"Stored target behavior: {behavior_pattern}")
    
    def store_evaluation(self, evaluation: Dict):
        """Store performance evaluation"""
        evaluation["timestamp"] = time.time()
        self.memory_data["performance_metrics"].append(evaluation)
        
        # Keep only recent evaluations (last 100)
        if len(self.memory_data["performance_metrics"]) > 100:
            self.memory_data["performance_metrics"] = self.memory_data["performance_metrics"][-100:]
        
        self._save_memory()
    
    def get_relevant_memories(self, drone_pos: List[float], target_pos: List[float], 
                            obstacles: List[List[float]], max_memories: int = 5) -> Dict:
        """Retrieve memories relevant to current situation"""
        current_time = time.time()
        
        # Get recent successful strategies
        recent_successes = [
            mem for mem in self.memory_data.get("successful_strategies", [])
            if current_time - mem["timestamp"] < 300  # Last 5 minutes
        ]
        
        # Get similar situations based on position similarity
        similar_situations = self._find_similar_situations(drone_pos, target_pos, obstacles)
        
        # Get recent target behaviors
        recent_behaviors = [
            mem for mem in self.memory_data.get("target_behaviors", [])
            if current_time - mem["timestamp"] < 180  # Last 3 minutes
        ]
        
        # Get recent performance metrics
        recent_performance = self.memory_data.get("performance_metrics", [])[-10:]
        
        return {
            "successful_strategies": recent_successes[:max_memories],
            "similar_situations": similar_situations[:max_memories],
            "target_behaviors": recent_behaviors[:max_memories],
            "performance_trends": recent_performance,
            "failure_patterns": self._get_failure_patterns()
        }
    
    def _find_similar_situations(self, drone_pos: List[float], target_pos: List[float], 
                               obstacles: List[List[float]]) -> List[Dict]:
        """Find similar past situations based on position and obstacle layout"""
        similar = []
        
        for memory in self.memory_data.get("successful_strategies", []):
            # Calculate position similarity
            drone_dist = self._distance(drone_pos, memory["drone_position"])
            target_dist = self._distance(target_pos, memory["target_position"])
            
            # If positions are similar (within 2 units), consider it relevant
            if drone_dist < 2.0 and target_dist < 2.0:
                similarity_score = 1.0 / (1.0 + drone_dist + target_dist)
                memory_copy = memory.copy()
                memory_copy["similarity_score"] = similarity_score
                similar.append(memory_copy)
        
        # Sort by similarity score
        similar.sort(key=lambda x: x["similarity_score"], reverse=True)
        return similar
    
    def _get_failure_patterns(self) -> Dict:
        """Analyze failure patterns to avoid repeating mistakes"""
        failures = self.memory_data.get("failed_attempts", [])
        recent_failures = [
            f for f in failures 
            if time.time() - f["timestamp"] < 600  # Last 10 minutes
        ]
        
        # Count failure types
        failure_counts = {}
        for failure in recent_failures:
            failure_type = failure.get("failure_type", "unknown")
            failure_counts[failure_type] = failure_counts.get(failure_type, 0) + 1
        
        return {
            "recent_failure_count": len(recent_failures),
            "failure_types": failure_counts,
            "most_common_failure": max(failure_counts.items(), key=lambda x: x[1])[0] if failure_counts else None
        }
    
    def _classify_failure(self, failure_reason: str) -> str:
        """Classify failure reason into categories"""
        reason_lower = failure_reason.lower()
        
        if "stuck" in reason_lower or "collision" in reason_lower:
            return "navigation_error"
        elif "timeout" in reason_lower or "too_slow" in reason_lower:
            return "performance_issue"
        elif "prediction" in reason_lower or "intercept" in reason_lower:
            return "strategy_error"
        elif "obstacle" in reason_lower:
            return "obstacle_avoidance"
        else:
            return "unknown"
    
    def _distance(self, pos1: List[float], pos2: List[float]) -> float:
        """Calculate Euclidean distance between two positions"""
        return ((pos1[0] - pos2[0])**2 + (pos1[1] - pos2[1])**2)**0.5
    
    def get_statistics(self) -> Dict:
        """Get memory statistics"""
        return {
            "total_successful_strategies": len(self.memory_data.get("successful_strategies", [])),
            "total_failed_attempts": len(self.memory_data.get("failed_attempts", [])),
            "total_target_behaviors": len(self.memory_data.get("target_behaviors", [])),
            "total_performance_metrics": len(self.memory_data.get("performance_metrics", [])),
            "success_rate": self._calculate_success_rate(),
            "memory_file_size": os.path.getsize(self.memory_file) if os.path.exists(self.memory_file) else 0
        }
    
    def _calculate_success_rate(self) -> float:
        """Calculate overall success rate"""
        successes = len(self.memory_data.get("successful_strategies", []))
        failures = len(self.memory_data.get("failed_attempts", []))
        total = successes + failures
        
        if total == 0:
            return 0.0
        
        return successes / total
    
    def clear_old_memories(self, days_old: int = 7):
        """Clear memories older than specified days"""
        cutoff_time = time.time() - (days_old * 24 * 60 * 60)
        
        for category in self.memory_data:
            if isinstance(self.memory_data[category], list):
                self.memory_data[category] = [
                    mem for mem in self.memory_data[category]
                    if mem.get("timestamp", 0) > cutoff_time
                ]
        
        self._save_memory()
        logger.info(f"Cleared memories older than {days_old} days") 