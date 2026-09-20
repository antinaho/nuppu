struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct Engine_Uniform_std140_0
{
    @align(16) perspective_transform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) ortho_transform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) world_transform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) camera_position_0 : vec4<f32>,
};

@binding(0) @group(0) var<uniform> data_uniforms_0 : Engine_Uniform_std140_0;
struct Vertex_std430_0
{
    @align(16) position_uv_0 : vec4<f32>,
    @align(16) color_normal_0 : vec4<u32>,
};

@binding(1) @group(0) var<storage, read> data_verts_0 : array<Vertex_std430_0>;

struct Instance_std430_0
{
    @align(16) position_0 : vec3<f32>,
    @align(4) color_0 : u32,
    @align(16) matrix_x_0 : vec3<f32>,
    @align(4) data0_0 : u32,
    @align(16) matrix_y_0 : vec3<f32>,
    @align(4) data1_0 : u32,
    @align(16) matrix_z_0 : vec3<f32>,
    @align(4) material_and_flags_0 : u32,
};

@binding(2) @group(0) var<storage, read> data_instances_0 : array<Instance_std430_0>;

@binding(0) @group(1) var shader_textures_0 : texture_2d<f32>;

@binding(1) @group(1) var shader_sampler_0 : sampler;

fn unpack_rgba_0( packed_0 : u32) -> vec4<f32>
{
    return vec4<f32>(f32((((packed_0 >> (u32(0)))) & (u32(255)))), f32((((packed_0 >> (u32(8)))) & (u32(255)))), f32((((packed_0 >> (u32(16)))) & (u32(255)))), f32((((packed_0 >> (u32(24)))) & (u32(255))))) * vec4<f32>(0.00392156885936856f);
}

struct v2f_0
{
    @builtin(position) position_1 : vec4<f32>,
    @location(0) normal_0 : vec3<f32>,
    @location(1) color_1 : vec3<f32>,
    @location(2) tex_coord_0 : vec2<f32>,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var i_0 : Instance_std430_0 = data_instances_0[instanceID_0];
    var v_uv_packed_0 : u32 = (bitcast<u32>((v_0.position_uv_0.w)));
    var v_uv_0 : vec2<f32> = vec2<f32>(f32((v_uv_packed_0 & (u32(65535)))), f32((((v_uv_packed_0 >> (u32(16)))) & (u32(65535))))) * vec2<f32>(0.00001525902189314f);
    var vnormal_0 : vec3<f32> = (bitcast<vec3<f32>>((v_0.color_normal_0.yzw)));
    var icol_0 : vec4<f32> = unpack_rgba_0(i_0.color_0);
    var _S1 : mat4x4<f32> = transpose(mat4x4<f32>(i_0.matrix_x_0.x, i_0.matrix_x_0.y, i_0.matrix_x_0.z, 0.0f, i_0.matrix_y_0.x, i_0.matrix_y_0.y, i_0.matrix_y_0.z, 0.0f, i_0.matrix_z_0.x, i_0.matrix_z_0.y, i_0.matrix_z_0.z, 0.0f, i_0.position_0.x, i_0.position_0.y, i_0.position_0.z, 1.0f));
    var o_0 : v2f_0;
    o_0.position_1 = (((((((((vec4<f32>(v_0.position_uv_0.xyz, 1.0f)) * (_S1)))) * (mat4x4<f32>(data_uniforms_0.world_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(3)]))));
    o_0.normal_0 = normalize((((vec4<f32>(vnormal_0, 0.0f)) * (_S1))).xyz);
    o_0.color_1 = icol_0.xyz;
    o_0.tex_coord_0 = v_uv_0;
    return o_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) normal_1 : vec3<f32>,
    @location(1) color_2 : vec3<f32>,
    @location(2) tex_coord_1 : vec2<f32>,
};

@fragment
fn fragmentMain( _S2 : pixelInput_0, @builtin(position) position_2 : vec4<f32>) -> pixelOutput_0
{
    var _S3 : vec3<f32> = _S2.color_2 * (textureSample((shader_textures_0), (shader_sampler_0), (_S2.tex_coord_1))).xyz;
    var _S4 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S3 * vec3<f32>(0.10000000149011612f) + _S3 * vec3<f32>(saturate(dot(normalize(_S2.normal_1), normalize(vec3<f32>(1.0f, 1.0f, 0.75f))))), 1.0f) );
    return _S4;
}

