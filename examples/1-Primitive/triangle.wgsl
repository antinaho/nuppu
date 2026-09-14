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
    @align(16) position_pack_0 : vec4<f32>,
    @align(16) scale_pack_0 : vec4<f32>,
    @align(16) rotation_pack_0 : vec4<f32>,
    @align(16) materials_0 : vec4<u32>,
};

@binding(2) @group(0) var<storage, read> data_instances_0 : array<Instance_std430_0>;

fn unpack_rgba_0( packed_0 : u32) -> vec4<f32>
{
    return vec4<f32>(f32((((packed_0 >> (u32(0)))) & (u32(255)))), f32((((packed_0 >> (u32(8)))) & (u32(255)))), f32((((packed_0 >> (u32(16)))) & (u32(255)))), f32((((packed_0 >> (u32(24)))) & (u32(255))))) * vec4<f32>(0.00392156885936856f);
}

struct v2f_0
{
    @builtin(position) position_0 : vec4<f32>,
    @location(0) color_0 : vec3<f32>,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var i_0 : Instance_std430_0 = data_instances_0[instanceID_0];
    var vcol_0 : vec4<f32> = unpack_rgba_0(v_0.color_normal_0.x);
    var position_1 : vec3<f32> = i_0.position_pack_0.xyz;
    var scale_0 : vec3<f32> = i_0.scale_pack_0.xyz;
    var rotation_0 : vec3<f32> = i_0.rotation_pack_0.xyz;
    var _S1 : f32 = rotation_0.x;
    var cp_0 : f32 = cos(_S1);
    var sp_0 : f32 = sin(_S1);
    var _S2 : f32 = rotation_0.y;
    var cyaw_0 : f32 = cos(_S2);
    var syaw_0 : f32 = sin(_S2);
    var _S3 : f32 = rotation_0.z;
    var cr_0 : f32 = cos(_S3);
    var sr_0 : f32 = sin(_S3);
    var _S4 : f32 = scale_0.x;
    var _S5 : f32 = cr_0 * syaw_0;
    var _S6 : f32 = scale_0.y;
    var _S7 : f32 = scale_0.z;
    var _S8 : f32 = sr_0 * syaw_0;
    var o_0 : v2f_0;
    o_0.position_0 = (((((((((vec4<f32>(v_0.position_uv_0.xyz, 1.0f)) * (transpose(mat4x4<f32>(cr_0 * cyaw_0 * _S4, (_S5 * sp_0 - sr_0 * cp_0) * _S6, (_S5 * cp_0 + sr_0 * sp_0) * _S7, 0.0f, sr_0 * cyaw_0 * _S4, (_S8 * sp_0 + cr_0 * cp_0) * _S6, (_S8 * cp_0 - cr_0 * sp_0) * _S7, 0.0f, - syaw_0 * _S4, cyaw_0 * sp_0 * _S6, cyaw_0 * cp_0 * _S7, 0.0f, position_1.x, position_1.y, position_1.z, 1.0f)))))) * (mat4x4<f32>(data_uniforms_0.world_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(3)]))));
    o_0.color_0 = vcol_0.xyz;
    return o_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) color_1 : vec3<f32>,
};

@fragment
fn fragmentMain( _S9 : pixelInput_0, @builtin(position) position_2 : vec4<f32>) -> pixelOutput_0
{
    var _S10 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S9.color_1, 1.0f) );
    return _S10;
}

