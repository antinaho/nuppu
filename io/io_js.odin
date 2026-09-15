#+build js
#+vet unused shadowing using-param style semicolon cast explicit-allocators
package nuppu_io

import "base:runtime"
import "core:log"

foreign import io_env "io_env"

@(default_calling_convention="contextless")
foreign io_env {
    _file_size :: proc(path: string) -> i32 ---                            // -1 if missing
    _file_read :: proc(path: string, dst: rawptr, len: i32) -> i32 ---     // bytes copied
}

read_entire_file :: proc(path: string, allocator: runtime.Allocator) -> ([]u8, bool) {
    size := _file_size(path)
    if size < 0 { log.errorf("Failed reading file %v", path); return {}, false }
    buf := make([]u8, int(size), allocator)
    if _file_read(path, raw_data(buf), size) != size {
        delete(buf, allocator)
        log.errorf("Short read for file %v", path)
        return {}, false
    }
    return buf, true
}
