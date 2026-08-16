#include <metal_stdlib>
using namespace metal;

struct v2f {
    float4 position [[position]]; // vertex position
    half3 color;                  // vertex color
};

v2f vertex vertexMain( uint vertexID  [[vertex_id]],
device const packed_float3* positions [[buffer(0)]],
device const packed_float3* colors    [[buffer(1)]]
) {
    v2f o;
    o.position = float4(positions[vertexID], 1.0);
    o.color = half3(colors[vertexID]);
    return o;
}

half4 fragment fragmentMain(v2f in [[stage_in]]) {
    return half4(in.color, 1.0);
}