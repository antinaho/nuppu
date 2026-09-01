struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
};

struct Vertex {
    float4 position_uv;
    uint4 color_normal;
};

struct Sprite_Instance {
    float4 position_color; // xyz = position, w = color ([4]u8)
    uint2 uvs; // x = uv_min, y = uv_size
    uint2 scale_turns; // x = scale, y = turns [3]u8
};


struct Instance {
    float4x4 transform;
    float4 color;
};

struct FrameData {
    StructuredBuffer<Vertex> verts;
    StructuredBuffer<Instance> instances;
};

ParameterBlock<FrameData> data;

float4 unpack_uint_to_float4(uint value)
{
    return float4(
        float((value >> 0)  & 0xFF),
        float((value >> 8)  & 0xFF),
        float((value >> 16) & 0xFF),
        float((value >> 24) & 0xFF)
    );
}

float unpack_u16(uint16_t value)
{
    return float(value) * (1.0 / 65535.0);
}

[shader("vertex")]
v2f vertexMain(
    uint vertexID : SV_VertexID,
    uint instanceID : SV_InstanceID
) {
    Vertex v = data.verts[vertexID];
    Instance i = data.instances[instanceID];

    // Vertex
    float3 position = v.position_uv.xyz;

    float2 uv = float2(
        unpack_u16( uint16_t( ( uint(v.position_uv.w) >> 0 ) & 0xFFFF ) ), 
        unpack_u16( uint16_t( ( uint(v.position_uv.w) >> 16) & 0xFFFF ) )
    );

    float4 color = unpack_uint_to_float4(v.color_normal.x);
    color /= 255.0;

    float3 normal = v.color_normal.yzw;

    // Instance
    Sprite_Instance inst;
    
    float4 color_instance = unpack_uint_to_float4(uint(inst.position_color.w));
    color_instance /= 255.0;

    float3 position_instance = inst.position_color.xyz;

    float2 uv_min = float2(
        unpack_u16( uint16_t( ( uint(inst.uvs.x) >> 0 ) & 0xFFFF ) ), 
        unpack_u16( uint16_t( ( uint(inst.uvs.x) >> 16) & 0xFFFF ) )
    );

    float2 uv_size = float2(
        unpack_u16( uint16_t( ( uint(inst.uvs.y) >> 0 ) & 0xFFFF ) ), 
        unpack_u16( uint16_t( ( uint(inst.uvs.y) >> 16) & 0xFFFF ) )
    );

    //
    float4 pos = float4(position, 1.0);
    pos = mul(i.transform, pos);

    v2f o;

    o.position = pos;
    o.color = i.color.xyz;

    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    return float4(in.color, 1.0);
}