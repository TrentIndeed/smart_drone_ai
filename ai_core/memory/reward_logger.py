"""
Reward Logger
Tracks and logs reward signals for reinforcement learning and performance analysis
"""

import json
import time
from typing import Dict, List, Any
from pathlib import Path
from dataclasses import dataclass


@dataclass
class RewardEvent:
    """Single reward event with context"""
    timestamp: float
    event_type: str
    reward_value: float
    context: Dict[str, Any]
    cumulative_reward: float


class RewardLogger:
    """Logs and analyzes reward signals for the drone AI"""
    
    def __init__(self, log_dir: str = "logs/rewards"):
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        
        self.current_session_rewards: List[RewardEvent] = []
        self.cumulative_reward = 0.0
        self.session_start_time = time.time()
        
        # Reward weights for different events
        self.reward_weights = {
            "target_approached": 1.0,
            "target_intercepted": 100.0,
            "obstacle_avoided": 5.0,
            "obstacle_hit": -25.0,
            "efficient_movement": 2.0,
            "inefficient_movement": -1.0,
            "emergency_activation": -15.0,
            "mission_completed": 50.0,
            "mission_failed": -30.0,
            "battery_optimized": 3.0,
            "altitude_maintained": 1.0,
            "speed_optimized": 2.0
        }
    
    def log_reward(self, event_type: str, context: Dict[str, Any] = None):
        """Log a reward event"""
        if context is None:
            context = {}
        
        reward_value = self.calculate_reward(event_type, context)
        self.cumulative_reward += reward_value
        
        event = RewardEvent(
            timestamp=time.time(),
            event_type=event_type,
            reward_value=reward_value,
            context=context,
            cumulative_reward=self.cumulative_reward
        )
        
        self.current_session_rewards.append(event)
        print(f"Reward: {event_type} = {reward_value:.2f} (Total: {self.cumulative_reward:.2f})")
    
    def calculate_reward(self, event_type: str, context: Dict[str, Any]) -> float:
        """Calculate reward value based on event type and context"""
        base_reward = self.reward_weights.get(event_type, 0.0)
        
        # Context-based reward modifications
        if event_type == "target_approached":
            # Reward based on distance reduction
            distance_change = context.get("distance_change", 0)
            if distance_change < 0:  # Getting closer
                base_reward *= abs(distance_change)
        
        elif event_type == "target_intercepted":
            # Bonus for speed of interception
            time_taken = context.get("time_taken", float('inf'))
            if time_taken < 60:  # Under 1 minute
                base_reward *= 1.5
            elif time_taken < 120:  # Under 2 minutes
                base_reward *= 1.2
        
        elif event_type == "obstacle_avoided":
            # Higher reward for close calls
            avoidance_distance = context.get("avoidance_distance", 10.0)
            if avoidance_distance < 2.0:
                base_reward *= 2.0
            elif avoidance_distance < 5.0:
                base_reward *= 1.5
        
        elif event_type == "efficient_movement":
            # Reward based on movement efficiency
            efficiency_score = context.get("efficiency", 1.0)
            base_reward *= efficiency_score
        
        return base_reward
    
    def get_session_summary(self) -> Dict[str, Any]:
        """Get summary of current session rewards"""
        if not self.current_session_rewards:
            return {"total_reward": 0.0, "event_count": 0, "events_by_type": {}}
        
        events_by_type = {}
        for event in self.current_session_rewards:
            event_type = event.event_type
            if event_type not in events_by_type:
                events_by_type[event_type] = {"count": 0, "total_reward": 0.0}
            
            events_by_type[event_type]["count"] += 1
            events_by_type[event_type]["total_reward"] += event.reward_value
        
        session_duration = time.time() - self.session_start_time
        
        return {
            "total_reward": self.cumulative_reward,
            "event_count": len(self.current_session_rewards),
            "session_duration": session_duration,
            "average_reward_per_minute": self.cumulative_reward / (session_duration / 60) if session_duration > 0 else 0,
            "events_by_type": events_by_type
        }
    
    def save_session(self, session_id: str = None):
        """Save current session to file"""
        if session_id is None:
            session_id = f"session_{int(time.time())}"
        
        session_data = {
            "session_id": session_id,
            "start_time": self.session_start_time,
            "end_time": time.time(),
            "total_reward": self.cumulative_reward,
            "events": [
                {
                    "timestamp": event.timestamp,
                    "event_type": event.event_type,
                    "reward_value": event.reward_value,
                    "context": event.context,
                    "cumulative_reward": event.cumulative_reward
                }
                for event in self.current_session_rewards
            ],
            "summary": self.get_session_summary()
        }
        
        session_file = self.log_dir / f"{session_id}.json"
        with open(session_file, 'w') as f:
            json.dump(session_data, f, indent=2)
        
        print(f"Session saved to {session_file}")
    
    def load_session(self, session_id: str):
        """Load a previous session"""
        session_file = self.log_dir / f"{session_id}.json"
        if not session_file.exists():
            print(f"Session file {session_file} not found")
            return False
        
        with open(session_file, 'r') as f:
            session_data = json.load(f)
        
        self.current_session_rewards = [
            RewardEvent(
                timestamp=event["timestamp"],
                event_type=event["event_type"],
                reward_value=event["reward_value"],
                context=event["context"],
                cumulative_reward=event["cumulative_reward"]
            )
            for event in session_data["events"]
        ]
        
        self.cumulative_reward = session_data["total_reward"]
        self.session_start_time = session_data["start_time"]
        
        return True
    
    def get_reward_trends(self, window_size: int = 10) -> List[float]:
        """Get moving average of rewards for trend analysis"""
        if len(self.current_session_rewards) < window_size:
            return []
        
        moving_averages = []
        for i in range(window_size - 1, len(self.current_session_rewards)):
            window_rewards = [
                event.reward_value 
                for event in self.current_session_rewards[i-window_size+1:i+1]
            ]
            moving_averages.append(sum(window_rewards) / window_size)
        
        return moving_averages
    
    def reset_session(self):
        """Reset current session"""
        self.current_session_rewards.clear()
        self.cumulative_reward = 0.0
        self.session_start_time = time.time() 