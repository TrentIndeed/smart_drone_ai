"""
Shared Data Schemas
Common data structures and validation schemas used across S1 and S2 systems
"""

from typing import Dict, List, Any, Optional, Union, Tuple
from dataclasses import dataclass, field
from enum import Enum
import time


class MessageType(Enum):
    """Types of messages exchanged between systems"""
    STATE_UPDATE = "state_update"
    COMMAND = "command"
    STATUS = "status"
    ERROR = "error"
    HEARTBEAT = "heartbeat"
    MISSION_UPDATE = "mission_update"


class CommandType(Enum):
    """Types of commands from S2 to S1"""
    HOVER = "hover"
    WAYPOINT = "waypoint"
    INTERCEPT = "intercept"
    AVOID = "avoid"
    EMERGENCY = "emergency"
    LAND = "land"
    RETURN_HOME = "return_home"


class SystemStatus(Enum):
    """System operational status"""
    INITIALIZING = "initializing"
    READY = "ready"
    ACTIVE = "active"
    WARNING = "warning"
    ERROR = "error"
    EMERGENCY = "emergency"
    SHUTDOWN = "shutdown"


class UrgencyLevel(Enum):
    """Command urgency levels"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class Position3D:
    """3D position with optional uncertainty"""
    x: float
    y: float
    z: float
    uncertainty: Optional[float] = None
    timestamp: Optional[float] = None
    
    def to_tuple(self) -> Tuple[float, float, float]:
        return (self.x, self.y, self.z)
    
    def distance_to(self, other: 'Position3D') -> float:
        """Calculate Euclidean distance to another position"""
        dx = self.x - other.x
        dy = self.y - other.y
        dz = self.z - other.z
        return (dx**2 + dy**2 + dz**2)**0.5


@dataclass
class Velocity3D:
    """3D velocity vector"""
    x: float
    y: float
    z: float
    timestamp: Optional[float] = None
    
    def to_tuple(self) -> Tuple[float, float, float]:
        return (self.x, self.y, self.z)
    
    def magnitude(self) -> float:
        """Calculate velocity magnitude"""
        return (self.x**2 + self.y**2 + self.z**2)**0.5


@dataclass
class Orientation3D:
    """3D orientation (pitch, roll, yaw)"""
    pitch: float  # radians
    roll: float   # radians
    yaw: float    # radians
    timestamp: Optional[float] = None
    
    def to_tuple(self) -> Tuple[float, float, float]:
        return (self.pitch, self.roll, self.yaw)


@dataclass
class DroneState:
    """Complete drone state information"""
    position: Position3D
    velocity: Velocity3D
    orientation: Orientation3D
    battery_level: float  # 0.0 to 100.0
    is_armed: bool
    flight_mode: str
    system_status: SystemStatus
    timestamp: float = field(default_factory=time.time)
    
    # Optional sensor health
    sensor_health: Optional[Dict[str, float]] = None
    
    # Optional performance metrics
    cpu_usage: Optional[float] = None
    memory_usage: Optional[float] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "position": {
                "x": self.position.x,
                "y": self.position.y,
                "z": self.position.z,
                "uncertainty": self.position.uncertainty
            },
            "velocity": {
                "x": self.velocity.x,
                "y": self.velocity.y,
                "z": self.velocity.z
            },
            "orientation": {
                "pitch": self.orientation.pitch,
                "roll": self.orientation.roll,
                "yaw": self.orientation.yaw
            },
            "battery_level": self.battery_level,
            "is_armed": self.is_armed,
            "flight_mode": self.flight_mode,
            "system_status": self.system_status.value,
            "timestamp": self.timestamp,
            "sensor_health": self.sensor_health,
            "cpu_usage": self.cpu_usage,
            "memory_usage": self.memory_usage
        }


@dataclass
class TargetState:
    """Target state information"""
    position: Position3D
    velocity: Velocity3D
    is_visible: bool
    confidence: float  # 0.0 to 1.0
    target_type: str
    size_estimate: Optional[Tuple[float, float, float]] = None
    timestamp: float = field(default_factory=time.time)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "position": {
                "x": self.position.x,
                "y": self.position.y,
                "z": self.position.z
            },
            "velocity": {
                "x": self.velocity.x,
                "y": self.velocity.y,
                "z": self.velocity.z
            },
            "is_visible": self.is_visible,
            "confidence": self.confidence,
            "target_type": self.target_type,
            "size_estimate": self.size_estimate,
            "timestamp": self.timestamp
        }


@dataclass
class Obstacle:
    """Obstacle information"""
    position: Position3D
    size: Tuple[float, float, float]  # width, height, depth
    obstacle_type: str
    is_static: bool
    velocity: Optional[Velocity3D] = None
    confidence: float = 1.0
    timestamp: float = field(default_factory=time.time)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        result = {
            "position": {
                "x": self.position.x,
                "y": self.position.y,
                "z": self.position.z
            },
            "size": self.size,
            "obstacle_type": self.obstacle_type,
            "is_static": self.is_static,
            "confidence": self.confidence,
            "timestamp": self.timestamp
        }
        
        if self.velocity:
            result["velocity"] = {
                "x": self.velocity.x,
                "y": self.velocity.y,
                "z": self.velocity.z
            }
        
        return result


@dataclass
class Command:
    """Command from S2 to S1"""
    command_id: str
    command_type: CommandType
    urgency: UrgencyLevel
    timestamp: float = field(default_factory=time.time)
    
    # Command-specific parameters
    target_position: Optional[Position3D] = None
    target_velocity: Optional[Velocity3D] = None
    duration_ms: Optional[int] = None
    parameters: Dict[str, Any] = field(default_factory=dict)
    
    # Metadata
    source: str = "S2"
    sequence_number: Optional[int] = None
    parent_command_id: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        result = {
            "command_id": self.command_id,
            "command_type": self.command_type.value,
            "urgency": self.urgency.value,
            "timestamp": self.timestamp,
            "duration_ms": self.duration_ms,
            "parameters": self.parameters,
            "source": self.source,
            "sequence_number": self.sequence_number,
            "parent_command_id": self.parent_command_id
        }
        
        if self.target_position:
            result["target_position"] = {
                "x": self.target_position.x,
                "y": self.target_position.y,
                "z": self.target_position.z
            }
        
        if self.target_velocity:
            result["target_velocity"] = {
                "x": self.target_velocity.x,
                "y": self.target_velocity.y,
                "z": self.target_velocity.z
            }
        
        return result


@dataclass
class SystemMessage:
    """Generic system message"""
    message_id: str
    message_type: MessageType
    source: str
    destination: str
    payload: Dict[str, Any]
    timestamp: float = field(default_factory=time.time)
    
    # Optional fields
    correlation_id: Optional[str] = None
    reply_to: Optional[str] = None
    ttl: Optional[float] = None  # Time to live in seconds
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "message_id": self.message_id,
            "message_type": self.message_type.value,
            "source": self.source,
            "destination": self.destination,
            "payload": self.payload,
            "timestamp": self.timestamp,
            "correlation_id": self.correlation_id,
            "reply_to": self.reply_to,
            "ttl": self.ttl
        }


@dataclass
class PerformanceMetrics:
    """Performance metrics for monitoring and evaluation"""
    timestamp: float = field(default_factory=time.time)
    
    # Mission metrics
    mission_time: float = 0.0
    target_distance: Optional[float] = None
    success_probability: float = 0.0
    
    # Flight metrics
    distance_traveled: float = 0.0
    average_speed: float = 0.0
    energy_consumed: float = 0.0
    
    # Safety metrics
    obstacles_detected: int = 0
    near_misses: int = 0
    emergency_activations: int = 0
    
    # System metrics
    cpu_usage: float = 0.0
    memory_usage: float = 0.0
    communication_latency: float = 0.0
    
    # Decision metrics
    strategy_changes: int = 0
    commands_issued: int = 0
    planning_time: float = 0.0
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "timestamp": self.timestamp,
            "mission_time": self.mission_time,
            "target_distance": self.target_distance,
            "success_probability": self.success_probability,
            "distance_traveled": self.distance_traveled,
            "average_speed": self.average_speed,
            "energy_consumed": self.energy_consumed,
            "obstacles_detected": self.obstacles_detected,
            "near_misses": self.near_misses,
            "emergency_activations": self.emergency_activations,
            "cpu_usage": self.cpu_usage,
            "memory_usage": self.memory_usage,
            "communication_latency": self.communication_latency,
            "strategy_changes": self.strategy_changes,
            "commands_issued": self.commands_issued,
            "planning_time": self.planning_time
        }


@dataclass
class MissionStatus:
    """Current mission status"""
    mission_id: str
    status: str  # "planning", "active", "completed", "failed", "aborted"
    start_time: float
    current_objective: str
    objectives_completed: List[str]
    success_probability: float
    estimated_completion_time: Optional[float] = None
    failure_reason: Optional[str] = None
    timestamp: float = field(default_factory=time.time)
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary for serialization"""
        return {
            "mission_id": self.mission_id,
            "status": self.status,
            "start_time": self.start_time,
            "current_objective": self.current_objective,
            "objectives_completed": self.objectives_completed,
            "success_probability": self.success_probability,
            "estimated_completion_time": self.estimated_completion_time,
            "failure_reason": self.failure_reason,
            "timestamp": self.timestamp
        }


# Type aliases for convenience
Vector3D = Tuple[float, float, float]
BoundingBox = Tuple[Vector3D, Vector3D]  # (min_corner, max_corner)
Polygon2D = List[Tuple[float, float]]    # List of (x, z) points


# Validation functions
def validate_position(pos: Union[Position3D, Vector3D, Dict[str, float]]) -> Position3D:
    """Validate and convert position to Position3D"""
    if isinstance(pos, Position3D):
        return pos
    elif isinstance(pos, (tuple, list)) and len(pos) == 3:
        return Position3D(x=float(pos[0]), y=float(pos[1]), z=float(pos[2]))
    elif isinstance(pos, dict):
        return Position3D(
            x=float(pos.get("x", 0.0)),
            y=float(pos.get("y", 0.0)),
            z=float(pos.get("z", 0.0)),
            uncertainty=pos.get("uncertainty")
        )
    else:
        raise ValueError(f"Invalid position format: {pos}")


def validate_velocity(vel: Union[Velocity3D, Vector3D, Dict[str, float]]) -> Velocity3D:
    """Validate and convert velocity to Velocity3D"""
    if isinstance(vel, Velocity3D):
        return vel
    elif isinstance(vel, (tuple, list)) and len(vel) == 3:
        return Velocity3D(x=float(vel[0]), y=float(vel[1]), z=float(vel[2]))
    elif isinstance(vel, dict):
        return Velocity3D(
            x=float(vel.get("x", 0.0)),
            y=float(vel.get("y", 0.0)),
            z=float(vel.get("z", 0.0))
        )
    else:
        raise ValueError(f"Invalid velocity format: {vel}")


def validate_orientation(ori: Union[Orientation3D, Vector3D, Dict[str, float]]) -> Orientation3D:
    """Validate and convert orientation to Orientation3D"""
    if isinstance(ori, Orientation3D):
        return ori
    elif isinstance(ori, (tuple, list)) and len(ori) == 3:
        return Orientation3D(pitch=float(ori[0]), roll=float(ori[1]), yaw=float(ori[2]))
    elif isinstance(ori, dict):
        return Orientation3D(
            pitch=float(ori.get("pitch", 0.0)),
            roll=float(ori.get("roll", 0.0)),
            yaw=float(ori.get("yaw", 0.0))
        )
    else:
        raise ValueError(f"Invalid orientation format: {ori}")


# Constants
DEFAULT_COMMAND_TIMEOUT = 5.0  # seconds
MAX_MESSAGE_SIZE = 1024 * 1024  # 1MB
DEFAULT_HEARTBEAT_INTERVAL = 1.0  # seconds
MAX_POSITION_UNCERTAINTY = 10.0  # meters
MIN_CONFIDENCE_THRESHOLD = 0.1 