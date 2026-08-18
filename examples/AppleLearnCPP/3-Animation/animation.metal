#include <metal_stdlib>
using namespace metal;

struct v2f
{
    float4 position [[position]];
    half3 color;
};

struct VertexData
{
    device packed_float3* positions;
    device packed_float3* colors;
};

struct FrameData
{
    float angle;
};

v2f vertex vertexMain( device const VertexData* vertexData [[buffer(0)]], device const FrameData* frameData [[buffer(1)]], uint vertexId [[vertex_id]] )
{
    float a = frameData->angle;
    float3x3 rotationMatrix = float3x3( sin(a), cos(a), 0.0, cos(a), -sin(a), 0.0, 0.0, 0.0, 1.0 );
    v2f o;
    o.position = float4( rotationMatrix * float3(vertexData->positions[ vertexId ]), 1.0 );
    o.color = half3(vertexData->colors[ vertexId ]);
    return o;
}

half4 fragment fragmentMain( v2f in [[stage_in]] )
{
    return half4( in.color, 1.0 );
}