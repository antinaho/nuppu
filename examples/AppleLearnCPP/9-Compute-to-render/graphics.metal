#include <metal_stdlib>
using namespace metal;

struct v2f {
    float4 position [[position]];
    float3 normal;
    half3 color;
    float2 texcoord;
};

struct Vertex_Data {
    packed_float3 position;
    float pad;
    packed_float3 normal;
    float pad2;
    packed_float2 texcoord;
    packed_float2 pad3;
};

struct Instance_Data {
    float4x4 transform;
    float4   color;
    float3x3 normal_transform;
};

struct Camera_Data {
    float4x4 perspective_transform;
    float4x4 world_transform;
    float3x3 world_normal_transform;
};

v2f vertex vertexMain(device const Vertex_Data*   vertex_data   [[buffer(0)]],
                        device const Instance_Data* instance_data [[buffer(1)]],
                        device const Camera_Data&   camera_data   [[buffer(2)]],
                        uint vertex_id                            [[vertex_id]],
                        uint instance_id                          [[instance_id]]) {
    v2f o;

    const device Vertex_Data&   vd = vertex_data[vertex_id];
    const device Instance_Data& id = instance_data[instance_id];

    float4 pos = float4(vd.position, 1.0);
    pos = id.transform * pos;
    pos = camera_data.perspective_transform * camera_data.world_transform * pos;
    o.position = pos;

    float3 normal = id.normal_transform * float3(vd.normal);
    normal   = camera_data.world_normal_transform * normal;
    o.normal = normal;

    o.texcoord = float2(vd.texcoord.xy);

    o.color = half3(id.color.rgb);
    return o;
}

half4 fragment fragmentMain(v2f in                              [[stage_in]],
                                texture2d<half, access::sample> tex [[texture(0)]]) {
    constexpr sampler s(address::repeat, filter::linear);
    half3 texel = tex.sample(s, in.texcoord).rgb;

    // assume light coming from front-top-right
    float3 l = normalize(float3(1.0, 1.0, 0.8));
    float3 n = normalize(in.normal);

    float ndotl = saturate(dot(n, l));

    half3 illum = in.color * texel * 0.1 + in.color * texel * ndotl;
    return half4(illum, 1.0);
}