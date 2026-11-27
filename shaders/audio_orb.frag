#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_boostNorm;   // 0.0 .. 1.0 (0% .. 500%)
    float u_peakLevel;   // 0.0 .. 1.0
    float u_active;      // 0.0 or 1.0
    float u_superBoost;  // 0.0 or 1.0
};

void main() {
    vec2 uv = qt_TexCoord0 * 2.0 - 1.0;
    float r = length(uv);
    float angle = atan(uv.y, uv.x);

    // Outer transparent fade
    float mask = smoothstep(1.0, 0.72, r);
    if (mask <= 0.001) {
        fragColor = vec4(0.0);
        return;
    }

    // Ring radius pulses gently with live audio peak
    float pulse = 0.64 + 0.04 * sin(u_time * 3.0) + 0.07 * u_peakLevel * u_active;
    float ringDist = abs(r - pulse);

    // Angular progress arc matching boost 0..500% (starts at bottom-left, sweeps 270 deg)
    float startAngle = 2.35619; // 135 deg
    float rel = mod(angle - startAngle + 6.2831853, 6.2831853);
    float sweep = 4.7123889; // 270 deg
    float arcStart = smoothstep(0.0, 0.10, rel);
    float arcFill = arcStart * smoothstep(u_boostNorm * sweep + 0.08, u_boostNorm * sweep - 0.08, rel) * step(rel, sweep + 0.08);

    // Colors
    vec3 inactiveCol = vec3(0.28, 0.34, 0.45);
    vec3 normalCol = vec3(0.12, 0.85, 0.56);
    vec3 boostCol = vec3(0.18, 0.72, 1.0);
    vec3 superCol = vec3(1.0, 0.45, 0.18);

    vec3 activeCol = mix(normalCol, boostCol, smoothstep(0.18, 0.45, u_boostNorm));
    activeCol = mix(activeCol, superCol, smoothstep(0.58, 0.92, u_boostNorm));
    vec3 baseAccent = mix(inactiveCol, activeCol, u_active);

    // Halo energy around the ring
    float harmonic = 1.0 + 0.25 * u_superBoost * sin(angle * 6.0 - u_time * 4.0) * u_active;
    float ringGlow = exp(-ringDist * 14.0) * (0.30 + 0.70 * arcFill) * harmonic;
    float innerMist = exp(-r * 2.6) * (0.14 + 0.28 * u_peakLevel * u_active);

    vec3 col = baseAccent * (ringGlow + innerMist);
    float alpha = clamp((ringGlow + innerMist * 0.7) * mask, 0.0, 1.0);

    fragColor = vec4(col, alpha) * qt_Opacity;
}
