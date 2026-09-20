
struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
    float2 tex_coord : TEXCOORD0;
    nointerpolation uint  material : MATERIAL;
};

struct Vertex {
    float4 position_uv;
    uint4 color_normal;
};

// Matches the engine's 64-byte instance slot. `Sprite_Instance` and
// `Mesh_Instance` share this prefix:
//   position | color | matrix_x + data0 | matrix_y + data1 | matrix_z + material_and_flags
// For sprites: data0 = uv_min (u16x2), data1 = uv_size (u16x2).
// For meshes:  data0 = mesh_data_1,     data1 = mesh_data_2.
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

struct Engine_Uniform {
    float4x4 perspective_transform;
    float4x4 ortho_transform;
    float4x4 world_transform;
    float4 camera_position;
};

// Matches the engine's 32-byte GPU_Material record. Two float4s keep Metal's
// natural stride at 32.
struct GPU_Material {
    float4 color;
    float4 _pad;
};

struct Engine_Data {
    ConstantBuffer<Engine_Uniform> uniforms;

    StructuredBuffer<Vertex>          verts;
    StructuredBuffer<Instance>        instances;
    StructuredBuffer<GPU_Material>    materials;
};

ParameterBlock<Engine_Data> data;

struct Shader_Data {
    SamplerState      sampler;
};

ParameterBlock<Shader_Data> shader;

struct Material_Data {
    Texture2D<float4> albedo;
}

ParameterBlock<Material_Data> material;

float4 unpack_rgba(uint packed) {
    return float4(
        float((packed >>  0) & 0xFFu),
        float((packed >>  8) & 0xFFu),
        float((packed >> 16) & 0xFFu),
        float((packed >> 24) & 0xFFu)
    ) * (1.0 / 255.0);
}

float2 unpack_u16x2(uint packed) {
    return float2(
        float(( packed        & 0xFFFFu)),
        float(((packed >> 16) & 0xFFFFu))
    ) * (1.0 / 65535.0);
}

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    Vertex   v = data.verts[vertexID];
    Instance i = data.instances[instanceID];

    // Vertex decode.
    float3 vpos = v.position_uv.xyz;
    uint   v_uv_packed = asuint(v.position_uv.w);
    float2 v_uv = float2(
        float(( v_uv_packed        & 0xFFFFu)),
        float(((v_uv_packed >> 16u) & 0xFFFFu))
    ) * (1.0 / 65535.0);

    float4 icol = unpack_rgba(i.color);

    uint mat   = i.material_and_flags & 0xFFFFu;
    bool atlas = (i.material_and_flags & (1u << 16)) != 0u;

    // Sprites carry an atlas rect in data0/data1; meshes use the vertex uv.
    float2 uv = v_uv;
    if (atlas) {
        uv = unpack_u16x2(i.data0) + v_uv * unpack_u16x2(i.data1);
    }

    // matrix_x/y/z are the rows of rotation * scale; add the translation row.
    float4x4 m = float4x4(
        i.matrix_x.x, i.matrix_x.y, i.matrix_x.z, 0.0,
        i.matrix_y.x, i.matrix_y.y, i.matrix_y.z, 0.0,
        i.matrix_z.x, i.matrix_z.y, i.matrix_z.z, 0.0,
        i.position.x, i.position.y, i.position.z, 1.0
    );

    v2f o;
    // Slang emits row-vector math for `mul(m, v)` (v * m) and transposes
    // ConstantBuffer matrices on load. The local matrix is not a buffer matrix,
    // so transpose it to keep the column-vector convention: P * W * M * v.
    float4 world_pos = mul(transpose(m), float4(vpos, 1.0));
    world_pos = mul(data.uniforms.world_transform, world_pos);
    o.position = mul(data.uniforms.perspective_transform, world_pos);

    o.color     = icol.xyz;
    o.tex_coord = uv;
    o.material  = mat;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    GPU_Material m = data.materials[in.material];
    float3 texel = material.albedo.Sample(shader.sampler, in.tex_coord).rgb;
    return float4(in.color * texel * m.color.rgb, 1.0);
}

// slangc examples/3-Instancing/instancing.slang \
//   -target metal \
//   -entry vertexMain \
//   -stage vertex \
//   -o examples/3-Instancing/instancing.vs.metal

// slangc examples/3-Instancing/instancing.slang \
//   -target metal \
//   -entry fragmentMain \
//   -stage fragment \
//   -o examples/3-Instancing/instancing.ps.metal

// slangc examples/3-Instancing/instancing.slang \
//   -target wgsl \
//   -entry vertexMain \
//   -stage vertex \
//   -entry fragmentMain \
//   -stage fragment \
//   -o examples/3-Instancing/instancing.wgsl