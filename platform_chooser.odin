package nuppu

// Chooses what platform API to use based of the operating system.

when ODIN_OS == .Darwin {
    PLATFORM_API :: GLFW_PLATFORM_API
} else when ODIN_OS == .JS {
    PLATFORM_API :: WEB_PLATFORM_API
} else {
    #panic("Platform not supported")
}