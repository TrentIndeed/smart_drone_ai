"""
Perception Module for System 1 (S1)
Real-time processing of sensor data at 200Hz
"""

import numpy as np
import time
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass
from ai_core.interface.sim_interface import SimulationState, DroneState, TargetState


@dataclass
class PerceptionState:
    """Processed perception data for S1 control"""
    timestamp: float
    drone_position: Tuple[float, float, float]
    drone_velocity: Tuple[float, float, float]
    drone_orientation: Tuple[float, float, float]
    target_position: Optional[Tuple[float, float, float]]
    target_velocity: Optional[Tuple[float, float, float]]
    target_visible: bool
    target_distance: float
    target_bearing: Tuple[float, float]  # azimuth, elevation in radians
    obstacles: List[Dict[str, Any]]
    immediate_threats: List[Dict[str, Any]]
    safe_directions: List[Tuple[float, float]]  # Available flight directions
    battery_level: float
    flight_envelope: Dict[str, Any]  # Current flight constraints


class PerceptionModule:
    """Real-time perception processing for drone AI"""
    
    def __init__(self, update_rate_hz: float = 200.0):
        self.update_rate = update_rate_hz
        self.update_interval = 1.0 / update_rate_hz
        self.last_update = 0.0
        
        # Perception history for filtering and prediction
        self.position_history: List[Tuple[float, Tuple[float, float, float]]] = []
        self.target_history: List[Tuple[float, Tuple[float, float, float]]] = []
        self.velocity_history: List[Tuple[float, Tuple[float, float, float]]] = []
        
        # Kalman filter parameters for smoothing
        self.position_filter = SimpleKalmanFilter()
        self.target_filter = SimpleKalmanFilter()
        
        # Threat detection parameters
        self.collision_lookahead_time = 2.0  # seconds
        self.min_safe_distance = 3.0  # meters
        self.critical_distance = 1.5  # meters
        
    def process_state(self, sim_state: SimulationState) -> PerceptionState:
        """Process raw simulation state into actionable perception data"""
        current_time = time.time()
        
        # Apply filters for noise reduction
        filtered_position = self.position_filter.update(sim_state.drone.position)
        filtered_target_pos = None
        
        if sim_state.target.is_visible:
            filtered_target_pos = self.target_filter.update(sim_state.target.position)
        
        # Calculate derived information
        target_distance, target_bearing = self._calculate_target_info(
            filtered_position, filtered_target_pos
        )
        
        # Detect immediate threats
        immediate_threats = self._detect_immediate_threats(
            filtered_position, sim_state.drone.velocity, sim_state.obstacles
        )
        
        # Calculate safe flight directions
        safe_directions = self._calculate_safe_directions(
            filtered_position, sim_state.obstacles, immediate_threats
        )
        
        # Determine current flight envelope
        flight_envelope = self._calculate_flight_envelope(
            sim_state.drone, sim_state.obstacles
        )
        
        # Update history
        self._update_history(current_time, sim_state)
        
        return PerceptionState(
            timestamp=current_time,
            drone_position=filtered_position,
            drone_velocity=sim_state.drone.velocity,
            drone_orientation=sim_state.drone.orientation,
            target_position=filtered_target_pos,
            target_velocity=sim_state.target.velocity if sim_state.target.is_visible else None,
            target_visible=sim_state.target.is_visible,
            target_distance=target_distance,
            target_bearing=target_bearing,
            obstacles=sim_state.obstacles,
            immediate_threats=immediate_threats,
            safe_directions=safe_directions,
            battery_level=sim_state.drone.battery_level,
            flight_envelope=flight_envelope
        )
    
    def _calculate_target_info(self, 
                             drone_pos: Tuple[float, float, float],
                             target_pos: Optional[Tuple[float, float, float]]) -> Tuple[float, Tuple[float, float]]:
        """Calculate distance and bearing to target"""
        if target_pos is None:
            return float('inf'), (0.0, 0.0)
        
        # Calculate 3D distance
        dx = target_pos[0] - drone_pos[0]
        dy = target_pos[1] - drone_pos[1]
        dz = target_pos[2] - drone_pos[2]
        
        distance = np.sqrt(dx**2 + dy**2 + dz**2)
        
        # Calculate bearing (azimuth and elevation)
        horizontal_distance = np.sqrt(dx**2 + dz**2)
        azimuth = np.arctan2(dz, dx)  # Angle in horizontal plane
        elevation = np.arctan2(dy, horizontal_distance)  # Vertical angle
        
        return distance, (azimuth, elevation)
    
    def _detect_immediate_threats(self, 
                                drone_pos: Tuple[float, float, float],
                                drone_vel: Tuple[float, float, float],
                                obstacles: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """Detect obstacles that pose immediate collision risk"""
        threats = []
        
        for obstacle in obstacles:
            threat_info = self._analyze_collision_risk(drone_pos, drone_vel, obstacle)
            if threat_info["is_threat"]:
                threats.append(threat_info)
        
        # Sort by urgency (time to collision)
        threats.sort(key=lambda x: x["time_to_collision"])
        
        return threats
    
    def _analyze_collision_risk(self, 
                              drone_pos: Tuple[float, float, float],
                              drone_vel: Tuple[float, float, float],
                              obstacle: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze collision risk with a specific obstacle"""
        obs_pos = obstacle.get("position", [0, 0, 0])
        obs_size = obstacle.get("size", [1, 1, 1])
        obs_vel = obstacle.get("velocity", [0, 0, 0])
        
        # Calculate relative position and velocity
        rel_pos = np.array(obs_pos) - np.array(drone_pos)
        rel_vel = np.array(obs_vel) - np.array(drone_vel)
        
        # Calculate closest approach
        if np.linalg.norm(rel_vel) < 0.001:  # Stationary relative motion
            closest_distance = np.linalg.norm(rel_pos)
            time_to_collision = float('inf')
        else:
            # Time when relative distance is minimized
            t_closest = -np.dot(rel_pos, rel_vel) / np.dot(rel_vel, rel_vel)
            t_closest = max(0, t_closest)  # Only consider future times
            
            # Position at closest approach
            closest_pos = rel_pos + rel_vel * t_closest
            closest_distance = np.linalg.norm(closest_pos)
            time_to_collision = t_closest if closest_distance < max(obs_size) else float('inf')
        
        # Determine threat level
        safe_distance = max(obs_size) + self.min_safe_distance
        is_threat = (closest_distance < safe_distance and 
                    time_to_collision < self.collision_lookahead_time)
        
        urgency = "critical" if closest_distance < self.critical_distance else "warning"
        
        return {
            "obstacle": obstacle,
            "is_threat": is_threat,
            "closest_distance": closest_distance,
            "time_to_collision": time_to_collision,
            "urgency": urgency,
            "avoidance_vector": self._calculate_avoidance_vector(rel_pos, obs_size)
        }
    
    def _calculate_avoidance_vector(self, 
                                  rel_pos: np.ndarray, 
                                  obs_size: List[float]) -> Tuple[float, float, float]:
        """Calculate recommended avoidance direction"""
        if np.linalg.norm(rel_pos) < 0.001:
            # If too close, move up as default
            return (0.0, 1.0, 0.0)
        
        # Normalize relative position and add safety margin
        avoidance_dir = -rel_pos / np.linalg.norm(rel_pos)
        safety_margin = max(obs_size) + self.min_safe_distance
        avoidance_vector = avoidance_dir * safety_margin
        
        return tuple(avoidance_vector)
    
    def _calculate_safe_directions(self, 
                                 drone_pos: Tuple[float, float, float],
                                 obstacles: List[Dict[str, Any]],
                                 threats: List[Dict[str, Any]]) -> List[Tuple[float, float]]:
        """Calculate available safe flight directions"""
        safe_directions = []
        
        # Sample directions in spherical coordinates
        azimuth_samples = np.linspace(0, 2*np.pi, 16)  # 16 directions horizontally
        elevation_samples = np.linspace(-np.pi/4, np.pi/4, 5)  # 5 elevations
        
        for azimuth in azimuth_samples:
            for elevation in elevation_samples:
                direction = (azimuth, elevation)
                if self._is_direction_safe(drone_pos, direction, obstacles, threats):
                    safe_directions.append(direction)
        
        return safe_directions
    
    def _is_direction_safe(self, 
                         drone_pos: Tuple[float, float, float],
                         direction: Tuple[float, float],
                         obstacles: List[Dict[str, Any]],
                         threats: List[Dict[str, Any]]) -> bool:
        """Check if a flight direction is safe"""
        azimuth, elevation = direction
        
        # Convert to unit vector
        dir_vector = np.array([
            np.cos(elevation) * np.cos(azimuth),
            np.sin(elevation),
            np.cos(elevation) * np.sin(azimuth)
        ])
        
        # Check for obstacles in this direction within safety distance
        check_distance = 10.0  # meters
        check_pos = np.array(drone_pos) + dir_vector * check_distance
        
        for obstacle in obstacles:
            obs_pos = np.array(obstacle.get("position", [0, 0, 0]))
            obs_size = max(obstacle.get("size", [1, 1, 1]))
            
            # Distance from check position to obstacle
            distance = np.linalg.norm(check_pos - obs_pos)
            if distance < obs_size + self.min_safe_distance:
                return False
        
        return True
    
    def _calculate_flight_envelope(self, 
                                 drone_state: DroneState,
                                 obstacles: List[Dict[str, Any]]) -> Dict[str, Any]:
        """Calculate current flight performance envelope"""
        return {
            "max_speed": 15.0,  # m/s
            "max_acceleration": 8.0,  # m/s²
            "max_climb_rate": 5.0,  # m/s
            "max_descent_rate": 3.0,  # m/s
            "max_bank_angle": 45.0,  # degrees
            "battery_limit_factor": drone_state.battery_level / 100.0,
            "altitude_limits": [1.0, 100.0],  # min/max altitude
            "emergency_reserves": drone_state.battery_level > 20.0
        }
    
    def _update_history(self, timestamp: float, sim_state: SimulationState):
        """Update perception history for filtering and prediction"""
        max_history_size = 50  # Keep last 50 samples
        
        # Update position history
        self.position_history.append((timestamp, sim_state.drone.position))
        if len(self.position_history) > max_history_size:
            self.position_history.pop(0)
        
        # Update target history if visible
        if sim_state.target.is_visible:
            self.target_history.append((timestamp, sim_state.target.position))
            if len(self.target_history) > max_history_size:
                self.target_history.pop(0)
        
        # Update velocity history
        self.velocity_history.append((timestamp, sim_state.drone.velocity))
        if len(self.velocity_history) > max_history_size:
            self.velocity_history.pop(0)
    
    def predict_target_position(self, prediction_time: float) -> Optional[Tuple[float, float, float]]:
        """Predict target position at future time"""
        if len(self.target_history) < 3:
            return None
        
        # Simple linear prediction based on recent velocity
        recent_positions = self.target_history[-3:]
        
        # Calculate average velocity from recent positions
        velocities = []
        for i in range(1, len(recent_positions)):
            dt = recent_positions[i][0] - recent_positions[i-1][0]
            if dt > 0:
                vel = np.array(recent_positions[i][1]) - np.array(recent_positions[i-1][1])
                vel = vel / dt
                velocities.append(vel)
        
        if not velocities:
            return self.target_history[-1][1]
        
        avg_velocity = np.mean(velocities, axis=0)
        current_pos = np.array(self.target_history[-1][1])
        predicted_pos = current_pos + avg_velocity * prediction_time
        
        return tuple(predicted_pos)


class SimpleKalmanFilter:
    """Simple 1D Kalman filter for position smoothing"""
    
    def __init__(self, process_noise=0.1, measurement_noise=0.5):
        self.process_noise = process_noise
        self.measurement_noise = measurement_noise
        self.estimate = None
        self.estimate_error = 1.0
    
    def update(self, measurement: Tuple[float, float, float]) -> Tuple[float, float, float]:
        """Update filter with new measurement"""
        if self.estimate is None:
            self.estimate = np.array(measurement)
            return measurement
        
        # Predict step
        predicted_estimate = self.estimate
        predicted_error = self.estimate_error + self.process_noise
        
        # Update step
        kalman_gain = predicted_error / (predicted_error + self.measurement_noise)
        self.estimate = predicted_estimate + kalman_gain * (np.array(measurement) - predicted_estimate)
        self.estimate_error = (1 - kalman_gain) * predicted_error
        
        return tuple(self.estimate) 