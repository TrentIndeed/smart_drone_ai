"""
Simulation Interface for Godot Communication
Handles socket communication between Python AI and Godot simulation
"""

import socket
import json
import threading
import time
from typing import Dict, Any, Optional
from dataclasses import dataclass


@dataclass
class DroneState:
    """Current state of the drone in simulation"""
    position: tuple[float, float, float]
    velocity: tuple[float, float, float]
    orientation: tuple[float, float, float]  # pitch, roll, yaw
    battery_level: float
    is_armed: bool


@dataclass
class TargetState:
    """Current state of the target"""
    position: tuple[float, float, float]
    velocity: tuple[float, float, float]
    is_visible: bool


@dataclass
class SimulationState:
    """Complete simulation state"""
    drone: DroneState
    target: TargetState
    obstacles: list[Dict[str, Any]]
    timestamp: float


class SimInterface:
    """Interface for communication with Godot simulation"""
    
    def __init__(self, host='localhost', port=8080):
        self.host = host
        self.port = port
        self.socket = None
        self.connected = False
        self.latest_state = None
        self.running = False
        
    def connect(self) -> bool:
        """Establish connection with Godot simulation"""
        try:
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.socket.connect((self.host, self.port))
            self.connected = True
            print(f"Connected to simulation at {self.host}:{self.port}")
            return True
        except Exception as e:
            print(f"Failed to connect to simulation: {e}")
            return False
    
    def disconnect(self):
        """Close connection with simulation"""
        if self.socket:
            self.socket.close()
            self.connected = False
            print("Disconnected from simulation")
    
    def send_command(self, command: Dict[str, Any]) -> bool:
        """Send command to simulation"""
        if not self.connected:
            return False
        
        try:
            command_json = json.dumps(command)
            self.socket.sendall(command_json.encode('utf-8'))
            return True
        except Exception as e:
            print(f"Failed to send command: {e}")
            return False
    
    def receive_state(self) -> Optional[SimulationState]:
        """Receive current state from simulation"""
        if not self.connected:
            return None
        
        try:
            data = self.socket.recv(4096)
            if data:
                state_dict = json.loads(data.decode('utf-8'))
                return self._parse_state(state_dict)
        except Exception as e:
            print(f"Failed to receive state: {e}")
        
        return None
    
    def _parse_state(self, state_dict: Dict[str, Any]) -> SimulationState:
        """Parse received state dictionary into SimulationState object"""
        drone_data = state_dict.get('drone', {})
        target_data = state_dict.get('target', {})
        
        drone_state = DroneState(
            position=tuple(drone_data.get('position', [0, 0, 0])),
            velocity=tuple(drone_data.get('velocity', [0, 0, 0])),
            orientation=tuple(drone_data.get('orientation', [0, 0, 0])),
            battery_level=drone_data.get('battery', 100.0),
            is_armed=drone_data.get('armed', False)
        )
        
        target_state = TargetState(
            position=tuple(target_data.get('position', [0, 0, 0])),
            velocity=tuple(target_data.get('velocity', [0, 0, 0])),
            is_visible=target_data.get('visible', True)
        )
        
        return SimulationState(
            drone=drone_state,
            target=target_state,
            obstacles=state_dict.get('obstacles', []),
            timestamp=time.time()
        )
    
    def start_listening(self):
        """Start listening for state updates in background thread"""
        self.running = True
        listener_thread = threading.Thread(target=self._listen_loop)
        listener_thread.daemon = True
        listener_thread.start()
    
    def stop_listening(self):
        """Stop background listening"""
        self.running = False
    
    def _listen_loop(self):
        """Background loop for receiving state updates"""
        while self.running and self.connected:
            state = self.receive_state()
            if state:
                self.latest_state = state
            time.sleep(0.005)  # 200Hz polling
    
    def get_latest_state(self) -> Optional[SimulationState]:
        """Get the most recent simulation state"""
        return self.latest_state 