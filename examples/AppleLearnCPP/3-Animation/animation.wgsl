struct v2f {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
};

@group(0) @binding(0) var<storage, read> a_positions: array<f32>;
@group(0) @binding(1) var<storage, read> a_colors:    array<f32>;
@group(0) @binding(2) var<uniform> u_angle:           vec4<f32>;

@vertex
fn vertexMain(@builtin(vertex_index) vid: u32) -> v2f {
    var out: v2f;

    let a = u_angle[0].x;

    let m = mat3x3<f32>(
        vec3<f32>( sin(a),  cos(a), 0.0),
        vec3<f32>( cos(a), -sin(a), 0.0),
        vec3<f32>(    0.0,     0.0, 1.0),
    );

    let pi = vid * 3u;
    out.position = vec4<f32>(m * vec3<f32>(
        a_positions[pi + 0u],
        a_positions[pi + 1u],
        a_positions[pi + 2u],
    ), 1.0);

    let ci = vid * 3u;
    out.color = vec3<f32>(
        a_colors[ci + 0u],
        a_colors[ci + 1u],
        a_colors[ci + 2u],
    );

    return out;
}

@fragment
fn fragmentMain(in: v2f) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}
