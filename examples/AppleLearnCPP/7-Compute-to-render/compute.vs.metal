#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1 "examples/AppleLearnCPP/7-Compute-to-render/compute.slang"
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 normal_0 [[user(_SLANG_ATTR)]];
    float3 color_0 [[user(_SLANG_ATTR_1)]];
    float2 tex_coord_0 [[user(_SLANG_ATTR_2)]];
};


#line 1
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 1
struct _MatrixStorage_float3x3_ColMajornatural_0
{
    array<float3, int(3)> data_1;
};


#line 1
struct CameraData_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspectiveTransform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 worldTransform_0;
    _MatrixStorage_float3x3_ColMajornatural_0 worldNormalTransform_0;
};


#line 1
struct Vertex_natural_0
{
    packed_float3 position_1;
    packed_float3 normal_1;
    packed_float2 tex_coord_1;
};


#line 1
struct _MatrixStorage_float4x4_ColMajornatural_1
{
    array<packed_float4, int(4)> data_2;
};


#line 1
struct _MatrixStorage_float3x3_ColMajornatural_1
{
    array<packed_float3, int(3)> data_3;
};


#line 1
struct Instance_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_1 transform_0;
    packed_float4 color_1;
    _MatrixStorage_float3x3_ColMajornatural_1 normalTransform_0;
};


#line 26
struct FrameData_default_0
{
    CameraData_natural_0 constant* camera_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    texture2d<float, access::sample> texture_0;
    sampler sampler_0;
};


#line 1
struct v2f_0
{
    float4 position_2;
    float3 normal_2;
    float3 color_2;
    float2 tex_coord_2;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_4 [[buffer(0)]])
{

#line 43
    Vertex_natural_0 v_0 = data_4->verts_0[vertexID_0];
    Instance_natural_0 i_0 = data_4->instances_0[instanceID_0];

#line 52
    float3 normal_3 = (((((((float3(v_0.normal_1) ).xyz) * (matrix<float,int(3),int(3)> (i_0.normalTransform_0.data_3[int(0)][int(0)], i_0.normalTransform_0.data_3[int(1)][int(0)], i_0.normalTransform_0.data_3[int(2)][int(0)], i_0.normalTransform_0.data_3[int(0)][int(1)], i_0.normalTransform_0.data_3[int(1)][int(1)], i_0.normalTransform_0.data_3[int(2)][int(1)], i_0.normalTransform_0.data_3[int(0)][int(2)], i_0.normalTransform_0.data_3[int(1)][int(2)], i_0.normalTransform_0.data_3[int(2)][int(2)]))))) * (matrix<float,int(3),int(3)> (data_4->camera_0->worldNormalTransform_0.data_1[int(0)][int(0)], data_4->camera_0->worldNormalTransform_0.data_1[int(1)][int(0)], data_4->camera_0->worldNormalTransform_0.data_1[int(2)][int(0)], data_4->camera_0->worldNormalTransform_0.data_1[int(0)][int(1)], data_4->camera_0->worldNormalTransform_0.data_1[int(1)][int(1)], data_4->camera_0->worldNormalTransform_0.data_1[int(2)][int(1)], data_4->camera_0->worldNormalTransform_0.data_1[int(0)][int(2)], data_4->camera_0->worldNormalTransform_0.data_1[int(1)][int(2)], data_4->camera_0->worldNormalTransform_0.data_1[int(2)][int(2)]))));

    thread v2f_0 o_0;

    (&o_0)->position_2 = (((((((((float4((float3(v_0.position_1) ).xyz, 1.0f)) * (matrix<float,int(4),int(4)> (i_0.transform_0.data_2[int(0)][int(0)], i_0.transform_0.data_2[int(1)][int(0)], i_0.transform_0.data_2[int(2)][int(0)], i_0.transform_0.data_2[int(3)][int(0)], i_0.transform_0.data_2[int(0)][int(1)], i_0.transform_0.data_2[int(1)][int(1)], i_0.transform_0.data_2[int(2)][int(1)], i_0.transform_0.data_2[int(3)][int(1)], i_0.transform_0.data_2[int(0)][int(2)], i_0.transform_0.data_2[int(1)][int(2)], i_0.transform_0.data_2[int(2)][int(2)], i_0.transform_0.data_2[int(3)][int(2)], i_0.transform_0.data_2[int(0)][int(3)], i_0.transform_0.data_2[int(1)][int(3)], i_0.transform_0.data_2[int(2)][int(3)], i_0.transform_0.data_2[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> (data_4->camera_0->worldTransform_0.data_0[int(0)][int(0)], data_4->camera_0->worldTransform_0.data_0[int(1)][int(0)], data_4->camera_0->worldTransform_0.data_0[int(2)][int(0)], data_4->camera_0->worldTransform_0.data_0[int(3)][int(0)], data_4->camera_0->worldTransform_0.data_0[int(0)][int(1)], data_4->camera_0->worldTransform_0.data_0[int(1)][int(1)], data_4->camera_0->worldTransform_0.data_0[int(2)][int(1)], data_4->camera_0->worldTransform_0.data_0[int(3)][int(1)], data_4->camera_0->worldTransform_0.data_0[int(0)][int(2)], data_4->camera_0->worldTransform_0.data_0[int(1)][int(2)], data_4->camera_0->worldTransform_0.data_0[int(2)][int(2)], data_4->camera_0->worldTransform_0.data_0[int(3)][int(2)], data_4->camera_0->worldTransform_0.data_0[int(0)][int(3)], data_4->camera_0->worldTransform_0.data_0[int(1)][int(3)], data_4->camera_0->worldTransform_0.data_0[int(2)][int(3)], data_4->camera_0->worldTransform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> (data_4->camera_0->perspectiveTransform_0.data_0[int(0)][int(0)], data_4->camera_0->perspectiveTransform_0.data_0[int(1)][int(0)], data_4->camera_0->perspectiveTransform_0.data_0[int(2)][int(0)], data_4->camera_0->perspectiveTransform_0.data_0[int(3)][int(0)], data_4->camera_0->perspectiveTransform_0.data_0[int(0)][int(1)], data_4->camera_0->perspectiveTransform_0.data_0[int(1)][int(1)], data_4->camera_0->perspectiveTransform_0.data_0[int(2)][int(1)], data_4->camera_0->perspectiveTransform_0.data_0[int(3)][int(1)], data_4->camera_0->perspectiveTransform_0.data_0[int(0)][int(2)], data_4->camera_0->perspectiveTransform_0.data_0[int(1)][int(2)], data_4->camera_0->perspectiveTransform_0.data_0[int(2)][int(2)], data_4->camera_0->perspectiveTransform_0.data_0[int(3)][int(2)], data_4->camera_0->perspectiveTransform_0.data_0[int(0)][int(3)], data_4->camera_0->perspectiveTransform_0.data_0[int(1)][int(3)], data_4->camera_0->perspectiveTransform_0.data_0[int(2)][int(3)], data_4->camera_0->perspectiveTransform_0.data_0[int(3)][int(3)]))));
    (&o_0)->normal_2 = normal_3;
    (&o_0)->color_2 = (float4(i_0.color_1) ).xyz;
    (&o_0)->tex_coord_2 = float2(v_0.tex_coord_1) ;

#line 59
    thread vertexMain_Result_0 _S1;

#line 59
    (&_S1)->position_0 = o_0.position_2;

#line 59
    (&_S1)->normal_0 = o_0.normal_2;

#line 59
    (&_S1)->color_0 = o_0.color_2;

#line 59
    (&_S1)->tex_coord_0 = o_0.tex_coord_2;

#line 59
    return _S1;
}

