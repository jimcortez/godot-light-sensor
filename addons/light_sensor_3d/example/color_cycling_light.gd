extends Node3D

## Color cycling light that cycles through the full color spectrum
## Speed is configurable and affects the rate of color change

@export var cycle_speed: float = 0.025
@export var light_energy: float = 1.0
@export var cycle_enabled: bool = true

var spot_light: SpotLight3D
var cycle_time: float = 0.0

func _ready():
	# Get the spot light child
	spot_light = get_node("SpotLight3D")
	if spot_light:
		spot_light.light_energy = light_energy

func _process(delta):
	if not cycle_enabled or not spot_light:
		return
	
	cycle_time += delta * cycle_speed
	
	# Cycle through HSV color space
	var hue = fmod(cycle_time, 1.0)
	var color = Color.from_hsv(hue, 1.0, 1.0)
	
	# Apply color to the light
	spot_light.light_color = color
	
	# Debug: Print color changes every 2 seconds (disabled)
	# if int(cycle_time) % 2 == 0 and cycle_time - delta < int(cycle_time):
	#	print("Light " + str(get_name()) + " color: " + str(color) + " (hue: " + str(hue) + ")")

func set_cycle_speed(speed: float):
	cycle_speed = speed

func set_light_energy(energy: float):
	light_energy = energy
	if spot_light:
		spot_light.light_energy = energy

func set_cycle_enabled(enabled: bool):
	cycle_enabled = enabled
