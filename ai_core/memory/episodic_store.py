"""
Episodic Memory Store
Stores and retrieves specific mission episodes for learning and adaptation
"""

import json
import sqlite3
import time
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, asdict
from pathlib import Path


@dataclass
class Episode:
    """Single mission episode with full context"""
    episode_id: str
    mission_type: str
    start_time: float
    end_time: float
    success: bool
    target_position: tuple[float, float, float]
    drone_start_position: tuple[float, float, float]
    final_distance: float
    strategy_used: str
    obstacles_hit: int
    emergency_activations: int
    flight_path: List[tuple[float, float, float]]
    decisions: List[Dict[str, Any]]
    environmental_factors: Dict[str, Any]
    performance_metrics: Dict[str, float]


class EpisodicStore:
    """Manages episodic memory for the drone AI"""
    
    def __init__(self, db_path: str = "ai_core/memory/episodes.db"):
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_database()
    
    def _init_database(self):
        """Initialize SQLite database for episode storage"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('''
                CREATE TABLE IF NOT EXISTS episodes (
                    episode_id TEXT PRIMARY KEY,
                    mission_type TEXT,
                    start_time REAL,
                    end_time REAL,
                    success INTEGER,
                    target_position TEXT,
                    drone_start_position TEXT,
                    final_distance REAL,
                    strategy_used TEXT,
                    obstacles_hit INTEGER,
                    emergency_activations INTEGER,
                    flight_path TEXT,
                    decisions TEXT,
                    environmental_factors TEXT,
                    performance_metrics TEXT
                )
            ''')
            conn.commit()
    
    def store_episode(self, episode: Episode):
        """Store a new episode in memory"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('''
                INSERT OR REPLACE INTO episodes VALUES 
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                episode.episode_id,
                episode.mission_type,
                episode.start_time,
                episode.end_time,
                int(episode.success),
                json.dumps(episode.target_position),
                json.dumps(episode.drone_start_position),
                episode.final_distance,
                episode.strategy_used,
                episode.obstacles_hit,
                episode.emergency_activations,
                json.dumps(episode.flight_path),
                json.dumps(episode.decisions),
                json.dumps(episode.environmental_factors),
                json.dumps(episode.performance_metrics)
            ))
            conn.commit()
    
    def get_episode(self, episode_id: str) -> Optional[Episode]:
        """Retrieve specific episode by ID"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT * FROM episodes WHERE episode_id = ?', (episode_id,))
            row = cursor.fetchone()
            
            if row:
                return self._row_to_episode(row)
            return None
    
    def get_similar_episodes(self, 
                           mission_type: str = None,
                           target_distance_range: tuple[float, float] = None,
                           success_only: bool = False,
                           limit: int = 10) -> List[Episode]:
        """Find episodes similar to current situation"""
        query = "SELECT * FROM episodes WHERE 1=1"
        params = []
        
        if mission_type:
            query += " AND mission_type = ?"
            params.append(mission_type)
        
        if target_distance_range:
            # Calculate distance from drone start to target
            query += " AND final_distance BETWEEN ? AND ?"
            params.extend(target_distance_range)
        
        if success_only:
            query += " AND success = 1"
        
        query += " ORDER BY start_time DESC LIMIT ?"
        params.append(limit)
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(query, params)
            rows = cursor.fetchall()
            
            return [self._row_to_episode(row) for row in rows]
    
    def get_successful_strategies(self, mission_type: str = None) -> Dict[str, int]:
        """Get frequency of successful strategies"""
        query = "SELECT strategy_used, COUNT(*) FROM episodes WHERE success = 1"
        params = []
        
        if mission_type:
            query += " AND mission_type = ?"
            params.append(mission_type)
        
        query += " GROUP BY strategy_used ORDER BY COUNT(*) DESC"
        
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute(query, params)
            rows = cursor.fetchall()
            
            return {strategy: count for strategy, count in rows}
    
    def get_learning_insights(self) -> Dict[str, Any]:
        """Generate insights from stored episodes"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            
            # Success rate by strategy
            cursor.execute('''
                SELECT strategy_used, 
                       AVG(CAST(success AS FLOAT)) as success_rate,
                       COUNT(*) as total_attempts
                FROM episodes 
                GROUP BY strategy_used
            ''')
            strategy_performance = {
                strategy: {"success_rate": rate, "attempts": attempts}
                for strategy, rate, attempts in cursor.fetchall()
            }
            
            # Average performance metrics
            cursor.execute('''
                SELECT AVG(final_distance) as avg_distance,
                       AVG(obstacles_hit) as avg_obstacles,
                       AVG(emergency_activations) as avg_emergencies
                FROM episodes WHERE success = 1
            ''')
            avg_metrics = cursor.fetchone()
            
            return {
                "strategy_performance": strategy_performance,
                "average_successful_metrics": {
                    "final_distance": avg_metrics[0] or 0.0,
                    "obstacles_hit": avg_metrics[1] or 0.0,
                    "emergency_activations": avg_metrics[2] or 0.0
                },
                "total_episodes": self.get_episode_count()
            }
    
    def get_episode_count(self) -> int:
        """Get total number of stored episodes"""
        with sqlite3.connect(self.db_path) as conn:
            cursor = conn.cursor()
            cursor.execute('SELECT COUNT(*) FROM episodes')
            return cursor.fetchone()[0]
    
    def _row_to_episode(self, row) -> Episode:
        """Convert database row to Episode object"""
        return Episode(
            episode_id=row[0],
            mission_type=row[1],
            start_time=row[2],
            end_time=row[3],
            success=bool(row[4]),
            target_position=tuple(json.loads(row[5])),
            drone_start_position=tuple(json.loads(row[6])),
            final_distance=row[7],
            strategy_used=row[8],
            obstacles_hit=row[9],
            emergency_activations=row[10],
            flight_path=json.loads(row[11]),
            decisions=json.loads(row[12]),
            environmental_factors=json.loads(row[13]),
            performance_metrics=json.loads(row[14])
        ) 