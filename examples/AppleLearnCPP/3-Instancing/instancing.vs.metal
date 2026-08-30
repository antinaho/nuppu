#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1 "examples/AppleLearnCPP/3-Instancing/instancing.slang"
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
};


#line 1
struct Vertex_natural_0
{
    packed_float4 position_uv_0;
    packed_uint4 color_normal_0;
};


#line 1
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<packed_float4, int(4)> data_0;
};


#line 1
struct Instance_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 transform_0;
    packed_float4 color_1;
};


#line 1
struct FrameData_default_0
{
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
};


#line 1
struct v2f_0
{
    float4 position_1;
    float3 color_2;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_1 [[buffer(0)]])
{

#line 44
    Instance_natural_0 i_0 = data_1->instances_0[instanceID_0];

#line 60
    thread v2f_0 o_0;

    (&o_0)->position_1 = (((float4((float4(data_1->verts_0[vertexID_0].position_uv_0) ).xyz, 1.0f)) * (matrix<float,int(4),int(4)> (i_0.transform_0.data_0[int(0)][int(0)], i_0.transform_0.data_0[int(1)][int(0)], i_0.transform_0.data_0[int(2)][int(0)], i_0.transform_0.data_0[int(3)][int(0)], i_0.transform_0.data_0[int(0)][int(1)], i_0.transform_0.data_0[int(1)][int(1)], i_0.transform_0.data_0[int(2)][int(1)], i_0.transform_0.data_0[int(3)][int(1)], i_0.transform_0.data_0[int(0)][int(2)], i_0.transform_0.data_0[int(1)][int(2)], i_0.transform_0.data_0[int(2)][int(2)], i_0.transform_0.data_0[int(3)][int(2)], i_0.transform_0.data_0[int(0)][int(3)], i_0.transform_0.data_0[int(1)][int(3)], i_0.transform_0.data_0[int(2)][int(3)], i_0.transform_0.data_0[int(3)][int(3)]))));
    (&o_0)->color_2 = (float4(i_0.color_1) ).xyz;

#line 63
    thread vertexMain_Result_0 _S1;

#line 63
    (&_S1)->position_0 = o_0.position_1;

#line 63
    (&_S1)->color_0 = o_0.color_2;

#line 63
    return _S1;
}

