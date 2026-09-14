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

@binding(6) @group(0) var data_textures_0 : texture_2d<f32>;

@binding(7) @group(0) var data_sampler_0 : sampler;

struct v2f_0
{
    @builtin(position) position_0 : vec4<f32>,
    @location(0) normal_0 : vec3<f32>,
    @location(1) color_0 : vec3<f32>,
    @location(2) tex_coord_0 : vec2<f32>,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var i_0 : Instance_std430_0 = data_instances_0[instanceID_0];
    var vpos_0 : vec3<f32> = v_0.position_uv_0.xyz;
    var v_uv_packed_0 : u32 = (bitcast<u32>((v_0.position_uv_0.w)));
    var v_uv_0 : vec2<f32> = vec2<f32>(f32((v_uv_packed_0 & (u32(65535)))), f32((((v_uv_packed_0 >> (u32(16)))) & (u32(65535))))) * vec2<f32>(0.00001525902189314f);
    var vnormal_0 : vec3<f32> = (bitcast<vec3<f32>>((v_0.color_normal_0.yzw)));
    var position_1 : vec3<f32> = i_0.position_pack_0.xyz;
    var scale_0 : vec3<f32> = i_0.scale_pack_0.xyz;
    var rotation_0 : vec3<f32> = i_0.rotation_pack_0.xyz;
    var data_offset_0 : u32 = (bitcast<u32>((i_0.rotation_pack_0.w)));
    var mat_0 : GPU_Material_std430_0 = data_materials_0[((((i_0.materials_0.x) & (u32(65535)))) & (u32(16383)))];
    var _S1 : u32 = data_material_params_0[(mat_0.user_data_2_0)/4];
    var _S2 : f32 = bitcast<f32>(_S1);
    var _S3 : u32 = data_material_params_0[(mat_0.user_data_2_0 + u32(4))/4];
    var _S4 : f32 = bitcast<f32>(_S3);
    var _S5 : u32 = data_material_params_0[(mat_0.user_data_2_0 + u32(8))/4];
    var _S6 : f32 = bitcast<f32>(_S5);
    var _S7 : u32 = data_material_params_0[(mat_0.user_data_2_0 + u32(12))/4];
    var _S8 : vec4<f32> = vec4<f32>(_S2, _S4, _S6, bitcast<f32>(_S7));
    var icol_0 : vec4<f32>;
    if(data_offset_0 != u32(0))
    {
        var _S9 : u32 = data_instance_data_0[(data_offset_0)/4];
        var _S10 : f32 = bitcast<f32>(_S9);
        var _S11 : u32 = data_instance_data_0[(data_offset_0 + u32(4))/4];
        var _S12 : f32 = bitcast<f32>(_S11);
        var _S13 : u32 = data_instance_data_0[(data_offset_0 + u32(8))/4];
        var _S14 : f32 = bitcast<f32>(_S13);
        var _S15 : u32 = data_instance_data_0[(data_offset_0 + u32(12))/4];
        icol_0 = vec4<f32>(_S10, _S12, _S14, bitcast<f32>(_S15));
    }
    else
    {
        icol_0 = _S8;
    }
    var _S16 : f32 = rotation_0.x;
    var cp_0 : f32 = cos(_S16);
    var sp_0 : f32 = sin(_S16);
    var _S17 : f32 = rotation_0.y;
    var cyaw_0 : f32 = cos(_S17);
    var syaw_0 : f32 = sin(_S17);
    var _S18 : f32 = rotation_0.z;
    var cr_0 : f32 = cos(_S18);
    var sr_0 : f32 = sin(_S18);
    var _S19 : f32 = scale_0.x;
    var _S20 : f32 = cr_0 * syaw_0;
    var _S21 : f32 = scale_0.y;
    var _S22 : f32 = scale_0.z;
    var _S23 : f32 = sr_0 * syaw_0;
    var _S24 : mat4x4<f32> = transpose(mat4x4<f32>(cr_0 * cyaw_0 * _S19, (_S20 * sp_0 - sr_0 * cp_0) * _S21, (_S20 * cp_0 + sr_0 * sp_0) * _S22, 0.0f, sr_0 * cyaw_0 * _S19, (_S23 * sp_0 + cr_0 * cp_0) * _S21, (_S23 * cp_0 - cr_0 * sp_0) * _S22, 0.0f, - syaw_0 * _S19, cyaw_0 * sp_0 * _S21, cyaw_0 * cp_0 * _S22, 0.0f, position_1.x, position_1.y, position_1.z, 1.0f));
    var o_0 : v2f_0;
    o_0.position_0 = (((((((((vec4<f32>(vpos_0, 1.0f)) * (_S24)))) * (mat4x4<f32>(data_uniforms_0.world_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(3)]))));
    o_0.normal_0 = normalize((((vec4<f32>(vnormal_0, 0.0f)) * (_S24))).xyz);
    o_0.color_0 = icol_0.xyz;
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
    @location(1) color_1 : vec3<f32>,
    @location(2) tex_coord_1 : vec2<f32>,
};

@fragment
fn fragmentMain( _S25 : pixelInput_0, @builtin(position) position_2 : vec4<f32>) -> pixelOutput_0
{
    var _S26 : vec3<f32> = _S25.color_1 * (textureSample((data_textures_0), (data_sampler_0), (_S25.tex_coord_1))).xyz;
    var _S27 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S26 * vec3<f32>(0.10000000149011612f) + _S26 * vec3<f32>(saturate(dot(normalize(_S25.normal_1), normalize(vec3<f32>(1.0f, 1.0f, 0.75f))))), 1.0f) );
    return _S27;
}

