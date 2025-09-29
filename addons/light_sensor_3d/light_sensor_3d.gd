@icon("res://addons/light_sensor_3d/icon.png")
@tool
class_name LightSensor3D extends Node3D

## Emitted when the color the sensor observes has changed (after refresh()).
## Only emitted when the color actually changes.
signal color_updated(color: Color)

## Emitted when the light level the sensor observes has changed (after refresh()).
## Only emitted when the light level actually changes.
## Ranges from 0 (pitch dark) to 1 (bright as the sun).
signal light_level_updated(luminance: float)

## Emitted whenever the sensor values are refreshed, regardless of whether they changed.
## Useful for benchmarking and monitoring refresh cycles.
signal values_refreshed(color: Color, luminance: float)

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
	
	# Set SubViewport size based on sample_resolution
	_sub_viewport.size = Vector2i(sample_resolution, sample_resolution)
	# print("LightSensor3D: Set SubViewport size to " + str(_sub_viewport.size) + " for sample_resolution " + str(sample_resolution))
	
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
	
	# Only register with compute manager if GPU compute mode is enabled
	if use_compute_mode and _manager != null and _manager.has_method("register_sensor"):
		_sensor_id = _manager.call("register_sensor", self)
		if _manager.has_signal("sensor_result_ready"):
			_manager.connect("sensor_result_ready", Callable(self, "_on_sensor_result_ready"))
		
		# Check if GPU compute is available when use_compute_mode is enabled
		_check_gpu_availability_strict()
	elif use_compute_mode:
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
	
	# CPU fallback implementation
	_sub_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	call_deferred("_cpu_refresh")

func _cpu_refresh() -> void:
	# Wait one frame to ensure the SubViewport has rendered after UPDATE_ONCE
	await get_tree().process_frame
	var t_start = Time.get_ticks_usec()
	var texture := _sub_viewport.get_texture()
	var image := texture.get_image() # this one's a doozy
	
	# Next, we want to get every pixel and average their colors.
	# Presumably calling get_data() once is faster than get_pixel() many times.
	var color_data := image.get_data()
	var color_data_size := color_data.size()
	assert(color_data_size % 3 == 0, "Expected 3 channels per pixel")

	# Sum all the values for each channel separately.
	var average_color_array := [0, 0, 0]
	for i in color_data.size():
		average_color_array[i % 3] += color_data.decode_u8(i)
	
	# Finally, convert the sums of rgb values into the average color.
	var pixel_count := color_data.size() / 3.0
	var average_color := Color(
		average_color_array[0] / pixel_count / 255,
		average_color_array[1] / pixel_count / 255,
		average_color_array[2] / pixel_count / 255,
	)
	
	var t_end := Time.get_ticks_usec()
	if print_timing_information:
		print(get_path(), " (a LightSensor3D) took %.2fms to refresh" % ((t_end - t_start) / 1000.0))
	
	# Store previous values to check for changes
	var previous_color = color
	var previous_light_level = light_level
	
	# Update the color
	color = average_color
	
	# Trigger updates if the color changed
	if not color.is_equal_approx(previous_color):
		color_updated.emit(color)
		light_level_updated.emit(light_level)
	
	# Always emit refresh signal for benchmarking (regardless of color change)
	values_refreshed.emit(color, light_level)



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
	
	# Store previous values to check for changes
	var previous_color = color
	var previous_light_level = light_level
	
	# Update cached values
	color = result_color
	var new_light_level = light_level  # This will use the getter
	
	# Emit change signals only if values actually changed
	if not color.is_equal_approx(previous_color):
		color_updated.emit(color)
	
	if not is_equal_approx(new_light_level, previous_light_level):
		light_level_updated.emit(new_light_level)
	
	# Always emit refresh signal for benchmarking
	values_refreshed.emit(color, new_light_level)

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
