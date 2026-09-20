#pragma once

import "shared.slang";

ParameterBlock<Frame_Constant_Data> ENGINE;
ParameterBlock<Frame_Graphics_Data> SHADER;

struct Sprite_VOut {
    float4 position : SV_Position;
    float4 color    : COLOR0;
    float2 tex_coord : TEXCOORD0;
    nointerpolation uint  material : MATERIAL;
};

struct Sprite_Instance {
    float4 position_color;
    float4 matrix_x_uv_min;
    float4 matrix_y_uv_size;

    float3 _unused;
    uint   material_and_flags;
};

struct Sprite_Material {
    float4 _pad;
    float4 _pad2;
};

// Set 1: shader-local constants (the sampler).
struct Shader_Data {
    SamplerState sampler;
}
ParameterBlock<Shader_Data> shader;

// Set 2: per-material resources.
struct Material_Data {
    Texture2D<float4> albedo;
}
ParameterBlock<Material_Data> material;

[shader("vertex")]
Sprite_VOut vertexMain(uint vID : SV_VertexID, uint iID : SV_InstanceID) {
    // Vertex
    Vertex vert = ENGINE.vertex(vID);

    Sprite_Instance inst = SHADER.instance<Sprite_Instance>(iID);
    
    // Instance

    float3 inst_pos = inst.position_color.xyz;
    float4 inst_color = unpack_rgba8(asuint(inst.position_color.w));

    float3 matrix_x = inst.matrix_x_uv_min.xyz;
    float2 inst_uv_min = unpack_u32(asuint(inst.matrix_x_uv_min.w));

    float3 matrix_y = inst.matrix_y_uv_size.xyz;
    float2 inst_uv_size = unpack_u32(asuint(inst.matrix_y_uv_size.w));

    // T R C
    float4x4 world_transform = float4x4(
        float4(matrix_x, 0.0),
        float4(matrix_y, 0.0),
        float4(0.0, 0.0, 0.0, 1.0),
        float4(inst_pos, 1.0)
    );

    // Out
    Sprite_VOut out;

    // Same convention as the mesh shaders: transpose the local TRS to match
    // Slang's row-vector math, then apply camera world + projection.
    float4 world_pos = mul(transpose(world_transform), float4(vert.position, 1.0));
    world_pos = mul(ENGINE.uniform.world_transform, world_pos);
    out.position = mul(ENGINE.uniform.perspective_transform, world_pos);
    out.color = inst_color;
    out.tex_coord = lerp(inst_uv_min, inst_uv_min + inst_uv_size, vert.uv);
    out.material = inst.material_and_flags & 0xFFFFu;

    return out;
}

[shader("fragment")]
float4 fragmentMain(Sprite_VOut in) : SV_Target {
    Sprite_Material m = SHADER.material_scalars<Sprite_Material>(in.material);
    float4 texel = material.albedo.Sample(shader.sampler, in.tex_coord);
    return in.color * texel;
}
