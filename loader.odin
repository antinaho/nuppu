package nuppu

import "core:fmt"
import "core:image"
import "core:image/png"
import "core:os"

png_init :: proc(path: string, options: image.Options = {}) -> ^image.Image {
    data, read_err := os.read_entire_file(path, context.temp_allocator)
    if read_err != nil {
        panic(fmt.tprintf("loader.odin: load_png: Failed to load file: %v", read_err))
    }

    img, err := image.load_from_bytes(data, options, context.temp_allocator)
    if err != nil {
        panic(fmt.tprintf("loader.odin: load_png: Failed to load image: %v", err))
    }
    
    return img
}

png_deinit :: proc(img: ^image.Image) {
    image.destroy(img, context.temp_allocator)
}
