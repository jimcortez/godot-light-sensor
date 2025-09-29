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

# Outgoing FPS measurement
var outgoing_fps_samples: Array[float] = []
var outgoing_fps_frequency: float = 0.0
var max_outgoing_fps: float = 0.0
var refresh_call_count: int = 0
var values_refreshed_count: int = 0
var outgoing_fps_start_time: float = 0.0

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
	
	# Note: Individual sensor signals will be connected after sensors are created in configure_sensors

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
	await start_test("CPU")

func start_gpu_test():
	if is_testing:
		return
	
	print("Starting GPU benchmark test...")
	is_batch_test = false
	await start_test("GPU")

func start_batch_test():
	if is_testing:
		return
	
	print("Starting batch benchmark test...")
	is_batch_test = true
	await start_test("GPU")  # Start with GPU for batch test

func start_test(test_type: String):
	is_testing = true
	current_test_type = test_type
	test_start_time = Time.get_unix_time_from_system()
	test_start_time_precise = Time.get_ticks_msec() / 1000.0  # More precise timing
	
	if is_batch_test:
		print("============================================================")
		print("BATCH TEST PHASE: Starting " + test_type + " test")
		print("Duration: " + str(test_duration) + "s")
		print("============================================================")
	else:
		print("Starting " + test_type + " test with duration: " + str(test_duration) + "s")
	
	# Reset test data
	fps_samples.clear()
	outgoing_fps_samples.clear()
	max_fps = 0.0
	min_fps = 999.0
	outgoing_fps_frequency = 0.0
	max_outgoing_fps = 0.0
	refresh_call_count = 0
	values_refreshed_count = 0
	
	# Reset color detection tracking
	detected_colors.clear()
	has_detected_non_black = false
	
	# Configure sensors based on test type
	if test_type == "CPU":
		await configure_sensors_for_cpu()
	elif test_type == "GPU":
		await configure_sensors_for_gpu()
	elif test_type == "BATCH":
		# For batch test, start with CPU
		await configure_sensors_for_cpu()
		current_test_type = "CPU"  # Will switch to GPU after CPU completes
	
	# Start the test
	update_status("Running " + current_test_type + " test...")
	emit_signal("test_started", current_test_type)
	
	# Start sensor refresh cycle
	start_sensor_refresh_cycle()

func configure_sensors_for_cpu():
	# Configure all sensors to use CPU mode
	if sensor_grid:
		await sensor_grid.configure_sensors(false)  # false = CPU mode

func configure_sensors_for_gpu():
	# Configure all sensors to use GPU mode
	if sensor_grid:
		await sensor_grid.configure_sensors(true)  # true = GPU mode

func start_sensor_refresh_cycle():
	# Start continuous refresh cycle for all sensors
	if sensor_grid:
		sensor_grid.start_refresh_cycle()
	
	# Start outgoing FPS measurement
	start_outgoing_fps_measurement()

func start_outgoing_fps_measurement():
	# Initialize outgoing FPS measurement
	outgoing_fps_start_time = Time.get_ticks_msec() / 1000.0
	refresh_call_count = 0
	values_refreshed_count = 0
	
	# Connect to sensor grid refresh signals to track outgoing FPS
	if sensor_grid:
		# Connect to refresh cycle start to count refresh calls
		if not sensor_grid.is_connected("refresh_cycle_started", Callable(self, "_on_refresh_cycle_started")):
			sensor_grid.connect("refresh_cycle_started", Callable(self, "_on_refresh_cycle_started"))
		
		# Connect to individual sensor signals (sensors should exist now)
		_connect_sensor_refresh_signals()
		_connect_sensor_color_signals()

func _connect_sensor_refresh_signals():
	# Connect to all sensor values_refreshed signals to track outgoing FPS
	if sensor_grid and sensor_grid.has_method("get_sensors"):
		var sensors = sensor_grid.get_sensors()
		for i in range(sensors.size()):
			var sensor = sensors[i]
			if sensor and sensor.has_signal("values_refreshed"):
				if not sensor.is_connected("values_refreshed", Callable(self, "_on_sensor_values_refreshed")):
					sensor.connect("values_refreshed", Callable(self, "_on_sensor_values_refreshed"))

func _on_refresh_cycle_started():
	# Count refresh calls (one per cycle for all sensors)
	refresh_call_count += 1

func _on_sensor_values_refreshed(color: Color, light_level: float):
	# Count values_refreshed events (one per sensor per cycle)
	values_refreshed_count += 1
	
	# Calculate outgoing FPS periodically
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed_time = current_time - outgoing_fps_start_time
	
	if elapsed_time > 0:
		# Calculate outgoing FPS based on refresh calls and responses
		# Each refresh cycle involves calling all sensors and waiting for all responses
		var outgoing_fps = refresh_call_count / elapsed_time
		outgoing_fps_samples.append(outgoing_fps)
		max_outgoing_fps = max(max_outgoing_fps, outgoing_fps)
		
		# Update outgoing FPS frequency
		outgoing_fps_frequency = outgoing_fps

func complete_test():
	if not is_testing:
		return
	
	test_end_time = Time.get_unix_time_from_system()
	var test_duration_actual = test_end_time - test_start_time
	
	if is_batch_test:
		print("============================================================")
		print("BATCH TEST PHASE: " + current_test_type + " test completed")
		print("Actual duration: " + str(test_duration_actual) + "s (target: " + str(test_duration) + "s)")
		print("============================================================")
	else:
		print("Test completed. Actual duration: " + str(test_duration_actual) + "s (target: " + str(test_duration) + "s)")
	
	# Calculate results
	var results = calculate_test_results()
	
	# Store results
	test_results[current_test_type] = results
	
	# Update UI
	update_status("Test completed: " + current_test_type)
	
	# For batch tests, only show brief status, not full results until both tests complete
	if is_batch_test:
		# Show brief status for individual test completion
		update_status("Batch test - " + current_test_type + " completed, preparing next phase...")
		# Don't display full results yet for batch tests
	else:
		# Show full results for individual tests
		display_results(results)
	
	# Emit signal
	emit_signal("test_completed", current_test_type, results)
	
	# Check if this was part of a batch test
	if is_batch_test and current_test_type == "GPU" and test_results.has("GPU") and not test_results.has("CPU"):
		# Switch to CPU test for batch test
		print("\nBATCH TEST TRANSITION: GPU test completed, preparing CPU test...")
		print("Brief pause before starting CPU test phase...")
		
		# Reset testing state before starting new test
		is_testing = false
		current_test_type = ""
		
		await get_tree().create_timer(1.0).timeout  # Brief pause between tests
		await start_test("CPU")
		return
	
	# Test is complete - only reset if not transitioning to another test
	is_testing = false
	current_test_type = ""
	
	# If this was a batch test, display the final comparison results
	if is_batch_test and test_results.has("GPU") and test_results.has("CPU"):
		print("Batch test completed - displaying final comparison results...")
		display_batch_comparison_results()
		is_batch_test = false
	elif not is_batch_test:
		# Only reset batch flag if not in a batch test
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
	
	# Outgoing FPS statistics
	if outgoing_fps_samples.size() > 0:
		var avg_outgoing_fps = outgoing_fps_samples.reduce(func(a, b): return a + b) / outgoing_fps_samples.size()
		results["avg_outgoing_fps"] = avg_outgoing_fps
		results["max_outgoing_fps"] = max_outgoing_fps
		results["min_outgoing_fps"] = outgoing_fps_samples.min()
		results["outgoing_fps_samples"] = outgoing_fps_samples.size()
	
	# Performance metrics
	results["outgoing_fps_frequency"] = outgoing_fps_frequency
	results["refresh_call_count"] = refresh_call_count
	results["values_refreshed_count"] = values_refreshed_count
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
	
	text += "[b]Outgoing FPS:[/b]\n"
	text += "Average Outgoing FPS: " + str(round(results.get("avg_outgoing_fps", 0) * 100) / 100) + "\n"
	text += "Max Outgoing FPS: " + str(round(results.get("max_outgoing_fps", 0) * 100) / 100) + "\n"
	text += "Min Outgoing FPS: " + str(round(results.get("min_outgoing_fps", 0) * 100) / 100) + "\n"
	text += "Outgoing FPS Samples: " + str(results.get("outgoing_fps_samples", 0)) + "\n"
	text += "Refresh Calls: " + str(results.get("refresh_call_count", 0)) + "\n"
	text += "Values Refreshed: " + str(results.get("values_refreshed_count", 0)) + "\n\n"
	
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

func display_batch_comparison_results():
	# Display final batch comparison results
	if test_results.has("GPU") and test_results.has("CPU"):
		var gpu_results = test_results["GPU"]
		var cpu_results = test_results["CPU"]
		
		# Use the results UI to display batch comparison
		if results_ui and results_ui.has_method("display_batch_results"):
			results_ui.display_batch_results(cpu_results, gpu_results)
		else:
			# Fallback: display basic comparison
			var text = "[b]Batch Test Results - GPU vs CPU Comparison[/b]\n\n"
			
			text += "[b]GPU Performance:[/b]\n"
			text += "Average FPS: " + str(round(gpu_results.get("avg_fps", 0) * 100) / 100) + "\n"
			text += "Average Outgoing FPS: " + str(round(gpu_results.get("avg_outgoing_fps", 0) * 100) / 100) + "\n\n"
			
			text += "[b]CPU Performance:[/b]\n"
			text += "Average FPS: " + str(round(cpu_results.get("avg_fps", 0) * 100) / 100) + "\n"
			text += "Average Outgoing FPS: " + str(round(cpu_results.get("avg_outgoing_fps", 0) * 100) / 100) + "\n\n"
			
			# Performance comparison
			var gpu_avg_fps = gpu_results.get("avg_fps", 0)
			var cpu_avg_fps = cpu_results.get("avg_fps", 0)
			if cpu_avg_fps > 0:
				var fps_ratio = gpu_avg_fps / cpu_avg_fps
				text += "[b]Performance Comparison:[/b]\n"
				text += "GPU is " + str(round(fps_ratio * 100) / 100) + "x " + ("faster" if fps_ratio > 1 else "slower") + " than CPU\n"
			
			results_text.text = text
		
		# Log batch comparison to console
		log_batch_comparison_to_console(cpu_results, gpu_results)

func _connect_sensor_color_signals():
	# Connect to all sensor color_updated signals to track color detection
	if sensor_grid and sensor_grid.has_method("get_sensors"):
		var sensors = sensor_grid.get_sensors()
		for i in range(sensors.size()):
			var sensor = sensors[i]
			if sensor and sensor.has_signal("color_updated"):
				sensor.connect("color_updated", Callable(self, "_on_sensor_color_detected"))

func _on_sensor_color_detected(color: Color):
	# Track detected colors and check for non-black colors
	detected_colors.append(color)
	
	# Check if this is a non-black color (not pure black)
	if color.r > 0.01 or color.g > 0.01 or color.b > 0.01:
		has_detected_non_black = true

# Removed _on_sensor_refresh_completed - now using outgoing FPS measurement instead

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
	
	# Outgoing FPS Performance
	print("\nOUTGOING FPS PERFORMANCE:")
	print("  Average Outgoing FPS: " + str(round(results.get("avg_outgoing_fps", 0) * 100) / 100))
	print("  Max Outgoing FPS: " + str(round(results.get("max_outgoing_fps", 0) * 100) / 100))
	print("  Min Outgoing FPS: " + str(round(results.get("min_outgoing_fps", 0) * 100) / 100))
	print("  Outgoing FPS Samples: " + str(results.get("outgoing_fps_samples", 0)))
	print("  Refresh Calls: " + str(results.get("refresh_call_count", 0)))
	print("  Values Refreshed: " + str(results.get("values_refreshed_count", 0)))
	
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
	var avg_outgoing_fps = results.get("avg_outgoing_fps", 0)
	var max_outgoing_fps = results.get("max_outgoing_fps", 0)
	
	if avg_fps >= 55:
		print("  ✓ FPS Performance: GOOD (Average FPS: " + str(round(avg_fps)) + ")")
	else:
		print("  ⚠ FPS Performance: BELOW TARGET (Average FPS: " + str(round(avg_fps)) + " < 55)")
	
	if avg_outgoing_fps >= 10:
		print("  ✓ Outgoing FPS: HIGH (" + str(round(avg_outgoing_fps * 100) / 100) + " Hz)")
	elif avg_outgoing_fps >= 5:
		print("  ⚠ Outgoing FPS: MEDIUM (" + str(round(avg_outgoing_fps * 100) / 100) + " Hz)")
	else:
		print("  ✗ Outgoing FPS: LOW (" + str(round(avg_outgoing_fps * 100) / 100) + " Hz)")
	
	if max_outgoing_fps >= 20:
		print("  ✓ Peak Outgoing FPS: EXCELLENT (" + str(round(max_outgoing_fps * 100) / 100) + " Hz)")
	elif max_outgoing_fps >= 10:
		print("  ⚠ Peak Outgoing FPS: GOOD (" + str(round(max_outgoing_fps * 100) / 100) + " Hz)")
	else:
		print("  ✗ Peak Outgoing FPS: POOR (" + str(round(max_outgoing_fps * 100) / 100) + " Hz)")
	
	print("============================================================")

func log_batch_comparison_to_console(cpu_results: Dictionary, gpu_results: Dictionary):
	print("\n================================================================================")
	print("BATCH TEST COMPARISON: GPU vs CPU PERFORMANCE")
	print("================================================================================")
	
	# FPS comparison
	var cpu_avg_fps = cpu_results.get("avg_fps", 0)
	var gpu_avg_fps = gpu_results.get("avg_fps", 0)
	print("\nFPS PERFORMANCE COMPARISON:")
	print("  CPU Average FPS: " + str(round(cpu_avg_fps * 100) / 100))
	print("  GPU Average FPS: " + str(round(gpu_avg_fps * 100) / 100))
	
	if cpu_avg_fps > 0 and gpu_avg_fps > 0:
		var fps_ratio = gpu_avg_fps / cpu_avg_fps
		if fps_ratio > 1:
			print("  → GPU is " + str(round(fps_ratio * 100) / 100) + "x FASTER than CPU")
		else:
			print("  → CPU is " + str(round((1.0 / fps_ratio) * 100) / 100) + "x FASTER than GPU")
	
	# Outgoing FPS comparison
	var cpu_avg_outgoing = cpu_results.get("avg_outgoing_fps", 0)
	var gpu_avg_outgoing = gpu_results.get("avg_outgoing_fps", 0)
	print("\nOUTGOING FPS COMPARISON:")
	print("  CPU Average Outgoing FPS: " + str(round(cpu_avg_outgoing * 100) / 100) + " Hz")
	print("  GPU Average Outgoing FPS: " + str(round(gpu_avg_outgoing * 100) / 100) + " Hz")
	
	if cpu_avg_outgoing > 0 and gpu_avg_outgoing > 0:
		var outgoing_ratio = gpu_avg_outgoing / cpu_avg_outgoing
		if outgoing_ratio > 1:
			print("  → GPU achieves " + str(round(outgoing_ratio * 100) / 100) + "x HIGHER outgoing FPS than CPU")
		else:
			print("  → CPU achieves " + str(round((1.0 / outgoing_ratio) * 100) / 100) + "x HIGHER outgoing FPS than GPU")
	
	print("================================================================================")

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
