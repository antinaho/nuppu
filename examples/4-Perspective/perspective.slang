struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
};

struct Vertex {
    float4 position_uv;
    uint4  color_normal;
};

// Matches the engine's 64-byte instance slot (Mesh_Instance).
// matrix_x/y/z are the rows of rotation * scale; position is the translation.
struct Instance {
    float3 position;
    uint   color;
    float3 matrix_x;
    uint   data0;
    float3 matrix_y;
    uint   data1;
    float3 matrix_z;
    uint   material_and_flags;
};

struct GPU_Material {
    float4 data0;
    float4 data1;
};

struct Engine_Uniform {
    float4x4 perspective_transform;
    float4x4 ortho_transform;
    float4x4 world_transform;
    float4 camera_position;
};

struct FrameData {
    ConstantBuffer<Engine_Uniform> uniforms;

    StructuredBuffer<Vertex>          verts;
    StructuredBuffer<Instance>        instances;
    StructuredBuffer<GPU_Material>    materials;
};

ParameterBlock<FrameData> data;

float4 unpack_rgba(uint packed) {
    return float4(
        float((packed >>  0) & 0xFFu),
        float((packed >>  8) & 0xFFu),
        float((packed >> 16) & 0xFFu),
        float((packed >> 24) & 0xFFu)
    ) * (1.0 / 255.0);
}

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    Vertex   v = data.verts[vertexID];
    Instance i = data.instances[instanceID];

    float3 vpos = v.position_uv.xyz;
    float4 icol = unpack_rgba(i.color);

    float4x4 m = float4x4(
        i.matrix_x.x, i.matrix_x.y, i.matrix_x.z, 0.0,
        i.matrix_y.x, i.matrix_y.y, i.matrix_y.z, 0.0,
        i.matrix_z.x, i.matrix_z.y, i.matrix_z.z, 0.0,
        i.position.x, i.position.y, i.position.z, 1.0
    );

    v2f o;
    float4 world_pos = mul(transpose(m), float4(vpos, 1.0));
    world_pos = mul(data.uniforms.world_transform, world_pos);
    o.position = mul(data.uniforms.perspective_transform, world_pos);
    o.color = icol.xyz;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    return float4(in.color, 1.0);
}
