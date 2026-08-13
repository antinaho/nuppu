#include <metal_stdlib>
using namespace metal;

struct v2f {
    float4 position [[position]];
    half3 color;
};

// Without using pointers
// struct VertexData {
//     device packed_float3* positions [[id(0)]];
//     device packed_float3* colors    [[id(1)]];
// };

struct VertexData {
    device packed_float3* positions;
    device packed_float3* colors;
};

v2f vertex vertexMain(
    uint vertexID [[vertex_id]],
    device const VertexData* vertexData [[buffer(0)]]
) {
    v2f o;
    o.position = float4(vertexData->positions[vertexID], 1.0);
    o.color = half3(vertexData->colors[vertexID]);
    return o;
}

half4 fragment fragmentMain(v2f in [[stage_in]]) {
    return half4(in.color, 1.0);
}