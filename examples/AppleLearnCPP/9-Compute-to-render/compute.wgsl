struct Animation {
    index: u32,
};

@group(0) @binding(0) var<uniform> u_animation: Animation;
@group(0) @binding(1) var tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(128, 1, 1)
fn mandelbrot_set(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.xy;
    let grid_size = textureDimensions(tex);

    let ANIMATION_FREQUENCY: f32 = 0.01;
    let ANIMATION_SPEED: f32 = 4.0;
    let ANIMATION_SCALE_LOW: f32 = 0.62;
    let ANIMATION_SCALE: f32 = 0.38;

    let MANDELBROT_PIXEL_OFFSET: vec2<f32> = vec2<f32>(-0.2, -0.35);
    let MANDELBROT_ORIGIN: vec2<f32> = vec2<f32>(-1.2, -0.32);
    let MANDELBROT_SCALE: vec2<f32> = vec2<f32>(2.2, 2.0);

    let zoom_base = ANIMATION_SCALE_LOW + ANIMATION_SCALE * cos(ANIMATION_FREQUENCY * f32(u_animation.index));
    let zoom = pow(zoom_base, ANIMATION_SPEED);

    // Scale
    let x0 = zoom * MANDELBROT_SCALE.x * (f32(index.x) / f32(grid_size.x) + MANDELBROT_PIXEL_OFFSET.x) + MANDELBROT_ORIGIN.x;
    let y0 = zoom * MANDELBROT_SCALE.y * (f32(index.y) / f32(grid_size.y) + MANDELBROT_PIXEL_OFFSET.y) + MANDELBROT_ORIGIN.y;

    // Implement Mandelbrot set
    var x: f32 = 0.0;
    var y: f32 = 0.0;
    var iter: u32 = 0u;
    let max_iter: u32 = 1000u;
    var xtmp: f32;

    loop {
        if !(x * x + y * y <= 4.0 && iter < max_iter) { break; }
        xtmp = x * x - y * y + x0;
        y = 2.0 * x * y + y0;
        x = xtmp;
        iter += 1u;
    }

    // Convert iteration result to colors
    let color = 0.5 + 0.5 * cos(3.0 + f32(iter) * 0.15);
    textureStore(tex, index, vec4<f32>(color, color, color, 1.0));
}
