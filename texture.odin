package nuppu

import "base:runtime"
import "core:mem"
import "gpu"

Texture :: gpu.Texture
Texture_Descriptor :: gpu.Texture_Descriptor

TEXTURE_HANDLE_RAW :: u16
Texture_Handle :: distinct Handle(TEXTURE_HANDLE_RAW)
Texture_Handle_Nil :: Texture_Handle{}
TEXTURE_INDEX_MASK :: (1 << 16) - 1
#assert(MAX_TEXTURES <= TEXTURE_INDEX_MASK, "MAX_TEXTURES must fit a u16 handle")

Built_in_texture :: enum u32 {
    Depth,
    Swapchain,
}

Texture_Library :: struct {
    built_in_textures: [Built_in_texture]Texture_Handle,

    table: Resource_Table(Texture),

    __texture_handles: [dynamic]Texture_Handle, // debug-only metadata
}

texture_handle_unpack :: proc "contextless" (handle: Texture_Handle) -> (idx: TEXTURE_HANDLE_RAW, ok: bool) #optional_ok {
    idx = handle.handle
    if idx == 0 || int(idx) >= MAX_TEXTURES { return 0, false }
    return idx, true
}

NUPPU_texture_library_init :: proc(lib: ^Texture_Library, allocator := context.allocator) -> (err: runtime.Allocator_Error) {
    err = resource_table_init(&lib.table, MAX_TEXTURES, allocator)
    if err != nil { return }
    lib.built_in_textures = {}

    when ODIN_DEBUG {
        lib.__texture_handles = make([dynamic]Texture_Handle, 0, 64, context.allocator)
    }

    return
}

NUPPU_texture_library_deinit :: proc(lib: ^Texture_Library) {
    // Release every owned texture. The swapchain is backend-owned, and slot 0 is
    // the nil sentinel.
    swapchain := lib.built_in_textures[.Swapchain]
    it := bit_mask_array_iterator_init(&lib.table.occupied)
    for index in bit_mask_array_iterator_next(&it) {
        if index == 0 { continue }
        handle := Texture_Handle { handle = u16(index) }
        if handle == swapchain { continue }
        gpu.release_texture(&lib.table.items[index])
    }

    resource_table_destroy(&lib.table)

    when ODIN_DEBUG {
        delete(lib.__texture_handles)
    }
    lib^ = {}
}



// Releases a user texture. Built-in depth/swapchain are engine-owned and ignored.
texture_free :: proc(handle: Texture_Handle) {
    lib := &_state.texture_library
    if handle == lib.built_in_textures[.Depth] || handle == lib.built_in_textures[.Swapchain] {
        return
    }
    _texture_remove(handle)
}

_texture_remove :: proc(handle: Texture_Handle) {
    lib := &_state.texture_library
    index, ok := texture_handle_unpack(handle)
    if !ok { return }

    gpu.release_texture(&lib.table.items[index])
    resource_table_release(&lib.table, index)

    when ODIN_DEBUG {
        for h, i in lib.__texture_handles {
            if h == handle {
                unordered_remove(&lib.__texture_handles, i)
                break
            }
        }
    }
}

// ---------------------------------------------------------------------------
// GPU texture uploads
//
// `texture_upload_scope` opens a staging arena; `texture_upload` copies CPU
// data into it and records a region; `texture_upload_scope_end` replays every
// region as a buffer->texture GPU copy. Works for shared and private targets.
// 3D textures are not supported yet.
// ---------------------------------------------------------------------------

Texture_Upload_Range :: struct {
    start:  uint,
    length: uint,
}

Texture_Upload_Entry :: struct {
    range:           Texture_Upload_Range,
    target:          Texture_Handle,
    origin:          [3]uint,
    size:            [3]uint,
    level:           uint,
    bytes_per_row:   uint,
    bytes_per_image: uint,
}

Texture_Upload_Scope :: struct {
    arena:   gpu.Arena,
    uploads: [dynamic]Texture_Upload_Entry,
    active:  bool,
}

// Rows must start on a 256-byte boundary inside the staging buffer for the GPU
// buffer->texture copy (Metal requires this for `sourceBytesPerRow`).
TEXTURE_UPLOAD_ROW_ALIGNMENT :: 256

_texture_upload_row_pitch :: proc(tight_row: uint) -> uint {
    if tight_row == 0 { return 0 }
    return (uint(tight_row) + TEXTURE_UPLOAD_ROW_ALIGNMENT - 1) & ~uint(TEXTURE_UPLOAD_ROW_ALIGNMENT - 1)
}

// Staging bytes required for one tightly packed image of this size/format.
texture_upload_image_bytes :: proc(width, height: uint, format: gpu.Pixel_Format) -> uint {
    return _texture_upload_row_pitch(width * gpu.pixel_format_bytes(format)) * height
}

// Staging bytes required for a full mip chain from these base dimensions.
texture_upload_chain_bytes :: proc(width, height: uint, format: gpu.Pixel_Format, mip_levels: uint) -> (total: uint) {
    for level in 0 ..< max(mip_levels, 1) {
        w := max(1, width >> level)
        h := max(1, height >> level)
        total += _texture_upload_row_pitch(w * gpu.pixel_format_bytes(format)) * h
    }
    return total
}

// Area-average `src` (src_w x src_h) down into `dst` (dst_w x dst_h). Each
// destination texel averages the source texels it covers, so odd and
// non-power-of-two sizes keep their edge data.
_texture_upload_downsample :: proc(
    dst: rawptr, dst_w, dst_h, dst_pitch: uint,
    src: rawptr, src_w, src_h, src_pitch: uint,
    format: gpu.Pixel_Format,
) {
    switch format {
    case .BGRA8Unorm, .RGBA8Unorm:
        for y in 0 ..< dst_h {
            sy0 := (y * src_h) / dst_h
            sy1 := min(((y + 1) * src_h + dst_h - 1) / dst_h, src_h)
            for x in 0 ..< dst_w {
                sx0 := (x * src_w) / dst_w
                sx1 := min(((x + 1) * src_w + dst_w - 1) / dst_w, src_w)

                acc: [4]u32
                count: u32
                for sy in sy0 ..< sy1 {
                    for sx in sx0 ..< sx1 {
                        p := ([^]u8)(uintptr(src) + uintptr(sy) * uintptr(src_pitch) + uintptr(sx) * 4)
                        acc[0] += u32(p[0])
                        acc[1] += u32(p[1])
                        acc[2] += u32(p[2])
                        acc[3] += u32(p[3])
                        count += 1
                    }
                }

                d := ([^]u8)(uintptr(dst) + uintptr(y) * uintptr(dst_pitch) + uintptr(x) * 4)
                d[0] = u8(acc[0] / count)
                d[1] = u8(acc[1] / count)
                d[2] = u8(acc[2] / count)
                d[3] = u8(acc[3] / count)
            }
        }

    case .RGBA32Float:
        for y in 0 ..< dst_h {
            sy0 := (y * src_h) / dst_h
            sy1 := min(((y + 1) * src_h + dst_h - 1) / dst_h, src_h)
            for x in 0 ..< dst_w {
                sx0 := (x * src_w) / dst_w
                sx1 := min(((x + 1) * src_w + dst_w - 1) / dst_w, src_w)

                acc: [4]f32
                count: f32
                for sy in sy0 ..< sy1 {
                    for sx in sx0 ..< sx1 {
                        p := ([^]f32)(uintptr(src) + uintptr(sy) * uintptr(src_pitch) + uintptr(sx) * 16)
                        acc[0] += p[0]
                        acc[1] += p[1]
                        acc[2] += p[2]
                        acc[3] += p[3]
                        count += 1
                    }
                }

                d := ([^]f32)(uintptr(dst) + uintptr(y) * uintptr(dst_pitch) + uintptr(x) * 16)
                d[0] = acc[0] / count
                d[1] = acc[1] / count
                d[2] = acc[2] / count
                d[3] = acc[3] / count
            }
        }

    case .None, .Depth32Float:
        unreachable()
    }
}

@(require_results)
texture_upload_scope :: proc(bytes: uint, loc := #caller_location) -> Texture_Upload_Scope {
    assert(bytes > 0, "texture_upload_scope: bytes must be > 0")

    arena, ok := gpu.arena_init(bytes, TEXTURE_UPLOAD_ROW_ALIGNMENT, .Staging, loc)
    assert(ok, "texture_upload_scope: failed to allocate staging arena")

    return Texture_Upload_Scope {
        arena  = arena,
        active = true,
    }
}

texture_upload :: proc(
    scope: ^Texture_Upload_Scope,
    target: Texture_Handle,
    pixel_format: gpu.Pixel_Format,
    data: rawptr,
    layer : uint = 0,
    loc := #caller_location,
) {
    assert(scope.active, "texture_upload: scope is not active")
    assert(data != nil, "texture_upload: data is nil")

    texture, ok := get_texture(target)
    assert(ok, "texture_upload: invalid texture handle")
    assert(texture.concrete.view != ._3D, "texture_upload: 3D uploads are not supported yet")
    assert(texture.concrete.samples == 1, "texture_upload: multisampled textures cannot be uploaded")
    assert(texture.concrete.format == pixel_format, "texture_upload: pixel_format does not match the target texture")

    mip_levels := texture.concrete.mip_levels

    switch pixel_format {
    case .BGRA8Unorm, .RGBA8Unorm, .RGBA32Float:
        // Supported for box-filtered mip generation.
    case .Depth32Float:
        assert(false, "texture_upload: depth textures cannot be uploaded")
    case .None:
        assert(false, "texture_upload: invalid pixel format")
    }

    width  := texture.concrete.size.x
    height := texture.concrete.size.y

    layer_count := texture.concrete.layers
    if texture.concrete.view == .Cube || texture.concrete.view == .Cube_Array {
        layer_count *= 6
    }
    assert(layer < layer_count, "texture_upload: layer out of range")

    needed := texture_upload_chain_bytes(width, height, pixel_format, mip_levels)
    assert(
        scope.arena.offset + uint(needed) <= uint(scope.arena.ptr.total_capacity_bytes),
        "texture_upload: staging scope too small; size it with texture_upload_chain_bytes",
    )

    prev_cpu:   rawptr
    prev_w:     uint
    prev_h:     uint
    prev_pitch: uint

    for level in 0 ..< mip_levels {
        w := max(1, width >> level)
        h := max(1, height >> level)
        tight_row := w * gpu.pixel_format_bytes(pixel_format)

        bytes_per_row   := _texture_upload_row_pitch(tight_row)
        bytes_per_image := bytes_per_row * h

        image := gpu.arena_alloc(&scope.arena, u8, bytes_per_image, loc)
        assert(image.cpu != nil, "texture_upload: staging allocation failed")

        if level == 0 {
            for y in 0 ..< uint(h) {
                dst := rawptr(uintptr(image.cpu) + uintptr(y) * uintptr(bytes_per_row))
                src := rawptr(uintptr(data) + uintptr(y) * uintptr(tight_row))
                mem.copy_non_overlapping(dst, src, int(tight_row))
            }
        } else {
            _texture_upload_downsample(
                image.cpu, w, h, bytes_per_row,
                prev_cpu, prev_w, prev_h, prev_pitch,
                pixel_format,
            )
        }

        append(&scope.uploads, Texture_Upload_Entry {
            range           = { start = image.byte_offset, length = image.total_capacity_bytes },
            target          = target,
            origin          = { 0, 0, layer },
            size            = { w, h, 1 },
            level           = level,
            bytes_per_row   = bytes_per_row,
            bytes_per_image = bytes_per_image,
        })

        prev_cpu   = image.cpu
        prev_w     = w
        prev_h     = h
        prev_pitch = bytes_per_row
    }
}

texture_upload_scope_end :: proc(scope: ^Texture_Upload_Scope) {
    if !scope.active { return }
    scope.active = false

    gpu.begin_commands()
    for entry in scope.uploads {
        texture, ok := get_texture(entry.target)
        assert(ok, "texture_upload_scope_end: invalid texture handle")
        assert(texture.concrete.view != ._3D, "texture_upload_scope_end: 3D uploads are not supported yet")

        src := gpu.sub_alloc(scope.arena.ptr, entry.range.start, entry.range.length)
        gpu.copy_buffer_to_texture(
            src, texture,
            entry.origin, entry.size, entry.level,
            entry.bytes_per_row, entry.bytes_per_image,
        )
    }
    gpu.transfer_submit(&scope.arena.ptr)
    delete(scope.uploads)
    scope.uploads = nil
}

// Single texture creation entry point. `data`, when provided, is uploaded to
// slice 0 / mip 0 immediately. Most callers should use the per-type helpers
// (`texture_1D`/`texture_2D`/`texture_2D_array`/`texture_3D`/`texture_cube`/
// `texture_cube_array`) below, which build the descriptor for you; construct a
// descriptor directly only for something those don't cover.
texture_init :: proc(
    descriptor: Texture_Descriptor,
    data: rawptr = nil,
    name: string = "",
    access: gpu.Texture_Access = .Write,
    loc: = #caller_location,
) -> Texture_Handle {
    texture := gpu.texture_init(descriptor, access)

    handle := _register_tex_handle(texture, name, loc)

    if data != nil {
        bytes := texture_upload_chain_bytes(
            texture.concrete.size.x,
            texture.concrete.size.y,
            descriptor.format,
            texture.concrete.mip_levels,
        )
        scope := texture_upload_scope(bytes)
        texture_upload(&scope, handle, descriptor.format, data)
        texture_upload_scope_end(&scope)
    }

    return handle
}

_register_tex_handle :: proc(texture: Texture, name: string = "", loc := #caller_location) -> Texture_Handle {
    index, ok := resource_table_acquire(&_state.texture_library.table)
    assert(ok, "texture_init: out of texture slots, raise MAX_TEXTURES")

    _state.texture_library.table.items[index] = texture
    handle := Texture_Handle { handle = u16(index) }
    when ODIN_DEBUG {
        handle.metadata = Metadata {
            created_at       = loc,
            created_on_frame = _state.frame_n,
            name             = name,
        }
        append(&_state.texture_library.__texture_handles, handle)
    }
    return handle
}


// Convenience creators. Each builds the descriptor for its texture type and
// forwards to `texture_init`. `sample_count`/`mip_levels` use 0 == 1.

texture_1D :: proc(
    width: uint,
    format: gpu.Pixel_Format,
    usage: gpu.Texture_Usage_1D,
    data: rawptr = nil,
    name: string = "",
    mip_levels: uint = 0,
    storage: gpu.Storage_Mode = .Shared,
    access: gpu.Texture_Access = .Write,
    loc: = #caller_location,
) -> Texture_Handle {
    descriptor := Texture_Descriptor {
        type = gpu.Texture_Type_1D {
            width = width,
            usage = usage,
        },
        format     = format,
        mip_levels = mip_levels,
        storage    = storage,
    }
    return texture_init(descriptor, data, name, access, loc)
}

texture_2D :: proc(
    dimensions: [2]uint,
    format: gpu.Pixel_Format,
    usage: gpu.Texture_Usage_2D,
    data: rawptr = nil,
    name: string = "",
    sample_count: uint = 0,
    mip_levels: uint = 0,
    storage: gpu.Storage_Mode = .Shared,
    access: gpu.Texture_Access = .Write,
    loc: = #caller_location,
) -> Texture_Handle {
    descriptor := Texture_Descriptor {
        type = gpu.Texture_Type_2D {
            dimensions   = dimensions,
            sample_count = sample_count,
            usage        = usage,
        },
        format     = format,
        mip_levels = mip_levels,
        storage    = storage,
    }
    return texture_init(descriptor, data, name, access, loc)
}

texture_2D_array :: proc(
    dimensions: [2]uint,
    array_length: uint,
    format: gpu.Pixel_Format,
    usage: gpu.Texture_Usage_2D,
    data: rawptr = nil,
    name: string = "",
    mip_levels: uint = 0,
    storage: gpu.Storage_Mode = .Shared,
    access: gpu.Texture_Access = .Write,
    loc: = #caller_location,
) -> Texture_Handle {
    descriptor := Texture_Descriptor {
        type = gpu.Texture_Type_2D {
            dimensions   = dimensions,
            array_length = array_length,
            usage        = usage,
        },
        format     = format,
        mip_levels = mip_levels,
        storage    = storage,
    }
    return texture_init(descriptor, data, name, access, loc)
}

texture_3D :: proc(
    dimensions: [3]uint,
    format: gpu.Pixel_Format,
    usage: gpu.Texture_Usage_3D,
    data: rawptr = nil,
    name: string = "",
    mip_levels: uint = 0,
    storage: gpu.Storage_Mode = .Shared,
    access: gpu.Texture_Access = .Write,
    loc: = #caller_location,
) -> Texture_Handle {
    descriptor := Texture_Descriptor {
        type = gpu.Texture_Type_3D {
            dimensions = dimensions,
            usage      = usage,
        },
        format     = format,
        mip_levels = mip_levels,
        storage    = storage,
    }
    return texture_init(descriptor, data, name, access, loc)
}

texture_cube :: proc(
    size: uint,
    format: gpu.Pixel_Format,
    usage: gpu.Texture_Usage_Cube,
    data: rawptr = nil,
    name: string = "",
    mip_levels: uint = 0,
    storage: gpu.Storage_Mode = .Shared,
    access: gpu.Texture_Access = .Write,
    loc: = #caller_location,
) -> Texture_Handle {
    descriptor := Texture_Descriptor {
        type = gpu.Texture_Type_Cube {
            dimensions = {size, size},
            usage      = usage,
        },
        format     = format,
        mip_levels = mip_levels,
        storage    = storage,
    }
    return texture_init(descriptor, data, name, access, loc)
}

texture_cube_array :: proc(
    size: uint,
    cubemap_count: uint,
    format: gpu.Pixel_Format,
    usage: gpu.Texture_Usage_Cube,
    data: rawptr = nil,
    name: string = "",
    mip_levels: uint = 0,
    storage: gpu.Storage_Mode = .Shared,
    access: gpu.Texture_Access = .Write,
    loc: = #caller_location,
) -> Texture_Handle {
    descriptor := Texture_Descriptor {
        type = gpu.Texture_Type_Cube {
            dimensions   = {size, size},
            array_length = cubemap_count,
            usage        = usage,
        },
        format     = format,
        mip_levels = mip_levels,
        storage    = storage,
    }
    return texture_init(descriptor, data, name, access, loc)
}
