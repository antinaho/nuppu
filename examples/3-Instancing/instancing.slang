struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
    float2 tex_coord : TEXCOORD0;
    uint   material : MATERIAL;
};

struct Vertex {
    float4 position_uv;
    uint4 color_normal;
};

// Matches nuppu.Instance (64 bytes, 16-byte aligned):
//   position/scale/rotation packs + 6 x u16 material handles + entity id.
//   `rotation_pack.w` is not rotation: it is the byte offset of this entity's
//   instance-data blob, reinterpreted with asuint() on the shader side.
struct Instance {
    float4 position_pack;   // xyz = position
    float4 scale_pack;      // xyz = scale
    float4 rotation_pack;   // xyz = rotation, w = instance_data byte offset
    uint4  materials;       // xyz = 6 x u16 Material_Handle, w = entity_id
};

// Matches nuppu.GPU_Material (8 bytes).
struct GPU_Material {
    uint handle_user;   // handle | (user_data_1 << 16)
    uint user_data_2;   // inline value, or byte offset into material_params
};

struct Engine_Uniform {
    float4x4 perspective_transform;
    float4x4 ortho_transform;
    float4x4 world_transform;
    float4 camera_position;
};

// Matches the Odin `nuppu.Sprite_Instance` instance-data struct, addressed by
// Instance.rotation_pack.w (byte offset).
struct Sprite_Instance {
    float2 uv_min;
    float2 uv_max;
    uint   frame_n;
    uint   _pad;
};

// Object params used by this example. Layout must match the Odin struct:
//   Object_Params { color: [4]f32 }
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
    Texture2DArray<float4>            textures;

    SamplerState sampler;
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

static const uint MATERIAL_INDEX_MASK = 0x3FFFu;

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    Vertex   v = data.verts[vertexID];
    Instance i = data.instances[instanceID];

    // Vertex decode.
    float3 vpos = v.position_uv.xyz;
    uint   v_uv_packed = asuint(v.position_uv.w);
    float2 v_uv = float2(
        float(( v_uv_packed        & 0xFFFFu)),
        float(( v_uv_packed >> 16u) & 0xFFFFu)
    ) * (1.0 / 65535.0);

    float3 position    = i.position_pack.xyz;
    float3 scale       = i.scale_pack.xyz;
    float3 rotation    = i.rotation_pack.xyz;
    uint   data_offset = asuint(i.rotation_pack.w);

    // Slot 0 material handle (u16 packed in materials.x).
    uint handle = i.materials.x & 0xFFFFu;
    GPU_Material mat = data.materials[handle & MATERIAL_INDEX_MASK];
    Object_Params p = data.material_params.Load<Object_Params>(mat.user_data_2);

    float4 icol   = p.color;
    float2 uv_min = float2(0.0, 0.0);
    float2 uv_max = float2(1.0, 1.0);
    if (data_offset != 0u) { // sprite: uv rect comes from per-entity data
        Sprite_Instance s = data.instance_data.Load<Sprite_Instance>(data_offset);
        uv_min = s.uv_min;
        uv_max = s.uv_max;
        // frame_n is arbitrary non-UV per-instance data; prove it reaches the shader.
        icol.rgb *= 0.65 + 0.35 * frac(float(s.frame_n) * 0.25 + 0.1);
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
    // Slang emits row-vector math for `mul(m, v)` (v * m), and transposes
    // ConstantBuffer matrices on load (v * W^T == W * v). The local matrix is
    // not a buffer matrix, so transpose it to keep the column-vector
    // convention used by the hand-written engine uniforms: P * W * M * v.
    float4 world_pos = mul(transpose(m), float4(vpos, 1.0));
    world_pos = mul(data.uniforms.world_transform, world_pos);
    o.position = mul(data.uniforms.perspective_transform, world_pos);

    o.color     = icol.xyz;
    o.tex_coord = uv_min + v_uv * (uv_max - uv_min);
    o.material  = handle;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    float3 texel = data.textures.Sample(data.sampler, float3(in.tex_coord, 0)).rgb;
    return float4(in.color * texel, 1.0);
}
