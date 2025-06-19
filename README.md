# Hunter Drone AI - Godot + LangGraph Edition

Smart hunter AI drone that tracks down a target using advanced AI reasoning powered by LangGraph.

## 🏗️ Architecture

This project now uses a hybrid architecture combining:
- **Godot Engine** for real-time 3D simulation and visualization
- **LangGraph** for sophisticated AI decision-making and memory
- **Ollama/LLaMA** for natural language reasoning

```
/hunter-drone-ai/
├── godot_project/          # Godot game engine project
│   ├── scenes/            # Game scenes (Main, Drone, Target, etc.)
│   ├── scripts/           # GDScript files for game logic
│   └── maps/              # Environment maps and obstacles
├── agent/                 # Python LangGraph AI agent
│   ├── main.py           # LangGraph agent loop
│   ├── memory_store.py   # Persistent memory management
│   ├── planner.py        # Strategic planning and pathfinding
│   └── evaluator.py      # Performance evaluation and adaptation
├── data/                 # Data storage and logs
│   ├── logs/            # Runtime logs
│   ├── memory.json      # AI memory storage
│   └── run_history.csv  # Performance history
└── requirements.txt      # Python dependencies
```

## 🧠 How It Works

### LangGraph AI Agent
The AI agent uses a sophisticated state machine with these nodes:
1. **Perceive** - Process environment data from Godot
2. **Remember** - Retrieve relevant memories and past experiences
3. **Plan** - Generate strategic movement plans using AI reasoning
4. **Evaluate** - Assess performance and adjust strategies
5. **Act** - Execute movement commands back to Godot

### Godot Simulation
- Real-time 3D simulation with physics
- Responsive target with evasive behavior  
- Dynamic obstacle avoidance
- Visual feedback of AI reasoning

### Memory System
- Stores successful strategies and failed attempts
- Learns from target behavior patterns
- Tracks performance metrics over time
- Provides context for future decisions

## 🚀 Setup & Installation

### Prerequisites
- **Godot 4.2+** - Download from [godotengine.org](https://godotengine.org)
- **Python 3.8+** with pip
- **Ollama** with LLaMA model - [Install Ollama](https://ollama.ai)

### Installation Steps

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd hunter-drone-ai
   ```

2. **Install Python dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Setup Ollama**
   ```bash
   ollama pull llama3
   ollama serve
   ```

4. **Open Godot Project**
   - Launch Godot Engine
   - Import the project from `godot_project/`
   - Run the project (F5)

## 🎮 Usage

### Running the Simulation
1. Start Ollama server: `ollama serve`
2. Open the Godot project and run it
3. The AI agent will automatically start making decisions
4. Watch the drone hunt the target using AI reasoning

### Controls
- **R** - Restart simulation
- **Space** - Pause/unpause simulation

### Monitoring AI Behavior
- AI reasoning is displayed in real-time in the Godot console
- Memory and performance data is stored in `data/`
- Logs are written to `data/logs/`

## 🔧 Configuration

### AI Agent Settings
Edit `agent/main.py` to adjust:
- Decision interval (default: 0.5 seconds)
- Grid size and physics parameters
- Memory retention policies

### Godot Settings
Edit `godot_project/scripts/GameManager.gd` to modify:
- Simulation parameters
- Obstacle placement
- Target behavior

## 📊 Features

### Advanced AI Capabilities
- **Strategic Planning**: Uses LLaMA to generate sophisticated hunting strategies
- **Memory & Learning**: Remembers successful tactics and avoids failed approaches
- **Adaptive Behavior**: Adjusts strategy based on target behavior patterns
- **Emergency Protocols**: Fallback behaviors when stuck or failing

### Simulation Features
- **Real-time Physics**: Accurate movement and collision detection  
- **Evasive Target**: Target actively tries to escape using obstacles
- **Dynamic Environment**: Configurable obstacles and terrain
- **Performance Metrics**: Detailed tracking of success rates and efficiency

### Technical Features
- **Asynchronous AI**: Non-blocking AI decisions don't slow down simulation
- **Robust Communication**: Error handling between Godot and Python
- **Extensible Architecture**: Easy to add new AI capabilities or game features
- **Data Persistence**: All decisions and outcomes are logged for analysis

## 🎯 Goals & Objectives

The AI agent learns to:
1. **Predict target movement** and plan interception routes
2. **Use obstacles strategically** to corner the target
3. **Adapt strategies** based on what has worked before
4. **Optimize pathfinding** for different environmental layouts
5. **Balance speed vs. safety** in navigation decisions

## 🔬 Research Applications

This project demonstrates:
- **Multi-agent AI coordination**
- **Real-time decision making under uncertainty**
- **Memory-augmented AI reasoning**
- **Hybrid symbolic/neural AI architectures**
- **Game AI and emergent behavior**

## 🛠️ Development

### Adding New AI Capabilities
1. Extend the LangGraph state machine in `agent/main.py`
2. Add new reasoning skills in `agent/planner.py`
3. Update memory categories in `agent/memory_store.py`

### Modifying Simulation
1. Edit Godot scenes in `godot_project/scenes/`
2. Modify game logic in `godot_project/scripts/`
3. Add new maps in `godot_project/maps/`

## 📈 Performance Metrics

The system tracks:
- **Success Rate**: Percentage of targets successfully caught
- **Efficiency**: Time to completion vs. optimal path
- **Strategy Effectiveness**: Which approaches work best
- **Learning Progress**: Improvement over time
- **Failure Analysis**: Common failure modes and solutions

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Test both Godot and Python components
4. Submit a pull request

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙋 Support

For questions or issues:
1. Check the documentation in `docs/`
2. Review existing GitHub issues
3. Create a new issue with detailed information

## 🔍 How This Program Currently Works

### Current Implementation Status

This project represents a **simulated drone AI system** where the intelligence is provided by LangGraph and LLaMA models, but with important limitations that distinguish it from a production-ready drone system:

#### ✅ What's Working Now
- **AI Decision Making**: LangGraph orchestrates a sophisticated 5-node state machine (Perceive → Remember → Plan → Evaluate → Act)
- **Strategic Planning**: LLaMA models generate hunting strategies using natural language reasoning about obstacle layouts and target behavior
- **Memory & Learning**: The system stores successful strategies, failed attempts, and target behavior patterns in JSON-based memory
- **Real-time Simulation**: Godot provides 3D physics simulation with responsive target and obstacle avoidance
- **Performance Tracking**: Continuous evaluation of AI effectiveness with adaptation based on success rates

#### ⚠️ Current Limitations (Simulated vs. Real)

**Perception**: The AI doesn't actually "see" the environment through sensors. Instead:
- Godot simulation feeds perfect position data directly to the AI
- Obstacle positions are pre-programmed, not dynamically detected
- No computer vision, LIDAR, or sensor fusion involved
- Target position is always known exactly (no tracking uncertainty)

**Control**: The drone doesn't have real flight dynamics:
- Movement commands are simplified grid-based positions
- No PID controllers, motor dynamics, or flight stabilization
- No wind, weather, or real-world physics constraints
- Instant position updates rather than gradual movement

**Learning**: The AI learns patterns but not physical skills:
- Stores strategic knowledge in JSON files
- Learns from position/timing patterns, not sensor data
- No reinforcement learning from actual flight experience
- Memory is text-based rather than sensorimotor

### How the AI Actually Learns

The LangGraph agent employs a **memory-augmented reasoning** approach:

1. **Experience Storage**: Every hunt attempt is stored with strategy, outcome, and contextual data
2. **Pattern Recognition**: The system identifies successful interception points and failed approaches
3. **Strategic Adaptation**: LLaMA models use past memories to inform new plans via natural language reasoning
4. **Performance Evaluation**: Continuous assessment triggers strategy changes when stuck or inefficient

**Learning Cycle**: 
```
Attempt Strategy → Measure Outcome → Store Experience → 
Retrieve Similar Situations → Reason About Patterns → Generate New Strategy
```

The AI doesn't learn motor skills or sensor processing - it learns strategic decision-making patterns.

## 🚁 Roadmap to Real Drone Integration

### Phase 1: Sensor Integration (2-3 months)
**Goal**: Replace simulated perception with real sensors

**Steps**:
1. **Computer Vision Pipeline**
   - Integrate OpenCV or similar for real-time object detection
   - Implement YOLO/RCNN for target identification
   - Add depth estimation from stereo cameras or LIDAR
   
2. **Sensor Fusion Module**
   - Combine GPS, IMU, camera, and LIDAR data
   - Implement Extended Kalman Filter for state estimation
   - Handle sensor noise and uncertainty in AI planning
   
3. **Replace Godot Interface**
   - Create `RealDroneInterface` class replacing `AIInterface.gd`
   - Add sensor data preprocessing and filtering
   - Implement real-time data streaming to LangGraph agent

### Phase 2: Flight Control Integration (2-4 months)
**Goal**: Connect to actual drone flight controllers

**Steps**:
1. **Flight Controller Communication**
   - Integrate with PX4/ArduPilot using MAVLink protocol
   - Implement safety checks and emergency stops
   - Add flight mode management (manual override capabilities)

2. **Low-Level Control Layer**
   - Implement PID controllers for position/velocity control
   - Add trajectory smoothing and motion planning
   - Handle physical constraints (battery, payload, weather)

3. **Safety Systems**
   - Geofencing and no-fly zone compliance
   - Emergency landing protocols
   - Real-time system health monitoring

### Phase 3: Advanced AI Learning (3-6 months)
**Goal**: Enable learning from real flight experience

**Steps**:
1. **Reinforcement Learning Integration**
   - Replace JSON memory with neural network state representations
   - Implement continuous learning from flight telemetry
   - Add reward functions based on mission success and safety

2. **Sensor-Motor Learning**
   - Train models to predict sensor readings from actions
   - Learn compensation for wind, turbulence, and disturbances
   - Develop adaptive control based on environmental conditions

3. **Multi-Agent Coordination**
   - Extend to swarm behaviors with multiple drones
   - Implement distributed decision making
   - Add communication protocols between agents

## 🏗️ Making the System Modular and Scalable

### Current Architecture Limitations
- **Tight Coupling**: Godot simulation and AI agent are specifically designed for this hunting task
- **Fixed Task Domain**: Strategic planning is hardcoded for hunter-prey scenarios
- **Limited Extensibility**: Adding new behaviors requires modifying core files

### Modularization Strategy

#### 1. Abstract Interface Layer
```
DroneAgent (Abstract)
├── PerceptionModule (Abstract)
│   ├── SimulatedPerception (Current)
│   └── RealSensorPerception (Future)
├── PlanningModule (Abstract)  
│   ├── HunterPlanner (Current)
│   ├── SearchAndRescuePlanner
│   └── DeliveryPlanner
└── ControlModule (Abstract)
    ├── SimulatedControl (Current)
    └── RealFlightControl (Future)
```

#### 2. Plugin-Based Task System
- **Task Definition Files**: JSON/YAML configs for different mission types
- **Behavior Libraries**: Reusable skill modules (search patterns, formation flying, etc.)
- **Mission Compiler**: Automatically generate LangGraph workflows from task descriptions

#### 3. Scalability Improvements

**Horizontal Scaling**:
- Containerize AI agents for distributed deployment
- Implement message queuing for multi-drone coordination
- Add load balancing for computational heavy reasoning

**Vertical Scaling**:
- Multi-level planning (strategic, tactical, operational)
- Hierarchical memory systems (short-term, episodic, semantic)
- Specialized AI models for different planning horizons

#### 4. Configuration Management
- **Environment Configs**: Different maps, obstacles, weather conditions
- **AI Behavior Configs**: Adjustable risk tolerance, planning horizons, learning rates
- **Hardware Profiles**: Different drone capabilities and sensor suites

### Complex Task Examples

**Search and Rescue**: 
- Replace target tracking with area coverage algorithms
- Add human detection and medical supply delivery
- Integrate with emergency response systems

**Infrastructure Inspection**:
- Replace hunting behaviors with systematic scanning patterns  
- Add defect detection and reporting capabilities
- Implement precision positioning for detailed photography

**Agricultural Monitoring**:
- Replace pursuit with crop field surveying
- Add multispectral imaging and health assessment
- Integrate with farm management systems

The modular architecture would allow rapid reconfiguration for these diverse applications while leveraging the core AI reasoning and learning capabilities.

---

*Built with ❤️ using Godot Engine and LangGraph*