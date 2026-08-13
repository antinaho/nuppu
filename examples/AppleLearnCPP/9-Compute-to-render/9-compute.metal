#include <metal_stdlib>
using namespace metal;

struct Animation {
    uint index;
};

kernel void mandelbrot_set(texture2d<half, access::write> tex [[texture(0)]],
                            uint2 index                        [[thread_position_in_grid]],
                            uint2 grid_size                    [[threads_per_grid]],
                            device const Animation& frame           [[buffer(0)]]) {
    constexpr float ANIMATION_FREQUENCY = 0.01;
    constexpr float ANIMATION_SPEED = 4;
    constexpr float ANIMATION_SCALE_LOW = 0.62;
    constexpr float ANIMATION_SCALE = 0.38;

    constexpr float2 MANDELBROT_PIXEL_OFFSET = {-0.2, -0.35};
    constexpr float2 MANDELBROT_ORIGIN = {-1.2, -0.32};
    constexpr float2 MANDELBROT_SCALE = {2.2, 2.0};

    // Map time to zoom value in [ANIMATION_SCALE_LOW, 1]
    float zoom = ANIMATION_SCALE_LOW + ANIMATION_SCALE * cos(ANIMATION_FREQUENCY * frame.index);
    // Speed up zooming
    zoom = pow(zoom, ANIMATION_SPEED);

    //Scale
    float x0 = zoom * MANDELBROT_SCALE.x * ((float)index.x / grid_size.x + MANDELBROT_PIXEL_OFFSET.x) + MANDELBROT_ORIGIN.x;
    float y0 = zoom * MANDELBROT_SCALE.y * ((float)index.y / grid_size.y + MANDELBROT_PIXEL_OFFSET.y) + MANDELBROT_ORIGIN.y;

    // Implement Mandelbrot set
    float x = 0.0;
    float y = 0.0;
    uint iteration = 0;
    uint max_iteration = 1000;
    float xtmp = 0.0;
    while (x * x + y * y <= 4 && iteration < max_iteration) {
        xtmp = x * x - y * y + x0;
        y = 2 * x * y + y0;
        x = xtmp;
        iteration += 1;
    }

    // Convert iteration result to colors
    half color = (0.5 + 0.5 * cos(3.0 + iteration * 0.15));
    tex.write(half4(color, color, color, 1.0), index, 0);
}