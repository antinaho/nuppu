struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
};

struct Vertex {
    float4 position_uv;
    uint4  color_normal;
};

// Matches nuppu.Instance (64 bytes, 16-byte aligned).
struct Instance {
    float4 position_pack;   // xyz = position
    float4 scale_pack;      // xyz = scale
    float4 rotation_pack;   // xyz = rotation, w = instance_data byte offset
    uint4  materials;       // xyz = 6 x u16 Material_Handle, w = entity_id
};

struct GPU_Material {
    uint handle_user;
    uint user_data_2;
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
    ByteAddressBuffer                 material_params;
    ByteAddressBuffer                 instance_data;
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
    float4 vcol = unpack_rgba(v.color_normal.x);

    float3 position = i.position_pack.xyz;
    float3 scale    = i.scale_pack.xyz;
    float3 rotation = i.rotation_pack.xyz;

    float cp   = cos(rotation.x), sp   = sin(rotation.x);
    float cyaw = cos(rotation.y), syaw = sin(rotation.y);
    float cr   = cos(rotation.z), sr   = sin(rotation.z);

    float4x4 m = float4x4(
         cr * cyaw * scale.x,   (cr * syaw * sp - sr * cp) * scale.y,   (cr * syaw * cp + sr * sp) * scale.z,   0.0,
         sr * cyaw * scale.x,   (sr * syaw * sp + cr * cp) * scale.y,   (sr * syaw * cp - cr * sp) * scale.z,   0.0,
        -syaw * scale.x,         cyaw * sp * scale.y,                    cyaw * cp * scale.z,                    0.0,
         position.x,              position.y,                             position.z,                             1.0
    );

    v2f o;
    float4 world_pos = mul(transpose(m), float4(vpos, 1.0));
    world_pos = mul(data.uniforms.world_transform, world_pos);
    o.position = mul(data.uniforms.perspective_transform, world_pos);
    o.color = vcol.xyz;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    return float4(in.color, 1.0);
}
