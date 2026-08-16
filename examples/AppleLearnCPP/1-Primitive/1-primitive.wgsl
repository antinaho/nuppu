struct v2f {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
};

@vertex
fn vertexMain(
    @location(0) position: vec3<f32>,
    @location(1) color: vec3<f32>
) -> v2f {
    var out: v2f;

    out.position = vec4<f32>(position, 1.0);
    out.color = color;

    return out;
}

@fragment
fn fragmentMain(
    @location(0) color: vec3<f32>
) -> @location(0) vec4<f32> {
    return vec4<f32>(color.rbg, 1.0);
}