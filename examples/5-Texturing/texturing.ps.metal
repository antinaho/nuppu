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
    float3 normal_0 [[user(NORMAL)]];
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
};


#line 90
struct Shader_Data_default_0
{
    texture2d<float, access::sample> textures_0;
    sampler sampler_0;
};


#line 101 "texturing.slang"
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S1 [[stage_in]], float4 position_0 [[position]], Shader_Data_default_0 constant* shader_0 [[buffer(1)]])
{

#line 109
    float3 _S2 = _S1.color_0 * ((shader_0->textures_0).sample((shader_0->sampler_0), (_S1.tex_coord_0))).xyz;

#line 109
    pixelOutput_0 _S3 = { float4(_S2 * float3(0.10000000149011612f)  + _S2 * float3(saturate(dot(normalize(_S1.normal_0), normalize(float3(1.0f, 1.0f, 0.75f))))) , 1.0f) };
    return _S3;
}

