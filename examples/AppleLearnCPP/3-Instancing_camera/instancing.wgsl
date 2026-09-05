struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct Engine_Uniform_std140_0
{
    @align(16) perspective_transform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) ortho_transform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) world_transform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) camera_position_0 : vec4<f32>,
};

@binding(0) @group(0) var<uniform> data_uniforms_0 : Engine_Uniform_std140_0;
struct Vertex_std430_0
{
    @align(16) position_uv_0 : vec4<f32>,
    @align(16) color_normal_0 : vec4<u32>,
};

@binding(1) @group(0) var<storage, read> data_verts_0 : array<Vertex_std430_0>;

struct Instance_std430_0
{
    @align(4) kind_material_0 : u32,
    @align(4) extra_data_0 : u32,
};

@binding(2) @group(0) var<storage, read> data_instances_0 : array<Instance_std430_0>;

@binding(3) @group(0) var<storage, read> data_instances_data_0 : array<u32>;

@binding(4) @group(0) var data_textures_0 : texture_2d_array<f32>;

@binding(5) @group(0) var data_sampler_0 : sampler;

struct Sprite_Instance_0
{
     position_color_0 : vec4<f32>,
     uv_min_size_0 : vec2<u32>,
     scale_turns_0 : vec2<u32>,
};

fn ReadSprite_0( byteOffset_0 : u32) -> Sprite_Instance_0
{
    var _S1 : u32 = data_instances_data_0[(byteOffset_0)/4];
    var _S2 : u32 = data_instances_data_0[(byteOffset_0 + u32(4))/4];
    var _S3 : u32 = data_instances_data_0[(byteOffset_0 + u32(8))/4];
    var _S4 : u32 = data_instances_data_0[(byteOffset_0 + u32(12))/4];
    var _S5 : vec4<u32> = vec4<u32>(_S1, _S2, _S3, _S4);
    var _S6 : u32 = byteOffset_0 + u32(16);
    var _S7 : u32 = data_instances_data_0[(_S6)/4];
    var _S8 : u32 = data_instances_data_0[(_S6 + u32(4))/4];
    var _S9 : u32 = data_instances_data_0[(_S6 + u32(8))/4];
    var _S10 : u32 = data_instances_data_0[(_S6 + u32(12))/4];
    var s_0 : Sprite_Instance_0;
    s_0.position_color_0 = (bitcast<vec4<f32>>((_S5)));
    s_0.uv_min_size_0 = vec2<u32>(_S7, _S8);
    s_0.scale_turns_0 = vec2<u32>(_S9, _S10);
    return s_0;
}

fn unpack_rgba_0( packed_0 : u32) -> vec4<f32>
{
    return vec4<f32>(f32((((packed_0 >> (u32(0)))) & (u32(255)))), f32((((packed_0 >> (u32(8)))) & (u32(255)))), f32((((packed_0 >> (u32(16)))) & (u32(255)))), f32((((packed_0 >> (u32(24)))) & (u32(255))))) * vec4<f32>(0.00392156885936856f);
}

fn unpack_u16_pair_0( packed_1 : u32) -> vec2<f32>
{
    return vec2<f32>(f32((packed_1 & (u32(65535)))), f32((((packed_1 >> (u32(16)))) & (u32(65535)))));
}

fn unpack_scale_0( packed_2 : u32) -> f32
{
    return unpack_u16_pair_0(packed_2).x * 0.00152590218931437f;
}

fn unpack_turn_0( packed_3 : u32) -> f32
{
    return f32((packed_3 & (u32(255)))) * 0.00392156885936856f * 6.28318548202514648f;
}

struct Mesh_Instance_0
{
     position_color_1 : vec4<f32>,
     scale_turns_material_0 : vec4<u32>,
};

fn ReadMesh_0( byteOffset_1 : u32) -> Mesh_Instance_0
{
    var _S11 : u32 = data_instances_data_0[(byteOffset_1)/4];
    var _S12 : u32 = data_instances_data_0[(byteOffset_1 + u32(4))/4];
    var _S13 : u32 = data_instances_data_0[(byteOffset_1 + u32(8))/4];
    var _S14 : u32 = data_instances_data_0[(byteOffset_1 + u32(12))/4];
    var _S15 : vec4<u32> = vec4<u32>(_S11, _S12, _S13, _S14);
    var _S16 : u32 = byteOffset_1 + u32(16);
    var _S17 : u32 = data_instances_data_0[(_S16)/4];
    var _S18 : u32 = data_instances_data_0[(_S16 + u32(4))/4];
    var _S19 : u32 = data_instances_data_0[(_S16 + u32(8))/4];
    var _S20 : u32 = data_instances_data_0[(_S16 + u32(12))/4];
    var _S21 : vec4<u32> = vec4<u32>(_S17, _S18, _S19, _S20);
    var m_0 : Mesh_Instance_0;
    m_0.position_color_1 = (bitcast<vec4<f32>>((_S15)));
    m_0.scale_turns_material_0 = _S21;
    return m_0;
}

struct v2f_0
{
    @builtin(position) position_0 : vec4<f32>,
    @location(0) color_0 : vec3<f32>,
    @location(1) tex_coord_0 : vec2<f32>,
    @location(2) material_0 : u32,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var i_0 : Instance_std430_0 = data_instances_0[instanceID_0];
    var vpos_0 : vec3<f32> = v_0.position_uv_0.xyz;
    var _S22 : u32 = (bitcast<u32>((v_0.position_uv_0.w)));
    var _S23 : vec2<f32> = vec2<f32>(0.00001525902189314f);
    var v_uv_0 : vec2<f32> = vec2<f32>(f32((((_S22 >> (u32(0)))) & (u32(65535)))), f32((((_S22 >> (u32(16)))) & (u32(65535))))) * _S23;
    var material_1 : u32 = ((((i_0.kind_material_0) >> (u32(16)))) & (u32(65535)));
    var byteOffset_2 : u32 = instanceID_0 * u32(32);
    const _S24 : vec4<f32> = vec4<f32>(1.0f, 1.0f, 1.0f, 1.0f);
    const _S25 : vec2<f32> = vec2<f32>(0.0f, 0.0f);
    const _S26 : vec2<f32> = vec2<f32>(1.0f, 1.0f);
    var _S27 : mat4x4<f32> = mat4x4<f32>(1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f, 0.0f, 0.0f, 0.0f, 0.0f, 1.0f);
    var m_1 : mat4x4<f32>;
    var icol_0 : vec4<f32>;
    var uv_min_0 : vec2<f32>;
    var uv_size_0 : vec2<f32>;
    switch(((i_0.kind_material_0) & (u32(65535))))
    {
    case u32(0):
        {
            var sprite_0 : Sprite_Instance_0 = ReadSprite_0(byteOffset_2);
            var position_1 : vec3<f32> = sprite_0.position_color_0.xyz;
            var _S28 : vec4<f32> = unpack_rgba_0((bitcast<u32>((sprite_0.position_color_0.w))));
            var _S29 : vec2<f32> = unpack_u16_pair_0(sprite_0.uv_min_size_0.x) * _S23;
            var _S30 : vec2<f32> = unpack_u16_pair_0(sprite_0.uv_min_size_0.y) * _S23;
            var _S31 : u32 = sprite_0.scale_turns_0.x;
            var sx_0 : f32 = unpack_scale_0(_S31);
            var sy_0 : f32 = unpack_scale_0((_S31 >> (u32(16))));
            var _S32 : u32 = sprite_0.scale_turns_0.y;
            var pitch_0 : f32 = unpack_turn_0((_S32 & (u32(255))));
            var yaw_0 : f32 = unpack_turn_0((((_S32 >> (u32(8)))) & (u32(255))));
            var roll_0 : f32 = unpack_turn_0((((_S32 >> (u32(16)))) & (u32(255))));
            var cp_0 : f32 = cos(pitch_0);
            var sp_0 : f32 = sin(pitch_0);
            var cyaw_0 : f32 = cos(yaw_0);
            var syaw_0 : f32 = sin(yaw_0);
            var cr_0 : f32 = cos(roll_0);
            var sr_0 : f32 = sin(roll_0);
            var _S33 : f32 = cr_0 * syaw_0;
            var _S34 : f32 = sr_0 * syaw_0;
            m_1 = mat4x4<f32>(cr_0 * cyaw_0 * sx_0, (_S33 * sp_0 - sr_0 * cp_0) * sy_0, _S33 * cp_0 + sr_0 * sp_0, position_1.x, sr_0 * cyaw_0 * sx_0, (_S34 * sp_0 + cr_0 * cp_0) * sy_0, _S34 * cp_0 - cr_0 * sp_0, position_1.y, - syaw_0 * sx_0, cyaw_0 * sp_0 * sy_0, cyaw_0 * cp_0, position_1.z, 0.0f, 0.0f, 0.0f, 1.0f);
            icol_0 = _S28;
            uv_min_0 = _S29;
            uv_size_0 = _S30;
            break;
        }
    case u32(1):
        {
            var mesh_0 : Mesh_Instance_0 = ReadMesh_0(byteOffset_2);
            var position_2 : vec3<f32> = mesh_0.position_color_1.xyz;
            var _S35 : vec4<f32> = unpack_rgba_0((bitcast<u32>((mesh_0.position_color_1.w))));
            var _S36 : u32 = mesh_0.scale_turns_material_0.x;
            var sx_1 : f32 = unpack_scale_0((_S36 & (u32(65535))));
            var sy_1 : f32 = unpack_scale_0((((_S36 >> (u32(16)))) & (u32(65535))));
            var _S37 : u32 = mesh_0.scale_turns_material_0.y;
            var sz_0 : f32 = unpack_scale_0((_S37 & (u32(65535))));
            var pitch_1 : f32 = unpack_turn_0((((_S37 >> (u32(16)))) & (u32(255))));
            var yaw_1 : f32 = unpack_turn_0((((_S37 >> (u32(24)))) & (u32(255))));
            var roll_1 : f32 = unpack_turn_0(((mesh_0.scale_turns_material_0.z) & (u32(255))));
            var cp_1 : f32 = cos(pitch_1);
            var sp_1 : f32 = sin(pitch_1);
            var cyaw_1 : f32 = cos(yaw_1);
            var syaw_1 : f32 = sin(yaw_1);
            var cr_1 : f32 = cos(roll_1);
            var sr_1 : f32 = sin(roll_1);
            var _S38 : f32 = cr_1 * syaw_1;
            var _S39 : f32 = sr_1 * syaw_1;
            m_1 = mat4x4<f32>(cr_1 * cyaw_1 * sx_1, (_S38 * sp_1 - sr_1 * cp_1) * sy_1, (_S38 * cp_1 + sr_1 * sp_1) * sz_0, position_2.x, sr_1 * cyaw_1 * sx_1, (_S39 * sp_1 + cr_1 * cp_1) * sy_1, (_S39 * cp_1 - cr_1 * sp_1) * sz_0, position_2.y, - syaw_1 * sx_1, cyaw_1 * sp_1 * sy_1, cyaw_1 * cp_1 * sz_0, position_2.z, 0.0f, 0.0f, 0.0f, 1.0f);
            icol_0 = _S35;
            uv_min_0 = _S25;
            uv_size_0 = _S26;
            break;
        }
    default :
        {
            m_1 = _S27;
            icol_0 = _S24;
            uv_min_0 = _S25;
            uv_size_0 = _S26;
            break;
        }
    }
    var o_0 : v2f_0;
    o_0.position_0 = (((((((((vec4<f32>(vpos_0, 1.0f)) * (m_1)))) * (mat4x4<f32>(data_uniforms_0.world_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.world_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.world_transform_0.data_0[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(0)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(1)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(2)], data_uniforms_0.perspective_transform_0.data_0[i32(0)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(1)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(2)][i32(3)], data_uniforms_0.perspective_transform_0.data_0[i32(3)][i32(3)]))));
    o_0.color_0 = icol_0.xyz;
    o_0.tex_coord_0 = uv_min_0 + v_uv_0 * uv_size_0;
    o_0.material_0 = material_1;
    return o_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) color_1 : vec3<f32>,
    @location(1) tex_coord_1 : vec2<f32>,
    @location(2) material_2 : u32,
};

@fragment
fn fragmentMain( _S40 : pixelInput_0, @builtin(position) position_3 : vec4<f32>) -> pixelOutput_0
{
    var _S41 : vec3<f32> = vec3<f32>(_S40.tex_coord_1, 0.0f);
    var _S42 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S40.color_1 * (textureSample((data_textures_0), (data_sampler_0), ((_S41)).xy, i32(((_S41)).z))).xyz, 1.0f) );
    return _S42;
}

