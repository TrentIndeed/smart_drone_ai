"""
Curriculum Tracker
Manages progressive learning curriculum, adjusting difficulty based on performance
"""

import json
import time
from typing import Dict, List, Any, Optional
from pathlib import Path
from dataclasses import dataclass
from enum import Enum


class DifficultyLevel(Enum):
    BEGINNER = "beginner"
    EASY = "easy"
    MEDIUM = "medium"
    HARD = "hard"
    EXPERT = "expert"


@dataclass
class CurriculumStage:
    """Single stage in the learning curriculum"""
    stage_id: str
    difficulty: DifficultyLevel
    requirements: Dict[str, float]  # Performance thresholds to advance
    environment_params: Dict[str, Any]
    unlock_conditions: Dict[str, Any]
    mastery_criteria: Dict[str, float]


@dataclass
class PerformanceMetrics:
    """Performance metrics for curriculum advancement"""
    success_rate: float
    average_completion_time: float
    average_final_distance: float
    obstacle_avoidance_rate: float
    efficiency_score: float


class CurriculumTracker:
    """Tracks learning progress and manages curriculum advancement"""
    
    def __init__(self, config_path: str = "ai_core/configs/curriculum.json"):
        self.config_path = Path(config_path)
        self.current_stage = DifficultyLevel.BEGINNER
        self.performance_history: List[Dict[str, Any]] = []
        self.stage_attempts: Dict[str, int] = {}
        self.stage_completions: Dict[str, int] = {}
        
        self.curriculum_stages = self._initialize_curriculum()
        self._load_progress()
    
    def _initialize_curriculum(self) -> Dict[DifficultyLevel, CurriculumStage]:
        """Initialize the learning curriculum stages"""
        return {
            DifficultyLevel.BEGINNER: CurriculumStage(
                stage_id="beginner",
                difficulty=DifficultyLevel.BEGINNER,
                requirements={
                    "success_rate": 0.6,
                    "completion_time": 180.0,  # 3 minutes
                    "final_distance": 10.0
                },
                environment_params={
                    "target_speed": 2.0,
                    "obstacle_density": 0.1,
                    "weather_complexity": 0.0,
                    "terrain_difficulty": 0.2,
                    "target_evasion": 0.1
                },
                unlock_conditions={},
                mastery_criteria={
                    "success_rate": 0.8,
                    "attempts_required": 5
                }
            ),
            
            DifficultyLevel.EASY: CurriculumStage(
                stage_id="easy",
                difficulty=DifficultyLevel.EASY,
                requirements={
                    "success_rate": 0.7,
                    "completion_time": 150.0,
                    "final_distance": 8.0
                },
                environment_params={
                    "target_speed": 3.0,
                    "obstacle_density": 0.2,
                    "weather_complexity": 0.1,
                    "terrain_difficulty": 0.3,
                    "target_evasion": 0.3
                },
                unlock_conditions={
                    "previous_stage_mastered": DifficultyLevel.BEGINNER
                },
                mastery_criteria={
                    "success_rate": 0.8,
                    "attempts_required": 10
                }
            ),
            
            DifficultyLevel.MEDIUM: CurriculumStage(
                stage_id="medium",
                difficulty=DifficultyLevel.MEDIUM,
                requirements={
                    "success_rate": 0.75,
                    "completion_time": 120.0,
                    "final_distance": 6.0
                },
                environment_params={
                    "target_speed": 5.0,
                    "obstacle_density": 0.4,
                    "weather_complexity": 0.3,
                    "terrain_difficulty": 0.5,
                    "target_evasion": 0.5
                },
                unlock_conditions={
                    "previous_stage_mastered": DifficultyLevel.EASY
                },
                mastery_criteria={
                    "success_rate": 0.85,
                    "attempts_required": 15
                }
            ),
            
            DifficultyLevel.HARD: CurriculumStage(
                stage_id="hard",
                difficulty=DifficultyLevel.HARD,
                requirements={
                    "success_rate": 0.8,
                    "completion_time": 90.0,
                    "final_distance": 4.0
                },
                environment_params={
                    "target_speed": 7.0,
                    "obstacle_density": 0.6,
                    "weather_complexity": 0.5,
                    "terrain_difficulty": 0.7,
                    "target_evasion": 0.7
                },
                unlock_conditions={
                    "previous_stage_mastered": DifficultyLevel.MEDIUM
                },
                mastery_criteria={
                    "success_rate": 0.9,
                    "attempts_required": 20
                }
            ),
            
            DifficultyLevel.EXPERT: CurriculumStage(
                stage_id="expert",
                difficulty=DifficultyLevel.EXPERT,
                requirements={
                    "success_rate": 0.85,
                    "completion_time": 60.0,
                    "final_distance": 2.0
                },
                environment_params={
                    "target_speed": 10.0,
                    "obstacle_density": 0.8,
                    "weather_complexity": 0.8,
                    "terrain_difficulty": 0.9,
                    "target_evasion": 0.9
                },
                unlock_conditions={
                    "previous_stage_mastered": DifficultyLevel.HARD
                },
                mastery_criteria={
                    "success_rate": 0.95,
                    "attempts_required": 25
                }
            )
        }
    
    def record_performance(self, 
                         success: bool,
                         completion_time: float,
                         final_distance: float,
                         obstacles_hit: int,
                         total_obstacles: int):
        """Record performance metrics from a mission"""
        
        stage_key = self.current_stage.value
        self.stage_attempts[stage_key] = self.stage_attempts.get(stage_key, 0) + 1
        
        if success:
            self.stage_completions[stage_key] = self.stage_completions.get(stage_key, 0) + 1
        
        performance = {
            "timestamp": time.time(),
            "stage": self.current_stage.value,
            "success": success,
            "completion_time": completion_time,
            "final_distance": final_distance,
            "obstacles_hit": obstacles_hit,
            "total_obstacles": total_obstacles,
            "obstacle_avoidance_rate": 1.0 - (obstacles_hit / max(total_obstacles, 1))
        }
        
        self.performance_history.append(performance)
        self._save_progress()
        
        # Check for stage advancement
        self._check_advancement()
    
    def _check_advancement(self):
        """Check if ready to advance to next difficulty level"""
        current_metrics = self.get_current_stage_metrics()
        current_stage_config = self.curriculum_stages[self.current_stage]
        
        # Check if mastery criteria are met
        if self._meets_mastery_criteria(current_metrics, current_stage_config):
            next_stage = self._get_next_stage()
            if next_stage and self._can_unlock_stage(next_stage):
                self._advance_to_stage(next_stage)
    
    def _meets_mastery_criteria(self, metrics: PerformanceMetrics, stage: CurriculumStage) -> bool:
        """Check if current performance meets mastery criteria"""
        stage_key = self.current_stage.value
        attempts = self.stage_attempts.get(stage_key, 0)
        
        required_attempts = stage.mastery_criteria.get("attempts_required", 5)
        required_success_rate = stage.mastery_criteria.get("success_rate", 0.8)
        
        return (attempts >= required_attempts and 
                metrics.success_rate >= required_success_rate)
    
    def _get_next_stage(self) -> Optional[DifficultyLevel]:
        """Get the next stage in progression"""
        stages = list(DifficultyLevel)
        current_index = stages.index(self.current_stage)
        
        if current_index < len(stages) - 1:
            return stages[current_index + 1]
        return None
    
    def _can_unlock_stage(self, stage: DifficultyLevel) -> bool:
        """Check if a stage can be unlocked based on conditions"""
        stage_config = self.curriculum_stages[stage]
        unlock_conditions = stage_config.unlock_conditions
        
        # Check if previous stage is mastered
        if "previous_stage_mastered" in unlock_conditions:
            previous_stage = unlock_conditions["previous_stage_mastered"]
            if not self._is_stage_mastered(previous_stage):
                return False
        
        return True
    
    def _is_stage_mastered(self, stage: DifficultyLevel) -> bool:
        """Check if a specific stage has been mastered"""
        stage_config = self.curriculum_stages[stage]
        stage_metrics = self.get_stage_metrics(stage)
        
        return self._meets_mastery_criteria(stage_metrics, stage_config)
    
    def _advance_to_stage(self, new_stage: DifficultyLevel):
        """Advance to a new curriculum stage"""
        old_stage = self.current_stage
        self.current_stage = new_stage
        
        print(f"🎓 Curriculum Advanced: {old_stage.value} → {new_stage.value}")
        print(f"New environment parameters: {self.get_current_environment_params()}")
        
        self._save_progress()
    
    def get_current_stage_metrics(self) -> PerformanceMetrics:
        """Get performance metrics for current stage"""
        return self.get_stage_metrics(self.current_stage)
    
    def get_stage_metrics(self, stage: DifficultyLevel) -> PerformanceMetrics:
        """Get performance metrics for a specific stage"""
        stage_performances = [
            p for p in self.performance_history 
            if p["stage"] == stage.value
        ]
        
        if not stage_performances:
            return PerformanceMetrics(0.0, 0.0, 0.0, 0.0, 0.0)
        
        successes = [p for p in stage_performances if p["success"]]
        success_rate = len(successes) / len(stage_performances)
        
        avg_completion_time = sum(p["completion_time"] for p in successes) / max(len(successes), 1)
        avg_final_distance = sum(p["final_distance"] for p in stage_performances) / len(stage_performances)
        avg_obstacle_avoidance = sum(p["obstacle_avoidance_rate"] for p in stage_performances) / len(stage_performances)
        
        # Calculate efficiency score (lower time + distance = higher efficiency)
        efficiency_scores = []
        for p in successes:
            # Normalize time and distance to 0-1 scale for efficiency calculation
            time_score = max(0, 1 - p["completion_time"] / 300)  # 300s max time
            distance_score = max(0, 1 - p["final_distance"] / 50)  # 50m max distance
            efficiency_scores.append((time_score + distance_score) / 2)
        
        avg_efficiency = sum(efficiency_scores) / max(len(efficiency_scores), 1)
        
        return PerformanceMetrics(
            success_rate=success_rate,
            average_completion_time=avg_completion_time,
            average_final_distance=avg_final_distance,
            obstacle_avoidance_rate=avg_obstacle_avoidance,
            efficiency_score=avg_efficiency
        )
    
    def get_current_environment_params(self) -> Dict[str, Any]:
        """Get environment parameters for current stage"""
        return self.curriculum_stages[self.current_stage].environment_params
    
    def get_progress_summary(self) -> Dict[str, Any]:
        """Get detailed progress summary"""
        current_metrics = self.get_current_stage_metrics()
        current_stage_config = self.curriculum_stages[self.current_stage]
        
        return {
            "current_stage": self.current_stage.value,
            "current_metrics": {
                "success_rate": current_metrics.success_rate,
                "average_completion_time": current_metrics.average_completion_time,
                "average_final_distance": current_metrics.average_final_distance,
                "obstacle_avoidance_rate": current_metrics.obstacle_avoidance_rate,
                "efficiency_score": current_metrics.efficiency_score
            },
            "stage_requirements": current_stage_config.requirements,
            "mastery_criteria": current_stage_config.mastery_criteria,
            "attempts_this_stage": self.stage_attempts.get(self.current_stage.value, 0),
            "completions_this_stage": self.stage_completions.get(self.current_stage.value, 0),
            "is_ready_to_advance": self._meets_mastery_criteria(current_metrics, current_stage_config),
            "total_missions": len(self.performance_history)
        }
    
    def _save_progress(self):
        """Save curriculum progress to file"""
        progress_data = {
            "current_stage": self.current_stage.value,
            "stage_attempts": self.stage_attempts,
            "stage_completions": self.stage_completions,
            "performance_history": self.performance_history[-100:]  # Keep last 100 records
        }
        
        self.config_path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.config_path, 'w') as f:
            json.dump(progress_data, f, indent=2)
    
    def _load_progress(self):
        """Load curriculum progress from file"""
        if self.config_path.exists():
            with open(self.config_path, 'r') as f:
                progress_data = json.load(f)
            
            self.current_stage = DifficultyLevel(progress_data.get("current_stage", "beginner"))
            self.stage_attempts = progress_data.get("stage_attempts", {})
            self.stage_completions = progress_data.get("stage_completions", {})
            self.performance_history = progress_data.get("performance_history", []) 