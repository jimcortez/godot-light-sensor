extends Node

## GPU Compute Manager for Light Sensor 3D
## Manages RenderingDevice resources and async compute pipeline for light sampling

signal sensor_result_ready(id: int, color: Color)

# Configuration
@export var use_gpu_compute: bool = true

# RenderingDevice and compute resources
var _rd: RenderingDevice
var _shader_rid: RID
var _pipeline_rid: RID
var _shared_sampler_rid: RID = RID()
var _frame_fence_rid: RID = RID()
var _last_submit_frame: int = -1
var _inflight_submit: bool = false

# Per-sensor state
class SensorState:
	var id: int
	var node_ref: WeakRef
	var viewport_tex_rid: RID
	var sampler_rid: RID = RID()
	var output_buffers: Array[RID] = []
	var fences: Array[RID] = []
	var uniform_sets: Array[RID] = []
	var buffer_index: int = 0
	var pending: bool = false
	var results_read: bool = false
	var last_result: Color = Color.BLACK
	var texture_size: Vector2i = Vector2i(4, 4)  # Store actual texture size
	var rd_texture_rid: RID = RID()
	var texture_set_rid: RID = RID()
	var buffer_set_rid: RID = RID()
	var last_buffer_index: int = -1

var _next_id: int = 1
var _sensors: Dictionary = {} # id -> SensorState
var _pending_queue: Array[int] = []
var _frame_count: int = 0

func _ready() -> void:
	# Add to group for easier discovery
	add_to_group("light_sensor_compute_manager")
	
	# print("LightSensorComputeManager: Initializing... (use_gpu_compute: " + str(use_gpu_compute) + ")")
	
	if not use_gpu_compute:
		# print_debug("LightSensorComputeManager: GPU compute disabled by configuration.")
		return
		
	# Use a local RenderingDevice (only local devices can submit/dispatch from scripts)
	_rd = RenderingServer.create_local_rendering_device()
	if _rd == null:
		push_error("LightSensorComputeManager: Failed to create RenderingDevice for GPU compute. System will crash when GPU compute is requested.")
		# Don't set use_gpu_compute = false - let the system crash when GPU compute is requested
		return
	
	# print_debug("LightSensorComputeManager: RenderingDevice created successfully.")
	_setup_compute_resources()

func _setup_compute_resources() -> void:
	if _rd == null:
		push_error("LightSensorComputeManager: Cannot setup compute resources - RenderingDevice is null. System will crash when GPU compute is requested.")
		return
	
	# Load GLSL shader file and get SPIR-V bytecode
	var shader_file_rd := load("res://addons/light_sensor_3d/compute/light_sensor.glsl")
	if shader_file_rd == null:
		push_error("LightSensorComputeManager: Failed to load GLSL shader file. System will crash when GPU compute is requested.")
		return
	
	var shader_spirv: RDShaderSPIRV = shader_file_rd.get_spirv()
	if shader_spirv == null:
		push_error("LightSensorComputeManager: Failed to get SPIRV from GLSL shader file. System will crash when GPU compute is requested.")
		return
	
	_shader_rid = _rd.shader_create_from_spirv(shader_spirv)
	if _shader_rid == RID():
		push_error("LightSensorComputeManager: Failed to create compute shader from SPIRV. System will crash when GPU compute is requested.")
		return
	
	# Create compute pipeline
	_pipeline_rid = _rd.compute_pipeline_create(_shader_rid)
	if _pipeline_rid == RID():
		push_error("LightSensorComputeManager: Failed to create compute pipeline. System will crash when GPU compute is requested.")
		return
	
	# Create and cache a shared sampler reused across all sensors
	var sampler_state := RDSamplerState.new()
	samper_state_use_defaults(sampler_state)
	_shared_sampler_rid = _rd.sampler_create(sampler_state)
	if _shared_sampler_rid == RID():
		push_error("LightSensorComputeManager: Failed to create shared sampler.")
		return

	# print("LightSensorComputeManager: GPU compute resources created successfully.")

func samper_state_use_defaults(sampler_state: RDSamplerState) -> void:
	# Defaults are fine for now; tweak later (e.g., enable mipmap filtering when using mip sampling)
	# Keep linear filtering and clamp to edge to minimize sampling artifacts
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE

func _exit_tree():
	# Clean up all resources when the compute manager is destroyed
	_cleanup_all_resources()

func _cleanup_all_resources():
	# Clean up all sensor resources
	var sensor_ids = _sensors.keys()
	for sensor_id in sensor_ids:
		unregister_sensor(sensor_id)
	
	# Clean up compute resources
	if _rd != null:
		if _pipeline_rid != RID():
			_rd.free_rid(_pipeline_rid)
			_pipeline_rid = RID()
		
		if _shader_rid != RID():
			_rd.free_rid(_shader_rid)
			_shader_rid = RID()

		if _shared_sampler_rid != RID():
			_rd.free_rid(_shared_sampler_rid)
			_shared_sampler_rid = RID()

		if _frame_fence_rid != RID():
			_rd.free_rid(_frame_fence_rid)
			_frame_fence_rid = RID()
		
		# RenderingDevice cleanup is handled automatically by Godot
		_rd = null

func register_sensor(node: Node) -> int:
	var id := _next_id
	_next_id += 1
	
	var state := SensorState.new()
	state.id = id
	state.node_ref = weakref(node)
	
	# Create double-buffered output buffers and fences
	if _rd != null:
		for i in 2:
			var buffer_size := 16
			var initial_data := PackedByteArray()
			initial_data.resize(buffer_size) # Initialize with zeros
			var buffer := _rd.storage_buffer_create(buffer_size, initial_data)
			state.output_buffers.append(buffer)
			state.fences.append(RID()) # Fences created on dispatch
	else:
		push_warning("LightSensorComputeManager: Cannot create buffers - RenderingDevice is null. Sensor registration may fail.")
	
	_sensors[id] = state
	# print("LightSensorComputeManager: Registered sensor with ID: " + str(id) + " (Total sensors: " + str(_sensors.size()) + ")")
	return id

func unregister_sensor(id: int) -> void:
	if not _sensors.has(id):
		return
	
	var state: SensorState = _sensors[id]
	
	# Only attempt to free RIDs if RenderingDevice is still valid
	if _rd != null:
		# Ensure no in-flight work before freeing resources
		if _inflight_submit:
			_rd.sync()
			_inflight_submit = false

		# Avoid explicit frees to prevent invalid ID errors during teardown; rely on device cleanup.
		# Just invalidate local references.
		for i in state.output_buffers.size():
			state.output_buffers[i] = RID()
		state.uniform_sets.clear()
		state.texture_set_rid = RID()
		state.buffer_set_rid = RID()
		state.rd_texture_rid = RID()
	
	# Remove from collections regardless of RenderingDevice state
	_sensors.erase(id)
	_pending_queue.erase(id)

func enqueue_refresh(id: int, texture: Texture2D) -> void:
	if not _sensors.has(id):
		push_error("LightSensorComputeManager: Sensor ID " + str(id) + " not found.")
		return
	
	var state: SensorState = _sensors[id]
	if state.pending:
		# Skip redundant refresh requests - this is normal during high refresh rates
		# The pending work will complete and the sensor will be available for the next cycle
		return
	
	if not use_gpu_compute:
		push_error("LightSensorComputeManager: GPU compute is disabled. Cannot enqueue refresh.")
		return
	
	# Debug: Print first few enqueue calls to verify GPU compute is being used
	# if _sensors.size() <= 5 or id <= 5:
	#	print("LightSensorComputeManager: Enqueuing GPU compute for sensor ID: " + str(id))
	
	# Get texture RID from the SubViewport
	# For SubViewport textures, we need to get the actual texture resource
	var viewport_tex_rid := texture.get_rid()
	if viewport_tex_rid == RID():
		push_error("LightSensorComputeManager: Invalid texture RID for sensor " + str(id))
		return
	
	# Store the original texture RID - we'll convert it when creating uniforms
	state.viewport_tex_rid = viewport_tex_rid
	state.pending = true
	_pending_queue.append(id)

func _process(_delta: float) -> void:
	if not use_gpu_compute:
		return
	
	_frame_count += 1

	# Ensure the previous local-device submit finished before starting a new one
	if _inflight_submit and _last_submit_frame >= 0 and _frame_count > _last_submit_frame:
		_rd.sync()
		_inflight_submit = false
	_process_compute_queue()
	_poll_completed_results()

func _process_compute_queue() -> void:
	# Batch all pending sensors, prepare textures/uniforms before beginning compute list
	if _pending_queue.size() == 0:
		return

	var to_dispatch: Array[int] = []
	while _pending_queue.size() > 0:
		var sensor_id := _pending_queue.pop_front()
		if not _sensors.has(sensor_id):
			continue
		var state: SensorState = _sensors[sensor_id]
		if not state.pending:
			continue
		# Ensure texture is created/updated BEFORE starting compute list
		_ensure_sensor_texture(state)
		if state.rd_texture_rid == RID():
			continue
		# Ensure uniform sets exist for this sensor (no compute list active yet)
		_create_sensor_uniform_sets(state)
		if state.uniform_sets.size() < 2:
			continue
		to_dispatch.append(sensor_id)

	if to_dispatch.size() == 0:
		return

	var compute_list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_rid)

	for sensor_id in to_dispatch:
		var state: SensorState = _sensors[sensor_id]
		# Bind sensor-specific uniform sets
		_rd.compute_list_bind_uniform_set(compute_list, state.uniform_sets[0], 0)
		_rd.compute_list_bind_uniform_set(compute_list, state.uniform_sets[1], 1)
		# Push constants (texture size)
		var texture_size := state.texture_size
		var push_constant_data := PackedByteArray()
		push_constant_data.resize(16)
		push_constant_data.encode_s32(0, texture_size.x)
		push_constant_data.encode_s32(4, texture_size.y)
		_rd.compute_list_set_push_constant(compute_list, push_constant_data, 16)
		# Dispatch compute work
		_rd.compute_list_dispatch(compute_list, 1, 1, 1)

	_rd.compute_list_end()
	_rd.submit()
	_inflight_submit = true

	# Defer readback to the next frame without fences
	_last_submit_frame = _frame_count
	for sid in to_dispatch:
		if _sensors.has(sid):
			var st: SensorState = _sensors[sid]
			st.pending = false
			st.results_read = false

func _dispatch_compute(sensor_id: int, state: SensorState) -> void:
	# Deprecated by batched path; kept for compatibility if ever used
	# Use the batched submit path in _process_compute_queue instead
	pass

func _create_sensor_uniform_sets(state: SensorState) -> void:
	# Ensure per-sensor texture exists and is updated; create texture uniform set once
	if state.viewport_tex_rid == RID():
		push_error("LightSensorComputeManager: Invalid viewport texture RID for sensor " + str(state.id))
		return
	
	# Ensure RD texture exists and matches size; update pixels from viewport image
	_ensure_sensor_texture(state)
	if state.rd_texture_rid == RID():
		push_error("LightSensorComputeManager: Sensor RD texture not available for sensor " + str(state.id))
		return
	
	
	# Use shared sampler
	if _shared_sampler_rid == RID():
		push_error("LightSensorComputeManager: Shared sampler not initialized.")
		return
	
	# Create texture set only once or if missing
	if state.texture_set_rid == RID():
		var texture_uniform := RDUniform.new()
		texture_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		texture_uniform.binding = 0
		texture_uniform.add_id(_shared_sampler_rid)
		texture_uniform.add_id(state.rd_texture_rid)
		var texture_set := _rd.uniform_set_create([texture_uniform], _shader_rid, 0)
		if texture_set == RID():
			push_error("LightSensorComputeManager: Failed to create texture uniform set for sensor " + str(state.id))
			return
		state.texture_set_rid = texture_set
	
	# Ensure storage buffer uniform set (set 1) matches current buffer index
	if state.output_buffers.size() <= state.buffer_index or state.output_buffers[state.buffer_index] == RID():
		push_error("LightSensorComputeManager: Invalid output buffer RID for sensor " + str(state.id))
		return

	if state.buffer_set_rid == RID() or state.last_buffer_index != state.buffer_index:
		# Free previous buffer set if exists
		if state.buffer_set_rid != RID():
			_rd.free_rid(state.buffer_set_rid)
		# Create new buffer uniform set for current buffer index
		var buffer_uniform := RDUniform.new()
		buffer_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		buffer_uniform.binding = 0
		buffer_uniform.add_id(state.output_buffers[state.buffer_index])
		var buffer_set := _rd.uniform_set_create([buffer_uniform], _shader_rid, 1)
		if buffer_set == RID():
			push_error("LightSensorComputeManager: Failed to create storage buffer uniform set for sensor " + str(state.id))
			return
		state.buffer_set_rid = buffer_set
		state.last_buffer_index = state.buffer_index

	# Refresh the per-sensor uniform_sets array in the expected order
	state.uniform_sets.clear()
	state.uniform_sets.append(state.texture_set_rid)
	state.uniform_sets.append(state.buffer_set_rid)

func _create_rd_texture_from_subviewport(viewport_tex_rid: RID, sensor_id: int) -> RID:
	"""Create a RenderingDevice texture from SubViewport texture and upload pixels (CPU path)."""
	if viewport_tex_rid == RID():
		push_error("LightSensorComputeManager: Invalid viewport texture RID for sensor " + str(sensor_id))
		return RID()
	
	# Get the SubViewport texture to get dimensions
	var viewport_texture: Image = RenderingServer.texture_2d_get(viewport_tex_rid)
	if viewport_texture == null:
		push_error("LightSensorComputeManager: Failed to get texture from viewport RID for sensor " + str(sensor_id))
		return RID()
	
	var texture_size := viewport_texture.get_size()
	# print("LightSensorComputeManager: Creating texture for sensor " + str(sensor_id) + " with size " + str(texture_size))
	if texture_size.x <= 0 or texture_size.y <= 0:
		push_error("LightSensorComputeManager: Invalid texture dimensions for sensor " + str(sensor_id) + ": " + str(texture_size))
		return RID()
	
	# Store the texture size in the sensor state
	if _sensors.has(sensor_id):
		_sensors[sensor_id].texture_size = texture_size
	
	# Create a new texture in the RenderingDevice
	var texture_format := RDTextureFormat.new()
	texture_format.width = texture_size.x
	texture_format.height = texture_size.y
	texture_format.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	texture_format.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	var texture_view := RDTextureView.new()
	var rd_texture := _rd.texture_create(texture_format, texture_view)
	if rd_texture == RID():
		push_error("LightSensorComputeManager: Failed to create RD texture for sensor " + str(sensor_id))
		return RID()
	
	# Copy texture data from SubViewport to RenderingDevice texture
	# NOTE: This path performs a CPU round-trip; will be replaced with direct binding when possible
	if viewport_texture != null:
		# Ensure the image is in the correct format for the texture
		viewport_texture.convert(Image.FORMAT_RGBA8)
		var image_data := viewport_texture.get_data()
		
		# Debug: Check if the texture has any non-zero data (disabled)
		# var has_non_zero_data := false
		# for i in range(min(16, image_data.size())):  # Check first 16 bytes
		#	if image_data.decode_u8(i) > 0:
		#		has_non_zero_data = true
		#		break
		# 
		# print("LightSensorComputeManager: Texture data for sensor " + str(sensor_id) + " - has_non_zero: " + str(has_non_zero_data))
		# if has_non_zero_data:
		#	# Print first few pixel values
		#	var pixel_count = min(4, texture_size.x * texture_size.y)
		#	for i in range(pixel_count):
		#		var pixel_offset = i * 4
		#		if pixel_offset + 3 < image_data.size():
		#			var r = image_data.decode_u8(pixel_offset)
		#			var g = image_data.decode_u8(pixel_offset + 1)
		#			var b = image_data.decode_u8(pixel_offset + 2)
		#			print("  Pixel " + str(i) + ": (" + str(r) + ", " + str(g) + ", " + str(b) + ")")
		
		# Calculate expected data size
		var expected_size := texture_size.x * texture_size.y * 4  # RGBA8 = 4 bytes per pixel
		
		if image_data.size() == expected_size:
			_rd.texture_update(rd_texture, 0, image_data)
		else:
			push_error("LightSensorComputeManager: Image data size mismatch for sensor " + str(sensor_id) + " (expected: " + str(expected_size) + ", got: " + str(image_data.size()) + ")")
			_rd.free_rid(rd_texture)
			return RID()
	else:
		push_warning("LightSensorComputeManager: Could not get image from viewport texture for sensor " + str(sensor_id))
	
	return rd_texture

func _ensure_sensor_texture(state: SensorState) -> void:
	# Ensure RD texture exists and matches the viewport texture size; upload latest pixels
	if state.viewport_tex_rid == RID():
		return

	var viewport_image: Image = RenderingServer.texture_2d_get(state.viewport_tex_rid)
	if viewport_image == null:
		return

	var size := viewport_image.get_size()
	if size.x <= 0 or size.y <= 0:
		return

	var need_create := state.rd_texture_rid == RID() or state.texture_size != size
	if need_create:
		# Free previous
		if state.rd_texture_rid != RID():
			_rd.free_rid(state.rd_texture_rid)
		state.texture_size = size
		var tf := RDTextureFormat.new()
		tf.width = size.x
		tf.height = size.y
		tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		tf.mipmaps = true
		tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		var tv := RDTextureView.new()
		state.rd_texture_rid = _rd.texture_create(tf, tv)
		# Update texture uniform set to point at new texture
		if state.texture_set_rid != RID():
			_rd.free_rid(state.texture_set_rid)
			state.texture_set_rid = RID()

	# Upload pixels
	viewport_image.convert(Image.FORMAT_RGBA8)
	var bytes := viewport_image.get_data()
	var expected := size.x * size.y * 4
	if bytes.size() == expected and state.rd_texture_rid != RID():
		_rd.texture_update(state.rd_texture_rid, 0, bytes)

func _poll_completed_results() -> void:
	if _rd == null:
		push_error("LightSensorComputeManager: Cannot poll results - RenderingDevice is null. GPU compute is required.")
		return
	
	for sensor_id in _sensors.keys():
		var state: SensorState = _sensors[sensor_id]
		# Readback one frame after the last submit to avoid stalls
		if not state.pending and not state.results_read and _last_submit_frame >= 0 and _frame_count > _last_submit_frame:
			_read_sensor_result(sensor_id, state)
			state.results_read = true

func _read_sensor_result(sensor_id: int, state: SensorState) -> void:
	# Map the output buffer and read the result
	var buffer_rid := state.output_buffers[state.buffer_index]
	var bytes := _rd.buffer_get_data(buffer_rid)
	
	if bytes.size() >= 12: # At least 3 floats
		var r := bytes.decode_float(0)
		var g := bytes.decode_float(4)
		var b := bytes.decode_float(8)
		var result_color := Color(r, g, b)
		
		state.last_result = result_color
		# print("LightSensorComputeManager: Emitting sensor_result_ready for sensor " + str(sensor_id) + " with color " + str(result_color) + " (raw: " + str(r) + ", " + str(g) + ", " + str(b) + ")")
		emit_signal("sensor_result_ready", sensor_id, result_color)
	else:
		# Invalid buffer data size - silently ignore
		pass
	
	# Switch to other buffer for next dispatch
	state.buffer_index = (state.buffer_index + 1) % 2

func is_gpu_compute_available() -> bool:
	return use_gpu_compute and _rd != null and _shader_rid != RID() and _pipeline_rid != RID()

func get_debug_status() -> String:
	var status := "LightSensorComputeManager Status:\n"
	status += "  use_gpu_compute: " + str(use_gpu_compute) + "\n"
	status += "  RenderingDevice: " + ("null" if _rd == null else "available") + "\n"
	status += "  Shader RID: " + ("null" if _shader_rid == RID() else "available") + "\n"
	status += "  Pipeline RID: " + ("null" if _pipeline_rid == RID() else "available") + "\n"
	status += "  GPU Compute: " + ("ENABLED" if is_gpu_compute_available() else "DISABLED") + "\n"
	status += "  Registered sensors: " + str(_sensors.size()) + "\n"
	status += "  Pending queue: " + str(_pending_queue.size()) + "\n"
	return status

# CPU fallback removed - GPU compute is required when use_compute_mode = true
