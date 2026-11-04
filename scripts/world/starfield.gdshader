shader_type sky;

// The background behind everything: deep space and stars. Nothing else.
//
// This shader deliberately knows NOTHING about atmospheres or the star. Sky
// colour, haze, limb glow and aerial perspective come from the scattering pass
// (atmosphere_scatter.gdshader) compositing on top of this. That split is why
// there is no "up" anywhere in here - the old sky shader built its gradient
// around EYEDIR.y, i.e. the WORLD Y axis, which is only the player's real up
// at the north pole and tilted everywhere else on a spherical planet.
//
// One shader for every body and for open space; nothing here is per-planet.

uniform vec3 space_color : source_color = vec3(0.004, 0.005, 0.012);

uniform float star_density : hint_range(40.0, 600.0) = 220.0;
// Fraction of cells that contain a star at all.
uniform float star_coverage : hint_range(0.0, 0.2) = 0.055;
uniform float star_brightness : hint_range(0.0, 8.0) = 2.7;
// Angular radius of a star, in units of one cell.
uniform float star_size : hint_range(0.01, 0.6) = 0.16;

// Faint galactic background. Real deep-space photography is not black with
// dots - there is structure between the stars, and it is what makes a sky read
// as a place rather than a void. Kept dim on purpose: this sits behind
// everything and should be felt, not noticed.
uniform float nebula_intensity : hint_range(0.0, 3.0) = 0.75;
uniform vec3 nebula_warm : source_color = vec3(0.85, 0.42, 0.18);
uniform vec3 nebula_cool : source_color = vec3(0.20, 0.30, 0.75);
// Higher = fewer, tighter clouds with more black between them. Below ~1.5 the
// noise covers the whole sky evenly and reads as fog rather than structure.
uniform float nebula_contrast : hint_range(0.5, 6.0) = 2.2;
// Density below this is empty sky. Raising it carves more black between clouds.
uniform float nebula_floor : hint_range(0.0, 0.9) = 0.46;

uint hash_cell(uvec3 p) {
	p *= uvec3(uint(374761393), uint(668265263), uint(1274126177));
	uint h = p.x ^ p.y ^ p.z;
	h *= uint(1274126177);
	return h ^ (h >> uint(15));
}

float hash_f(uvec3 c, uint salt) {
	return float(hash_cell(c + uvec3(salt)) & uint(0xffffff)) / float(0xffffff);
}

// Stars are hashed from a 3D cell on the unit sphere, NOT from a 2D
// projection. The previous version used `floor((dir.xz + 1.0) * 260.0)`,
// which squashes toward the poles of the Y axis - so stars near straight up
// or straight down smeared into streaks. A 3D cell has roughly the same
// solid angle everywhere, so stars stay points in every direction.
vec3 stars(vec3 dir) {
	vec3 p = dir * star_density;
	uvec3 cell = uvec3(ivec3(floor(p)) + ivec3(1024));

	float present = hash_f(cell, uint(0));
	if (present > star_coverage) {
		return vec3(0.0);
	}

	// Jitter the star inside its own cell so the field doesn't read as a grid.
	vec3 offset = vec3(
		hash_f(cell, uint(1)),
		hash_f(cell, uint(2)),
		hash_f(cell, uint(3)));
	vec3 star_dir = normalize((floor(p) + offset) / star_density);

	float d = distance(dir, star_dir) * star_density;
	float falloff = 1.0 - smoothstep(0.0, star_size, d);
	if (falloff <= 0.0) {
		return vec3(0.0);
	}

	// Magnitude and colour temperature vary per star: mostly dim white, a few
	// bright ones, tinted warm or cool.
	float mag = hash_f(cell, uint(4));
	mag = mag * mag * mag;
	float temp = hash_f(cell, uint(5));
	vec3 tint = mix(vec3(1.0, 0.86, 0.72), vec3(0.76, 0.85, 1.0), temp);

	return tint * falloff * mag * star_brightness;
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n = 0.0;
	// Trilinear blend of the eight lattice corners.
	for (int c = 0; c < 8; c++) {
		vec3 corner = vec3(float(c & 1), float((c >> 1) & 1), float((c >> 2) & 1));
		float w = mix(1.0 - f.x, f.x, corner.x)
			* mix(1.0 - f.y, f.y, corner.y)
			* mix(1.0 - f.z, f.z, corner.z);
		n += hash_f(uvec3(ivec3(i + corner) + ivec3(512)), uint(7)) * w;
	}
	return n;
}

// Four octaves, each rotated off-axis. Without the rotation every octave lines
// its features up on the same world axes and the result reads as a grid of
// blobs - the same failure the terrain shader had.
float fbm(vec3 p) {
	const mat3 ROT = mat3(
		vec3(0.00, 0.80, 0.60),
		vec3(-0.80, 0.36, -0.48),
		vec3(-0.60, -0.48, 0.64));
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p = ROT * p * 2.03;
		amp *= 0.5;
	}
	return sum;
}

vec3 nebula(vec3 dir) {
	if (nebula_intensity <= 0.0) {
		return vec3(0.0);
	}
	float density = fbm(dir * 2.4);
	// A second, offset field decides the HUE rather than reusing the density
	// field: keyed off density alone, colour and brightness move together and
	// every cloud ends up the same colour at the same thickness.
	float hue = fbm(dir * 1.7 + vec3(19.3, 7.1, 41.6));
	// Remapped BEFORE the contrast curve. fbm sums to roughly 0.5 on average and
	// never reaches 0 or 1, so raising it to a power directly still leaves a
	// non-zero floor across the entire sky - which reads as fog, not clouds.
	// Subtracting the floor first is what creates genuine empty sky between the
	// filaments.
	density = clamp((density - nebula_floor) / max(1.0 - nebula_floor, 0.001), 0.0, 1.0);
	density = pow(density, nebula_contrast);
	vec3 tint = mix(nebula_cool, nebula_warm, clamp(hue * 1.6 - 0.2, 0.0, 1.0));
	return tint * density * nebula_intensity;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	// No sun disc here any more. The star is real geometry now (see Star.gd),
	// so painting one on the sky as well would double-draw it - and a painted
	// disc is at infinity, so it would show THROUGH the actual star and could
	// never be approached or occluded.
	COLOR = space_color + nebula(dir) + stars(dir);
}
