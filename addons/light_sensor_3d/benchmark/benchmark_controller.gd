extends Node

## Main controller for the Light Sensor 3D benchmark system
## Manages test execution, FPS monitoring, and result collection

signal test_started(test_type: String)
signal test_completed(test_type: String, results: Dictionary)
signal test_progress(progress: float, status: String)

# Test configuration
@export var test_duration: float = 10.0
@export var grid_size: int = 2
@export var color_cycle_speed: float = 1.0
@export var target_fps_threshold: float = 55.0

# Test state
var is_testing: bool = false
var current_test_type: String = ""
var is_batch_test: bool = false
var test_start_time: float = 0.0
var test_end_time: float = 0.0
var test_start_time_precise: float = 0.0

# FPS monitoring
var fps_samples: Array[float] = []
var max_fps: float = 0.0
var min_fps: float = 999.0
var avg_fps: float = 0.0

# Refresh timing
var refresh_times: Array[float] = []
var refresh_frequency: float = 0.0
var max_refresh_frequency: float = 0.0

# Color detection tracking
var detected_colors: Array[Color] = []
var has_detected_non_black: bool = false

# Node references
var sensor_grid: Node3D
var color_cycling_light: Node3D
var results_ui: Control
var status_label: Label
var fps_label: Label
var progress_bar: ProgressBar
var results_text: RichTextLabel

# Test results storage
var test_results: Dictionary = {}

func _ready():
	# Get node references
	sensor_grid = get_node("../SensorGrid")
	color_cycling_light = get_node("../ColorCyclingLight")
	results_ui = get_node("BenchmarkResults")
	
	# Get UI references
	status_label = results_ui.get_node("VBoxContainer/StatusLabel")
	fps_label = results_ui.get_node("VBoxContainer/FPSLabel")
	progress_bar = results_ui.get_node("VBoxContainer/ProgressBar")
	results_text = results_ui.get_node("VBoxContainer/ResultsText")
	
	# Initialize UI
	update_status("Ready")
	update_fps_display(0)
	update_progress_bar(0.0)
	
	# Connect to sensor grid signals
	if sensor_grid.has_signal("refresh_completed"):
		sensor_grid.connect("refresh_completed", Callable(self, "_on_sensor_refresh_completed"))
	
	# Connect to individual sensor color signals for color detection tracking
	_connect_sensor_color_signals()

func _process(delta):
	if is_testing:
		# Monitor FPS
		var current_fps = Engine.get_frames_per_second()
		fps_samples.append(current_fps)
		max_fps = max(max_fps, current_fps)
		min_fps = min(min_fps, current_fps)
		
		# Update UI
		update_fps_display(current_fps)
		
		# Update progress bar using more precise timing
		var current_time_precise = Time.get_ticks_msec() / 1000.0
		var elapsed = current_time_precise - test_start_time_precise
		var progress = (elapsed / test_duration) * 100.0
		progress = clamp(progress, 0.0, 100.0)
		update_progress_bar(progress)
		
		# Check if test should end (with small buffer to account for frame timing)
		if elapsed >= test_duration:
			print("Test duration reached: " + str(elapsed) + "s (target: " + str(test_duration) + "s)")
			complete_test()

func start_cpu_test():
	if is_testing:
		return
	
	print("Starting CPU benchmark test...")
	is_batch_test = false
	start_test("CPU")

func start_gpu_test():
	if is_testing:
		return
	
	print("Starting GPU benchmark test...")
	is_batch_test = false
	start_test("GPU")

func start_batch_test():
	if is_testing:
		return
	
	print("Starting batch benchmark test...")
	is_batch_test = true
	start_test("CPU")  # Start with CPU for batch test

func start_test(test_type: String):
	is_testing = true
	current_test_type = test_type
	test_start_time = Time.get_unix_time_from_system()
	test_start_time_precise = Time.get_ticks_msec() / 1000.0  # More precise timing
	
	print("Starting " + test_type + " test with duration: " + str(test_duration) + "s")
	
	# Reset test data
	fps_samples.clear()
	refresh_times.clear()
	max_fps = 0.0
	min_fps = 999.0
	refresh_frequency = 0.0
	max_refresh_frequency = 0.0
	
	# Reset color detection tracking
	detected_colors.clear()
	has_detected_non_black = false
	
	# Configure sensors based on test type
	if test_type == "CPU":
		configure_sensors_for_cpu()
	elif test_type == "GPU":
		configure_sensors_for_gpu()
	elif test_type == "BATCH":
		# For batch test, start with CPU
		configure_sensors_for_cpu()
		current_test_type = "CPU"  # Will switch to GPU after CPU completes
	
	# Start the test
	update_status("Running " + current_test_type + " test...")
	emit_signal("test_started", current_test_type)
	
	# Start sensor refresh cycle
	start_sensor_refresh_cycle()

func configure_sensors_for_cpu():
	# Configure all sensors to use CPU mode
	if sensor_grid:
		sensor_grid.configure_sensors(false)  # false = CPU mode

func configure_sensors_for_gpu():
	# Configure all sensors to use GPU mode
	if sensor_grid:
		sensor_grid.configure_sensors(true)  # true = GPU mode

func start_sensor_refresh_cycle():
	# Start continuous refresh cycle for all sensors
	if sensor_grid:
		sensor_grid.start_refresh_cycle()

func complete_test():
	if not is_testing:
		return
	
	test_end_time = Time.get_unix_time_from_system()
	var test_duration_actual = test_end_time - test_start_time
	
	print("Test completed. Actual duration: " + str(test_duration_actual) + "s (target: " + str(test_duration) + "s)")
	
	# Calculate results
	var results = calculate_test_results()
	
	# Store results
	test_results[current_test_type] = results
	
	# Update UI
	update_status("Test completed: " + current_test_type)
	display_results(results)
	
	# Emit signal
	emit_signal("test_completed", current_test_type, results)
	
	# Check if this was part of a batch test
	if is_batch_test and current_test_type == "CPU" and test_results.has("CPU") and not test_results.has("GPU"):
		# Switch to GPU test for batch test
		print("CPU test completed, starting GPU test...")
		await get_tree().create_timer(1.0).timeout  # Brief pause between tests
		start_test("GPU")
		return
	
	# Test is complete
	is_testing = false
	current_test_type = ""
	is_batch_test = false
	
	# Stop sensor refresh cycle
	if sensor_grid:
		sensor_grid.stop_refresh_cycle()

func calculate_test_results() -> Dictionary:
	var results = {}
	
	# FPS statistics
	if fps_samples.size() > 0:
		avg_fps = fps_samples.reduce(func(a, b): return a + b) / fps_samples.size()
		results["avg_fps"] = avg_fps
		results["max_fps"] = max_fps
		results["min_fps"] = min_fps
		results["fps_samples"] = fps_samples.size()
	
	# Refresh timing
	if refresh_times.size() > 0:
		var avg_refresh_time = refresh_times.reduce(func(a, b): return a + b) / refresh_times.size()
		results["avg_refresh_time"] = avg_refresh_time
		results["max_refresh_time"] = refresh_times.max()
		results["min_refresh_time"] = refresh_times.min()
		results["refresh_count"] = refresh_times.size()
	
	# Performance metrics
	results["max_refresh_frequency"] = max_refresh_frequency
	results["test_duration"] = test_end_time - test_start_time
	results["sensor_count"] = grid_size * grid_size
	
	# Color detection validation
	results["color_detection_success"] = has_detected_non_black
	results["detected_colors_count"] = detected_colors.size()
	results["non_black_colors_detected"] = has_detected_non_black
	
	return results

func display_results(results: Dictionary):
	var text = "[b]Test Results: " + current_test_type + "[/b]\n\n"
	
	text += "[b]FPS Statistics:[/b]\n"
	text += "Average FPS: " + str(round(results.get("avg_fps", 0) * 100) / 100) + "\n"
	text += "Max FPS: " + str(round(results.get("max_fps", 0) * 100) / 100) + "\n"
	text += "Min FPS: " + str(round(results.get("min_fps", 0) * 100) / 100) + "\n"
	text += "Samples: " + str(results.get("fps_samples", 0)) + "\n\n"
	
	text += "[b]Refresh Performance:[/b]\n"
	text += "Average Refresh Time: " + str(round(results.get("avg_refresh_time", 0) * 1000) / 1000) + "s\n"
	text += "Max Refresh Time: " + str(round(results.get("max_refresh_time", 0) * 1000) / 1000) + "s\n"
	text += "Min Refresh Time: " + str(round(results.get("min_refresh_time", 0) * 1000) / 1000) + "s\n"
	text += "Refresh Count: " + str(results.get("refresh_count", 0)) + "\n"
	text += "Max Refresh Frequency: " + str(round(results.get("max_refresh_frequency", 0) * 100) / 100) + " Hz\n\n"
	
	# Color Detection Validation
	text += "[b]Color Detection:[/b]\n"
	var color_success = results.get("color_detection_success", false)
	var color_count = results.get("detected_colors_count", 0)
	if color_success:
		text += "✓ Colors detected: " + str(color_count) + " samples\n"
		text += "✓ Non-black colors: YES\n"
	else:
		text += "✗ Colors detected: " + str(color_count) + " samples\n"
		text += "✗ Non-black colors: NO (sensors may not be aligned with light)\n"
	text += "\n"
	
	text += "[b]Test Configuration:[/b]\n"
	text += "Sensor Grid: " + str(results.get("sensor_count", 0)) + " sensors (" + str(grid_size) + "x" + str(grid_size) + ")\n"
	text += "Test Duration: " + str(round(results.get("test_duration", 0) * 100) / 100) + "s\n"
	
	results_text.text = text
	
	# Log results to console
	log_results_to_console(results)

func _connect_sensor_color_signals():
	# Connect to all sensor color_updated signals to track color detection
	if sensor_grid and sensor_grid.has_method("get_sensors"):
		var sensors = sensor_grid.get_sensors()
		for sensor in sensors:
			if sensor and sensor.has_signal("color_updated"):
				sensor.connect("color_updated", Callable(self, "_on_sensor_color_detected"))

func _on_sensor_color_detected(color: Color):
	# Track detected colors and check for non-black colors
	detected_colors.append(color)
	
	# Debug: Print all detected colors
	print("Sensor detected color: " + str(color))
	
	# Check if this is a non-black color (not pure black)
	if color.r > 0.01 or color.g > 0.01 or color.b > 0.01:
		has_detected_non_black = true
		print("✓ Color detected: " + str(color) + " (non-black)")
	else:
		print("✗ Color detected: " + str(color) + " (black)")

func _on_sensor_refresh_completed(refresh_time: float):
	refresh_times.append(refresh_time)
	
	# Calculate refresh frequency using current time
	if refresh_times.size() > 1:
		var current_time = Time.get_ticks_msec() / 1000.0
		var time_diff = current_time - test_start_time_precise
		if time_diff > 0:
			refresh_frequency = refresh_times.size() / time_diff
			max_refresh_frequency = max(max_refresh_frequency, refresh_frequency)

func update_status(status: String):
	if status_label:
		status_label.text = "Status: " + status

func update_fps_display(fps: float):
	if fps_label:
		fps_label.text = "FPS: " + str(round(fps))

func update_progress_bar(progress: float):
	if progress_bar:
		progress_bar.value = progress

func set_test_duration(duration: float):
	test_duration = duration
	print("Test duration set to: " + str(test_duration) + "s")

func log_results_to_console(results: Dictionary):
	print("============================================================")
	print("LIGHT SENSOR 3D BENCHMARK RESULTS - " + current_test_type + " MODE")
	print("============================================================")
	
	# FPS Statistics
	print("\nFPS STATISTICS:")
	print("  Average FPS: " + str(round(results.get("avg_fps", 0) * 100) / 100))
	print("  Max FPS: " + str(round(results.get("max_fps", 0) * 100) / 100))
	print("  Min FPS: " + str(round(results.get("min_fps", 0) * 100) / 100))
	print("  FPS Samples: " + str(results.get("fps_samples", 0)))
	
	# Refresh Performance
	print("\nREFRESH PERFORMANCE:")
	print("  Average Refresh Time: " + str(round(results.get("avg_refresh_time", 0) * 1000) / 1000) + "s")
	print("  Max Refresh Time: " + str(round(results.get("max_refresh_time", 0) * 1000) / 1000) + "s")
	print("  Min Refresh Time: " + str(round(results.get("min_refresh_time", 0) * 1000) / 1000) + "s")
	print("  Refresh Count: " + str(results.get("refresh_count", 0)))
	print("  Max Refresh Frequency: " + str(round(results.get("max_refresh_frequency", 0) * 100) / 100) + " Hz")
	
	# Color Detection Validation
	print("\nCOLOR DETECTION:")
	var color_success = results.get("color_detection_success", false)
	var color_count = results.get("detected_colors_count", 0)
	if color_success:
		print("  ✓ Colors detected: " + str(color_count) + " samples")
		print("  ✓ Non-black colors: YES")
	else:
		print("  ✗ Colors detected: " + str(color_count) + " samples")
		print("  ✗ Non-black colors: NO (sensors may not be aligned with light)")
	
	# Test Configuration
	print("\nTEST CONFIGURATION:")
	print("  Sensor Grid: " + str(results.get("sensor_count", 0)) + " sensors (" + str(grid_size) + "x" + str(grid_size) + ")")
	print("  Test Duration: " + str(round(results.get("test_duration", 0) * 100) / 100) + "s")
	print("  Color Cycle Speed: " + str(color_cycle_speed) + "x")
	
	# Performance Assessment
	print("\nPERFORMANCE ASSESSMENT:")
	var avg_fps = results.get("avg_fps", 0)
	var max_refresh_freq = results.get("max_refresh_frequency", 0)
	var avg_refresh_time = results.get("avg_refresh_time", 0)
	
	if avg_fps >= 55:
		print("  ✓ FPS Performance: GOOD (Average FPS: " + str(round(avg_fps)) + ")")
	else:
		print("  ⚠ FPS Performance: BELOW TARGET (Average FPS: " + str(round(avg_fps)) + " < 55)")
	
	if max_refresh_freq >= 10:
		print("  ✓ Refresh Frequency: HIGH (" + str(round(max_refresh_freq * 100) / 100) + " Hz)")
	elif max_refresh_freq >= 5:
		print("  ⚠ Refresh Frequency: MEDIUM (" + str(round(max_refresh_freq * 100) / 100) + " Hz)")
	else:
		print("  ✗ Refresh Frequency: LOW (" + str(round(max_refresh_freq * 100) / 100) + " Hz)")
	
	if avg_refresh_time <= 0.1:
		print("  ✓ Refresh Speed: FAST (" + str(round(avg_refresh_time * 1000) / 1000) + "s)")
	elif avg_refresh_time <= 0.5:
		print("  ⚠ Refresh Speed: MODERATE (" + str(round(avg_refresh_time * 1000) / 1000) + "s)")
	else:
		print("  ✗ Refresh Speed: SLOW (" + str(round(avg_refresh_time * 1000) / 1000) + "s)")
	
	print("============================================================")

func reset_test():
	is_testing = false
	current_test_type = ""
	is_batch_test = false
	test_results.clear()
	
	# Reset UI
	update_status("Ready")
	update_fps_display(0)
	update_progress_bar(0.0)
	results_text.text = "Results will appear here..."
	
	# Stop sensor refresh cycle
	if sensor_grid:
		sensor_grid.stop_refresh_cycle()
	
	print("Test reset")
