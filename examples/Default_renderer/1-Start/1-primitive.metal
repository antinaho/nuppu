#include <metal_stdlib>
using namespace metal;

#define u8 uchar;
#define u16 ushort;
#define u32 uint;

#define i8 char;
#define i16 short;
#define i32 int;

#define f16 half;
#define f32 float;

struct v2f {
    float4 position [[position]]; // vertex position
    half3 color;                  // vertex color
};

struct Vertex {
    packed_float3 position;
};

struct Instance {
    float4x4 transform;
    float4 color;
    uint mesh_id;
};

struct Range {
    uint location;
    uint length;
};

struct Mesh {
    Range vertex_range;
    Range index_range;
};

struct Data {
    const device Instance* instances;
    const device Mesh* meshes;
    const device Vertex* vertices;
    const device uint* vertex_colors;
};

struct CameraData
{
    float4x4 to_clip;
    float4x4 to_view;
};

v2f vertex vertexMain(
    uint vertexID  [[vertex_id]], 
    uint instanceID [[instance_id]],
    device const Data* data [[buffer(0)]],
    device const CameraData& cameraData [[buffer(1)]]
) {
    v2f o;

    const device Instance& instance = data->instances[instanceID];
    const device Mesh& mesh = data->meshes[instance.mesh_id];
    const device Vertex& vert = data->vertices[mesh.vertex_range.location + vertexID];

    float4 pos = float4(vert.position, 1.0);
    pos = instance.transform * pos;
    pos = cameraData.to_clip * cameraData.to_view * pos;
    o.position = pos;
    o.color = half3(instance.color.rgb);
    return o;
}

half4 fragment fragmentMain(v2f in [[stage_in]]) {
    return half4(in.color, 1.0);
}