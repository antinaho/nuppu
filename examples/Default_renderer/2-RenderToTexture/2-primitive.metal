#include <metal_stdlib>
using namespace metal;

#define u8 uchar;
#define u16 ushort;
#define u32 uint;

#define i8 char;
#define i16 short;
#define i32 int;

#define f16 half;
#define f32 float;

struct v2f {
    float4 position [[position]]; // vertex position
    half3 color;                  // vertex color
    float2 uvs;
};

struct Vertex {
    packed_float3 position;
};

struct alignas(16) Instance {
    float4x4 transform;
    float4 uv_rect;
    uint mesh_id;
};

struct Range {
    uint location;
    uint length;
};

struct alignas(16) Mesh {
    Range vertex_pos_range;
    Range vertex_uv_range;
    Range index_range;
};

struct alignas(16) Data {
    const device Instance* instances;
    const device Mesh* meshes;
    const device packed_float3* vertex_positions;
    const device packed_float2* vertex_uvs;
};

struct alignas(16) CameraData
{
    float4x4 to_clip;
    float4x4 to_view;
};

float4 unpack_color(uint c) {
    return float4(
        float((c >> 24) & 0xFFu),
        float((c >> 16) & 0xFFu),
        float((c >>  8) & 0xFFu),
        float( c        & 0xFFu)
    ) / 255.0;
}

v2f vertex vertexMain(
    uint vertexID  [[vertex_id]],
    uint instanceID [[instance_id]],
    device const Data* data [[buffer(0)]],
    device const CameraData& cameraData [[buffer(1)]]
) {
    v2f o;

    const device Instance& instance = data->instances[instanceID];
    const device Mesh& mesh = data->meshes[instance.mesh_id];
    const device packed_float3& vertex_position = data->vertex_positions[mesh.vertex_pos_range.location + vertexID];

    float4 pos = float4(vertex_position.xyz, 1.0);
    pos = instance.transform * pos;
    pos = cameraData.to_clip * cameraData.to_view * pos;
    o.position = pos;

    // float4 vColorUnpacked = unpack_color(instance.color);
    o.color = half3(1);

    const device packed_float2& vertex_uv = data->vertex_uvs[mesh.vertex_uv_range.location + vertexID];
    o.uvs = mix(instance.uv_rect.xy, instance.uv_rect.zw, vertex_uv.xy);

    return o;
}

half4 fragment fragmentMain(v2f in [[stage_in]]) {
    return half4(in.color, 1.0);
}

// ---------------------------------------------------------------------------
// Screen pass: stretches the offscreen scene_color to fill the swapchain.
//
// Uses a single fullscreen triangle (3 vertices, no index buffer) covering the
// entire NDC range [-1,1] x [-1,1]. The vertex shader accepts a uniform
// describing the NDC bounds of the letterboxed (aspect-preserving) region, so
// the same shader works for any scene size / window size. Outside the
// letterboxed region the UV falls outside [0,1] and the sampler clamps to
// the edge texel of scene_color — which is the offscreen render pass's clear
// colour (sky blue here), NOT black. The swapchain's own clear (dark) shows
// through only outside the fullscreen triangle, which never happens because
// the triangle covers the entire visible NDC range.
//
// Sampling uses filter::nearest so the stretched pixels stay crisp. This is
// the canonical pixel-art "small render target, large window" idiom.

struct ScreenV2F {
    float4 position [[position]];
    float2 uv;
};

vertex ScreenV2F screenVertexMain(
    uint vid                [[vertex_id]],
    constant float4& bounds [[buffer(0)]] // (min_x, min_y, max_x, max_y) NDC rect of the textured region
) {
    // Classic fullscreen-triangle trick. The triangle's vertices are
    // outside the visible NDC area but clipping handles them, and the
    // resulting triangle covers the entire [-1,1]^2 viewport with no
    // overdraw along the diagonal (cheaper than a 2-triangle quad).
    float2 ndc_positions[3] = {
        float2(-1.0, -1.0),
        float2(-1.0,  3.0),
        float2( 3.0, -1.0),
    };

    float2 ndc = ndc_positions[vid];
    float2 min_ndc = bounds.xy;
    float2 max_ndc = bounds.zw;

    ScreenV2F o;
    o.position = float4(ndc, 0.0, 1.0);
    // Map NDC -> UV so the textured region is exactly [0,1] in UV space.
    // Anything outside the letterboxed NDC rect gets UV outside [0,1] and
    // the sampler returns the clamped edge texel of scene_color (which is
    // the offscreen render pass's clear colour — not black). The swapchain's
    // own dark clear shows through only outside the fullscreen triangle,
    // which never happens because the triangle covers the entire NDC range.
    o.uv = (ndc - min_ndc) / (max_ndc - min_ndc);
    return o;
}

half4 fragment screenFragmentMain(
    ScreenV2F in                       [[stage_in]],
    texture2d<half, access::sample> src [[texture(0)]]
) {
    // nearest filter keeps the stretched pixels crisp — the whole point of
    // the small offscreen target for pixel-art rendering.
    constexpr sampler s(filter::nearest, address::clamp_to_edge);
    half4 c = src.sample(s, in.uv);
    return c;
}
