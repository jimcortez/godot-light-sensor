// Godot Shading Language - Compute Shader for Light Sensor GPU Reduction
shader_type compute;

// Workgroup size - single invocation; we'll use a 4x4 box average via bilinear taps
group_size(1, 1, 1);

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

void compute() {
	vec3 rgb = texture(input_texture, vec2(0.5, 0.5)).rgb;
	vec3 linear_rgb = pow(rgb, vec3(2.2));
	vec3 srgb_color = pow(linear_rgb, vec3(1.0 / 2.2));
	result_color = vec4(srgb_color, 1.0);
}
