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
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 90
struct Engine_Uniform_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspective_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 ortho_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 world_transform_0;
    float4 camera_position_0;
};


#line 90
struct Vertex_natural_0
{
    packed_float4 position_uv_0;
    packed_uint4 color_normal_0;
};


#line 90
struct Instance_natural_0
{
    packed_float4 position_pack_0;
    packed_float4 scale_pack_0;
    packed_float4 rotation_pack_0;
    packed_uint4 materials_0;
};


#line 21 "compute.slang"
struct GPU_Material_0
{
    uint handle_user_0;
    uint user_data_2_0;
};


#line 42
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_0 device* materials_1;
    uint32_t device* material_params_0;
    uint32_t device* instance_data_0;
    texture2d<float, access::sample> textures_0;
    sampler sampler_0;
};


#line 114
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S1 [[stage_in]], float4 position_0 [[position]], FrameData_default_0 constant* data_1 [[buffer(0)]])
{

#line 122
    float3 _S2 = _S1.color_0 * ((data_1->textures_0).sample((data_1->sampler_0), (_S1.tex_coord_0))).xyz;

#line 122
    pixelOutput_0 _S3 = { float4(_S2 * float3(0.10000000149011612f)  + _S2 * float3(saturate(dot(normalize(_S1.normal_0), normalize(float3(1.0f, 1.0f, 0.75f))))) , 1.0f) };
    return _S3;
}

