#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 67 "instancing.slang"
float4 unpack_rgba_0(uint packed_0)
{

#line 68
    return float4(float((packed_0 >> 0U) & 255U), float((packed_0 >> 8U) & 255U), float((packed_0 >> 16U) & 255U), float((packed_0 >> 24U) & 255U)) * float4(0.00392156885936856f) ;
}


#line 76
float2 unpack_u16x2_0(uint packed_1)
{

#line 77
    return float2(float(packed_1 & 65535U), float((packed_1 >> 16U) & 65535U)) * float2(0.00001525902189314f) ;
}


#line 2
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
    uint material_0 [[user(MATERIAL)]];
};


#line 2
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 2
struct Engine_Uniform_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspective_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 ortho_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 world_transform_0;
    float4 camera_position_0;
};


#line 2
struct Vertex_natural_0
{
    packed_float4 position_uv_0;
    packed_uint4 color_normal_0;
};


#line 2
struct Instance_natural_0
{
    packed_float3 position_1;
    uint color_1;
    packed_float3 matrix_x_0;
    uint data0_0;
    packed_float3 matrix_y_0;
    uint data1_0;
    packed_float3 matrix_z_0;
    uint material_and_flags_0;
};


#line 2
struct GPU_Material_natural_0
{
    packed_float4 color_2;
    packed_float4 _pad_0;
};


#line 2
struct Engine_Data_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_natural_0 device* materials_0;
};


#line 2
struct KernelContext_0
{
    Engine_Data_default_0 constant* data_1;
};


#line 2
struct v2f_0
{
    float4 position_2;
    float3 color_3;
    float2 tex_coord_1;
    [[flat]] uint material_1;
};


#line 2
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], Engine_Data_default_0 constant* data_2 [[buffer(0)]])
{

#line 2
    thread KernelContext_0 kernelContext_0;

#line 2
    (&kernelContext_0)->data_1 = data_2;

#line 86
    Instance_natural_0 i_0 = data_2->instances_0[instanceID_0];

#line 86
    float4 _S1 = float4(data_2->verts_0[vertexID_0].position_uv_0) ;


    float3 vpos_0 = _S1.xyz;
    uint v_uv_packed_0 = (as_type<uint>((_S1.w)));



    float2 v_uv_0 = float2(float(v_uv_packed_0 & 65535U), float((v_uv_packed_0 >> 16U) & 65535U)) * float2(0.00001525902189314f) ;

    float4 icol_0 = unpack_rgba_0(i_0.color_1);

    uint mat_0 = (i_0.material_and_flags_0) & 65535U;

#line 98
    float2 uv_0;

#line 103
    if(((i_0.material_and_flags_0) & 65536U) != 0U)
    {

#line 103
        uv_0 = unpack_u16x2_0(i_0.data0_0) + v_uv_0 * unpack_u16x2_0(i_0.data1_0);

#line 103
    }
    else
    {

#line 103
        uv_0 = v_uv_0;

#line 103
    }

#line 103
    float3 _S2 = float3(i_0.matrix_x_0) ;

#line 103
    float3 _S3 = float3(i_0.matrix_y_0) ;

#line 103
    float3 _S4 = float3(i_0.matrix_z_0) ;

#line 103
    float3 _S5 = float3(i_0.position_1) ;

#line 115
    thread v2f_0 o_0;

#line 121
    (&o_0)->position_2 = (((((((((float4(vpos_0, 1.0f)) * (transpose(matrix<float,int(4),int(4)> (_S2.x, _S2.y, _S2.z, 0.0f, _S3.x, _S3.y, _S3.z, 0.0f, _S4.x, _S4.y, _S4.z, 0.0f, _S5.x, _S5.y, _S5.z, 1.0f)))))) * (matrix<float,int(4),int(4)> ((&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], (&kernelContext_0)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> ((&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], (&kernelContext_0)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));

    (&o_0)->color_3 = icol_0.xyz;
    (&o_0)->tex_coord_1 = uv_0;
    (&o_0)->material_1 = mat_0;
    v2f_0 _S6 = o_0;

#line 126
    thread vertexMain_Result_0 _S7;

#line 126
    (&_S7)->position_0 = _S6.position_2;

#line 126
    (&_S7)->color_0 = _S6.color_3;

#line 126
    (&_S7)->tex_coord_0 = _S6.tex_coord_1;

#line 126
    (&_S7)->material_0 = _S6.material_1;

#line 126
    return _S7;
}

