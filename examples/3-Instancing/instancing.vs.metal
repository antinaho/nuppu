#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1 "instancing.slang"
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
    uint material_0 [[user(MATERIAL)]];
};


#line 1
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 1
struct Engine_Uniform_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspective_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 ortho_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 world_transform_0;
    float4 camera_position_0;
};


#line 1
struct Vertex_natural_0
{
    packed_float4 position_uv_0;
    packed_uint4 color_normal_0;
};


#line 1
struct Instance_natural_0
{
    packed_float4 position_pack_0;
    packed_float4 scale_pack_0;
    packed_float4 rotation_pack_0;
    packed_uint4 materials_0;
};


#line 25
struct GPU_Material_0
{
    uint handle_user_0;
    uint user_data_2_0;
};


#line 52
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_0 device* materials_1;
    uint32_t device* material_params_0;
    uint32_t device* instance_data_0;
    texture2d_array<float, access::sample> textures_0;
    sampler sampler_0;
};


#line 52
struct KernelContext_0
{
    FrameData_default_0 constant* data_1;
};


#line 1
struct v2f_0
{
    float4 position_1;
    float3 color_1;
    float2 tex_coord_1;
    uint material_1;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_2 [[buffer(0)]])
{

#line 1
    thread KernelContext_0 kernelContext_0;

#line 1
    (&kernelContext_0)->data_1 = data_2;

#line 81
    Instance_natural_0 i_0 = data_2->instances_0[instanceID_0];

#line 81
    float4 _S1 = float4(data_2->verts_0[vertexID_0].position_uv_0) ;


    float3 vpos_0 = _S1.xyz;
    uint v_uv_packed_0 = (as_type<uint>((_S1.w)));



    float2 v_uv_0 = float2(float(v_uv_packed_0 & 65535U), float((v_uv_packed_0 >> 16U) & 65535U)) * float2(0.00001525902189314f) ;

    float3 position_2 = (float4(i_0.position_pack_0) ).xyz;
    float3 scale_0 = (float4(i_0.scale_pack_0) ).xyz;

#line 92
    float4 _S2 = float4(i_0.rotation_pack_0) ;
    float3 rotation_0 = _S2.xyz;
    uint data_offset_0 = (as_type<uint>((_S2.w)));


    uint handle_0 = ((uint4(i_0.materials_0) ).x) & 65535U;
    GPU_Material_0 mat_0 = data_2->materials_1[handle_0 & 16383U];

#line 98
    uint32_t device* _S3 = data_2->material_params_0;

#line 98
    float _S4 = as_type<float>(_S3[(mat_0.user_data_2_0)>>2]);

#line 98
    float _S5 = as_type<float>(_S3[(mat_0.user_data_2_0 + 4U)>>2]);

#line 98
    float _S6 = as_type<float>(_S3[(mat_0.user_data_2_0 + 8U)>>2]);

#line 98
    float _S7 = as_type<float>(_S3[(mat_0.user_data_2_0 + 12U)>>2]);


    thread float4 icol_0 = float4(_S4, _S5, _S6, _S7);
    float2 _S8 = float2(0.0f, 0.0f);
    float2 _S9 = float2(1.0f, 1.0f);

#line 103
    float2 uv_min_0;

#line 103
    float2 uv_max_0;
    if(data_offset_0 != 0U)
    {

#line 104
        uint32_t device* _S10 = (&kernelContext_0)->data_1->instance_data_0;

#line 104
        float _S11 = as_type<float>(_S10[(data_offset_0)>>2]);

#line 104
        float _S12 = as_type<float>(_S10[(data_offset_0 + 4U)>>2]);

#line 104
        float2 _S13 = float2(_S11, _S12);

#line 104
        float _S14 = as_type<float>(_S10[(data_offset_0 + 8U)>>2]);

#line 104
        float _S15 = as_type<float>(_S10[(data_offset_0 + 12U)>>2]);

#line 104
        float2 _S16 = float2(_S14, _S15);

#line 104
        uint _S17 = as_type<uint>(_S10[(data_offset_0 + 16U)>>2]);

#line 104
        uint _S18 = as_type<uint>(_S10[(data_offset_0 + 20U)>>2]);

#line 109
        icol_0.xyz = icol_0.xyz * float3((0.64999997615814209f + 0.34999999403953552f * fract(float(_S17) * 0.25f + 0.10000000149011612f))) ;

#line 109
        uv_min_0 = _S13;

#line 109
        uv_max_0 = _S16;

#line 104
    }
    else
    {

#line 104
        uv_min_0 = _S8;

#line 104
        uv_max_0 = _S9;

#line 104
    }

#line 112
    float _S19 = rotation_0.x;

#line 112
    float cp_0 = cos(_S19);

#line 112
    float sp_0 = sin(_S19);
    float _S20 = rotation_0.y;

#line 113
    float cyaw_0 = cos(_S20);

#line 113
    float syaw_0 = sin(_S20);
    float _S21 = rotation_0.z;

#line 114
    float cr_0 = cos(_S21);

#line 114
    float sr_0 = sin(_S21);


    float _S22 = scale_0.x;

#line 117
    float _S23 = cr_0 * syaw_0;

#line 117
    float _S24 = scale_0.y;

#line 117
    float _S25 = scale_0.z;
    float _S26 = sr_0 * syaw_0;

#line 123
    thread v2f_0 o_0;

#line 130
    (&o_0)->position_1 = (((((((((float4(vpos_0, 1.0f)) * (transpose(matrix<float,int(4),int(4)> (cr_0 * cyaw_0 * _S22, (_S23 * sp_0 - sr_0 * cp_0) * _S24, (_S23 * cp_0 + sr_0 * sp_0) * _S25, 0.0f, sr_0 * cyaw_0 * _S22, (_S26 * sp_0 + cr_0 * cp_0) * _S24, (_S26 * cp_0 - cr_0 * sp_0) * _S25, 0.0f, - syaw_0 * _S22, cyaw_0 * sp_0 * _S24, cyaw_0 * cp_0 * _S25, 0.0f, position_2.x, position_2.y, position_2.z, 1.0f)))))) * (matrix<float,int(4),int(4)> ((&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> ((&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));

    (&o_0)->color_1 = icol_0.xyz;
    (&o_0)->tex_coord_1 = uv_min_0 + v_uv_0 * (uv_max_0 - uv_min_0);
    (&o_0)->material_1 = handle_0;
    v2f_0 _S27 = o_0;

#line 135
    thread vertexMain_Result_0 _S28;

#line 135
    (&_S28)->position_0 = _S27.position_1;

#line 135
    (&_S28)->color_0 = _S27.color_1;

#line 135
    (&_S28)->tex_coord_0 = _S27.tex_coord_1;

#line 135
    (&_S28)->material_0 = _S27.material_1;

#line 135
    return _S28;
}

