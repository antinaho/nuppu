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

struct Sprite_Instance_std430_0
{
    @align(16) position_color_0 : vec4<f32>,
    @align(16) uv_min_size_0 : vec2<u32>,
    @align(8) scale_turns_0 : vec2<u32>,
};

@binding(2) @group(0) var<storage, read> data_instances_0 : array<Sprite_Instance_std430_0>;

@binding(3) @group(0) var data_textures_0 : texture_2d_array<f32>;

@binding(4) @group(0) var data_sampler_0 : sampler;

fn unpack_rgba_0( packed_0 : u32) -> vec4<f32>
{
    return vec4<f32>(f32((((packed_0 >> (u32(0)))) & (u32(255)))), f32((((packed_0 >> (u32(8)))) & (u32(255)))), f32((((packed_0 >> (u32(16)))) & (u32(255)))), f32((((packed_0 >> (u32(24)))) & (u32(255))))) * vec4<f32>(0.00392156885936856f);
}

fn unpack_u16_pair_0( packed_1 : u32) -> vec2<f32>
{
    return vec2<f32>(f32((packed_1 & (u32(65535)))), f32((((packed_1 >> (u32(16)))) & (u32(65535)))));
}

fn unpack_scale_0( packed_2 : u32) -> f32
{
    return unpack_u16_pair_0(packed_2).x * 0.00152590218931437f;
}

fn unpack_turn_0( packed_3 : u32) -> f32
{
    return f32((packed_3 & (u32(255)))) * 0.00392156885936856f * 6.28318548202514648f;
}

struct v2f_0
{
    @builtin(position) position_0 : vec4<f32>,
    @location(0) color_0 : vec3<f32>,
    @location(1) tex_coord_0 : vec2<f32>,
    @location(2) layer_0 : u32,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var i_0 : Sprite_Instance_std430_0 = data_instances_0[instanceID_0];
    var _S1 : u32 = (bitcast<u32>((v_0.position_uv_0.w)));
    var _S2 : vec2<f32> = vec2<f32>(0.00001525902189314f);
    var v_uv_0 : vec2<f32> = vec2<f32>(f32((((_S1 >> (u32(0)))) & (u32(65535)))), f32((((_S1 >> (u32(16)))) & (u32(65535))))) * _S2;
    var position_1 : vec3<f32> = i_0.position_color_0.xyz;
    var icol_0 : vec4<f32> = unpack_rgba_0((bitcast<u32>((i_0.position_color_0.w))));
    var uv_min_0 : vec2<f32> = unpack_u16_pair_0(i_0.uv_min_size_0.x) * _S2;
    var uv_size_0 : vec2<f32> = unpack_u16_pair_0(i_0.uv_min_size_0.y) * _S2;
    var _S3 : u32 = i_0.scale_turns_0.x;
    var sx_0 : f32 = unpack_scale_0(_S3);
    var sy_0 : f32 = unpack_scale_0((_S3 >> (u32(16))));
    var _S4 : u32 = i_0.scale_turns_0.y;
    var pitch_0 : f32 = unpack_turn_0((_S4 & (u32(255))));
    var yaw_0 : f32 = unpack_turn_0((((_S4 >> (u32(8)))) & (u32(255))));
    var roll_0 : f32 = unpack_turn_0((((_S4 >> (u32(16)))) & (u32(255))));
    var layer_1 : u32 = (((_S4 >> (u32(24)))) & (u32(255)));
    var cp_0 : f32 = cos(pitch_0);
    var sp_0 : f32 = sin(pitch_0);
    var cyaw_0 : f32 = cos(yaw_0);
    var syaw_0 : f32 = sin(yaw_0);
    var cr_0 : f32 = cos(roll_0);
    var sr_0 : f32 = sin(roll_0);
    var _S5 : f32 = cr_0 * syaw_0;
    var _S6 : f32 = sr_0 * syaw_0;
    var o_0 : v2f_0;
    o_0.position_0 = (((((((((vec4<f32>(v_0.position_uv_0.xyz, 1.0f)) * (mat4x4<f32>(cr_0 * cyaw_0 * sx_0, (_S5 * sp_0 - sr_0 * cp_0) * sy_0, _S5 * cp_0 + sr_0 * sp_0, position_1.x, sr_0 * cyaw_0 * sx_0, (_S6 * sp_0 + cr_0 * cp_0) * sy_0, _S6 * cp_0 - cr_0 * sp_0, position_1.y, - syaw_0 * sx_0, cyaw_0 * sp_0 * sy_0, cyaw_0 * cp_0, position_1.z, 0.0f, 0.0f, 0.0f, 1.0f))))) * (mat4x4<f32>(data_uniforms_0.world_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(3)]))));
    o_0.color_0 = icol_0.xyz;
    o_0.tex_coord_0 = uv_min_0 + v_uv_0 * uv_size_0;
    o_0.layer_0 = layer_1;
    return o_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) color_1 : vec3<f32>,
    @location(1) tex_coord_1 : vec2<f32>,
    @location(2) layer_2 : u32,
};

@fragment
fn fragmentMain( _S7 : pixelInput_0, @builtin(position) position_2 : vec4<f32>) -> pixelOutput_0
{
    var _S8 : vec3<f32> = vec3<f32>(_S7.tex_coord_1, f32(_S7.layer_2));
    var _S9 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S7.color_1 * (textureSample((data_textures_0), (data_sampler_0), ((_S8)).xy, i32(((_S8)).z))).xyz, 1.0f) );
    return _S9;
}

