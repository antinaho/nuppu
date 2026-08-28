struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
};

struct Vertex {
    float4 position;
    float4 color;
};

struct VertexData {
    StructuredBuffer<Vertex> verts;
};

ParameterBlock<VertexData> data;

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID) {
    v2f o;
    Vertex v = data.verts[vertexID];

    o.position = float4(v.position.xyz, 1.0);
    o.color = v.color.xyz;
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
