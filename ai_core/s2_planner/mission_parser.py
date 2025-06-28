"""
Mission Parser for System 2 (S2)
Parses and interprets mission configurations and objectives
"""

import yaml
import json
from typing import Dict, List, Any, Optional
from dataclasses import dataclass
from enum import Enum
from pathlib import Path


class MissionType(Enum):
    INTERCEPT = "intercept"
    PATROL = "patrol"
    SEARCH = "search"
    ESCORT = "escort"
    SURVEILLANCE = "surveillance"
    TRANSPORT = "transport"


class Priority(Enum):
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"


@dataclass
class MissionObjective:
    """Single mission objective with priority and constraints"""
    objective_id: str
    type: str
    description: str
    priority: Priority
    success_criteria: Dict[str, Any]
    constraints: Dict[str, Any]
    rewards: Dict[str, float]
    penalties: Dict[str, float]


@dataclass
class MissionParameters:
    """Mission execution parameters"""
    max_flight_time: float
    max_speed: float
    altitude_range: tuple[float, float]
    intercept_radius: float
    energy_limit: float
    communication_range: float


@dataclass
class EnvironmentSettings:
    """Environment configuration for mission"""
    terrain_type: str
    weather_conditions: str
    visibility: str
    obstacle_density: float
    no_fly_zones: List[Dict[str, Any]]
    emergency_landing_sites: List[tuple[float, float, float]]


@dataclass
class ParsedMission:
    """Complete parsed mission configuration"""
    mission_id: str
    name: str
    description: str
    mission_type: MissionType
    objectives: List[MissionObjective]
    parameters: MissionParameters
    environment: EnvironmentSettings
    scoring: Dict[str, Any]
    metadata: Dict[str, Any]


class MissionParser:
    """Parses mission configuration files and creates executable mission plans"""
    
    def __init__(self, config_dir: str = "ai_core/configs/missions"):
        self.config_dir = Path(config_dir)
        self.config_dir.mkdir(parents=True, exist_ok=True)
        
        # Default mission templates
        self.mission_templates = self._load_templates()
        
    def parse_mission_file(self, file_path: str) -> ParsedMission:
        """Parse a mission configuration file"""
        file_path = Path(file_path)
        
        if not file_path.exists():
            raise FileNotFoundError(f"Mission file not found: {file_path}")
        
        # Load based on file extension
        if file_path.suffix.lower() == '.yaml' or file_path.suffix.lower() == '.yml':
            with open(file_path, 'r') as f:
                config = yaml.safe_load(f)
        elif file_path.suffix.lower() == '.json':
            with open(file_path, 'r') as f:
                config = json.load(f)
        else:
            raise ValueError(f"Unsupported file format: {file_path.suffix}")
        
        return self._parse_config(config, file_path.stem)
    
    def parse_mission_dict(self, config: Dict[str, Any], mission_id: str = None) -> ParsedMission:
        """Parse a mission configuration dictionary"""
        if mission_id is None:
            mission_id = config.get("mission", {}).get("name", "unknown_mission")
        
        return self._parse_config(config, mission_id)
    
    def _parse_config(self, config: Dict[str, Any], mission_id: str) -> ParsedMission:
        """Parse mission configuration dictionary into ParsedMission object"""
        
        mission_info = config.get("mission", {})
        
        # Parse basic mission info
        name = mission_info.get("name", mission_id)
        description = mission_info.get("description", "")
        mission_type = MissionType(mission_info.get("type", "intercept"))
        
        # Parse objectives
        objectives = self._parse_objectives(config.get("objectives", {}))
        
        # Parse parameters
        parameters = self._parse_parameters(config.get("parameters", {}))
        
        # Parse environment
        environment = self._parse_environment(config.get("environment", {}))
        
        # Parse scoring
        scoring = config.get("scoring", {})
        
        # Parse metadata
        metadata = {
            "created_time": config.get("created_time"),
            "version": config.get("version", "1.0"),
            "author": config.get("author", "unknown"),
            "tags": config.get("tags", [])
        }
        
        return ParsedMission(
            mission_id=mission_id,
            name=name,
            description=description,
            mission_type=mission_type,
            objectives=objectives,
            parameters=parameters,
            environment=environment,
            scoring=scoring,
            metadata=metadata
        )
    
    def _parse_objectives(self, objectives_config: Dict[str, Any]) -> List[MissionObjective]:
        """Parse mission objectives"""
        objectives = []
        
        # Primary objective
        if "primary" in objectives_config:
            primary = self._create_objective(
                "primary",
                objectives_config["primary"],
                Priority.HIGH
            )
            objectives.append(primary)
        
        # Secondary objectives
        if "secondary" in objectives_config:
            secondary = self._create_objective(
                "secondary", 
                objectives_config["secondary"],
                Priority.MEDIUM
            )
            objectives.append(secondary)
        
        # Tertiary objectives
        if "tertiary" in objectives_config:
            tertiary = self._create_objective(
                "tertiary",
                objectives_config["tertiary"],
                Priority.LOW
            )
            objectives.append(tertiary)
        
        # Additional objectives
        for key, value in objectives_config.items():
            if key not in ["primary", "secondary", "tertiary"]:
                obj = self._create_objective(key, value, Priority.LOW)
                objectives.append(obj)
        
        return objectives
    
    def _create_objective(self, obj_id: str, config: Any, default_priority: Priority) -> MissionObjective:
        """Create a mission objective from configuration"""
        
        if isinstance(config, str):
            # Simple string objective
            return MissionObjective(
                objective_id=obj_id,
                type=config,
                description=config,
                priority=default_priority,
                success_criteria={},
                constraints={},
                rewards={},
                penalties={}
            )
        elif isinstance(config, dict):
            # Detailed objective configuration
            return MissionObjective(
                objective_id=obj_id,
                type=config.get("type", obj_id),
                description=config.get("description", config.get("type", obj_id)),
                priority=Priority(config.get("priority", default_priority.value)),
                success_criteria=config.get("success_criteria", {}),
                constraints=config.get("constraints", {}),
                rewards=config.get("rewards", {}),
                penalties=config.get("penalties", {})
            )
        else:
            raise ValueError(f"Invalid objective configuration for {obj_id}: {config}")
    
    def _parse_parameters(self, params_config: Dict[str, Any]) -> MissionParameters:
        """Parse mission parameters"""
        
        return MissionParameters(
            max_flight_time=params_config.get("max_flight_time", 300.0),
            max_speed=params_config.get("max_speed", 15.0),
            altitude_range=tuple(params_config.get("altitude_range", [2.0, 50.0])),
            intercept_radius=params_config.get("intercept_radius", 5.0),
            energy_limit=params_config.get("energy_limit", 1000.0),
            communication_range=params_config.get("communication_range", 1000.0)
        )
    
    def _parse_environment(self, env_config: Dict[str, Any]) -> EnvironmentSettings:
        """Parse environment settings"""
        
        return EnvironmentSettings(
            terrain_type=env_config.get("terrain_type", "flat"),
            weather_conditions=env_config.get("weather", "clear"),
            visibility=env_config.get("visibility", "good"),
            obstacle_density=env_config.get("obstacle_density", 0.1),
            no_fly_zones=env_config.get("no_fly_zones", []),
            emergency_landing_sites=[
                tuple(site) for site in env_config.get("emergency_landing_sites", [[0, 0, 0]])
            ]
        )
    
    def validate_mission(self, mission: ParsedMission) -> List[str]:
        """Validate parsed mission and return list of issues"""
        issues = []
        
        # Check basic requirements
        if not mission.name:
            issues.append("Mission name is required")
        
        if not mission.objectives:
            issues.append("At least one objective is required")
        
        # Validate parameters
        if mission.parameters.max_flight_time <= 0:
            issues.append("Max flight time must be positive")
        
        if mission.parameters.max_speed <= 0:
            issues.append("Max speed must be positive")
        
        if mission.parameters.altitude_range[0] >= mission.parameters.altitude_range[1]:
            issues.append("Invalid altitude range: min >= max")
        
        if mission.parameters.intercept_radius <= 0:
            issues.append("Intercept radius must be positive")
        
        # Validate objectives
        primary_count = sum(1 for obj in mission.objectives if obj.priority == Priority.HIGH)
        if primary_count == 0:
            issues.append("At least one high-priority objective is required")
        
        # Check for conflicting objectives
        objective_types = [obj.type for obj in mission.objectives]
        if len(set(objective_types)) != len(objective_types):
            issues.append("Duplicate objective types found")
        
        return issues
    
    def create_mission_template(self, mission_type: MissionType) -> Dict[str, Any]:
        """Create a mission template for the given type"""
        
        templates = {
            MissionType.INTERCEPT: {
                "mission": {
                    "name": "intercept_template",
                    "description": "Intercept and capture a moving target",
                    "type": "intercept"
                },
                "objectives": {
                    "primary": {
                        "type": "intercept_target",
                        "description": "Successfully intercept the target",
                        "priority": "high",
                        "success_criteria": {
                            "final_distance": 5.0,
                            "time_limit": 300.0
                        }
                    },
                    "secondary": "avoid_obstacles",
                    "tertiary": "minimize_flight_time"
                },
                "parameters": {
                    "max_flight_time": 300.0,
                    "intercept_radius": 5.0,
                    "max_speed": 15.0,
                    "altitude_range": [2.0, 50.0]
                },
                "environment": {
                    "terrain_type": "forest",
                    "obstacle_density": 0.3,
                    "weather": "clear",
                    "visibility": "good"
                },
                "scoring": {
                    "success_points": 100,
                    "time_bonus_factor": 0.5,
                    "collision_penalty": -25
                }
            },
            
            MissionType.PATROL: {
                "mission": {
                    "name": "patrol_template",
                    "description": "Patrol a designated area",
                    "type": "patrol"
                },
                "objectives": {
                    "primary": "patrol_waypoints",
                    "secondary": "detect_intrusions",
                    "tertiary": "maintain_communication"
                },
                "parameters": {
                    "max_flight_time": 1800.0,  # 30 minutes
                    "max_speed": 10.0,
                    "altitude_range": [10.0, 100.0]
                }
            },
            
            MissionType.SEARCH: {
                "mission": {
                    "name": "search_template",
                    "description": "Search area for targets",
                    "type": "search"
                },
                "objectives": {
                    "primary": "search_area",
                    "secondary": "identify_targets",
                    "tertiary": "map_obstacles"
                }
            }
        }
        
        return templates.get(mission_type, templates[MissionType.INTERCEPT])
    
    def _load_templates(self) -> Dict[MissionType, Dict[str, Any]]:
        """Load mission templates"""
        templates = {}
        
        for mission_type in MissionType:
            templates[mission_type] = self.create_mission_template(mission_type)
        
        return templates
    
    def save_mission(self, mission: ParsedMission, file_path: str = None):
        """Save parsed mission back to file"""
        
        if file_path is None:
            file_path = self.config_dir / f"{mission.mission_id}.yaml"
        else:
            file_path = Path(file_path)
        
        # Convert back to configuration format
        config = self._mission_to_config(mission)
        
        # Save as YAML
        with open(file_path, 'w') as f:
            yaml.dump(config, f, indent=2, default_flow_style=False)
        
        print(f"Mission saved to {file_path}")
    
    def _mission_to_config(self, mission: ParsedMission) -> Dict[str, Any]:
        """Convert ParsedMission back to configuration dictionary"""
        
        config = {
            "mission": {
                "name": mission.name,
                "description": mission.description,
                "type": mission.mission_type.value
            },
            "objectives": {},
            "parameters": {
                "max_flight_time": mission.parameters.max_flight_time,
                "max_speed": mission.parameters.max_speed,
                "altitude_range": list(mission.parameters.altitude_range),
                "intercept_radius": mission.parameters.intercept_radius
            },
            "environment": {
                "terrain_type": mission.environment.terrain_type,
                "weather": mission.environment.weather_conditions,
                "visibility": mission.environment.visibility,
                "obstacle_density": mission.environment.obstacle_density,
                "no_fly_zones": mission.environment.no_fly_zones,
                "emergency_landing_sites": [list(site) for site in mission.environment.emergency_landing_sites]
            },
            "scoring": mission.scoring,
            **mission.metadata
        }
        
        # Add objectives
        for obj in mission.objectives:
            config["objectives"][obj.objective_id] = {
                "type": obj.type,
                "description": obj.description,
                "priority": obj.priority.value
            }
            
            if obj.success_criteria:
                config["objectives"][obj.objective_id]["success_criteria"] = obj.success_criteria
            if obj.constraints:
                config["objectives"][obj.objective_id]["constraints"] = obj.constraints
        
        return config
    
    def list_available_missions(self) -> List[str]:
        """List all available mission files"""
        mission_files = []
        
        for file_path in self.config_dir.glob("*.yaml"):
            mission_files.append(file_path.stem)
        
        for file_path in self.config_dir.glob("*.yml"):
            mission_files.append(file_path.stem)
            
        for file_path in self.config_dir.glob("*.json"):
            mission_files.append(file_path.stem)
        
        return sorted(mission_files) 