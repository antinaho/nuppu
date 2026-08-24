@group(0) @binding(0) var tex: texture_storage_2d<rgba8unorm, write>;

@compute @workgroup_size(128, 1, 1)
fn mandelbrot_set(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.xy;
    let dims = textureDimensions(tex);

    // Scale
    let x0 = 2.0 * f32(index.x) / f32(dims.x) - 1.5;
    let y0 = 2.0 * f32(index.y) / f32(dims.y) - 1.0;

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