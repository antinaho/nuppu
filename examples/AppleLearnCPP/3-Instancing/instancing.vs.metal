#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 27 "examples/AppleLearnCPP/3-Instancing/instancing.slang"
float4 unpack_rgba_0(uint packed_0)
{

#line 28
    return float4(float((packed_0 >> 0U) & 255U), float((packed_0 >> 8U) & 255U), float((packed_0 >> 16U) & 255U), float((packed_0 >> 24U) & 255U)) * float4(0.00392156885936856f) ;
}


#line 36
float2 unpack_u16_pair_0(uint packed_1)
{

#line 37
    return float2(float(packed_1 & 65535U), float((packed_1 >> 16U) & 65535U));
}


#line 44
float unpack_scale_0(uint packed_2)
{

#line 45
    return unpack_u16_pair_0(packed_2).x * 0.00152590218931437f;
}


float unpack_turn_0(uint packed_3)
{

#line 50
    return float(packed_3 & 255U) * 0.00392156885936856f * 6.28318548202514648f;
}


#line 1
struct vertexMain_Result_0
{
    float4 position_0 [[position]];
    float3 color_0 [[user(COLOR)]];
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


#line 1
struct FrameData_default_0
{
    Vertex_natural_0 device* verts_0;
    Sprite_Instance_natural_0 device* instances_0;
};


#line 1
struct v2f_0
{
    float4 position_1;
    float3 color_1;
};


#line 1
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_0 [[buffer(0)]])
{

#line 56
    Sprite_Instance_natural_0 i_0 = data_0->instances_0[instanceID_0];

#line 56
    float4 _S1 = float4(i_0.position_color_0) ;

#line 69
    float3 position_2 = _S1.xyz;

    float4 icol_0 = unpack_rgba_0((as_type<uint>((_S1.w))));

#line 71
    uint2 _S2 = uint2(i_0.scale_turns_0) ;

#line 76
    uint _S3 = _S2.x;

#line 76
    float sx_0 = unpack_scale_0(_S3);
    float sy_0 = unpack_scale_0(_S3 >> 16U);

#line 83
    float rz_0 = unpack_turn_0(((_S2.y) >> 16U) & 255U);


    float c_0 = cos(rz_0);

#line 86
    float s_0 = sin(rz_0);

#line 94
    thread v2f_0 o_0;
    (&o_0)->position_1 = (((float4((float4(data_0->verts_0[vertexID_0].position_uv_0) ).xyz, 1.0f)) * (matrix<float,int(4),int(4)> (sx_0 * c_0, - sy_0 * s_0, 0.0f, position_2.x, sx_0 * s_0, sy_0 * c_0, 0.0f, position_2.y, 0.0f, 0.0f, 1.0f, position_2.z, 0.0f, 0.0f, 0.0f, 1.0f))));
    (&o_0)->color_1 = icol_0.xyz;

#line 96
    thread vertexMain_Result_0 _S4;

#line 96
    (&_S4)->position_0 = o_0.position_1;

#line 96
    (&_S4)->color_0 = o_0.color_1;

#line 96
    return _S4;
}

