# Drone AI Simulation Project - Cursor-AI Optimized README

## 🚀 Overview

This project simulates an intelligent drone intercepting a moving target in a 3D forest environment using:

- **Godot 4.4** for 3D simulation
- **LangGraph + LLMs** for high-level planning (System 2 / S2)
- **Python control module** for low-level execution (System 1 / S1)
- Modular perception with switchable real-time/omniscient views

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

---

## 🧠 AI Architecture

### System 1 (S1): Control Executor

- Runs at **200 Hz** (5ms loop)
- Receives JSON action chunks from S2 like:

```json
{
  "action": "intercept",
  "target_point": [x, y, z],
  "urgency": "high",
  "duration_ms": 750
}
```

- Executes motion using linear interpolation, physics, or reinforcement learning

### System 2 (S2): High-Level Planner

- Runs at **7-9 Hz**
- Implemented using LangGraph LLM agents
- Strategy phases: `scan → predict → intercept`
- Uses LangGraph memory to adapt plans over time

---

## 🛰 Drone & Simulation

### Physics

- Uses `AerodynamicsPhysics` plugin with `Aerobody3D` node for realistic flight
- Controls pitch, roll, yaw based on S1 output

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

- `perception_exporter.gd` sends JSON state via socket
- JSON state includes drone pos, target pos, terrain info

### From Python → Godot

- `chunk_executor.py` sends updated drone commands (target point, velocity)
- Interpolated in `drone_controller.gd`

---

## 🧪 Simulation Loop

1. Godot sim runs real-time
2. Every frame (5ms): S1 executes current chunk
3. Every \~150ms: S2 LangGraph plan updated
4. PerceptionModule feeds LangGraph abstracted input
5. JSON output from S2 routed back to control

---

## 🧰 Setup

- Install Godot 4.4
- Install `AerodynamicsPhysics` plugin (AssetLib or GitHub)
- Clone this repo
- Run `godot_sim/project.godot`
- In terminal, run `python ai_core/run_agent.py`

---

## ✅ Goals for Cursor AI

Cursor AI should:

- Respect folder layout: write scripts in `scripts/`, not outside
- Use LangGraph-style JSON format for actions
- Hook into `Aerobody3D` for motion, not fake transforms
- Avoid generating placeholder code unless explicitly told

Use this README as persistent context to align outputs.

