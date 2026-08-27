struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
};


struct Vertex {
    float4 position;
};

struct Instance {
    float4x4 transform;
    float4 color;
};

struct CameraData {
    float4x4 perspectiveTransform;
    float4x4 worldTransform;
}

struct FrameData {
    ConstantBuffer<CameraData> camera;
    
    StructuredBuffer<Vertex> verts;
    StructuredBuffer<Instance> instances;
};

ParameterBlock<FrameData> data;

[shader("vertex")]
v2f vertexMain(
    uint vertexID : SV_VertexID,
    uint instanceID : SV_InstanceID
) {
    Vertex v = data.verts[vertexID];
    Instance i = data.instances[instanceID];

    float4 pos = float4(v.position.xyz, 1.0);
    pos = mul(i.transform, pos);
    pos = mul(data.camera.worldTransform, pos);
    pos = mul(data.camera.perspectiveTransform, pos);

    v2f o;

    o.position = pos;
    o.color = i.color.xyz;

    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    return float4(in.color.xyz, 1.0);
}

