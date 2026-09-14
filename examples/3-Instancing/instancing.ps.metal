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


#line 2570
struct Instance_natural_0
{
    packed_float4 position_pack_0;
    packed_float4 scale_pack_0;
    packed_float4 rotation_pack_0;
    packed_uint4 materials_0;
};


#line 25 "instancing.slang"
struct GPU_Material_0
{
    uint handle_user_0;
    uint user_data_2_0;
};


#line 52
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_0 device* materials_1;
    uint32_t device* material_params_0;
    uint32_t device* instance_data_0;
    texture2d_array<float, access::sample> textures_0;
    sampler sampler_0;
};


#line 139
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S1 [[stage_in]], float4 position_0 [[position]], FrameData_default_0 constant* data_1 [[buffer(0)]])
{

#line 140
    float3 _S2 = float3(_S1.tex_coord_0, 0.0f);

#line 140
    pixelOutput_0 _S3 = { float4(_S1.color_0 * ((data_1->textures_0).sample((data_1->sampler_0), ((_S2)).xy, uint(((_S2)).z))).xyz, 1.0f) };
    return _S3;
}

