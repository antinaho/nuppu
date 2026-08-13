#include <metal_stdlib>
using namespace metal;

struct v2f {
    float4 position [[position]];
    half3 color;
};

struct Vertex_Data {
    packed_float3 position;
};

struct Instance_Data {
    float4x4 transform;
    float4   color;
};

v2f vertex vertexMain(device const Vertex_Data*   vertex_data   [[buffer(0)]],
                      device const Instance_Data* instance_data [[buffer(1)]],
                      uint vertex_id                            [[vertex_id]],
                      uint instance_id                          [[instance_id]]) {
    v2f o;
    float4 pos = float4(vertex_data[vertex_id].position, 1.0);
    o.position = instance_data[instance_id].transform * pos;
    o.color = half3(instance_data[instance_id].color.rgb);
    return o;
}

half4 fragment fragmentMain(v2f in [[stage_in]]) {
    return half4(in.color, 1.0);
}