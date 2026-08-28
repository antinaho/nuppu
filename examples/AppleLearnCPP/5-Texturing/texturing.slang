struct v2f {
    float4 position : SV_POSITION;
    float3 normal;
    float3 color;
    float2 tex_coord;
};

struct Vertex {
    float4 position;
    float4 normal;
    float2 tex_coord;
    float2 _pad;
};

struct Instance {
    float4x4 transform;
    float4 color;
    float4x4 normalTransform;
};

struct CameraData {
    float4x4 perspectiveTransform;
    float4x4 worldTransform;
    float3x3 worldNormalTransform;
};

struct FrameData {
    ConstantBuffer<CameraData> camera;
    
    StructuredBuffer<Vertex> verts;
    StructuredBuffer<Instance> instances;
    Texture2D texture;

    SamplerState sampler;
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
    
    float3 normal = mul(float3x3(i.normalTransform), v.normal.xyz);
    normal = mul(data.camera.worldNormalTransform, normal);
    
    v2f o;

    o.position = pos;
    o.normal = normal;
    o.color = i.color.xyz;
    o.tex_coord = v.tex_coord;

    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target {
    float3 texel = data.texture.Sample(data.sampler, in.tex_coord).rgb;

    float3 l = normalize(float3(1.0, 1.0, 0.75));
    float3 n = normalize(in.normal);

    float ndotl = saturate(dot(n, l));

    float3 illum = (mul(in.color, texel) * 0.1) + (in.color * texel * ndotl);

    return float4(illum, 1.0);
}
