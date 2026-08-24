struct v2f {
    @builtin(position) position: vec4<f32>,
    @location(0) normal: vec3<f32>,
    @location(1) color: vec3<f32>,
    @location(2) texcoord: vec2<f32>,
};

struct Vertex {
    position: vec3<f32>,
    normal:   vec3<f32>,
    texcoord: vec2<f32>,
};

struct Instance {
    transform: mat4x4<f32>,
    color: vec4<f32>,
    normal_transform: mat3x3<f32>,
};

struct CameraData {
    perspectiveTransform: mat4x4<f32>,
    worldTransform: mat4x4<f32>,
    worldNormalTransform: mat3x3<f32>,
};

@group(0) @binding(0) var<storage, read> a_vertices:  array<Vertex>;
@group(0) @binding(1) var<storage, read> a_instances: array<Instance>;
@group(0) @binding(2) var<uniform> u_camera: CameraData;
@group(0) @binding(3) var tex: texture_2d<f32>;
@group(0) @binding(4) var samp: sampler;

@vertex
fn vertexMain(@builtin(vertex_index)   vertex_index   : u32,
              @builtin(instance_index) instance_index : u32) -> v2f {
    let vd = a_vertices[vertex_index];
    let id = a_instances[instance_index];

    var out: v2f;
    out.position = u_camera.perspectiveTransform
                 * u_camera.worldTransform
                 * id.transform
                 * vec4<f32>(vd.position, 1.0);
    out.normal    = u_camera.worldNormalTransform * id.normal_transform * vd.normal;
    out.color     = id.color.xyz;
    out.texcoord  = vd.texcoord;
    return out;
}

@fragment
fn fragmentMain(in: v2f) -> @location(0) vec4<f32> {
    let texel = textureSample(tex, samp, in.texcoord).rgb;

    // assume light coming from (front-top-right)
    let l = normalize(vec3<f32>(1.0, 1.0, 0.8));
    let n = normalize(in.normal);

    let ndotl = max(0.0, dot(n, l));

    let illum = (in.color * texel * 0.1) + (in.color * texel * ndotl);
    return vec4<f32>(illum, 1.0);
}
