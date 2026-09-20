#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 55 "texturing.slang"
float4 unpack_rgba_0(uint packed_0)
{

#line 56
    return float4(float((packed_0 >> 0U) & 255U), float((packed_0 >> 8U) & 255U), float((packed_0 >> 16U) & 255U), float((packed_0 >> 24U) & 255U)) * float4(0.00392156885936856f) ;
}


#line 1
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 normal_0 [[user(NORMAL)]];
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
};


#line 1
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 1
struct Engine_Uniform_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspective_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 ortho_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 world_transform_0;
    float4 camera_position_0;
};


#line 1
struct Vertex_natural_0
{
    packed_float4 position_uv_0;
    packed_uint4 color_normal_0;
};


#line 1
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


#line 1
struct GPU_Material_natural_0
{
    packed_float4 data0_1;
    packed_float4 data1_1;
};


#line 1
struct Engine_Data_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_natural_0 device* instances_0;
    GPU_Material_natural_0 device* materials_0;
};


#line 1
struct v2f_0
{
    float4 position_2;
    float3 normal_1;
    float3 color_2;
    float2 tex_coord_1;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], Engine_Data_default_0 constant* data_1 [[buffer(0)]])
{

#line 66
    Vertex_natural_0 v_0 = data_1->verts_0[vertexID_0];
    Instance_natural_0 i_0 = data_1->instances_0[instanceID_0];

#line 67
    float4 _S1 = float4(v_0.position_uv_0) ;


    uint v_uv_packed_0 = (as_type<uint>((_S1.w)));



    float2 v_uv_0 = float2(float(v_uv_packed_0 & 65535U), float((v_uv_packed_0 >> 16U) & 65535U)) * float2(0.00001525902189314f) ;


    float3 vnormal_0 = (as_type<float3>(((uint4(v_0.color_normal_0) ).yzw)));
    float4 icol_0 = unpack_rgba_0(i_0.color_1);

#line 78
    float3 _S2 = float3(i_0.matrix_x_0) ;

#line 78
    float3 _S3 = float3(i_0.matrix_y_0) ;

#line 78
    float3 _S4 = float3(i_0.matrix_z_0) ;

#line 78
    float3 _S5 = float3(i_0.position_1) ;

#line 88
    matrix<float,int(4),int(4)>  _S6 = transpose(matrix<float,int(4),int(4)> (_S2.x, _S2.y, _S2.z, 0.0f, _S3.x, _S3.y, _S3.z, 0.0f, _S4.x, _S4.y, _S4.z, 0.0f, _S5.x, _S5.y, _S5.z, 1.0f));

#line 87
    thread v2f_0 o_0;


    (&o_0)->position_2 = (((((((((float4(_S1.xyz, 1.0f)) * (_S6)))) * (matrix<float,int(4),int(4)> (data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> (data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));



    (&o_0)->normal_1 = normalize((((float4(vnormal_0, 0.0f)) * (_S6))).xyz);
    (&o_0)->color_2 = icol_0.xyz;
    (&o_0)->tex_coord_1 = v_uv_0;

#line 96
    thread vertexMain_Result_0 _S7;

#line 96
    (&_S7)->position_0 = o_0.position_2;

#line 96
    (&_S7)->normal_0 = o_0.normal_1;

#line 96
    (&_S7)->color_0 = o_0.color_2;

#line 96
    (&_S7)->tex_coord_0 = o_0.tex_coord_1;

#line 96
    return _S7;
}

