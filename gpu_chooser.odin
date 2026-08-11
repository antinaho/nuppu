package nuppu

when ODIN_OS == .Darwin {
    RENDERER_API :: MTL_RENDERER_API
} else {
    #panic("GPU not supported")
}