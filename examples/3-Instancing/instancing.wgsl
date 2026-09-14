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

struct GPU_Material_std430_0
{
    @align(4) handle_user_0 : u32,
    @align(4) user_data_2_0 : u32,
};

@binding(3) @group(0) var<storage, read> data_materials_0 : array<GPU_Material_std430_0>;

@binding(4) @group(0) var<storage, read> data_material_params_0 : array<u32>;

@binding(5) @group(0) var<storage, read> data_instance_data_0 : array<u32>;

@binding(6) @group(0) var data_textures_0 : texture_2d_array<f32>;

@binding(7) @group(0) var data_sampler_0 : sampler;

struct v2f_0
{
    @builtin(position) position_0 : vec4<f32>,
    @location(0) color_0 : vec3<f32>,
    @location(1) tex_coord_0 : vec2<f32>,
    @location(2) material_0 : u32,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var i_0 : Instance_std430_0 = data_instances_0[instanceID_0];
    var vpos_0 : vec3<f32> = v_0.position_uv_0.xyz;
    var v_uv_packed_0 : u32 = (bitcast<u32>((v_0.position_uv_0.w)));
    var v_uv_0 : vec2<f32> = vec2<f32>(f32((v_uv_packed_0 & (u32(65535)))), f32((((v_uv_packed_0 >> (u32(16)))) & (u32(65535))))) * vec2<f32>(0.00001525902189314f);
    var position_1 : vec3<f32> = i_0.position_pack_0.xyz;
    var scale_0 : vec3<f32> = i_0.scale_pack_0.xyz;
    var rotation_0 : vec3<f32> = i_0.rotation_pack_0.xyz;
    var data_offset_0 : u32 = (bitcast<u32>((i_0.rotation_pack_0.w)));
    var handle_0 : u32 = ((i_0.materials_0.x) & (u32(65535)));
    var mat_0 : GPU_Material_std430_0 = data_materials_0[(handle_0 & (u32(16383)))];
    var _S1 : u32 = data_material_params_0[(mat_0.user_data_2_0)/4];
    var _S2 : f32 = bitcast<f32>(_S1);
    var _S3 : u32 = data_material_params_0[(mat_0.user_data_2_0 + u32(4))/4];
    var _S4 : f32 = bitcast<f32>(_S3);
    var _S5 : u32 = data_material_params_0[(mat_0.user_data_2_0 + u32(8))/4];
    var _S6 : f32 = bitcast<f32>(_S5);
    var _S7 : u32 = data_material_params_0[(mat_0.user_data_2_0 + u32(12))/4];
    var icol_0 : vec4<f32> = vec4<f32>(_S2, _S4, _S6, bitcast<f32>(_S7));
    const _S8 : vec2<f32> = vec2<f32>(0.0f, 0.0f);
    const _S9 : vec2<f32> = vec2<f32>(1.0f, 1.0f);
    var uv_min_0 : vec2<f32>;
    var uv_max_0 : vec2<f32>;
    if(data_offset_0 != u32(0))
    {
        var _S10 : u32 = data_instance_data_0[(data_offset_0)/4];
        var _S11 : f32 = bitcast<f32>(_S10);
        var _S12 : u32 = data_instance_data_0[(data_offset_0 + u32(4))/4];
        var _S13 : vec2<f32> = vec2<f32>(_S11, bitcast<f32>(_S12));
        var _S14 : u32 = data_instance_data_0[(data_offset_0 + u32(8))/4];
        var _S15 : f32 = bitcast<f32>(_S14);
        var _S16 : u32 = data_instance_data_0[(data_offset_0 + u32(12))/4];
        var _S17 : vec2<f32> = vec2<f32>(_S15, bitcast<f32>(_S16));
        var _S18 : u32 = data_instance_data_0[(data_offset_0 + u32(16))/4];
        var _S19 : u32 = data_instance_data_0[(data_offset_0 + u32(20))/4];
        var _S20 : vec3<f32> = icol_0.xyz * vec3<f32>((0.64999997615814209f + 0.34999999403953552f * fract(f32(_S18) * 0.25f + 0.10000000149011612f)));
        icol_0.x = _S20.x;
        icol_0.y = _S20.y;
        icol_0.z = _S20.z;
        uv_min_0 = _S13;
        uv_max_0 = _S17;
    }
    else
    {
        uv_min_0 = _S8;
        uv_max_0 = _S9;
    }
    var _S21 : f32 = rotation_0.x;
    var cp_0 : f32 = cos(_S21);
    var sp_0 : f32 = sin(_S21);
    var _S22 : f32 = rotation_0.y;
    var cyaw_0 : f32 = cos(_S22);
    var syaw_0 : f32 = sin(_S22);
    var _S23 : f32 = rotation_0.z;
    var cr_0 : f32 = cos(_S23);
    var sr_0 : f32 = sin(_S23);
    var _S24 : f32 = scale_0.x;
    var _S25 : f32 = cr_0 * syaw_0;
    var _S26 : f32 = scale_0.y;
    var _S27 : f32 = scale_0.z;
    var _S28 : f32 = sr_0 * syaw_0;
    var o_0 : v2f_0;
    o_0.position_0 = (((((((((vec4<f32>(vpos_0, 1.0f)) * (transpose(mat4x4<f32>(cr_0 * cyaw_0 * _S24, (_S25 * sp_0 - sr_0 * cp_0) * _S26, (_S25 * cp_0 + sr_0 * sp_0) * _S27, 0.0f, sr_0 * cyaw_0 * _S24, (_S28 * sp_0 + cr_0 * cp_0) * _S26, (_S28 * cp_0 - cr_0 * sp_0) * _S27, 0.0f, - syaw_0 * _S24, cyaw_0 * sp_0 * _S26, cyaw_0 * cp_0 * _S27, 0.0f, position_1.x, position_1.y, position_1.z, 1.0f)))))) * (mat4x4<f32>(data_uniforms_0.world_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(3)]))));
    o_0.color_0 = icol_0.xyz;
    o_0.tex_coord_0 = uv_min_0 + v_uv_0 * (uv_max_0 - uv_min_0);
    o_0.material_0 = handle_0;
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
    @location(2) material_1 : u32,
};

@fragment
fn fragmentMain( _S29 : pixelInput_0, @builtin(position) position_2 : vec4<f32>) -> pixelOutput_0
{
    var _S30 : vec3<f32> = vec3<f32>(_S29.tex_coord_1, 0.0f);
    var _S31 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S29.color_1 * (textureSample((data_textures_0), (data_sampler_0), ((_S30)).xy, i32(((_S30)).z))).xyz, 1.0f) );
    return _S31;
}

