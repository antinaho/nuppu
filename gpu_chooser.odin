package nuppu

when ODIN_OS == .Darwin {
    RENDERER_API :: MTL_RENDERER_API
} else when ODIN_OS == .JS {
    RENDERER_API :: WEB_RENDERER_API
} else {
    #panic("GPU not supported")
}