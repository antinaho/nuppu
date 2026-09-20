#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 47 "animation.slang"
float4 unpack_rgba_0(uint packed_0)
{

#line 48
    return float4(float((packed_0 >> 0U) & 255U), float((packed_0 >> 8U) & 255U), float((packed_0 >> 16U) & 255U), float((packed_0 >> 24U) & 255U)) * float4(0.00392156885936856f) ;
}


#line 1
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
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
struct FrameData_default_0
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
    float3 color_2;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_1 [[buffer(0)]])
{

#line 58
    Vertex_natural_0 v_0 = data_1->verts_0[vertexID_0];
    Instance_natural_0 i_0 = data_1->instances_0[instanceID_0];


    float4 vcol_0 = unpack_rgba_0((uint4(v_0.color_normal_0) ).x);

#line 62
    float3 _S1 = float3(i_0.matrix_x_0) ;

#line 62
    float3 _S2 = float3(i_0.matrix_y_0) ;

#line 62
    float3 _S3 = float3(i_0.matrix_z_0) ;

#line 62
    float3 _S4 = float3(i_0.position_1) ;

#line 71
    thread v2f_0 o_0;

#line 77
    (&o_0)->position_2 = (((((((((float4((float4(v_0.position_uv_0) ).xyz, 1.0f)) * (transpose(matrix<float,int(4),int(4)> (_S1.x, _S1.y, _S1.z, 0.0f, _S2.x, _S2.y, _S2.z, 0.0f, _S3.x, _S3.y, _S3.z, 0.0f, _S4.x, _S4.y, _S4.z, 1.0f)))))) * (matrix<float,int(4),int(4)> (data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> (data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));
    (&o_0)->color_2 = vcol_0.xyz;

#line 78
    thread vertexMain_Result_0 _S5;

#line 78
    (&_S5)->position_0 = o_0.position_2;

#line 78
    (&_S5)->color_0 = o_0.color_2;

#line 78
    return _S5;
}

