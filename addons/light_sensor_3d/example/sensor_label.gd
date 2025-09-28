extends Label3D

@export var light_probe: LightSensor3D
@export var log_color_change_event: bool
@export var log_light_level_change_event: bool

func _ready():
	# These logs are just kinda for fun.

	if log_color_change_event:
		light_probe.color_updated.connect(
			func (new_color: Color): pass)  # Logging removed
	
	if log_light_level_change_event:
		light_probe.light_level_updated.connect(
			func (new_lum: float): pass)  # Logging removed

func _process(_delta):
	text = "%.2f" % light_probe.light_level
