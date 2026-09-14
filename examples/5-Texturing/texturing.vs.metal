#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1 "texturing.slang"
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 normal_0 [[user(NORMAL)]];
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
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


#line 21
struct GPU_Material_0
{
    uint handle_user_0;
    uint user_data_2_0;
};


#line 42
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_0 device* materials_1;
    uint32_t device* material_params_0;
    uint32_t device* instance_data_0;
    texture2d<float, access::sample> textures_0;
    sampler sampler_0;
};


#line 42
struct KernelContext_0
{
    FrameData_default_0 constant* data_1;
};


#line 1
struct v2f_0
{
    float4 position_1;
    float3 normal_1;
    float3 color_1;
    float2 tex_coord_1;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_2 [[buffer(0)]])
{

#line 1
    thread KernelContext_0 kernelContext_0;

#line 1
    (&kernelContext_0)->data_1 = data_2;

#line 61
    Vertex_natural_0 v_0 = data_2->verts_0[vertexID_0];
    Instance_natural_0 i_0 = data_2->instances_0[instanceID_0];

#line 62
    float4 _S1 = float4(v_0.position_uv_0) ;

    float3 vpos_0 = _S1.xyz;
    uint v_uv_packed_0 = (as_type<uint>((_S1.w)));



    float2 v_uv_0 = float2(float(v_uv_packed_0 & 65535U), float((v_uv_packed_0 >> 16U) & 65535U)) * float2(0.00001525902189314f) ;


    float3 vnormal_0 = (as_type<float3>(((uint4(v_0.color_normal_0) ).yzw)));

    float3 position_2 = (float4(i_0.position_pack_0) ).xyz;
    float3 scale_0 = (float4(i_0.scale_pack_0) ).xyz;

#line 75
    float4 _S2 = float4(i_0.rotation_pack_0) ;
    float3 rotation_0 = _S2.xyz;
    uint data_offset_0 = (as_type<uint>((_S2.w)));


    GPU_Material_0 mat_0 = data_2->materials_1[(((uint4(i_0.materials_0) ).x) & 65535U) & 16383U];

#line 80
    uint32_t device* _S3 = data_2->material_params_0;

#line 80
    float _S4 = as_type<float>(_S3[(mat_0.user_data_2_0)>>2]);

#line 80
    float _S5 = as_type<float>(_S3[(mat_0.user_data_2_0 + 4U)>>2]);

#line 80
    float _S6 = as_type<float>(_S3[(mat_0.user_data_2_0 + 8U)>>2]);

#line 80
    float _S7 = as_type<float>(_S3[(mat_0.user_data_2_0 + 12U)>>2]);

#line 80
    float4 _S8 = float4(_S4, _S5, _S6, _S7);

#line 80
    float4 icol_0;



    if(data_offset_0 != 0U)
    {

#line 84
        uint32_t device* _S9 = (&kernelContext_0)->data_1->instance_data_0;

#line 84
        float _S10 = as_type<float>(_S9[(data_offset_0)>>2]);

#line 84
        float _S11 = as_type<float>(_S9[(data_offset_0 + 4U)>>2]);

#line 84
        float _S12 = as_type<float>(_S9[(data_offset_0 + 8U)>>2]);

#line 84
        float _S13 = as_type<float>(_S9[(data_offset_0 + 12U)>>2]);

#line 84
        icol_0 = float4(_S10, _S11, _S12, _S13);

#line 84
    }
    else
    {

#line 84
        icol_0 = _S8;

#line 84
    }

#line 89
    float _S14 = rotation_0.x;

#line 89
    float cp_0 = cos(_S14);

#line 89
    float sp_0 = sin(_S14);
    float _S15 = rotation_0.y;

#line 90
    float cyaw_0 = cos(_S15);

#line 90
    float syaw_0 = sin(_S15);
    float _S16 = rotation_0.z;

#line 91
    float cr_0 = cos(_S16);

#line 91
    float sr_0 = sin(_S16);


    float _S17 = scale_0.x;

#line 94
    float _S18 = cr_0 * syaw_0;

#line 94
    float _S19 = scale_0.y;

#line 94
    float _S20 = scale_0.z;
    float _S21 = sr_0 * syaw_0;

#line 101
    matrix<float,int(4),int(4)>  _S22 = transpose(matrix<float,int(4),int(4)> (cr_0 * cyaw_0 * _S17, (_S18 * sp_0 - sr_0 * cp_0) * _S19, (_S18 * cp_0 + sr_0 * sp_0) * _S20, 0.0f, sr_0 * cyaw_0 * _S17, (_S21 * sp_0 + cr_0 * cp_0) * _S19, (_S21 * cp_0 - cr_0 * sp_0) * _S20, 0.0f, - syaw_0 * _S17, cyaw_0 * sp_0 * _S19, cyaw_0 * cp_0 * _S20, 0.0f, position_2.x, position_2.y, position_2.z, 1.0f));

#line 100
    thread v2f_0 o_0;


    (&o_0)->position_1 = (((((((((float4(vpos_0, 1.0f)) * (_S22)))) * (matrix<float,int(4),int(4)> ((&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> ((&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));



    (&o_0)->normal_1 = normalize((((float4(vnormal_0, 0.0f)) * (_S22))).xyz);
    (&o_0)->color_1 = icol_0.xyz;
    (&o_0)->tex_coord_1 = v_uv_0;
    v2f_0 _S23 = o_0;

#line 110
    thread vertexMain_Result_0 _S24;

#line 110
    (&_S24)->position_0 = _S23.position_1;

#line 110
    (&_S24)->normal_0 = _S23.normal_1;

#line 110
    (&_S24)->color_0 = _S23.color_1;

#line 110
    (&_S24)->tex_coord_0 = _S23.tex_coord_1;

#line 110
    return _S24;
}

