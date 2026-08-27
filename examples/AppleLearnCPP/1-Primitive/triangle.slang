struct v2f {
    float4 position : SV_Position;
    float3 color    : COLOR0;
};

struct Vertex {
    float4 position;
    float4 color;
};

struct VertexData {
    StructuredBuffer<Vertex> verts;
};

ParameterBlock<VertexData> data;

[shader("vertex")]
v2f vertexMain(uint vertexID : SV_VertexID) {
    v2f o;
    Vertex v = data.verts[vertexID];

    o.position = float4(v.position.xyz, 1.0);
    o.color = v.color.xyz;
    return o;
}

[shader("fragment")]
float4 fragmentMain(v2f in) : SV_Target
{
    return float4(in.color, 1.0);
}


// slangc examples/AppleLearnCPP/1-Primitive/triangle.slang \
//     -target metal \
//     -entry vertexMain \
//     -stage vertex \
//     -o examples/AppleLearnCPP/1-Primitive/triangle.vs.metal \

// slangc examples/AppleLearnCPP/1-Primitive/triangle.slang \
//     -target metal \
//     -entry fragmentMain \
//     -stage fragment \
//     -o examples/AppleLearnCPP/1-Primitive/triangle.ps.metal

// wgsl compiled to 1 file only
// slangc examples/AppleLearnCPP/1-Primitive/triangle.slang \
//     -target wgsl \
//     -entry vertexMain \
//     -stage vertex \
//     -entry fragmentMain \
//     -stage fragment \
//     -o examples/AppleLearnCPP/1-Primitive/triangle.wgsl



//     -fvk-b-shift 0 all \
//     -fvk-t-shift 50 all \
//     -fvk-u-shift 100 all \
//     -fvk-s-shift 150 all


// slangc examples/AppleLearnCPP/7-Compute-to-render/compute.slang \
//     -target metal \
//     -entry vertexMain \
//     -stage vertex \
//     -o examples/AppleLearnCPP/7-Compute-to-render/compute.vs.metal \

// slangc examples/AppleLearnCPP/7-Compute-to-render/compute.slang \
//     -target metal \
//     -entry fragmentMain \
//     -stage fragment \
//     -o examples/AppleLearnCPP/7-Compute-to-render/compute.ps.metal \

// slangc examples/AppleLearnCPP/7-Compute-to-render/mandelbrot.slang \
//     -target metal \
//     -entry mandelbrot_set \
//     -stage compute \
//     -o examples/AppleLearnCPP/7-Compute-to-render/mandelbrot.metal



// slangc examples/AppleLearnCPP/7-Compute-to-render/mandelbrot.slang \
//     -target wgsl \
//     -entry mandelbrot_set \
//     -stage compute \
//     -o examples/AppleLearnCPP/7-Compute-to-render/mandelbrot.wgsl