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
	
	# Outgoing FPS Performance
	text += "[font_size=16][b]Outgoing FPS:[/b][/font_size]\n"
	text += "Average Outgoing FPS: " + str(round(results.get("avg_outgoing_fps", 0) * 100) / 100) + "\n"
	text += "Max Outgoing FPS: " + str(round(results.get("max_outgoing_fps", 0) * 100) / 100) + "\n"
	text += "Min Outgoing FPS: " + str(round(results.get("min_outgoing_fps", 0) * 100) / 100) + "\n"
	text += "Outgoing FPS Samples: " + str(results.get("outgoing_fps_samples", 0)) + "\n"
	text += "Refresh Calls: " + str(results.get("refresh_call_count", 0)) + "\n"
	text += "Values Refreshed: " + str(results.get("values_refreshed_count", 0)) + "\n\n"
	
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
	
	# Outgoing FPS comparison
	var cpu_avg_outgoing = cpu_results.get("avg_outgoing_fps", 0)
	var gpu_avg_outgoing = gpu_results.get("avg_outgoing_fps", 0)
	
	if cpu_avg_outgoing > 0 and gpu_avg_outgoing > 0:
		var outgoing_ratio = gpu_avg_outgoing / cpu_avg_outgoing
		text += "Outgoing FPS: GPU is " + str(round(outgoing_ratio * 100) / 100) + "x " + ("higher" if outgoing_ratio > 1 else "lower") + " than CPU\n"
	
	# Max Outgoing FPS comparison
	var cpu_max_outgoing = cpu_results.get("max_outgoing_fps", 0)
	var gpu_max_outgoing = gpu_results.get("max_outgoing_fps", 0)
	
	if cpu_max_outgoing > 0 and gpu_max_outgoing > 0:
		var max_outgoing_ratio = gpu_max_outgoing / cpu_max_outgoing
		text += "Max Outgoing FPS: GPU is " + str(round(max_outgoing_ratio * 100) / 100) + "x " + ("higher" if max_outgoing_ratio > 1 else "lower") + " than CPU\n"
	
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
	
	# Max Outgoing FPS comparison
	var cpu_max_outgoing = cpu_results.get("max_outgoing_fps", 0)
	var gpu_max_outgoing = gpu_results.get("max_outgoing_fps", 0)
	print("\nMAX OUTGOING FPS COMPARISON:")
	print("  CPU Max Outgoing FPS: " + str(round(cpu_max_outgoing * 100) / 100) + " Hz")
	print("  GPU Max Outgoing FPS: " + str(round(gpu_max_outgoing * 100) / 100) + " Hz")
	
	if cpu_max_outgoing > 0 and gpu_max_outgoing > 0:
		var max_outgoing_ratio = gpu_max_outgoing / cpu_max_outgoing
		if max_outgoing_ratio > 1:
			print("  → GPU achieves " + str(round(max_outgoing_ratio * 100) / 100) + "x HIGHER peak outgoing FPS than CPU")
		else:
			print("  → CPU achieves " + str(round((1.0 / max_outgoing_ratio) * 100) / 100) + "x HIGHER peak outgoing FPS than GPU")
	
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
	
	# Outgoing FPS component (30% weight)
	var avg_outgoing_fps = results.get("avg_outgoing_fps", 0)
	var outgoing_fps_score = min(avg_outgoing_fps / 20.0, 1.0) * 30.0
	score += outgoing_fps_score
	
	# Max Outgoing FPS component (30% weight)
	var max_outgoing_fps = results.get("max_outgoing_fps", 0)
	var max_outgoing_score = min(max_outgoing_fps / 30.0, 1.0) * 30.0
	score += max_outgoing_score
	
	return score

func clear_results():
	update_results_display("Results cleared. Ready for new tests...")
