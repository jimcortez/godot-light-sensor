@icon("res://addons/light_sensor_3d/icon.png")
@tool
class_name LightSensor3D extends Node3D

## Emitted when the color the sensor observes has changed (after refresh()).
signal color_updated(color: Color)

## Emitted when the light level the sensor observes has changed (after refresh()).
## Ranges from 0 (pitch dark) to 1 (bright as the sun).
signal light_level_updated(luminance: float)

## Configure a layer for the sensor probe.
## Choose a layer visible to your lights but invisible to your camera.
@export_flags_3d_render var layer: int = 0:
	set(value):
		layer = value
		update_configuration_warnings()

@export_group("Advanced")
## Renders a square next to the sensor that shows what the subviewport is seeing.
@export var enable_subviewport_debug = false

## Prints out how long the sensor took every time it refreshes.
@export var print_timing_information = false

## Use GPU compute manager path (async) instead of direct CPU averaging.
@export var use_compute_mode := true

## Input sample resolution for the subviewport (1, 4, or 8). Not strictly enforced here.
@export var sample_resolution := 4

## Color recorded by the probe during refresh().
## See also: light_level()
var color: Color = Color.BLACK

## Gets the luminance of the last color generated using refresh().
## Ranges from 0 (pitch dark) to 1 (bright as the sun).
## See also: color
var light_level: float:
	get:
		# This calculates and returns the luminance.
		# Color#luminance exists but sounds broken:
		# https://github.com/godotengine/godot/issues/57015
		return 0.299 * color.r + 0.587 * color.g + 0.114 * color.b

## Check if GPU compute mode is available before enabling use_compute_mode.
## Returns true if GPU compute is available, false otherwise.
## Call this method before setting use_compute_mode = true to avoid errors.
func check_gpu_availability() -> bool:
	if _manager == null:
		return false
	
	if not _manager.has_method("is_gpu_compute_available"):
		return false
	
	return _manager.call("is_gpu_compute_available")

var _scene: Node3D
var _sub_viewport: SubViewport
var _manager: Node
var _sensor_id: int = -1

func _ready():
	if Engine.is_editor_hint():
		return

	_scene = preload("res://addons/light_sensor_3d/light_sensor_scene.tscn").instantiate() as Node3D
	add_child(_scene)
	
	_sub_viewport = _scene.get_node("SubViewport") as SubViewport
	var camera := _scene.get_node("SubViewport/Camera3D") as Camera3D
	var sensor_mesh := _scene.get_node("SubViewport/Camera3D/SensorMesh") as MeshInstance3D

	camera.cull_mask = layer
	sensor_mesh.layers = layer
	
	# Optional: size the subviewport based on sample_resolution if reasonable
	if sample_resolution == 1:
		_sub_viewport.size = Vector2i(1, 1)
	elif sample_resolution == 4:
		_sub_viewport.size = Vector2i(4, 4)
	elif sample_resolution == 8:
		_sub_viewport.size = Vector2i(8, 8)

	# Disable continuous updates; we flip to UPDATE_ONCE during refresh()
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	
	var debug_sprite := _scene.get_node("DebugViewportSprite") as Sprite3D
	debug_sprite.visible = enable_subviewport_debug
	
	# Try to locate the compute manager autoload and register
	_manager = get_node_or_null("/root/LightSensorComputeManager")
	
	# Fallback: try to find the manager in the scene tree if autoload failed
	if _manager == null:
		_manager = get_tree().get_first_node_in_group("light_sensor_compute_manager")
		if _manager == null:
			# Try to find any node with the compute manager script
			var all_nodes := get_tree().get_nodes_in_group("")
			for node in all_nodes:
				if node.get_script() != null and node.get_script().get_path().ends_with("light_sensor_compute_manager.gd"):
					_manager = node
					break
	
	if _manager != null and _manager.has_method("register_sensor"):
		_sensor_id = _manager.call("register_sensor", self)
		if _manager.has_signal("sensor_result_ready"):
			_manager.connect("sensor_result_ready", Callable(self, "_on_sensor_result_ready"))
		
		# Check if GPU compute is available when use_compute_mode is enabled
		if use_compute_mode:
			_check_gpu_availability_strict()
	else:
		if use_compute_mode:
			push_warning("LightSensor3D: GPU compute mode enabled but LightSensorComputeManager not found. Check autoload configuration in Project Settings > AutoLoad.")
	
	if print_timing_information:
		print_debug(get_path(), ": This LightSensor3D is configured to print out timing information.")

## Recalculates the light/color affecting this probe.
func refresh() -> void:
	if use_compute_mode:
		# GPU compute mode is explicitly requested - must be available
		if _manager == null:
			push_error("LightSensor3D: GPU compute mode enabled but LightSensorComputeManager not found. Check autoload configuration in Project Settings > AutoLoad.")
			return
		
		if _sensor_id < 0:
			push_error("LightSensor3D: GPU compute mode enabled but sensor not registered. Check sensor initialization.")
			return
		
		if not _manager.has_method("enqueue_refresh"):
			push_error("LightSensor3D: GPU compute mode enabled but compute manager missing enqueue_refresh method. Check compute manager initialization.")
			return
		
		if not _manager.has_method("is_gpu_compute_available") or not _manager.call("is_gpu_compute_available"):
			var debug_status := ""
			if _manager.has_method("get_debug_status"):
				debug_status = "\n" + _manager.call("get_debug_status")
			push_error("LightSensor3D: GPU compute mode enabled but GPU compute is not available. Check GPU compatibility and call check_gpu_availability() before enabling use_compute_mode." + debug_status)
			return
		
		# GPU compute is available - proceed with GPU path
		_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		call_deferred("_enqueue_compute")
		return
	
	# CPU fallback removed - GPU compute is required when use_compute_mode is enabled
	push_error("LightSensor3D: CPU fallback removed. GPU compute is required when use_compute_mode is enabled.")

func _enqueue_compute() -> void:
	if _manager == null or _sensor_id < 0:
		return
	# Wait one frame to ensure the SubViewport has rendered after UPDATE_ONCE
	await get_tree().process_frame
	var texture: Texture2D = _sub_viewport.get_texture()
	if texture != null:
		_manager.call("enqueue_refresh", _sensor_id, texture)

func _on_sensor_result_ready(id: int, result_color: Color) -> void:
	if id != _sensor_id:
		return
	if not color.is_equal_approx(result_color):
		color = result_color
		color_updated.emit(color)
		light_level_updated.emit(light_level)

func _check_gpu_availability_strict() -> void:
	if _manager == null:
		push_error("LightSensor3D: GPU compute mode enabled but LightSensorComputeManager not found. Check autoload configuration in Project Settings > AutoLoad.")
		return
	
	# Check if the manager has GPU compute available
	if not _manager.has_method("is_gpu_compute_available"):
		push_error("LightSensor3D: GPU compute mode enabled but compute manager missing is_gpu_compute_available method. Check compute manager initialization.")
		return
	
	var gpu_available := _manager.call("is_gpu_compute_available")
	if not gpu_available:
		var debug_status := ""
		if _manager.has_method("get_debug_status"):
			debug_status = "\n" + _manager.call("get_debug_status")
		push_error("LightSensor3D: GPU compute mode enabled but GPU compute is not available. Check GPU compatibility and call check_gpu_availability() before enabling use_compute_mode." + debug_status)
		return
	
	# Check if the manager has the required methods for GPU compute
	if not _manager.has_method("enqueue_refresh"):
		push_error("LightSensor3D: GPU compute mode enabled but compute manager is not properly initialized. Missing enqueue_refresh method.")
		return
	
	# Check if sensor was successfully registered
	if _sensor_id < 0:
		push_error("LightSensor3D: GPU compute mode enabled but sensor registration failed. sensor_id: " + str(_sensor_id))
		return

func _exit_tree():
	# Clean up sensor registration when node is removed
	if _manager != null and _sensor_id >= 0 and _manager.has_method("unregister_sensor"):
		_manager.call("unregister_sensor", _sensor_id)
		_sensor_id = -1

func _get_configuration_warnings():
	if layer == 0:
		return ["LightProbe won't work without a layer configured"]
	return []
