struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct _MatrixStorage_float3x3_ColMajorstd140_0
{
    @align(16) data_1 : array<vec4<f32>, i32(3)>,
};

struct CameraData_std140_0
{
    @align(16) perspectiveTransform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) worldTransform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) worldNormalTransform_0 : _MatrixStorage_float3x3_ColMajorstd140_0,
};

@binding(0) @group(0) var<uniform> data_camera_0 : CameraData_std140_0;
struct Vertex_std430_0
{
    @align(16) position_0 : vec4<f32>,
    @align(16) normal_0 : vec4<f32>,
    @align(16) tex_coord_0 : vec2<f32>,
    @align(8) _pad_0 : vec2<f32>,
};

@binding(1) @group(0) var<storage, read> data_verts_0 : array<Vertex_std430_0>;

struct _MatrixStorage_float4x4_ColMajorstd430_0
{
    @align(16) data_2 : array<vec4<f32>, i32(4)>,
};

struct Instance_std430_0
{
    @align(16) transform_0 : _MatrixStorage_float4x4_ColMajorstd430_0,
    @align(16) color_0 : vec4<f32>,
    @align(16) normalTransform_0 : _MatrixStorage_float4x4_ColMajorstd430_0,
};

@binding(2) @group(0) var<storage, read> data_instances_0 : array<Instance_std430_0>;

@binding(3) @group(0) var data_textures_0 : texture_2d_array<f32>;

@binding(4) @group(0) var data_sampler_0 : sampler;

struct v2f_0
{
    @builtin(position) position_1 : vec4<f32>,
    @location(0) normal_1 : vec3<f32>,
    @location(1) color_1 : vec3<f32>,
    @location(2) tex_coord_1 : vec2<f32>,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var v_0 : Vertex_std430_0 = data_verts_0[vertexID_0];
    var _S1 : mat4x4<f32> = mat4x4<f32>(data_instances_0[instanceID_0].normalTransform_0.data_2[i32(0)][i32(0)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(1)][i32(0)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(2)][i32(0)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(3)][i32(0)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(0)][i32(1)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(1)][i32(1)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(2)][i32(1)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(3)][i32(1)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(0)][i32(2)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(1)][i32(2)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(2)][i32(2)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(3)][i32(2)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(0)][i32(3)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(1)][i32(3)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(2)][i32(3)], data_instances_0[instanceID_0].normalTransform_0.data_2[i32(3)][i32(3)]);
    var normal_2 : vec3<f32> = ((((((v_0.normal_0.xyz) * (mat3x3<f32>(_S1[i32(0)].xyz, _S1[i32(1)].xyz, _S1[i32(2)].xyz))))) * (mat3x3<f32>(data_camera_0.worldNormalTransform_0.data_1[i32(0)][i32(0)], data_camera_0.worldNormalTransform_0.data_1[i32(1)][i32(0)], data_camera_0.worldNormalTransform_0.data_1[i32(2)][i32(0)], data_camera_0.worldNormalTransform_0.data_1[i32(0)][i32(1)], data_camera_0.worldNormalTransform_0.data_1[i32(1)][i32(1)], data_camera_0.worldNormalTransform_0.data_1[i32(2)][i32(1)], data_camera_0.worldNormalTransform_0.data_1[i32(0)][i32(2)], data_camera_0.worldNormalTransform_0.data_1[i32(1)][i32(2)], data_camera_0.worldNormalTransform_0.data_1[i32(2)][i32(2)]))));
    var o_0 : v2f_0;
    o_0.position_1 = (((((((((vec4<f32>(v_0.position_0.xyz, 1.0f)) * (mat4x4<f32>(data_instances_0[instanceID_0].transform_0.data_2[i32(0)][i32(0)], data_instances_0[instanceID_0].transform_0.data_2[i32(1)][i32(0)], data_instances_0[instanceID_0].transform_0.data_2[i32(2)][i32(0)], data_instances_0[instanceID_0].transform_0.data_2[i32(3)][i32(0)], data_instances_0[instanceID_0].transform_0.data_2[i32(0)][i32(1)], data_instances_0[instanceID_0].transform_0.data_2[i32(1)][i32(1)], data_instances_0[instanceID_0].transform_0.data_2[i32(2)][i32(1)], data_instances_0[instanceID_0].transform_0.data_2[i32(3)][i32(1)], data_instances_0[instanceID_0].transform_0.data_2[i32(0)][i32(2)], data_instances_0[instanceID_0].transform_0.data_2[i32(1)][i32(2)], data_instances_0[instanceID_0].transform_0.data_2[i32(2)][i32(2)], data_instances_0[instanceID_0].transform_0.data_2[i32(3)][i32(2)], data_instances_0[instanceID_0].transform_0.data_2[i32(0)][i32(3)], data_instances_0[instanceID_0].transform_0.data_2[i32(1)][i32(3)], data_instances_0[instanceID_0].transform_0.data_2[i32(2)][i32(3)], data_instances_0[instanceID_0].transform_0.data_2[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_camera_0.worldTransform_0.data_0[i32(0)][i32(0)], data_camera_0.worldTransform_0.data_0[i32(1)][i32(0)], data_camera_0.worldTransform_0.data_0[i32(2)][i32(0)], data_camera_0.worldTransform_0.data_0[i32(3)][i32(0)], data_camera_0.worldTransform_0.data_0[i32(0)][i32(1)], data_camera_0.worldTransform_0.data_0[i32(1)][i32(1)], data_camera_0.worldTransform_0.data_0[i32(2)][i32(1)], data_camera_0.worldTransform_0.data_0[i32(3)][i32(1)], data_camera_0.worldTransform_0.data_0[i32(0)][i32(2)], data_camera_0.worldTransform_0.data_0[i32(1)][i32(2)], data_camera_0.worldTransform_0.data_0[i32(2)][i32(2)], data_camera_0.worldTransform_0.data_0[i32(3)][i32(2)], data_camera_0.worldTransform_0.data_0[i32(0)][i32(3)], data_camera_0.worldTransform_0.data_0[i32(1)][i32(3)], data_camera_0.worldTransform_0.data_0[i32(2)][i32(3)], data_camera_0.worldTransform_0.data_0[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_camera_0.perspectiveTransform_0.data_0[i32(0)][i32(0)], data_camera_0.perspectiveTransform_0.data_0[i32(1)][i32(0)], data_camera_0.perspectiveTransform_0.data_0[i32(2)][i32(0)], data_camera_0.perspectiveTransform_0.data_0[i32(3)][i32(0)], data_camera_0.perspectiveTransform_0.data_0[i32(0)][i32(1)], data_camera_0.perspectiveTransform_0.data_0[i32(1)][i32(1)], data_camera_0.perspectiveTransform_0.data_0[i32(2)][i32(1)], data_camera_0.perspectiveTransform_0.data_0[i32(3)][i32(1)], data_camera_0.perspectiveTransform_0.data_0[i32(0)][i32(2)], data_camera_0.perspectiveTransform_0.data_0[i32(1)][i32(2)], data_camera_0.perspectiveTransform_0.data_0[i32(2)][i32(2)], data_camera_0.perspectiveTransform_0.data_0[i32(3)][i32(2)], data_camera_0.perspectiveTransform_0.data_0[i32(0)][i32(3)], data_camera_0.perspectiveTransform_0.data_0[i32(1)][i32(3)], data_camera_0.perspectiveTransform_0.data_0[i32(2)][i32(3)], data_camera_0.perspectiveTransform_0.data_0[i32(3)][i32(3)]))));
    o_0.normal_1 = normal_2;
    o_0.color_1 = data_instances_0[instanceID_0].color_0.xyz;
    o_0.tex_coord_1 = v_0.tex_coord_0;
    return o_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) normal_3 : vec3<f32>,
    @location(1) color_2 : vec3<f32>,
    @location(2) tex_coord_2 : vec2<f32>,
};

@fragment
fn fragmentMain( _S2 : pixelInput_0, @builtin(position) position_2 : vec4<f32>) -> pixelOutput_0
{
    var _S3 : vec3<f32> = vec3<f32>(_S2.tex_coord_2, 2.0f);
    var _S4 : vec3<f32> = (textureSample((data_textures_0), (data_sampler_0), ((_S3)).xy, i32(((_S3)).z))).xyz;
    var _S5 : pixelOutput_0 = pixelOutput_0( vec4<f32>(vec3<f32>((dot(_S2.color_2, _S4) * 0.10000000149011612f)) + _S2.color_2 * _S4 * vec3<f32>(saturate(dot(normalize(_S2.normal_3), normalize(vec3<f32>(1.0f, 1.0f, 0.75f))))), 1.0f) );
    return _S5;
}

