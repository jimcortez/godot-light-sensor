extends Node3D

## Configurable grid of light sensors for benchmarking
## Creates a grid of LightSensor3D nodes and manages their refresh cycles

signal refresh_completed(refresh_time: float)
signal refresh_cycle_started()

@export var grid_size: int = 2  # Default to 2x2, will be overridden by benchmark controller
@export var sensor_spacing: float = 0.2
@export var sensor_height: float = 0.1

# Sensor management
var sensors: Array[Node] = []
var refresh_timer: Timer
var is_refreshing: bool = false
var pending_refreshes: int = 0
var completed_refreshes: int = 0
var refresh_start_time: float = 0.0
var individual_refresh_times: Array[float] = []
var refresh_timeout_timer: Timer

# Configuration
var use_gpu_mode: bool = false
var current_refresh_interval: float = 0.1  # Default 10 Hz (0.1s interval)

func _ready():
	create_sensor_grid()
	setup_refresh_timer()

func create_sensor_grid():
	# Clear existing sensors synchronously
	for child in get_children():
		if child.name.begins_with("Sensor_"):
			child.queue_free()
	# Wait for cleanup to complete
	await get_tree().process_frame
	sensors.clear()
	
	# Create new sensor grid
	var half_size = (grid_size - 1) * sensor_spacing * 0.5
	
	for x in range(grid_size):
		for z in range(grid_size):
			var sensor_pos = Vector3(
				(x * sensor_spacing) - half_size,
				sensor_height,
				(z * sensor_spacing) - half_size
			)
			
			create_sensor_at_position(sensor_pos, x, z)

func create_sensor_at_position(position: Vector3, grid_x: int, grid_z: int):
	# Create sensor node
	var sensor_node = Node3D.new()
	sensor_node.name = "Sensor_" + str(grid_x) + "_" + str(grid_z)
	sensor_node.position = position
	add_child(sensor_node)
	
	# Debug: Print sensor position
	# print("Sensor " + str(grid_x) + "_" + str(grid_z) + " at: " + str(position))
	# print("Sensor grid center: " + str(Vector3(0, 0.1, 0)))
	
	# Create light sensor
	var light_sensor = preload("res://addons/light_sensor_3d/light_sensor_3d.gd").new()
	light_sensor.name = "LightSensor3D"
	light_sensor.layer = 3  # Match the light layer
	light_sensor.use_compute_mode = use_gpu_mode
	light_sensor.sample_resolution = 8
	# print("Creating sensor " + str(grid_x) + "_" + str(grid_z) + " with GPU mode: " + str(use_gpu_mode) + " on layer " + str(light_sensor.layer))
	sensor_node.add_child(light_sensor)
	
	# Connect signals with sensor reference
	# Use values_refreshed for completion tracking (always emitted) and color_updated for color changes
	var values_connection = light_sensor.connect("values_refreshed", Callable(self, "_on_sensor_values_refreshed").bind(light_sensor))
	var color_connection = light_sensor.connect("color_updated", Callable(self, "_on_sensor_color_updated").bind(light_sensor))
	var light_connection = light_sensor.connect("light_level_updated", Callable(self, "_on_sensor_light_updated").bind(light_sensor))
	
	if values_connection != OK:
		print("WARNING: Failed to connect values_refreshed signal for sensor " + str(grid_x) + "_" + str(grid_z))
	if color_connection != OK:
		print("WARNING: Failed to connect color_updated signal for sensor " + str(grid_x) + "_" + str(grid_z))
	if light_connection != OK:
		print("WARNING: Failed to connect light_level_updated signal for sensor " + str(grid_x) + "_" + str(grid_z))
	
	sensors.append(light_sensor)
	

func setup_refresh_timer():
	refresh_timer = Timer.new()
	refresh_timer.name = "RefreshTimer"
	refresh_timer.wait_time = current_refresh_interval
	refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	add_child(refresh_timer)
	
	# Setup timeout timer for refresh cycles
	refresh_timeout_timer = Timer.new()
	refresh_timeout_timer.name = "RefreshTimeoutTimer"
	refresh_timeout_timer.wait_time = 2.0  # 2 second timeout
	refresh_timeout_timer.one_shot = true
	refresh_timeout_timer.timeout.connect(_on_refresh_timeout)
	add_child(refresh_timeout_timer)

func configure_sensors(use_gpu: bool):
	use_gpu_mode = use_gpu
	
	# Recreate the sensor grid with the new mode
	# This ensures clean initialization without dynamic mode switching issues
	# print("Recreating sensor grid for " + ("GPU" if use_gpu_mode else "CPU") + " mode")
	await create_sensor_grid()

func set_refresh_rate(interval: float):
	"""Set the refresh rate for the sensor grid
	@param interval: Time interval in seconds between refresh cycles
	"""
	current_refresh_interval = interval
	
	if refresh_timer:
		refresh_timer.wait_time = current_refresh_interval
		print("Sensor grid refresh rate set to: " + str(current_refresh_interval) + "s (" + str(1.0 / current_refresh_interval) + " FPS)")
	
	return current_refresh_interval

func set_grid_size(new_size: int):
	"""Set the grid size and recreate the sensor grid
	
	Args:
		new_size: New grid size (will create new_size x new_size grid)
	"""
	if new_size != grid_size:
		grid_size = new_size
		print("Recreating sensor grid with size: " + str(grid_size) + "x" + str(grid_size))
		await create_sensor_grid()

func start_refresh_cycle():
	if refresh_timer:
		refresh_timer.start()

func stop_refresh_cycle():
	if refresh_timer:
		refresh_timer.stop()
	
	# Reset refresh state
	is_refreshing = false
	pending_refreshes = 0
	completed_refreshes = 0

func _on_refresh_timer_timeout():
	if is_refreshing:
		return  # Wait for previous refresh to complete
	
	start_refresh_cycle_batch()

func start_refresh_cycle_batch():
	is_refreshing = true
	pending_refreshes = sensors.size()
	completed_refreshes = 0
	refresh_start_time = Time.get_unix_time_from_system()
	individual_refresh_times.clear()
	
	# Emit signal that refresh cycle has started
	emit_signal("refresh_cycle_started")
	
	# Start timeout timer
	refresh_timeout_timer.start()
	
	# Start refresh for all sensors with individual timing
	for i in range(sensors.size()):
		var sensor = sensors[i]
		if sensor.has_method("refresh"):
			# Store the start time for this individual sensor
			var start_time = Time.get_unix_time_from_system()
			sensor.set_meta("refresh_start_time", start_time)
			sensor.refresh()
		else:
			print("Sensor " + str(i) + " does not have refresh method")

func _on_sensor_values_refreshed(color: Color, light_level: float, sensor: Node):
	# This is called when a sensor completes its refresh (always emitted)
	completed_refreshes += 1
	
	# Calculate individual sensor refresh time (only during active refresh cycles)
	if is_refreshing and sensor and sensor.has_meta("refresh_start_time"):
		var start_time = sensor.get_meta("refresh_start_time")
		var end_time = Time.get_unix_time_from_system()
		var individual_time = end_time - start_time
		individual_refresh_times.append(individual_time)
		sensor.remove_meta("refresh_start_time")
	elif is_refreshing:
		# Sensor signal received but no start time found - this can happen in GPU mode
		# where sensors emit initial values_refreshed signals after registration
		pass
	# If not refreshing, this is just an initial sensor setup - ignore timing
	
	# Check if all sensors have completed
	if completed_refreshes >= pending_refreshes:
		complete_refresh_cycle()

func _on_sensor_color_updated(color: Color, sensor: Node):
	# This is called when a sensor's color actually changes
	# We don't handle completion here anymore - use _on_sensor_values_refreshed
	pass

func _on_sensor_light_updated(light_level: float, sensor: Node):
	# This is called when a sensor's light level actually changes
	# We don't handle completion here anymore - use _on_sensor_values_refreshed
	pass

func _on_refresh_timeout():
	print("WARNING: Refresh cycle timed out after 2 seconds")
	if is_refreshing:
		# Force completion with estimated times
		var estimated_time = 0.1  # Default 100ms per sensor
		for i in range(pending_refreshes - completed_refreshes):
			individual_refresh_times.append(estimated_time)
		complete_refresh_cycle()

func get_sensors() -> Array:
	return sensors

func complete_refresh_cycle():
	# Stop timeout timer
	refresh_timeout_timer.stop()
	
	var refresh_end_time = Time.get_unix_time_from_system()
	var refresh_duration = refresh_end_time - refresh_start_time
	
	# Calculate average individual refresh time
	var avg_individual_time = 0.0
	if individual_refresh_times.size() > 0:
		avg_individual_time = individual_refresh_times.reduce(func(a, b): return a + b) / individual_refresh_times.size()
	else:
		# Use fallback timing if individual times aren't available
		avg_individual_time = refresh_duration / pending_refreshes if pending_refreshes > 0 else 0.0
	
	# Emit signal with average individual refresh timing (more accurate)
	emit_signal("refresh_completed", avg_individual_time)
	
	# Reset state
	is_refreshing = false
	pending_refreshes = 0
	completed_refreshes = 0
	individual_refresh_times.clear()

func get_sensor_count() -> int:
	return sensors.size()

func get_sensor_data() -> Array:
	var data = []
	for sensor in sensors:
		if sensor.has_method("get"):
			var color = sensor.get("color")
			var light_level = sensor.get("light_level")
			data.append({
				"color": color,
				"light_level": light_level
			})
	return data
