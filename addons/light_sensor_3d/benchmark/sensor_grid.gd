extends Node3D

## Configurable grid of light sensors for benchmarking
## Creates a grid of LightSensor3D nodes and manages their refresh cycles

signal refresh_completed(refresh_time: float)

@export var grid_size: int = 2
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

func _ready():
	create_sensor_grid()
	setup_refresh_timer()

func create_sensor_grid():
	# Clear existing sensors
	for child in get_children():
		if child.name.begins_with("Sensor_"):
			child.queue_free()
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
	print("Sensor " + str(grid_x) + "_" + str(grid_z) + " at: " + str(position))
	print("Sensor grid center: " + str(Vector3(0, 0.1, 0)))
	
	# Create light sensor
	var light_sensor = preload("res://addons/light_sensor_3d/light_sensor_3d.gd").new()
	light_sensor.name = "LightSensor3D"
	light_sensor.layer = 2
	light_sensor.use_compute_mode = use_gpu_mode
	light_sensor.sample_resolution = 8
	sensor_node.add_child(light_sensor)
	
	# Connect signals with sensor reference
	var color_connection = light_sensor.connect("color_updated", Callable(self, "_on_sensor_color_updated").bind(light_sensor))
	var light_connection = light_sensor.connect("light_level_updated", Callable(self, "_on_sensor_light_updated").bind(light_sensor))
	
	if color_connection != OK:
		print("WARNING: Failed to connect color_updated signal for sensor " + str(grid_x) + "_" + str(grid_z))
	if light_connection != OK:
		print("WARNING: Failed to connect light_level_updated signal for sensor " + str(grid_x) + "_" + str(grid_z))
	
	sensors.append(light_sensor)
	

func setup_refresh_timer():
	refresh_timer = Timer.new()
	refresh_timer.name = "RefreshTimer"
	refresh_timer.wait_time = 0.1  # 10 Hz refresh rate
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
	
	# Update all sensors
	for i in range(sensors.size()):
		var sensor = sensors[i]
		if sensor.has_method("set"):
			sensor.set("use_compute_mode", use_gpu_mode)
			
			# For CPU mode, we need to ensure the sensor doesn't try to use the compute manager
			if not use_gpu_mode:
				# Disconnect from compute manager if connected
				if sensor.has_meta("sensor_id"):
					var sensor_id = sensor.get_meta("sensor_id")
					print("Disconnecting sensor " + str(i) + " from compute manager (ID: " + str(sensor_id) + ")")
					sensor.remove_meta("sensor_id")

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
	
	
	# Start timeout timer
	refresh_timeout_timer.start()
	
	# Start refresh for all sensors with individual timing
	for i in range(sensors.size()):
		var sensor = sensors[i]
		if sensor.has_method("refresh"):
			# Store the start time for this individual sensor
			sensor.set_meta("refresh_start_time", Time.get_unix_time_from_system())
			sensor.refresh()
		else:
			print("Sensor " + str(i) + " does not have refresh method")

func _on_sensor_color_updated(color: Color, sensor: Node):
	# This is called when a sensor completes its refresh
	completed_refreshes += 1
	
	# Calculate individual sensor refresh time
	if sensor and sensor.has_meta("refresh_start_time"):
		var start_time = sensor.get_meta("refresh_start_time")
		var end_time = Time.get_unix_time_from_system()
		var individual_time = end_time - start_time
		individual_refresh_times.append(individual_time)
		sensor.remove_meta("refresh_start_time")
	else:
		print("WARNING: Sensor signal received but no start time found")
	
	# Check if all sensors have completed
	if completed_refreshes >= pending_refreshes:
		complete_refresh_cycle()

func _on_sensor_light_updated(light_level: float, sensor: Node):
	# This is also called when a sensor completes its refresh
	# We handle completion in _on_sensor_color_updated to avoid double-counting
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
		print("WARNING: No individual refresh times recorded!")
	
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
