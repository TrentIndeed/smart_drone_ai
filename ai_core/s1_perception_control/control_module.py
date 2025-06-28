"""
Control Module for System 1 (S1)
Real-time execution of drone commands at 200Hz
"""

import numpy as np
import time
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
from .perception_module import PerceptionState


class ControlMode(Enum):
    MANUAL = "manual"
    WAYPOINT = "waypoint"
    INTERCEPT = "intercept"
    AVOID = "avoid"
    EMERGENCY = "emergency"
    HOVER = "hover"


@dataclass
class ControlCommand:
    """Command from S2 planner to S1 control"""
    command_id: str
    timestamp: float
    mode: ControlMode
    target_position: Optional[Tuple[float, float, float]]
    target_velocity: Optional[Tuple[float, float, float]]
    duration_ms: int
    urgency: str  # "low", "medium", "high", "critical"
    parameters: Dict[str, Any]


@dataclass
class DroneCommand:
    """Low-level command to send to drone"""
    timestamp: float
    thrust: float  # 0.0 to 1.0
    pitch: float   # -1.0 to 1.0 (nose down/up)
    roll: float    # -1.0 to 1.0 (left/right)
    yaw: float     # -1.0 to 1.0 (left/right rotation)
    mode_flags: Dict[str, bool]


class ControlModule:
    """Real-time control execution for drone AI"""
    
    def __init__(self, update_rate_hz: float = 200.0):
        self.update_rate = update_rate_hz
        self.update_interval = 1.0 / update_rate_hz
        
        # Current control state
        self.current_command: Optional[ControlCommand] = None
        self.current_mode = ControlMode.HOVER
        self.command_start_time = 0.0
        
        # PID controllers for position control
        self.position_controller = PIDController3D(
            kp=[2.0, 2.0, 2.0],  # Proportional gains for X, Y, Z
            ki=[0.1, 0.1, 0.1],  # Integral gains
            kd=[0.5, 0.5, 0.5]   # Derivative gains
        )
        
        # PID controllers for orientation
        self.orientation_controller = PIDController3D(
            kp=[3.0, 3.0, 1.5],  # Pitch, Roll, Yaw
            ki=[0.1, 0.1, 0.05],
            kd=[0.8, 0.8, 0.3]
        )
        
        # Safety limits
        self.max_tilt_angle = 45.0  # degrees
        self.max_thrust = 0.8  # Maximum thrust (0.0-1.0)
        self.min_altitude = 1.0  # meters
        self.max_altitude = 100.0  # meters
        
        # Emergency state
        self.emergency_mode = False
        self.emergency_reason = ""
        
        # Control history for analysis
        self.control_history: List[Dict[str, Any]] = []
        
    def execute_command(self, 
                       command: ControlCommand, 
                       perception: PerceptionState) -> DroneCommand:
        """Execute a high-level command from S2 planner"""
        
        # Update current command if new one received
        if (self.current_command is None or 
            command.command_id != self.current_command.command_id):
            self.current_command = command
            self.command_start_time = time.time()
            self.current_mode = command.mode
            
        # Check for emergency conditions
        self._check_emergency_conditions(perception)
        
        # Execute based on current mode
        if self.emergency_mode:
            drone_cmd = self._execute_emergency_control(perception)
        elif self.current_mode == ControlMode.HOVER:
            drone_cmd = self._execute_hover_control(perception)
        elif self.current_mode == ControlMode.WAYPOINT:
            drone_cmd = self._execute_waypoint_control(command, perception)
        elif self.current_mode == ControlMode.INTERCEPT:
            drone_cmd = self._execute_intercept_control(command, perception)
        elif self.current_mode == ControlMode.AVOID:
            drone_cmd = self._execute_avoidance_control(command, perception)
        else:
            drone_cmd = self._execute_hover_control(perception)
        
        # Apply safety limits
        drone_cmd = self._apply_safety_limits(drone_cmd, perception)
        
        # Log control action
        self._log_control_action(command, perception, drone_cmd)
        
        return drone_cmd
    
    def _check_emergency_conditions(self, perception: PerceptionState):
        """Check for conditions requiring emergency response"""
        
        # Low battery emergency
        if perception.battery_level < 15.0:
            self._trigger_emergency("Low battery")
            return
        
        # Immediate collision threat
        for threat in perception.immediate_threats:
            if threat["urgency"] == "critical":
                self._trigger_emergency(f"Collision threat: {threat['time_to_collision']:.1f}s")
                return
        
        # Altitude limits
        if perception.drone_position[1] < self.min_altitude:
            self._trigger_emergency("Below minimum altitude")
            return
        elif perception.drone_position[1] > self.max_altitude:
            self._trigger_emergency("Above maximum altitude")
            return
        
        # If no emergency conditions, clear emergency mode
        if self.emergency_mode:
            self.emergency_mode = False
            self.emergency_reason = ""
            print("Emergency mode cleared")
    
    def _trigger_emergency(self, reason: str):
        """Trigger emergency mode"""
        if not self.emergency_mode:
            self.emergency_mode = True
            self.emergency_reason = reason
            print(f"🚨 EMERGENCY: {reason}")
    
    def _execute_emergency_control(self, perception: PerceptionState) -> DroneCommand:
        """Execute emergency control (priority: safety landing)"""
        
        # Emergency landing - controlled descent
        current_pos = np.array(perception.drone_position)
        
        # Find safe landing spot (for now, just descend in place)
        target_pos = current_pos.copy()
        target_pos[1] = max(0.5, current_pos[1] - 1.0)  # Descend 1m but not below 0.5m
        
        # Calculate control inputs for emergency descent
        position_error = target_pos - current_pos
        control_output = self.position_controller.update(position_error, self.update_interval)
        
        return DroneCommand(
            timestamp=time.time(),
            thrust=max(0.3, min(0.6, 0.5 + control_output[1])),  # Controlled descent
            pitch=np.clip(control_output[0] * 0.1, -0.3, 0.3),  # Limited movement
            roll=np.clip(control_output[2] * 0.1, -0.3, 0.3),
            yaw=0.0,  # No yaw in emergency
            mode_flags={"emergency": True, "landing": True}
        )
    
    def _execute_hover_control(self, perception: PerceptionState) -> DroneCommand:
        """Execute hover control - maintain current position"""
        
        current_pos = np.array(perception.drone_position)
        
        # If no target set, hover at current position
        if not hasattr(self, 'hover_target'):
            self.hover_target = current_pos.copy()
        
        position_error = self.hover_target - current_pos
        control_output = self.position_controller.update(position_error, self.update_interval)
        
        return DroneCommand(
            timestamp=time.time(),
            thrust=np.clip(0.5 + control_output[1], 0.0, 1.0),
            pitch=np.clip(control_output[0], -0.5, 0.5),
            roll=np.clip(control_output[2], -0.5, 0.5),
            yaw=0.0,
            mode_flags={"hover": True}
        )
    
    def _execute_waypoint_control(self, 
                                command: ControlCommand, 
                                perception: PerceptionState) -> DroneCommand:
        """Execute waypoint navigation"""
        
        if command.target_position is None:
            return self._execute_hover_control(perception)
        
        current_pos = np.array(perception.drone_position)
        target_pos = np.array(command.target_position)
        
        # Calculate position error
        position_error = target_pos - current_pos
        distance = np.linalg.norm(position_error)
        
        # Slow down as we approach target
        speed_factor = min(1.0, distance / 5.0)  # Slow down within 5m
        
        control_output = self.position_controller.update(position_error, self.update_interval)
        control_output *= speed_factor
        
        return DroneCommand(
            timestamp=time.time(),
            thrust=np.clip(0.5 + control_output[1], 0.0, 1.0),
            pitch=np.clip(control_output[0], -0.7, 0.7),
            roll=np.clip(control_output[2], -0.7, 0.7),
            yaw=0.0,
            mode_flags={"waypoint": True}
        )
    
    def _execute_intercept_control(self, 
                                 command: ControlCommand, 
                                 perception: PerceptionState) -> DroneCommand:
        """Execute target intercept maneuver"""
        
        if perception.target_position is None:
            return self._execute_hover_control(perception)
        
        current_pos = np.array(perception.drone_position)
        target_pos = np.array(perception.target_position)
        
        # Predictive intercept - lead the target
        if perception.target_velocity is not None:
            target_vel = np.array(perception.target_velocity)
            intercept_time = self._calculate_intercept_time(current_pos, target_pos, target_vel)
            predicted_target_pos = target_pos + target_vel * intercept_time
        else:
            predicted_target_pos = target_pos
        
        # Calculate intercept vector
        intercept_vector = predicted_target_pos - current_pos
        distance = np.linalg.norm(intercept_vector)
        
        # Aggressive pursuit mode
        pursuit_factor = min(2.0, distance / 10.0)  # More aggressive at distance
        
        control_output = self.position_controller.update(intercept_vector, self.update_interval)
        control_output *= pursuit_factor
        
        return DroneCommand(
            timestamp=time.time(),
            thrust=np.clip(0.5 + control_output[1], 0.0, self.max_thrust),
            pitch=np.clip(control_output[0], -0.8, 0.8),
            roll=np.clip(control_output[2], -0.8, 0.8),
            yaw=0.0,
            mode_flags={"intercept": True, "aggressive": True}
        )
    
    def _execute_avoidance_control(self, 
                                 command: ControlCommand, 
                                 perception: PerceptionState) -> DroneCommand:
        """Execute obstacle avoidance maneuver"""
        
        current_pos = np.array(perception.drone_position)
        
        # Calculate avoidance vector from immediate threats
        avoidance_vector = np.zeros(3)
        total_weight = 0.0
        
        for threat in perception.immediate_threats:
            threat_weight = 1.0 / max(0.1, threat["time_to_collision"])
            avoidance_dir = np.array(threat["avoidance_vector"])
            avoidance_vector += avoidance_dir * threat_weight
            total_weight += threat_weight
        
        if total_weight > 0:
            avoidance_vector /= total_weight
        
        # If we have a safe direction from perception, use it
        if perception.safe_directions:
            # Choose the safe direction closest to our avoidance vector
            best_direction = self._choose_best_safe_direction(
                avoidance_vector, perception.safe_directions
            )
            
            # Convert spherical to cartesian
            azimuth, elevation = best_direction
            safe_vector = np.array([
                np.cos(elevation) * np.cos(azimuth) * 5.0,  # 5m in safe direction
                np.sin(elevation) * 5.0,
                np.cos(elevation) * np.sin(azimuth) * 5.0
            ])
            
            target_pos = current_pos + safe_vector
        else:
            # Emergency avoidance - move up and away
            target_pos = current_pos + np.array([0, 5, 0]) + avoidance_vector
        
        position_error = target_pos - current_pos
        control_output = self.position_controller.update(position_error, self.update_interval)
        
        return DroneCommand(
            timestamp=time.time(),
            thrust=np.clip(0.5 + control_output[1], 0.3, 1.0),  # Minimum thrust for escape
            pitch=np.clip(control_output[0], -1.0, 1.0),  # Full authority for avoidance
            roll=np.clip(control_output[2], -1.0, 1.0),
            yaw=0.0,
            mode_flags={"avoid": True, "emergency_maneuver": True}
        )
    
    def _calculate_intercept_time(self, 
                                drone_pos: np.ndarray, 
                                target_pos: np.ndarray, 
                                target_vel: np.ndarray) -> float:
        """Calculate optimal intercept time"""
        
        relative_pos = target_pos - drone_pos
        drone_speed = 10.0  # Assumed drone speed in m/s
        
        # Solve intercept triangle
        a = np.dot(target_vel, target_vel) - drone_speed**2
        b = 2 * np.dot(relative_pos, target_vel)
        c = np.dot(relative_pos, relative_pos)
        
        discriminant = b**2 - 4*a*c
        
        if discriminant < 0 or abs(a) < 0.001:
            # No intercept possible or target stationary
            return np.linalg.norm(relative_pos) / drone_speed
        
        # Choose the positive root
        t1 = (-b + np.sqrt(discriminant)) / (2*a)
        t2 = (-b - np.sqrt(discriminant)) / (2*a)
        
        intercept_time = t1 if t1 > 0 else t2
        return max(0.1, intercept_time)  # Minimum 0.1s
    
    def _choose_best_safe_direction(self, 
                                  desired_vector: np.ndarray, 
                                  safe_directions: List[Tuple[float, float]]) -> Tuple[float, float]:
        """Choose the safe direction closest to desired avoidance vector"""
        
        if not safe_directions:
            return (0.0, 0.0)  # Default direction
        
        # Convert desired vector to spherical
        desired_azimuth = np.arctan2(desired_vector[2], desired_vector[0])
        desired_elevation = np.arctan2(desired_vector[1], 
                                     np.sqrt(desired_vector[0]**2 + desired_vector[2]**2))
        
        # Find closest safe direction
        best_direction = safe_directions[0]
        best_distance = float('inf')
        
        for direction in safe_directions:
            azimuth, elevation = direction
            
            # Calculate angular distance
            azimuth_diff = abs(azimuth - desired_azimuth)
            elevation_diff = abs(elevation - desired_elevation)
            
            # Wrap azimuth difference
            azimuth_diff = min(azimuth_diff, 2*np.pi - azimuth_diff)
            
            angular_distance = np.sqrt(azimuth_diff**2 + elevation_diff**2)
            
            if angular_distance < best_distance:
                best_distance = angular_distance
                best_direction = direction
        
        return best_direction
    
    def _apply_safety_limits(self, 
                           command: DroneCommand, 
                           perception: PerceptionState) -> DroneCommand:
        """Apply safety limits to control commands"""
        
        # Limit thrust
        command.thrust = np.clip(command.thrust, 0.0, self.max_thrust)
        
        # Limit tilt angles (convert to radians for calculation)
        max_tilt_rad = np.radians(self.max_tilt_angle)
        command.pitch = np.clip(command.pitch, -max_tilt_rad, max_tilt_rad)
        command.roll = np.clip(command.roll, -max_tilt_rad, max_tilt_rad)
        
        # Limit yaw rate
        command.yaw = np.clip(command.yaw, -1.0, 1.0)
        
        # Emergency altitude limits
        current_altitude = perception.drone_position[1]
        if current_altitude < self.min_altitude and command.thrust < 0.6:
            command.thrust = 0.6  # Force climb
            command.pitch = max(command.pitch, 0.0)  # No nose down at low altitude
        
        return command
    
    def _log_control_action(self, 
                          command: ControlCommand, 
                          perception: PerceptionState, 
                          drone_cmd: DroneCommand):
        """Log control action for analysis"""
        
        log_entry = {
            "timestamp": time.time(),
            "mode": self.current_mode.value,
            "emergency": self.emergency_mode,
            "command": {
                "thrust": drone_cmd.thrust,
                "pitch": drone_cmd.pitch,
                "roll": drone_cmd.roll,
                "yaw": drone_cmd.yaw
            },
            "state": {
                "position": perception.drone_position,
                "target_distance": perception.target_distance,
                "battery": perception.battery_level,
                "threats": len(perception.immediate_threats)
            }
        }
        
        self.control_history.append(log_entry)
        
        # Keep only recent history
        if len(self.control_history) > 1000:
            self.control_history = self.control_history[-500:]


class PIDController3D:
    """3D PID controller for position/orientation control"""
    
    def __init__(self, kp: List[float], ki: List[float], kd: List[float]):
        self.kp = np.array(kp)
        self.ki = np.array(ki)
        self.kd = np.array(kd)
        
        self.prev_error = np.zeros(3)
        self.integral = np.zeros(3)
        self.last_time = time.time()
    
    def update(self, error: np.ndarray, dt: float) -> np.ndarray:
        """Update PID controller with new error"""
        
        # Proportional term
        p_term = self.kp * error
        
        # Integral term
        self.integral += error * dt
        i_term = self.ki * self.integral
        
        # Derivative term
        derivative = (error - self.prev_error) / max(dt, 0.001)
        d_term = self.kd * derivative
        
        # Update for next iteration
        self.prev_error = error.copy()
        
        # Combine terms
        output = p_term + i_term + d_term
        
        return output
    
    def reset(self):
        """Reset controller state"""
        self.prev_error = np.zeros(3)
        self.integral = np.zeros(3) 