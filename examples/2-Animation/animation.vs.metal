#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 43 "animation.slang"
float4 unpack_rgba_0(uint packed_0)
{

#line 44
    return float4(float((packed_0 >> 0U) & 255U), float((packed_0 >> 8U) & 255U), float((packed_0 >> 16U) & 255U), float((packed_0 >> 24U) & 255U)) * float4(0.00392156885936856f) ;
}


#line 1
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


#line 31
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_0 device* materials_1;
    uint32_t device* material_params_0;
    uint32_t device* instance_data_0;
};


#line 1
struct v2f_0
{
    float4 position_1;
    float3 color_1;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_1 [[buffer(0)]])
{

#line 54
    Vertex_natural_0 v_0 = data_1->verts_0[vertexID_0];
    Instance_natural_0 i_0 = data_1->instances_0[instanceID_0];


    float4 vcol_0 = unpack_rgba_0((uint4(v_0.color_normal_0) ).x);

    float3 position_2 = (float4(i_0.position_pack_0) ).xyz;
    float3 scale_0 = (float4(i_0.scale_pack_0) ).xyz;
    float3 rotation_0 = (float4(i_0.rotation_pack_0) ).xyz;

    float _S1 = rotation_0.x;

#line 64
    float cp_0 = cos(_S1);

#line 64
    float sp_0 = sin(_S1);
    float _S2 = rotation_0.y;

#line 65
    float cyaw_0 = cos(_S2);

#line 65
    float syaw_0 = sin(_S2);
    float _S3 = rotation_0.z;

#line 66
    float cr_0 = cos(_S3);

#line 66
    float sr_0 = sin(_S3);


    float _S4 = scale_0.x;

#line 69
    float _S5 = cr_0 * syaw_0;

#line 69
    float _S6 = scale_0.y;

#line 69
    float _S7 = scale_0.z;
    float _S8 = sr_0 * syaw_0;

#line 75
    thread v2f_0 o_0;


    (&o_0)->position_1 = (((((((((float4((float4(v_0.position_uv_0) ).xyz, 1.0f)) * (transpose(matrix<float,int(4),int(4)> (cr_0 * cyaw_0 * _S4, (_S5 * sp_0 - sr_0 * cp_0) * _S6, (_S5 * cp_0 + sr_0 * sp_0) * _S7, 0.0f, sr_0 * cyaw_0 * _S4, (_S8 * sp_0 + cr_0 * cp_0) * _S6, (_S8 * cp_0 - cr_0 * sp_0) * _S7, 0.0f, - syaw_0 * _S4, cyaw_0 * sp_0 * _S6, cyaw_0 * cp_0 * _S7, 0.0f, position_2.x, position_2.y, position_2.z, 1.0f)))))) * (matrix<float,int(4),int(4)> (data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> (data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));
    (&o_0)->color_1 = vcol_0.xyz;

#line 79
    thread vertexMain_Result_0 _S9;

#line 79
    (&_S9)->position_0 = o_0.position_1;

#line 79
    (&_S9)->color_0 = o_0.color_1;

#line 79
    return _S9;
}

