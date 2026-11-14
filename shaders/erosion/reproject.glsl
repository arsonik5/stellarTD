#[compute]
#version 450

// Equirectangular bake result -> the projection godot_voxel's SdfSphereHeightmap node reads (SphereUV in GDScript).
// For each output pixel: its direction under the node's mapping, then a bilinear read of the equirectangular source
// at that direction (pixel centres, as generate.glsl writes them). Longitude wraps, latitude clamps.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, r32f) uniform restrict readonly image2D src;
layout(set = 0, binding = 1, r32f) uniform restrict writeonly image2D dst;

layout(push_constant, std430) uniform Params {
	int width;
	int height_px;
	int pad0;
	int pad1;
} p;

float cbrt_s(float v) { return sign(v) * pow(abs(v), 1.0 / 3.0); }

float src_at(int x, int y) {
	x = x < 0 ? x + p.width : (x >= p.width ? x - p.width : x);
	y = clamp(y, 0, p.height_px - 1);
	return imageLoad(src, ivec2(x, y)).r;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= p.width || px.y >= p.height_px || p.pad0 + p.pad1 != 0) { return; }   // pads read so they are not stripped
	// node: u = 0.5 - atan2(z, x) / TAU, v = 0.5 - 0.5 * (y^3 + y) / 2, sampled at corners (u * width)
	float u = float(px.x) / float(p.width);
	float v = float(px.y) / float(p.height_px);
	float lon = (0.5 - u) * 6.28318530718;
	float s = (0.5 - v) * 2.0;
	float q = sqrt(s * s + 1.0 / 27.0);
	float y = clamp(cbrt_s(s + q) + cbrt_s(s - q), -1.0, 1.0);
	float lat = asin(y);
	// equirectangular source (generate.glsl): lon = (x + 0.5) / w * TAU - PI, lat = PI/2 - (y + 0.5) / h * PI
	float fx = (lon + 3.14159265359) / 6.28318530718 * float(p.width) - 0.5;
	float fy = (1.57079632679 - lat) / 3.14159265359 * float(p.height_px) - 0.5;
	fx = mod(fx, float(p.width));
	int x0 = int(floor(fx));
	int y0 = int(floor(fy));
	float tx = fx - float(x0);
	float ty = fy - float(y0);
	float a = mix(src_at(x0, y0), src_at(x0 + 1, y0), tx);
	float b = mix(src_at(x0, y0 + 1), src_at(x0 + 1, y0 + 1), tx);
	imageStore(dst, px, vec4(mix(a, b, ty), 0.0, 0.0, 0.0));
}
