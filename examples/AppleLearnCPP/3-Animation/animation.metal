#include <metal_stdlib>
using namespace metal;

struct v2f
{
    float4 position [[position]];
    half3 color;
};

struct FrameData
{
    float angle;
    float pad0;
    float pad1;
    float pad2;
};

v2f vertex vertexMain(
    device const packed_float3* positions [[buffer(0)]],
    device const packed_float3* colors    [[buffer(1)]],
    device const FrameData& frameData     [[buffer(2)]],
    uint vertexId [[vertex_id]]
) {
    float a = frameData.angle;
    float3x3 rotationMatrix = float3x3(
        sin(a),  cos(a), 0.0,
        cos(a), -sin(a), 0.0,
        0.0,     0.0,    1.0
    );
    v2f o;
    o.position = float4(rotationMatrix * float3(positions[vertexId]), 1.0);
    o.color = half3(colors[vertexId]);
    return o;
}

half4 fragment fragmentMain(v2f in [[stage_in]])
{
    return half4(in.color, 1.0);
}
