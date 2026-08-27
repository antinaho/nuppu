struct ComputeData {
    ConstantBuffer<uint2> grid_size;
    RWTexture2D texture;
};

ParameterBlock<ComputeData> data;

[shader("compute")]
[numthreads(128, 1, 1)]
void mandelbrot_set(
    uint2 index : SV_DispatchThreadID,
) {
    uint2 grid_size = data.grid_size;

    float x0 = 2.0 * index.x / grid_size.x - 1.5;
    float y0 = 2.0 * index.y / grid_size.y - 1.0;

    float x = 0.0;
    float y = 0.0;
    uint iteration = 0;
    const uint max_iteration = 1000;
    float xtmp = 0.0;
    while (x * x + y * y <= 4.0 && iteration < max_iteration) {
        xtmp = x * x - y * y + x0;
        y    = 2.0 * x * y + y0;
        x    = xtmp;
        iteration += 1;
    }

    half color = half(0.5 + 0.5 * cos(3.0 + float(iteration) * 0.15));
    data.texture[index] = half4(color, color, color, half(1.0));
}
