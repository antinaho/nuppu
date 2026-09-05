#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 16 "examples/AppleLearnCPP/3-Instancing_camera/instancing.slang"
struct Sprite_Instance_0
{
    float4 position_color_0;
    uint2 uv_min_size_0;
    uint2 scale_turns_0;
};


#line 16
struct _MatrixStorage_float4x4_ColMajornatural_0
{
    array<float4, int(4)> data_0;
};


#line 16
struct Engine_Uniform_natural_0
{
    _MatrixStorage_float4x4_ColMajornatural_0 perspective_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 ortho_transform_0;
    _MatrixStorage_float4x4_ColMajornatural_0 world_transform_0;
    float4 camera_position_0;
};


#line 16
struct Vertex_natural_0
{
    packed_float4 position_uv_0;
    packed_uint4 color_normal_0;
};


#line 44
struct Instance_0
{
    uint kind_material_0;
    uint extra_data_0;
};


#line 5606 "core.meta.slang"
struct FrameData_default_0
{
    Engine_Uniform_natural_0 constant* uniforms_0;
    Vertex_natural_0 device* verts_0;
    Instance_0 device* instances_0;
    uint32_t device* instances_data_0;
    texture2d_array<float, access::sample> textures_0;
    sampler sampler_0;
};


#line 5606
struct KernelContext_0
{
    FrameData_default_0 constant* data_1;
};


#line 91 "examples/AppleLearnCPP/3-Instancing_camera/instancing.slang"
Sprite_Instance_0 ReadSprite_0(uint byteOffset_0, KernelContext_0 thread* kernelContext_0)
{

#line 91
    uint32_t device* _S1 = kernelContext_0->data_1->instances_data_0;

#line 91
    uint _S2 = as_type<uint>(_S1[(byteOffset_0)>>2]);

#line 91
    uint _S3 = as_type<uint>(_S1[(byteOffset_0 + 4U)>>2]);

#line 91
    uint _S4 = as_type<uint>(_S1[(byteOffset_0 + 8U)>>2]);

#line 91
    uint _S5 = as_type<uint>(_S1[(byteOffset_0 + 12U)>>2]);

#line 91
    uint4 _S6 = uint4(_S2, _S3, _S4, _S5);

#line 91
    uint32_t device* _S7 = kernelContext_0->data_1->instances_data_0;


    uint _S8 = byteOffset_0 + 16U;

#line 94
    uint _S9 = as_type<uint>(_S7[(_S8)>>2]);

#line 94
    uint _S10 = as_type<uint>(_S7[(_S8 + 4U)>>2]);

#line 94
    uint _S11 = as_type<uint>(_S7[(_S8 + 8U)>>2]);

#line 94
    uint _S12 = as_type<uint>(_S7[(_S8 + 12U)>>2]);

    thread Sprite_Instance_0 s_0;

    (&s_0)->position_color_0 = (as_type<float4>((_S6)));
    (&s_0)->uv_min_size_0 = uint2(_S9, _S10);
    (&s_0)->scale_turns_0 = uint2(_S11, _S12);

    return s_0;
}


#line 62
float4 unpack_rgba_0(uint packed_0)
{

#line 63
    return float4(float((packed_0 >> 0U) & 255U), float((packed_0 >> 8U) & 255U), float((packed_0 >> 16U) & 255U), float((packed_0 >> 24U) & 255U)) * float4(0.00392156885936856f) ;
}


#line 71
float2 unpack_u16_pair_0(uint packed_1)
{

#line 72
    return float2(float(packed_1 & 65535U), float((packed_1 >> 16U) & 65535U));
}


#line 79
float unpack_scale_0(uint packed_2)
{

#line 80
    return unpack_u16_pair_0(packed_2).x * 0.00152590218931437f;
}


float unpack_turn_0(uint packed_3)
{

#line 85
    return float(packed_3 & 255U) * 0.00392156885936856f * 6.28318548202514648f;
}


#line 27
struct Mesh_Instance_0
{
    float4 position_color_1;
    uint4 scale_turns_material_0;
};


#line 105
Mesh_Instance_0 ReadMesh_0(uint byteOffset_1, KernelContext_0 thread* kernelContext_1)
{

#line 105
    uint32_t device* _S13 = kernelContext_1->data_1->instances_data_0;

#line 105
    uint _S14 = as_type<uint>(_S13[(byteOffset_1)>>2]);

#line 105
    uint _S15 = as_type<uint>(_S13[(byteOffset_1 + 4U)>>2]);

#line 105
    uint _S16 = as_type<uint>(_S13[(byteOffset_1 + 8U)>>2]);

#line 105
    uint _S17 = as_type<uint>(_S13[(byteOffset_1 + 12U)>>2]);

#line 105
    uint4 _S18 = uint4(_S14, _S15, _S16, _S17);

#line 105
    uint32_t device* _S19 = kernelContext_1->data_1->instances_data_0;


    uint _S20 = byteOffset_1 + 16U;

#line 108
    uint _S21 = as_type<uint>(_S19[(_S20)>>2]);

#line 108
    uint _S22 = as_type<uint>(_S19[(_S20 + 4U)>>2]);

#line 108
    uint _S23 = as_type<uint>(_S19[(_S20 + 8U)>>2]);

#line 108
    uint _S24 = as_type<uint>(_S19[(_S20 + 12U)>>2]);

#line 108
    uint4 _S25 = uint4(_S21, _S22, _S23, _S24);

    thread Mesh_Instance_0 m_0;

    (&m_0)->position_color_1 = (as_type<float4>((_S18)));
    (&m_0)->scale_turns_material_0 = _S25;

    return m_0;
}


#line 115
struct pixelOutput_0
{
    float4 output_0 [[color(0)]];
};


#line 115
struct pixelInput_0
{
    float3 color_0 [[user(COLOR)]];
    float2 tex_coord_0 [[user(TEXCOORD)]];
    uint material_0 [[user(MATERIAL)]];
};


#line 242
[[fragment]] pixelOutput_0 fragmentMain(pixelInput_0 _S26 [[stage_in]], float4 position_0 [[position]], FrameData_default_0 constant* data_2 [[buffer(0)]])
{

#line 243
    float3 _S27 = float3(_S26.tex_coord_0, 0.0f);

#line 243
    pixelOutput_0 _S28 = { float4(_S26.color_0 * ((data_2->textures_0).sample((data_2->sampler_0), ((_S27)).xy, uint(((_S27)).z))).xyz, 1.0f) };
    return _S28;
}


#line 244
struct vertexMain_Result_0
{
    float4 position_1 [[position]];
    float3 color_1 [[user(COLOR)]];
    float2 tex_coord_1 [[user(TEXCOORD)]];
    uint material_1 [[user(MATERIAL)]];
};


#line 1
struct v2f_0
{
    float4 position_2;
    float3 color_2;
    float2 tex_coord_2;
    uint material_2;
};


#line 473 "core"
[[vertex]] vertexMain_Result_0 vertexMain(uint vertexID_0 [[vertex_id]], uint instanceID_0 [[instance_id]], FrameData_default_0 constant* data_3 [[buffer(0)]])
{

#line 473
    v2f_0 _S29;

#line 473
    thread KernelContext_0 kernelContext_2;

#line 473
    (&kernelContext_2)->data_1 = data_3;

#line 473
    for(;;)
    {

#line 121 "examples/AppleLearnCPP/3-Instancing_camera/instancing.slang"
        Instance_0 i_0 = (&kernelContext_2)->data_1->instances_0[instanceID_0];

#line 121
        float4 _S30 = float4((&kernelContext_2)->data_1->verts_0[vertexID_0].position_uv_0) ;


        float3 vpos_0 = _S30.xyz;

        uint _S31 = (as_type<uint>((_S30.w)));

#line 126
        float2 _S32 = float2(0.00001525902189314f) ;

        float2 v_uv_0 = float2(float((_S31 >> 0U) & 65535U), float((_S31 >> 16U) & 65535U)) * _S32;



        uint material_3 = ((i_0.kind_material_0) >> 16U) & 65535U;

#line 138
        uint byteOffset_2 = instanceID_0 * 32U;

#line 143
        float4 _S33 = float4(1.0f, 1.0f, 1.0f, 1.0f);
        float2 _S34 = float2(0.0f, 0.0f);
        float2 _S35 = float2(1.0f, 1.0f);
        matrix<float,int(4),int(4)>  _S36 = matrix<float,int(4),int(4)> (1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f);

#line 146
        matrix<float,int(4),int(4)>  m_1;

#line 146
        float4 icol_0;

#line 146
        float2 uv_min_0;

#line 146
        float2 uv_size_0;

        switch((i_0.kind_material_0) & 65535U)
        {
        case 0U:
            {

#line 148
                Sprite_Instance_0 _S37 = ReadSprite_0(byteOffset_2, &kernelContext_2);

#line 153
                float3 position_3 = _S37.position_color_0.xyz;
                float4 _S38 = unpack_rgba_0((as_type<uint>((_S37.position_color_0.w))));

                float2 _S39 = unpack_u16_pair_0(_S37.uv_min_size_0.x) * _S32;
                float2 _S40 = unpack_u16_pair_0(_S37.uv_min_size_0.y) * _S32;

                uint _S41 = _S37.scale_turns_0.x;

#line 159
                float sx_0 = unpack_scale_0(_S41);
                float sy_0 = unpack_scale_0(_S41 >> 16U);

                uint _S42 = _S37.scale_turns_0.y;

#line 162
                float pitch_0 = unpack_turn_0(_S42 & 255U);
                float yaw_0 = unpack_turn_0((_S42 >> 8U) & 255U);
                float roll_0 = unpack_turn_0((_S42 >> 16U) & 255U);


                float cp_0 = cos(pitch_0);

#line 167
                float sp_0 = sin(pitch_0);
                float cyaw_0 = cos(yaw_0);

#line 168
                float syaw_0 = sin(yaw_0);
                float cr_0 = cos(roll_0);

#line 169
                float sr_0 = sin(roll_0);


                float _S43 = cr_0 * syaw_0;
                float _S44 = sr_0 * syaw_0;

#line 173
                m_1 = matrix<float,int(4),int(4)> (cr_0 * cyaw_0 * sx_0, (_S43 * sp_0 - sr_0 * cp_0) * sy_0, _S43 * cp_0 + sr_0 * sp_0, position_3.x, sr_0 * cyaw_0 * sx_0, (_S44 * sp_0 + cr_0 * cp_0) * sy_0, _S44 * cp_0 - cr_0 * sp_0, position_3.y, - syaw_0 * sx_0, cyaw_0 * sp_0 * sy_0, cyaw_0 * cp_0, position_3.z, 0.0f, 0.0f, 0.0f, 1.0f);

#line 173
                icol_0 = _S38;

#line 173
                uv_min_0 = _S39;

#line 173
                uv_size_0 = _S40;

#line 178
                break;
            }
        case 1U:
            {

#line 178
                Mesh_Instance_0 _S45 = ReadMesh_0(byteOffset_2, &kernelContext_2);

#line 184
                float3 position_4 = _S45.position_color_1.xyz;
                float4 _S46 = unpack_rgba_0((as_type<uint>((_S45.position_color_1.w))));

#line 202
                uint _S47 = _S45.scale_turns_material_0.x;

#line 202
                float sx_1 = unpack_scale_0(_S47 & 65535U);
                float sy_1 = unpack_scale_0((_S47 >> 16U) & 65535U);
                uint _S48 = _S45.scale_turns_material_0.y;

#line 204
                float sz_0 = unpack_scale_0(_S48 & 65535U);

                float pitch_1 = unpack_turn_0((_S48 >> 16U) & 255U);
                float yaw_1 = unpack_turn_0((_S48 >> 24U) & 255U);
                float roll_1 = unpack_turn_0((_S45.scale_turns_material_0.z) & 255U);

                float cp_1 = cos(pitch_1);

#line 210
                float sp_1 = sin(pitch_1);
                float cyaw_1 = cos(yaw_1);

#line 211
                float syaw_1 = sin(yaw_1);
                float cr_1 = cos(roll_1);

#line 212
                float sr_1 = sin(roll_1);


                float _S49 = cr_1 * syaw_1;
                float _S50 = sr_1 * syaw_1;

#line 216
                m_1 = matrix<float,int(4),int(4)> (cr_1 * cyaw_1 * sx_1, (_S49 * sp_1 - sr_1 * cp_1) * sy_1, (_S49 * cp_1 + sr_1 * sp_1) * sz_0, position_4.x, sr_1 * cyaw_1 * sx_1, (_S50 * sp_1 + cr_1 * cp_1) * sy_1, (_S50 * cp_1 - cr_1 * sp_1) * sz_0, position_4.y, - syaw_1 * sx_1, cyaw_1 * sp_1 * sy_1, cyaw_1 * cp_1 * sz_0, position_4.z, 0.0f, 0.0f, 0.0f, 1.0f);

#line 216
                icol_0 = _S46;

#line 216
                uv_min_0 = _S34;

#line 216
                uv_size_0 = _S35;

#line 221
                break;
            }
        default:
            {

#line 221
                m_1 = _S36;

#line 221
                icol_0 = _S33;

#line 221
                uv_min_0 = _S34;

#line 221
                uv_size_0 = _S35;



                break;
            }
        }

        thread v2f_0 o_0;



        (&o_0)->position_2 = (((((((((float4(vpos_0, 1.0f)) * (m_1)))) * (matrix<float,int(4),int(4)> ((&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(0)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(0)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(0)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(0)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(1)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(1)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(1)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(1)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(2)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(2)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(2)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(2)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(0)][int(3)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(1)][int(3)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(2)][int(3)], (&kernelContext_2)->data_1->uniforms_0->world_transform_0.data_0[int(3)][int(3)]))))) * (matrix<float,int(4),int(4)> ((&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(0)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(0)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(0)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(0)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(1)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(1)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(1)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(1)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(2)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(2)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(2)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(2)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(0)][int(3)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(1)][int(3)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(2)][int(3)], (&kernelContext_2)->data_1->uniforms_0->perspective_transform_0.data_0[int(3)][int(3)]))));

        (&o_0)->color_2 = icol_0.xyz;
        (&o_0)->tex_coord_2 = uv_min_0 + v_uv_0 * uv_size_0;
        (&o_0)->material_2 = material_3;

#line 237
        _S29 = o_0;
        break;
    }

#line 238
    thread vertexMain_Result_0 _S51;

#line 238
    (&_S51)->position_1 = _S29.position_2;

#line 238
    (&_S51)->color_1 = _S29.color_2;

#line 238
    (&_S51)->tex_coord_1 = _S29.tex_coord_2;

#line 238
    (&_S51)->material_1 = _S29.material_2;

#line 238
    return _S51;
}

