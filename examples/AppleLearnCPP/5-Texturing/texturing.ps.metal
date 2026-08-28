#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 90 "core"
struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};


#line 90
struct pixelInput_0
{
    float3 normal_0 [[user(_SLANG_ATTR)]];
    float3 color_0 [[user(_SLANG_ATTR_1)]];
    float2 tex_coord_0 [[user(_SLANG_ATTR_2)]];
};


#line 90
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 90
struct _MatrixStorage_float3x3_ColMajornatural_0
{
    array<float3, int(3)> data_1;
};


#line 90
struct CameraData_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspectiveTransform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 worldTransform_0;
    _MatrixStorage_float3x3_ColMajornatural_0 worldNormalTransform_0;
};


#line 90
struct Vertex_natural_0
{
    packed_float4 position_0;
    packed_float4 normal_1;
    packed_float2 tex_coord_1;
    packed_float2 _pad_0;
};


#line 90
struct _MatrixStorage_float4x4_ColMajornatural_1
{
    array<packed_float4, int(4)> data_2;
};


#line 90
struct Instance_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_1 transform_0;
    packed_float4 color_1;
    _MatrixStorage_float4x4_ColMajornatural_1 normalTransform_0;
};


#line 90
struct FrameData_default_0
{
    CameraData_natural_0 constant* camera_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    texture2d<float, access::sample> texture_0;
    sampler sampler_0;
};


#line 67 "examples/AppleLearnCPP/5-Texturing/texturing.slang"
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S1 [[stage_in]], float4 position_1 [[position]], FrameData_default_0 constant* data_3 [[buffer(0)]])
{

#line 68
    float3 texel_0 = ((data_3->texture_0).sample((data_3->sampler_0), (_S1.tex_coord_0))).xyz;

#line 68
    pixelOutput_0 _S2 = { float4(float3((dot(_S1.color_0, texel_0) * 0.10000000149011612f))  + _S1.color_0 * texel_0 * float3(saturate(dot(normalize(_S1.normal_0), normalize(float3(1.0f, 1.0f, 0.75f))))) , 1.0f) };

#line 77
    return _S2;
}

