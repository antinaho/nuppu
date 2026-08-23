struct v2f {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
};

struct Instance {
    transform: mat4x4<f32>,
    color: vec4<f32>,
};

struct CameraData
{
    perspectiveTransform: mat4x4<f32>,
    worldTransform: mat4x4<f32>,
};

@group(0) @binding(0) var<storage, read> a_positions: array<f32>;
@group(0) @binding(1) var<storage, read> a_instances: array<Instance>;
@group(0) @binding(2) var<uniform> u_camera: CameraData;

@vertex
fn vertexMain(@builtin(vertex_index)   vertex_index   : u32,
              @builtin(instance_index) instance_index : u32) -> v2f {
    let pos = vec4<f32>(
        a_positions[vertex_index * 3u + 0u],
        a_positions[vertex_index * 3u + 1u],
        a_positions[vertex_index * 3u + 2u],
        1.0,
    );

    var out: v2f;
    out.position = u_camera.perspectiveTransform
                 * u_camera.worldTransform
                 * a_instances[instance_index].transform
                 * pos;
    out.color    = a_instances[instance_index].color.xyz;
    return out;
}

@fragment
fn fragmentMain(in: v2f) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}


