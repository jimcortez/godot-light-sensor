# Light Sensor 3D Benchmark System

This benchmark system provides comprehensive performance testing for the Light Sensor 3D plugin, comparing CPU and GPU compute modes under various conditions. It includes an advanced adaptive testing system that automatically finds optimal refresh rates for your hardware.

## Features

- **Configurable Sensor Grid**: Test with different grid sizes (default 2x2, configurable)
- **Color Cycling Light**: Cycles through the full color spectrum at configurable speed
- **FPS Monitoring**: Real-time FPS tracking with statistics
- **Refresh Timing**: Measures time between refresh calls and completion
- **Batch Testing**: Run both CPU and GPU tests in sequence
- **Adaptive Testing**: Automatically finds optimal refresh rates for your hardware
- **Hardware Recommendations**: Provides specific recommendations based on test results
- **Multiple Test Passes**: Runs multiple passes per refresh rate for accurate results
- **Comprehensive Results**: Detailed performance metrics and comparisons

## Usage

### Running the Benchmark

1. Open the benchmark scene: `addons/light_sensor_3d/benchmark/benchmark_scene.tscn`
2. Use the control buttons to run tests:
   - **Start CPU Test**: Tests CPU-only mode
   - **Start GPU Test**: Tests GPU compute mode
   - **Start Batch Test**: Runs both CPU and GPU tests sequentially
   - **Start Adaptive Test**: **NEW** - Automatically finds optimal refresh rates
   - **Reset**: Clears results and resets the test

### Adaptive Testing (Recommended)

The **Start Adaptive Test** button runs an intelligent benchmark that:

1. **Runs CPU Phase**: Tests CPU mode with adaptive refresh rates
   - Starts with target outgoing FPS (default: 40 FPS)
   - Runs multiple passes at each refresh rate for accuracy
   - Monitors engine FPS to ensure it stays above minimum threshold (default: 40 FPS)
   - Automatically adjusts outgoing FPS up/down based on performance
   - Continues until optimal refresh rate is found for CPU mode

2. **Runs GPU Phase**: Tests GPU mode with the same adaptive process
   - Resets and runs the same adaptive testing for GPU compute mode
   - Finds optimal refresh rate for GPU mode independently

3. **Provides comprehensive recommendations** comparing CPU vs GPU performance
   - Shows optimal refresh rates for both modes
   - Compares performance between CPU and GPU
   - Gives hardware-specific recommendations

### Configuration

The benchmark can be configured through the `BenchmarkController` node:

#### Basic Configuration
- `test_duration`: Duration of each test in seconds (default: 10)
- `grid_size`: Size of the sensor grid (default: 2x2)
- `color_cycle_speed`: Speed of color cycling (default: 1.0)
- `target_fps_threshold`: FPS threshold for performance analysis (default: 55)

#### Adaptive Testing Configuration
- `engine_fps_goal`: Minimum acceptable engine FPS (default: 40)
- `engine_fps_max`: Maximum expected engine FPS (default: 55)
- `outgoing_fps_goal`: Target outgoing FPS to start with (default: 40 FPS)
- `outgoing_fps_min`: Minimum outgoing FPS (default: 10 FPS)
- `outgoing_fps_step`: Step size for decreasing outgoing FPS (default: 5 FPS)
- `test_passes_per_rate`: Number of test passes per refresh rate (default: 3)

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

### Basic Metrics
- **Higher FPS**: Better performance, less impact on frame rate
- **Lower Refresh Time**: Faster sensor response
- **Higher Refresh Frequency**: More frequent sensor updates possible
- **GPU vs CPU**: Compare relative performance between modes

### Adaptive Test Results
- **Recommended Outgoing FPS**: The highest refresh rate (in FPS) that maintains acceptable engine FPS
- **Hardware Assessment**: Evaluation of your hardware's capability for sensor applications
- **Engine FPS Goal**: Whether your hardware can maintain the minimum acceptable frame rate
- **Performance Score**: Overall assessment of your hardware's performance

### Hardware Assessment
The adaptive test provides objective performance measurements:
- **High**: Achieved outgoing FPS ≥ 30 FPS
- **Medium**: Achieved outgoing FPS ≥ 20 FPS  
- **Moderate**: Achieved outgoing FPS ≥ 10 FPS
- **Low**: Achieved outgoing FPS < 10 FPS

## Troubleshooting

- Ensure the Light Sensor 3D plugin is properly installed
- Check that the compute manager is available for GPU tests
- Verify sensor layer configuration matches light setup
- Monitor console for any error messages during testing
