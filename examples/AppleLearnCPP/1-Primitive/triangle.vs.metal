#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1 "examples/AppleLearnCPP/1-Primitive/triangle.slang"
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
};


#line 1
struct Vertex_natural_0
{
    packed_float4 position_1;
    packed_float4 color_1;
};


#line 1
struct VertexData_default_0
{
    Vertex_natural_0 device* verts_0;
};


#line 1
struct v2f_0
{
    float4 position_2;
    float3 color_2;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], VertexData_default_0 constant* data_0 [[buffer(0)]])
{

#line 20
    Vertex_natural_0 v_0 = data_0->verts_0[vertexID_0];

#line 19
    thread v2f_0 o_0;


    (&o_0)->position_2 = float4((float4(v_0.position_1) ).xyz, 1.0f);
    (&o_0)->color_2 = (float4(v_0.color_1) ).xyz;

#line 23
    thread vertexMain_Result_0 _S1;

#line 23
    (&_S1)->position_0 = o_0.position_2;

#line 23
    (&_S1)->color_0 = o_0.color_2;

#line 23
    return _S1;
}

