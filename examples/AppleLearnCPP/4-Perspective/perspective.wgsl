struct _MatrixStorage_float4x4_ColMajorstd140_0
{
    @align(16) data_0 : array<vec4<f32>, i32(4)>,
};

struct CameraData_std140_0
{
    @align(16) perspectiveTransform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
    @align(16) worldTransform_0 : _MatrixStorage_float4x4_ColMajorstd140_0,
};

@binding(0) @group(0) var<uniform> data_camera_0 : CameraData_std140_0;
struct Vertex_std430_0
{
    @align(16) position_uv_0 : vec4<f32>,
    @align(16) color_normal_0 : vec4<u32>,
};

@binding(1) @group(0) var<storage, read> data_verts_0 : array<Vertex_std430_0>;

struct _MatrixStorage_float4x4_ColMajorstd430_0
{
    @align(16) data_1 : array<vec4<f32>, i32(4)>,
};

struct Instance_std430_0
{
    @align(16) transform_0 : _MatrixStorage_float4x4_ColMajorstd430_0,
    @align(16) color_0 : vec4<f32>,
};

@binding(2) @group(0) var<storage, read> data_instances_0 : array<Instance_std430_0>;

struct v2f_0
{
    @builtin(position) position_0 : vec4<f32>,
    @location(0) color_1 : vec3<f32>,
};

@vertex
fn vertexMain(@builtin(vertex_index) vertexID_0 : u32, @builtin(instance_index) instanceID_0 : u32) -> v2f_0
{
    var i_0 : Instance_std430_0 = data_instances_0[instanceID_0];
    var o_0 : v2f_0;
    o_0.position_0 = (((((((((vec4<f32>(data_verts_0[vertexID_0].position_uv_0.xyz.xyz, 1.0f)) * (mat4x4<f32>(i_0.transform_0.data_1[i32(0)][i32(0)], i_0.transform_0.data_1[i32(1)][i32(0)], i_0.transform_0.data_1[i32(2)][i32(0)], i_0.transform_0.data_1[i32(3)][i32(0)], i_0.transform_0.data_1[i32(0)][i32(1)], i_0.transform_0.data_1[i32(1)][i32(1)], i_0.transform_0.data_1[i32(2)][i32(1)], i_0.transform_0.data_1[i32(3)][i32(1)], i_0.transform_0.data_1[i32(0)][i32(2)], i_0.transform_0.data_1[i32(1)][i32(2)], i_0.transform_0.data_1[i32(2)][i32(2)], i_0.transform_0.data_1[i32(3)][i32(2)], i_0.transform_0.data_1[i32(0)][i32(3)], i_0.transform_0.data_1[i32(1)][i32(3)], i_0.transform_0.data_1[i32(2)][i32(3)], i_0.transform_0.data_1[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_camera_0.worldTransform_0.data_0[i32(0)][i32(0)], data_camera_0.worldTransform_0.data_0[i32(1)][i32(0)], data_camera_0.worldTransform_0.data_0[i32(2)][i32(0)], data_camera_0.worldTransform_0.data_0[i32(3)][i32(0)], data_camera_0.worldTransform_0.data_0[i32(0)][i32(1)], data_camera_0.worldTransform_0.data_0[i32(1)][i32(1)], data_camera_0.worldTransform_0.data_0[i32(2)][i32(1)], data_camera_0.worldTransform_0.data_0[i32(3)][i32(1)], data_camera_0.worldTransform_0.data_0[i32(0)][i32(2)], data_camera_0.worldTransform_0.data_0[i32(1)][i32(2)], data_camera_0.worldTransform_0.data_0[i32(2)][i32(2)], data_camera_0.worldTransform_0.data_0[i32(3)][i32(2)], data_camera_0.worldTransform_0.data_0[i32(0)][i32(3)], data_camera_0.worldTransform_0.data_0[i32(1)][i32(3)], data_camera_0.worldTransform_0.data_0[i32(2)][i32(3)], data_camera_0.worldTransform_0.data_0[i32(3)][i32(3)]))))) * (mat4x4<f32>(data_camera_0.perspectiveTransform_0.data_0[i32(0)][i32(0)], data_camera_0.perspectiveTransform_0.data_0[i32(1)][i32(0)], data_camera_0.perspectiveTransform_0.data_0[i32(2)][i32(0)], data_camera_0.perspectiveTransform_0.data_0[i32(3)][i32(0)], data_camera_0.perspectiveTransform_0.data_0[i32(0)][i32(1)], data_camera_0.perspectiveTransform_0.data_0[i32(1)][i32(1)], data_camera_0.perspectiveTransform_0.data_0[i32(2)][i32(1)], data_camera_0.perspectiveTransform_0.data_0[i32(3)][i32(1)], data_camera_0.perspectiveTransform_0.data_0[i32(0)][i32(2)], data_camera_0.perspectiveTransform_0.data_0[i32(1)][i32(2)], data_camera_0.perspectiveTransform_0.data_0[i32(2)][i32(2)], data_camera_0.perspectiveTransform_0.data_0[i32(3)][i32(2)], data_camera_0.perspectiveTransform_0.data_0[i32(0)][i32(3)], data_camera_0.perspectiveTransform_0.data_0[i32(1)][i32(3)], data_camera_0.perspectiveTransform_0.data_0[i32(2)][i32(3)], data_camera_0.perspectiveTransform_0.data_0[i32(3)][i32(3)]))));
    o_0.color_1 = i_0.color_0.xyz;
    return o_0;
}

struct pixelOutput_0
{
    @location(0) output_0 : vec4<f32>,
};

struct pixelInput_0
{
    @location(0) color_2 : vec3<f32>,
};

@fragment
fn fragmentMain( _S1 : pixelInput_0, @builtin(position) position_1 : vec4<f32>) -> pixelOutput_0
{
    var _S2 : pixelOutput_0 = pixelOutput_0( vec4<f32>(_S1.color_2.xyz, 1.0f) );
    return _S2;
}

