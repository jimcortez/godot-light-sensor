extends Control

## UI component for displaying benchmark results
## Provides a clean interface for viewing test results and statistics

var results_data: Dictionary = {}

func _ready():
	# Initialize with default text
	update_results_display("Ready to run benchmark tests...")

func update_results_display(text: String):
	var results_text = get_node("VBoxContainer/ResultsText")
	if results_text:
		results_text.text = text
		# Ensure font size is applied
		results_text.add_theme_font_size_override("normal_font_size", 16)

func display_cpu_results(results: Dictionary):
	var text = "[font_size=20][b]CPU Test Results[/b][/font_size]\n\n"
	text += format_results(results)
	update_results_display(text)

func display_gpu_results(results: Dictionary):
	var text = "[font_size=20][b]GPU Test Results[/b][/font_size]\n\n"
	text += format_results(results)
	update_results_display(text)

func display_batch_results(cpu_results: Dictionary, gpu_results: Dictionary):
	var text = "[font_size=20][b]Batch Test Results[/b][/font_size]\n\n"
	
	text += "[font_size=18][b]CPU Performance:[/b][/font_size]\n"
	text += format_results(cpu_results)
	text += "\n"
	
	text += "[font_size=18][b]GPU Performance:[/b][/font_size]\n"
	text += format_results(gpu_results)
	text += "\n"
	
	text += "[font_size=18][b]Performance Comparison:[/b][/font_size]\n"
	text += compare_results(cpu_results, gpu_results)
	
	update_results_display(text)
	
	# Log batch comparison to console
	log_batch_comparison_to_console(cpu_results, gpu_results)

func format_results(results: Dictionary) -> String:
	var text = ""
	
	# FPS Statistics
	text += "[font_size=16][b]FPS Statistics:[/b][/font_size]\n"
	text += "Average FPS: " + str(round(results.get("avg_fps", 0) * 100) / 100) + "\n"
	text += "Max FPS: " + str(round(results.get("max_fps", 0) * 100) / 100) + "\n"
	text += "Min FPS: " + str(round(results.get("min_fps", 0) * 100) / 100) + "\n"
	text += "FPS Samples: " + str(results.get("fps_samples", 0)) + "\n\n"
	
	# Refresh Performance
	text += "[font_size=16][b]Refresh Performance:[/b][/font_size]\n"
	text += "Average Refresh Time: " + str(round(results.get("avg_refresh_time", 0) * 1000) / 1000) + "s\n"
	text += "Max Refresh Time: " + str(round(results.get("max_refresh_time", 0) * 1000) / 1000) + "s\n"
	text += "Min Refresh Time: " + str(round(results.get("min_refresh_time", 0) * 1000) / 1000) + "s\n"
	text += "Refresh Count: " + str(results.get("refresh_count", 0)) + "\n"
	text += "Max Refresh Frequency: " + str(round(results.get("max_refresh_frequency", 0) * 100) / 100) + " Hz\n\n"
	
	# Test Configuration
	text += "[font_size=16][b]Test Configuration:[/b][/font_size]\n"
	text += "Sensor Count: " + str(results.get("sensor_count", 0)) + "\n"
	text += "Test Duration: " + str(round(results.get("test_duration", 0) * 100) / 100) + "s\n"
	
	return text

func compare_results(cpu_results: Dictionary, gpu_results: Dictionary) -> String:
	var text = ""
	
	# FPS comparison
	var cpu_avg_fps = cpu_results.get("avg_fps", 0)
	var gpu_avg_fps = gpu_results.get("avg_fps", 0)
	
	if cpu_avg_fps > 0 and gpu_avg_fps > 0:
		var fps_ratio = gpu_avg_fps / cpu_avg_fps
		text += "FPS Performance: GPU is " + str(round(fps_ratio * 100) / 100) + "x " + ("faster" if fps_ratio > 1 else "slower") + " than CPU\n"
	
	# Refresh time comparison
	var cpu_avg_refresh = cpu_results.get("avg_refresh_time", 0)
	var gpu_avg_refresh = gpu_results.get("avg_refresh_time", 0)
	
	if cpu_avg_refresh > 0 and gpu_avg_refresh > 0:
		var refresh_ratio = cpu_avg_refresh / gpu_avg_refresh
		text += "Refresh Speed: GPU is " + str(round(refresh_ratio * 100) / 100) + "x " + ("faster" if refresh_ratio > 1 else "slower") + " than CPU\n"
	
	# Refresh frequency comparison
	var cpu_max_freq = cpu_results.get("max_refresh_frequency", 0)
	var gpu_max_freq = gpu_results.get("max_refresh_frequency", 0)
	
	if cpu_max_freq > 0 and gpu_max_freq > 0:
		var freq_ratio = gpu_max_freq / cpu_max_freq
		text += "Max Refresh Frequency: GPU is " + str(round(freq_ratio * 100) / 100) + "x " + ("higher" if freq_ratio > 1 else "lower") + " than CPU\n"
	
	return text

func log_batch_comparison_to_console(cpu_results: Dictionary, gpu_results: Dictionary):
	print("\n================================================================================")
	print("BATCH TEST COMPARISON: CPU vs GPU PERFORMANCE")
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
	
	# Refresh time comparison
	var cpu_avg_refresh = cpu_results.get("avg_refresh_time", 0)
	var gpu_avg_refresh = gpu_results.get("avg_refresh_time", 0)
	print("\nREFRESH SPEED COMPARISON:")
	print("  CPU Average Refresh Time: " + str(round(cpu_avg_refresh * 1000) / 1000) + "s")
	print("  GPU Average Refresh Time: " + str(round(gpu_avg_refresh * 1000) / 1000) + "s")
	
	if cpu_avg_refresh > 0 and gpu_avg_refresh > 0:
		var refresh_ratio = cpu_avg_refresh / gpu_avg_refresh
		if refresh_ratio > 1:
			print("  → GPU is " + str(round(refresh_ratio * 100) / 100) + "x FASTER than CPU")
		else:
			print("  → CPU is " + str(round((1.0 / refresh_ratio) * 100) / 100) + "x FASTER than GPU")
	
	# Refresh frequency comparison
	var cpu_max_freq = cpu_results.get("max_refresh_frequency", 0)
	var gpu_max_freq = gpu_results.get("max_refresh_frequency", 0)
	print("\nREFRESH FREQUENCY COMPARISON:")
	print("  CPU Max Refresh Frequency: " + str(round(cpu_max_freq * 100) / 100) + " Hz")
	print("  GPU Max Refresh Frequency: " + str(round(gpu_max_freq * 100) / 100) + " Hz")
	
	if cpu_max_freq > 0 and gpu_max_freq > 0:
		var freq_ratio = gpu_max_freq / cpu_max_freq
		if freq_ratio > 1:
			print("  → GPU achieves " + str(round(freq_ratio * 100) / 100) + "x HIGHER frequency than CPU")
		else:
			print("  → CPU achieves " + str(round((1.0 / freq_ratio) * 100) / 100) + "x HIGHER frequency than GPU")
	
	# Overall assessment
	print("\nOVERALL PERFORMANCE ASSESSMENT:")
	var cpu_score = calculate_performance_score(cpu_results)
	var gpu_score = calculate_performance_score(gpu_results)
	
	print("  CPU Performance Score: " + str(round(cpu_score * 100) / 100) + "/100")
	print("  GPU Performance Score: " + str(round(gpu_score * 100) / 100) + "/100")
	
	if gpu_score > cpu_score:
		var improvement = ((gpu_score - cpu_score) / cpu_score) * 100
		print("  → GPU shows " + str(round(improvement * 100) / 100) + "% improvement over CPU")
	elif cpu_score > gpu_score:
		var improvement = ((cpu_score - gpu_score) / gpu_score) * 100
		print("  → CPU shows " + str(round(improvement * 100) / 100) + "% improvement over GPU")
	else:
		print("  → CPU and GPU performance are comparable")
	
	print("================================================================================")

func calculate_performance_score(results: Dictionary) -> float:
	var score = 0.0
	
	# FPS component (40% weight)
	var avg_fps = results.get("avg_fps", 0)
	var fps_score = min(avg_fps / 60.0, 1.0) * 40.0
	score += fps_score
	
	# Refresh frequency component (30% weight)
	var max_freq = results.get("max_refresh_frequency", 0)
	var freq_score = min(max_freq / 20.0, 1.0) * 30.0
	score += freq_score
	
	# Refresh speed component (30% weight)
	var avg_refresh = results.get("avg_refresh_time", 0)
	var refresh_score = max(0, (0.5 - avg_refresh) / 0.5) * 30.0
	score += refresh_score
	
	return score

func clear_results():
	update_results_display("Results cleared. Ready for new tests...")
