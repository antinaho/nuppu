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

// Matches the Odin `Color_Instance` instance-data struct.
struct Color_Instance {
    float4 color;
};

struct Object_Params {
    float4 color;
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

static const uint MATERIAL_INDEX_MASK = 0x3FFFu;

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    Vertex   v = data.verts[vertexID];
    Instance i = data.instances[instanceID];

    float3 vpos = v.position_uv.xyz;

    float3 position    = i.position_pack.xyz;
    float3 scale       = i.scale_pack.xyz;
    float3 rotation    = i.rotation_pack.xyz;
    uint   data_offset = asuint(i.rotation_pack.w);

    uint handle = i.materials.x & 0xFFFFu;
    GPU_Material mat = data.materials[handle & MATERIAL_INDEX_MASK];
    Object_Params p = data.material_params.Load<Object_Params>(mat.user_data_2);

    float4 icol = p.color;
    if (data_offset != 0u) {
        Color_Instance ci = data.instance_data.Load<Color_Instance>(data_offset);
        icol = ci.color;
    }

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
    o.color = icol.xyz;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    return float4(in.color, 1.0);
}
