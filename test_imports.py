#!/usr/bin/env python3

print("Testing imports...")

try:
    from environment import Environment, FPS, check_circle_collision, distance, GRID_SIZE
    print("✓ Environment imports successful")
except ImportError as e:
    print(f"✗ Environment import failed: {e}")

try:
    from drone import Drone, DRONE_RADIUS, MAX_SPEED
    print("✓ Drone imports successful")
except ImportError as e:
    print(f"✗ Drone import failed: {e}")

try:
    from target import Target, TARGET_RADIUS
    print("✓ Target imports successful")
except ImportError as e:
    print(f"✗ Target import failed: {e}")

try:
    from ai import DroneAI
    print("✓ AI imports successful")
except ImportError as e:
    print(f"✗ AI import failed: {e}")

print("All imports tested!") 