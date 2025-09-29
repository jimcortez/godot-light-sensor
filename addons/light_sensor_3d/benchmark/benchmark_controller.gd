extends Node

## Main controller for the Light Sensor 3D benchmark system
## Manages test execution, FPS monitoring, and result collection

signal test_started(test_type: String)
signal test_completed(test_type: String, results: Dictionary)
signal test_progress(progress: float, status: String)

# Test configuration
@export var test_duration: float = 5.0
@export var grid_size: int = 6
@export var color_cycle_speed: float = 1.0
@export var target_fps_threshold: float = 55.0

# Adaptive testing configuration
@export var engine_fps_goal: float = 40.0  # Minimum acceptable engine FPS
@export var engine_fps_max: float = 55.0   # Maximum expected engine FPS
@export var outgoing_fps_goal: float = 40.0  # Target outgoing FPS to start with
@export var outgoing_fps_min: float = 10.0   # Minimum outgoing FPS
@export var outgoing_fps_step: float = 10.0   # Step size for decreasing outgoing FPS
@export var test_passes_per_rate: int = 1    # Number of test passes per refresh rate

# Test state
var is_testing: bool = false
var current_test_type: String = ""
var is_batch_test: bool = false
var test_start_time: float = 0.0
var test_end_time: float = 0.0
var test_start_time_precise: float = 0.0

# Adaptive testing state
var is_adaptive_test: bool = false
var current_outgoing_fps_target: float = 0.0
var current_pass: int = 0
var adaptive_test_results: Array[Dictionary] = []
var adaptive_test_recommendations: Dictionary = {}
var current_adaptive_mode: String = ""  # "CPU" or "GPU"
var adaptive_test_phases_completed: int = 0  # Track completed phases (CPU=1, GPU=2)

# Convergence tracking to prevent infinite loops
var tested_fps_rates: Array[float] = []  # Track all FPS rates we've tested
var convergence_attempts: int = 0  # Track how many times we've oscillated
var max_convergence_attempts: int = 3  # Maximum oscillation attempts before stopping

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
	
	# Set the sensor grid size to match the benchmark configuration
	if sensor_grid and sensor_grid.has_method("set_grid_size"):
		await sensor_grid.set_grid_size(grid_size)
		print("Benchmark controller set sensor grid size to: " + str(grid_size) + "x" + str(grid_size))
	
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

func start_adaptive_test():
	if is_testing:
		return
	
	print("Starting adaptive benchmark test...")
	is_adaptive_test = true
	is_batch_test = false
	adaptive_test_results.clear()
	adaptive_test_recommendations.clear()
	current_outgoing_fps_target = outgoing_fps_goal
	current_pass = 0
	current_adaptive_mode = "CPU"
	adaptive_test_phases_completed = 0
	
	# Start with CPU mode for adaptive testing
	await start_adaptive_test_phase("CPU")

func start_adaptive_test_phase(test_type: String):
	print("============================================================")
	print("ADAPTIVE TEST PHASE: " + test_type + " mode")
	print("Target outgoing FPS: " + str(current_outgoing_fps_target))
	print("Original goal: " + str(outgoing_fps_goal))
	print("Pass: " + str(current_pass + 1) + "/" + str(test_passes_per_rate))
	print("Current adaptive mode: " + str(current_adaptive_mode))
	print("============================================================")
	
	# Ensure we're in the right mode
	current_adaptive_mode = test_type
	
	# Set the refresh rate for the sensor grid
	if sensor_grid and sensor_grid.has_method("set_refresh_rate"):
		var refresh_interval = 1.0 / current_outgoing_fps_target
		sensor_grid.set_refresh_rate(refresh_interval)
		print("Set sensor refresh rate to: " + str(refresh_interval) + "s (" + str(current_outgoing_fps_target) + " FPS)")
	
	# Start the test with the configured refresh rate
	await start_test(test_type)

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
	
	# Calculate results
	var results = calculate_test_results()
	
	# Handle adaptive testing logic
	if is_adaptive_test:
		await handle_adaptive_test_completion(results, test_duration_actual)
		return
	
	if is_batch_test:
		print("============================================================")
		print("BATCH TEST PHASE: " + current_test_type + " test completed")
		print("Actual duration: " + str(test_duration_actual) + "s (target: " + str(test_duration) + "s)")
		print("============================================================")
	else:
		print("Test completed. Actual duration: " + str(test_duration_actual) + "s (target: " + str(test_duration) + "s)")
	
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

func handle_adaptive_test_completion(results: Dictionary, test_duration_actual: float):
	print("============================================================")
	print("ADAPTIVE TEST PHASE: " + current_test_type + " test completed")
	print("Target outgoing FPS: " + str(current_outgoing_fps_target))
	print("Pass: " + str(current_pass + 1) + "/" + str(test_passes_per_rate))
	print("Actual duration: " + str(test_duration_actual) + "s (target: " + str(test_duration) + "s)")
	print("============================================================")
	
	# Add metadata to results for adaptive testing
	results["adaptive_test_metadata"] = {
		"outgoing_fps_target": current_outgoing_fps_target,
		"pass_number": current_pass,
		"test_type": current_test_type
	}
	
	# Store results
	adaptive_test_results.append(results)
	
	# Check if we need more passes at this refresh rate
	current_pass += 1
	if current_pass < test_passes_per_rate:
		print("Running additional pass at same refresh rate...")
		update_status("Adaptive test - " + current_test_type + " pass " + str(current_pass + 1) + "/" + str(test_passes_per_rate))
		
		# Reset testing state and run another pass
		is_testing = false
		current_test_type = ""
		
		await get_tree().create_timer(1.0).timeout  # Brief pause between passes
		await start_adaptive_test_phase("CPU")  # Continue with CPU mode
		return
	
	# All passes completed for this refresh rate
	print("All passes completed for outgoing FPS target: " + str(current_outgoing_fps_target))
	
	# Track this FPS rate as tested
	tested_fps_rates.append(current_outgoing_fps_target)
	
	# Calculate average results for this refresh rate
	var avg_results = calculate_average_results_for_rate(current_outgoing_fps_target)
	var avg_engine_fps = avg_results.get("avg_fps", 0)
	
	print("Average engine FPS for " + str(current_outgoing_fps_target) + " FPS: " + str(round(avg_engine_fps * 100) / 100))
	
	# Check for convergence issues (oscillation between same FPS rates)
	if tested_fps_rates.size() >= 4:
		var last_four = tested_fps_rates.slice(-4)
		# Check if we're oscillating between two values (e.g., [20, 30, 20, 30])
		if last_four[0] == last_four[2] and last_four[1] == last_four[3] and last_four[0] != last_four[1]:
			convergence_attempts += 1
			print("⚠ Convergence issue detected! Oscillating between " + str(last_four[0]) + " and " + str(last_four[1]) + " FPS (attempt " + str(convergence_attempts) + "/" + str(max_convergence_attempts) + ")")
			
			if convergence_attempts >= max_convergence_attempts:
				print("🛑 Maximum convergence attempts reached. Stopping adaptive test to prevent infinite loop.")
				print("Final recommendation will be based on the best performing rate tested so far.")
				
				# If we're in CPU mode and haven't tried GPU yet, switch to GPU phase
				if current_adaptive_mode == "CPU" and adaptive_test_phases_completed == 0:
					print("Switching to GPU phase to continue testing...")
					await switch_to_gpu_phase()
					return
				else:
					# Otherwise, complete the test
					await complete_adaptive_test()
					return
	
	# Check if we met the engine FPS goal AND achieved the target outgoing FPS
	var avg_outgoing_fps = avg_results.get("avg_outgoing_fps", 0)
	var outgoing_fps_target_achieved = avg_outgoing_fps >= (current_outgoing_fps_target * 0.9)  # Allow 10% tolerance
	
	if avg_engine_fps >= engine_fps_goal and outgoing_fps_target_achieved:
		print("✓ Engine FPS goal met! Average: " + str(round(avg_engine_fps * 100) / 100) + " >= " + str(engine_fps_goal))
		print("✓ Outgoing FPS target achieved! Average: " + str(round(avg_outgoing_fps * 100) / 100) + " FPS (target: " + str(current_outgoing_fps_target) + " FPS)")
		
		# Check if we can try a higher refresh rate
		var next_target = current_outgoing_fps_target + outgoing_fps_step
		
		# For CPU mode: continue testing higher rates if performance is good, even beyond original goal
		# For GPU mode: respect the outgoing_fps_goal limit
		var should_continue_testing = false
		if current_adaptive_mode == "CPU":
			# CPU mode: continue testing higher rates as long as engine FPS goal is met
			should_continue_testing = next_target <= (outgoing_fps_goal + outgoing_fps_step * 2) and not tested_fps_rates.has(next_target)
		else:
			# GPU mode: respect the original goal
			should_continue_testing = next_target <= outgoing_fps_goal and not tested_fps_rates.has(next_target)
		
		if should_continue_testing:
			print("Trying higher outgoing FPS target: " + str(next_target) + " FPS")
			current_outgoing_fps_target = next_target
			current_pass = 0
			update_status("Adaptive test - trying higher refresh rate: " + str(current_outgoing_fps_target) + " FPS")
			
			# Reset testing state and continue with new target
			is_testing = false
			current_test_type = ""
			
			await get_tree().create_timer(2.0).timeout  # Longer pause between different refresh rates
			await start_adaptive_test_phase(current_adaptive_mode)  # Continue with current mode
			return
		elif next_target > outgoing_fps_goal and current_adaptive_mode == "CPU":
			# CPU mode reached reasonable limit - switch to GPU phase
			print("CPU mode reached reasonable outgoing FPS limit (" + str(outgoing_fps_goal + outgoing_fps_step * 2) + " FPS). Switching to GPU phase.")
			await switch_to_gpu_phase()
			return
		elif next_target > outgoing_fps_goal and current_adaptive_mode == "GPU":
			# GPU mode reached maximum - complete the test
			print("Reached maximum outgoing FPS target: " + str(outgoing_fps_goal))
			await complete_adaptive_test()
			return
		else:
			# Already tested this rate
			print("Already tested " + str(next_target) + " FPS.")
			
			# If we're in CPU mode and haven't tried GPU yet, switch to GPU phase
			if current_adaptive_mode == "CPU" and adaptive_test_phases_completed == 0:
				print("Switching to GPU phase to continue testing...")
				await switch_to_gpu_phase()
				return
			else:
				# Otherwise, complete the test
				print("Completing adaptive test.")
				await complete_adaptive_test()
				return
	
	# Check different scenarios
	if avg_engine_fps >= engine_fps_goal:
		print("✓ Engine FPS goal met! Average: " + str(round(avg_engine_fps * 100) / 100) + " >= " + str(engine_fps_goal))
		print("⚠ Outgoing FPS target not achieved! Average: " + str(round(avg_outgoing_fps * 100) / 100) + " FPS (target: " + str(current_outgoing_fps_target) + " FPS)")
		
		# Engine FPS is good but outgoing FPS is low - try a higher refresh rate
		var next_target = current_outgoing_fps_target + outgoing_fps_step
		
		# For CPU mode: continue testing higher rates if performance is good, even beyond original goal
		# For GPU mode: respect the outgoing_fps_goal limit
		var should_continue_testing = false
		if current_adaptive_mode == "CPU":
			# CPU mode: continue testing higher rates as long as engine FPS goal is met
			should_continue_testing = next_target <= (outgoing_fps_goal + outgoing_fps_step * 2) and not tested_fps_rates.has(next_target)
		else:
			# GPU mode: respect the original goal
			should_continue_testing = next_target <= outgoing_fps_goal and not tested_fps_rates.has(next_target)
		
		if should_continue_testing:
			print("Trying higher outgoing FPS target: " + str(next_target) + " FPS")
			current_outgoing_fps_target = next_target
			current_pass = 0
			update_status("Adaptive test - trying higher refresh rate: " + str(current_outgoing_fps_target) + " FPS")
			
			# Reset testing state and continue with new target
			is_testing = false
			current_test_type = ""
			
			await get_tree().create_timer(2.0).timeout  # Longer pause between different refresh rates
			await start_adaptive_test_phase(current_adaptive_mode)  # Continue with current mode
			return
		elif next_target > outgoing_fps_goal and current_adaptive_mode == "CPU":
			# CPU mode reached reasonable limit - switch to GPU phase
			print("CPU mode reached reasonable outgoing FPS limit (" + str(outgoing_fps_goal + outgoing_fps_step * 2) + " FPS). Switching to GPU phase.")
			await switch_to_gpu_phase()
			return
		elif next_target > outgoing_fps_goal and current_adaptive_mode == "GPU":
			# GPU mode reached maximum - complete the test
			print("Reached maximum outgoing FPS target: " + str(outgoing_fps_goal))
			await complete_adaptive_test()
			return
		else:
			# Already tested this rate
			print("Already tested " + str(next_target) + " FPS.")
			
			# If we're in CPU mode and haven't tried GPU yet, switch to GPU phase
			if current_adaptive_mode == "CPU" and adaptive_test_phases_completed == 0:
				print("Switching to GPU phase to continue testing...")
				await switch_to_gpu_phase()
				return
			else:
				# Otherwise, complete the test
				print("Completing adaptive test.")
				await complete_adaptive_test()
				return
	else:
		print("⚠ Engine FPS goal not met. Average: " + str(round(avg_engine_fps * 100) / 100) + " < " + str(engine_fps_goal))
		
		# Decrease outgoing FPS target and continue
		var next_target = current_outgoing_fps_target - outgoing_fps_step
		current_pass = 0
		
		# Check if we've reached the minimum outgoing FPS
		if next_target < outgoing_fps_min:
			# Current mode completed - check if we need to switch to GPU
			if current_adaptive_mode == "CPU":
				print("CPU phase completed - switching to GPU phase")
				await switch_to_gpu_phase()
				return
			else:
				print("Reached minimum outgoing FPS limit: " + str(outgoing_fps_min))
				await complete_adaptive_test()
				return
		
		# Check if we've already tested this lower rate
		if tested_fps_rates.has(next_target):
			print("Already tested " + str(next_target) + " FPS.")
			
			# If we're in CPU mode and haven't tried GPU yet, switch to GPU phase
			if current_adaptive_mode == "CPU" and adaptive_test_phases_completed == 0:
				print("Switching to GPU phase to continue testing...")
				await switch_to_gpu_phase()
				return
			else:
				# Otherwise, complete the test
				print("Completing adaptive test.")
				await complete_adaptive_test()
				return
		
		current_outgoing_fps_target = next_target
		print("Decreasing outgoing FPS target to: " + str(current_outgoing_fps_target))
		update_status("Adaptive test - trying lower refresh rate: " + str(current_outgoing_fps_target) + " FPS")
		
		# Reset testing state and continue with new target
		is_testing = false
		current_test_type = ""
		
		await get_tree().create_timer(2.0).timeout  # Longer pause between different refresh rates
		await start_adaptive_test_phase(current_adaptive_mode)  # Continue with current mode

func switch_to_gpu_phase():
	print("============================================================")
	print("ADAPTIVE TEST PHASE TRANSITION: CPU → GPU")
	print("============================================================")
	
	# Mark CPU phase as completed
	adaptive_test_phases_completed = 1
	current_adaptive_mode = "GPU"
	
	# Reset for GPU phase - start at the original goal, not where CPU left off
	current_outgoing_fps_target = outgoing_fps_goal
	current_pass = 0
	
	# Reset convergence tracking for GPU phase
	tested_fps_rates.clear()
	convergence_attempts = 0
	
	# Ensure any lingering test is properly stopped
	is_testing = false
	current_test_type = ""
	
	print("GPU phase reset - starting at outgoing FPS target: " + str(current_outgoing_fps_target))
	update_status("Adaptive test - switching to GPU mode...")
	
	# Brief pause before starting GPU phase
	await get_tree().create_timer(3.0).timeout
	
	# Start GPU phase
	await start_adaptive_test_phase("GPU")

func calculate_average_results_for_rate(outgoing_fps_target: float) -> Dictionary:
	var results_for_rate = []
	
	# Find all results for this refresh rate
	for result in adaptive_test_results:
		var metadata = result.get("adaptive_test_metadata", {})
		if metadata.get("outgoing_fps_target", 0) == outgoing_fps_target:
			results_for_rate.append(result)
	
	if results_for_rate.is_empty():
		return {}
	
	# Calculate averages
	var avg_results = {}
	var fps_sum = 0.0
	var outgoing_fps_sum = 0.0
	var max_fps_sum = 0.0
	var max_outgoing_fps_sum = 0.0
	var min_fps_sum = 999.0
	var min_outgoing_fps_sum = 999.0
	
	for result in results_for_rate:
		fps_sum += result.get("avg_fps", 0)
		outgoing_fps_sum += result.get("avg_outgoing_fps", 0)
		max_fps_sum += result.get("max_fps", 0)
		max_outgoing_fps_sum += result.get("max_outgoing_fps", 0)
		min_fps_sum = min(min_fps_sum, result.get("min_fps", 999.0))
		min_outgoing_fps_sum = min(min_outgoing_fps_sum, result.get("min_outgoing_fps", 999.0))
	
	var count = results_for_rate.size()
	avg_results["avg_fps"] = fps_sum / count
	avg_results["avg_outgoing_fps"] = outgoing_fps_sum / count
	avg_results["max_fps"] = max_fps_sum / count
	avg_results["max_outgoing_fps"] = max_outgoing_fps_sum / count
	avg_results["min_fps"] = min_fps_sum
	avg_results["min_outgoing_fps"] = min_outgoing_fps_sum
	avg_results["pass_count"] = count
	avg_results["outgoing_fps_target"] = outgoing_fps_target
	
	return avg_results

func calculate_average_results_for_rate_and_mode(outgoing_fps_target: float, mode: String) -> Dictionary:
	var results_for_rate = []
	
	# Find all results for this refresh rate and mode
	for result in adaptive_test_results:
		var metadata = result.get("adaptive_test_metadata", {})
		if metadata.get("outgoing_fps_target", 0) == outgoing_fps_target and metadata.get("test_type", "") == mode:
			results_for_rate.append(result)
	
	if results_for_rate.is_empty():
		return {}
	
	# Calculate averages
	var avg_results = {}
	var fps_sum = 0.0
	var outgoing_fps_sum = 0.0
	var max_fps_sum = 0.0
	var max_outgoing_fps_sum = 0.0
	var min_fps_sum = 999.0
	var min_outgoing_fps_sum = 999.0
	
	for result in results_for_rate:
		fps_sum += result.get("avg_fps", 0)
		outgoing_fps_sum += result.get("avg_outgoing_fps", 0)
		max_fps_sum += result.get("max_fps", 0)
		max_outgoing_fps_sum += result.get("max_outgoing_fps", 0)
		min_fps_sum = min(min_fps_sum, result.get("min_fps", 999.0))
		min_outgoing_fps_sum = min(min_outgoing_fps_sum, result.get("min_outgoing_fps", 999.0))
	
	var count = results_for_rate.size()
	avg_results["avg_fps"] = fps_sum / count
	avg_results["avg_outgoing_fps"] = outgoing_fps_sum / count
	avg_results["max_fps"] = max_fps_sum / count
	avg_results["max_outgoing_fps"] = max_outgoing_fps_sum / count
	avg_results["min_fps"] = min_fps_sum
	avg_results["min_outgoing_fps"] = min_outgoing_fps_sum
	avg_results["pass_count"] = count
	avg_results["outgoing_fps_target"] = outgoing_fps_target
	avg_results["mode"] = mode
	
	return avg_results

func complete_adaptive_test():
	print("============================================================")
	print("ADAPTIVE TEST COMPLETED")
	print("============================================================")
	
	# Calculate recommendations
	adaptive_test_recommendations = calculate_adaptive_recommendations()
	
	# Display results and recommendations
	display_adaptive_results()
	
	# Reset testing state
	is_testing = false
	current_test_type = ""
	is_adaptive_test = false
	current_outgoing_fps_target = 0.0
	current_pass = 0
	current_adaptive_mode = ""
	adaptive_test_phases_completed = 0
	
	# Stop sensor refresh cycle
	if sensor_grid:
		sensor_grid.stop_refresh_cycle()
	
	print("Adaptive test completed successfully!")

func calculate_adaptive_recommendations() -> Dictionary:
	var recommendations = {}
	
	# Find the highest outgoing FPS that met the engine FPS goal AND achieved good outgoing FPS
	var best_outgoing_fps = 0.0
	var best_results = {}
	var best_outgoing_fps_achieved = 0.0
	
	for result in adaptive_test_results:
		var metadata = result.get("adaptive_test_metadata", {})
		var outgoing_fps_target = metadata.get("outgoing_fps_target", 0)
		var avg_engine_fps = result.get("avg_fps", 0)
		var avg_outgoing_fps = result.get("avg_outgoing_fps", 0)
		
		# Check if this result meets engine FPS goal and has good outgoing FPS achievement
		if avg_engine_fps >= engine_fps_goal:
			# Calculate how well it achieved the outgoing FPS target (with 90% tolerance)
			var outgoing_fps_achievement = avg_outgoing_fps / outgoing_fps_target if outgoing_fps_target > 0 else 0
			
			# Prefer results that achieve better outgoing FPS rates
			if outgoing_fps_target > best_outgoing_fps or (outgoing_fps_target == best_outgoing_fps and avg_outgoing_fps > best_outgoing_fps_achieved):
				best_outgoing_fps = outgoing_fps_target
				best_results = result
				best_outgoing_fps_achieved = avg_outgoing_fps
	
	if best_outgoing_fps > 0:
		var achievement_percentage = (best_outgoing_fps_achieved / best_outgoing_fps) * 100 if best_outgoing_fps > 0 else 0
		recommendations["recommended_outgoing_fps"] = best_outgoing_fps
		recommendations["achieved_engine_fps"] = best_results.get("avg_fps", 0)
		recommendations["achieved_outgoing_fps"] = best_outgoing_fps_achieved
		recommendations["achievement_percentage"] = achievement_percentage
		
		if achievement_percentage >= 90:
			recommendations["recommendation_type"] = "optimal"
			recommendations["recommendation_text"] = generate_sensor_recommendation(best_outgoing_fps, best_outgoing_fps_achieved, best_results.get("avg_fps", 0), achievement_percentage, "optimal")
		elif achievement_percentage >= 70:
			recommendations["recommendation_type"] = "good"
			recommendations["recommendation_text"] = generate_sensor_recommendation(best_outgoing_fps, best_outgoing_fps_achieved, best_results.get("avg_fps", 0), achievement_percentage, "good")
		else:
			recommendations["recommendation_type"] = "limited"
			recommendations["recommendation_text"] = generate_sensor_recommendation(best_outgoing_fps, best_outgoing_fps_achieved, best_results.get("avg_fps", 0), achievement_percentage, "limited")
	else:
		# No refresh rate met the engine FPS goal - find the best compromise
		var highest_fps = 0.0
		var best_compromise_results = {}
		
		for result in adaptive_test_results:
			var metadata = result.get("adaptive_test_metadata", {})
			var outgoing_fps_target = metadata.get("outgoing_fps_target", 0)
			var avg_engine_fps = result.get("avg_fps", 0)
			
			if avg_engine_fps > highest_fps:
				highest_fps = avg_engine_fps
				best_compromise_results = result
				best_outgoing_fps = outgoing_fps_target
		
		recommendations["recommended_outgoing_fps"] = best_outgoing_fps
		recommendations["achieved_engine_fps"] = highest_fps
		recommendations["achieved_outgoing_fps"] = best_compromise_results.get("avg_outgoing_fps", 0)
		recommendations["achievement_percentage"] = 0
		recommendations["recommendation_type"] = "compromise"
		recommendations["recommendation_text"] = generate_sensor_recommendation(best_outgoing_fps, best_compromise_results.get("avg_outgoing_fps", 0), highest_fps, 0, "compromise")
	
	# Hardware assessment based on achieved outgoing FPS
	var achieved_outgoing_fps = recommendations.get("achieved_outgoing_fps", 0)
	if achieved_outgoing_fps >= 30:
		recommendations["hardware_assessment"] = "high"
		recommendations["hardware_text"] = "Achieved outgoing FPS: " + str(round(achieved_outgoing_fps * 10) / 10) + " FPS"
	elif achieved_outgoing_fps >= 20:
		recommendations["hardware_assessment"] = "medium"
		recommendations["hardware_text"] = "Achieved outgoing FPS: " + str(round(achieved_outgoing_fps * 10) / 10) + " FPS"
	elif achieved_outgoing_fps >= 10:
		recommendations["hardware_assessment"] = "moderate"
		recommendations["hardware_text"] = "Achieved outgoing FPS: " + str(round(achieved_outgoing_fps * 10) / 10) + " FPS"
	else:
		recommendations["hardware_assessment"] = "low"
		recommendations["hardware_text"] = "Achieved outgoing FPS: " + str(round(achieved_outgoing_fps * 10) / 10) + " FPS"
	
	return recommendations

func generate_sensor_recommendation(target_fps: float, achieved_fps: float, engine_fps: float, achievement_percentage: float, recommendation_type: String) -> String:
	var text = ""
	
	# Separate CPU and GPU results
	var cpu_results = []
	var gpu_results = []
	
	for result in adaptive_test_results:
		var metadata = result.get("adaptive_test_metadata", {})
		if metadata.get("test_type", "") == "CPU":
			cpu_results.append(result)
		elif metadata.get("test_type", "") == "GPU":
			gpu_results.append(result)
	
	# Find the maximum refresh rate that meets engine FPS goal for each mode
	var cpu_max_fps = 0.0
	var cpu_max_engine_fps = 0.0
	var gpu_max_fps = 0.0
	var gpu_max_engine_fps = 0.0
	
	# For CPU mode - find highest FPS that meets engine goal
	for result in cpu_results:
		var metadata = result.get("adaptive_test_metadata", {})
		var fps_target = metadata.get("outgoing_fps_target", 0)
		var engine_fps_result = result.get("avg_fps", 0)
		if engine_fps_result >= engine_fps_goal and fps_target > cpu_max_fps:
			cpu_max_fps = fps_target
			cpu_max_engine_fps = engine_fps_result
	
	# For GPU mode - find highest FPS that meets engine goal
	for result in gpu_results:
		var metadata = result.get("adaptive_test_metadata", {})
		var fps_target = metadata.get("outgoing_fps_target", 0)
		var engine_fps_result = result.get("avg_fps", 0)
		if engine_fps_result >= engine_fps_goal and fps_target > gpu_max_fps:
			gpu_max_fps = fps_target
			gpu_max_engine_fps = engine_fps_result
	
	# If no results meet engine FPS goal, find the best compromise
	var cpu_best_compromise_fps = 0.0
	var cpu_best_compromise_engine_fps = 0.0
	var gpu_best_compromise_fps = 0.0
	var gpu_best_compromise_engine_fps = 0.0
	
	if cpu_max_fps == 0:  # No CPU result met engine goal
		# Find the best compromise: prioritize refresh rates that get close to engine goal
		for result in cpu_results:
			var metadata = result.get("adaptive_test_metadata", {})
			var fps_target = metadata.get("outgoing_fps_target", 0)
			var engine_fps_result = result.get("avg_fps", 0)
			
			# Prefer refresh rates that achieve at least 80% of engine goal
			if engine_fps_result >= engine_fps_goal * 0.8:
				if cpu_best_compromise_fps == 0 or fps_target > cpu_best_compromise_fps:
					cpu_best_compromise_fps = fps_target
					cpu_best_compromise_engine_fps = engine_fps_result
		
		# If no good compromise found, use the result with highest engine FPS
		if cpu_best_compromise_fps == 0:
			for result in cpu_results:
				var metadata = result.get("adaptive_test_metadata", {})
				var fps_target = metadata.get("outgoing_fps_target", 0)
				var engine_fps_result = result.get("avg_fps", 0)
				if engine_fps_result > cpu_best_compromise_engine_fps:
					cpu_best_compromise_fps = fps_target
					cpu_best_compromise_engine_fps = engine_fps_result
	
	if gpu_max_fps == 0:  # No GPU result met engine goal
		# Find the best compromise: prioritize refresh rates that get close to engine goal
		for result in gpu_results:
			var metadata = result.get("adaptive_test_metadata", {})
			var fps_target = metadata.get("outgoing_fps_target", 0)
			var engine_fps_result = result.get("avg_fps", 0)
			
			# Prefer refresh rates that achieve at least 80% of engine goal
			if engine_fps_result >= engine_fps_goal * 0.8:
				if gpu_best_compromise_fps == 0 or fps_target > gpu_best_compromise_fps:
					gpu_best_compromise_fps = fps_target
					gpu_best_compromise_engine_fps = engine_fps_result
		
		# If no good compromise found, use the result with highest engine FPS
		if gpu_best_compromise_fps == 0:
			for result in gpu_results:
				var metadata = result.get("adaptive_test_metadata", {})
				var fps_target = metadata.get("outgoing_fps_target", 0)
				var engine_fps_result = result.get("avg_fps", 0)
				if engine_fps_result > gpu_best_compromise_engine_fps:
					gpu_best_compromise_fps = fps_target
					gpu_best_compromise_engine_fps = engine_fps_result
	
	text += "MAXIMUM SENSOR REFRESH RATE RECOMMENDATIONS:\n"
	text += "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
	
	# CPU recommendations
	if cpu_max_fps > 0:
		text += "CPU Mode: Maximum " + str(round(cpu_max_fps)) + " FPS refresh rate\n"
		text += "  → Refresh interval: " + str(round((1.0 / cpu_max_fps) * 1000) / 1000) + "s\n"
		text += "  → Engine FPS: " + str(round(cpu_max_engine_fps * 10) / 10) + " (meets goal of " + str(engine_fps_goal) + "+)\n\n"
	elif cpu_best_compromise_fps > 0:
		text += "CPU Mode: Maximum " + str(round(cpu_best_compromise_fps)) + " FPS refresh rate\n"
		text += "  → Refresh interval: " + str(round((1.0 / cpu_best_compromise_fps) * 1000) / 1000) + "s\n"
		text += "  → Engine FPS: " + str(round(cpu_best_compromise_engine_fps * 10) / 10) + " (below goal of " + str(engine_fps_goal) + "+)\n\n"
	
	# GPU recommendations
	if gpu_max_fps > 0:
		text += "GPU Mode: Maximum " + str(round(gpu_max_fps)) + " FPS refresh rate\n"
		text += "  → Refresh interval: " + str(round((1.0 / gpu_max_fps) * 1000) / 1000) + "s\n"
		text += "  → Engine FPS: " + str(round(gpu_max_engine_fps * 10) / 10) + " (meets goal of " + str(engine_fps_goal) + "+)\n\n"
	elif gpu_best_compromise_fps > 0:
		text += "GPU Mode: Maximum " + str(round(gpu_best_compromise_fps)) + " FPS refresh rate\n"
		text += "  → Refresh interval: " + str(round((1.0 / gpu_best_compromise_fps) * 1000) / 1000) + "s\n"
		text += "  → Engine FPS: " + str(round(gpu_best_compromise_engine_fps * 10) / 10) + " (below goal of " + str(engine_fps_goal) + "+)\n\n"
	
	# Best mode recommendation
	if cpu_max_fps > 0 and gpu_max_fps > 0:
		if gpu_max_fps > cpu_max_fps:
			text += "RECOMMENDATION: Use GPU mode for maximum " + str(round(gpu_max_fps)) + " FPS\n"
		elif cpu_max_fps > gpu_max_fps:
			text += "RECOMMENDATION: Use CPU mode for maximum " + str(round(cpu_max_fps)) + " FPS\n"
		else:
			text += "RECOMMENDATION: Both modes support maximum " + str(round(cpu_max_fps)) + " FPS\n"
	elif cpu_max_fps > 0:
		text += "RECOMMENDATION: Use CPU mode for maximum " + str(round(cpu_max_fps)) + " FPS\n"
	elif gpu_max_fps > 0:
		text += "RECOMMENDATION: Use GPU mode for maximum " + str(round(gpu_max_fps)) + " FPS\n"
	elif cpu_best_compromise_fps > 0 or gpu_best_compromise_fps > 0:
		text += "RECOMMENDATION: Engine FPS goal not met - use lowest tested refresh rate\n"
	
	return text

func display_adaptive_results():
	var text = "[font_size=20][b]Adaptive Benchmark Results[/b][/font_size]\n\n"
	
	text += "[font_size=18][b]Test Summary:[/b][/font_size]\n"
	text += "Engine FPS Goal: " + str(engine_fps_goal) + " (minimum acceptable)\n"
	text += "Engine FPS Max: " + str(engine_fps_max) + " (target range)\n"
	text += "Outgoing FPS Range: " + str(outgoing_fps_min) + " - " + str(outgoing_fps_goal) + " FPS\n"
	text += "Test Passes per Rate: " + str(test_passes_per_rate) + "\n\n"
	
	# Separate CPU and GPU results
	var cpu_results = []
	var gpu_results = []
	
	for result in adaptive_test_results:
		var metadata = result.get("adaptive_test_metadata", {})
		if metadata.get("test_type", "") == "CPU":
			cpu_results.append(result)
		elif metadata.get("test_type", "") == "GPU":
			gpu_results.append(result)
	
	# Display CPU results
	if cpu_results.size() > 0:
		text += "[font_size=18][b]CPU Mode Results:[/b][/font_size]\n"
		text += display_mode_results(cpu_results, "CPU")
		text += "\n"
	
	# Display GPU results
	if gpu_results.size() > 0:
		text += "[font_size=18][b]GPU Mode Results:[/b][/font_size]\n"
		text += display_mode_results(gpu_results, "GPU")
		text += "\n"
	
	text += "\n[font_size=18][b]Recommendations:[/b][/font_size]\n"
	text += adaptive_test_recommendations.get("recommendation_text", "No recommendation available") + "\n\n"
	
	text += "[font_size=18][b]Hardware Assessment:[/b][/font_size]\n"
	text += adaptive_test_recommendations.get("hardware_text", "No assessment available") + "\n"
	
	if results_ui and results_ui.has_method("update_results_display"):
		results_ui.update_results_display(text)
	else:
		results_text.text = text
	
	# Log to console
	log_adaptive_results_to_console()

func display_mode_results(mode_results: Array, mode_name: String) -> String:
	var text = ""
	
	# Group results by refresh rate for this mode
	var rates_tested = []
	for result in mode_results:
		var metadata = result.get("adaptive_test_metadata", {})
		var rate = metadata.get("outgoing_fps_target", 0)
		if rate not in rates_tested:
			rates_tested.append(rate)
	
	rates_tested.sort()
	
	for rate in rates_tested:
		var avg_results = calculate_average_results_for_rate_and_mode(rate, mode_name)
		text += "\n[b]Outgoing FPS: " + str(rate) + " FPS[/b]\n"
		text += "  Average Engine FPS: " + str(round(avg_results.get("avg_fps", 0) * 100) / 100) + "\n"
		text += "  Average Outgoing FPS: " + str(round(avg_results.get("avg_outgoing_fps", 0) * 100) / 100) + "\n"
		text += "  Max Engine FPS: " + str(round(avg_results.get("max_fps", 0) * 100) / 100) + "\n"
		text += "  Min Engine FPS: " + str(round(avg_results.get("min_fps", 0) * 100) / 100) + "\n"
		text += "  Test Passes: " + str(avg_results.get("pass_count", 0)) + "\n"
		
		# Status indicator
		var avg_fps = avg_results.get("avg_fps", 0)
		if avg_fps >= engine_fps_goal:
			text += "  Status: ✓ MEETS ENGINE FPS GOAL\n"
		else:
			text += "  Status: ⚠ BELOW ENGINE FPS GOAL\n"
	
	return text

func log_adaptive_results_to_console():
	print("\n================================================================================")
	print("ADAPTIVE BENCHMARK RESULTS AND RECOMMENDATIONS")
	print("================================================================================")
	
	print("\nTEST CONFIGURATION:")
	print("  Engine FPS Goal: " + str(engine_fps_goal) + " (minimum acceptable)")
	print("  Engine FPS Max: " + str(engine_fps_max) + " (target range)")
	print("  Outgoing FPS Range: " + str(outgoing_fps_min) + " - " + str(outgoing_fps_goal) + " FPS")
	print("  Test Passes per Rate: " + str(test_passes_per_rate))
	
	# Separate CPU and GPU results for console logging
	var cpu_results = []
	var gpu_results = []
	
	for result in adaptive_test_results:
		var metadata = result.get("adaptive_test_metadata", {})
		if metadata.get("test_type", "") == "CPU":
			cpu_results.append(result)
		elif metadata.get("test_type", "") == "GPU":
			gpu_results.append(result)
	
	# Log CPU results
	if cpu_results.size() > 0:
		print("\nCPU MODE RESULTS:")
		log_mode_results_to_console(cpu_results, "CPU")
	
	# Log GPU results
	if gpu_results.size() > 0:
		print("\nGPU MODE RESULTS:")
		log_mode_results_to_console(gpu_results, "GPU")
	
	print("\nRECOMMENDATIONS:")
	print("  " + adaptive_test_recommendations.get("recommendation_text", "No recommendation available"))
	
	print("\nHARDWARE ASSESSMENT:")
	print("  " + adaptive_test_recommendations.get("hardware_text", "No assessment available"))
	
	print("================================================================================")

func log_mode_results_to_console(mode_results: Array, mode_name: String):
	# Group results by refresh rate for this mode
	var rates_tested = []
	for result in mode_results:
		var metadata = result.get("adaptive_test_metadata", {})
		var rate = metadata.get("outgoing_fps_target", 0)
		if rate not in rates_tested:
			rates_tested.append(rate)
	
	rates_tested.sort()
	
	for rate in rates_tested:
		var avg_results = calculate_average_results_for_rate_and_mode(rate, mode_name)
		print("\n  Outgoing FPS: " + str(rate) + " FPS")
		print("    Average Engine FPS: " + str(round(avg_results.get("avg_fps", 0) * 100) / 100))
		print("    Average Outgoing FPS: " + str(round(avg_results.get("avg_outgoing_fps", 0) * 100) / 100))
		print("    Max Engine FPS: " + str(round(avg_results.get("max_fps", 0) * 100) / 100))
		print("    Min Engine FPS: " + str(round(avg_results.get("min_fps", 0) * 100) / 100))
		print("    Test Passes: " + str(avg_results.get("pass_count", 0)))
		
		# Status indicator
		var avg_fps = avg_results.get("avg_fps", 0)
		if avg_fps >= engine_fps_goal:
			print("    Status: ✓ MEETS ENGINE FPS GOAL")
		else:
			print("    Status: ⚠ BELOW ENGINE FPS GOAL")

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
		print("  ✓ Outgoing FPS: HIGH (" + str(round(avg_outgoing_fps * 100) / 100) + " FPS)")
	elif avg_outgoing_fps >= 5:
		print("  ⚠ Outgoing FPS: MEDIUM (" + str(round(avg_outgoing_fps * 100) / 100) + " FPS)")
	else:
		print("  ✗ Outgoing FPS: LOW (" + str(round(avg_outgoing_fps * 100) / 100) + " FPS)")
	
	if max_outgoing_fps >= 20:
		print("  ✓ Peak Outgoing FPS: EXCELLENT (" + str(round(max_outgoing_fps * 100) / 100) + " FPS)")
	elif max_outgoing_fps >= 10:
		print("  ⚠ Peak Outgoing FPS: GOOD (" + str(round(max_outgoing_fps * 100) / 100) + " FPS)")
	else:
		print("  ✗ Peak Outgoing FPS: POOR (" + str(round(max_outgoing_fps * 100) / 100) + " FPS)")
	
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
	print("  CPU Average Outgoing FPS: " + str(round(cpu_avg_outgoing * 100) / 100) + " FPS")
	print("  GPU Average Outgoing FPS: " + str(round(gpu_avg_outgoing * 100) / 100) + " FPS")
	
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
	is_adaptive_test = false
	current_outgoing_fps_target = 0.0
	current_pass = 0
	current_adaptive_mode = ""
	adaptive_test_phases_completed = 0
	test_results.clear()
	adaptive_test_results.clear()
	adaptive_test_recommendations.clear()
	
	# Reset convergence tracking
	tested_fps_rates.clear()
	convergence_attempts = 0
	
	# Reset UI
	update_status("Ready")
	update_fps_display(0)
	update_progress_bar(0.0)
	results_text.text = "Results will appear here..."
	
	# Stop sensor refresh cycle
	if sensor_grid:
		sensor_grid.stop_refresh_cycle()
	
	print("Test reset")
