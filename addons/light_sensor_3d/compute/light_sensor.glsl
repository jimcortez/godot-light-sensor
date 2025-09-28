#[compute]
#version 450

// Workgroup size - 8x8 threads for processing up to 8x8 texture samples
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// Input texture binding
layout(set = 0, binding = 0) uniform sampler2D input_texture;

// Output storage buffer for the averaged color result
layout(set = 1, binding = 0, std430) restrict buffer OutputBuffer {
	vec4 result_color; // RGB + padding for alignment
};

// Push constants for texture dimensions
layout(push_constant, std430) uniform PushConstants {
	ivec2 texture_size;
};

// Shared memory for reduction within workgroup (using integers to avoid atomic float issues)
shared ivec3 shared_sum_int;

void main() {
	// Get thread ID within workgroup
	ivec2 local_id = ivec2(gl_LocalInvocationID.xy);
	ivec2 workgroup_id = ivec2(gl_WorkGroupID.xy);
	ivec2 global_id = workgroup_id * ivec2(8, 8) + local_id;
	
	// Initialize shared memory
	if (gl_LocalInvocationIndex == 0) {
		shared_sum_int = ivec3(0);
	}
	barrier();
	
	// Each thread reads one pixel if within texture bounds
	vec3 pixel_color = vec3(0.0);
	if (global_id.x < texture_size.x && global_id.y < texture_size.y) {
		vec2 tex_coord = (vec2(global_id) + 0.5) / vec2(texture_size);
		vec4 sampled = texture(input_texture, tex_coord);
		// Convert from sRGB to linear space for proper averaging
		pixel_color = pow(sampled.rgb, vec3(2.2));
	}
	
	// Convert to fixed-point integers for atomic operations
	// Scale by 10000 to preserve precision
	ivec3 pixel_int = ivec3(pixel_color * 10000.0);
	
	// Accumulate in shared memory using integer atomics
	atomicAdd(shared_sum_int.r, pixel_int.r);
	atomicAdd(shared_sum_int.g, pixel_int.g);
	atomicAdd(shared_sum_int.b, pixel_int.b);
	barrier();
	
	// Only thread 0 writes the final result
	if (gl_LocalInvocationIndex == 0) {
		// Calculate total number of pixels processed
		int total_pixels = texture_size.x * texture_size.y;
		vec3 average_color = vec3(shared_sum_int) / float(total_pixels * 10000);
		
		// Convert back to sRGB for output
		vec3 srgb_color = pow(average_color, vec3(1.0 / 2.2));
		result_color = vec4(srgb_color, 1.0);
	}
}
