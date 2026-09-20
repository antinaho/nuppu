#pragma once

// Packed
struct __Nuppu_Vertex {
    float4 position_uv;
    uint4  color_normal;
}

struct Vertex {
    float3 position;
    float2 uv;
}

struct Nuppu_Frame_Uniform {
    float4x4 perspective_transform;
    float4x4 ortho_transform;
    float4x4 world_transform;
    float4 camera_position;
};

struct __Nuppu_Material {
    uint8_t data[32];
}
static const uint MATERIAL_SIZE = sizeof(__Nuppu_Material);

struct Frame_Constant_Data {
    ConstantBuffer<Nuppu_Frame_Uniform> uniform;
    StructuredBuffer<__Nuppu_Vertex> verts;

    Vertex vertex(uint vID) {
        __Nuppu_Vertex nv = verts[vID];
        return Vertex(nv.position_uv.xyz, unpack_u32(asuint(nv.position_uv.w)));
    }
};

struct Frame_Graphics_Data {
    ByteAddressBuffer instances;   // layout chosen per shader
    ByteAddressBuffer materials;

    T instance<T>(uint iID) {
        return instances.Load<T>(iID * uint(sizeof(T)));
    }

    T material_scalars<T>(uint matID) {
        return materials.Load<T>(matID * MATERIAL_SIZE);
    }
};

float4 unpack_rgba8(uint packed) {
    return float4(
        float((packed >>  0) & 0xFFu),
        float((packed >>  8) & 0xFFu),
        float((packed >> 16) & 0xFFu),
        float((packed >> 24) & 0xFFu)
    ) * (1.0 / 255.0);
}

float2 unpack_u32(uint packed) {
    return float2(
        float(( packed        & 0xFFFFu)),
        float(((packed >> 16u) & 0xFFFFu))
    ) * (1.0 / 65535.0);
}
