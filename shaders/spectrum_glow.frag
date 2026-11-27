#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float u_time;
    float u_boostNorm;
    float u_peakLevel;
    float u_active;
    float u_limiterHit;
};

void main() {
    vec2 uv = qt_TexCoord0;
    // Soft luminous horizontal specular ribbon + bloom glow behind the spectrum bars
    float centerY = 1.0 - uv.y;

    vec3 lowCol = vec3(0.10, 0.84, 0.58);
    vec3 midCol = vec3(0.16, 0.66, 1.0);
    vec3 highCol = mix(vec3(1.0, 0.55, 0.16), vec3(1.0, 0.24, 0.28), u_limiterHit);

    vec3 grad = mix(lowCol, midCol, smoothstep(0.15, 0.55, uv.x));
    grad = mix(grad, highCol, smoothstep(0.55, 0.95, uv.x));

    float wave = 0.5 + 0.5 * sin(uv.x * 14.0 - u_time * 3.5);
    float floorGlow = exp(-centerY * 4.5) * (0.18 + 0.35 * u_peakLevel * u_active + 0.15 * u_boostNorm * u_active);
    float horizonLine = smoothstep(0.03, 0.0, abs(centerY - 0.02)) * (0.25 + 0.45 * u_active);

    vec3 col = grad * (floorGlow * (0.85 + 0.15 * wave) + horizonLine);
    float alpha = clamp(floorGlow + horizonLine * 0.6, 0.0, 0.85);

    fragColor = vec4(col, alpha) * qt_Opacity;
}
