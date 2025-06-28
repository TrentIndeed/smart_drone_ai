Act as a full-stack AI + robotics engineer.

You're working in this repo:

- `README.md` contains the full architecture and goal (LangGraph S2 planner, Python S1, Godot sim).
- The drone is in `godot_sim/scenes/drone.tscn` and uses a `.glb` mesh.
- The S2 planner lives in `ai_core/s2_planner/` and outputs JSON action chunks.
- S1 is in `ai_core/s1_perception_control/` and executes at 200 Hz.

Do not generate placeholder code — only operate within the real repo design.

Now read the full `README.md` and confirm your understanding of:
1. Repo structure
2. Mission architecture (LangGraph + perception)
3. Where Godot connects with Python
4. How the drone control loop works

After that, help me implement [TASK].


# 🛠️ Fix Drone Auto Mode in Godot — Avoid Uncontrolled Ascent

## 📁 Repo Overview
- `godot_sim/`: Godot 3D simulation (drone, terrain, target, environment)
- `ai_core/`: Python-based S1/S2 system (LangGraph planner, chunk executor)
- `configs/`: Task/environment configs in YAML
- `shared/`: Schema definitions (e.g., chunk format)

## 🤖 System Design
- **S1**: real-time control executor (~200Hz), normally receives JSON `action_chunk` from S2
- **S2**: LangGraph-based planner (~7Hz)
- Simulation sends drone/target positions to Python → Python responds with control chunks
- In this mode, we want to **bypass the LLM (S2)** and use a simple auto-fly-to-target mode

## 🎯 Objective
- Add a **non-LLM auto mode** in Godot where the drone flies toward the moving target
- Disable S2 and any socket communication
- Implement logic in `drone_controller.gd` or new `auto_chase.gd`

## ⚠️ Issue
- Drone **rises rapidly**, flying upward uncontrollably
- Likely due to:
  - Incorrect force direction (e.g., `Vector3.UP`)
  - Misuse of world vs. local space motion
  - Not using physics (`Aerobody3D`) properly

## ✅ Tasks
- Fix drone auto-fly behavior:
  - Use `Aerobody3D` or physics-based motion
  - Rotate to face the target smoothly
  - Apply forward thrust in local Z direction (`-transform.basis.z`)
  - Apply upward lift in moderation (balance gravity, prevent rising)
  - Do **not** use `translate()` or direct `transform.origin` hacks

- Use physics methods:
  - `apply_force()`, `add_central_force()`, or `apply_impulse()`

## 🔄 Debug Tips
- Draw debug lines:
  - To target
  - Forward thrust vector
- Print:
  - Pitch, roll, yaw
  - Altitude changes per frame

## 📍 Bonus Features
- Add toggle: `use_auto_mode: bool` in `GameManager`
- Later, replace logic with S1 JSON `chunk` executor

## ✏️ Relevant Files
- `godot_sim/scripts/drone_controller.gd`
- `godot_sim/scenes/main_scene.tscn`
- Optional: `target.tscn` for target movement

---

