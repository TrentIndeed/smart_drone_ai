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

---

*Built with ❤️ using Godot Engine and LangGraph*