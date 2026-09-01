#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 41 "examples/AppleLearnCPP/3-Instancing_camera/instancing.slang"
float4 unpack_rgba_0(uint packed_0)
{

#line 42
    return float4(float((packed_0 >> 0U) & 255U), float((packed_0 >> 8U) & 255U), float((packed_0 >> 16U) & 255U), float((packed_0 >> 24U) & 255U)) * float4(0.00392156885936856f) ;
}


#line 50
float2 unpack_u16_pair_0(uint packed_1)
{

#line 51
    return float2(float(packed_1 & 65535U), float((packed_1 >> 16U) & 65535U));
}


#line 58
float unpack_scale_0(uint packed_2)
{

#line 59
    return unpack_u16_pair_0(packed_2).x * 0.00152590218931437f;
}


float unpack_turn_0(uint packed_3)
{

#line 64
    return float(packed_3 & 255U) * 0.00392156885936856f * 6.28318548202514648f;
}


#line 1
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
    uint layer_0 [[user(LAYER)]];
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
struct Sprite_Instance_natural_0
{
    packed_float4 position_color_0;
    packed_uint2 uv_min_size_0;
    packed_uint2 scale_turns_0;
};


#line 29
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Sprite_Instance_natural_0 device* instances_0;
    texture2d_array<float, access::sample> textures_0;
    sampler sampler_0;
};


#line 1
struct v2f_0
{
    float4 position_1;
    float3 color_1;
    float2 tex_coord_1;
    uint layer_1;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_1 [[buffer(0)]])
{

#line 70
    Sprite_Instance_natural_0 i_0 = data_1->instances_0[instanceID_0];

#line 70
    float4 _S1 = float4(data_1->verts_0[vertexID_0].position_uv_0) ;

#line 75
    uint _S2 = (as_type<uint>((_S1.w)));

#line 75
    float2 _S3 = float2(0.00001525902189314f) ;

    float2 v_uv_0 = float2(float((_S2 >> 0U) & 65535U), float((_S2 >> 16U) & 65535U)) * _S3;

#line 77
    float4 _S4 = float4(i_0.position_color_0) ;

#line 83
    float3 position_2 = _S4.xyz;

    float4 icol_0 = unpack_rgba_0((as_type<uint>((_S4.w))));

#line 85
    uint2 _S5 = uint2(i_0.uv_min_size_0) ;

    float2 uv_min_0 = unpack_u16_pair_0(_S5.x) * _S3;
    float2 uv_size_0 = unpack_u16_pair_0(_S5.y) * _S3;

#line 88
    uint2 _S6 = uint2(i_0.scale_turns_0) ;

    uint _S7 = _S6.x;

#line 90
    float sx_0 = unpack_scale_0(_S7);
    float sy_0 = unpack_scale_0(_S7 >> 16U);

#line 97
    uint _S8 = _S6.y;

#line 97
    float pitch_0 = unpack_turn_0(_S8 & 255U);
    float yaw_0 = unpack_turn_0((_S8 >> 8U) & 255U);
    float roll_0 = unpack_turn_0((_S8 >> 16U) & 255U);
    uint layer_2 = (_S8 >> 24U) & 255U;


    float cp_0 = cos(pitch_0);

#line 103
    float sp_0 = sin(pitch_0);
    float cyaw_0 = cos(yaw_0);

#line 104
    float syaw_0 = sin(yaw_0);
    float cr_0 = cos(roll_0);

#line 105
    float sr_0 = sin(roll_0);


    float _S9 = cr_0 * syaw_0;
    float _S10 = sr_0 * syaw_0;

#line 114
    thread v2f_0 o_0;



    (&o_0)->position_1 = (((((((((float4(_S1.xyz, 1.0f)) * (matrix<float,int(4),int(4)> (cr_0 * cyaw_0 * sx_0, (_S9 * sp_0 - sr_0 * cp_0) * sy_0, _S9 * cp_0 + sr_0 * sp_0, position_2.x, sr_0 * cyaw_0 * sx_0, (_S10 * sp_0 + cr_0 * cp_0) * sy_0, _S10 * cp_0 - cr_0 * sp_0, position_2.y, - syaw_0 * sx_0, cyaw_0 * sp_0 * sy_0, cyaw_0 * cp_0, position_2.z, 0.0f, 0.0f, 0.0f, 1.0f))))) * (matrix<float,int(4),int(4)> (data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> (data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));

    (&o_0)->color_1 = icol_0.xyz;
    (&o_0)->tex_coord_1 = uv_min_0 + v_uv_0 * uv_size_0;
    (&o_0)->layer_1 = layer_2;

#line 122
    thread vertexMain_Result_0 _S11;

#line 122
    (&_S11)->position_0 = o_0.position_1;

#line 122
    (&_S11)->color_0 = o_0.color_1;

#line 122
    (&_S11)->tex_coord_0 = o_0.tex_coord_1;

#line 122
    (&_S11)->layer_0 = o_0.layer_1;

#line 122
    return _S11;
}

