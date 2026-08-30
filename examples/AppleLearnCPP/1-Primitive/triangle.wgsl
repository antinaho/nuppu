struct Vertex_std430_0
{
    @align(16) position_uv_0 : vec4<f32>,
    @align(16) color_normal_0 : vec4<u32>,
};

@binding(0) @group(0) var<storage, read> data_verts_0 : array<Vertex_std430_0>;

fn unpack_uint_to_float4_01_0( value_0 : u32) -> vec4<f32>
{
    return vec4<f32>(f32((((value_0 >> (u32(0)))) & (u32(255)))), f32((((value_0 >> (u32(8)))) & (u32(255)))), f32((((value_0 >> (u32(16)))) & (u32(255)))), f32((((value_0 >> (u32(24)))) & (u32(255))))) * vec4<f32>(0.00392156885936856f);
}

struct v2f_0
{
    @builtin(position) position_0 : vec4<f32>,
    @location(0) color_0 : vec3<f32>,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var color_1 : vec4<f32> = unpack_uint_to_float4_01_0(v_0.color_normal_0.x);
    var o_0 : v2f_0;
    o_0.position_0 = vec4<f32>(v_0.position_uv_0.xyz, 1.0f);
    o_0.color_0 = color_1.xyz;
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
fn fragmentMain( _S1 : pixelInput_0, @builtin(position) position_1 : vec4<f32>) -> pixelOutput_0
{
    var _S2 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S1.color_2, 1.0f) );
    return _S2;
}

