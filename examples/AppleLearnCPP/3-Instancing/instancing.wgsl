struct Vertex_std430_0
{
    @align(16) position_uv_0 : vec4<f32>,
    @align(16) color_normal_0 : vec4<u32>,
};

@binding(0) @group(0) var<storage, read> data_verts_0 : array<Vertex_std430_0>;

struct Sprite_Instance_std430_0
{
    @align(16) position_color_0 : vec4<f32>,
    @align(16) uv_min_size_0 : vec2<u32>,
    @align(8) scale_turns_0 : vec2<u32>,
};

@binding(1) @group(0) var<storage, read> data_instances_0 : array<Sprite_Instance_std430_0>;

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

struct v2f_0
{
    @builtin(position) position_0 : vec4<f32>,
    @location(0) color_0 : vec3<f32>,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var i_0 : Sprite_Instance_std430_0 = data_instances_0[instanceID_0];
    var position_1 : vec3<f32> = i_0.position_color_0.xyz;
    var icol_0 : vec4<f32> = unpack_rgba_0((bitcast<u32>((i_0.position_color_0.w))));
    var _S1 : u32 = i_0.scale_turns_0.x;
    var sx_0 : f32 = unpack_scale_0(_S1);
    var sy_0 : f32 = unpack_scale_0((_S1 >> (u32(16))));
    var rz_0 : f32 = unpack_turn_0(((((i_0.scale_turns_0.y) >> (u32(16)))) & (u32(255))));
    var c_0 : f32 = cos(rz_0);
    var s_0 : f32 = sin(rz_0);
    var o_0 : v2f_0;
    o_0.position_0 = (((vec4<f32>(data_verts_0[vertexID_0].position_uv_0.xyz, 1.0f)) * (mat4x4<f32>(sx_0 * c_0, - sy_0 * s_0, 0.0f, position_1.x, sx_0 * s_0, sy_0 * c_0, 0.0f, position_1.y, 0.0f, 0.0f, 1.0f, position_1.z, 0.0f, 0.0f, 0.0f, 1.0f))));
    o_0.color_0 = icol_0.xyz;
    return o_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) color_1 : vec3<f32>,
};

@fragment
fn fragmentMain( _S2 : pixelInput_0, @builtin(position) position_2 : vec4<f32>) -> pixelOutput_0
{
    var _S3 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S2.color_1, 1.0f) );
    return _S3;
}

