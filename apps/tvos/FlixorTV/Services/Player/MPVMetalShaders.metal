//
//  MPVMetalShaders.metal
//  FlixorTV
//
//  Simple passthrough shader for video rendering
//  Samples texture with swizzle support
//

#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Vertex shader - fullscreen quad
vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    // Fullscreen triangle strip coordinates
    float2 positions[4] = {
        float2(-1.0, -1.0),  // Bottom-left
        float2( 1.0, -1.0),  // Bottom-right
        float2(-1.0,  1.0),  // Top-left
        float2( 1.0,  1.0)   // Top-right
    };

    float2 texCoords[4] = {
        float2(0.0, 1.0),  // Bottom-left
        float2(1.0, 1.0),  // Bottom-right
        float2(0.0, 0.0),  // Top-left
        float2(1.0, 0.0)   // Top-right
    };

    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

// Fragment shader - simple texture sample (respects swizzle)
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                              texture2d<float> videoTexture [[texture(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear, min_filter::linear);

    // Sample texture - Metal will apply swizzle here
    float4 color = videoTexture.sample(textureSampler, in.texCoord);

    return color;
}
