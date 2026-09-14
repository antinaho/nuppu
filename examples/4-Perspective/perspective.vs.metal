#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1 "perspective.slang"
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
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


#line 19
struct GPU_Material_0
{
    uint handle_user_0;
    uint user_data_2_0;
};


#line 5606 "core.meta.slang"
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_0 device* materials_1;
    uint32_t device* material_params_0;
    uint32_t device* instance_data_0;
};


#line 5606
struct KernelContext_0
{
    FrameData_default_0 constant* data_1;
};


#line 1 "perspective.slang"
struct v2f_0
{
    float4 position_1;
    float3 color_1;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_2 [[buffer(0)]])
{

#line 1
    thread KernelContext_0 kernelContext_0;

#line 1
    (&kernelContext_0)->data_1 = data_2;

#line 57
    Instance_natural_0 i_0 = data_2->instances_0[instanceID_0];

    float3 vpos_0 = (float4(data_2->verts_0[vertexID_0].position_uv_0) ).xyz;

    float3 position_2 = (float4(i_0.position_pack_0) ).xyz;
    float3 scale_0 = (float4(i_0.scale_pack_0) ).xyz;

#line 62
    float4 _S1 = float4(i_0.rotation_pack_0) ;
    float3 rotation_0 = _S1.xyz;
    uint data_offset_0 = (as_type<uint>((_S1.w)));


    GPU_Material_0 mat_0 = data_2->materials_1[(((uint4(i_0.materials_0) ).x) & 65535U) & 16383U];

#line 67
    uint32_t device* _S2 = data_2->material_params_0;

#line 67
    float _S3 = as_type<float>(_S2[(mat_0.user_data_2_0)>>2]);

#line 67
    float _S4 = as_type<float>(_S2[(mat_0.user_data_2_0 + 4U)>>2]);

#line 67
    float _S5 = as_type<float>(_S2[(mat_0.user_data_2_0 + 8U)>>2]);

#line 67
    float _S6 = as_type<float>(_S2[(mat_0.user_data_2_0 + 12U)>>2]);

#line 67
    float4 _S7 = float4(_S3, _S4, _S5, _S6);

#line 67
    float4 icol_0;



    if(data_offset_0 != 0U)
    {

#line 71
        uint32_t device* _S8 = (&kernelContext_0)->data_1->instance_data_0;

#line 71
        float _S9 = as_type<float>(_S8[(data_offset_0)>>2]);

#line 71
        float _S10 = as_type<float>(_S8[(data_offset_0 + 4U)>>2]);

#line 71
        float _S11 = as_type<float>(_S8[(data_offset_0 + 8U)>>2]);

#line 71
        float _S12 = as_type<float>(_S8[(data_offset_0 + 12U)>>2]);

#line 71
        icol_0 = float4(_S9, _S10, _S11, _S12);

#line 71
    }
    else
    {

#line 71
        icol_0 = _S7;

#line 71
    }

#line 76
    float _S13 = rotation_0.x;

#line 76
    float cp_0 = cos(_S13);

#line 76
    float sp_0 = sin(_S13);
    float _S14 = rotation_0.y;

#line 77
    float cyaw_0 = cos(_S14);

#line 77
    float syaw_0 = sin(_S14);
    float _S15 = rotation_0.z;

#line 78
    float cr_0 = cos(_S15);

#line 78
    float sr_0 = sin(_S15);


    float _S16 = scale_0.x;

#line 81
    float _S17 = cr_0 * syaw_0;

#line 81
    float _S18 = scale_0.y;

#line 81
    float _S19 = scale_0.z;
    float _S20 = sr_0 * syaw_0;

#line 87
    thread v2f_0 o_0;


    (&o_0)->position_1 = (((((((((float4(vpos_0, 1.0f)) * (transpose(matrix<float,int(4),int(4)> (cr_0 * cyaw_0 * _S16, (_S17 * sp_0 - sr_0 * cp_0) * _S18, (_S17 * cp_0 + sr_0 * sp_0) * _S19, 0.0f, sr_0 * cyaw_0 * _S16, (_S20 * sp_0 + cr_0 * cp_0) * _S18, (_S20 * cp_0 - cr_0 * sp_0) * _S19, 0.0f, - syaw_0 * _S16, cyaw_0 * sp_0 * _S18, cyaw_0 * cp_0 * _S19, 0.0f, position_2.x, position_2.y, position_2.z, 1.0f)))))) * (matrix<float,int(4),int(4)> ((&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> ((&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));
    (&o_0)->color_1 = icol_0.xyz;
    v2f_0 _S21 = o_0;

#line 92
    thread vertexMain_Result_0 _S22;

#line 92
    (&_S22)->position_0 = _S21.position_1;

#line 92
    (&_S22)->color_0 = _S21.color_1;

#line 92
    return _S22;
}

