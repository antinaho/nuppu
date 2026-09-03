struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
};

struct Vertex {
    float4 position_uv;
    uint4 color_normal;
};

struct VertexData {
    StructuredBuffer<Vertex> verts;
};

ParameterBlock<VertexData> data;

float4 unpack_uint_to_float4_01(uint value)
{
    return float4(
        float((value >> 0)  & 0xFF),
        float((value >> 8)  & 0xFF),
        float((value >> 16) & 0xFF),
        float((value >> 24) & 0xFF)
    ) * (1.0 / 255.0);
}

float unpack_u16(uint16_t value)
{
    return float(value) * (1.0 / 65535.0);
}

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID) {
    v2f o;
    Vertex v = data.verts[vertexID];

    float3 position = v.position_uv.xyz;

    float2 uv = float2(
        unpack_u16( uint16_t( ( uint(v.position_uv.w) >> 0 ) & 0xFFFF ) ), 
        unpack_u16( uint16_t( ( uint(v.position_uv.w) >> 16) & 0xFFFF ) )
    );

    float4 color = unpack_uint_to_float4_01(v.color_normal.x);
    float3 normal = v.color_normal.yzw;

    o.position = float4(v.position_uv.xyz, 1.0);
    o.color = color.xyz;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target
{
    return float4(in.color, 1.0);
}

// slangc examples/AppleLearnCPP/1-Primitive/triangle.slang \
//     -target metal \
//     -entry vertexMain \
//     -stage vertex \
//     -o examples/AppleLearnCPP/1-Primitive/triangle.vs.metal \

// slangc examples/AppleLearnCPP/1-Primitive/triangle.slang \
//     -target metal \
//     -entry fragmentMain \
//     -stage fragment \
//     -o examples/AppleLearnCPP/1-Primitive/triangle.ps.metal

// wgsl compiled to 1 file only
// slangc examples/AppleLearnCPP/1-Primitive/triangle.slang \
//     -target wgsl \
//     -entry vertexMain \
//     -stage vertex \
//     -entry fragmentMain \
//     -stage fragment \
//     -o examples/AppleLearnCPP/1-Primitive/triangle.wgsl


// slangc examples/AppleLearnCPP/4-Perspective/perspective.slang \
//     -target metal \
//     -entry vertexMain \
//     -stage vertex \
//     -o examples/AppleLearnCPP/4-Perspective/perspective.vs.metal \

// slangc examples/AppleLearnCPP/4-Perspective/perspective.slang \
//     -target metal \
//     -entry fragmentMain \
//     -stage fragment \
//     -o examples/AppleLearnCPP/4-Perspective/perspective.ps.metal \

// slangc examples/AppleLearnCPP/4-Perspective/perspective.slang \
//     -target wgsl \
//     -entry vertexMain \
//     -stage vertex \
//     -entry fragmentMain \
//     -stage fragment \
//     -o examples/AppleLearnCPP/4-Perspective/perspective.wgsl




// slangc examples/AppleLearnCPP/3-Instancing_camera/instancing.slang \
//     -target metal \
//     -entry vertexMain \
//     -stage vertex \
//     -o examples/AppleLearnCPP/3-Instancing_camera/instancing.vs.metal \

// slangc examples/AppleLearnCPP/3-Instancing_camera/instancing.slang \
//     -target metal \
//     -entry fragmentMain \
//     -stage fragment \
//     -o examples/AppleLearnCPP/3-Instancing_camera/instancing.ps.metal