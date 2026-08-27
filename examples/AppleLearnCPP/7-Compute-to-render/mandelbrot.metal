#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 5234 "hlsl.meta.slang"
struct ComputeData_default_0
{
    uint2 constant* grid_size_0;
    uint constant* frame_0;
    texture2d<float, access::read_write> texture_0;
};


#line 5234
struct KernelContext_0
{
    ComputeData_default_0 constant* data_0;
};


#line 20 "examples/AppleLearnCPP/7-Compute-to-render/mandelbrot.slang"
[[kernel]] void mandelbrot_set(uint3 index_0 [[thread_position_in_grid]], ComputeData_default_0 constant* data_1 [[buffer(0)]])
{

#line 21
    thread KernelContext_0 kernelContext_0;

#line 21
    (&kernelContext_0)->data_0 = data_1;

#line 21
    uint2 index_1 = index_0.xy;

#line 26
    float zoom_0 = pow(0.62000000476837158f + 0.37999999523162842f * cos(0.00999999977648258f * float(*data_1->frame_0)), 4.0f);

#line 31
    float _S1 = zoom_0 * 2.20000004768371582f * (float(index_1.x) / float((*data_1->grid_size_0).x) + -0.20000000298023224f) + -1.20000004768371582f;
    float _S2 = zoom_0 * 2.0f * (float(index_1.y) / float((*data_1->grid_size_0).y) + -0.34999999403953552f) + -0.31999999284744263f;

#line 32
    float x_0 = 0.0f;

#line 32
    float y_0 = 0.0f;

#line 32
    uint iteration_0 = 0U;

#line 39
    for(;;)
    {

#line 39
        float _S3 = x_0 * x_0;

#line 39
        float _S4 = y_0 * y_0;

#line 39
        bool _S5;

#line 39
        if((_S3 + _S4) <= 4.0f)
        {

#line 39
            _S5 = iteration_0 < 1000U;

#line 39
        }
        else
        {

#line 39
            _S5 = false;

#line 39
        }

#line 39
        if(_S5)
        {
        }
        else
        {

#line 39
            break;
        }
        float _S6 = 2.0f * x_0 * y_0 + _S2;

        uint iteration_1 = iteration_0 + 1U;

#line 43
        x_0 = _S3 - _S4 + _S1;

#line 43
        y_0 = _S6;

#line 43
        iteration_0 = iteration_1;

#line 39
    }

#line 46
    half color_0 = half(0.5f + 0.5f * cos(3.0f + float(iteration_0) * 0.15000000596046448f));
    (&kernelContext_0)->data_0->texture_0.write(float4(half4(color_0, color_0, color_0, 1.0h)),index_1);
    return;
}

