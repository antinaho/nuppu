#include <metal_stdlib>
#include <metal_math>
#include <metal_texture>
using namespace metal;

#line 5234 "hlsl.meta.slang"
struct ComputeData_default_0
{
    uint2 constant* grid_size_0;
    texture2d<float, access::read_write> texture_0;
};


#line 5234
struct KernelContext_0
{
    ComputeData_default_0 constant* data_0;
};


#line 10 "examples/AppleLearnCPP/6-Compute/mandelbrot.slang"
[[kernel]] void mandelbrot_set(uint3 index_0 [[thread_position_in_grid]], ComputeData_default_0 constant* data_1 [[buffer(0)]])
{

#line 11
    thread KernelContext_0 kernelContext_0;

#line 11
    (&kernelContext_0)->data_0 = data_1;

#line 11
    uint2 index_1 = index_0.xy;



    float _S1 = 2.0f * float(index_1.x) / float((*data_1->grid_size_0).x) - 1.5f;
    float _S2 = 2.0f * float(index_1.y) / float((*data_1->grid_size_0).y) - 1.0f;

#line 16
    float x_0 = 0.0f;

#line 16
    float y_0 = 0.0f;

#line 16
    uint iteration_0 = 0U;

#line 23
    for(;;)
    {

#line 23
        float _S3 = x_0 * x_0;

#line 23
        float _S4 = y_0 * y_0;

#line 23
        bool _S5;

#line 23
        if((_S3 + _S4) <= 4.0f)
        {

#line 23
            _S5 = iteration_0 < 1000U;

#line 23
        }
        else
        {

#line 23
            _S5 = false;

#line 23
        }

#line 23
        if(_S5)
        {
        }
        else
        {

#line 23
            break;
        }
        float _S6 = 2.0f * x_0 * y_0 + _S2;

        uint iteration_1 = iteration_0 + 1U;

#line 27
        x_0 = _S3 - _S4 + _S1;

#line 27
        y_0 = _S6;

#line 27
        iteration_0 = iteration_1;

#line 23
    }

#line 30
    half color_0 = half(0.5f + 0.5f * cos(3.0f + float(iteration_0) * 0.15000000596046448f));
    (&kernelContext_0)->data_0->texture_0.write(float4(half4(color_0, color_0, color_0, 1.0h)),index_1);
    return;
}

