"""
Basic Sensor Model
Simulates basic drone sensors with realistic noise and limitations
"""

import numpy as np
import time
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass


@dataclass
class SensorReading:
    """Single sensor reading with metadata"""
    timestamp: float
    sensor_type: str
    value: Any
    confidence: float  # 0.0 to 1.0
    noise_level: float
    valid: bool


class BasicSensorModel:
    """Basic sensor model with configurable noise and failures"""
    
    def __init__(self, sensor_config: Dict[str, Any] = None):
        if sensor_config is None:
            sensor_config = self._default_config()
        
        self.config = sensor_config
        self.last_readings: Dict[str, SensorReading] = {}
        
        # Sensor failure simulation
        self.sensor_failures: Dict[str, bool] = {}
        self.failure_probabilities: Dict[str, float] = {
            "gps": 0.001,      # 0.1% chance per reading
            "imu": 0.0005,     # 0.05% chance
            "altimeter": 0.002, # 0.2% chance
            "camera": 0.01,    # 1% chance
            "lidar": 0.005     # 0.5% chance
        }
        
    def _default_config(self) -> Dict[str, Any]:
        """Default sensor configuration"""
        return {
            "gps": {
                "noise_std": 0.5,      # meters
                "update_rate": 10.0,    # Hz
                "accuracy": 0.3,        # CEP in meters
                "enabled": True
            },
            "imu": {
                "accel_noise_std": 0.1,     # m/s²
                "gyro_noise_std": 0.05,     # rad/s
                "update_rate": 200.0,       # Hz
                "drift_rate": 0.001,        # rad/s per second
                "enabled": True
            },
            "altimeter": {
                "noise_std": 0.1,      # meters
                "update_rate": 50.0,    # Hz
                "range": [0, 200],      # min/max altitude
                "enabled": True
            },
            "camera": {
                "resolution": [640, 480],
                "fov_degrees": 60,
                "update_rate": 30.0,    # Hz
                "detection_range": 50.0, # meters
                "enabled": True
            },
            "lidar": {
                "range": 100.0,        # meters
                "accuracy": 0.05,      # meters
                "angular_resolution": 1.0, # degrees
                "update_rate": 20.0,   # Hz
                "enabled": True
            }
        }
    
    def read_gps(self, true_position: Tuple[float, float, float]) -> SensorReading:
        """Simulate GPS reading with noise and potential failures"""
        
        if self._check_sensor_failure("gps"):
            return SensorReading(
                timestamp=time.time(),
                sensor_type="gps",
                value=None,
                confidence=0.0,
                noise_level=1.0,
                valid=False
            )
        
        config = self.config["gps"]
        noise_std = config["noise_std"]
        
        # Add Gaussian noise to each coordinate
        noise = np.random.normal(0, noise_std, 3)
        noisy_position = np.array(true_position) + noise
        
        # Calculate confidence based on noise level
        noise_magnitude = np.linalg.norm(noise)
        confidence = max(0.1, 1.0 - noise_magnitude / (3 * noise_std))
        
        return SensorReading(
            timestamp=time.time(),
            sensor_type="gps",
            value=tuple(noisy_position),
            confidence=confidence,
            noise_level=noise_magnitude,
            valid=True
        )
    
    def read_imu(self, 
                true_acceleration: Tuple[float, float, float],
                true_angular_velocity: Tuple[float, float, float]) -> Dict[str, SensorReading]:
        """Simulate IMU readings (accelerometer + gyroscope)"""
        
        readings = {}
        
        # Accelerometer
        if not self._check_sensor_failure("imu"):
            config = self.config["imu"]
            accel_noise = np.random.normal(0, config["accel_noise_std"], 3)
            noisy_accel = np.array(true_acceleration) + accel_noise
            
            readings["accelerometer"] = SensorReading(
                timestamp=time.time(),
                sensor_type="accelerometer",
                value=tuple(noisy_accel),
                confidence=0.9,
                noise_level=np.linalg.norm(accel_noise),
                valid=True
            )
            
            # Gyroscope with drift
            gyro_noise = np.random.normal(0, config["gyro_noise_std"], 3)
            drift = np.random.normal(0, config["drift_rate"], 3)
            noisy_gyro = np.array(true_angular_velocity) + gyro_noise + drift
            
            readings["gyroscope"] = SensorReading(
                timestamp=time.time(),
                sensor_type="gyroscope",
                value=tuple(noisy_gyro),
                confidence=0.95,
                noise_level=np.linalg.norm(gyro_noise),
                valid=True
            )
        else:
            # IMU failure - return invalid readings
            readings["accelerometer"] = SensorReading(
                timestamp=time.time(),
                sensor_type="accelerometer",
                value=None,
                confidence=0.0,
                noise_level=1.0,
                valid=False
            )
            
            readings["gyroscope"] = SensorReading(
                timestamp=time.time(),
                sensor_type="gyroscope",
                value=None,
                confidence=0.0,
                noise_level=1.0,
                valid=False
            )
        
        return readings
    
    def read_altimeter(self, true_altitude: float) -> SensorReading:
        """Simulate barometric altimeter reading"""
        
        if self._check_sensor_failure("altimeter"):
            return SensorReading(
                timestamp=time.time(),
                sensor_type="altimeter",
                value=None,
                confidence=0.0,
                noise_level=1.0,
                valid=False
            )
        
        config = self.config["altimeter"]
        noise = np.random.normal(0, config["noise_std"])
        noisy_altitude = true_altitude + noise
        
        # Check if altitude is within sensor range
        alt_range = config["range"]
        if noisy_altitude < alt_range[0] or noisy_altitude > alt_range[1]:
            confidence = 0.1  # Low confidence out of range
        else:
            confidence = max(0.7, 1.0 - abs(noise) / (3 * config["noise_std"]))
        
        return SensorReading(
            timestamp=time.time(),
            sensor_type="altimeter",
            value=noisy_altitude,
            confidence=confidence,
            noise_level=abs(noise),
            valid=True
        )
    
    def read_camera(self, 
                   target_position: Optional[Tuple[float, float, float]],
                   drone_position: Tuple[float, float, float],
                   obstacles: List[Dict[str, Any]]) -> SensorReading:
        """Simulate camera-based target detection"""
        
        if self._check_sensor_failure("camera"):
            return SensorReading(
                timestamp=time.time(),
                sensor_type="camera",
                value=None,
                confidence=0.0,
                noise_level=1.0,
                valid=False
            )
        
        config = self.config["camera"]
        detection_data = {
            "targets_detected": [],
            "obstacles_detected": [],
            "image_quality": 1.0
        }
        
        # Check if target is visible
        if target_position is not None:
            distance = np.linalg.norm(np.array(target_position) - np.array(drone_position))
            
            if distance <= config["detection_range"]:
                # Simulate detection with distance-based confidence
                confidence = max(0.3, 1.0 - distance / config["detection_range"])
                
                # Add noise to detected position
                noise_std = 0.1 * distance  # Noise increases with distance
                noise = np.random.normal(0, noise_std, 3)
                detected_position = np.array(target_position) + noise
                
                detection_data["targets_detected"].append({
                    "position": tuple(detected_position),
                    "confidence": confidence,
                    "distance": distance,
                    "type": "target"
                })
        
        # Detect obstacles in range
        for obstacle in obstacles:
            obs_pos = obstacle.get("position", [0, 0, 0])
            distance = np.linalg.norm(np.array(obs_pos) - np.array(drone_position))
            
            if distance <= config["detection_range"]:
                confidence = max(0.5, 1.0 - distance / config["detection_range"])
                
                detection_data["obstacles_detected"].append({
                    "position": obs_pos,
                    "size": obstacle.get("size", [1, 1, 1]),
                    "confidence": confidence,
                    "distance": distance,
                    "type": obstacle.get("type", "unknown")
                })
        
        # Overall confidence based on detections
        overall_confidence = 0.8 if detection_data["targets_detected"] or detection_data["obstacles_detected"] else 0.3
        
        return SensorReading(
            timestamp=time.time(),
            sensor_type="camera",
            value=detection_data,
            confidence=overall_confidence,
            noise_level=0.1,
            valid=True
        )
    
    def read_lidar(self, 
                  drone_position: Tuple[float, float, float],
                  obstacles: List[Dict[str, Any]]) -> SensorReading:
        """Simulate LiDAR distance measurements"""
        
        if self._check_sensor_failure("lidar"):
            return SensorReading(
                timestamp=time.time(),
                sensor_type="lidar",
                value=None,
                confidence=0.0,
                noise_level=1.0,
                valid=False
            )
        
        config = self.config["lidar"]
        max_range = config["range"]
        accuracy = config["accuracy"]
        
        # Simulate 360-degree scan
        scan_points = []
        angular_resolution = config["angular_resolution"]
        
        for angle_deg in range(0, 360, int(angular_resolution)):
            angle_rad = np.radians(angle_deg)
            
            # Cast ray in this direction
            ray_direction = np.array([np.cos(angle_rad), 0, np.sin(angle_rad)])
            
            # Find closest obstacle in this direction
            min_distance = max_range
            
            for obstacle in obstacles:
                obs_pos = np.array(obstacle.get("position", [0, 0, 0]))
                obs_size = max(obstacle.get("size", [1, 1, 1]))
                
                # Simple ray-sphere intersection
                to_obstacle = obs_pos - np.array(drone_position)
                projection = np.dot(to_obstacle, ray_direction)
                
                if projection > 0:  # Obstacle is in front
                    closest_point = np.array(drone_position) + ray_direction * projection
                    distance_to_closest = np.linalg.norm(closest_point - obs_pos)
                    
                    if distance_to_closest <= obs_size:
                        obstacle_distance = projection - obs_size
                        if obstacle_distance > 0 and obstacle_distance < min_distance:
                            min_distance = obstacle_distance
            
            # Add noise to distance measurement
            noise = np.random.normal(0, accuracy)
            measured_distance = min_distance + noise
            
            scan_points.append({
                "angle": angle_deg,
                "distance": max(0.1, measured_distance),  # Minimum 0.1m
                "valid": measured_distance < max_range
            })
        
        return SensorReading(
            timestamp=time.time(),
            sensor_type="lidar",
            value=scan_points,
            confidence=0.95,
            noise_level=accuracy,
            valid=True
        )
    
    def _check_sensor_failure(self, sensor_type: str) -> bool:
        """Check if sensor has failed"""
        
        # Check if already failed
        if sensor_type in self.sensor_failures:
            if self.sensor_failures[sensor_type]:
                # 10% chance of recovery each reading
                if np.random.random() < 0.1:
                    self.sensor_failures[sensor_type] = False
                    print(f"Sensor {sensor_type} recovered")
                    return False
                return True
        
        # Check for new failure
        failure_prob = self.failure_probabilities.get(sensor_type, 0.0)
        if np.random.random() < failure_prob:
            self.sensor_failures[sensor_type] = True
            print(f"Sensor {sensor_type} failed!")
            return True
        
        return False
    
    def get_sensor_status(self) -> Dict[str, Dict[str, Any]]:
        """Get current status of all sensors"""
        status = {}
        
        for sensor_type in self.config.keys():
            status[sensor_type] = {
                "enabled": self.config[sensor_type]["enabled"],
                "failed": self.sensor_failures.get(sensor_type, False),
                "last_reading": self.last_readings.get(sensor_type, None)
            }
        
        return status
    
    def reset_failures(self):
        """Reset all sensor failures"""
        self.sensor_failures.clear()
        print("All sensor failures cleared")
    
    def simulate_sensor_suite(self,
                            true_state: Dict[str, Any]) -> Dict[str, SensorReading]:
        """Simulate reading from all sensors"""
        
        readings = {}
        
        # GPS
        if "position" in true_state:
            readings["gps"] = self.read_gps(true_state["position"])
        
        # IMU
        if "acceleration" in true_state and "angular_velocity" in true_state:
            imu_readings = self.read_imu(
                true_state["acceleration"],
                true_state["angular_velocity"]
            )
            readings.update(imu_readings)
        
        # Altimeter
        if "altitude" in true_state:
            readings["altimeter"] = self.read_altimeter(true_state["altitude"])
        
        # Camera
        if "target_position" in true_state:
            readings["camera"] = self.read_camera(
                true_state.get("target_position"),
                true_state["position"],
                true_state.get("obstacles", [])
            )
        
        # LiDAR
        if "obstacles" in true_state:
            readings["lidar"] = self.read_lidar(
                true_state["position"],
                true_state["obstacles"]
            )
        
        # Store last readings
        self.last_readings.update(readings)
        
        return readings 