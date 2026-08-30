#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 17 "examples/AppleLearnCPP/1-Primitive/triangle.slang"
float4 unpack_uint_to_float4_01_0(uint value_0)
{
    return float4(float((value_0 >> 0U) & 255U), float((value_0 >> 8U) & 255U), float((value_0 >> 16U) & 255U), float((value_0 >> 24U) & 255U)) * float4(0.00392156885936856f) ;
}


#line 1
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
struct VertexData_default_0
{
    Vertex_natural_0 device* verts_0;
};


#line 1
struct v2f_0
{
    float4 position_1;
    float3 color_1;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], VertexData_default_0 constant* data_0 [[buffer(0)]])
{

#line 35
    Vertex_natural_0 v_0 = data_0->verts_0[vertexID_0];

#line 44
    float4 color_2 = unpack_uint_to_float4_01_0((uint4(v_0.color_normal_0) ).x);

#line 34
    thread v2f_0 o_0;

#line 47
    (&o_0)->position_1 = float4((float4(v_0.position_uv_0) ).xyz, 1.0f);
    (&o_0)->color_1 = color_2.xyz;

#line 48
    thread vertexMain_Result_0 _S1;

#line 48
    (&_S1)->position_0 = o_0.position_1;

#line 48
    (&_S1)->color_0 = o_0.color_1;

#line 48
    return _S1;
}

