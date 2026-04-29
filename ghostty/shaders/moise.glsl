// CONFIG
const float NOISE_STRENGTH = 0.015; // try 0.008–0.03 (subtle -> visible)

// Cheap, static hash noise in screen space
float hash21(vec2 p) {
    // p is in pixels
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // Base terminal color
    fragColor = texture(iChannel0, fragCoord.xy / iResolution.xy);

    // Static grain (no time used)
    float n = hash21(floor(fragCoord)) - 0.5;

    // Add subtle noise
    fragColor.rgb += n * NOISE_STRENGTH;
}
