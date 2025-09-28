extends Node

## Example script showing how to use the benchmark system programmatically
## This can be attached to any node to run automated benchmark tests

@export var auto_run_tests: bool = false
@export var test_duration: float = 10.0
@export var grid_size: int = 2

var benchmark_controller: Node

func _ready():
	# Find the benchmark controller in the scene
	benchmark_controller = get_node_or_null("../BenchmarkController")
	
	if not benchmark_controller:
		push_error("BenchmarkController not found. Make sure this script is in the benchmark scene.")
		return
	
	# Connect to benchmark signals
	benchmark_controller.connect("test_started", Callable(self, "_on_test_started"))
	benchmark_controller.connect("test_completed", Callable(self, "_on_test_completed"))
	
	# Configure benchmark parameters
	benchmark_controller.set_test_duration(test_duration)
	benchmark_controller.grid_size = grid_size
	
	if auto_run_tests:
		# Run tests automatically after a short delay
		await get_tree().create_timer(2.0).timeout
		run_automated_benchmark()

func run_automated_benchmark():
	print("Starting automated benchmark...")
	
	# Run CPU test
	print("Running CPU test...")
	benchmark_controller.start_cpu_test()
	
	# Wait for CPU test to complete
	await benchmark_controller.test_completed
	
	# Wait a bit between tests
	await get_tree().create_timer(2.0).timeout
	
	# Run GPU test
	print("Running GPU test...")
	benchmark_controller.start_gpu_test()
	
	# Wait for GPU test to complete
	await benchmark_controller.test_completed
	
	print("Automated benchmark completed!")

func _on_test_started(test_type: String):
	print("Test started: " + test_type)

func _on_test_completed(test_type: String, results: Dictionary):
	print("Test completed: " + test_type)
	print("Results: " + str(results))
	
	# You can process results here
	analyze_results(test_type, results)

func analyze_results(test_type: String, results: Dictionary):
	var avg_fps = results.get("avg_fps", 0)
	var max_refresh_freq = results.get("max_refresh_frequency", 0)
	var avg_refresh_time = results.get("avg_refresh_time", 0)
	
	print("Analysis for " + test_type + ":")
	print("  Average FPS: " + str(avg_fps))
	print("  Max Refresh Frequency: " + str(max_refresh_freq) + " Hz")
	print("  Average Refresh Time: " + str(avg_refresh_time) + "s")
	
	# Example: Check if performance meets requirements
	if avg_fps < 55:
		print("  WARNING: FPS below target threshold!")
	
	if avg_refresh_time > 0.1:
		print("  WARNING: Refresh time is high!")
	
	if max_refresh_freq > 10:
		print("  GOOD: High refresh frequency achieved!")
