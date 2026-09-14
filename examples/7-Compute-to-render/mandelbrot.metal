#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 1084 "core"
struct ComputeData_default_0
{
    uint constant* frame_0;
    texture2d<float, access::write> texture_0;
};


#line 19 "examples/AppleLearnCPP/7-Compute-to-render/mandelbrot.slang"
[[kernel]] void mandelbrot_set(uint3 index_0 [[thread_position_in_grid]], ComputeData_default_0 constant* data_0 [[buffer(0)]])
{

#line 20
    uint2 index_1 = index_0.xy;

#line 25
    float zoom_0 = pow(0.62000000476837158f + 0.37999999523162842f * cos(0.00999999977648258f * float(*data_0->frame_0)), 4.0f);

#line 25
    texture2d<float, access::write> _S1 = data_0->texture_0;

    thread uint w_0;

#line 27
    thread uint h_0;
    (*((&w_0)) = (_S1).get_width(0)),(*((&h_0)) = (_S1).get_height(0));

#line 33
    float _S2 = zoom_0 * 2.20000004768371582f * (float(index_1.x) / float(w_0) + -0.20000000298023224f) + -1.20000004768371582f;
    float _S3 = zoom_0 * 2.0f * (float(index_1.y) / float(h_0) + -0.34999999403953552f) + -0.31999999284744263f;

#line 34
    float x_0 = 0.0f;

#line 34
    float y_0 = 0.0f;

#line 34
    uint iteration_0 = 0U;

#line 41
    for(;;)
    {

#line 41
        float _S4 = x_0 * x_0;

#line 41
        float _S5 = y_0 * y_0;

#line 41
        bool _S6;

#line 41
        if((_S4 + _S5) <= 4.0f)
        {

#line 41
            _S6 = iteration_0 < 1000U;

#line 41
        }
        else
        {

#line 41
            _S6 = false;

#line 41
        }

#line 41
        if(_S6)
        {
        }
        else
        {

#line 41
            break;
        }
        float _S7 = 2.0f * x_0 * y_0 + _S3;

        uint iteration_1 = iteration_0 + 1U;

#line 45
        x_0 = _S4 - _S5 + _S2;

#line 45
        y_0 = _S7;

#line 45
        iteration_0 = iteration_1;

#line 41
    }

#line 48
    float color_0 = 0.5f + 0.5f * cos(3.0f + float(iteration_0) * 0.15000000596046448f);
    data_0->texture_0.write(float4(color_0, color_0, color_0, 1.0f),index_1);
    return;
}

