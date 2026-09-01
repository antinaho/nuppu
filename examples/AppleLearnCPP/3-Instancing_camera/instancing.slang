struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
    float2 tex_coord : TEXCOORD0;
    uint   layer    : LAYER;
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

struct Engine_Uniform {
    float4x4 perspective_transform;
    float4x4 ortho_transform;
    float4x4 world_transform;
    float4 camera_position;
}

struct FrameData {
    ConstantBuffer<Engine_Uniform> uniforms;

    StructuredBuffer<Vertex>          verts;
    StructuredBuffer<Sprite_Instance> instances;
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

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID, uint instanceID : SV_InstanceID) {
    Vertex          v = data.verts[vertexID];
    Sprite_Instance i = data.instances[instanceID];

    // Vertex decode
    float3 vpos = v.position_uv.xyz;
    float2 v_uv = float2(
        float((asuint(v.position_uv.w) >>  0) & 0xFFFFu),
        float((asuint(v.position_uv.w) >> 16) & 0xFFFFu)
    ) * (1.0 / 65535.0);

    float4 vcol    = unpack_rgba(v.color_normal.x);
    float3 vnormal = v.color_normal.yzw;

    // Instance decode
    float3 position = i.position_color.xyz;
    // position_color.w is float-typed; bit-cast it to uint to read the packed RGBA bytes.
    float4 icol     = unpack_rgba(asuint(i.position_color.w));

    float2 uv_min  = unpack_u16_pair(i.uv_min_size.x) * (1.0 / 65535.0);
    float2 uv_size = unpack_u16_pair(i.uv_min_size.y) * (1.0 / 65535.0);

    float sx = unpack_scale(i.scale_turns.x);
    float sy = unpack_scale(i.scale_turns.x >> 16);
    // scale_turns.y (little-endian u32 at offset 28):
    //   byte 0 = turns[0] (pitch / rotation.x)
    //   byte 1 = turns[1] (yaw   / rotation.y)
    //   byte 2 = turns[2] (roll  / rotation.z)
    //   byte 3 = texture_layer
    float pitch = unpack_turn( i.scale_turns.y        & 0xFFu);
    float yaw   = unpack_turn((i.scale_turns.y >>  8) & 0xFFu);
    float roll  = unpack_turn((i.scale_turns.y >> 16) & 0xFFu);
    uint  layer = (i.scale_turns.y >> 24) & 0xFFu;

    // T * R_z * R_y * R_x * S  (ZYX Euler; reduces to 2D Z-rotation when pitch = yaw = 0)
    float cp   = cos(pitch), sp   = sin(pitch);
    float cyaw = cos(yaw),   syaw = sin(yaw);
    float cr   = cos(roll),  sr   = sin(roll);

    float4x4 m = float4x4(
         cr * cyaw * sx,                 (cr * syaw * sp - sr * cp) * sy,     cr * syaw * cp + sr * sp,    position.x,
         sr * cyaw * sx,                 (sr * syaw * sp + cr * cp) * sy,     sr * syaw * cp - cr * sp,    position.y,
        -syaw * sx,                       cyaw * sp * sy,                       cyaw * cp,                   position.z,
         0.0,                             0.0,                                  0.0,                         1.0
    );

    v2f o;

    float4 world_pos = mul(m, float4(vpos, 1.0));
    world_pos = mul(data.uniforms.world_transform, world_pos);
    o.position = mul(data.uniforms.perspective_transform, world_pos);

    o.color    = icol.xyz;
    o.tex_coord = uv_min + v_uv * uv_size;
    o.layer    = layer;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    float3 texel = data.textures.Sample(data.sampler, float3(in.tex_coord, in.layer)).rgb;
    return float4(in.color * texel, 1.0);
}