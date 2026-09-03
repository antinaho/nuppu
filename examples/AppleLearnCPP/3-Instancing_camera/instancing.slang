struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
    float2 tex_coord : TEXCOORD0;
    uint   material    : MATERIAL;
};

struct Vertex {
    float4 position_uv;
    uint4 color_normal;
};

// Matches graphics.odin Sprite_Instance byte layout (32 bytes, 16-byte aligned).
// Uses float4 + uint2 + uint2 so std430 in WGSL doesn't pad float3->16 and
// break the byte correspondence with the Odin struct.
struct Sprite_Instance {
    float4 position_color;   // off 0:  xyz = position, w = color RGBA u8 packed
    uint2  uv_min_size;      // off 16: x = uv_min u16-pair, y = uv_size u16-pair
    uint2  scale_turns;      // off 24: x = scale u16-pair (sx, sy), y = turns[0..2] u8 + texture_layer u8
};

// Matches graphics.odin Mesh_Instance byte layout (32 bytes, 16-byte aligned):
//   off 0:  position [3]f32 + color [4]u8 -> float4 position_color
//   off 16: scale [3]u16 + turns [3]u8 + material_index u8 + pad -> uint4 scale_turns_material
// uint4 covers the full second 16-byte region so the decode below matches the
// Odin #all_or_none packing (scale.x, scale.y, scale.z at offsets 16-21).
struct Mesh_Instance {
    float4 position_color;
    uint4 scale_turns_material;
}

struct Material {
    uint id_user_data_1;
    uint user_data_2;
};

struct Engine_Uniform {
    float4x4 perspective_transform;
    float4x4 ortho_transform;
    float4x4 world_transform;
    float4 camera_position;
}

struct Instance {
    uint kind_material;
    uint extra_data;
};

struct FrameData {
    ConstantBuffer<Engine_Uniform> uniforms;

    StructuredBuffer<Vertex>          verts;
    StructuredBuffer<Instance>        instances;
    ByteAddressBuffer                 instances_data;
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

float2 unpack_u16_pair(uint packed) {
    return float2(
        float( packed        & 0xFFFFu),
        float((packed >> 16) & 0xFFFFu)
    );
}

// [0, 65535] -> [0, SCALE_MAX=100.0]
float unpack_scale(uint packed) {
    return unpack_u16_pair(packed).x * (100.0 / 65535.0);
}

// [0, 255] -> [0, 2π]
float unpack_turn(uint packed) {
    return (float(packed & 0xFFu) * (1.0 / 255.0)) * 6.2831853;
}

static const uint Instance_Kind_Sprite = 0u;
static const uint Instance_Kind_Mesh = 1u;

Sprite_Instance ReadSprite(uint byteOffset)
{
    uint4 a = data.instances_data.Load<uint4>(byteOffset + 0);   // position_color + uv_min_size
    uint4 b = data.instances_data.Load<uint4>(byteOffset + 16);  // scale_turns + (next 16 bytes if any)

    Sprite_Instance s;

    s.position_color = asfloat(a);
    s.uv_min_size = b.xy;
    s.scale_turns = b.zw;

    return s;
}

Mesh_Instance ReadMesh(uint byteOffset)
{
    uint4 a = data.instances_data.Load<uint4>(byteOffset + 0);   // position_color
    uint4 b = data.instances_data.Load<uint4>(byteOffset + 16);  // scale [3]u16 + turns [3]u8 + material_index u8 + pad

    Mesh_Instance m;

    m.position_color       = asfloat(a);
    m.scale_turns_material = b;

    return m;
}

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    Vertex    v = data.verts[vertexID];
    Instance  i = data.instances[instanceID];

    // Vertex decode
    float3 vpos = v.position_uv.xyz;
    float2 v_uv = float2(
        float((asuint(v.position_uv.w) >>  0) & 0xFFFFu),
        float((asuint(v.position_uv.w) >> 16) & 0xFFFFu)
    ) * (1.0 / 65535.0);

    // Instance decode (low16=kind, high16=material)
    uint kind     = i.kind_material         & 0xFFFFu;
    uint material = (i.kind_material >> 16) & 0xFFFFu;

    // SV_InstanceID = base_instance + local_index on both Metal and WGSL,
    // so the byte offset into instances_data is just instanceID * 32u.
    // The CPU draw call must set base_instance to the offset of this kind's
    // payloads (0 for sprites, sprite_count for meshes).
    uint byteOffset = instanceID * 32u;

    // Output state hoisted so the post-switch assembly can see it.
    // Defaults give a sane no-op for any case we haven't filled yet.
    float3   position = float3(0, 0, 0);
    float4   icol     = float4(1, 1, 1, 1);
    float2   uv_min   = float2(0, 0);
    float2   uv_size  = float2(1, 1);
    float4x4 m        = float4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1);

    switch (kind) {
        case Instance_Kind_Sprite:
        {
            Sprite_Instance sprite = ReadSprite(byteOffset);

            position = sprite.position_color.xyz;
            icol     = unpack_rgba(asuint(sprite.position_color.w));

            uv_min   = unpack_u16_pair(sprite.uv_min_size.x) * (1.0 / 65535.0);
            uv_size  = unpack_u16_pair(sprite.uv_min_size.y) * (1.0 / 65535.0);

            float sx = unpack_scale(sprite.scale_turns.x);
            float sy = unpack_scale(sprite.scale_turns.x >> 16);

            float pitch = unpack_turn( sprite.scale_turns.y        & 0xFFu);
            float yaw   = unpack_turn((sprite.scale_turns.y >>  8) & 0xFFu);
            float roll  = unpack_turn((sprite.scale_turns.y >> 16) & 0xFFu);

            // T * R_z * R_y * R_x * S  (ZYX Euler; reduces to 2D Z-rotation when pitch = yaw = 0)
            float cp   = cos(pitch), sp   = sin(pitch);
            float cyaw = cos(yaw),   syaw = sin(yaw);
            float cr   = cos(roll),  sr   = sin(roll);

            m = float4x4(
                 cr * cyaw * sx,   (cr * syaw * sp - sr * cp) * sy,   cr * syaw * cp + sr * sp,   position.x,
                 sr * cyaw * sx,   (sr * syaw * sp + cr * cp) * sy,   sr * syaw * cp - cr * sp,   position.y,
                -syaw * sx,         cyaw * sp * sy,                    cyaw * cp,                 position.z,
                 0.0,               0.0,                               0.0,                       1.0
            );

            break;
        }
        case Instance_Kind_Mesh:
        {
            Mesh_Instance mesh = ReadMesh(byteOffset);

            position = mesh.position_color.xyz;
            icol     = unpack_rgba(asuint(mesh.position_color.w));

            // Mesh has no UV — leave uv_min/uv_size at defaults (0, 1) so the
            // tex_coord in the fragment falls back to v_uv (cube vertices
            // default to uv=(0,0); texture sampling is a placeholder until
            // material layer handling is wired up).

            // scale_turns_material layout (offset 16, 16 bytes):
            //   bytes 16-17: scale.x (u16)
            //   bytes 18-19: scale.y (u16)
            //   bytes 20-21: scale.z (u16)
            //   bytes 22:    turns[0] (u8)
            //   bytes 23:    turns[1] (u8)
            //   bytes 24:    turns[2] (u8)
            //   bytes 25:    material_index (u8)
            //   bytes 26-28: _pad [3]u8
            //   bytes 29-31: end padding
            float sx = unpack_scale( mesh.scale_turns_material.x         & 0xFFFFu);
            float sy = unpack_scale((mesh.scale_turns_material.x >> 16) & 0xFFFFu);
            float sz = unpack_scale( mesh.scale_turns_material.y         & 0xFFFFu);

            float pitch = unpack_turn((mesh.scale_turns_material.y >> 16) & 0xFFu);
            float yaw   = unpack_turn((mesh.scale_turns_material.y >> 24) & 0xFFu);
            float roll  = unpack_turn( mesh.scale_turns_material.z         & 0xFFu);

            float cp   = cos(pitch), sp   = sin(pitch);
            float cyaw = cos(yaw),   syaw = sin(yaw);
            float cr   = cos(roll),  sr   = sin(roll);

            m = float4x4(
                 cr * cyaw * sx,        (cr * syaw * sp - sr * cp) * sy,   (cr * syaw * cp + sr * sp) * sz,   position.x,
                 sr * cyaw * sx,        (sr * syaw * sp + cr * cp) * sy,   (sr * syaw * cp - cr * sp) * sz,   position.y,
                -syaw * sx,              cyaw * sp * sy,                     cyaw * cp * sz,                   position.z,
                 0.0,                    0.0,                                0.0,                              1.0
            );

            break;
        }
        default:
        {
            break;
        }
    }

    v2f o;

    float4 world_pos = mul(m, float4(vpos, 1.0));
    world_pos = mul(data.uniforms.world_transform, world_pos);
    o.position = mul(data.uniforms.perspective_transform, world_pos);

    o.color     = icol.xyz;
    o.tex_coord = uv_min + v_uv * uv_size;
    o.material  = material;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    float3 texel = data.textures.Sample(data.sampler, float3(in.tex_coord, 0)).rgb;
    return float4(in.color * texel, 1.0);
}