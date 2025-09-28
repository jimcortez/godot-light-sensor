# Light Sensor 3D Benchmark System

This benchmark system provides comprehensive performance testing for the Light Sensor 3D plugin, comparing CPU and GPU compute modes under various conditions.

## Features

- **Configurable Sensor Grid**: Test with different grid sizes (default 2x2, configurable)
- **Color Cycling Light**: Cycles through the full color spectrum at configurable speed
- **FPS Monitoring**: Real-time FPS tracking with statistics
- **Refresh Timing**: Measures time between refresh calls and completion
- **Batch Testing**: Run both CPU and GPU tests in sequence
- **Comprehensive Results**: Detailed performance metrics and comparisons

## Usage

### Running the Benchmark

1. Open the benchmark scene: `addons/light_sensor_3d/benchmark/benchmark_scene.tscn`
2. Use the control buttons to run tests:
   - **Start CPU Test**: Tests CPU-only mode
   - **Start GPU Test**: Tests GPU compute mode
   - **Start Batch Test**: Runs both CPU and GPU tests sequentially
   - **Reset**: Clears results and resets the test

### Configuration

The benchmark can be configured through the `BenchmarkController` node:

- `test_duration`: Duration of each test in seconds (default: 30)
- `grid_size`: Size of the sensor grid (default: 2x2)
- `color_cycle_speed`: Speed of color cycling (default: 1.0)
- `target_fps_threshold`: FPS threshold for performance analysis (default: 55)

### Test Metrics

The benchmark measures:

- **FPS Statistics**: Average, maximum, and minimum FPS
- **Refresh Performance**: Time between refresh calls and completion
- **Refresh Frequency**: Maximum refresh rate achieved
- **Sensor Count**: Number of sensors being tested
- **Test Duration**: Actual test duration

## Architecture

### Components

1. **BenchmarkController**: Main controller managing test execution
2. **ColorCyclingLight**: Light that cycles through color spectrum
3. **SensorGrid**: Configurable grid of light sensors
4. **BenchmarkResults**: UI component for displaying results

### Test Flow

1. **Initialization**: Set up sensor grid and configure test parameters
2. **Test Execution**: Run continuous refresh cycles while monitoring FPS
3. **Data Collection**: Gather timing and performance data
4. **Results Analysis**: Calculate statistics and generate reports
5. **Comparison**: Compare CPU vs GPU performance (for batch tests)

## Performance Considerations

- **GPU Mode**: Uses compute shaders for parallel processing
- **CPU Mode**: Uses traditional CPU-based color averaging
- **Refresh Timing**: Measures actual time from refresh call to completion
- **FPS Impact**: Monitors frame rate impact of sensor operations

## Results Interpretation

- **Higher FPS**: Better performance, less impact on frame rate
- **Lower Refresh Time**: Faster sensor response
- **Higher Refresh Frequency**: More frequent sensor updates possible
- **GPU vs CPU**: Compare relative performance between modes

## Troubleshooting

- Ensure the Light Sensor 3D plugin is properly installed
- Check that the compute manager is available for GPU tests
- Verify sensor layer configuration matches light setup
- Monitor console for any error messages during testing
