
struct VertexOutput {
    float4 position : SV_Position;
    float4 color : TEXCOORD0;
}

struct Data {
    float2 extra;
    Vertex* verts; 
}

struct Vertex {
    float2 position;
    float2 tex_coords;
    float4 color;
}

[shader("vertex")]
VertexOutput vertexMain(
    uint vertexID : SV_VertexID,
    ConstantBuffer<Data> data,
) {
    VertexOutput output;

    Vertex v = data.verts[vertexID];

    output.position = float4(v.position + data.extra, 0.0, 1.0);
    output.color = v.color;

    return output;
}

[shader("fragment")]
float4 fragmentMain(VertexOutput input) : SV_Target {    
    return input.color;
}