# Drone AI Simulation Project - Cursor-AI Optimized README

## 🚀 Overview

This project simulates an intelligent drone intercepting a moving target in a 3D forest environment using:

* **Godot 4.4** for 3D simulation
* **LangGraph + LLMs** for high-level planning (System 2 / S2)
* **Python control module** for low-level execution (System 1 / S1)
* Modular perception with switchable real-time/omniscient views

---

## 📁 Repo Structure

```
drone-ai-project/
├── godot_sim/                  # Godot 4.4 simulation
│   ├── scenes/                 # Drone, target, terrain .tscn files
│   ├── scripts/                # Godot GDScript control
│   └── assets/                 # GLB models, textures
│
├── ai_core/                    # Python AI core (LangGraph, S1/S2)
│   ├── s1_perception_control/  # Real-time executor (200Hz)
│   ├── s2_planner/             # LangGraph planner (7-9Hz)
│   └── run_agent.py            # Entry point
│
├── configs/                   # YAML or JSON config files
├── logs/                      # Output logs for metrics + memory
├── shared/                    # Schemas, utils, interfaces
└── README.md
```

## 🧠 AI Architecture

### System 1 (S1): Control Executor

* Runs at **200 Hz** (5ms loop)
* Receives JSON action chunks from S2 like:

```json
{
  "action": "intercept",
  "target_point": [x, y, z],
  "urgency": "high",
  "duration_ms": 750
}
```

* Executes motion using linear interpolation, physics, or reinforcement learning

### System 2 (S2): High-Level Planner

* Runs at **7-9 Hz**
* Implemented using LangGraph LLM agents
* Strategy phases: `scan → predict → intercept`
* Uses LangGraph memory to adapt plans over time

---

## 🛰 Drone & Simulation

### Physics

* Uses `AerodynamicsPhysics` plugin with `Aerobody3D` node for realistic flight
* Controls pitch, roll, yaw based on S1 output

### Scene Structure

```
scenes/
├── drone.tscn       # Has Aerobody3D and collision
├── target.tscn      # Animated, runs away
├── terrain.tscn     # Procedural elevation (via plugin)
└── main_scene.tscn  # Root scene
```

---

## 🔄 Interfaces

### From Godot → Python

* `perception_exporter.gd` sends JSON state via socket
* JSON state includes drone pos, target pos, terrain info

### From Python → Godot

* `chunk_executor.py` sends updated drone commands (target point, velocity)
* Interpolated in `drone_controller.gd`

---

## 🧪 Simulation Loop

1. Godot sim runs real-time
2. Every frame (5ms): S1 executes current chunk
3. Every \~150ms: S2 LangGraph plan updated
4. PerceptionModule feeds LangGraph abstracted input
5. JSON output from S2 routed back to control

---

## 🧰 Setup

* Install Godot 4.5
* Install `AerodynamicsPhysics` plugin (AssetLib or GitHub)
* Clone this repo
* Run `godot_sim/project.godot`
* In terminal, run `python ai_core/run_agent.py`

---

## ✅ Goals for Cursor AI

Cursor AI should:

* Respect folder layout: write scripts in `scripts/`, not outside
* Use LangGraph-style JSON format for actions
* Hook into `Aerobody3D` for motion, not fake transforms
* Avoid generating placeholder code unless explicitly told

Use this README as persistent context to align outputs.



# Drone AI Simulation Project - Current State & Roadmap

## 🚀 Overview

This project simulates an intelligent drone intercepting a moving target in a 3D forest environment. The system combines **Godot 4.4/4.5** for realistic 3D simulation with **Python-based AI** for intelligent behavior.

**🎯 Mission:** Create a modular AI architecture that can control both **drone** and **target** entities, with swappable intelligence systems.

---

## 📁 Current Repo Structure

```
smart_drone_ai/
├── godot_sim/                  # ✅ Godot 4.4+ simulation (IMPLEMENTED)
│   ├── scenes/                 # drone.tscn, target.tscn, main.tscn  
│   ├── scripts/                # 25+ GDScript files for physics & control
│   ├── assets/models/          # Drone GLB mesh + textures
│   └── addons/                 # AerodynamicsPhysics + terrain plugins
│
├── ai_core/                    # 🔄 Python AI core (PARTIALLY IMPLEMENTED)
│   ├── s1_perception_control/  # ✅ Real-time control at 200Hz
│   ├── s2_planner/             # ✅ LangGraph planner + memory 
│   ├── memory/                 # ✅ Episodic, reward, curriculum systems
│   ├── interface/              # 🔄 Socket communication (designed, not connected)
│   └── configs/missions/       # ✅ YAML mission definitions
│
├── configs/                   # ✅ Agent & terrain configuration
├── logs/                      # ✅ Run history & trial data
├── shared/                    # ✅ Schema definitions
└── README.md                  # 📝 This file
```

**Legend:** ✅ Implemented | 🔄 Partially Done | ❌ Not Started | 📝 Documentation

---

## 🧠 AI Architecture - Current vs Intended

### **System 1 (S1): Control Executor** ✅ IMPLEMENTED

**Current State:**
- **Location:** `ai_core/s1_perception_control/`
- **Frequency:** 200 Hz control loop
- **Components:**
  - `control_module.py` - PID controllers, flight modes (HOVER, INTERCEPT, AVOID)
  - `perception_module.py` - Kalman filtering, threat detection, target prediction
  - `evaluator.py` - Performance evaluation
- **Capabilities:** 
  - Real-time drone command generation
  - Multi-mode control (manual, waypoint, intercept, emergency)
  - Safety limits and emergency handling

**Input Format (S2 → S1):**
```python
ControlCommand(
    command_id="cmd_123",
    mode=ControlMode.INTERCEPT,
    target_position=(x, y, z),
    urgency="high",
    duration_ms=750
)
```

### **System 2 (S2): Strategic Planner** ✅ IMPLEMENTED  

**Current State:**
- **Location:** `ai_core/s2_planner/`
- **Frequency:** 7-9 Hz planning cycle
- **Components:**
  - `planner.py` - LangGraph + Ollama LLM strategic planning
  - `memory_store.py` - Success/failure pattern storage
  - `run_agent.py` - Main LangGraph agent coordination
- **Capabilities:**
  - AI-powered interception planning
  - Memory-based strategy adaptation
  - Multiple strategy types (direct, predictive, flanking, ambush)

**Output Format (S2 → S1):**
```json
{
  "action": "intercept",
  "target_point": [x, y, z],
  "urgency": "high", 
  "duration_ms": 750,
  "strategy_type": "predictive_intercept"
}
```

### **Memory System** ✅ IMPLEMENTED

**Current State:**
- **Episodic Memory:** `memory/episodic_store.py` - SQLite-based mission episode storage
- **Reward System:** `memory/reward_logger.py` - Performance tracking & reward calculation
- **Curriculum:** `memory/curriculum_tracker.py` - Adaptive difficulty progression
- **Working Memory:** `s2_planner/memory_store.py` - Strategy success/failure patterns

---

## 🛰 Drone & Simulation - Current State

### **Physics & Control** ✅ WELL IMPLEMENTED

**Current State:**
- **Main Controller:** `godot_sim/scripts/drone_flight_adapter.gd` (852 lines)
- **Physics Engine:** Uses Godot's `RigidBody3D` with `AerodynamicsPhysics` plugin
- **Flight Modes:** MANUAL, STABILIZE, ALTITUDE_HOLD, LOITER, RTL, AUTO_CHASE
- **Control Systems:**
  - Multi-rotor physics simulation
  - PID controllers for pitch, roll, yaw, altitude
  - Emergency systems & stability monitoring
  - Auto-chase mode for direct target following

**Additional Scripts:**
- `drone_flight_fallback.gd` - Simplified backup physics
- `drone_ai_interface.gd` - Bridge between AI and drone
- `camera_controller.gd` - Camera following system
- `game_manager.gd` - Overall coordination

### **Current Scene Structure** ✅ IMPLEMENTED
```
scenes/
├── main.tscn           # Root game scene
├── drone.tscn          # Aerodynamic drone with physics
├── target.tscn         # Moving target with AI
└── drone_flight_simple.tscn  # Simplified test scene
```

---

## 🔄 Communication Gap - The Missing Link ❌ NOT CONNECTED

### **The Problem:**
The README describes a socket-based communication system between Godot and Python:

**Described but NOT Implemented:**
- ❌ `perception_exporter.gd` (mentioned in README, doesn't exist)
- ❌ `chunk_executor.py` (mentioned in README, doesn't exist)  
- ❌ Active socket communication

**What Actually Exists:**
- ✅ `ai_core/interface/sim_interface.py` - Socket communication framework
- ✅ `godot_sim/scripts/ai_interface.gd` - Basic AI bridge (51 lines)
- ✅ `godot_sim/scripts/drone_ai_interface.gd` - Navigation interface (235 lines)

**Current Reality:**
The AI systems (S1/S2) and Godot simulation run **independently**. Godot has sophisticated self-contained auto-chase modes, while the Python AI is a complete strategic system that's not connected to Godot.

---

## 🎯 Target Vision - How We Want It To Work

### **1. Bidirectional AI-Sim Integration**
```
Godot Simulation ⟷ Socket Bridge ⟷ Python AI Core
     ↓                   ↓                ↓
 Physics Reality    JSON Messages    Strategic Thinking
```

### **2. Modular AI Assignment** 
**Key Innovation:** Swap AI control between entities:
```yaml
# Mission config example
ai_assignment:
  drone: "s2_planner"     # Strategic hunter
  target: "simple_evasion" # Basic avoidance
  
# OR flip it:
ai_assignment:
  drone: "manual"         # Human controlled  
  target: "s2_planner"    # Strategic evader
```

### **3. Unified Control Interface**
All entities (drone, target, NPCs) should accept the same command format:
```python
EntityCommand(
    entity_id="drone_01", 
    mode=ControlMode.INTERCEPT,
    target_position=(x, y, z),
    parameters={"speed": 0.8, "aggression": 0.6}
)
```

### **4. Real-Time Mission Configuration**
```yaml
missions/advanced_hunt.yaml:
  entities:
    - id: "hunter_drone"
      type: "drone"
      ai_system: "s2_strategic"
      spawn_point: [0, 5, 0]
    
    - id: "evader_target"  
      type: "target"
      ai_system: "s1_reactive" 
      spawn_point: [100, 2, 100]
      
  objectives:
    primary: "intercept_within_time"
    time_limit: 300
```

---

## ⚡ Implementation Roadmap

### **Phase 1: Connect the Bridge** 🔄 IN PROGRESS
1. ✅ Complete `godot_sim/scripts/perception_exporter.gd`
2. ✅ Complete `ai_core/interface/chunk_executor.py` 
3. ✅ Establish real-time socket communication
4. ✅ Test S2 → Godot command flow

### **Phase 2: Unified Entity Control** 📋 PLANNED
1. Create `shared/entity_controller.py` - Universal entity interface
2. Refactor `target.gd` to accept external AI commands
3. Implement AI assignment switching in mission configs
4. Add real-time entity reassignment via API

### **Phase 3: Advanced Capabilities** 🚀 FUTURE
1. Multi-entity scenarios (multiple drones, multiple targets)
2. Real-time strategy switching
3. Human-in-the-loop override capabilities  
4. Integration with real drone hardware via `ai_core/interface/real_interface.py`

---

## 🧰 Quick Start

### **Current Working Modes:**

**1. Godot-Only Simulation** ✅ WORKS NOW
```bash
# Run Godot simulation with built-in AI
cd godot_sim && godot project.godot
# Press '5' in-game to enable auto-chase mode
```

**2. Python AI Testing** ✅ WORKS NOW  
```bash
# Test S2 strategic planner independently
cd ai_core && python run_agent.py
```

**3. Full Integration** 🔄 COMING SOON
```bash
# Terminal 1: Start Godot simulation
cd godot_sim && godot project.godot

# Terminal 2: Start Python AI
cd ai_core && python run_agent.py --connect-godot
```

---

## 🎮 Current Capabilities Demo

**What Works Right Now:**
- ✅ Realistic drone physics with aerodynamic simulation
- ✅ Advanced auto-chase modes in Godot  
- ✅ Sophisticated Python AI planning with LLM + memory
- ✅ Mission configuration system
- ✅ Performance tracking & curriculum learning
- ✅ Multiple camera modes and visual debugging

**Try This:**
1. Open `godot_sim/project.godot`
2. Run the scene
3. Press `5` to enable auto-chase mode
4. Watch the drone intelligently pursue the moving target
5. Check `logs/run_history.csv` for performance data

---

## ✅ Goals for Development

**Immediate (Next Sprint):**
- [ ] Bridge Godot ↔ Python communication gap
- [ ] Enable S2 strategic planner to control Godot drone
- [ ] Implement entity AI assignment switching

**Medium-term:**
- [ ] Multi-entity scenarios  
- [ ] Real-time mission reconfiguration
- [ ] Advanced memory-based learning

**Long-term:**
- [ ] Real drone hardware integration
- [ ] Distributed multi-agent systems
- [ ] Human-AI collaborative control

---

**🔗 Key Files to Understand:**
- `ai_core/s1_perception_control/control_module.py` - Core control logic
- `ai_core/s2_planner/planner.py` - Strategic AI planning  
- `godot_sim/scripts/drone_flight_adapter.gd` - Physics simulation
- `ai_core/interface/sim_interface.py` - Communication framework
- `configs/agent_config.yaml` - System configuration
