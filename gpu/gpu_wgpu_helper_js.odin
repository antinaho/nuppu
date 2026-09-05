#+build js
package nuppu_gpu

import "vendor:wgpu"

when GPU_BACKEND == GPU_BACKEND_WGPU {
    _get_wgpu_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
        return wgpu.InstanceCreateSurface(
            instance,
            &wgpu.SurfaceDescriptor{
                nextInChain = &wgpu.SurfaceSourceCanvasHTMLSelector{
                    sType = .SurfaceSourceCanvasHTMLSelector,
                    selector = "#wgpu-canvas",
                },
            },
        )
    }
}

