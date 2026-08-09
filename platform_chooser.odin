package nuppu

// Chooses what platform API to use based of the operating system.

when ODIN_OS == .Darwin {
    PLATFORM_API :: GLFW_PLATFORM_API
} else {
    #panic("Platform not supported")
    // PLATFORM_API :: DUMMY_PLATFORM_API
}