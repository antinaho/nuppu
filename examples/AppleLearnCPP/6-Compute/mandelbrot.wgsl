@binding(0) @group(0) var data_texture_0 : texture_storage_2d<rgba8unorm, read_write>;

@compute
@workgroup_size(128, 1, 1)
fn mandelbrot_set(@builtin(global_invocation_id) index_0 : vec3<u32>)
{
    var index_1 : vec2<u32> = index_0.xy;
    var w_0 : u32;
    var h_0 : u32;
    {var dim = textureDimensions((data_texture_0));((w_0)) = dim.x;((h_0)) = dim.y;};
    var _S1 : f32 = 2.0f * f32(index_1.x) / f32(w_0) - 1.5f;
    var _S2 : f32 = 2.0f * f32(index_1.y) / f32(h_0) - 1.0f;
    var x_0 : f32 = 0.0f;
    var y_0 : f32 = 0.0f;
    var iteration_0 : u32 = u32(0);
    for(;;)
    {
        var _S3 : f32 = x_0 * x_0;
        var _S4 : f32 = y_0 * y_0;
        var _S5 : bool;
        if((_S3 + _S4) <= 4.0f)
        {
            _S5 = iteration_0 < u32(1000);
        }
        else
        {
            _S5 = false;
        }
        if(_S5)
        {
        }
        else
        {
            break;
        }
        var _S6 : f32 = 2.0f * x_0 * y_0 + _S2;
        var iteration_1 : u32 = iteration_0 + u32(1);
        x_0 = _S3 - _S4 + _S1;
        y_0 = _S6;
        iteration_0 = iteration_1;
    }
    var color_0 : f32 = 0.5f + 0.5f * cos(3.0f + f32(iteration_0) * 0.15000000596046448f);
    textureStore((data_texture_0), (index_1), (vec4<f32>(color_0, color_0, color_0, 1.0f)));
    return;
}

