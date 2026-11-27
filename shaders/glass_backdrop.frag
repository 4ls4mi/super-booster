#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_boostNorm;   // 0.0 (0%) .. 1.0 (500%)
    float u_peakLevel;   // 0.0 .. 1.0 live audio energy
    float u_active;      // 0.0 or 1.0
    vec2 u_resolution;
    vec2 u_mouse;        // normalized 0..1 cursor position
};

// Smooth procedural noise for subtle glass grain & ambient light
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 aspect = vec2(u_resolution.x / max(u_resolution.y, 1.0), 1.0);
    vec2 p = (uv - 0.5) * aspect;

    // Deep obsidian base
    vec3 baseCol = vec3(0.045, 0.055, 0.078);

    // Dynamic palette shifts with boost level:
    // Standby: slate blue -> Active 100%: emerald/cyan -> SuperBoost 300-500%: amber/coral
    vec3 coolCol = mix(vec3(0.10, 0.42, 0.85), vec3(0.08, 0.78, 0.58), u_active);
    vec3 hotCol = vec3(1.0, 0.42, 0.16);
    float heat = smoothstep(0.45, 0.95, u_boostNorm) * u_active;
    vec3 accent = mix(coolCol, hotCol, heat);

    // Animated ambient light blobs
    vec2 orb1 = vec2(sin(u_time * 0.45) * 0.35, cos(u_time * 0.35) * 0.25);
    vec2 orb2 = vec2(cos(u_time * 0.30) * 0.40, sin(u_time * 0.55) * 0.30);

    float d1 = length(p - orb1);
    float d2 = length(p - orb2);
    float glow1 = exp(-d1 * 2.8) * (0.18 + 0.22 * u_peakLevel * u_active);
    float glow2 = exp(-d2 * 3.4) * (0.12 + 0.16 * u_boostNorm * u_active);

    // Subtle cursor specular highlight on frosted glass
    vec2 mp = (u_mouse - 0.5) * aspect;
    float dm = length(p - mp);
    float mouseGlow = exp(-dm * 5.0) * 0.08;

    // Diagonal glass sheen
    float sheen = smoothstep(0.35, 0.0, abs(uv.x * 0.7 + uv.y * 0.5 - 0.55 + sin(u_time * 0.2) * 0.04));

    vec3 col = baseCol;
    col += accent * glow1;
    col += mix(vec3(0.16, 0.58, 0.95), vec3(0.95, 0.65, 0.20), heat) * glow2;
    col += vec3(0.75, 0.90, 1.0) * mouseGlow;
    col += vec3(0.18, 0.24, 0.34) * sheen * 0.09;

    // Fine frosted glass dithering grain (prevents banding)
    float grain = (hash21(uv * u_resolution + fract(u_time)) - 0.5) * 0.014;
    col += grain;

    // Soft glass edge vignette & specular border
    float edgeX = min(uv.x, 1.0 - uv.x) * u_resolution.x;
    float edgeY = min(uv.y, 1.0 - uv.y) * u_resolution.y;
    float borderDist = min(edgeX, edgeY);
    float rim = smoothstep(2.0, 0.0, borderDist) * 0.25;
    col += mix(vec3(0.45, 0.60, 0.85), accent, 0.5) * rim;

    fragColor = vec4(col, 0.96) * qt_Opacity;
}
