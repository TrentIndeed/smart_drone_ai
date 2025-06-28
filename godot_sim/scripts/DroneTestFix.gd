extends Node

# Drone Test Fix Script - helps verify the fixes are working

@export var check_interval: float = 2.0
@export var auto_fix_falling: bool = true
@export var auto_fix_target_errors: bool = true

var drone: Drone = null
var target: Target = null
var check_timer: float = 0.0

func _ready():
	print("DroneTestFix: Starting diagnostics...")
	await get_tree().process_frame
	
	# Find components
	drone = get_tree().get_first_node_in_group("drones") as Drone
	target = get_tree().get_first_node_in_group("target") as Target
	
	if drone:
		print("DroneTestFix: Found drone - monitoring for falling")
	else:
		print("DroneTestFix: No drone found")
	
	if target:
		print("DroneTestFix: Found target - monitoring for errors")
	else:
		print("DroneTestFix: No target found")

func _physics_process(delta):
	check_timer += delta
	if check_timer >= check_interval:
		check_timer = 0.0
		_run_diagnostics()

func _run_diagnostics():
	"""Run diagnostic checks"""
	print("=== DRONE FIX DIAGNOSTICS ===")
	
	# Check drone falling through floor
	if drone:
		print("Drone position: ", drone.position)
		print("Drone velocity: ", "%.2f" % drone.linear_velocity.length())
		
		var status = drone.get_flight_status() if drone.has_method("get_flight_status") else {}
		print("Drone mode: ", status.get("flight_mode", "UNKNOWN"))
		print("Auto mode: ", status.get("auto_mode", false))
		
		# Check if falling through floor
		if drone.position.y < -0.2:
			print("❌ ISSUE: Drone falling through floor!")
			if auto_fix_falling:
				_fix_falling_drone()
		elif drone.position.y > -0.2:
			print("✅ OK: Drone altitude is normal")
	
	# Check target errors
	if target:
		print("Target position: ", target.position)
		print("Target velocity: ", "%.2f" % target.velocity.length())
		print("Target health: ", target.current_health, "/", target.max_health)
		
		# Check if RunningModel exists
		var running_model = target.get_node_or_null("RunningModel")
		if running_model:
			print("✅ OK: Target RunningModel found")
		else:
			print("❌ ISSUE: Target RunningModel missing!")
			if auto_fix_target_errors:
				_fix_target_model()
	
	print("===============================")

func _fix_falling_drone():
	"""Emergency fix for falling drone"""
	print("DroneTestFix: Emergency fixing falling drone...")
	
	if drone:
		# Reset to safe position
		drone.position = Vector3(0, 2, 0)
		drone.linear_velocity = Vector3.ZERO
		drone.angular_velocity = Vector3.ZERO
		drone.rotation = Vector3.ZERO
		
		# Enable auto mode if available
		if drone.has_method("enable_auto_mode"):
			drone.enable_auto_mode(true)
		
		print("DroneTestFix: Drone reset to safe position")

func _fix_target_model():
	"""Attempt to fix target model issues"""
	print("DroneTestFix: Attempting to fix target model...")
	
	if target:
		# Force target to ground level
		target.position.y = 0.0
		
		# Reset velocity if stuck
		if target.velocity.length() < 0.1:
			target.velocity = Vector3(1, 0, 0) * target.max_speed
			print("DroneTestFix: Reset target velocity")

func _input(event):
	"""Handle debug input"""
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_F1:
				_fix_falling_drone()
			KEY_F2:
				_fix_target_model()
			KEY_F3:
				_force_diagnostic()

func _force_diagnostic():
	"""Force run diagnostics"""
	print("DroneTestFix: Running forced diagnostics...")
	_run_diagnostics()

# Public methods for external use
func is_drone_falling() -> bool:
	"""Check if drone is falling through floor"""
	if drone:
		return drone.position.y < -0.2
	return false

func is_target_healthy() -> bool:
	"""Check if target is working properly"""
	if target:
		var has_model = target.get_node_or_null("RunningModel") != null
		var is_moving = target.velocity.length() > 0.1
		return has_model and is_moving
	return false

func get_system_status() -> Dictionary:
	"""Get overall system status"""
	return {
		"drone_found": drone != null,
		"target_found": target != null,
		"drone_falling": is_drone_falling(),
		"target_healthy": is_target_healthy(),
		"auto_fix_enabled": auto_fix_falling and auto_fix_target_errors
	} 