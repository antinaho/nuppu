struct Animation_std140_0
{
    @align(16) angle_0 : f32,
};

@binding(0) @group(0) var<uniform> data_uniform_data_0 : Animation_std140_0;
struct Vertex_std430_0
{
    @align(16) position_0 : vec4<f32>,
    @align(16) color_0 : vec4<f32>,
};

@binding(1) @group(0) var<storage, read> data_verts_0 : array<Vertex_std430_0>;

struct v2f_0
{
    @builtin(position) position_1 : vec4<f32>,
    @location(0) color_1 : vec3<f32>,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var _S1 : f32 = sin(data_uniform_data_0.angle_0);
    var _S2 : f32 = cos(data_uniform_data_0.angle_0);
    var o_0 : v2f_0;
    o_0.position_1 = vec4<f32>((((v_0.position_0.xyz) * (mat3x3<f32>(_S1, _S2, 0.0f, _S2, - _S1, 0.0f, 0.0f, 0.0f, 1.0f)))), 1.0f);
    o_0.color_1 = v_0.color_0.xyz;
    return o_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) color_2 : vec3<f32>,
};

@fragment
fn fragmentMain( _S3 : pixelInput_0, @builtin(position) position_2 : vec4<f32>) -> pixelOutput_0
{
    var _S4 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S3.color_2, 1.0f) );
    return _S4;
}

