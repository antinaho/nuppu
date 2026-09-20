#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 90 "core"
struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};


#line 2571 "core.meta.slang"
struct pixelInput_0
{
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
    [[flat]] uint material_0 [[user(MATERIAL)]];
};


#line 2571
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 2571
struct Engine_Uniform_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspective_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 ortho_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 world_transform_0;
    float4 camera_position_0;
};


#line 2571
struct Vertex_natural_0
{
    packed_float4 position_uv_0;
    packed_uint4 color_normal_0;
};


#line 2571
struct Instance_natural_0
{
    packed_float3 position_0;
    uint color_1;
    packed_float3 matrix_x_0;
    uint data0_0;
    packed_float3 matrix_y_0;
    uint data1_0;
    packed_float3 matrix_z_0;
    uint material_and_flags_0;
};


#line 2571
struct GPU_Material_natural_0
{
    packed_float4 color_2;
    packed_float4 _pad_0;
};


#line 2571
struct Engine_Data_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_natural_0 device* materials_0;
};


#line 2571
struct Material_Data_default_0
{
    texture2d<float, access::sample> albedo_0;
};


#line 2571
struct Shader_Data_default_0
{
    sampler sampler_0;
};


#line 2571
struct KernelContext_0
{
    Engine_Data_default_0 constant* data_1;
    Material_Data_default_0 constant* material_1;
    Shader_Data_default_0 constant* shader_0;
};


#line 130 "instancing.slang"
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S1 [[stage_in]], float4 position_1 [[position]], Engine_Data_default_0 constant* data_2 [[buffer(0)]], Material_Data_default_0 constant* material_2 [[buffer(2)]], Shader_Data_default_0 constant* shader_1 [[buffer(1)]])
{

#line 130
    thread KernelContext_0 kernelContext_0;

#line 130
    (&kernelContext_0)->data_1 = data_2;

#line 130
    (&kernelContext_0)->material_1 = material_2;

#line 130
    (&kernelContext_0)->shader_0 = shader_1;

#line 130
    pixelOutput_0 _S2 = { float4(_S1.color_0 * ((material_2->albedo_0).sample((shader_1->sampler_0), (_S1.tex_coord_0))).xyz * (float4(data_2->materials_0[_S1.material_0].color_2) ).xyz, 1.0f) };


    return _S2;
}

