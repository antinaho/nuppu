struct v2f {
    @builtin(position) position: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) color: vec3<f32>,
};

struct Instance {
    transform: mat4x4<f32>,
    color: vec4<f32>,
    normal_transform: mat3x3<f32>,
};

struct CameraData
{
    perspectiveTransform: mat4x4<f32>,
    worldTransform: mat4x4<f32>,
    worldNormalTransform: mat3x3<f32>,
};

@group(0) @binding(0) var<storage, read> a_positions: array<f32>;
@group(0) @binding(1) var<storage, read> a_instances: array<Instance>;
@group(0) @binding(2) var<uniform> u_camera: CameraData;

@vertex
fn vertexMain(@builtin(vertex_index)   vertex_index   : u32,
              @builtin(instance_index) instance_index : u32) -> v2f {
    let pi = vertex_index * 6u;

    let pos = vec4<f32>(
        a_positions[pi + 0u],
        a_positions[pi + 1u],
        a_positions[pi + 2u],
        1.0,
    );
    let normal = vec3<f32>(
        a_positions[pi + 3u],
        a_positions[pi + 4u],
        a_positions[pi + 5u],
    );

    let inst = a_instances[instance_index];

    var out: v2f;
    out.position = u_camera.perspectiveTransform
                 * u_camera.worldTransform
                 * inst.transform
                 * pos;
    out.normal = u_camera.worldNormalTransform * inst.normal_transform * normal;
    out.color  = inst.color.xyz;
    return out;
}

@fragment
fn fragmentMain(in: v2f) -> @location(0) vec4<f32> {

    // assume light coming from front-top-right
    let l = normalize(vec3<f32>(1.0, 1.0, 0.6));
    let n = normalize(in.normal);

    let ndotl = max(0.0, dot(n, l));

    return vec4<f32>(in.color * 0.1 + in.color * ndotl, 1.0);
}


