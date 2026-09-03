#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 90 "core"
struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};


#line 2570 "core.meta.slang"
struct pixelInput_0
{
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
    uint material_0 [[user(MATERIAL)]];
};


#line 2570
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 2570
struct Engine_Uniform_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspective_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 ortho_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 world_transform_0;
    float4 camera_position_0;
};


#line 2570
struct Vertex_natural_0
{
    packed_float4 position_uv_0;
    packed_uint4 color_normal_0;
};


#line 44 "examples/AppleLearnCPP/3-Instancing_camera/instancing.slang"
struct Instance_0
{
    uint kind_material_0;
    uint extra_data_0;
};


#line 49
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_0 device* instances_0;
    uint32_t device* instances_data_0;
    texture2d_array<float, access::sample> textures_0;
    sampler sampler_0;
};


#line 242
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S1 [[stage_in]], float4 position_0 [[position]], FrameData_default_0 constant* data_1 [[buffer(0)]])
{

#line 243
    float3 _S2 = float3(_S1.tex_coord_0, 0.0f);

#line 243
    pixelOutput_0 _S3 = { float4(_S1.color_0 * ((data_1->textures_0).sample((data_1->sampler_0), ((_S2)).xy, uint(((_S2)).z))).xyz, 1.0f) };
    return _S3;
}

