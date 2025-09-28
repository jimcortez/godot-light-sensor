extends Label3D

@export var light_probe: LightSensor3D
@export var log_color_change_event: bool
@export var log_light_level_change_event: bool

func _ready():
	# Connect to light probe signals for real-time updates
	light_probe.color_updated.connect(_on_color_updated)
	light_probe.light_level_updated.connect(_on_light_level_updated)
	light_probe.values_refreshed.connect(_on_values_refreshed)
	
	# Update display with initial values
	_update_display()

func _on_color_updated(new_color: Color):
	await get_tree().process_frame
	_update_display()

func _on_light_level_updated(new_lum: float):
	await get_tree().process_frame
	_update_display()

func _on_values_refreshed(new_color: Color, new_luminance: float):
	# This signal is emitted on every refresh, regardless of whether values changed
	# Useful for benchmarking and monitoring refresh cycles
	# The cached values in light_probe.color and light_probe.light_level are always up-to-date
	pass

func _update_display():
	var rgb_text = "(%.1f,%.1f,%.1f)" % [light_probe.color.r, light_probe.color.g, light_probe.color.b]
	var lum_text = "Lum:%.2f" % light_probe.light_level
	var new_text = rgb_text + "\n" + lum_text
	
	# Update the text
	text = new_text
	
	# Also try deferred update
	call_deferred("_deferred_text_update", new_text)
	
	# Debug: Print sensor updates (reduced frequency)
	if int(Time.get_time_dict_from_system()["second"]) % 2 == 0:
		print("Sensor " + str(get_name()) + " - Color: " + str(light_probe.color) + ", Luminosity: " + str(light_probe.light_level))

func _deferred_text_update(new_text: String):
	text = new_text
