#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 90 "core"
struct ComputeData_default_0
{
    texture2d<float, access::read_write> texture_0;
};


#line 9 "examples/AppleLearnCPP/6-Compute/mandelbrot.slang"
[[kernel]] void mandelbrot_set(uint3 index_0 [[thread_position_in_grid]], ComputeData_default_0 constant* data_0 [[buffer(0)]])
{

#line 10
    uint2 index_1 = index_0.xy;

#line 10
    texture2d<float, access::read_write> _S1 = data_0->texture_0;


    thread uint w_0;

#line 13
    thread uint h_0;
    (*((&w_0)) = (_S1).get_width(0)),(*((&h_0)) = (_S1).get_height(0));



    float _S2 = 2.0f * float(index_1.x) / float(w_0) - 1.5f;
    float _S3 = 2.0f * float(index_1.y) / float(h_0) - 1.0f;

#line 19
    float x_0 = 0.0f;

#line 19
    float y_0 = 0.0f;

#line 19
    uint iteration_0 = 0U;

#line 26
    for(;;)
    {

#line 26
        float _S4 = x_0 * x_0;

#line 26
        float _S5 = y_0 * y_0;

#line 26
        bool _S6;

#line 26
        if((_S4 + _S5) <= 4.0f)
        {

#line 26
            _S6 = iteration_0 < 1000U;

#line 26
        }
        else
        {

#line 26
            _S6 = false;

#line 26
        }

#line 26
        if(_S6)
        {
        }
        else
        {

#line 26
            break;
        }
        float _S7 = 2.0f * x_0 * y_0 + _S3;

        uint iteration_1 = iteration_0 + 1U;

#line 30
        x_0 = _S4 - _S5 + _S2;

#line 30
        y_0 = _S7;

#line 30
        iteration_0 = iteration_1;

#line 26
    }

#line 33
    float color_0 = 0.5f + 0.5f * cos(3.0f + float(iteration_0) * 0.15000000596046448f);
    data_0->texture_0.write(float4(color_0, color_0, color_0, 1.0f),index_1);
    return;
}

