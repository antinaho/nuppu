#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 2 "examples/1_Window/triangle.slang"
struct VertexOutput_0
{
    float4 position_0;
    float4 color_0;
};


#line 7
struct Vertex_natural_0
{
    packed_float2 position_1;
    packed_float2 tex_coords_0;
    packed_float4 color_1;
};


#line 7
struct Data_0
{
    float2 extra_0;
    Vertex_natural_0 device* verts_0;
};


#line 7
struct KernelContext_0
{
    Data_0 constant* entryPointParams_data_0;
};


#line 19
VertexOutput_0 vertexMain_0(const uint thread* vertexID_0, KernelContext_0 thread* kernelContext_0)
{

#line 20
    Vertex_natural_0 device* _S1 = kernelContext_0->entryPointParams_data_0->verts_0 + *vertexID_0;

#line 25
    Vertex_natural_0 v_0 = *_S1;

#line 23
    thread VertexOutput_0 output_0;



    (&output_0)->position_0 = float4(float2((*_S1).position_1)  + kernelContext_0->entryPointParams_data_0->extra_0, 0.0f, 1.0f);
    (&output_0)->color_0 = float4(v_0.color_1) ;

    return output_0;
}


#line 30
struct pixelOutput_0
{
    float4 output_1 [[color(0)]];
};


#line 30
struct pixelInput_0
{
    float4 color_2 [[user(TEXCOORD)]];
};


#line 34
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S2 [[stage_in]], float4 position_2 [[position]])
{

#line 34
    pixelOutput_0 _S3 = { _S2.color_2 };
    return _S3;
}


#line 35
struct vertexMain_Result_0
{
    float4 position_3 [[position]];
    float4 color_3 [[user(TEXCOORD)]];
};


#line 35
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_1 [[vertex_id]], Data_0 constant* entryPointParams_data_1 [[buffer(0)]])
{

#line 35
    thread KernelContext_0 kernelContext_1;

#line 35
    (&kernelContext_1)->entryPointParams_data_0 = entryPointParams_data_1;

#line 35
    thread uint _S4 = vertexID_1;

#line 35
    VertexOutput_0 _S5 = vertexMain_0(&_S4, &kernelContext_1);

#line 35
    thread vertexMain_Result_0 _S6;

#line 35
    (&_S6)->position_3 = _S5.position_0;

#line 35
    (&_S6)->color_3 = _S5.color_0;

#line 35
    return _S6;
}

