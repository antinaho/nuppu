struct ComputeData {
    ConstantBuffer<uint2> grid_size;
    ConstantBuffer<uint> frame;
    RWTexture2D texture;
};

ParameterBlock<ComputeData> data;

static const float ANIMATION_FREQUENCY = 0.01;
static const float ANIMATION_SPEED = 4;
static const float ANIMATION_SCALE_LOW = 0.62;
static const float ANIMATION_SCALE = 0.38;

static const float2 MANDELBROT_PIXEL_OFFSET = {-0.2, -0.35};
static const float2 MANDELBROT_ORIGIN = {-1.2, -0.32};
static const float2 MANDELBROT_SCALE = {2.2, 2.0};

[shader("compute")]
[numthreads(128, 1, 1)]
void mandelbrot_set(
    uint2 index : SV_DispatchThreadID,
) {
    // Map time to zoom value in [ANIMATION_SCALE_LOW, 1]
    float zoom = ANIMATION_SCALE_LOW + ANIMATION_SCALE * cos(ANIMATION_FREQUENCY * data.frame);
    // Speed up zooming
    zoom = pow(zoom, ANIMATION_SPEED);

    uint2 grid_size = data.grid_size;

    //Scale
    float x0 = zoom * MANDELBROT_SCALE.x * ((float)index.x / grid_size.x + MANDELBROT_PIXEL_OFFSET.x) + MANDELBROT_ORIGIN.x;
    float y0 = zoom * MANDELBROT_SCALE.y * ((float)index.y / grid_size.y + MANDELBROT_PIXEL_OFFSET.y) + MANDELBROT_ORIGIN.y;

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

    float color = float(0.5 + 0.5 * cos(3.0 + float(iteration) * 0.15));
    data.texture[index] = float4(color, color, color, 1.0);
}
