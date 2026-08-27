struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
};

struct Animation {
    float angle;
};

struct Vertex {
    float4 position;
    float4 color;
};

struct VertexData {
    ConstantBuffer<Animation> uniform_data;
    StructuredBuffer<Vertex> verts;
}

ParameterBlock<VertexData> data;

[shader("vertex")]
v2f vertexMain(
    uint vertexID : SV_VertexID
) {
    Vertex v = data.verts[vertexID];
    Animation uniforms = data.uniform_data;

    float angle = uniforms.angle;
    float3x3 rotationMatrix = float3x3(
        sin(angle),  cos(angle), 0.0,
        cos(angle), -sin(angle), 0.0,
        0.0,         0.0,        1.0
    );

    v2f o;

    o.position = float4(mul(rotationMatrix, v.position.xyz), 1.0);
    o.color = v.color.xyz;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target
{
    return float4(in.color, 1.0);
}
