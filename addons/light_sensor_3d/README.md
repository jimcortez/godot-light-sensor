# Godot Light Sensor 3D

Do you need to find the total amount of light reaching a point in your Godot 4 3D project? Then you've come to the right place.

This asset contains a "light sensor" -- a tiny camera pointing at a tiny white plane that can be queried to determine how much light is reaching that plane. You can check the color, too, if you care about that.

## How to Use

1. Create a new node of type LightSensor3D.
2. Move it to the point you want to measure light.
3. Configure the layer.
4. Call the refresh() method on it periodically, e.g. every second.
5. Query it using the available properties, functions, and signals.

### Positioning and Orientation

The sensor is not a single point in space, capable of reading detecting light in a sphere. It's a plane, which means a couple things:
1. You'll _probably_ want to place the sensor low to the ground of your game.
2. You'll _probably_ want to orient the sensor so the sensor is pointing downwards (this is the default).

These suggestions are assuming you're measuring the amount of light some point on the ground is receiving.

### Configuring the Layer

The internal sensor mesh uses the layer you configure on the light sensor itself. You'll want to choose layer(s) based on the following principles:
1. The layer shouldn't be visible to your main camera, otherwise you'll see a small white plane near the center of the sensor.
2. The layer _should_ be visible to the lights you want to register on the light sensor, otherwise you won't get the desired readings.

### Calling the `refresh()` Method

Refreshing the sensor's state is pretty expensive, since it requires downloading data from the GPU back to the CPU (see [Texture2D#get_image](https://docs.godotengine.org/en/stable/classes/class_texture2d.html#class-texture2d-method-get-image)). In my tests, it takes on the order of 0.2ms, which is potentially a big chunk of the frame budget if you have multiple sensors updating every frame. Therefore, it's recommended to only update as often as you need -- once every 250ms or even less often.

Calling `refresh()` is left up to you. The easiest way to do this is to add a child node of the LightSensor3D of type [Timer](https://docs.godotengine.org/en/stable/classes/class_timer.html) that:
* has a wait time of 1 second, or whatever your update frequency need is.
* does **not** have one-shot enabled.
* does have autostart enabled.
* and lastly and most importantly, triggers the parent node's `refresh()` method in the `timeout` signal.

There's an included example scene that does this that you can also check out.

### Outputs

|          | name                | type                                                                     | description                                                                                            |   |   |
|----------|---------------------|--------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------|---|---|
| property | `color`             | [Color](https://docs.godotengine.org/en/stable/classes/class_color.html) | This is the current color the sensor is seeing. Always cached and available synchronously.             |   |   |
| property | `light_level`       | float                                                                    | This is the [luminance](https://en.wikipedia.org/wiki/Luminance) seen by the sensor. 0=dark, 1=bright. Always cached and available synchronously. |   |   |
| signal   | color_updated       | (color: Color)                                                           | Emitted only when the current color actually changes.                                                  |   |   |
| signal   | light_level_updated | (luminance: float)                                                       | Emitted only when the light level actually changes.                                                   |   |   |
| signal   | values_refreshed     | (color: Color, luminance: float)                                        | Emitted on every refresh, regardless of whether values changed. Useful for benchmarking.                 |   |   |

### Event-Driven Usage

The sensor now uses an event-driven approach where values are cached as properties and signals are emitted based on actual changes:

- **Synchronous Access**: You can always read `sensor.color` and `sensor.light_level` directly - these are always up-to-date with the latest refresh.
- **Change Events**: Connect to `color_updated` and `light_level_updated` to react only when values actually change.
- **Refresh Events**: Connect to `values_refreshed` to monitor every refresh cycle, useful for benchmarking and performance monitoring.

Example usage:
```gdscript
# Connect to change events for UI updates
sensor.color_updated.connect(_on_color_changed)
sensor.light_level_updated.connect(_on_light_level_changed)

# Connect to refresh events for benchmarking
sensor.values_refreshed.connect(_on_values_refreshed)

# Or just read values directly (always synchronous)
print("Current color: ", sensor.color)
print("Current light level: ", sensor.light_level)
```

Note that all of these require you to call `refresh()` before they'll be updated and triggered.

## GPU Compute Pipeline Mode

For improved performance with multiple sensors, the plugin includes an optional GPU compute pipeline that processes light sampling asynchronously on the GPU. This mode is particularly beneficial when you have many sensors or need to update them frequently.

### Enabling GPU Compute Mode

1. **Automatic Setup**: The GPU compute manager is automatically registered as an autoload singleton when the plugin is enabled.

2. **Check Availability First**: Before enabling GPU compute mode, always check if it's available:
   ```gdscript
   if sensor.check_gpu_availability():
       sensor.use_compute_mode = true
   else:
       print("GPU compute not available, using CPU mode")
   ```

3. **Per-Sensor Configuration**: Enable GPU compute mode on individual sensors by setting `use_compute_mode = true` in the inspector.

4. **Global Configuration**: The compute manager can be configured via the autoload singleton:
   - `use_gpu_compute`: Enable/disable GPU compute globally
   - `max_dispatches_per_frame`: Limit GPU work per frame (default: 4)

**Important**: If `use_compute_mode = true` is set but GPU compute is not available, the system will fail with clear error messages. No silent fallbacks are provided.

### How GPU Compute Mode Works

1. **Offscreen Rendering**: Each sensor uses a small SubViewport (1×1, 4×4, or 8×8 pixels) to render the light scene.

2. **GPU Reduction**: A compute shader processes the rendered texture and reduces it to a single averaged color using GPU parallel processing.

3. **Asynchronous Results**: Results are returned asynchronously with 1-2 frame latency, allowing multiple sensors to be processed efficiently.

### Performance Benefits

- **Scalability**: Multiple sensors can be processed in parallel without blocking the main thread
- **GPU Efficiency**: Light sampling and averaging happens entirely on the GPU
- **Reduced CPU Load**: No CPU-side texture downloads or pixel processing
- **Batched Processing**: Multiple sensors can be processed in a single frame

### Configuration Options

- **Sample Resolution**: Choose between 1×1, 4×4, or 8×8 pixel sampling (configured per sensor)
- **Max Dispatches Per Frame**: Control how many sensors can be processed per frame
- **CPU Fallback**: Automatically falls back to CPU processing if GPU compute fails

### Requirements

- Godot 4.0+ with RenderingDevice support
- Compatible GPU with compute shader support
- Shader Baker enabled in export settings (recommended for Metal/macOS)

### Troubleshooting

If GPU compute mode fails to initialize:
- Check that your GPU supports compute shaders
- Verify that RenderingDevice is available on your platform
- The system will automatically fall back to CPU processing
- Check the console for error messages about RenderingDevice creation

### Performance Notes

- Prefer 1×1 subviewport sampling when acceptable for your use case
- Use 4×4 or 8×8 sampling for higher accuracy at the cost of more GPU work
- Batch sensor updates to avoid performance spikes
- Consider using `max_dispatches_per_frame` to limit GPU work per frame